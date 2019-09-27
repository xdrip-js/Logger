#!/bin/bash

SECONDS_IN_10_DAYS=864000
SECONDS_IN_1_DAY=86400
SECONDS_IN_7_DAYS=604800
SECONDS_IN_30_MINUTES=1800

CONF_DIR="${HOME}/myopenaps"
LDIR="${HOME}/myopenaps/monitor/xdripjs"
OLD_LDIR="${HOME}/myopenaps/monitor/logger"
treatmentsFile="${LDIR}/treatments-backfill.json"
lastEntryFile="${LDIR}/last-entry.json"
calibrationFile="${LDIR}/calibration-linear.json"
calCacheFile="${LDIR}/calibrations.csv"
xdripMessageFile="${LDIR}/xdrip-js-messages.json"
calibrationMessageFile="${LDIR}/calibration-xdrip-js-messages.json"
sentLoggerCalibrationToTx=false
CALFILE="${LDIR}/calibration.json"

main()
{
  log "Starting Logger"

  check_dirs

# Cmd line args - transmitter $1 is 6 character tx serial number
  transmitter=$1
  if [ -z  "$transmitter" ]; then
    # check config file
    transmitter=$(cat ${CONF_DIR}/xdripjs.json | jq -M -r '.transmitter_id')
  fi
  if [ -z  "$transmitter" ] || [ "$transmitter" == "null" ]; then
    log "ERROR: No transmitter id set!; exiting"
    exit
  fi

  txType="g5"

  if [[ $transmitter == 8* ]]; then
    txType="g6"
  fi

  cmd_line_mode=$2
  if [ -z "$cmd_line_mode" ]; then
    # check config file
    cmd_line_mode=$(cat ${CONF_DIR}/xdripjs.json | jq -M -r '.mode')
    if [ -z  "$cmd_line_mode" ] || [ "$cmd_line_mode" == "null" ]; then
      cmd_line_mode=""
    fi
  fi

  pumpUnits=$3
  if [ -z  "$pumpUnits" ]; then
    # check config file
    pumpUnits=$(cat ${CONF_DIR}/xdripjs.json | jq -M -r '.pump_units')
    if [ -z  "$pumpUnits" ] || [ "$pumpUnits" == "null" ]; then
      pumpUnits="mg/dl"
    fi
  fi

  meterid=$4
  if [ -z  "$meterid" ]; then
    # check config file
    meterid=$(cat ${CONF_DIR}/xdripjs.json | jq -M -r '.fake_meter_id')
    if [ -z  "$meterid" ] || [ "$meterid" == "null" ]; then
      meterid="000000"
    fi
  fi

  # check config file
  sensorCode=$(cat ${CONF_DIR}/xdripjs.json | jq -M -r '.sensor_code')
  if [ -z  "$sensorCode" ] || [ "$sensorCode" == "null" ]; then
    sensorCode=""
  fi

  watchdog=$(cat ${CONF_DIR}/xdripjs.json | jq -M -r '.watchdog')
  if [ -z  "$watchdog" ] || [ "$watchdog" == "null" ]; then
    watchdog=true
  fi
  log "Parameter (watchdog):  $watchdog"

  utc=$(cat ${CONF_DIR}/xdripjs.json | jq -M -r '.utc')
  if [ -z  "$utc" ] || [ "$utc" == "null" ]; then
    utc=true
  fi
  log "Parameter (utc): $utc"

  auto_sensor_restart=$(cat ${CONF_DIR}/xdripjs.json | jq -M -r '.auto_sensor_restart')
  if [ -z  "$auto_sensor_restart" ] || [ "$auto_sensor_restart" == "null" ]; then
    auto_sensor_restart=false
  fi
  log "Parameter (auto_sensor_restart): $auto_sensor_restart"


  fakemeter_only_offline=$(cat ${CONF_DIR}/xdripjs.json | jq -M -r '.fakemeter_only_offline')
  if [ -z  "$fakemeter_only_offline" ] || [ "$fakemeter_only_offline" == "null" ]; then
    fakemeter_only_offline=false
  fi

  log "Parameter (fakemeter_only_offline): $fakemeter_only_offline"

  alternateBluetoothChannel=$(cat ${CONF_DIR}/xdripjs.json | jq -M -r '.alternate_bluetooth_channel')
  if [ -z  "$alternateBluetoothChannel" ] || [ "$alternateBluetoothChannel" == "null" ]; then
    alternateBluetoothChannel=false
  fi

  log "Parameter (alternateBluetoothChannel): $alternateBluetoothChannel"
  log "Parameter (transmitter): $transmitter"

  id2=$(echo "${transmitter: -2}")
  id="Dexcom${id2}"
  rig="openaps://$(hostname)"
  glucoseType="unfiltered"
  noiseSend=4 # default heavy
  UTCString=" -u "
  lastGlucose=0
  lastGlucoseDate=0
  lastSensorInsertDate=0
  variation=0
  messages=""
  ns_url="${NIGHTSCOUT_HOST}"
  METERBG_NS_RAW="meterbg_ns_raw.json"
  battery_check="No" # default - however it will be changed to Yes every 12 hours
  sensitivty=0

  epochdate=$(date +'%s')
  epochdatems=$(date +'%s%3N')
  dateString=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")


  initialize_mode # call now and after getting status from tx
  initialize_messages
  check_environment
  check_utc

  check_last_entry_values

  check_last_glucose_time_smart_sleep

  # clear out prior curl or tx responses
  rm -f $METERBG_NS_RAW 
  rm -f ${LDIR}/entry.json

  check_sensor_change
  check_sensitivity

  check_send_battery_status
  check_sensor_start
  check_sensor_stop

# begin calibration logic - look for calibration from NS, use existing calibration or none
  maxDelta=30
  found_meterbg=false
  check_cmd_line_calibration
  check_pump_history_calibration
  check_ns_calibration
  check_messages

  remove_dexcom_bt_pair
  compile_messages
  call_logger
  epochdate=$(date +'%s')
  epochdatems=$(date +'%s%3N')
  dateString=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
  capture_entry_values
  checkif_fallback_mode

  log "Mode = $mode"
  if [[ "$mode" != "expired" ]]; then
    initialize_calibrate_bg 
  else
    check_last_calibration
  fi
  set_entry_fields

  check_variation
  check_native_calibrates_lsr
  check_tx_calibration

  #call after posting to NS OpenAPS for not-expired mode
  if [ "$mode" == "expired" ]; then
    calculate_calibrations
  fi

  check_recent_sensor_insert


  readLastState
  if [ "$mode" == "expired" ]; then
    apply_lsr_calibration 
  fi

  # necessary for not-expired mode - ok for both modes 
  cp -p ${LDIR}/entry.json ${LDIR}/entry-xdrip.json

  process_delta # call for all modes 
  calculate_noise # necessary for all modes

  fake_meter

  if [ "$state" != "Stopped" ] || [ "$mode" == "expired" ]; then
    log "Posting glucose record to xdripAPS / OpenAPS"
    if [ -e "${LDIR}/entry-backfill2.json" ] ; then
      local numBackfills=$(jq '. | length' ${LDIR}/entry-backfill2.json)
      if [ $(bc <<< "$numBackfills > 6") -eq 1 ]; then
        # more than 30 minutes of missed/backfilled glucose values
        postAnnouncementToNSAdder="Backfilled $numBackfills glucose values"
      fi
      /usr/local/bin/cgm-post-xdrip ${LDIR}/entry-backfill2.json
    fi
    /usr/local/bin/cgm-post-xdrip ${LDIR}/entry-xdrip.json
  fi

  post-nightscout-with-backfill
  cp -p ${LDIR}/entry-xdrip.json $lastEntryFile

  if [ "$mode" != "expired" ]; then
    log "Calling expired tx lsr calcs (after posting) -allows mode switches / comparisons" 
    calculate_calibrations
    apply_lsr_calibration 
  fi

  check_battery_status

  log_cgm_csv

  process_announcements
  post_cgm_ns_pill

  saveLastState

  remove_dexcom_bt_pair
  log "Completed Logger"
  echo
}

function validNumber()
{
  local num=$1
  case ${num#[-+]} in
    *[!0-9.]* | '') echo false ;;
    * ) echo true ;;
  esac
}


function validBG()
{
  local bg=$1
  local valid="false"

  if [ "$(validNumber $bg)" == "true" ]; then
    if [ $(bc  -l <<< "$bg >= 20") -eq 1 -a $(bc -l <<< "$bg < 500") -eq 1 ]; then
      valid="true"
    fi
  fi

  echo $valid
}


function check_dirs() {

  if [ ! -d ${LDIR} ]; then
    if [ -d ${OLD_LDIR} ]; then
      mv ${OLD_LDIR} ${LDIR}
    fi
  fi
  mkdir -p ${LDIR}
  mkdir -p ${LDIR}/old-calibrations
}

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

function readLastState
{
    lastState=$(cat ${LDIR}/Logger-last-state.json | jq -M '.[0].state')
    lastState="${lastState%\"}"
    lastState="${lastState#\"}"
    log "readLastState: lastState=$lastState"
}

function saveLastState
{
  log "saveLastState, state=$state"
  echo "[{\"state\":\"${state}\",\"txId\":\"${transmitter}\"}]" > ${LDIR}/Logger-last-state.json
}

function log
{
  echo -e "$(date +'%m/%d %H:%M:%S') $*"
}

