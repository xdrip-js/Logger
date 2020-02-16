#!/bin/bash

common_funcs="/root/src/Logger/bin/logger-common-funcs.sh"
if [ ! -e $common_funcs ]; then
  echo "ERROR: Failed to run logger-common-funcs.sh. Is Logger correctly installed?"
  exit 1
fi
source $common_funcs

# Except for new firmware transmitters, always do 120 minutes ago 
# for sensor stop message. Allows time travel for subsequent start.

version=$(txVersion)
if [ $(newFirmware $version) == "true" ]; then
  # time travel not allowed for new firmware tx versions
  minutesago=0
else
  # always time travel in this case 
  minutesago=120
fi
 
MESSAGE="${HOME}/myopenaps/monitor/xdripjs/cgm-stop.json"

epochdate=$(date +'%s%3N' -d "$minutesago minutes ago")

echo "[{\"date\":\"${epochdate}\",\"type\":\"StopSensor\"}]" >  $MESSAGE
cat $MESSAGE
