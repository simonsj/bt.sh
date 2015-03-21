#!/bin/bash
# example.sh: example usage of bt.sh

set -e

. bt.sh
bt_init

example_function () {
  timeout 1.0s cat /dev/zero > /dev/null || true
}
export -f example_function

bt_start "full example"

bt_start "serial cats"
bash -c "bt_start 'cat1'; example_function; bt_end 'cat1'"
bash -c "bt_start 'cat2'; example_function; bt_end 'cat2'"
bt_end "serial cats"

bt_start "sleep 0.25"
sleep 0.5
bt_end "sleep 0.25"

bt_start "parallel cats"
bash -c "bt_start 'cat3'; example_function; bt_end 'cat3'" &
bash -c "bt_start 'cat4'; example_function; bt_end 'cat4'" &
wait 2>/dev/null || true
bt_end "parallel cats"

bt_end "full example"

bt_cleanup
