#!/bin/bash

function usage
{
  echo "Usage:"
  echo "cgm-start [minutes-ago]"
  echo "cgm-start [-m minutes-ago] [-c g6_sensor_code] [-t transmitter_id]"
  echo
  exit
}

numArgs=$#
if [ $(bc <<< "$numArgs > 1") -eq 1 ]; then
# use -m or -c to specify minutes ago and/or g6 code
  while test $# != 0
  do
    case "$1" in
    -m|--minutes_ago) minutes_ago=$2; shift ;;
    -c|--code) code=$2; shift ;;
    -t|--transmitter) txId=$2; shift ;;
    -h|--help) usage;  ;;
    *)  usage ;;
    esac
    shift
  done
elif [ $(bc <<< "$numArgs > 0") -eq 1 ]; then
  # optional parameter $1 to specify how many minutes ago for sensor insert/start
  minutes_ago=$1
fi

#update config
if [ -n $txId ]; then
  if [ "$txId" != "null" -a "$txId" != "" ]; then  
    cgm-transmitter "$txId"
  fi
fi
if [ -n $code ]; then
  if [ "$code" != "null" -a "$code" != "" ]; then  
    config="/root/myopenaps/xdripjs.json"
    if [ -e "$config" ]; then
      tmp=$(mktemp)
      jq --arg code "$code" '.sensor_code = $code' "$config" > "$tmp" && mv "$tmp" "$config"
    fi        
  fi
fi

MESSAGE="${HOME}/myopenaps/monitor/xdripjs/cgm-start.json"
if [ -n "$minutes_ago" ]; then
  epochdate=$(date +'%s%3N' -d "$minutes_ago minutes ago")
else
  epochdate=$(date +'%s%3N')
fi

echo "[{\"date\":\"${epochdate}\",\"type\":\"StartSensor\",\"sensorSerialCode\":\"${code}\"}]" >  $MESSAGE
cat $MESSAGE
