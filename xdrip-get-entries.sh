#!/bin/bash

glucoseType="unfiltered"

cd /root/src/xdrip-js-logger
mkdir -p old-calibrations

echo "Starting xdrip-get-entries.sh"
date

# Check required environment variables
source ~/.bash_profile
export API_SECRET
export NIGHTSCOUT_HOST
if [ "$API_SECRET" = "" ]; then
   echo "API_SECRET environment variable is not set"
   echo -e "Make sure the two lines below are in your ~/.bash_profile as follows:\n"
   echo "API_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxx # where xxxx is your hashed NS API_SECRET"
   echo -e "export API_SECRET\n\nexiting\n"
   exit
fi
if [ "$NIGHTSCOUT_HOST" = "" ]; then
   echo "NIGHTSCOUT_HOST environment variable is not set"
   echo -e "Make sure the two lines below are in your ~/.bash_profile as follows:\n"
   echo "NIGHTSCOUT_HOST=https://xxxx # where xxxx is your hashed Nightscout url"
   echo -e "export NIGHTSCOUT_HOST\n\nexiting\n"
   exit
fi



function ClearCalibrationInput()
{
  if [ -e ./calibrations.csv ]; then
    cp ./calibrations.csv "./old-calibrations/calibrations.csv.$(date +%Y%m%d-%H%M%S)" 
    rm ./calibrations.csv
  fi
}

function ClearCalibrationCache()
{
  local cache="./old-calibrations/calibration-linear.json"
  if [ -e $cache ]; then
    cp $cache "${cache}.$(date +%Y%m%d-%H%M%S)" 
    rm $cache 
  fi
}

noiseSend=0 # default unknown
UTC=" -u "
# check UTC to begin with and use UTC flag for any curls
curl --compressed -m 30 "${NIGHTSCOUT_HOST}/api/v1/treatments.json?count=1&find\[created_at\]\[\$gte\]=$(date -d "2400 hours ago" -Ihours -u)&find\[eventType\]\[\$regex\]=Sensor.Change" 2>/dev/null  > ./testUTC.json  
if [ $? == 0 ]; then
  createdAt=$(jq ".[0].created_at" ./testUTC.json)
  if [ $"$createdAt" == "" ]; then
    echo "You must record a \"Sensor Insert\" in Nightscout before Logger will run" 
    echo -e "exiting\n"
    exit
  elif [[ $createdAt == *"Z"* ]]; then
    UTC=" -u "
    echo "NS is using UTC $UTC"      
  else
    UTC=""
    echo "NS is not using UTC $UTC"      
  fi
fi

# remove old calibration storage when sensor change occurs
# calibrate after 15 minutes of sensor change time entered in NS
#
curl --compressed -m 30 "${NIGHTSCOUT_HOST}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "15 minutes ago" -Iminutes $UTC)&find\[eventType\]\[\$regex\]=Sensor.Change" 2>/dev/null | grep "Sensor Change"
if [ $? == 0 ]; then
  echo "sensor change within last 15 minutes - clearing calibration files"
  ClearCalibrationInput
  ClearCalibrationCache
  touch ./last_sensor_change
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
epochdate=$(date +'%s')
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

maxDelta=30
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
      if ! cat ./calibrations.csv | egrep "$meterbgid"; then 
        echo "$raw,$meterbg,$datetime,$epochdate,$meterbgid" >> ./calibrations.csv
        ./calc-calibration.sh ./calibrations.csv ./calibration-linear.json
        maxDelta=60
      fi
    else
      echo "Invalid calibration, meterbg=$meterbg outside of range [40,400]"
    fi
    cat ./calibrations.csv
    cat ./calibration-linear.json
  fi
fi
# check if sensor changed in last 12 hours.
# If so, clear calibration inputs and only calibrate using single point calibration
# do not keep the calibration records within the first 12 hours as they might skew LSR
if [ -e ./last_sensor_change ]; then
  if test  `find ./last_sensor_change -mmin -720`
  then
    echo "sensor change within last 12 hours - will use single pt calibration"
    ClearCalibrationInput
  fi
fi

