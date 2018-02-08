#!/bin/bash

glucoseType="unfiltered"

cd /root/src/xdrip-js-logger

echo "Starting xdrip-get-entries.sh"
date

#CALIBRATION_STORAGE="calibration.json"
CAL_INPUT="./calibrations.csv"
CAL_OUTPUT="./calibration-linear.json"
# check UTC to begin with and use UTC flag for any curls
NS_RAW="testUTC.json"
curl --compressed -m 30 "${NIGHTSCOUT_HOST}/api/v1/treatments.json?count=1&find\[created_at\]\[\$gte\]=$(date -d "6000 minutes ago" -Iminutes -u)" 2>/dev/null  > $NS_RAW  
createdAt=$(jq ".[0].created_at" $NS_RAW)
if [[ $createdAt == *"Z"* ]]; then
  UTC=" -u "
  echo "NS is using UTC $UTC"       
else
  UTC=""
  echo "NS is not using UTC"       
fi

#UTC=" -u "

# remove old calibration storage when sensor change occurs
# calibrate after 15 minutes of sensor change time entered in NS
# disable this feature for now. It isn't recreating the calibration file after sensor insert and BG check
#
curl --compressed -m 30 "${NIGHTSCOUT_HOST}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "15 minutes ago" -Iminutes $UTC)&find\[eventType\]\[\$regex\]=Sensor.Change" 2>/dev/null | grep "Sensor Change"
if [ $? == 0 ]; then
  echo "sensor change within last 15 minutes - clearing calibration files"
  cp $CAL_INPUT "${CAL_INPUT}.$(date +%Y%m%d-%H%M%S)" 
  cp $CAL_OUTPUT "${CAL_OUTPUT}.$(date +%Y%m%d-%H%M%S)"
  rm $CAL_INPUT
  rm $CAL_OUTPUT
  echo "exiting"
  exit
fi


if [ -e "./entry.json" ] ; then
  lastGlucose=$(cat ./entry.json | jq -M '.[0].glucose')
  echo "lastGlucose=$lastGlucose"
  mv ./entry.json ./last-entry.json
else
  echo "prior entry.json not available, setting lastGlucose=0"
  lastGlucose=0
fi

transmitter=$1

id2=$(echo "${transmitter: -2}")
id="Dexcom${id2}"
echo "Removing existing Dexcom bluetooth connection = ${id}"
bt-device -r $id

echo "Calling xdrip-js ... node logger $transmitter"
DEBUG=smp,transmitter,bluetooth-manager timeout 360s node logger $transmitter
echo
echo "after xdrip-js bg record below ..."
cat ./entry.json
glucose=$(cat ./entry.json | jq -M '.[0].glucose')

if [ -z "${glucose}" ] ; then
  echo "Invalid response from g5 transmitter"
  ls -al ./entry.json
  rm ./entry.json
  bt-device -r $id
  exit
fi

# capture raw values for use and for log to csv file 
unfiltered=$(cat ./entry.json | jq -M '.[0].unfiltered')
filtered=$(cat ./entry.json | jq -M '.[0].filtered')
datetime=$(date +"%Y-%m-%d %H:%M")
if [ "glucoseType" == "filtered" ]; then
  raw=$filtered
else
  raw=$unfiltered
fi

# begin calibration logic - look for calibration from NS, use existing calibration or none
ns_url="${NIGHTSCOUT_HOST}"
METERBG_NS_RAW="meterbg_ns_raw.json"

rm $METERBG_NS_RAW # clear any old meterbg curl responses

# look for a bg check from pumphistory (direct from meter->openaps):
meterbgafter=$(date -d "7 minutes ago" -Iminutes)
meterjqstr="'.[] | select(._type == \"BGReceived\") | select(.timestamp > \"$meterbgafter\") | .amount'"
meterbg=$(bash -c "jq $meterjqstr ~/myopenaps/monitor/pumphistory-merged.json")
# TBD: meter BG from pumphistory doesn't support mmol yet - has no units...
echo
echo "meterbg from pumphistory: $meterbg"

