#!/bin/bash

main()
{
  log "Starting Logger"

  cd /root/src/xdrip-js-logger
  LDIR="${HOME}/myopenaps/monitor/logger"
  mkdir -p ${LDIR}
  mkdir -p ${LDIR}/old-calibrations

# Cmd line args - transmitter $1 is 6 character tx serial number
  transmitter=$1
  meterid=${2:-"000000"}
  pumpUnits=${3:-"mg/dl"}

  id2=$(echo "${transmitter: -2}")
  id="Dexcom${id2}"
  glucoseType="unfiltered"
  noiseSend=0 # default unknown
  UTC=" -u "
  lastGlucose=0
  messages="[]"
  calibrationJSON=""
  epochdate=$(date +'%s')
  ns_url="${NIGHTSCOUT_HOST}"
  METERBG_NS_RAW="meterbg_ns_raw.json"
  battery_check="No" # default - however it will be changed to Yes every 12 hours
  sensitivty=0


  initialize_messages
  check_environment
  check_utc

  check_last_glucose_time_smart_sleep

  # clear out prior curl or tx responses
  rm -f $METERBG_NS_RAW 
  rm -f ${LDIR}/entry.json

  check_sensor_change
  check_sensitivity

  check_send_battery_status
  check_sensor_start
  check_last_entry_values

# begin calibration logic - look for calibration from NS, use existing calibration or none
  maxDelta=30
  check_cmd_line_calibration
  check_pump_history_calibration
  check_ns_calibration
  check_messages

  remove_dexcom_bt_pair
  compile_messages
  call_logger
  capture_entry_values
  set_glucose_type
  set_mode

  log "Mode = $mode"
  # not sure if we need a "dual" mode
  if [[ "$mode" == "not-expired" || $"$mode" == "dual" ]]; then
    initialize_calibrate_bg 
  fi
  set_entry_device_id


  check_variation
  #call after posting to NS OpenAPS for not-expired mode
  if [ "$mode" == "expired" ]; then
    calculate_calibrations
  fi

  check_recent_sensor_insert


  if [ "$mode" == expired ]; then
    apply_lsr_calibration 
  fi

  # necessary for not-expired mode - ok for both modes 
  cp ${LDIR}/entry.json ${LDIR}/entry-xdrip.json

  process_delta # call for all modes 
  calculate_noise # necessary for all modes

  fake_meter

  if [ "$mode" != "Stopped" ]; then
    log "Posting glucose record to xdripAPS / OpenAPS"
    /usr/local/bin/g5-post-xdrip ${LDIR}/entry-xdrip.json
  fi

  post-nightscout-with-backfill
  cp ${LDIR}/entry-xdrip.json ${LDIR}/last-entry.json

  if [ "$mode" == "not-expired" ]; then
    log "Calling expired tx lsr calcs (after posting) -allows mode switches / comparisons" 
    calculate_calibrations
    apply_lsr_calibration 
  fi

  check_battery_status

  log_g5_csv

  process_announcements

  remove_dexcom_bt_pair
  log "Completed Logger"
  echo
}

function log
{
  echo -e "$(date +'%m/%d %H:%M:%S') $*"
}

function fake_meter()
{
  if [ -e "/usr/local/bin/fakemeter" ]; then
    export MEDTRONIC_PUMP_ID=`grep serial ~/myopenaps/pump.ini | tr -cd 0-9`
    export MEDTRONIC_FREQUENCY=`cat ~/myopenaps/monitor/medtronic_frequency.ini`
    if ! listen -t 4s >& /dev/null ; then 
      log "Sending BG of $calibratedBG to pump via meterid $meterid"
      fakemeter -m $meterid  $calibratedBG 
    else
      log "Timed out trying to send BG of $calibratedBG to pump via meterid $meterid"
    fi
  fi
}


# Check required environment variables
function check_environment
{
  source ~/.bash_profile
  export API_SECRET
  export NIGHTSCOUT_HOST
  if [ "$API_SECRET" = "" ]; then
     log "API_SECRET environment variable is not set"
     log "Make sure the two lines below are in your ~/.bash_profile as follows:\n"
     log "API_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxx # where xxxx is your hashed NS API_SECRET"
     log "export API_SECRET\n\nexiting\n"
     exit
  fi
  if [ "$NIGHTSCOUT_HOST" = "" ]; then
     log "NIGHTSCOUT_HOST environment variable is not set"
     log "Make sure the two lines below are in your ~/.bash_profile as follows:\n"
     log "NIGHTSCOUT_HOST=https://xxxx # where xxxx is your hashed Nightscout url"
     log "export NIGHTSCOUT_HOST\n\nexiting\n"
     exit
  fi
}

