#!/bin/bash
# Usage: . bt.sh; bt_init; [ bt_start "foo"; bt_end "foo"; ... ]; bt_cleanup
# Simple timechart-like tracing for bash.

bt_sample_cpu_idle () {
  local sample_interval_s=1
  local sample_count=1
  while [ 1 ]; do
    # mpstat columns differ across versions: here assume last column is '%idle'
    mpstat -u -P ALL $sample_interval_s $sample_count |
      grep -e "^Average" | tail -n +3 | grep -o -e '[0-9\.]*$' |
      tr '\n' ' ' | sed -e 's/  *$/\n/g' >> "$BT_DIR/CPU"
  done
}
export -f bt_sample_cpu_idle

#
# Remember the first file to 'bt_init' as BT_INIT which is honored via
# 'bt_cleanup' to allowed nested usages that emit reports at the right
# times.
#
bt_init () {
  if [ -z "$BT_INIT" ]; then
    export BT_INIT="$(basename ${BASH_SOURCE[1]} 2>/dev/null):${BASH_LINENO[0]}"
    export BT_DIR="$(mktemp -d /tmp/bt-$$-XXXXXXX)"
    export BT_DATE="${BT_DATE:-date}"
    export BT_HEAD="${BT_HEAD:-head}"
    $BT_DATE '+%s%N' > "$BT_DIR/START"

    # only trace CPU if mpstat seems to be available
    touch "$BT_DIR/CPU"
    if [ -z "$BT_DISABLE_CPUSAMPLE" ]; then
      # need both mpstat and bc for this to work
      if type mpstat >/dev/null 2>&1 && type bc >/dev/null 2>&1; then
        bash -c "bt_sample_cpu_idle" &
        export BT_CPUSAMPLE_PID=$!
      fi
    fi
  fi
}

bt_cleanup () {
  local init_file="${BT_INIT%%:*}"
  local caller="$(basename ${BASH_SOURCE[1]} 2>/dev/null):${BASH_LINENO[0]}"
  local caller_file="${caller%%:*}"
  if [ "$init_file" = "$caller_file" ]; then
    if [ -n "$BT_CPUSAMPLE_PID" ]; then
      kill $BT_CPUSAMPLE_PID
      wait $BT_CPUSAMPLE_PID 2>/dev/null || true
    fi
    $BT_DATE '+%s%N' > "$BT_DIR/END"
    if [ -z "$BT_DISABLED" -o "$BT_DISABLED" = "0" ]; then bt_report; fi

    # clean up in the usual case, but make it easy to debug saved stats
    if [ -z "$BT_DEBUG" ]; then
      rm -rf "$BT_DIR" 2>/dev/null
      # Clean up temporary directories at least one day old, also.
      find "$(dirname "$BT_DIR")" -maxdepth 1 -mtime +0 -type d -name 'bt-*' -print0 | xargs -0 rm -rf
    fi
    export BT_INIT=""
  fi
}

#
# Sets 'BT_DISABLED' in the environment such that subsequent tracing will be
# ignored.  Use 'bt_enable' to unset the value and re-enable tracing.  Can
# be used to squelch sub-measurements, if desired.
#
bt_disable () {
  export BT_DISABLED=1
}

bt_enable () {
  export BT_DISABLED=0
}

#
# bt_start "description for a part of the build"
#
# Creates "$BT_DIR/<description checksum>.<start timestamp>" and a symlink to
# it named "$BT_DIR/<description checksum>".  The former enables easily sorting
# results by start time, and the latter enables easily recording the end time
# for a given measurement.
#
# Requires a balanced bt_end with matching description text.
#
bt_start () {
  if [ -z "$BT_DISABLED" -o "$BT_DISABLED" = "0" ]; then
    local caller="$(basename ${BASH_SOURCE[1]} 2>/dev/null):${BASH_LINENO[0]}"
    local desc_checksum=$(echo "$@" | cksum | awk '{print $1}')
    local timestamp=$($BT_DATE '+%s%N')
    echo "$caller $@" > "$BT_DIR/$desc_checksum.$timestamp"
    ln -s "$BT_DIR/$desc_checksum.$timestamp" "$BT_DIR/$desc_checksum" || {
      echo "FAIL: entry already exists for '$@' ($desc_checksum)"
      exit 1
    }
  fi
}
export -f bt_start

