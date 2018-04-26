#!/bin/bash
#{date: Date.now(), type: "StopSensor"}

MESSAGE="/root/myopenaps/monitor/g5-start.json"
epochdate=$(date +'%s')

echo "[{\"date\":\"${epochdate}000\",\"type\":\"StartSensor\"}]" >  $MESSAGE
cat $MESSAGE
