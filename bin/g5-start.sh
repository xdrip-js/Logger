#!/bin/bash

# optional parameter $1 to specify how many minutes ago for sensor insert/start
minutesago=$1

MESSAGE="${HOME}/myopenaps/monitor/xdripjs/g5-start.json"
if [ -n "$minutesago" ]; then
  epochdate=$(date +'%s%3N' -d "$minutesago minutes ago")
else
  epochdate=$(date +'%s%3N')
fi

echo "[{\"date\":\"${epochdate}\",\"type\":\"StartSensor\"}]" >  $MESSAGE
cat $MESSAGE
