#!/bin/bash

MESSAGE="/root/myopenaps/monitor/g5-stop.json"
epochdate=$(date +'%s%3N')

echo "[{\"date\":\"${epochdate}\",\"type\":\"StopSensor\"}]" >  $MESSAGE
cat $MESSAGE
