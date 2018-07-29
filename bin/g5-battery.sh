#!/bin/bash

# optional parameter $1 to specify how many hours ago for sensor insert/start
refresh=$1

file="${HOME}/myopenaps/monitor/xdripjs/cgm-battery.json"
if [ -n "$refresh" ]; then
  echo "Queueing Battery Status Refresh message for next Tx transmission (5 to 10 minutes)"
  touch -d "13 hours ago" $file
else
  cat $file
  echo
fi
