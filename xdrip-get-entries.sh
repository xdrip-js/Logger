#!/bin/bash

glucoseType='.[0].unfiltered'

cd /root/src/xdrip-js-logger

echo "Starting xdrip-get-entries.sh"
date

CALIBRATION_STORAGE="calibration.json"

# remove old calibration storage when sensor change occurs
# calibrate after 15 minutes of sensor change time entered in NS
curl -m 30 "${NIGHTSCOUT_HOST}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -u -d "15 minutes ago" -Iminutes)&find\[eventType\]\[\$regex\]=Sensor.Change" 2>/dev/null | grep "Sensor Change"
if [ $? == 0 ]; then
  echo "sensor change - removing calibration"
  rm $CALIBRATION_STORAGE
fi

if [ -e "./entry.json" ] ; then
  lastGlucose=$(cat ./entry.json | jq -M $glucoseType)
  lastUnfiltered=$(cat ./entry.json | jq -M '.[0].unfiltered')
  lastAfter=$(date -u -d "5 minutes ago" -Iminutes)
  lastPostStr="'.[0] | select(.dateString > \"$lastAfter\") | .glucose'"
  lastPostCal=$(cat ./entry.json | bash -c "jq -M $lastPostStr")
  #echo lastAfter=$lastAfter, lastPostStr=$lastPostStr, lastPostCal=$lastPostCal
  mv ./entry.json ./last-entry.json
fi

transmitter=$1

id2=$(echo "${transmitter: -2}")
id="Dexcom${id2}"
echo "Removing existing Dexcom bluetooth connection = ${id}"
bt-device -r $id

echo "Calling xdrip-js ... node logger $transmitter"
DEBUG=smp,transmitter,bluetooth-manager timeout 360s node logger $transmitter
echo "after xdrip-js bg record below ..."
cat ./entry.json

glucose=$(cat ./entry.json | jq -M $glucoseType)
echo

if [ -z "${glucose}" ] ; then
  echo "Invalid response from g5 transmitter"
  ls -al ./entry.json
  cat ./entry.json
  rm ./entry.json
