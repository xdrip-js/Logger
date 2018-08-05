#!/bin/bash

MAXRECORDS=${1:-25}
INPUT=${2:-"/var/log/openaps/cgm.csv"}

n=0


if [ -e $INPUT ]; then
  arrdate=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f1 ) )
  unfiltered=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f17 ) )
  filtered=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f18 ) )
  arrlsrbg=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f6 ) )
  arrtxbg=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f7 ) )
  arrnoise=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f19 ) )
  arrnoisesend=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f15 ) )
  
  n=${#arrdate[@]}
fi

for (( i=0; i<$n; i++ ))
do
  arrdate[$i]=$(date -d @${arrdate[$i]} +%Y%m%d-%H:%M)
#  unfiltered[$i]=$(bc <<< "${unfiltered[$i]} / 1000")
#  filtered[$i]=$(bc <<< "${filtered[$i]} / 1000")
done

echo "Datetime, unfiltered/1k, filtered/1k, LSR bg, Tx bg, noise*100, noisesend"
for (( i=0; i<$n; i++ ))
do
#  echo "${arrdate[$i]}"
#  noisetimes100=$(bc <<< "${arrnoise[$i]} * 100")
  echo "${arrdate[$i]}, ${unfiltered[$i]}, ${filtered[$i]}, ${arrlsrbg[$i]}, ${arrtxbg[$i]}, ${arrnoise[$i]}, ${arrnoisesend[$i]}"
done
