#!/bin/bash

function usage
{
  echo "Usage:"
  echo "cgm-start [minutes-ago]"
  echo "cgm-start [-m minutes-ago] [-c g6_sensor_code]"
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
    -h|--help) usage;  ;;
    *)  usage ;;
    esac
    shift
  done
elif [ $(bc <<< "$numArgs > 0") -eq 1 ]; then
  # optional parameter $1 to specify how many minutes ago for sensor insert/start
  minutes_ago=$1
fi
 


#echo "minutes_ago=$minutes_ago"
#echo "code=$code"


# check Logger last state json file to get txId in order to determine if using g6 or not
#LAST_STATE="${HOME}/myopenaps/monitor/xdripjs/Logger-last-state.json"
#txId=$(cat ${LDIR}/Logger-last-state.json | jq -M '.[0].txId')
#txId="${txId%\"}"
#txId="${txId#\"}"
#echo ""



MESSAGE="${HOME}/myopenaps/monitor/xdripjs/cgm-start.json"
if [ -n "$minutes_ago" ]; then
  epochdate=$(date +'%s%3N' -d "$minutes_ago minutes ago")
else
  epochdate=$(date +'%s%3N')
fi

echo "[{\"date\":\"${epochdate}\",\"type\":\"StartSensor\"},\"code\":\"${code}\"]" >  $MESSAGE
cat $MESSAGE
