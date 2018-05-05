#!/bin/bash
# optional parameter $1 to specify how many hours ago for sensor insert/start
hoursago=$1
MESSAGE="${HOME}/myopenaps/monitor/logger/g5-stop.json"

if [ -n "$hoursago" ]; then
  epochdate=$(date +'%s%3N' -d "$hoursago hour ago")
else
  epochdate=$(date +'%s%3N')
fi

echo "[{\"date\":\"${epochdate}\",\"type\":\"StopSensor\"}]" >  $MESSAGE
cat $MESSAGE
