#!/bin/bash

maxRecords=${1:-25}
inputFile=${2:-"/var/log/openaps/cgm.csv"}

n=0

records=$(cat $inputFile | wc -l)

if [ $(bc <<< "$records - 1 <  $maxRecords") -eq 1 ]; then
  n=$((records-1))
  echo "records of $records -1 < $maxRecords"
  maxRecords=$n
fi



if [ -e $inputFile ]; then
  arrdate=( $(tail -$maxRecords $inputFile | cut -d ',' -f1 ) )
  unfiltered=( $(tail -$maxRecords $inputFile | cut -d ',' -f3 ) )
  filtered=( $(tail -$maxRecords $inputFile | cut -d ',' -f4 ) )
  arrlsrbg=( $(tail -$maxRecords $inputFile | cut -d ',' -f6 ) )
  arrtxbg=( $(tail -$maxRecords $inputFile | cut -d ',' -f7 ) )
  arrnoise=( $(tail -$maxRecords $inputFile | cut -d ',' -f14 ) )
  arrnoisesend=( $(tail -$maxRecords $inputFile | cut -d ',' -f15 ) )
  
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
