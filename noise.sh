#!/bin/bash

MAXRECORDS=${1:-25}
INPUT=${2:-"/var/log/openaps/g5.csv"}

n=0


if [ -e $INPUT ]; then
  arrdate=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f1 ) )
  unfiltered=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f3 ) )
  filtered=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f4 ) )
  arrbg=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f6 ) )
  arrnoise=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f13 ) )
  arrnoisesend=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f14 ) )
  
  n=${#arrbg[@]}
fi

for (( i=0; i<$n; i++ ))
do
  arrdate[$i]=$(date -d @${arrdate[$i]} +%Y%m%d-%H:%M)
  unfiltered[$i]=$(bc <<< "${unfiltered[$i]} / 1000")
  filtered[$i]=$(bc <<< "${filtered[$i]} / 1000")
done

echo "Datetime, unfiltered/1k, filtered/1k, bg, noise, noise*100, noisesend"
for (( i=0; i<$n; i++ ))
do
#  echo "${arrdate[$i]}"
  noisetimes100=$(bc <<< "${arrnoise[$i]} * 100")
  echo "${arrdate[$i]}, ${unfiltered[$i]}, ${filtered[$i]}, ${arrbg[$i]}, ${arrnoise[$i]}, $noisetimes100, ${arrnoisesend[$i]}"
done