if [ -z $meterbg ]; then
  curl --compressed -m 30 "${ns_url}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "7 minutes ago" -Iminutes $UTC)&find\[eventType\]\[\$regex\]=Check" 2>/dev/null > $METERBG_NS_RAW
  #createdAt=$(jq ".[0].created_at" $METERBG_NS_RAW)
  meterbgid=$(jq ".[0]._id" $METERBG_NS_RAW)

  meterbgunits=$(cat $METERBG_NS_RAW | jq -M '.[0] | .units')
  meterbg=`jq -M '.[0] .glucose' $METERBG_NS_RAW`
  meterbg="${meterbg%\"}"
  meterbg="${meterbg#\"}"
  if [ "$meterbgunits" == "mmol" ]; then
    meterbg=$(bc <<< "($meterbg *18)/1")
  fi
  echo "meterbg from nightscout: $meterbg"

  if [ "$meterbg" != "null" -a "$meterbg" != "" ]; then
    if [ $(bc <<< "$meterbg < 400") -eq 1  -a $(bc <<< "$meterbg > 40") -eq 1 ]; then
      # only do this once for a single calibration check for duplicate BG check record ID
      if ! cat $CAL_INPUT | egrep "$meterbgid"; then 
        echo "$raw,$meterbg,$datetime,$meterbgid" >> $CAL_INPUT
        ./calc-calibration.sh $CAL_INPUT $CAL_OUTPUT
      fi
    else
      echo "Invalid calibration"
    fi
    cat $CAL_INPUT
    cat $CAL_OUTPUT
  fi
fi

if [ -e $CAL_OUTPUT ]; then
  slope=`jq -M '.[0] .slope' calibration-linear.json` 
  yIntercept=`jq -M '.[0] .yIntercept' calibration-linear.json` 
  slopeError=`jq -M '.[0] .slopeError' calibration-linear.json` 
  yError=`jq -M '.[0] .yError' calibration-linear.json` 
  calibrationType=`jq -M '.[0] .calibrationType' calibration-linear.json` 
else
  # exit until we have a valid calibration record
  echo "no valid calibration record yet, exiting ..."
  bt-device -r $id
  exit
fi


# $raw is either unfiltered or filtered value from g5
# based upon glucoseType variable at top of script
calibratedBG=$(bc -l <<< "($raw - $yIntercept)/$slope")
calibratedBG=$(bc <<< "($calibratedBG / 1)") # truncate
echo "After calibration calibratedBG =$calibratedBG, slope=$slope, yIntercept=$yIntercept, filtered=$filtered, unfiltered=$unfiltered, raw=$raw"

# For Single Point calibration, use a calculated corrective intercept
# for glucose in the range of 70 <= BG < 85
# per https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4764224
# AdjustedBG = BG - CI
# CI = a1 * BG^2 + a2 * BG + a3
# a1=-0.1667, a2=25.66667, a3=-977.5
c=$calibratedBG
if [ "$calibrationType" == "SinglePoint" ]; then
  if [ $(bc <<< "$c > 69") -eq 1 -a $(bc <<< "$c < 85") -eq 1 ]; then
    echo "SinglePoint calibration calculating corrective intercept"
    echo "Before CI, BG=$c"
    calibratedBG=$(bc <<< "$c - (-0.16667 * ${c}^2 + 25.6667 * ${c} - 977.5)")
    echo "After CI, BG=$calibratedBG"
  fi
fi

if [ -z $calibratedBG -o $(bc <<< "$calibratedBG > 400") -eq 1 -o $(bc <<< "$calibratedBG < 40") -eq 1 ]; then
  echo "Glucose $calibratedBG out of range [40,400] - exiting"
  bt-device -r $id
  exit
fi

if [ -z $lastGlucose -o $(bc <<< "$lastGlucose < 40") -eq 1 ] ; then
  dg=0
else
  dg=$(bc <<< "$calibratedBG - $lastGlucose")
fi
echo "lastGlucose=$lastGlucose, dg=$dg"

# begin try out averaging last two entries ...
da=$dg
if [ -n $da -a $(bc <<< "$da < 0") -eq 1 ]; then
  da=$(bc <<< "0 - $da")
fi
if [ "$da" -lt "45" -a "$da" -gt "15" ]; then
 echo "Before Average last 2 entries - lastGlucose=$lastGlucose, dg=$dg, calibratedBG=$calibratedBG"
 calibratedBG=$(bc <<< "($calibratedBG + $lastGlucose)/2")
 dg=$(bc <<< "$calibratedBG - $lastGlucose")
 echo "After average last 2 entries - lastGlucose=$lastGlucose, dg=$dg, calibratedBG=${calibratedBG}"