if [ -e ./calibration-linear.json ]; then
  slope=`jq -M '.[0] .slope' ./calibration-linear.json` 
  yIntercept=`jq -M '.[0] .yIntercept' ./calibration-linear.json` 
  slopeError=`jq -M '.[0] .slopeError' ./calibration-linear.json` 
  yError=`jq -M '.[0] .yError' ./calibration-linear.json` 
  calibrationType=`jq -M '.[0] .calibrationType' ./calibration-linear.json` 
  calibrationType="${calibrationType%\"}"
  calibrationType="${calibrationType#\"}"
  numCalibrations=`jq -M '.[0] .numCalibrations' ./calibration-linear.json` 
  rSquared=`jq -M '.[0] .rSquared' ./calibration-linear.json` 
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
echo "numCalibrations=$numCalibrations, calibrationType=$calibrationType, c=$c"
if [ "$calibrationType" = "SinglePoint" ]; then
  echo "inside CalibrationType=$calibrationType, c=$c"
  if [ $(bc <<< "$c > 69") -eq 1 -a $(bc <<< "$c < 85") -eq 1 ]; then
    echo "SinglePoint calibration calculating corrective intercept"
    echo "Before CI, BG=$c"
    calibratedBG=$(bc -l <<< "$c - (-0.16667 * ${c}^2 + 25.6667 * ${c} - 977.5)")
    calibratedBG=$(bc <<< "($calibratedBG / 1)") # truncate
    echo "After CI, BG=$calibratedBG"
  else
    echo "Not using CI because bg not in [70-84]"
  fi
fi

if [ -z $calibratedBG ]; then
  # Outer calibrated BG boundary checks - exit and don't send these on to Nightscout / openaps
  if [ $(bc <<< "$calibratedBG > 600") -eq 1 -o $(bc <<< "$calibratedBG < 0") -eq 1 ]; then
    echo "Glucose $calibratedBG out of range [0,600] - exiting"
    bt-device -r $id
    exit
  fi

  # Inner Calibrated BG boundary checks for case > 400
  if [ $(bc <<< "$calibratedBG > 400") -eq 1 ]; then
    echo "Glucose $calibratedBG over 400 - setting noise level Heavy"
    echo "BG value will show in Nightscout but Openaps will not use it for looping"
    noiseSend=4
  fi

  # Inner Calibrated BG boundary checks for case < 40
  if [ $(bc <<< "$calibratedBG < 40") -eq 1 ]; then
    echo "Glucose $calibratedBG < 40 - setting noise level Light"
    echo "BG value will show in Nightscout and Openaps will conservatively use it for looping"
    noiseSend=2
  fi
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
# end average last two entries if noise


if [ $(bc <<< "$dg > $maxDelta") -eq 1 -o $(bc <<< "$dg < (0 - $maxDelta)") -eq 1 ]; then
  echo "Change $dg out of range [$maxDelta,-${maxDelta}] - setting noise=Heavy"
  noiseSend=4
fi

cp entry.json entry-before-calibration.json

tmp=$(mktemp)
jq ".[0].glucose = $calibratedBG" entry.json > "$tmp" && mv "$tmp" entry.json

tmp=$(mktemp)
jq ".[0].sgv = $calibratedBG" entry.json > "$tmp" && mv "$tmp" entry.json

tmp=$(mktemp)
jq ".[0].device = \"${transmitter}\"" entry.json > "$tmp" && mv "$tmp" entry.json

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
  echo "epochdate,datetime,unfiltered,filtered,trend,calibratedBG,meterbg,slope,yIntercept,slopeError,yError,rSquared,Noise,NoiseSend" > /var/log/openaps/g5.csv
fi


# calculate the noise and position it for updating the entry sent to NS and xdripAPS
if [ $(bc -l <<< "$noiseSend == 0") -eq 1 ]; then
  # means that noise was not already set before
  noise=$(./calc-noise.sh)
fi

if [ $(bc -l <<< "$noise < 0.2") -eq 1 ]; then
  noiseSend=1  # Clean
elif [ $(bc -l <<< "$noise < 0.4") -eq 1 ]; then
  noiseSend=2  # Light
elif [ $(bc -l <<< "$noise < 0.6") -eq 1 ]; then
  noiseSend=3  # Medium
elif [ $(bc -l <<< "$noise >= 0.75") -eq 1 ]; then
  noiseSend=4  # Heavy
fi

tmp=$(mktemp)
jq ".[0].noise = $noiseSend" entry-xdrip.json > "$tmp" && mv "$tmp" entry-xdrip.json

echo "${epochdate},${datetime},${unfiltered},${filtered},${direction},${calibratedBG},${meterbg},${slope},${yIntercept},${slopeError},${yError},${rSquared},${noise},${noiseSend}" >> /var/log/openaps/g5.csv

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

echo "Posting blood glucose to NightScout"
./post-ns.sh ./entry-ns.json && (echo; echo "Upload to NightScout of xdrip entry worked ... removing ./entry-backfill.json"; rm -f ./entry-backfill.json) || (echo; echo "Upload to NS of xdrip entry did not work ... saving for upload when network is restored ... Auth to NS may have failed; ensure you are using hashed API_SECRET in ~/.bash_profile"; cp ./entry-ns.json ./entry-backfill.json)
echo

bt-device -r $id
echo "Finished xdrip-get-entries.sh"
date
echo