function fake_meter()
{
  if [[ "$fakemeter_only_offline" == true && !$(~/src/Logger/bin/logger-online.sh) ]]; then
    log  "Not running fakemeter because fakemeter_only_offline=true and not offline"
    return
  fi

  if [ -e "/usr/local/bin/fakemeter" ]; then
    if [ -d ~/myopenaps/plugins/once ]; then
        scriptf=~/myopenaps/plugins/once/run_fakemeter.sh
        log "Scheduling fakemeter run once at end of next OpenAPS loop to send BG of $calibratedBG to pump via meterid $meterid"
      echo "#!/bin/bash" > $scriptf 
      echo "fakemeter -m $meterid $calibratedBG" >> $scriptf 
      chmod +x $scriptf 
    else
      if ! listen -t 4s >& /dev/null ; then 
        log "Sending BG of $calibratedBG to pump via meterid $meterid"
        fakemeter -m $meterid  $calibratedBG 
      else
        log "Timed out trying to send BG of $calibratedBG to pump via meterid $meterid"
      fi
    fi
  fi
}


# Check required environment variables
function check_environment
{
  source ~/.bash_profile
  cd ~/src/Logger
  export API_SECRET
  export NIGHTSCOUT_HOST
  if [ "$API_SECRET" = "" ]; then
     log "API_SECRET environment variable is not set"
     log "Make sure the two lines below are in your ~/.bash_profile as follows:\n"
     log "API_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxx # where xxxx is your hashed NS API_SECRET"
     log "export API_SECRET\n\nexiting\n"
     state_id=0x21
     state="API_SECRET Not Set" ; stateString=$state ; stateStringShort=$state
     post_cgm_ns_pill
     exit
  fi
  if [ "$NIGHTSCOUT_HOST" = "" ]; then
     log "NIGHTSCOUT_HOST environment variable is not set"
     log "Make sure the two lines below are in your ~/.bash_profile as follows:\n"
     log "NIGHTSCOUT_HOST=https://xxxx # where xxxx is your hashed Nightscout url"
     log "export NIGHTSCOUT_HOST\n\nexiting\n"
     state_id=0x22
     state="NIGHTSCOUT_HOST Not Set" ; stateString=$state ; stateStringShort=$state
     post_cgm_ns_pill
     exit
  fi

  type bt-device 2> /dev/null || echo "Error: bt-device is not found. Use sudo apt-get install bluez-tools"

}

function ClearCalibrationInput()
{
  if [ -e $calCacheFile ]; then
    cp $calCacheFile "${LDIR}/old-calibrations/calibrations.csv.$(date +%Y%m%d-%H%M%S)" 
    rm $calCacheFile
  fi
}

# we need to save the last calibration for meterbgid checks, throw out the rest
function ClearCalibrationInputOne()
{
  if [ -e $calCacheFile ]; then
    howManyLines=$(wc -l $calCacheFile | awk '{print $1}')
    if [ $(bc <<< "$howManyLines > 1") -eq 1 ]; then
      cp $calCacheFile "${LDIR}/old-calibrations/calibrations.csv.$(date +%Y%m%d-%H%M%S)"
      tail -1 $calCacheFile > ${LDIR}/calibrations.csv.new
      rm $calCacheFile
      mv ${LDIR}/calibrations.csv.new $calCacheFile
    fi
  fi
}

function ClearCalibrationCache()
{
  local cache="$calibrationFile"
  if [ -e ${LDIR}/$cache ]; then
    cp ${LDIR}/$cache "${LDIR}/old-calibrations/${cache}.$(date +%Y%m%d-%H%M%S)" 
    rm ${LDIR}/$cache 
  fi
}

# check utc command line to begin with and use UTC flag for any curls
function check_utc()
{
  if [[ "$utc" == true ]]; then
    UTCString=" -u "
    log "Using UTCString $UTCString"      
  else
    UTC=""
    log "Not Using UTCString"      
  fi
}

function log_status_csv()
{
  file="/var/log/openaps/cgm-status.csv"
  if [ ! -f $file ]; then
    echo "epochdate,datetime,status,voltagea,voltageb,resist,runtime,temperature" > $file 
  fi
  echo "${epochdate},${datetime},${tx_status},${voltagea},${voltageb},${resist},${runtime} days,${temperature} celcuis" >> $file 
}

#called after a battery status update was sent and logger got a response
function check_battery_status()
{

   file="${LDIR}/cgm-battery.json"
   voltagea=$(jq ".voltagea" $file)
   voltageb=$(jq ".voltageb" $file)
   resist=$(jq ".resist" $file)
   runtime=$(jq ".runtime" $file)
   temperature=$(jq ".temperature" $file)
   batteryTimestamp=$(date +%s%3N -r $file)

   if [ "$battery_check" == "Yes" ]; then
     tx_status=$(jq ".status" $file)
     battery_msg="tx_status=$tx_status, voltagea=$voltagea, voltageb=$voltageb, resist=$resist, runtime=$runtime days, temp=$temperature celcius"
    
     echo "[{\"enteredBy\":\"Logger\",\"eventType\":\"Note\",\"notes\":\"Battery $battery_msg\"}]" > ${LDIR}/cgm-battery-status.json
     /usr/local/bin/cgm-post-ns ${LDIR}/cgm-battery-status.json treatments && (echo; log "Upload to NightScout of battery status change worked") || (echo; log "Upload to NS of battery status change did not work")
     log_status_csv
   fi
}


function check_send_battery_status()
 {
   file="${LDIR}/cgm-battery.json"
 
   if [ -e $file ]; then
     if test  `find $file -mmin +720`
     then
       battery_check="Yes"
     fi
   else
       touch $file 
       battery_check="Yes"
   fi
     
   if [ "$battery_check" == "Yes" ]; then
       touch $file 
       battery_date=$(date +'%s%3N')
       batteryJSON="[{\"date\": ${battery_date}, \"type\": \"BatteryStatus\"}]"
       log "Sending Message to Transmitter to request battery status"
   fi
 }

