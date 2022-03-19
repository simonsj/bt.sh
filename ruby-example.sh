#!/bin/bash
# ruby-example.sh: example usage of bt.sh with Ruby stub

set -e

. bt.sh
bt_init

bt_start "running some ruby"

ruby -r ./bt.rb -e 'BT.time("hey") { sleep(0.25); BT.time("there") { sleep(0.1) } }'

bt_end "running some ruby"

bt_cleanup
