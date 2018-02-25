#!/bin/bash

# Takes in BG calibration as argument #1 and after some boundary checking 
# it puts it in to /root/openaps/monitor/calibration.json
# This way any apps can put a calibration bg record in that 
# file and Logger will pick it up and use it for calibration.

BG=${1:-"null"}
CALIBRATION=${2:-"/root/myopenaps/monitor/calibration.json"}
dateString=$(date +"%Y-%m-%d %H:%M")
epochdate=$(date +'%s')
UUID=$(cat /proc/sys/kernel/random/uuid)
UUID=$(echo "${UUID//-}")




if [ "$BG" == "null" ]; then
  echo "Error - Missing required argument 1 meterBG value"
  echo "Usage: calibrate MeterBG"
  exit
fi

if [ $(bc <<< "$BG > 39") -eq 1 -a $(bc <<< "$BG < 401") -eq 1 ]; then
#  touch $CALIBRATION_FILE
  echo "[{\"_id\":\"$UUID\",\"dateString\":\"${dateString}\",\"date\":${epochdate},\"glucose\":${BG}}]" >  $CALIBRATION
  cat $CALIBRATION
else
  echo "Error - BG of $BG is out of range (40-400) for calibration and cannot be used"
fi


