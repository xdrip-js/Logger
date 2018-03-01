#!/bin/bash

INPUT=${1:-"/var/log/openaps/g5.csv"}
MAXRECORDS=25

n=0

echo "Datetime,                     bg, noise, noisesend"

if [ -e $INPUT ]; then
  arrdate=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f1 ) )
  arrbg=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f6 ) )
  arrnoise=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f13 ) )
  arrnoisesend=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f14 ) )
  
  n=${#arrbg[@]}
fi

for (( i=0; i<$n; i++ ))
do
  arrdate[$i]=$(date -d @${arrdate[$i]})
done

for (( i=0; i<$n; i++ ))
do
#  echo "${arrdate[$i]}"
  echo "${arrdate[$i]}, ${arrbg[$i]}, ${arrnoise[$i]}, ${arrnoisesend[$i]}"
done