bt_start_log () {
  bt_start "$@"
  echo "*** $@ START"
}

bt_end () {
  if [ -z "$BT_DISABLED" -o "$BT_DISABLED" = "0" ]; then
    local caller="$(basename ${BASH_SOURCE[1]} 2>/dev/null):${BASH_LINENO[0]}"
    local desc_checksum=$(echo "$@" | cksum | awk '{print $1}')
    echo "$($BT_DATE '+%s%N') $caller $1" >> "$BT_DIR/$desc_checksum"
  fi
}
export -f bt_end

bt_end_log () {
  bt_end "$@"
  echo "*** $@ END"
}

# spark
# https://github.com/holman/spark
# $1 - The data we'd like to graph.
_echo () {
  if [ "X$1" = "X-n" ]; then
    shift
    printf "%s" "$*"
  else
    printf "%s\n" "$*"
  fi
}

spark () {
  local n numbers=

  # find min/max values
  local min=0xffffffff max=0

  for n in ${@//,/ }
  do
    # on Linux (or with bash4) we could use `printf %.0f $n` here to
    # round the number but that doesn't work on OS X (bash3) nor does
    # `awk '{printf "%.0f",$1}' <<< $n` work, so just cut it off
    n=${n%.*}
    if [ -z "$n" ]; then n=0; fi
    (( n < min )) && min=$n
    (( n > max )) && max=$n
    numbers=$numbers${numbers:+ }$n
  done

  if [ -z "$min" ]; then
    >&2 echo "warning: min became empty"
    >&2 echo "warning: input   '$@'"
    >&2 echo "warning: numbers '$numbers'"
    min=0
  fi

  # print ticks
  local ticks=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

  # use a high tick if data is constant
  (( min == max )) && ticks=(▅ ▆)

  local f=$(( (($max-$min)<<8)/(${#ticks[@]}-1) ))
  (( f < 1 )) && f=1

  for n in $numbers
  do
    _echo -n ${ticks[$(( ((($n-$min)<<8)/$f) ))]}
  done
  _echo
}

bt_compute_cpu_sparkline () {
  # CPU usage sparkline
  local base_path="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
  local num_procs=$(cat /proc/cpuinfo | grep -c -e "processor")
  local samples_per_column=$(($(wc -l "$BT_DIR/CPU" | cut -f1 -d' ') / $width))
  local nonidle_values=""
  if [ "$samples_per_column" -gt 0 ]; then
    for n in $(seq $width); do
      local samples=$(tail -n +$(($n * $samples_per_column)) "$BT_DIR/CPU" | $BT_HEAD -n $samples_per_column)
      local sum=$(echo "$samples" | tr ' ' '\n' | awk '{s+=$1} END {print s}')
      local avg=$(echo "$sum / $samples_per_column" | bc -l)
      local value=$(echo "($num_procs * 100.0) - $avg" | bc -l)
      nonidle_values="$nonidle_values $value"
    done
  else
    num_samples=$(wc -l "$BT_DIR/CPU" | cut -f1 -d' ')
    for c in $(seq $width); do
      local n=$((($c * $num_samples) / $width))
      local sample=$(tail -n +$n "$BT_DIR/CPU" | $BT_HEAD -n 1)
      local sum=$(echo "$sample" | tr ' ' '\n' | awk '{s+=$1} END {print s}')
      local avg=$(echo "$sum / $num_procs" | bc -l)
      local value=$(echo "($num_procs * 100.0) - $avg" | bc -l)
      nonidle_values="$nonidle_values $value"
    done
  fi
  bt_sparkline=$(printf "%${width}s" $(spark "$nonidle_values")) || {
    >&2 echo "spark failed, nonidle_values: '$nonidle_values'"
  }
}

#
# Called automatically upon bt_cleanup.
#
bt_report () {
  # subshell used in case caller has 'set -x', which thwarts our ascii beauty
  (
  set -e
  set +x
  if [ -n "$BT_DEBUG" ]; then
    set -x
  fi

  local total_start_ms=$(($(cat "$BT_DIR/START") / 1000000))
  local total_end_ms=$(($(cat "$BT_DIR/END") / 1000000))
  local total_time_ms=$(($total_end_ms - $total_start_ms))
  local total_time_s=$(($total_time_ms / 1000))
  local total_time_s_remainder=$(($total_time_ms % 1000))
  local total_time_s_fmt=$(printf "%s.%03d" "$total_time_s" "$total_time_s_remainder")
  local width=${BT_WIDTH-80}
  local unit_ms=$(($total_time_ms / $width))
  local unit_s=$(($unit_ms / 1000))
  local unit_s_remainder=$(($unit_ms % 1000))
  local unit_s_fmt=$(printf "%s.%03d" "$unit_s" "$unit_s_remainder")

  if [ "$unit_ms" -eq 0 ]; then return; fi

  printf "Build Trace Start ($BT_INIT)\n\n"

  if [ -n "$BT_CPUSAMPLE_PID" ]; then
    bt_compute_cpu_sparkline
    printf "%14s%s * CPU Utilization\n" " " "$bt_sparkline"
  fi

  # measurements sorted chronologically by start time
  for m in $(ls -1 "$BT_DIR"/*.* | sort -t '.' -k2,2 -n); do
    local m_failed=0
    local m_desc=$($BT_HEAD -n1 $m | cut -d ' ' -f 2-)
    local m_start_ms=$((${m##*.} / 1000000))
    local m_end_ms="$total_end_ms"
    if [ -s "$m" -a $(wc -l $m | awk '{print $1}') -eq 2 ]; then
      m_end_ms=$(($(tail -n +2 $m | awk '{print $1}') / 1000000))
    else
      m_desc="$m_desc (tracepoint end failed)"
      m_failed=1
    fi
    local m_time_ms=$((m_end_ms - $m_start_ms))
    local m_time_s=$(($m_time_ms / 1000))
    local m_time_s_remainder=$(($m_time_ms % 1000))
    local m_time_s_fmt=$(printf "%s.%03d" "$m_time_s" "$m_time_s_remainder")

    local m_start_col=$((($m_start_ms - $total_start_ms) / $unit_ms))
    if [ "$m_start_col" -ge "$width" ]; then
      m_start_col="$((width - 1))"
    fi

    local m_num_units=$(($m_time_ms / $unit_ms))
    if [ "$m_num_units" -eq 0 ]; then
      m_num_units=1
    elif [ "$(($m_num_units + $m_start_col))" -gt "$(($width - 2))" ]; then
      m_num_units="$(($width - $m_start_col))"
    fi

    local m_num_end_units=0
    if [ "$(($m_start_col + $m_num_units))" -lt "$width" ]; then
      m_num_end_units=$(($width - ($m_start_col + $m_num_units)))
    fi

    local m_bar_start="├"
    local m_bar="─"
    local m_bar_end="┤"
    local m_num_middle_units=1
    if [ "$m_num_units" -lt 2 ]; then
      m_bar_start=""
      m_bar_end=""
      m_bar="."
    else
      m_num_middle_units=$(($m_num_units - 2))
    fi

    # omit small measurements by default
    if [ -z "$BT_SMALLSTATS" -a "$m_bar" = "." ]; then
      continue
    fi

    if [ "$m_failed" -eq 1 ]; then
      m_bar_start="˟"
      m_bar="˟"
      m_bar_end="˟"
    fi

    printf "[ %8ss ] %s%s%s%s%s * %s\n" \
     "$m_time_s_fmt" \
     "$(yes ' ' 2> /dev/null | $BT_HEAD -n $m_start_col | tr -d '\n')" \
     "$m_bar_start" \
     "$(yes "$m_bar" 2> /dev/null | $BT_HEAD -n $m_num_middle_units | tr -d '\n')" \
     "$m_bar_end" \
     "$(yes ' ' 2> /dev/null | $BT_HEAD -n $m_num_end_units | tr -d '\n')" \
     "$m_desc"
  done

  printf "\n"
  printf "%30s: %8ss\n" "one '.' unit is less than" "$unit_s_fmt"
  printf "%30s: %8ss\n" "total time" "$total_time_s_fmt"
  printf "\nBuild Trace End ($BT_INIT)\n"
  )
}
