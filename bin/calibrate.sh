#!/bin/bash

# Takes in BG calibration as argument #1 and after some boundary checking 
# it puts it in to /root/openaps/monitor/calibration.json
# This way any apps can put a calibration bg record in that 
# file and Logger will pick it up and use it for calibration.

BG=${1:-"null"}     # arg 1 is meter bg value
UNITS=${2:-"mg/dl"} # arg 2 if "mmol" then bg in mmol
TEST=${3:-""}       # arg 3 if "test" then test mode

CALIBRATION="/root/myopenaps/monitor/calibration.json"
dateString=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
epochdate=$(date +'%s')
UUID=$(cat /proc/sys/kernel/random/uuid)
UUID=$(echo "${UUID//-}")

# temporary while testing
#UUID=""

LOW=40
HIGH=400

# ability to test without causing BG Check treatment to be used
if [ "$TEST" == "test" ]; then
  tmp=$(mktemp)
  CALIBRATION=$(mktemp)
fi

# ability to test without causing BG Check treatment to be used
if [ "$UNITS" == "mmol" ]; then
  LOW=2
  HIGH=22
fi

if [ "$BG" == "null" ]; then
  echo "Error - Missing required argument 1 meterBG value"
  echo "Usage: calibrate MeterBG"
  exit
fi

if [ $(bc <<< "$BG >= $LOW") -eq 1 -a $(bc <<< "$BG <= $HIGH") -eq 1 ]; then
  echo "[{\"_id\":\"${UUID}\",\"dateString\":\"${dateString}\",\"date\":${epochdate},\"glucose\":${BG},\"units\":\"${UNITS}\"}]" >  $CALIBRATION
  echo "calibration treatment posted to $CALIBRATION - record is below"
  cat $CALIBRATION
else
  echo "Error - BG of $BG $UNITS is out of range ($LOW-$HIGH $UNITS) for calibration and cannot be used"
fi


