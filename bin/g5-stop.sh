#!/bin/bash
# always do 120 minutes ago for sensor stop message. Allows time travel for subsequent start.
minutesago=120
MESSAGE="${HOME}/myopenaps/monitor/xdripjs/cgm-stop.json"

if [ -n "$minutesago" ]; then
  epochdate=$(date +'%s%3N' -d "$minutesago minutes ago")
else
  epochdate=$(date +'%s%3N')
fi

echo "[{\"date\":\"${epochdate}\",\"type\":\"StopSensor\"}]" >  $MESSAGE
cat $MESSAGE
