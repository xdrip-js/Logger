#!/bin/bash
#{date: Date.now(), type: "StopSensor"}

ago=$1

MESSAGE="/root/myopenaps/monitor/g5-start.json"
if [ -n "$ago" ]; then
  if [ "$ago" == "onehour" ]; then
    epochdate=$(date +'%s%3N' -d '1 hour ago')
  elif [ "$ago" == "twohour" ]; then
    epochdate=$(date +'%s%3N' -d '2 hour ago')
  fi
else
  epochdate=$(date +'%s%3N')
fi

echo "[{\"date\":\"${epochdate}\",\"type\":\"StartSensor\"}]" >  $MESSAGE
cat $MESSAGE
