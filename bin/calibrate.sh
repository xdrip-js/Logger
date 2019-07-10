#!/bin/bash

# Takes in BG calibration as argument #1 and after some boundary checking 
# it puts it in to ~/openaps/monitor/xdripjs/calibration.json
# This way any apps can put a calibration bg record in that 
# file and Logger will pick it up and use it for calibration.

BG=${1:-"null"}     # arg 1 is meter bg value
UNITS=${2:-"mg/dl"} # arg 2 if "mmol" then bg in mmol
TEST=${3:-""}       # arg 3 if "test" then test mode

calibrationFile="${HOME}/myopenaps/monitor/xdripjs/calibration.json"
stagingFile1=$(mktemp)
stagingFile2=$(mktemp)
dateString=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
epochdate=$(date +'%s%3N')
UUID=$(cat /proc/sys/kernel/random/uuid)
UUID=$(echo "${UUID//-}")

LOW=40
HIGH=400

# ability to test without causing BG Check treatment to be used
if [ "$TEST" == "test" ]; then
  tmp=$(mktemp)
  calibrationFile=$(mktemp)
fi

if [ "$UNITS" == "mmol" ]; then
  BG=$(bc <<< "($meterbg *18)/1")
  echo "converted OpenAPS meterbg from mmol value to $meterbg"
fi

if [ "$BG" == "null" ]; then
  echo "Error - Missing required argument 1 meterBG value"
  echo "Usage: calibrate MeterBG"
  exit
fi

if [ $(bc <<< "$BG >= $LOW") -eq 1 -a $(bc <<< "$BG <= $HIGH") -eq 1 ]; then
  echo "[{\"_id\":\"${UUID}\",\"dateString\":\"${dateString}\",\"date\":${epochdate},\"glucose\":${BG}}\"}]" >  $stagingFile2
  if [ -e $calibrationFile ]; then
    cp $calibrationFile $stagingFile1
    jq -s add $stagingFile1 $stagingFile2 > $calibrationFile
  else
    cp $stagingFile2 $calibrationFile
  fi
  echo "calibration treatment posted to $calibrationFile - record is below"
  cat $calibrationFile
else
  echo "Error - BG of $BG $UNITS is out of range ($LOW-$HIGH $UNITS) for calibration and cannot be used"
fi


