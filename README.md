## bt.sh

`bt.sh` is a simple set of bash functions that can be incorporated into an existing set of shell scripts to provide a timechart-like trace view of different script phases.

Here's an example where `BT_WIDTH` is chosen to fit the output nicely into this README:

```
[simonsj@simonsj-lx2 : bt.sh] BT_WIDTH=50 ./example.sh
Build Trace Start (example.sh:7)

              ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▃▁▁▁▁▁▁▂▇▇▇▇▇███████▆▆▁▁▁▁ * CPU Utilization
[    8.111s ] ├────────────────────────────────────────────────┤ * full example
[    4.036s ] ├──────────────────────┤                           * serial cats
[    2.008s ] ├──────────┤                                       * cat + gzip 1
[    2.008s ]             ├──────────┤                           * cat + gzip 2
[    1.011s ]                          ├────┤                    * sleep 1.0
[    2.023s ]                                ├──────────┤        * parallel cats
[    2.010s ]                                ├──────────┤        * cat + gzip 3
[    2.009s ]                                ├──────────┤        * cat + gzip 4
[    1.012s ]                                            ├─────┤ * final sleep 1.0

     one '.' unit is less than:    0.162s
                    total time:    8.122s

Build Trace End (example.sh:7)
```

Time goes left-to-right, and tracepoints are ordered top-to-bottom chronologically according to when they started.

The cumulative time for a trace is emitted on the far-left column, and the trace's globally unique name is emitted on the far-right column.

CPU usage is sampled with `mpstat` and emitted using [`spark`](https://github.com/holman/spark).

## Motivation

`bt.sh` was originally created to aid reasoning about the numerous highly-parallelized and heavily-cached build and CI test phases used in GitHub's internal development of [GitHub Enterprise](https://enterprise.github.com).

Explicit goals:
 * single-file consumption
 * a small set of trivial, commonly-available Linux dependencies
 * replace "eyeball grepping" build timestamps and manually computing different phase durations
 * verify work intended to be run in parallel is indeed doing so
 * "stats in your face" to help with identifying regressions
 * identify phases which are CPU-bound (and not)

Non-goals:
 * no claims to function on OSX out of the box
 * not suitable for fine-grained perf measurement
   * if `date` overhead would matter in your context, `bt.sh` is not a good fit

## Usage

See [example.sh](https://github.com/simonsj/bt.sh/blob/master/example.sh) for an example script.

In a nutshell:
```sh
#!/bin/bash
. bt.sh                            # source bt.sh
bt_init                            # initialize

bt_start 'some phase of my build'  # start trace
...                                # (your actual script)
bt_end 'some phase of my build'    # end trace

bt_cleanup                         # cleanup once when done
```

The `bt_init` and `bt_cleanup` are okay to be invoked in a nested fashion from multiple scripts: a report will be emitted when the first script to have done `bt_init` finally reaches its `bt_cleanup`.

The `bt_start` and `bt_end` invocations for a given measurement each require their string description argument to match, and to be globally unique.  The description name is used to key into the measurement database: simple files placed into /tmp.  Files for each measurement are organized as:
```
  actual file:  /tmp/bt.<description checksum>.<start timestamp>
  symlink:      /tmp/bt.<description checksum> --> actual file
```
With this scheme, lookup for `bt_end` is constant-time via the symlink, and the stats can be sorted by chronological start time using the actual files' names.

Upon `bt_end`, the final line of the data file looks like:
```
  <end timestamp> <end_caller_source_file:lineno> <description text ...>
```
Where above, the first two columns are stable, and everything from the third word to the end of line is the string description.

### Assumptions
 * today an assumption is `bt.sh` will only ever be used by any single build at a time: it assumes sole control over the `/tmp/bt.*` namespace of files
 * some bash-isms are relied upon: `export -f`, `BASH_SOURCE`, `BASH_LINENO`

## Dependencies

`bt.sh` is expected to work without much effort on a modern Linux.

It depends on these utilities:

 * bash
 * date, yes, seq, cksum (GNU coreutils)
 * mpstat (sysstat package)
 * GNU bc (math package)
 * POSIX: awk, tail, sed, basename, head

## License

See the [LICENSE](https://github.com/simonsj/bt.sh/blob/master/LICENSE.md) file for license rights and limitations (MIT).