function ClearCalibrationInput()
{
  if [ -e ${LDIR}/calibrations.csv ]; then
    cp ${LDIR}/calibrations.csv "${LDIR}/old-calibrations/calibrations.csv.$(date +%Y%m%d-%H%M%S)" 
    rm ${LDIR}/calibrations.csv
  fi
}

# we need to save the last calibration for meterbgid checks, throw out the rest
function ClearCalibrationInputOne()
{
  if [ -e ${LDIR}/calibrations.csv ]; then
    howManyLines=$(wc -l ${LDIR}/calibrations.csv | awk '{print $1}')
    if [ $(bc <<< "$howManyLines > 1") -eq 1 ]; then
      cp ${LDIR}/calibrations.csv "${LDIR}/old-calibrations/calibrations.csv.$(date +%Y%m%d-%H%M%S)"
      tail -1 ${LDIR}/calibrations.csv > ${LDIR}/calibrations.csv.new
      rm ${LDIR}/calibrations.csv
      mv ${LDIR}/calibrations.csv.new ${LDIR}/calibrations.csv
    fi
  fi
}

function ClearCalibrationCache()
{
  local cache="${LDIR}/calibration-linear.json"
  if [ -e $cache ]; then
    cp $cache "${LDIR}/old-calibrations/${cache}.$(date +%Y%m%d-%H%M%S)" 
    rm $cache 
  fi
}

