#!/bin/bash

glucoseType='.[0].unfiltered'

cd /root/src/xdrip-js-logger

echo "Starting xdrip-get-entries.sh"
date

#CALIBRATION_STORAGE="calibration.json"
CAL_INPUT="./calibrations.csv"
CAL_OUTPUT="./calibration-linear.json"

# remove old calibration storage when sensor change occurs
# calibrate after 15 minutes of sensor change time entered in NS
# disable this feature for now. It isn't recreating the calibration file after sensor insert and BG check
#
#curl -m 30 "${NIGHTSCOUT_HOST}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "15 minutes ago" -Iminutes -u)&find\[eventType\]\[\$regex\]=Sensor.Change" 2>/dev/null | grep "Sensor Change"
#if [ $? == 0 ]; then
#  echo "sensor change - removing calibration"
#  rm $CALIBRATION_STORAGE
#fi
glucoseType='.[0].unfiltered'

if [ -e "./entry.json" ] ; then
  lastGlucose=$(cat ./entry.json | jq -M '.[0].glucose')
  echo "lastGlucose=$lastGlucose"
  
#  lastAfter=$(date -d "5 minutes ago" -Iminutes)
#  lastPostStr="'.[0] | select(.dateString > \"$lastAfter\") | .glucose'"
#  lastPostCal=$(cat ./entry.json | bash -c "jq -M $lastPostStr")
#  echo lastAfter=$lastAfter, lastPostStr=$lastPostStr, lastPostCal=$lastPostCal
  mv ./entry.json ./last-entry.json
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
fi

# capture raw values for use and for log to csv file 
unfiltered=$(cat ./entry.json | jq -M '.[0].unfiltered')
filtered=$(cat ./entry.json | jq -M '.[0].filtered')
glucoseg5=$(cat ./entry.json | jq -M '.[0].glucose')
datetime=$(date +"%Y-%m-%d %H:%M")

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
  curl -m 30 "${ns_url}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "7 minutes ago" -Iminutes -u)&find\[eventType\]\[\$regex\]=Check" 2>/dev/null > $METERBG_NS_RAW
  createdAt=$(jq ".[0].created_at" $METERBG_NS_RAW)

  if [[ $createdAt == *"Z"* ]]; then
     echo "meterbg within 7 minutes using UTC time comparison."       
  else   
    if [ "$createdAt" != "null" -a "$createdAt" != "" ]; then
      curl -m 30 "${ns_url}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "7 minutes ago" -Iminutes)&find\[eventType\]\[\$regex\]=Check" 2>/dev/null > $METERBG_NS_RAW
      echo "meterbg within 7 minutes using non-UTC time comparison."
    fi
  fi
    
  meterbgunits=$(cat $METERBG_NS_RAW | jq -M '.[0] | .units')
  meterbg=`jq -M '.[0] .glucose' $METERBG_NS_RAW`
  meterbg="${meterbg%\"}"
  meterbg="${meterbg#\"}"
  if [ "$meterbgunits" == "mmol" ]; then
    meterbg=$(bc <<< "($meterbg *18)/1")
  fi
  echo "meterbg from nightscout: $meterbg"

  if [ "$meterBG" != "null" -a "$meterBG" != "" ]; then
    if [ $(bc <<< "$meterbg < 400") -eq 1  -a $(bc <<< "$meterbg > 40") -eq 1 ]; then
      echo "$unfiltered,$meterbg,$datetime" >> $CAL_INPUT
      ./calc-calibration.sh $CAL_INPUT $CAL_OUTPUT
    else
      echo "Invalid calibration"
    fi
    cat $CAL_OUTPUT
  fi
fi

if [ -e $CAL_OUTPUT ]; then
  slope=`jq -M '.[0] .slope' calibration-linear.json` 
  yIntercept=`jq -M '.[0] .yIntercept' calibration-linear.json` 
else
  slope=1000
  yIntercept=0
fi

calibratedBG=$(bc -l <<< "($unfiltered-$yIntercept)/$slope")
calibratedBG=$(bc <<< "($calibratedBG/1)") # truncate
echo "After calibration calibratedBG =$calibratedBG, slope=$slope, yIntercept=$yIntercept, unfiltered=$unfiltered"

if [ $(bc <<< "$calibratedBG > 400") -eq 1 -o $(bc <<< "$calibratedBG < 40") -eq 1 ]; then
  echo "Glucose $calibratedBG out of range [40,400] - exiting"
  bt-device -r $id
  exit
fi

glucose=$calibratedBG

if [ -z "${glucose}" ] ; then
  echo "Invalid response from g5 transmitter"
  ls -al ./entry.json
  cat ./entry.json
  rm ./entry.json
else
  echo "Valid response from g5 transmitter"
  if [ -z $lastGlucose -o $(bc <<< "$lastGlucose < 40") -eq 1] ; then
    dg=0
  else
    dg=$(bc <<< "$glucose - $lastGlucose")
  fi

  # begin try out averaging last two entries ...
  da=$dg
  if [ -n $da -a $(bc <<< "$da < 0") -eq 1 ]; then
    da=$(bc <<< "0 - $da")
  fi
  if [ "$da" -lt "45" -a "$da" -gt "15" ]; then
   echo "Before Average last 2 entries - lastGlucose=$lastGlucose, dg=$dg, glucose=$glucose"
   glucose=$(bc <<< "($glucose + $lastGlucose)/2")
   dg=$(bc <<< "$glucose - $lastGlucose")
   echo "After average last 2 entries - lastGlucose=$lastGlucose, dg=$dg, glucose=${glucose}"
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
  echo "Gluc=${glucose}, last=${lastGlucose}, diff=${dg}, dir=${direction}"


  cat entry.json | jq ".[0].direction = \"$direction\"" > entry-xdrip.json


  if [ ! -f "/var/log/openaps/g5.csv" ]; then
    echo "datetime,unfiltered,filtered,glucoseg5,glucose,direction,calibratedBG,slope,yIntercept" > /var/log/openaps/g5.csv
  fi


  echo "${datetime},${unfiltered},${filtered},${glucoseg5},${glucose},${direction},${calibratedBG},${slope},${yIntercept}" >> /var/log/openaps/g5.csv

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
fi

bt-device -r $id
echo "Finished xdrip-get-entries.sh"
date
echo
