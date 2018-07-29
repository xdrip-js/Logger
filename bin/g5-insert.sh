#!/bin/bash

MESSAGE="${HOME}/myopenaps/monitor/xdripjs/cgm-reset.json"

LDIR="${HOME}/myopenaps/monitor/xdripjs"

function ClearCalibrationInput()
{
  if [ -e ${LDIR}/calibrations.csv ]; then
    cp ${LDIR}/calibrations.csv "${LDIR}/old-calibrations/calibrations.csv.$(date +%Y%m%d-%H%M%S)"
    rm ${LDIR}/calibrations.csv
  fi
}

ClearCalibrationInput
echo "Logger calibration files cleared."
echo "Wait at least 15 minutes and then calibrate"
#TODO - add NS Sensor Insert record
