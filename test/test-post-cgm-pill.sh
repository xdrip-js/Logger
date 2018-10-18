#!/bin/bash

jstr=""

# This func takes an arg list of value name pairs creating a simple json string
# What's different about this vs jq is that this function will ignore
# any value/name pair where the variable value name is null or blank
# it also automatically handles quotes around variable values with strings
# and doesn't include quotes for those without strings

function build_json() {
  local __result="{"
  
  args=("$@")
  for (( i=0; i < ${#}; i+=2 ))
  do
      local __key=${args[$i]}
      local __value=${args[$i+1]}
      #echo "key=$__key, value=$__value"
      local __len=${#__value}
      if [ $__len -gt 0 ]; then
        if [ $(echo "$__value" | grep -cE "^\-?([0-9]+)(\.[0-9]+)?$") -gt 0 ]; then
        # must be a number
          __result="$__result\"$__key\":$__value,"
        else
        # must be a string
          __result="$__result\"$__key\":\"$__value\","
        fi
      fi
  done
  # remove comma on last value/name pair
  __result="${__result::-1}}"
  echo $__result
}




created_at=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
state_id=6
status_id=0
state="OK"
state="OK"
mode="expired"
xrig="xdripjs://$(hostname)"
rssi=-84
unfiltered=114.445
filtered=116.445
noise=0
noiseString="Clean"
voltagea=3.12
voltageb=3.02
txID="4XXXU4"
   

function post_cgm_ns_pill()
{

   jstr="$(build_json \
      sessionStart "$lastSensorInsertDate" \
    state "$state_id" \
    txStatus "$status_id" \
    stateString "$state" \
    stateStringShort "$state" \
    txId "$transmitter" \
    txStatusString "$status" \
    txStatusStringShort "$status" \
    mode "$mode" \
    timestamp "$epochdatems" \
    rssi "$rssi" \
    unfiltered "$unfiltered" \
    filtered "$filtered" \
    noise "$noise" \
    noiseString "$noiseString" \
    slope "$slope" \
    intercept "$yIntercept" \
    calType "$calibrationType" \
    batteryTimestamp "$batteryTimestamp" \
    voltagea "$voltagea" \
    voltageb "$voltageb" \
    temperature "$temperature" \
    resistance "$resist"
    )"
		 

   pill="[{\"device\":\"$xrig\",\"xdripjs\": $jstr, \"created_at\":\"$created_at\"}] "

   echo $pill && echo $pill > ./cgm-pill.json

   /usr/local/bin/g5-post-ns ./cgm-pill.json devicestatus && (echo; echo "Upload to NightScout of cgm status pill record entry worked";) || (echo; echo "Upload to NS of cgm status pill record did not work")
}


post_cgm_ns_pill
