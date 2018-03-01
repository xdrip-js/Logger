#!/bin/bash

MAXRECORDS=${1:-25}
INPUT=${2:-"/var/log/openaps/g5.csv"}

n=0

echo "Datetime,      bg, noise, noise*100, noisesend"

if [ -e $INPUT ]; then
  arrdate=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f1 ) )
  arrbg=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f6 ) )
  arrnoise=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f13 ) )
  arrnoisesend=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f14 ) )
  
  n=${#arrbg[@]}
fi

for (( i=0; i<$n; i++ ))
do
  arrdate[$i]=$(date -d @${arrdate[$i]} +%Y%m%d-%H:%M)
done

for (( i=0; i<$n; i++ ))
do
#  echo "${arrdate[$i]}"
  noisetimes100=$(bc <<< "${arrnoise[$i]} * 100")
  echo "${arrdate[$i]}, ${arrbg[$i]}, ${arrnoise[$i]}, $noisetimes100, ${arrnoisesend[$i]}"
done
