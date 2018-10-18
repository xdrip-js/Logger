#!/bin/bash

function usage
{
  echo "Usage:"
  echo "cgm-transmitter [transmitter_id]"
  echo
  exit
}

function  generate_config
{
  echo "{\"transmitter_id\":\"${txId}\",\"sensor_code\":\"\",\"mode\":\"not-expired\",\"pump_units\":\"mg/dl\",\"fake_meter_id\":\"000000\"}" | jq . > $config
}

numArgs=$#
if [ $(bc <<< "$numArgs < 1") -eq 1 ] || [ $(bc <<< "$numArgs > 1") -eq 1 ]; then
  usage
  exit
fi

txId=$1

#validate transmitter id
if [ ${#txId} -ne 6 ]; then
  echo "Invalid transmitter id; should be 6 characters long"
  exit
elif [ ${txId:0:1} == 8 ]; then
  echo "setting G6 transmitter: $txId"
else
  echo "setting G5 transmitter: $txId"
fi

#Update config file
config="/root/myopenaps/xdripjs.json"
if [ -e "$config" ]; then
  echo "config found, updating xdripjs.json"
  tmp=$(mktemp)
  jq --arg txId "$txId" '.transmitter_id = $txId' "$config" > "$tmp" && mv "$tmp" "$config"
else
  echo "Config file does not exist, generating xdripjs.json"
  generate_config
fi

#Post message
MESSAGE="${HOME}/myopenaps/monitor/xdripjs/cgm-transmitter.json"
epochdate=$(date +'%s%3N')
echo "[{\"date\":\"${epochdate}\",\"type\":\"New Transmitter\",\"txId\":\"${txId}\"}]" >  $MESSAGE
cat $MESSAGE
