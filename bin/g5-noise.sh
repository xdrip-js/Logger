#!/bin/bash

MAXRECORDS=${1:-45}
INPUT=${2:-"/var/log/openaps/cgm.csv"}

n=0


if [ -e $INPUT ]; then
  arrdate=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f1 ) )
  unfiltered=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f3 ) )
  filtered=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f4 ) )
  arrlsrbg=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f6 ) )
  arrtxbg=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f7 ) )
  arrnoise=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f14 ) )
  arrnoisesend=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f15 ) )
  
  n=${#arrdate[@]}
fi

for (( i=0; i<$n; i++ ))
do
  arrdate[$i]=$(date -d @${arrdate[$i]} +%Y%m%d-%H:%M)
  noisetext[$i]="Error"
  if [[ "${arrnoisesend[$i]}" == "1" ]]; then
     noisetext[$i]="Clean"
  elif [[ "${arrnoisesend[$i]}" == "2" ]]; then
     noisetext[$i]="Light"
  elif [[ "${arrnoisesend[$i]}" == "3" ]]; then
     noisetext[$i]="Medium"
  elif [[ "${arrnoisesend[$i]}" == "4" ]]; then
     noisetext[$i]="Heavy"
  fi

#  unfiltered[$i]=$(bc <<< "${unfiltered[$i]} / 1000")
#  filtered[$i]=$(bc <<< "${filtered[$i]} / 1000")
done

echo "Date,          unfilt, filt, LSRbg, Txbg, noise, noisesend, noisetext"
for (( i=0; i<$n; i++ ))
do
#  echo "${arrdate[$i]}"
#  noisetimes100=$(bc <<< "${arrnoise[$i]} * 100")
  echo "${arrdate[$i]}, ${unfiltered[$i]},    ${filtered[$i]},     ${arrlsrbg[$i]},    ${arrtxbg[$i]},    ${arrnoise[$i]},    ${arrnoisesend[$i]},    ${noisetext[$i]}"
done
