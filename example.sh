#!/bin/bash
# example.sh: example usage of bt.sh

set -e

. bt.sh
bt_init

example_function () {
  timeout 2.0s cat /dev/zero | gzip > /dev/null || true
}
export -f example_function

bt_start 'full example'

bt_start 'serial cats'
bash -c 'bt_start "cat + gzip 1"; example_function; bt_end "cat + gzip 1"'
bash -c 'bt_start "cat + gzip 2"; example_function; bt_end "cat + gzip 2"'
bt_end 'serial cats'

bt_start 'sleep 1.0'
sleep 1.0
bt_end 'sleep 1.0'

bt_start 'parallel cats'

bash -c 'bt_start "cat + gzip 3"; example_function; bt_end "cat + gzip 3"' &
pcat_pids=$!

bash -c 'bt_start "cat + gzip 4"; example_function; bt_end "cat + gzip 4"' &
pcat_pids="$! $pcat_pids"

wait $pcat_pids 2>/dev/null || true

bt_end 'parallel cats'

bt_start 'final sleep 1.0'
sleep 1.0
bt_end 'final sleep 1.0'

bt_end 'full example'

bt_cleanup
