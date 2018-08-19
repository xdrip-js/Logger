#!/bin/bash

function usage
{
  echo "Usage:"
  echo "cgm-transmitter [transmitter_id]"
  echo
  exit
}

numArgs=$#
if [ $(bc <<< "$numArgs < 1") -eq 1 ] || [ $(bc <<< "$numArgs > 1") -eq 1 ]; then
# use -m or -c to specify minutes ago and/or g6 code
  usage
  exit
fi

txId=$1
echo ${txId}

#Update config file
config="/root/myopenaps/xdripjs.json"
tmp=$(mktemp)
jq --arg txId "$txId" '.transmitter_id = $txId' "$config" > "$tmp" && mv "$tmp" "$config"

#Post message
MESSAGE="${HOME}/myopenaps/monitor/xdripjs/cgm-transmitter.json"
epochdate=$(date +'%s%3N')

echo "[{\"date\":\"${epochdate}\",\"type\":\"New Transmitter\",\"txId\":\"${txId}\"}]" >  $MESSAGE
cat $MESSAGE
