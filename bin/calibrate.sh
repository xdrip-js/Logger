#!/bin/bash

# Takes in BG calibration as argument #1 and after some boundary checking 
# it puts it in to ~/openaps/monitor/xdripjs/calibration.json
# This way any apps can put a calibration bg record in that 
# file and Logger will pick it up and use it for calibration.

bg=${1:-"null"}     # arg 1 is meter bg value
UNITS=${2:-"mg/dl"} # arg 2 if "mmol" then bg in mmol
TEST=${3:-""}       # arg 3 if "test" then test mode

calibrationFile="${HOME}/myopenaps/monitor/xdripjs/calibration.json"
stagingFile1=$(mktemp)
stagingFile2=$(mktemp)
#dateString=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

epochdate=$(date +'%s')
# doing it this way for consistency - Logger will convert back to seconds from ms
epochdate=$(($epochdate * 1000)) # xdrip-js requires milliseconds epoch

LOW=40
HIGH=400

# ability to test without causing bg Check treatment to be used
if [ "$TEST" == "test" ]; then
  tmp=$(mktemp)
  calibrationFile=$(mktemp)
fi

if [ "$UNITS" == "mmol" ]; then
  bg=$(bc <<< "($bg *18)/1")
  echo "converted OpenAPS meterbg from $1 mmol value to $bg mg/dl"
fi

if [ "$bg" == "null" ]; then
  echo "Error - Missing required argument 1 meterBG value"
  echo "Usage: calibrate MeterBG"
  exit
fi

if [ $(bc <<< "$bg >= $LOW") -eq 1 -a $(bc <<< "$bg <= $HIGH") -eq 1 ]; then
  echo "[{\"date\":$epochdate,\"type\":\"CalibrateSensor\",\"glucose\":$bg}]" >  $stagingFile2
  if [ -e $calibrationFile ]; then
    cp $calibrationFile $stagingFile1
    jq -c -s add $stagingFile2 $stagingFile1 > $calibrationFile
  else
    cp $stagingFile2 $calibrationFile
  fi
  echo "calibration treatment posted to $calibrationFile - record is below"
  cat $calibrationFile
else
  echo "Error - bg of $bg $UNITS is out of range ($LOW-$HIGH $UNITS) for calibration and cannot be used"
fi