fi
# end average last two entries if noise  code


if [ $(bc <<< "$dg > 50") -eq 1 -o $(bc <<< "$dg < -50") -eq 1 ]; then
  echo "Change $dg out of range [50,-50] - exiting"
  bt-device -r $id
  exit
fi

cp entry.json entry-before-calibration.json

tmp=$(mktemp)
jq ".[0].glucose = $calibratedBG" entry.json > "$tmp" && mv "$tmp" entry.json

tmp=$(mktemp)
jq ".[0].sgv = $calibratedBG" entry.json > "$tmp" && mv "$tmp" entry.json

tmp=$(mktemp)
jq ".[0].device = \"${transmitter}\"" entry.json > "$tmp" && mv "$tmp" entry.json
# end calibration logic

direction='NONE'

# Begin trend calculation logic based on last 15 minutes glucose delta average
if [ -z "$dg" ]; then
  direction="NONE"
  echo "setting direction=NONE because dg is null, dg=$dg"
else
  echo $dg > bgdelta-$(date +%Y%m%d-%H%M%S).dat

   # first delete any delta's > 15 minutes
  find . -name 'bgdelta*.dat' -mmin +15 -delete
  usedRecords=0
  totalDelta=0
  for i in ./bgdelta*.dat; do
    usedRecords=$(bc <<< "$usedRecords + 1")
    currentDelta=`cat $i`
    totalDelta=$(bc <<< "$totalDelta + $currentDelta")
  done

  if [ $(bc <<< "$usedRecords > 0") -eq 1 ]; then
    perMinuteAverageDelta=$(bc -l <<< "$totalDelta / (5 * $usedRecords)")

    if (( $(bc <<< "$perMinuteAverageDelta > 3") )); then
      direction='DoubleUp'
    elif (( $(bc <<< "$perMinuteAverageDelta > 2") )); then
      direction='SingleUp'
    elif (( $(bc <<< "$perMinuteAverageDelta > 1") )); then
      direction='FortyFiveUp'
    elif (( $(bc <<< "$perMinuteAverageDelta < -3") )); then
      direction='DoubleDown'
    elif (( $(bc <<< "$perMinuteAverageDelta < -2") )); then
      direction='SingleDown'
    elif (( $(bc <<< "$perMinuteAverageDelta < -1") )); then
      direction='FortyFiveDown'
    else
      direction='Flat'
    fi
  fi
fi

echo "perMinuteAverageDelta=$perMinuteAverageDelta, totalDelta=$totalDelta, usedRecords=$usedRecords"
echo "Gluc=${calibratedBG}, last=${lastGlucose}, diff=${dg}, dir=${direction}"


cat entry.json | jq ".[0].direction = \"$direction\"" > entry-xdrip.json


if [ ! -f "/var/log/openaps/g5.csv" ]; then
  echo "datetime,unfiltered,filtered,glucose,trend,calibratedBG,slope,yIntercept,slopeError,yError" > /var/log/openaps/g5.csv
fi


echo "${datetime},${unfiltered},${filtered},${glucose},${direction},${calibratedBG},${slope},${yIntercept},${slopeError},${yError}" >> /var/log/openaps/g5.csv

echo "Posting glucose record to xdripAPS"
./post-xdripAPS.sh ./entry-xdrip.json

if [ -e "./entry-backfill.json" ] ; then
  # In this case backfill records not yet sent to Nightscout

  jq -s add ./entry-xdrip.json ./entry-backfill.json > ./entry-ns.json
  cp ./entry-ns.json ./entry-backfill.json
  echo "entry-backfill.json exists, so setting up for backfill"
else
  echo "entry-backfill.json does not exist so no backfill"
  cp ./entry-xdrip.json ./entry-ns.json
fi

echo "Posting blood glucose record(s) to NightScout"
./post-ns.sh ./entry-ns.json && (echo; echo "Upload to NightScout of xdrip entry worked ... removing ./entry-backfill.json"; rm -f ./entry-backfill.json) || (echo; echo "Upload to NS of xdrip entry did not work ... saving for upload when network is restored"; cp ./entry-ns.json ./entry-backfill.json)
echo

bt-device -r $id
echo "Finished xdrip-get-entries.sh"
date
echo