# check UTC to begin with and use UTC flag for any curls
function check_utc()
{
  curl --compressed -m 30 "${NIGHTSCOUT_HOST}/api/v1/treatments.json?count=1&find\[created_at\]\[\$gte\]=$(date -d "2400 hours ago" -Ihours -u)&find\[eventType\]\[\$regex\]=Sensor.Change" 2>/dev/null  > ${LDIR}/testUTC.json  
  if [ $? == 0 ]; then
    createdAt=$(jq ".[0].created_at" ${LDIR}/testUTC.json)
    if [ ${#createdAt} -le 4 ]; then
      log "You must record a \"Sensor Insert\" in Nightscout before Logger will run" 
      log "exiting\n"
      exit
    elif [[ $createdAt == *"Z"* ]]; then
      UTC=" -u "
      log "NS is using UTC $UTC"      
    else
      UTC=""
      log "NS is not using UTC $UTC"      
    fi
  fi
}

function log_g5_status_csv()
{
  file="/var/log/openaps/g5-status.csv"
  if [ ! -f $file ]; then
    echo "epochdate,datetime,status,voltagea,voltageb,resist,runtime,temperature" > $file 
  fi
  echo "${epochdate},${datetime},${g5_status},${voltagea},${voltageb},${resist},${runtime} days,${temperature} celcuis" >> $file 
}

#called after a battery status update was sent and logger got a response
function check_battery_status()
{

   if [ "$battery_check" == "Yes" ]; then
     file="${LDIR}/g5-battery.json"
     g5_status=$(jq ".status" $file)
     voltagea=$(jq ".voltagea" $file)
     voltageb=$(jq ".voltageb" $file)
     resist=$(jq ".resist" $file)
     runtime=$(jq ".runtime" $file)
     temperature=$(jq ".temperature" $file)
     battery_msg="g5_status=$g5_status, voltagea=$voltagea, voltageb=$voltageb, resist=$resist, runtime=$runtime days, temp=$temperature celcius"
    
     echo "[{\"enteredBy\":\"Logger\",\"eventType\":\"Note\",\"notes\":\"Battery $battery_msg\"}]" > ${LDIR}/g5-battery-status.json
     /usr/local/bin/g5-post-ns ${LDIR}/g5-battery-status.json treatments && (echo; log "Upload to NightScout of battery status change worked") || (echo; log "Upload to NS of battery status change did not work")
     log_g5_status_csv

   fi
}

function check_send_battery_status()
 {
   file="${LDIR}/g5-battery.json"
 
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

function check_sensor_start()
{
  if [ "$mode" == "expired" ];then
    # can't start sensor on an expired tx
    return
  fi

  file="${LDIR}/nightscout_sensor_start_treatment.json"
  rm -f $file
  curl --compressed -m 30 "${NIGHTSCOUT_HOST}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "3 hours ago" -Ihours $UTC)&find\[eventType\]\[\$regex\]=Sensor.Start" 2>/dev/null > $file
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
          start_date=$(date "+%s%3N" -d "$createdAt")
          echo "Processing sensor start retrieved from Nightscout - startdate = $createdAt"
          # comment out below line for testing sensor start without actually sending tx message
          startJSON="[{\"date\":\"${start_date}\",\"type\":\"StartSensor\"}]"
          echo "startJSON = $startJSON"
          # below done so that next time the egrep returns positive for this specific message and the log reads right
          echo "Already Processed Sensor Start Message from Nightscout at $createdAt" >> ${LDIR}/nightscout-treatments.log
          # clear in this case? not sure
          #ClearCalibrationInput
          #ClearCalibrationCache
          #touch ${LDIR}/last_sensor_change
        fi
      fi
    fi
  fi
}

# remove old calibration storage when sensor change occurs
# calibrate after 15 minutes of sensor change time entered in NS
function check_sensor_change()
{
  curl --compressed -m 30 "${NIGHTSCOUT_HOST}/api/v1/treatments.json?find\[created_at\]\[\$gte\]=$(date -d "15 minutes ago" -Iminutes $UTC)&find\[eventType\]\[\$regex\]=Sensor.Change" 2>/dev/null | grep "Sensor Change"
  if [ $? == 0 ]; then
    log "sensor change within last 15 minutes - clearing calibration files"
    ClearCalibrationInput
    ClearCalibrationCache
    touch ${LDIR}/last_sensor_change
    log "exiting"
    exit
  fi
}

function check_last_entry_values()
{
  # TODO: check file stamp for > x for last-entry.json and ignore lastGlucose if older than x minutes
  if [ -e "${LDIR}/last-entry.json" ] ; then
    lastGlucose=$(cat ${LDIR}/last-entry.json | jq -M '.[0].sgv')
    lastState=$(cat ${LDIR}/last-entry.json | jq -M '.[0].state')
    lastStatus=$(cat ${LDIR}/last-entry.json | jq -M '.[0].status')
    lastStatus="${lastStatus%\"}"
    lastStatus="${lastStatus#\"}"
    lastState="${lastState%\"}"
    lastState="${lastState#\"}"
    log "lastGlucose=$lastGlucose, lastStatus=$lastStatus, lastState=$lastState"
  else
    log "${LDIR}/last-entry.json not available, lastGlucose=0"
  fi
}



function  check_cmd_line_calibration()
{
## look for a bg check from ${LDIR}/calibration.json
  if [ -z $meterbg ]; then
    CALFILE="${LDIR}/calibration.json"
    if [ -e $CALFILE ]; then
      if test  `find $CALFILE -mmin -7`
      then
        log "calibration file $CALFILE contents below"
        cat $CALFILE
        echo
        calDate=$(jq ".[0].date" $CALFILE)
        # check the date inside to make sure we don't calibrate using old record
        if [ $(bc <<< "($epochdate - $calDate) < 420") -eq 1 ]; then
          calDate=$(jq ".[0].date" $CALFILE)
          meterbg=$(jq ".[0].glucose" $CALFILE)
          meterbgid=$(jq ".[0].dateString" $CALFILE)
          meterbgid="${meterbgid%\"}"
          meterbgid="${meterbgid#\"}"
          units=$(jq ".[0].units" $CALFILE)
          if [[ "$units" == *"mmol"* ]]; then
            meterbg=$(bc <<< "($meterbg *18)/1")
            log "converted OpenAPS meterbg from mmol value to $meterbg"
          fi
          log "Calibration of $meterbg from $CALFILE being processed - id = $meterbgid"
          # put in backfill so that the command line calibration will be sent up to NS 
          # now (or later if offline)
          log "Setting up to send calibration to NS now if online (or later with backfill)"
          echo "[{\"created_at\":\"$meterbgid\",\"enteredBy\":\"Logger\",\"reason\":\"sensor calibration\",\"eventType\":\"BG Check\",\"glucose\":$meterbg,\"glucoseType\":\"Finger\",\"units\":\"mg/dl\"}]" > ${LDIR}/calibration-backfill.json
          cat ${LDIR}/calibration-backfill.json
          jq -s add ${LDIR}/calibration-backfill.json ${LDIR}/treatments-backfill.json > ${LDIR}/treatments-backfill.json
        else
          log "Calibration bg over 7 minutes - not used"
        fi
      fi
      rm $CALFILE
    fi
  fi
  log "meterbg from ${LDIR}/calibration.json: $meterbg"
}

function  remove_dexcom_bt_pair()
{
  log "Removing existing Dexcom bluetooth connection = ${id}"
  bt-device -r $id 2> /dev/null
}

function initialize_messages()
{
  calibrationJSON=""
  stopJSON=""
  startJSON=""
  batteryJSON=""
  resetJSON=""
}

function compile_messages()
{
  files=""
  mfile="${LDIR}/messages.json"
  touch $mfile
  cp ${mfile} "${mfile}.last"
  rm -f $mfile
  touch $mfile
  
  if [ "${calibrationJSON}" != "" ]; then
    tmp=$(mktemp)
    echo "${calibrationJSON}" > $tmp
    files="$tmp"
  fi
  
  if [ "${stopJSON}" != "" ]; then
    tmp=$(mktemp)
    echo "${stopJSON}" > $tmp
    files="$files $tmp"
  fi
  
  if [ "${startJSON}" != "" ]; then
    tmp=$(mktemp)
    echo "${startJSON}" > $tmp
    files="$files $tmp"
  fi

  if [ "${batteryJSON}" != "" ]; then
    tmp=$(mktemp)
    echo "${batteryJSON}" > $tmp
    files="$files $tmp"
  fi
  
  if [ "${resetJSON}" != "" ]; then
    tmp=$(mktemp)
    echo "${resetJSON}" > $tmp
    files="$files $tmp"
  fi
  
  if [ "$files" != "" ]; then
    jq -c -s add $files > $mfile
    rm -f $files 
  fi
  
  messages=$(cat $mfile)
  log "Logger g5 tx messages = $messages"
}


function  call_logger()
{
  log "Calling xdrip-js ... node logger $transmitter"
  DEBUG=smp,transmitter,bluetooth-manager
  export DEBUG
  timeout 420 node logger $transmitter "${messages}"
  #"[{\"date\": ${calDate}000, \"type\": \"CalibrateSensor\",\" glucose\": $meterbg}]"
  echo
  log "after xdrip-js bg record below ..."
  cat ${LDIR}/entry.json
  echo
  glucose=$(cat ${LDIR}/entry.json | jq -M '.[0].glucose')

  if [ -z "${glucose}" ] ; then
    log "Exit - Invalid response from g5 transmitter"
    ls -al ${LDIR}/entry.json
    rm ${LDIR}/entry.json
    remove_dexcom_bt_pair
    exit
  fi
}

function  capture_entry_values()
{
  # capture raw values for use and for log to csv file 
  unfiltered=$(cat ${LDIR}/entry.json | jq -M '.[0].unfiltered')
  filtered=$(cat ${LDIR}/entry.json | jq -M '.[0].filtered')
  state=$(cat ${LDIR}/entry.json | jq -M '.[0].state')
  state="${state%\"}"
  state="${state#\"}"
  rssi=$(cat ${LDIR}/entry.json | jq -M '.[0].rssi')

  status=$(cat ${LDIR}/entry.json | jq -M '.[0].status')
  status="${status%\"}"
  status="${status#\"}"
  log "Sensor state = $state" 
  log "Transmitter status = $status" 

  # get dates for use in filenames and json entries
  datetime=$(date +"%Y-%m-%d %H:%M")
  epochdate=$(date +'%s')
  cp ${LDIR}/entry.json ${LDIR}/last-entry.json
}

function  set_glucose_type()
{
  log "Using glucoseType of $glucoseType"
  if [ "glucoseType" == "filtered" ]; then
    raw=$filtered
  else
    raw=$unfiltered
  fi
}

function set_mode()
{
  mode="expired"
  if [[ "$status" == "OK" || "$status" == "Low battery" ]]; then 
    mode="not-expired"
    if [[ "$state" == "Stopped" ]]; then
      mode="Stopped" 
      mode="expired"
    elif [[ "$state" == "Warmup" ]]; then
      mode="not-expired" 
    fi
  fi

  if [ "$mode" == "not-expired" ]; then
    if [[ $(bc <<< "$glucose > 0") -eq 1 && "$glucose" != "null" ]]; then 
      :
      # this means we got an internal tx calibrated glucose
    else
      # fallback to try to use unfiltered in this case
      mode="expired"
    fi
  fi
  # to hard-code or test expired mode, uncomment below line
  mode="expired"
}

function  initialize_calibrate_bg()
{
    calibratedBG=$glucose
    tmp=$(mktemp)
    jq ".[0].sgv = $glucose" ${LDIR}/entry.json > "$tmp" && mv "$tmp" ${LDIR}/entry.json
}

function set_entry_device_id()
{
  tmp=$(mktemp)
  jq ".[0].device = \"${id}\"" ${LDIR}/entry.json > "$tmp" && mv "$tmp" ${LDIR}/entry.json
}


function log_g5_csv()
{
  file="/var/log/openaps/g5.csv"
  unfiltered_div_1000=$(bc <<< "$unfiltered / 1000")
  filtered_div_1000=$(bc <<< "$filtered / 1000")
  noise_percentage=$(bc <<< "$noise * 100")

  if [ ! -f $file ]; then
    echo "epochdate,datetime,unfiltered,filtered,direction,calibratedBG-lsr,g5-glucose,meterbg,slope,yIntercept,slopeError,yError,rSquared,Noise,NoiseSend,mode,unfilt/1000,filt/1000,noise*100,sensitivity,rssi" > $file 
  fi
  echo "${epochdate},${datetime},${unfiltered},${filtered},${direction},${calibratedBG},${glucose},${meterbg},${slope},${yIntercept},${slopeError},${yError},${rSquared},${noise},${noiseSend},${mode},${unfiltered_div_1000},${filtered_div_1000},${noise_percentage},${sensitivity},${rssi}" >> $file 
}


# if tx state or status changed, then post a note to NS
function process_announcements()
{
  if [ "$mode" == "Stopped" ]; then
    log "Not posting glucose to Nightscout or OpenAPS - sensor state is Stopped, unfiltered/1000=$unfiltered_div_1000"
    echo "[{\"enteredBy\":\"Logger\",\"eventType\":\"Announcement\",\"notes\":\"Sensor Stopped, unfiltered=$unfiltered_div_1000\"}]" > ${LDIR}/status-change.json
    /usr/local/bin/g5-post-ns ${LDIR}/status-change.json treatments && (echo; log "Upload to NightScout of sensor Stopped status change worked") || (echo; log "Upload to NS of transmitter sensor Stopped did not work")
  else
    log "process_announcements: state=$state status=$status"
    if [ "$status" != "$lastStatus" ]; then
      echo "[{\"enteredBy\":\"Logger\",\"eventType\":\"Announcement\",\"notes\":\"Tx $status\"}]" > ${LDIR}/status-change.json
      /usr/local/bin/g5-post-ns ${LDIR}/status-change.json treatments && (echo; log "Upload to NightScout of transmitter status change worked") || (echo; log "Upload to NS of transmitter status change did not work")
    fi

    if [ "$state" != "$lastState" ]; then
      echo "[{\"enteredBy\":\"Logger\",\"eventType\":\"Announcement\",\"notes\":\"Sensor $state\"}]" > ${LDIR}/state-change.json
      /usr/local/bin/g5-post-ns ${LDIR}/state-change.json treatments && (echo; log "Upload to NightScout of sensor state change worked") || (echo; log "Upload to NS of sensor state change did not work")
    fi
  fi
}

function check_pump_history_calibration()
{
  # look for a bg check from pumphistory (direct from meter->openaps):
  # note: pumphistory may not be loaded by openaps very timely...
  meterbgafter=$(date -d "9 minutes ago" -Iminutes)
  meterjqstr="'.[] | select(._type == \"BGReceived\") | select(.timestamp > \"$meterbgafter\")'"
  bash -c "jq $meterjqstr ~/myopenaps/monitor/pumphistory-merged.json" > $METERBG_NS_RAW
  meterbg=$(bash -c "jq .amount $METERBG_NS_RAW")
  meterbgid=$(bash -c "jq .timestamp $METERBG_NS_RAW")
  # meter BG from pumphistory doesn't support mmol yet - has no units...
  # using arg3 if mmol then convert it
  if [[ "$pumpUnits" == *"mmol"* ]]; then
    meterbg=$(bc <<< "($meterbg *18)/1")
    log "converted pump history meterbg from mmol value to $meterbg"
  fi
  echo
  log "meterbg from pumphistory: $meterbg"
  calDate=$(date +'%s%3N') # TODO: use pump history date
}

function check_variation()
{
  variation=$(bc <<< "($filtered - $unfiltered) * 100 / $filtered")
  if [ $(bc <<< "$variation > 10") -eq 1 -o $(bc <<< "$variation < -10") -eq 1 ]; then
    log "would not allow meter calibration - filtered/unfiltered variation of $variation exceeds 10%"
    meterbg=""
    noiseSend=2 # set noise to light so SMB will not be used during this noisy scenario
  else
    log "filtered/unfiltered variation ok for meter calibration, $variation"
  fi
}

function check_ns_calibration()
{
  if [ -z $meterbg ]; then
    # can't use the Sensor insert UTC determination for BG since they can
    # be entered in either UTC or local time depending on how they were entered.
    curl --compressed -m 30 "${ns_url}/api/v1/treatments.json?find\[eventType\]\[\$regex\]=Check&count=1" 2>/dev/null > $METERBG_NS_RAW
    createdAt=$(jq -r ".[0].created_at" $METERBG_NS_RAW)
    secNow=`date +%s`
    secThen=`date +%s --date=$createdAt`
    elapsed=$(bc <<< "($secNow - $secThen)")
    log "meterbg date=$createdAt, secNow=$secNow, secThen=$secThen, elapsed=$elapsed"
    if [ $(bc <<< "$elapsed < 540") -eq 1 ]; then
      # note: pumphistory bg has no _id field, but .timestamp matches .created_at
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
    else
      # clear old meterbg curl responses
      rm $METERBG_NS_RAW
    fi
    log "meterbg from nightscout: $meterbg"
    calDate=$(date +'%s%3N') # TODO: use NS BG Check date
  fi
}

#call after posting to NS OpenAPS for not-expired mode
function calculate_calibrations()
{
  calibrationDone=0
  if [ -n $meterbg ]; then 
    if [ "$meterbg" != "null" -a "$meterbg" != "" ]; then
      if [ $(bc <<< "$meterbg < 400") -eq 1  -a $(bc <<< "$meterbg > 40") -eq 1 ]; then
        # only do this once for a single calibration check for duplicate BG check record ID
        if ! cat ${LDIR}/calibrations.csv | egrep "$meterbgid"; then 
          # safety check to make sure we don't have wide variance between the meterbg and the unfiltered/raw value
          # Use 1000 as slope for safety in this check
          meterbg_raw_delta=$(bc -l <<< "$meterbg - $raw/1000")
          # calculate absolute value
          if [ $(bc -l <<< "$meterbg_raw_delta < 0") -eq 1 ]; then
	    meterbg_raw_delta=$(bc -l <<< "0 - $meterbg_raw_delta")
          fi
          if [ $(bc -l <<< "$meterbg_raw_delta > 70") -eq 1 ]; then
	    log "Raw/unfiltered compared to meterbg is $meterbg_raw_delta > 70, ignoring calibration"
          else
            echo "$raw,$meterbg,$datetime,$epochdate,$meterbgid,$filtered,$unfiltered" >> ${LDIR}/calibrations.csv
            /usr/local/bin/g5-calc-calibration ${LDIR}/calibrations.csv ${LDIR}/calibration-linear.json
            maxDelta=60
            calibrationDone=1
            cat ${LDIR}/calibrations.csv
            cat ${LDIR}/calibration-linear.json
          fi
        else 
          log "this calibration was previously recorded - ignoring"
        fi
      else
        log "Invalid calibration, meterbg="${meterbg}" outside of range [40,400]"
      fi
    fi
  fi
}

# expired mode only
function apply_lsr_calibration()
{
  if [ -e ${LDIR}/calibration-linear.json ]; then
    slope=`jq -M '.[0] .slope' ${LDIR}/calibration-linear.json` 
    yIntercept=`jq -M '.[0] .yIntercept' ${LDIR}/calibration-linear.json` 
    slopeError=`jq -M '.[0] .slopeError' ${LDIR}/calibration-linear.json` 
    yError=`jq -M '.[0] .yError' ${LDIR}/calibration-linear.json` 
    calibrationType=`jq -M '.[0] .calibrationType' ${LDIR}/calibration-linear.json` 
    calibrationType="${calibrationType%\"}"
    calibrationType="${calibrationType#\"}"
    numCalibrations=`jq -M '.[0] .numCalibrations' ${LDIR}/calibration-linear.json` 
    rSquared=`jq -M '.[0] .rSquared' ${LDIR}/calibration-linear.json` 

    if [ "$calibrationDone" == "1" ];then
      # new calibration record log it to NS
      echo "[{\"device\":\"$transmitter\",\"type\":\"cal\",\"date\":$epochdate,\"scale\":1,\"intercept\":$yIntercept,\"slope\":$slope}]" > ${LDIR}cal.json 
      log "Posting cal record to NightScout"
      /usr/local/bin/g5-post-ns ${LDIR}/cal.json && (echo; log "Upload to NightScout of cal record entry worked";) || (echo; log "Upload to NS of cal record did not work")
    fi
  else
    # exit until we have a valid calibration record
    log "no valid calibration record yet, exiting ..."
    remove_dexcom_bt_pair
    exit
  fi

  # $raw is either unfiltered or filtered value from g5
  # based upon glucoseType variable at top of script
  calibratedBG=$(bc -l <<< "($raw - $yIntercept)/$slope")
  calibratedBG=$(bc <<< "($calibratedBG / 1)") # truncate
  log "After calibration calibratedBG =$calibratedBG, slope=$slope, yIntercept=$yIntercept, filtered=$filtered, unfiltered=$unfiltered, raw=$raw"

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
      log "Glucose $calibratedBG out of range [0,600] - exiting"
      remove_dexcom_bt_pair
      exit
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

# not needed given how OpenAPS processes
#
#  if [ "$da" -lt "45" -a "$da" -gt "15" ]; then
#    if [ "$mode" == "expired" ]; then
#      log "Before Average last 2 entries - lastGlucose=$lastGlucose, dg=$dg, calibratedBG=$calibratedBG"
#      calibratedBG=$(bc <<< "($calibratedBG + $lastGlucose)/2")
#      dg=$(bc <<< "$calibratedBG - $lastGlucose")
#      log "After average last 2 entries - lastGlucose=$lastGlucose, dg=$dg, calibratedBG=${calibratedBG}"
#    fi
#  fi
  # end average last two entries if noise


  if [ $(bc <<< "$dg > $maxDelta") -eq 1 -o $(bc <<< "$dg < (0 - $maxDelta)") -eq 1 ]; then
    log "Change $dg out of range [$maxDelta,-${maxDelta}] - setting noise=Heavy"
    noiseSend=4
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
    last3=( $(jq -r ".[].glucose" ${LDIR}/last15minutes.json) )
    date3=( $(jq -r ".[].date" ${LDIR}/last15minutes.json) )
    #log ${last3[@]}

    usedRecords=${#last3[@]}
    totalDelta=$dg

    for (( i=1; i<$usedRecords; i++ ))
    do
      #log "before totalDelta=$totalDelta, last3[i-1]=${last3[$i-1]}, last3[i]=${last3[$i]}"
      totalDelta=$(bc <<< "$totalDelta + (${last3[$i-1]} - ${last3[$i]})")
      #log "after totalDelta=$totalDelta"
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
  echo "${epochdate},${unfiltered},${filtered},${calibratedBG}" >> ${LDIR}/noise-input.csv

  # calculate the noise and position it for updating the entry sent to NS and xdripAPS
  if [ $(bc -l <<< "$noiseSend == 0") -eq 1 ]; then
    # means that noise was not already set before
    # get last 41 minutes (approx 7 BG's) from monitor/glucose to better support multiple rigs
    # be able to support multiple rigs running openaps / Logger at same time. 
    epms15=$(bc -l <<< "$epochdate *1000  - 41*60000")
    glucosejqstr="'[ .[] | select(.date > $epms15) ]'"
    bash -c "jq -c $glucosejqstr ~/myopenaps/monitor/glucose.json" > ${LDIR}/last41minutes.json
    date41=( $(jq -r ".[].date" ${LDIR}/last41minutes.json) )
    gluc41=( $(jq -r ".[].glucose" ${LDIR}/last41minutes.json) )
    unf41=( $(jq -r ".[].unfiltered" ${LDIR}/last41minutes.json) )
    fil41=( $(jq -r ".[].filtered" ${LDIR}/last41minutes.json) )

    usedRecords=${#gluc41[@]}
    log "usedRecords=$usedRecords last 41 minutes = ${gluc41[@]}"

    truncate -s 0 ${LDIR}/noise-input41.csv
    for (( i=$usedRecords-1; i>=0; i-- ))
    do
      dateSeconds=$(bc <<< "${date41[$i]} / 1000")
      echo "$dateSeconds,${unf41[$i]},${fil41[$i]},${gluc41[$i]}" >> ${LDIR}/noise-input41.csv
    done
    echo "${epochdate},${unfiltered},${filtered},${calibratedBG}" >> ${LDIR}/noise-input41.csv

    if [ -e "/usr/local/bin/g5-calc-noise-go" ]; then
      # use the go-based version
      noise_cmd="/usr/local/bin/g5-calc-noise-go"
      log "calculating noise using go-based version"
    else 
      noise_cmd="/usr/local/bin/g5-calc-noise"
      log "calculating noise using bash-based version"
    fi
    $noise_cmd ${LDIR}/noise-input41.csv ${LDIR}/noise.json

    if [ -e ${LDIR}/noise.json ]; then
      noise=`jq -M '.[0] .noise' ${LDIR}/noise.json` 
      # remove issue where jq returns scientific notation, convert to decimal
      noise=$(awk -v noise="$noise" 'BEGIN { printf("%.2f", noise) }' </dev/null)
      log "Raw noise of $noise will be used to determine noiseSend value."
    fi

    if [ $(bc -l <<< "$noise < 0.35") -eq 1 ]; then
      noiseSend=1  # Clean
    elif [ $(bc -l <<< "$noise < 0.5") -eq 1 ]; then
      noiseSend=2  # Light
    elif [ $(bc -l <<< "$noise < 0.7") -eq 1 ]; then
      noiseSend=3  # Medium
    elif [ $(bc -l <<< "$noise >= 0.7") -eq 1 ]; then
      noiseSend=4  # Heavy
    fi
  fi

  tmp=$(mktemp)
  jq ".[0].noise = $noiseSend" ${LDIR}/entry-xdrip.json > "$tmp" && mv "$tmp" ${LDIR}/entry-xdrip.json
}

function check_messages()
{
  if [ -n $meterbg ]; then 
    if [ "$meterbg" != "null" -a "$meterbg" != "" ]; then
      calibrationJSON="[{\"date\": ${calDate}, \"type\": \"CalibrateSensor\",\"glucose\": $meterbg}]"
      log "calibrationJSON=$calibrationJSON"
    fi
  fi
  
  file="${LDIR}/g5-stop.json"
  if [ -e "$file" ]; then
    stopJSON=$(cat $file)
    log "stopJSON=$stopJSON"
    rm -f $file
  fi

  file="${LDIR}/g5-start.json"
  if [ -e "$file" ]; then
    startJSON=$(cat $file)
    log "startJSON=$startJSON"
    rm -f $file
  fi

  file="${LDIR}/g5-reset.json"
  if [ -e "$file" ]; then
    resetJSON=$(cat $file)
    log "resetJSON=$resetJSON"
    rm -f $file
  fi
}

function check_recent_sensor_insert()
{
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
  if [ "$mode" == "Stopped" ]; then
    # don't post glucose to NS
    return
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
  /usr/local/bin/g5-post-ns ${LDIR}/entry-ns.json && (echo; log "Upload to NightScout of xdrip entry worked ... removing ${LDIR}/entry-backfill.json"; rm -f ${LDIR}/entry-backfill.json) || (echo; log "Upload to NS of xdrip entry did not work ... saving for upload when network is restored ... Auth to NS may have failed; ensure you are using hashed API_SECRET in ~/.bash_profile"; cp ${LDIR}/entry-ns.json ${LDIR}/entry-backfill.json)
  echo

  if [ -e "${LDIR}/treatments-backfill.json" ]; then
    log "Posting treatments to NightScout"
    /usr/local/bin/g5-post-ns ${LDIR}/treatments-backfill.json treatments && (echo; log "Upload to NightScout of xdrip treatments worked ... removing ${LDIR}/treatments-backfill.json"; rm -f ${LDIR}/treatments-backfill.json) || (echo; log "Upload to NS of xdrip entry did not work ... saving treatments for upload when network is restored ... Auth to NS may have failed; ensure you are using hashed API_SECRET in ~/.bash_profile")
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
  file="${LDIR}/entry.json"
  if [ -e $file ]; then
    age=$(date -r $file +'%s')
    seconds_since_last_entry=$(bc <<< "$epochdate - $age")
    log "Time since last glucose entry in seconds = $seconds_since_last_entry seconds"
    sleep_time=$(bc <<< "240 - $seconds_since_last_entry") 
    if [ $(bc <<< "$sleep_time > 0") -eq 1 ]; then
      log "Waiting $sleep_time seconds because glucose records only happen every 5 minutes"
      wait_with_echo $sleep_time
    fi
  else
    log "More than 4 minutes since last glucose entry, continue processing without waiting"
  fi
}

function check_sensitivity()
{
  sensitivity=$(jq .ratio ${HOME}/myopenaps/settings/autosens.json)
}

main "$@"