else
  dg=$(bc -l <<< "$glucose - $lastGlucose")

  # begin try out averaging last two entries ...
  da=${dg}
  if [ -n ${da} -a $(bc <<< "${da} < 0") -eq 1 ]; then
    da=$(bc <<< "0 - $da")
  fi
  if (( $(bc <<< "(${da} < 45) && (${da} > 6)") )); then
     echo "Before Average last 2 entries - lastGlucose=$lastGlucose, dg=$dg, glucose=${glucose}"
     glucose=$(bc -l <<< "($glucose + $lastGlucose)/2")
     dg=$(bc -l <<< "$glucose - $lastGlucose")
     echo "After Average last 2 entries - lastGlucose=$lastGlucose, dg=$dg, glucose=${glucose}"
  fi
  # end average last two entries if noise  code

  # log to csv file for research g5 outputs
  unfiltered=$(cat ./entry.json | jq -M '.[0].unfiltered')
  filtered=$(cat ./entry.json | jq -M '.[0].filtered')
  glucoseg5=$(cat ./entry.json | jq -M '.[0].glucose')
  datetime=$(date +"%Y-%m-%d %H:%M")
  # end log to csv file logic for g5 outputs

  # begin calibration logic - look for calibration from NS, use existing calibration or none
  calibration=0
  ns_url="${NIGHTSCOUT_HOST}"
  METERBG_NS_RAW="meterbg_ns_raw.json"

  # look for a bg check from pumphistory (direct from meter->openaps):
  meterbgafter=$(date -d "7 minutes ago" -Iminutes)
  meterjqstr="'.[] | select(._type == \"BGReceived\") | select(.timestamp > \"$meterbgafter\") | .amount'"
  meterbg=$(bash -c "jq $meterjqstr ~/myopenaps/monitor/pumphistory-merged.json")
  # TBD: meter BG from pumphistory doesn't support mmol yet - has no units...
  echo "meterbg from pumphistory: $meterbg"

  if [ -z $meterbg ]; then
    # look for a bg check from NS (& test NS record for local time or UTC)
    curl -m 30 "${ns_url}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -u -d "7 minutes ago" -Iminutes)&find\[eventType\]\[\$regex\]=Check" 2>/dev/null >> $METERBG_NS_RAW
    isUTC=$(jq ".[0].created_at[-1:]" $METERBG_NS_RAW)
    if [ "$isUTC" != '"Z"' ]; then
      curl -m 30 "${ns_url}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "7 minutes ago" -Iminutes)&find\[eventType\]\[\$regex\]=Check" 2>/dev/null > $METERBG_NS_RAW
      isUTC=$(jq ".[0].created_at[-1:]" $METERBG_NS_RAW)
      if [ "$isUTC" == '"Z"' ]; then
        echo > $METERBG_NS_RAW
      fi
    fi

    meterbgunits=$(cat $METERBG_NS_RAW | jq -M '.[0] | .units' | tr -d '"')
    meterbg=$(cat $METERBG_NS_RAW | jq -M '.[0] | .glucose' | tr -d '"')
    if [ "$meterbgunits" == "mmol" ]; then
      meterbg=$(bc -l <<< "$meterbg *18")
    fi
    echo "meterbg from nightscout: $meterbg"
  fi

  if [ -n "$meterbg" ]; then
    if (( bc -l <<< "($meterbg < 400) && ($meterbg > 40)" )); then
      calibrationBg=$meterbg
      if [ -n "$lastPostCal" ]; then
        if (( bc <<< "($lastPostCal < 400) && ($lastPostCal > 40)" )); then
          calibrationBg=$((($meterbg + $lastPostCal) / 2))
        fi
      fi
      calibration="$(bc -l <<< "$calibrationBg - $glucose")"
      echo "calibration=$calibration, meterbg=$meterbg, lastPostCal=$lastPostCal, calibrationBg=$calibrationBg, glucose=$glucose"
      if (( bc -l <<< "($calibration < 60) && ($calibration > -80)" )); then
        # another safety check, but this is a good calibration
        echo "[{\"calibration\":${calibration}}]" > $CALIBRATION_STORAGE
        cp $METERBG_NS_RAW meterbg-ns-backup.json
      fi
    fi
  fi

  if [ -e $CALIBRATION_STORAGE ]; then
    calibration=$(cat $CALIBRATION_STORAGE | jq -M '.[0] | .calibration')
    calibratedglucose=$(bc -l <<< "$glucose + $calibration")
    echo "After calibration calibratedglucose =$calibratedglucose"
  else
    echo "No valid calibration yet - exiting"
    bt-device -r $id
    exit
  fi

  if [ $calibratedglucose -gt 400 -o $calibratedglucose -lt 40 ]; then
    echo "Glucose $calibratedglucose out of range [40,400] - exiting"
    bt-device -r $id
    exit
  fi

  if [ $dg -gt 50 -o $dg -lt -50 ]; then
    echo "Change $dg out of range [-50,50] - exiting"
    bt-device -r $id
    exit
  fi

   cp entry.json entry-before-calibration.json

   tmp=$(mktemp)
   jq ".[0].glucose = $calibratedglucose" entry.json > "$tmp" && mv "$tmp" entry.json

   tmp=$(mktemp)
   jq ".[0].sgv = $calibratedglucose" entry.json > "$tmp" && mv "$tmp" entry.json

   tmp=$(mktemp)
   jq ".[0].device = \"${transmitter}\"" entry.json > "$tmp" && mv "$tmp" entry.json
  # end calibration logic

  direction='NONE'
  echo "Valid response from g5 transmitter"

  if (( $(bc <<< "${dg} < -10") )); then
     direction='DoubleDown'
  elif (( $(bc <<< "${dg} < -7") )); then
     direction='SingleDown'
  elif (( $(bc <<< "${dg} < -3") )); then
     direction='FortyFiveDown'
  elif (( $(bc <<< "${dg} < 3") )); then
     direction='Flat'
  elif (( $(bc <<< "${dg} < 7") )); then
     direction='FortyFiveUp'
  elif (( $(bc <<< "${dg} < 10") )); then
     direction='SingleUp'
  elif (( $(bc <<< "${dg} < 50") )); then
     direction='DoubleUp'
  fi

  echo "Gluc=${glucose}, last=${lastGlucose}, diff=${dg}, dir=${direction}"

  cat entry.json | jq ".[0].direction = \"$direction\"" > entry-xdrip.json

  if [ ! -f "/var/log/openaps/g5.csv" ]; then
    echo "datetime,unfiltered,filtered,glucoseg5,glucose,calibratedglucose,direction,calibration" > /var/log/openaps/g5.csv
  fi

  echo "${datetime},${unfiltered},${filtered},${glucoseg5},${glucose},${calibratedglucose},${direction},${calibration}" >> /var/log/openaps/g5.csv

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