function check_sensor_stop()
{
  if [ "$mode" == "read-only" ]; then
    return
  fi

  file="${LDIR}/nightscout_sensor_stop_treatment.json"
  rm -f $file
  curl --compressed -m 30 -H "API-SECRET: ${API_SECRET}" "${NIGHTSCOUT_HOST}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "3 hours ago" --iso-8601=seconds $UTCString )&find\[eventType\]\[\$regex\]=Sensor.Stop&count=1" 2>/dev/null > $file
  if [ $? == 0 ]; then
    len=$(jq '. | length' $file)
    index=$(bc <<< "$len - 1")

    if [ $(bc <<< "$index >= 0") -eq 1 ]; then
      createdAt=$(jq ".[$index].created_at" $file)
      createdAt="${createdAt%\"}"
      createdAt="${createdAt#\"}"
      if [ ${#createdAt} -ge 8 ]; then
        touch ${LDIR}/nightscout-treatments.log
        if ! cat ${LDIR}/nightscout-treatments.log | egrep "$createdAt"; then
          stop_date=$(date "+%s%3N" -d "$createdAt")
          echo "Processing sensor stop retrieved from Nightscout - stopdate = $createdAt"
          # comment out below line for testing sensor stop without actually sending tx message
          stopJSON="[{\"date\":\"${stop_date}\",\"type\":\"StopSensor\"}]"
          echo "stopJSON = $stopJSON"
          # below done so that next time the egrep returns positive for this specific message and the log reads right
          echo "Already Processed Sensor Stop Message from Nightscout at $createdAt" >> ${LDIR}/nightscout-treatments.log
        fi
      fi
    fi
  fi
}

function check_sensor_start()
{
  if [ "$mode" == "read-only" ]; then
    return
  fi

  file="${LDIR}/nightscout_sensor_start_treatment.json"
  rm -f $file
  curl --compressed -m 30 -H "API-SECRET: ${API_SECRET}" "${NIGHTSCOUT_HOST}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "3 hours ago" --iso-8601=seconds $UTCString )&find\[eventType\]\[\$regex\]=Sensor.Start&count=1" 2>/dev/null > $file
  if [ $? == 0 ]; then
    len=$(jq '. | length' $file)
    index=$(bc <<< "$len - 1")

    if [ $(bc <<< "$index >= 0") -eq 1 ]; then
      createdAt=$(jq ".[$index].created_at" $file)
      createdAt="${createdAt%\"}"
      createdAt="${createdAt#\"}"
      if [ ${#createdAt} -ge 8 ]; then
        touch ${LDIR}/nightscout-treatments.log
        if ! cat ${LDIR}/nightscout-treatments.log | egrep "$createdAt"; then
          sensorSerialCode=$(jq ".[$index].notes" $file) 
          sensorSerialCode="${sensorSerialCode%\"}"
          sensorSerialCode="${sensorSerialCode#\"}"

          start_date=$(date "+%s%3N" -d "$createdAt")
          echo "Processing sensor start retrieved from Nightscout - startdate = $createdAt, sensorCode = $sensorSerialCode"
          # comment out below line for testing sensor start without actually sending tx message
          # always send sensorSerialCode even if it is blank - doesn't matter for g5, but needed
          # for g6
          startJSON="[{\"date\":\"${start_date}\",\"type\":\"StartSensor\",\"sensorSerialCode\":\"${sensorSerialCode}\"}]"
          echo "startJSON = $startJSON"
          # below done so that next time the egrep returns positive for this specific message and the log reads right
          echo "Already Processed Sensor Start Message from Nightscout at $createdAt" >> ${LDIR}/nightscout-treatments.log
          # do not clear in this case because in session sensors could be just doing a quick start 
          # clearing only happens for sensor insert
  
          #update xdripjs.json with new sensor code
          if [ "$sensorSerialCode" != "null" -a "$sensorSerialCode" != "" ]; then  
            config="/root/myopenaps/xdripjs.json"
            if [ -e "$config" ]; then
              tmp=$(mktemp)
              jq --arg sensorSerialCode "$sensorSerialCode" '.sensor_code = $sensorSerialCode' "$config" > "$tmp" && mv "$tmp" "$config"
            fi
          fi

        fi
      fi
    fi
  fi
}

# remove old calibration storage when sensor change occurs
# calibrate after 15 minutes of sensor change time entered in NS
function check_sensor_change()
{
  if [ "$mode" == "read-only" ]; then
    return
  fi


  curl --compressed -m 30 -H "API-SECRET: ${API_SECRET}" "${NIGHTSCOUT_HOST}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "15 minutes ago" --iso-8601=seconds $UTCString )&find\[eventType\]\[\$regex\]=Sensor.Change" 2>/dev/null | grep "Sensor Change"
  if [ $? == 0 ]; then
    log "sensor change within last 15 minutes - clearing calibration files"
    ClearCalibrationInput
    ClearCalibrationCache
    touch ${LDIR}/last_sensor_change
    state_id=0x02
    state="Warmup" ; stateString=$state ; stateStringShort=$state
    post_cgm_ns_pill

    log "exiting"
    exit
  fi

curl --compressed -m 30 -H "API-SECRET: ${API_SECRET}" "${NIGHTSCOUT_HOST}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "15 minutes ago" --iso-8601=seconds $UTCString)&find\[eventType\]\[\$regex\]=Sensor.Stop" 2>/dev/null | grep "Sensor Stop"
  if [ $? == 0 ]; then
    log "sensor stopped within last 15 minutes - clearing calibration files"
    ClearCalibrationInput
    ClearCalibrationCache
    touch ${LDIR}/last_sensor_change
    state_id=0x02
    state="Warmup" ; stateString=$state ; stateStringShort=$state
    post_cgm_ns_pill

    log "exiting"
    exit
  fi

  curl --compressed -m 30 -H "API-SECRET: ${API_SECRET}" "${NIGHTSCOUT_HOST}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "15 minutes ago" --iso-8601=seconds $UTCString)&find\[eventType\]\[\$regex\]=Sensor.Start" 2>/dev/null | grep "Sensor Start"
  if [ $? == 0 ]; then
    log "sensor start within last 15 minutes - clearing calibration files"
    ClearCalibrationInput
    ClearCalibrationCache
    touch ${LDIR}/last_sensor_change
    state_id=0x02
    state="Warmup" ; stateString=$state ; stateStringShort=$state
    post_cgm_ns_pill

    log "exiting"
    exit
  fi
}

function check_last_entry_values()
{
  # RESOLVED: check file stamp for > x for last-entry.json and ignore lastGlucose if older than x minutes
  # if within last 11 minutes
  if test `find $lastEntryFile -mmin -11`
  then
    if [ -e "$lastEntryFile" ] ; then
      lastGlucose=$(cat $lastEntryFile | jq -M '.[0].sgv')
      lastGlucoseDate=$(cat $lastEntryFile | jq -M '.[0].date')
      lastStatus=$(cat $lastEntryFile | jq -M '.[0].status')
      lastStatus="${lastStatus%\"}"
      lastStatus="${lastStatus#\"}"
      lastFiltered=$(cat $lastEntryFile | jq -M '.[0].filtered')
      lastUnfiltered=$(cat $lastEntryFile | jq -M '.[0].unfiltered')
      if [ "$mode" != "expired" ]; then
        lastState=$(cat $lastEntryFile | jq -M '.[0].state')
        lastState="${lastState%\"}"
        lastState="${lastState#\"}"
      fi
      log "check_last_entry_values: lastGlucose=$lastGlucose, lastStatus=$lastStatus, lastState=$lastState"
    fi
  fi
}

function updateCalibrationCache()
{
  local filtered=$1
  local unfiltered=$2
  local meterbg=$3
  local meterbgid=$4
  local datetime=$5      # string form of date/time
  local epochdate=$6     # epoch date in seconds
  local enteredBy=$7

  log "updateCalibrationCache, filtered=$filtered, unfiltered=$unfiltered, meterbg=$meterbg"
  log "                        meterbgid=$meterbgid, datetime=$datetime"
  log "                        epochdate=$epochdate, enteredBy=$enteredBy"

  local variation=0
  local after=$epochdate
  local before=$epochdate
  local f=$calCacheFile

  if [ $(bc <<< "$after > 1") -eq 1 ]; then
    after=$(($epochdate+1))
  fi

  if [ $(bc <<< "$before > 1") -eq 1 ]; then
    before=$(($epochdate-1))
  fi


    # grep txepochdate in to see if this tx calibration is known yet or not
    # The tx reports a time in ms that shifts each and every time, so to be sure
    # to not have duplicates, grep for the second before and second after
  if cat $f | egrep "$epochdate" || cat $f | egrep "$after" || cat $f | egrep "$before"; then
    log "Already processed calibration of $meterbg with id = $epochdate"
    return
  fi

  if cat $f | egrep "$meterbgid"; then
    log "Already processed calibration of $meterbg with id = $meterbgid"
    return
  fi


  if [ "$(validBG $unfiltered)" == "false" ]; then
    log "Calibration of $meterbg not being used due to unfiltered of $unfiltered"
    return
  fi

  # safety check to make sure we don't have wide variance between the meterbg and the unfiltered value
  # Use 1 as slope for safety in this check
  meterbg_delta=$(bc -l <<< "$meterbg - $unfiltered/1")
  # calculate absolute value
  if [ $(bc -l <<< "$meterbg_delta < 0") -eq 1 ]; then
    meterbg_delta=$(bc -l <<< "0 - $meterbg_delta")
  fi
  if [ $(bc -l <<< "$meterbg_delta > 150") -eq 1 ]; then
    log "Raw/unfiltered compared to meterbg is $meterbg_delta > 150, ignoring calibration"
    return
  fi

  variation=$(calc_variation $filtered $unfiltered)
  if [ $(bc <<< "$variation > 10") -eq 1 ]; then
    log "would not allow calibration - filtered/unfiltered variation of $variation exceeds 10%"
    return
  fi

    log "Calibration is new and within bounds - adding to calibrations.csv"
    log "meterbg=$meterbg,datetime=$datetime,epochdate=$epochdate,meterbgid=$meterbgid,filtered=$filtered,unfiltered=$unfiltered"
    echo "$unfiltered,$meterbg,$datetime,$epochdate,$meterbgid,$filtered,$unfiltered,$enteredBy" >> $calCacheFile
    /usr/local/bin/cgm-calc-calibration $calCacheFile $calibrationFile
}

function seen_before()
{
  # pass unique id as arg1 and it will return "No" if not seen before 
  # Optional arg2 that is the application usage for unique id check
  # or "Yes" if it is the first and only time this id has been seen 
  # Remembers up to 200 last unique id
bg=${1:-"null"}     # arg 1 is meter bg value


  local uid=$1
  local app=${2:-"Logger"}
  local processed_before="No"
  local f="${LDIR}/already_processed.txt"
  local t=$(mktemp)
  
  if [ -e $f ]; then
    if cat $f | egrep "$uid"; then
      processed_before="Yes"
    fi
  else
    touch $f
  fi

  if [[ "$processed_before" == "No" ]]; then
    echo "$datetime, seen at least once, $uid, $app" >> $f
  fi
  
  echo $processed_before

  # keep only last 200 seen unique ids
  cp $f $t
  tail -200 $t > $f 
}

function check_tx_calibration()
{
  if [ "$mode" == "read-only" ]; then
    return
  fi

  # TODO: remove - it is likely not necessary anymore
  if [[ "$sentLoggerCalibrationToTx" == true ]]; then
    # This is the reflection of the cmd line based calibration. 
    # Do not process it twice
    return
  fi

  TXCALFILE="${LDIR}/tx-calibration-data.json"

  if [ -e $TXCALFILE ]; then

    txdatetime=$(jq ".date" $TXCALFILE)
    txdatetime="${txdatetime%\"}"
    txdatetime="${txdatetime#\"}"
    txmeterbg=$(jq ".glucose" $TXCALFILE)
    txepochdate=`date --date="$txdatetime" +"%s"`
    txmeterbgid=$txepochdate
    #  calibrations.csv "unfiltered,meterbg,datetime,epochdate,meterbgid,filtered,unfiltered"
    seen=$(seen_before $txepochdate "Calibration from Tx") 
    if [[ "$seen_before" == "No" ]]; then
      log "Tx last calibration of $txmeterbg being considered - id = $txmeterbgid, txdatetime= $txdatetime"
    else
      log "Tx last calibration of $txmeterbg seen before, already processed - id = $txmeterbgid, txdatetime= $txdatetime"
      return
    fi

    epochdateNow=$(date +'%s')

    if [ $(bc <<< "($epochdateNow - $txepochdate) < 420") -eq 1 ]; then
     log "tx meterbg is within 7 minutes so use current filtered/unfiltered values "
     txfiltered=$filtered
     txunfiltered=$unfiltered
    else
     log "tx meterbg is older than 7 minutes so queryfiltered/unfiltered values"
     #  after=$(date -d "15 minutes ago" -Iminutes)
     #  glucosejqstr="'[ .[] | select(.dateString > \"$after\") ]'"
     before=$(bc -l <<< "$txepochdate *1000  + 240*1000")
     after=$(bc -l <<< "$txepochdate *1000  - 240*1000")
     glucosejqstr="'[ .[] | select(.date > $after) | select(.date < $before) ]'"

     bash -c "jq -c $glucosejqstr ~/myopenaps/monitor/glucose.json" > ${LDIR}/test.json
     txunfiltered=( $(jq -r ".[0].unfiltered" ${LDIR}/test.json) )
     txfiltered=( $(jq -r ".[0].filtered" ${LDIR}/test.json) )
    fi

    updateCalibrationCache $txfiltered $txunfiltered $txmeterbg $txmeterbgid "$txdatetime" $txepochdate "Logger-tx"
    # use enteredBy Logger so that 
    # it can be filtered and not reprocessed by Logger again
    readyCalibrationToNS $txdatetime $txmeterbg "Logger-tx"
    postTreatmentsToNS
    rm -f $TXCALFILE
  fi
}


function addToMessages() 
{
  local jsonToAdd=$1
  local resultJSON=""
  local msgFile=$2

  log "addToMessages jsonToAdd=$jsonToAdd"
  
  jqType=$(jq type  <<< "$jsonToAdd")
  if [[ "$jqType" != *"array"* ]]; then
    log "jsonToAdd is not valid = $jsonToAdd"
    return 
  fi
  
  local lengthJSON=${#jsonToAdd} 

  if [ $(bc <<< "$lengthJSON < 2") -eq 1 ]; then
    log "jsonToAdd is not valid too short = $jsonToAdd"
    return
  fi 

  if [ -e $msgFile ]; then
    local stagingFile1=$(mktemp)
    local stagingFile2=$(mktemp)
    echo "$jsonToAdd" > $stagingFile1
    cp $msgFile $stagingFile2
    log "stagingFile2 is below"
    cat $stagingFile2
    log "stagingFile1 is below"
    cat $stagingFile1
      resultJSON=$(jq -c -s add $stagingFile2 $stagingFile1)

  else
     resultJSON=$jsonToAdd
  fi
  
  jqType=$(jq type  <<< "$resultJSON")
  if [[ "$jqType" != *"array"* ]]; then
    log "resultJSON is not valid = $resultJSON"
    return 
  fi

  log "resultJSON=$resultJSON"
  echo "$resultJSON" > $msgFile
}

# TODO: make one of these for start/stop treatments

function readyCalibrationToNS()
{
  # takes a calibration record and puts it in json file for later sending it to NS
  local createDate="$1"
  local meterbg=$2
  local enteredBy="$3"


  # arg1 = createDate in string format T ... Z
  # arg2 = meterbg
  # arg3 = enteredBy 

  calibrationNSFile=$(mktemp)
  stagingFile=$(mktemp)


  log "Setting up to send calibration to NS now if online (or later with backfill)"
  echo "[{\"created_at\":\"$createDate\",\"enteredBy\":\"$enteredBy\",\"reason\":\"sensor calibration\",\"eventType\":\"BG Check\",\"glucose\":$meterbg,\"glucoseType\":\"Finger\",\"units\":\"mg/dl\"}]" > $calibrationNSFile
  cat $calibrationNSFile

  if [ -e $treatmentsFile ]; then
    cp $treatmentsFile $stagingFile
    jq -s add $calibrationNSFile $stagingFile > $treatmentsFile
  else
    cp $calibrationNSFile $treatmentsFile
  fi
}

function generate_uuid()
{
  cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1
}

function  check_cmd_line_calibration()
{
  if [ "$mode" == "read-only" ]; then
    return
  fi
## look for a bg check from ${LDIR}/calibration.json
  if [ -e $CALFILE ]; then
    epochdatems=$(date +'%s%3N')
    if test  `find $CALFILE -mmin -7`
    then
      log "calibration file $CALFILE contents below"
      cat $CALFILE
      echo

      cJSON=$(cat $CALFILE)
      addToMessages "$cJSON" $calibrationMessageFile

      calDateA=( $(jq -r ".[].date" ${CALFILE}) )
      meterbgA=( $(jq -r ".[].glucose" ${CALFILE}) )
      calRecords=${#meterbgA[@]}
      log "Calibration records from command line=$calRecords" 

      # Leverage tx reflection here. The first calibration is the latest one
      # based on how the command line utility does it
      # so process the records in reverse order
      # Consider in the future: use lastFiltered and lastUnfiltered 
      #                         values if they exist, otherwise 
      #                         do LSR here and set variable so that 
      #                         reflective Tx calibration doesn't duplicate
      for (( i=$calRecords-1; i>=0; i-- ))
      do
        calDate=${calDateA[$i]}
        # check the date inside to make sure we don't calibrate using old record
        if [ $(bc <<< "($epochdatems - $calDate)/1000 < 820") -eq 1 ]; then
          calDateSeconds=$(bc  <<< "($calDate / 1000)") # truncate
          meterbg=${meterbgA[$i]}
          meterbgid=$(generate_uuid) 
          log "Calibration of $meterbg from $CALFILE being processed - id = $meterbgid"
          found_meterbg=true
          # put in backfill so that the command line calibration will be sent up to NS 
          # now (or later if offline)
          
          createdAt=$(date $UTCString -d @$calDateSeconds +'%Y-%m-%dT%H:%M:%S.%3NZ')

          if [ $(bc <<< "$lastUnfiltered > 0") -eq 1 ]; then
            updateCalibrationCache $lastFiltered $lastUnfiltered $meterbg $meterbgid "$createdAt" $calDateSeconds "Logger-cmd-line"
            sentLoggerCalibrationToTx=true
          fi
          readyCalibrationToNS $createdAt $meterbg "Logger-cmd-line"
          postTreatmentsToNS
        else
          log "Calibration is too old - not used"
        fi
      done
    fi
    rm -f $CALFILE
    log "meterbg from ${LDIR}/calibration.json: $meterbg"
  fi
}

function  remove_dexcom_bt_pair()
{
  log "Removing existing Dexcom bluetooth connection = ${id}"
  bt-device -r $id 2> /dev/null

  # Also remove the mac address tx pairing if exists 
  sfile="${LDIR}/saw-transmitter.json"

  if [ -e $sfile ]; then
    mac=$(cat $sfile | jq -M '.address')
    mac="${mac%\"}"
    mac="${mac#\"}"
    if [ ${#mac} -ge 8 ]; then
      smac=${mac//:/-}
      smac=${smac^^}
      #echo $smac
      log "Removing existing Dexcom bluetooth mac connection also = ${smac}"
      bt-device -r $smac 2> /dev/null
    fi
  fi
}

function initialize_messages()
{
  stopJSON=""
  startJSON=""
  batteryJSON=""
  resetJSON=""
}

function compile_messages()
{
  if [ "${resetJSON}" != "" ]; then
    addToMessages "$resetJSON" $xdripMessageFile
  fi

  if [ "${stopJSON}" != "" ]; then
    addToMessages "$stopJSON" $xdripMessageFile
  fi
  
  if [ "${startJSON}" != "" ]; then
    addToMessages "$startJSON" $xdripMessageFile
  fi

  if [ "${batteryJSON}" != "" ]; then
    addToMessages "$batteryJSON" $xdripMessageFile
  fi

  if [ -e $calibrationMessageFile ]; then
    local calibrationJSON=$(cat $calibrationMessageFile)
  
    addToMessages "$calibrationJSON" $xdripMessageFile
    rm -f $calibrationMessageFile
  fi


  messages=""
  if [ -e $xdripMessageFile ]; then
    messages=$(cat $xdripMessageFile)
    echo "messages=$messages"
  fi
 
  if [ "$messages" == "" ]; then
    echo "[]" > $xdripMessageFile
    log "clearing out logger to xdrip-js messages"
  fi

}


function  call_logger()
{
  log "Calling xdrip-js ... node logger $transmitter $xdripMessageFile $alternateBluetoothChannel"
  DEBUG=smp,transmitter,bluetooth-manager,backfill-parser
  export DEBUG
#  echo -n "Timezone = "
#  env | grep TZ

  timeout 420 node logger $transmitter $xdripMessageFile $alternateBluetoothChannel
  echo
  local error=""
  log "after xdrip-js bg record below ..."
  if [ -e "${LDIR}/entry.json" ]; then
    cat ${LDIR}/entry.json
    touch ${LDIR}/entry-watchdog
    echo
    glucose=$(cat ${LDIR}/entry.json | jq -M '.[0].glucose')
    unfiltered=$(cat ${LDIR}/entry.json | jq -M '.[0].unfiltered')
    unfiltered=$(bc -l <<< "scale=0; $unfiltered / 1000")
    if [ "$(validBG $unfiltered)" == "false" -a "$(validBG $glucose)" == "false" ]; then
      error="Invalid response - Unf=$unfiltered, gluc=$glucose"
      state_id=0x25
      ls -al ${LDIR}/entry.json
      cat ${LDIR}/entry.json
      rm ${LDIR}/entry.json
    fi
    # remove start/stop message files only if not rebooting and we acted on them
    if [[ -n "$stopJSON" ]]; then  
        rm -f $cgm_stop_file
    fi
    if [[ -n "$startJSON" ]]; then  
        rm -f $cgm_start_file
    fi
  else
    state_id=0x24
    error="No Response" 
    bt_watchdog
  fi
  if [ "$error" != "" ]; then
      state=$error ; stateString=$state ; stateStringShort=$state
      remove_dexcom_bt_pair
      post_cgm_ns_pill
      exit
  fi
}

function  capture_entry_values()
{
  # capture values for use and for log to csv file 
  unfiltered=$(cat ${LDIR}/entry.json | jq -M '.[0].unfiltered')
  filtered=$(cat ${LDIR}/entry.json | jq -M '.[0].filtered')

  # convert data to scale of 1 vs 1000x
  unfiltered=$(bc -l <<< "scale=0; $unfiltered / 1000")
  filtered=$(bc -l <<< "scale=0; $filtered / 1000")
  
  state=$(cat ${LDIR}/entry.json | jq -M '.[0].state')
  state="${state%\"}"
  state="${state#\"}"

  state_id=$(cat ${LDIR}/extra.json | jq -M '.[0].state_id')
  status_id=$(cat ${LDIR}/extra.json | jq -M '.[0].status_id')
  transmitterStartDate=$(cat ${LDIR}/extra.json | jq -M '.[0].transmitterStartDate')
  transmitterStartDate="${transmitterStartDate%\"}"
  transmitterStartDate="${transmitterStartDate#\"}"
  log "transmitterStartDate=$transmitterStartDate" 

  sessionStartDate=$(cat ${LDIR}/extra.json | jq -M '.[0].sessionStartDate')
  sessionStartDate="${sessionStartDate%\"}"
  sessionStartDate="${sessionStartDate#\"}"
  sessionStartDateEpochms=$(cat ${LDIR}/extra.json | jq -M '.[0].sessionStartDateEpoch')
  # make sure to use 7 days for g5 and 10 for g6
  local sessionMaxSeconds=$SECONDS_IN_10_DAYS
  if [ "$txType" == "g5" ]; then
    sessionMaxSeconds=$SECONDS_IN_7_DAYS
  fi

  # check for valid and not expired sessionStartDate
  sessionMinutesRemaining=$(bc <<< "($sessionMaxSeconds - ($epochdate-$sessionStartDateEpochms/1000))/60")
  if [ $(bc <<< "$sessionMinutesRemaining < 0") -eq 1 -a $(bc <<< "$sessionMinutesRemaining > ($sessionMaxSeconds * 60)") -eq 1 ]; then
    log "Expired session or invalid sessionStartDate, not processing auto-restart logic"
  fi
  log "sessionStartDate=$sessionStartDate, sessionStartDateEpochms=$sessionStartDateEpochms" 
  log "sessionMinutesRemaining=$sessionMinutesRemaining"
  if [ $(bc <<< "$sessionMinutesRemaining < 65") -eq 1 ]; then
    if [ $(bc <<< "$glucose < 400") -eq 1  -a $(bc <<< "$glucose > 40") -eq 1 ]; then
      if [ $(bc <<< "$variation < 10") -eq 1 ]; then
        if [[ "$auto_sensor_restart" == true ]]; then
         cgm-stop; sleep 5; cgm-start -m 120; sleep 5; cgm-calibrate $glucose; sleep 61; cgm-calibrate $glucose  
        else
         log "Not sending restart messages - auto_sensor_restart=$auto_sensor_restart"
        fi
      fi
    fi
  fi

  rssi=$(cat ${LDIR}/entry.json | jq -M '.[0].rssi')

  status=$(cat ${LDIR}/entry.json | jq -M '.[0].status')
  status="${status%\"}"
  status="${status#\"}"
  log "Sensor state = $state" 
  log "Transmitter status = $status" 

  orig_status=$status
  orig_state=$state
  orig_status_id=$status_id
  orig_state_id=$state_id

  # get dates for use in filenames and json entries
  datetime=$(date +"%Y-%m-%d %H:%M")
  epochdate=$(date +'%s')
  cp -p ${LDIR}/entry.json $lastEntryFile
}

function checkif_fallback_mode()
{
  fallback=false
  if [ "$mode" == "read-only" ]; then
    return
  fi

  if [ "$mode" != "expired" ]; then
    # did we not get a valid internal tx calibrated glucose
    if [ "$(validBG $glucose)" == "false" ]; then 
      # fallback to try to use unfiltered in this case
      mode="expired"
      fallback=true
      echo "Due to tx calibrated glucose of $glucose, Logger will temporarily fallback to mode=$mode"
    fi
  fi
}

function initialize_mode()
{
  # This is the default so that calibrations from tx generated BG values 
  #  to reflect in LSR in order to make it safer to allow seamless transition to LSR calibration
  mode="native-calibrates-lsr"

  if [[ "$cmd_line_mode" == "expired" ]]; then	
    mode="expired"	
  fi

  if [[ "$cmd_line_mode" == "not-expired" ]]; then	
    mode="not-expired"	
  fi


  if [[ "$cmd_line_mode" == "read-only" ]]; then
    mode="read-only"
  fi
  echo "Logger mode=$mode"
}

function  initialize_calibrate_bg()
{
    calibratedBG=$glucose
    tmp=$(mktemp)
    jq ".[0].sgv = $glucose" ${LDIR}/entry.json > "$tmp" && mv "$tmp" ${LDIR}/entry.json
}

function set_entry_fields()
{
  tmp=$(mktemp)
  jq ".[0].device = \"${transmitter}\"" ${LDIR}/entry.json > "$tmp" && mv "$tmp" ${LDIR}/entry.json
  tmp=$(mktemp)
  jq ".[0].filtered = ${filtered}" ${LDIR}/entry.json > "$tmp" && mv "$tmp" ${LDIR}/entry.json
  tmp=$(mktemp)
  jq ".[0].unfiltered = ${unfiltered}" ${LDIR}/entry.json > "$tmp" && mv "$tmp" ${LDIR}/entry.json
}


function log_cgm_csv()
{
  file="/var/log/openaps/cgm.csv"
  noise_percentage=$(bc <<< "$noise * 100")

  noiseToLog=${noise}
  if [ "$noiseToLog" == "null" -o "$noiseToLog" == "" ]; then
    noiseToLog="Other"
  fi

  if [ ! -f $file ]; then
    echo "epochdate,datetime,unfiltered,filtered,direction,calibratedBG-lsr,cgm-glucose,meterbg,slope,yIntercept,slopeError,yError,rSquared,Noise,NoiseSend,mode,noise*100,sensitivity,rssi" > $file 
  fi
  echo "${epochdate},${datetime},${unfiltered},${filtered},${direction},${calibratedBG},${glucose},${meterbg},${slope},${yIntercept},${slopeError},${yError},${rSquared},${noiseToLog},${noiseSend},${mode},${noise_percentage},${sensitivity},${rssi}" >> $file 
}


function postAnnouncementToNS()
{
  local announcement=$1

  echo "[{\"enteredBy\":\"Logger\",\"eventType\":\"Announcement\",\"notes\":\"$announcement\"}]" > ${LDIR}/status-change.json
  /usr/local/bin/cgm-post-ns ${LDIR}/status-change.json treatments && (echo; log "Upload to NightScout of Announcment worked - $announcement") || (echo; log "Upload of Announcement to NS did not work - $announcement")
}

# if tx state or status changed, then post a note to NS
function process_announcements()
{
  if [ "$state" == "Stopped" ] && [ "$mode" != "expired" ]; then
    log "Not posting glucose to Nightscout or OpenAPS - sensor state is Stopped, unfiltered=$unfiltered"
    postAnnouncementToNS "Sensor Stopped, unfiltered=$unfiltered"
  else
    log "process_announcements: state=$state lastState=$lastState status=$status lastStatus=$lastStatus"
    if [ "$status" != "$lastStatus" ]; then
      postAnnouncementToNS "Tx $status $postAnnouncementToNSAdder"
    fi

    if [ "$state" != "$lastState" ]; then
      postAnnouncementToNS "Sensor $state"
    fi
  fi
}

function check_last_calibration()
{
  if [ "$mode" == "read-only" ]; then
    return
  fi

  if $fallback ; then
    state=$orig_state
    status=$orig_status
    state_id=$orig_state_id
    status_id=$orig_status_id
    return
  fi

   if [ "$mode" == "expired" ]; then
   state="Needs Calibration" ; stateString=$state ; stateStringShort=$state
   state_id=0x07
     if [ -e $calibrationFile ]; then
       if test  `find $calibrationFile -mmin +720`
       then
         log "Last calibration > 12 hours ago, setting sensor state to Needs Calibration"
         : # default of Needs calibration here since last one > 12 hours ago
       else
         log "Last calibration within 12 hours, setting sensor state to OK"
         state="OK" ; stateString=$state ; stateStringShort=$state
         state_id=0x06
       fi
     fi
    fi
}

function check_native_calibrates_lsr()
{
  local file="${LDIR}/native-calibrates-lsr"
  local native_calibrates_lsr_check="No"

  if [ "$mode" == "native-calibrates-lsr" ]; then
   if [ -e $file ]; then
     if test  `find $file -mmin +360`
     then
       native_calibrates_lsr_check="Yes"
     fi
   else
     native_calibrates_lsr_check="Yes"
   fi

    # every 6 hours, calibrate LSR algo. via native dexcom glucose value:
    # (note: _does not_ calibrate tx, since this is only called after the tx comm is over.)
    if [ $(bc <<< "$glucose < 400") -eq 1  -a $(bc <<< "$glucose > 40") -eq 1 ]; then
      if [ $(bc <<< "$variation < 10") -eq 1 ]; then
        if [ "$native_calibrates_lsr_check" == "Yes" ]; then
          meterbg=$glucose
          meterbgid=$(generate_uuid) 
          calDate=$(date +'%s%3N') 
          calDateSeconds=$(date +'%s') 
          log "meterbg from native-calibrates-lsr: $meterbg"
          # datetime has spaces in it and must have quotes around it
          updateCalibrationCache $filtered $unfiltered $meterbg $meterbgid "$datetime" $calDateSeconds "Logger-native-calibrates-lsr"
          postAnnouncementToNS "native-calibrated-lsr $meterbg"
          touch $file 
          sentLoggerCalibrationToTx=true
          found_meterbg=true
        fi
      fi
    fi
  fi
}

# Pump History BG records
#  {
#    "timestamp": "2017-06-07T06:30:09-04:00",
#    "_type": "CalBGForPH",
#    "id": "Ck9JniZnEQ==",
#    "amount": 79,
#    "units": "mgdl"
#  }
#  {
#    "timestamp": "2017-06-07T06:30:09-04:00",
#    "_type": "BGReceived",
#    "id": "PwlJnuZnEcI2Rw==",
#    "link": "C23647",
#    "amount": 79,
#    "units": "mgdl"
#  }
function check_pump_history_calibration()
{
  if [ "$mode" == "read-only" ]; then
    return
  fi

  if [[ "$found_meterbg" == false ]]; then
    historyFile="$HOME/myopenaps/monitor/pumphistory-24h-zoned.json"
    if [ ! -e "$historyFile" ]; then
      # support the old file name in case of older version of OpenAPS
      historyFile="$HOME/myopenaps/monitor/pumphistory-zoned.json"
    fi

    if [ -e "$historyFile" ]; then
      # look for a bg check from pumphistory (direct from meter->openaps):
      # note: pumphistory may not be loaded by openaps very timely...
      meterbgafter=$(date -d "20 minutes ago" -Iminutes)
      meterjqstr="'.[] | select(._type == \"BGReceived\") | select(.timestamp > \"$meterbgafter\")'"
      bash -c "jq $meterjqstr $historyFile" > $METERBG_NS_RAW
      meterbg=$(bash -c "jq .amount $METERBG_NS_RAW | head -1")
      meterbgid=$(bash -c "jq .timestamp $METERBG_NS_RAW | head -1")
      meterbgid="${meterbgid%\"}"
      meterbgid="${meterbgid#\"}"
      # meter BG from pumphistory doesn't support mmol yet - has no units...
      # using arg3 if mmol then convert it
      if [[ "$pumpUnits" == *"mmol"* ]]; then
        meterbg=$(bc <<< "($meterbg *18)/1")
        log "converted pump history meterbg from mmol value to $meterbg"
      fi
      echo
      if [[ -n "$meterbg" && "$meterbg" != "" ]]; then  
        log "meterbg from pumphistory: $meterbg"
        found_meterbg=true
      fi
      calDate=$(date --date="$meterbgid" +"%s%3N")
      # no need to send to NS because OpenAPS does this for us
      #calDate=$(date +'%s%3N') # SOLVED: use pump history date
    fi
  fi
}

function calc_variation()
{
  # arg1 = filtered
  # arg2 = unfiltered

  variationLocal=0
  # check to see if filtered and unfiltered are valid numbers
  # so that the new g6 firmware will still work with a valid glucose
  # and null raw numbers. This means the sensor is in session and will
  # handle noise on its own so zero for variation is fine in this case
  if [ "$(validNumber $1)" == "true" -a "$(validNumber $2)" == "true" ]; then
    if [ $(bc <<< "$1 > 0") -eq 1 ]; then
      variationLocal=$(bc <<< "($1 - $2) * 100 / $1")
      if [ $(bc <<< "$variationLocal < 0") -eq 1 ]; then
        variationLocal=$(bc <<< "0 - $variationLocal")
      fi 
    fi
  fi

  echo $variationLocal
}

function check_variation()
{
  if [ "$mode" == "read-only" ]; then
    return
  fi

  # always calc variation because its value is used elsewhere
  variation=$(calc_variation $filtered $unfiltered)

  if [[ "$found_meterbg" == true ]]; then
    if [ $(bc <<< "$variation > 10") -eq 1 ]; then
      log "would not allow meter calibration - filtered/unfiltered variation of $variation exceeds 10%"
      meterbg=""
    else
      log "filtered/unfiltered variation ok for meter calibration, $variation"
    fi
  fi
}

function check_ns_calibration()
{
  if [ "$mode" == "read-only" ]; then
    return
  fi

  if [[ "$found_meterbg" == false ]]; then
    # can't use the Sensor insert UTC determination for BG since they can
    # be entered in either UTC or local time depending on how they were entered.
    curl --compressed -m 30 -H "API-SECRET: ${API_SECRET}" "${ns_url}/api/v1/treatments.json?find\[eventType\]\[\$regex\]=Check&count=1" 2>/dev/null > $METERBG_NS_RAW
    createdAt=$(jq -r ".[0].created_at" $METERBG_NS_RAW)
    if [ "$createdAt" == "null" ] ; then 
        return
    fi
    secNow=`date +%s`
    secThen=`date +%s --date=$createdAt`
    secThenMs=`date +%s%3N --date=$createdAt`
    elapsed=$(bc <<< "($secNow - $secThen)")
    #log "meterbg date=$createdAt, secNow=$secNow, secThen=$secThen, elapsed=$elapsed"
    if [ $(bc <<< "$elapsed < 540") -eq 1 ]; then
      # note: pumphistory bg has no _id field, but .timestamp matches .created_at
      enteredBy=$(jq ".[0].enteredBy" $METERBG_NS_RAW)
      enteredBy="${enteredBy%\"}"
      enteredBy="${enteredBy#\"}"
      if [[ "$enteredBy" == *"Logger"* ]]; then
        # Logger knows about it already so don't process again
        return
      fi

      meterbgid=$(jq ".[0].created_at" $METERBG_NS_RAW)
      meterbgid="${meterbgid%\"}"
      meterbgid="${meterbgid#\"}"
      meterbgunits=$(cat $METERBG_NS_RAW | jq -M '.[0] | .units')
      meterbg=`jq -M '.[0] .glucose' $METERBG_NS_RAW`
      meterbg="${meterbg%\"}"
      meterbg="${meterbg#\"}"
      if [[ "$meterbgunits" == *"mmol"* ]]; then
        meterbg=$(bc <<< "($meterbg *18)/1")
      fi
      found_meterbg=true
      # nothing to do here except prepare xdrip-js message 
      calDate=$secThenMs
      addToMessages "[{\"date\": ${calDate}, \"type\": \"CalibrateSensor\",\"glucose\": $meterbg}]" $calibrationMessageFile
    log "meterbg from nightscout: $meterbg, date=$calDate"
    else
      # clear old meterbg curl responses
      rm $METERBG_NS_RAW
    fi
  fi
}

#call after posting to NS OpenAPS for not-expired mode
function calculate_calibrations()
{
  # Do not update LSR calibration for read only mode or for invalid unfiltered value
  if [ "$mode" == "read-only" -o "$(validNumber $unfiltered)" == "false" ]; then
    return
  fi

  calibrationDone=0
  if [ -n $meterbg ]; then 
    if [ "$meterbg" != "null" -a "$meterbg" != "" ]; then
      if [ $(bc <<< "$meterbg < 400") -eq 1  -a $(bc <<< "$meterbg > 40") -eq 1 ]; then
        updateCalibrationCache $filtered $unfiltered $meterbg $meterbgid "$datetime" $epochdate "Logger"
        calibrationDone=1
        maxDelta=80
        if [ -e $calibrationFile ]; then
          cat $calibrationFile
          slope=`jq -M '.[0] .slope' $calibrationFile` 
          yIntercept=`jq -M '.[0] .yIntercept' $calibrationFile` 

          log "Posting cal record to NightScout"
          # new calibration record log it to NS
          #slope_div_1000=$(bc -l <<< "scale=2; $slope / 1000")
          #yIntercept_div_1000=$(bc -l <<< "scale=2; $yIntercept / 1000")

          echo "[{\"device\":\"$rig\",\"type\":\"cal\",\"date\":$epochdatems,\"dateString\":\"$dateString\", \"scale\":1,\"intercept\":$yIntercept,\"slope\":$slope}]" > ${LDIR}/cal.json 
          cat ${LDIR}/cal.json
          /usr/local/bin/cgm-post-ns ${LDIR}/cal.json && (echo; log "Upload to NightScout of cal record entry worked";) || (echo; log "Upload to NS of cal record did not work")
        fi
      else 
        log "this calibration was previously recorded - ignoring"
      fi
    fi
  fi
}

function apply_lsr_calibration()
{
  # Do not update LSR calibration for read only mode or for invalid unfiltered value
  if [ "$mode" == "read-only" -o "$(validNumber $unfiltered)" == "false" ]; then
    return
  fi

  if [ -e $calibrationFile ]; then
    #TODO: store calibration date in json file and read here
    slope=`jq -M '.[0] .slope' $calibrationFile`
    yIntercept=`jq -M '.[0] .yIntercept' $calibrationFile`
    slopeError=`jq -M '.[0] .slopeError' $calibrationFile`
    yError=`jq -M '.[0] .yError' $calibrationFile`
    calibrationType=`jq -M '.[0] .calibrationType' $calibrationFile`
    calibrationType="${calibrationType%\"}"
    calibrationType="${calibrationType#\"}"
    numCalibrations=`jq -M '.[0] .numCalibrations' $calibrationFile`
    rSquared=`jq -M '.[0] .rSquared' $calibrationFile`
  else
    if [ "$mode" == "expired" ]; then
      # do not exit here because g6 supports no calibration mode now
      # TODO: determine if g6 and in no-calibration mode somehow and do not set state to First Calibration
      log "no calibration records (mode: expired)"
      state_id=0x04
      state="First Calibration" ; stateString=$state ; stateStringShort=$state
      #post_cgm_ns_pill
      #remove_dexcom_bt_pair
      #exit
    else
      if [ "$mode" != "expired" ]; then
        # exit as there is nothing to calibrate without calibration-linear.json?
        log "no calibration records (mode: $mode)"
        # don't exit here because g6 supports no calibration mode now
        #exit
      fi
    fi
  fi   

  if [ "$yIntercept" != "" -a "$slope" != "" ]; then
    calibratedBG=$(bc -l <<< "($unfiltered - $yIntercept)/$slope")
    calibratedBG=$(bc <<< "($calibratedBG / 1)") # truncate
    log "After calibration calibratedBG =$calibratedBG, slope=$slope, yIntercept=$yIntercept, filtered=$filtered, unfiltered=$unfiltered"
  else
    calibratedBG=0
    if [ "$mode" == "expired" ]; then
      state_id=0x07
      state="Needs Calibration" ; stateString=$state ; stateStringShort=$state
      post_cgm_ns_pill
      remove_dexcom_bt_pair
      log "expired mode with no calibration - exiting"
      exit
    fi
  fi

  # For Single Point calibration, use a calculated corrective intercept
  # for glucose in the range of 70 <= BG < 85
  # per https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4764224
  # AdjustedBG = BG - CI
  # CI = a1 * BG^2 + a2 * BG + a3
  # a1=-0.1667, a2=25.66667, a3=-977.5
  c=$calibratedBG
  log "numCalibrations=$numCalibrations, calibrationType=$calibrationType, c=$c"
  if [ "$calibrationType" = "SinglePoint" ]; then
    log "inside CalibrationType=$calibrationType, c=$c"
    if [ $(bc <<< "$c > 69") -eq 1 -a $(bc <<< "$c < 85") -eq 1 ]; then
      log "SinglePoint calibration calculating corrective intercept"
      log "Before CI, BG=$c"
      calibratedBG=$(bc -l <<< "$c - (-0.16667 * ${c}^2 + 25.6667 * ${c} - 977.5)")
      calibratedBG=$(bc <<< "($calibratedBG / 1)") # truncate
      log "After CI, BG=$calibratedBG"
    else
      log "Not using CI because bg not in [70-84]"
    fi
  fi

  if [ -z $calibratedBG ]; then
    # Outer calibrated BG boundary checks - exit and don't send these on to Nightscout / openaps
    if [ $(bc <<< "$calibratedBG > 600") -eq 1 -o $(bc <<< "$calibratedBG < 0") -eq 1 ]; then
      if [ "$mode" == "expired" ]; then
        log "Glucose $calibratedBG out of range [0,600] - exiting"
        #state_id=0x07
        #state="Needs Calibration" ; stateString=$state ; stateStringShort=$state
        state_id=0x20
        state="LSR Calibrated BG Out of Bounds" ; stateString=$state ; stateStringShort=$state
        post_cgm_ns_pill
        remove_dexcom_bt_pair
        exit
      fi
    fi
  fi

  # Inner Calibrated BG boundary checks for case > 400
  if [ $(bc <<< "$calibratedBG > 400") -eq 1 ]; then
    log "Glucose $calibratedBG over 400; BG value of HI will show in Nightscout"
    calibratedBG=401
  fi

  # Inner Calibrated BG boundary checks for case < 40
  if [ $(bc <<< "$calibratedBG < 40") -eq 1 ]; then
    log "Glucose $calibratedBG < 40; BG value of LO will show in Nightscout"
    calibratedBG=39
  fi
}

function post_cgm_ns_pill()
{
   # json required conversion to decimal values

   local cache="$calibrationFile"
   if [ -e $cache ]; then
     lastCalibrationDate=$(stat -c "%Y000" ${cache})
   fi

   # Dont send tx activation date to NS CGM pill if state is invalid
   if [[ $state_id != 0x25 ]]; then
     txActivation=`date +'%s%3N' -d "$transmitterStartDate"`
     # logic to check if tx age > 90 days and append to state string if so ...
     if [ "$(validBG $glucose)" == "false" -a "$(validBG $unfiltered)" == "false" ]; then
       if [ $(bc -l <<< "($epochdatems - $txActivation)/($SECONDS_IN_1_DAY * 1000) > 90") -eq 1 ]; then
       state="${state}-tx-expired"
       fi
     fi
   fi
   xrig="xdripjs://$(hostname)"
   state_id=$(echo $(($state_id)))
   status_id=$(echo $(($status_id)))
   if [ "$mode" == "read-only" ]; then
     state=$orig_state
     status=$orig_status
     state_id=$orig_state_id
     status_id=$orig_status_id
   fi

   jstr="$(build_json \
      sessionStart "$sessionStartDate" \
    state "$state_id" \
    txStatus "$status_id" \
    stateString "$state" \
    stateStringShort "$state" \
    txId "$transmitter" \
    txActivation "$txActivation" \
    txStatusString "$status" \
    txStatusStringShort "$status" \
    mode "$mode" \
    timestamp "$epochdatems" \
    rssi "$rssi" \
    unfiltered "$unfiltered" \
    filtered "$filtered" \
    noise "$noise" \
    noiseString "$noiseString" \
    lastCalibrationDate "$lastCalibrationDate" \
    slope "$slope" \
    intercept "$yIntercept" \
    calType "$calibrationType" \
    batteryTimestamp "$batteryTimestamp" \
    voltagea "$voltagea" \
    voltageb "$voltageb" \
    temperature "$temperature" \
    resistance "$resist"
    )"

   pill="[{\"device\":\"$xrig\",\"xdripjs\": $jstr, \"created_at\":\"$dateString\"}] "

   echo $pill > ${LDIR}/cgm-pill.json

   /usr/local/bin/cgm-post-ns ${LDIR}/cgm-pill.json devicestatus && (echo; log "Upload to NightScout of cgm status pill record entry worked";) || (echo; log "Upload to NS of cgm status pill record did not work")
}

function process_delta()
{

  if [ -z $lastGlucose -o $(bc <<< "$lastGlucose < 40") -eq 1 ] ; then
    dg=0
  else
    dg=$(bc <<< "$calibratedBG - $lastGlucose")
  fi
  log "calibratedBG=$calibratedBG, lastGlucose=$lastGlucose, dg=$dg"

  # begin try out averaging last two entries ...
  da=$dg
  if [ -n $da -a $(bc <<< "$da < 0") -eq 1 ]; then
    da=$(bc <<< "0 - $da")
  fi

  cp ${LDIR}/entry.json ${LDIR}/entry-before-calibration.json

  tmp=$(mktemp)
  jq ".[0].glucose = $calibratedBG" ${LDIR}/entry.json > "$tmp" && mv "$tmp" ${LDIR}/entry.json

  tmp=$(mktemp)
  jq ".[0].sgv = $calibratedBG" ${LDIR}/entry.json > "$tmp" && mv "$tmp" ${LDIR}/entry.json

  tmp=$(mktemp)
  jq ".[0].device = \"${transmitter}\"" ${LDIR}/entry.json > "$tmp" && mv "$tmp" ${LDIR}/entry.json


  direction='NONE'
  trend=0

  # Begin trend calculation logic based on last 15 minutes glucose delta average
  if [ -z "$dg" ]; then
    direction="NONE"
    log "setting direction=NONE because dg is null, dg=$dg"
  else
    usedRecords=0
    totalDelta=0
    # Don't use files to store delta's anymore. Use monitor/glucose.json in order to 
    # be able to support multiple rigs running openaps / Logger at same time. 

    #  after=$(date -d "15 minutes ago" -Iminutes)
    #  glucosejqstr="'[ .[] | select(.dateString > \"$after\") ]'"
    epms15=$(bc -l <<< "$epochdate *1000  - 900000")
    glucosejqstr="'[ .[] | select(.date > $epms15) ]'"
    bash -c "jq -c $glucosejqstr ~/myopenaps/monitor/glucose.json" > ${LDIR}/last15minutes.json
    last3=( $(jq -r ".[].sgv" ${LDIR}/last15minutes.json) )
    date3=( $(jq -r ".[].date" ${LDIR}/last15minutes.json) )
    #log ${last3[@]}

    usedRecords=${#last3[@]}
    totalDelta=$dg

    for (( i=1; i<$usedRecords; i++ ))
    do
      #log "before totalDelta=$totalDelta, last3[i-1]=${last3[$i-1]}, last3[i]=${last3[$i]}"
      if [ $(bc <<< "${last3[$i]} > 20") -eq 1 -a $(bc <<< "${last3[$i-1]} > 20") -eq 1 ]; then
        totalDelta=$(bc <<< "$totalDelta + (${last3[$i-1]} - ${last3[$i]})")
        #log "after totalDelta=$totalDelta"
      else
       # for null/bad glucose value in last 3 - leave trend to default which is none or unkown
        usedRecords=0  
      fi
    done

    if [ $(bc <<< "$usedRecords > 0") -eq 1 ]; then
      numMinutes=$(bc -l <<< "($epochdate-(${date3[$usedRecords-1]}/1000))/60")
      perMinuteAverageDelta=$(bc -l <<< "$totalDelta / $numMinutes")
      log "direction calculation based on $numMinutes minutes"
      log "perMinuteAverageDelta=$perMinuteAverageDelta"

      if (( $(bc <<< "$perMinuteAverageDelta > 3") )); then
        direction='DoubleUp'
        trend=1
      elif (( $(bc <<< "$perMinuteAverageDelta > 2") )); then
        direction='SingleUp'
        trend=2
      elif (( $(bc <<< "$perMinuteAverageDelta > 1") )); then
        direction='FortyFiveUp'
        trend=3
      elif (( $(bc <<< "$perMinuteAverageDelta < -3") )); then
        direction='DoubleDown'
        trend=7
      elif (( $(bc <<< "$perMinuteAverageDelta < -2") )); then
        direction='SingleDown'
        trend=6
      elif (( $(bc <<< "$perMinuteAverageDelta < -1") )); then
        direction='FortyFiveDown'
        trend=5
      else
        direction='Flat'
        trend=4
      fi
    fi
  fi

  log "perMinuteAverageDelta=$perMinuteAverageDelta, totalDelta=$totalDelta, usedRecords=$usedRecords"
  log "Gluc=${calibratedBG}, last=${lastGlucose}, diff=${dg}, dir=${direction}"

  cat ${LDIR}/entry.json | jq ".[0].direction = \"$direction\"" > ${LDIR}/entry-xdrip.json

  tmp=$(mktemp)
  jq ".[0].trend = $trend" ${LDIR}/entry-xdrip.json > "$tmp" && mv "$tmp" ${LDIR}/entry-xdrip.json
}

function calculate_noise()
{
  noise_input="${LDIR}/noise-input41.csv"
  truncate -s 0 ${noise_input}

  # calculate the noise and position it for updating the entry sent to NS and xdripAPS
  # get last 41 minutes (approx 7 BG's) from monitor/glucose to better support multiple rigs
  # be able to support multiple rigs running openaps / Logger at same time. 
  epms41=$(bc -l <<< "$epochdate *1000  - 41*60000")
  glucosejqstr="'[ .[] | select(.date > $epms41) | select(.unfiltered > 0) ]'"
  bash -c "jq -c $glucosejqstr ~/myopenaps/monitor/glucose.json" > ${LDIR}/last41minutes.json
  date41=( $(jq -r ".[].date" ${LDIR}/last41minutes.json) )
  gluc41=( $(jq -r ".[].glucose" ${LDIR}/last41minutes.json) )
  unf41=( $(jq -r ".[].unfiltered" ${LDIR}/last41minutes.json) )
  fil41=( $(jq -r ".[].filtered" ${LDIR}/last41minutes.json) )

  usedRecords=${#gluc41[@]}
  log "usedRecords=$usedRecords last 41 minutes = ${gluc41[@]}"

  for (( i=$usedRecords-1; i>=0; i-- ))
  do
    dateSeconds=$(bc <<< "${date41[$i]} / 1000")
    echo "$dateSeconds,${unf41[$i]},${fil41[$i]},${gluc41[$i]}" >> ${noise_input}
  done
  echo "${epochdate},${unfiltered},${filtered},${calibratedBG}" >> ${noise_input}

  cgm-calc-noise ${noise_input} 

  if [ -e ${LDIR}/noise.json ]; then
    noise=`jq -M '.[0] .noise' ${LDIR}/noise.json` 
    noiseSend=`jq -M '.[0] .noiseSend' ${LDIR}/noise.json` 
    noiseString=`jq -M '.[0] .noiseString' ${LDIR}/noise.json` 
    noiseString="${noiseString%\"}"
    noiseString="${noiseString#\"}"
    # remove issue where jq returns scientific notation, convert to decimal
    noise=$(awk -v noise="$noise" 'BEGIN { printf("%.2f", noise) }' </dev/null)
  fi

  if [[ $noiseSend < 2 && $orig_state != "OK" && $orig_state != *"alibration"* && $orig_state != "Warmup" && $orig_state != "Stopped" ]]; then
      noiseSend=2  
      noiseString="Light"
      log "setting noise to $noiseString because of tx status of $orig_state"
  fi

  if [ "$(validBG $glucose)" == "true" ]; then
    # tx will not give a valid glucose if noisy
    noiseSend=1
    noiseString="Clean"
    log "setting noise to $noiseString because tx supplied a valid glucose of $glucose"
  fi

  tmp=$(mktemp)
  jq ".[0].noise = $noiseSend" ${LDIR}/entry-xdrip.json > "$tmp" && mv "$tmp" ${LDIR}/entry-xdrip.json
}

function check_messages()
{
  cgm_stop_file="${LDIR}/cgm-stop.json"
  if [ -e "$cgm_stop_file" ]; then
    stopJSON=$(cat $cgm_stop_file)
    log "stopJSON=$stopJSON"
    # wait to remove command line file after call_logger (Tx/Rx processing)
  fi

  cgm_start_file="${LDIR}/cgm-start.json"
  if [ -e "$cgm_start_file" ]; then
    startJSON=$(cat $cgm_start_file)
    log "startJSON=$startJSON"
    #TODO: add cmd line treatments to NS

    # wait to remove command line file after call_logger (Tx/Rx processing)
  fi

  file="${LDIR}/cgm-reset.json"
  if [ -e "$file" ]; then
    resetJSON=$(cat $file)
    log "resetJSON=$resetJSON"
    rm -f $file
  fi
}

function check_recent_sensor_insert()
{
  if [ "$mode" == "read-only" ]; then
    return
  fi

  # check if sensor inserted in last 12 hours.
  # If so, clear calibration inputs and only calibrate using single point calibration
  # do not keep the calibration records within the first 12 hours as they might skew LSR
  if [ -e ${LDIR}/last_sensor_change ]; then
    if test  `find ${LDIR}/last_sensor_change -mmin -720`
    then
      log "sensor change within last 12 hours - will use single pt calibration"
      ClearCalibrationInputOne
    fi
  fi
}

function  post-nightscout-with-backfill()
{
  #if [ "$state" == "Stopped" ]; then
    # don't post glucose to NS
    #return
  #fi

  
  if [ -e "${LDIR}/entry-backfill2.json" ] ; then
    /usr/local/bin/cgm-post-ns ${LDIR}/entry-backfill2.json && (echo; log "Upload backfill2 to NightScout worked ... removing ${LDIR}/entry-backfill2.json"; rm -f ${LDIR}/entry-backfill2.json) || (echo; log "Upload backfill to NS did not work ... keeping for upload when network is restored ... Auth to NS may have failed; ensure you are using hashed API_SECRET in ~/.bash_profile";)
  fi

  if [ -e "${LDIR}/entry-backfill.json" ] ; then
    # In this case backfill records not yet sent to Nightscout
    jq -s add ${LDIR}/entry-xdrip.json ${LDIR}/entry-backfill.json > ${LDIR}/entry-ns.json
    cp ${LDIR}/entry-ns.json ${LDIR}/entry-backfill.json
    log "${LDIR}/entry-backfill.json exists, so setting up for backfill"
  else
    log "${LDIR}/entry-backfill.json does not exist so no backfill"
    cp ${LDIR}/entry-xdrip.json ${LDIR}/entry-ns.json
  fi

  log "Posting blood glucose to NightScout"
  /usr/local/bin/cgm-post-ns ${LDIR}/entry-ns.json && (echo; log "Upload to NightScout of xdrip entry worked ... removing ${LDIR}/entry-backfill.json"; rm -f ${LDIR}/entry-backfill.json) || (echo; log "Upload to NS of xdrip entry did not work ... saving for upload when network is restored ... Auth to NS may have failed; ensure you are using hashed API_SECRET in ~/.bash_profile"; cp ${LDIR}/entry-ns.json ${LDIR}/entry-backfill.json)
  echo

  postTreatmentsToNS
}

function postTreatmentsToNS()
{
  if [ -e "$treatmentsFile" ]; then
    log "Posting treatments to NightScout"
    /usr/local/bin/cgm-post-ns $treatmentsFile treatments && (echo; log "Upload to NightScout of xdrip treatments worked ... removing $treatmentsFile"; rm -f $treatmentsFile) || (echo; log "Upload to NS of xdrip entry did not work ... saving treatments for upload when network is restored ... Auth to NS may have failed; ensure you are using hashed API_SECRET in ~/.bash_profile")
    echo
  fi
}

function wait_with_echo()
{
  total_wait_remaining=$1
  waited_so_far=0
  
  while [ $(bc <<< "$total_wait_remaining >= 10") -eq 1 ]    
  do
    echo -n "."
    sleep 10 
    total_wait_remaining=$(bc <<< "$total_wait_remaining - 10")
  done

  if [ $(bc <<< "$total_wait_remaining >= 1") -eq 1 ]; then    
    sleep $total_wait_remaining 
  fi
  echo
  log "Wait complete"
}

function check_last_glucose_time_smart_sleep()
{
  rm -f $xdripMessageFile

  if [ -e ${LDIR}/entry-watchdog ]; then
    entry_timestamp=$(date -r ${LDIR}/entry-watchdog +'%s')
    seconds_since_last_entry=$(bc <<< "$epochdate - $entry_timestamp")
    log "check_last_glucose_time - epochdate=$epochdate,  entry_timestamp=$entry_timestamp"
    log "Time since last glucose entry in seconds = $seconds_since_last_entry seconds"
    sleep_time=$(bc <<< "180 - $seconds_since_last_entry") 
    if [ $(bc <<< "$sleep_time > 0") -eq 1 -a $(bc <<< "$sleep_time < 180") -eq 1 ]; then
      log "Waiting $sleep_time seconds because glucose records only happen every 5 minutes"
      wait_with_echo $sleep_time
    elif [ $(bc <<< "$sleep_time < -60") -eq 1 ]; then
      # FIXME: maybe this sholud go in a seperate function not related to sleep
      backfill_start=${lastGlucoseDate}
      [[ $backfill_start == 0 ]] && backfill_start=$(date "+%s%3N" -d @"$entry_timestamp")
      # add one minute to the backfill_start to avoid duplicating the last seen entry
      backfill_start=$(bc <<< "$backfill_start + 60 * 1000")

      log "Adding backfill message since $backfill_start"
      addToMessages "[{\"date\":\"${backfill_start}\",\"type\":\"Backfill\"}]" $xdripMessageFile
    fi
  else
    log "More than 4 minutes since last glucose entry, continue processing without waiting"
  fi
}

function check_sensitivity()
{
  sensitivity=$(jq .ratio ${HOME}/myopenaps/settings/autosens.json)
}

function bt_watchdog()
{
  logfiledir=/var/log/openaps
  logfilename=logger-reset-log.txt
  minutes=14
  xdrip_errors=`find ${LDIR} -mmin -$minutes -type f -name entry-watchdog; find $logfiledir -mmin -$minutes -type f -name $logfilename`
  if [ -z "$xdrip_errors" ]
  then
    logfile=$logfiledir/$logfilename
    date >> $logfile
    echo "no entry.json for $minutes minutes" | tee -a $logfile
    if [[ "$watchdog" == true ]]; then
      echo "Rebooting" | tee -a $logfile
      wall "Rebooting in 15 seconds to fix BT and xdrip-js - save your work quickly!"
      cd ${HOME}/myopenaps && /etc/init.d/cron stop && killall -g openaps ; killall -g oref0-pump-loop | tee -a $logfile
      sleep 15
      reboot
    else
      echo "Not rebooting because watchdog preference is false" | tee -a $logfile
    fi
  fi
}

main "$@"
