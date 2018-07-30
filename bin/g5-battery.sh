#!/bin/bash

# optional parameter $1 to specify "refresh" then it queues a Battery refresh ctl message to tx
refresh=$1

file="${HOME}/myopenaps/monitor/xdripjs/cgm-battery.json"
if [ -n "$refresh" ]; then
  echo "Queueing Battery Status Refresh message for next Tx transmission (5 to 10 minutes)"
  touch -d "13 hours ago" $file
else
  cat $file
  echo
fi
