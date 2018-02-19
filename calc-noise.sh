#!/bin/bash

#"${epochdate},${unfiltered},${filtered},${calibratedBG}" >> ./noise-input.csv

INPUT=${1:-"./noise-input.csv"}
OUTPUT=${2:-"./noise.json"}
MAXRECORDS=8
MINRECORDS=4
noise=0

function ReportNoiseAndExit()
{
  echo "[{"noise":$noise}]" > $OUTPUT
  cat $OUTPUT
  exit
}

if [ -e $INPUT ]; then
  yarr=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f2 ) )
  xdate=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f1 ) )
  n=${#yarr[@]}
else
  noise=0
  ReportNoiseAndExit
fi

#    set initial x values based on date differences

if [ $(bc <<< "$n < 3") -eq 1 ]; then
  # set noise = 0 - unknown
  noise=0
  ReportNoiseAndExit
fi

firstDate=${xdate[0]}
for (( i=0; i<$n; i++ ))
do
  xarr[$i]=$(bc <<< "(${xdate[$i]} - $firstDate) * 30") # use 30 multiplier to normalize axis
#  echo "x,y=${xarr[$i]},${yarr[$i]}"
done

#echo ${xarr[@]}
#echo ${xdate[@]}

# sod = sum of distances
sod=0
overallsod=0

lastDelta=0
for (( i=1; i<$n; i++ ))
do
  y2y1Delta=$(bc  <<< "${yarr[$i]} - ${yarr[$i-1]}")
  x2x1Delta=$(bc  <<< "${xarr[$i]} - ${xarr[$i-1]}")
  if [ $(bc <<< "$lastDelta > 0") -eq 1 -a $(bc <<< "$y2y1Delta < 0") -eq 1 ]; then
    # switched from positive delta to negative, increase noise impact  
    y2y1Delta=$(bc -l <<< "${y2y1Delta} * 1.1")
  elif [ $(bc <<< "$lastDelta < 0") -eq 1 -a $(bc <<< "$y2y1Delta > 0") -eq 1 ]; then
    # switched from positive delta to negative, increase noise impact 
    y2y1Delta=$(bc -l <<< "${y2y1Delta} * 1.3")
  fi

  sod=$(bc  <<< "$sod + sqrt(($x2x1Delta)^2 + ($y2y1Delta)^2)")
done  

overallsod=$(bc -l <<< "sqrt((${yarr[$n-1]} - ${yarr[0]})^2 + (${xarr[$n-1]} - ${xarr[0]})^2)")

if [ $(bc -l <<< "$sod == 0") -eq 1 ]; then
  # assume no noise if no records
  noise = 0
else
#  echo "sod=$sod, overallsod=$overallsod"
  noise=$(bc -l <<< "1 - ($overallsod/$sod)")
fi
noise=$(printf "%.*f\n" 5 $noise)
ReportNoiseAndExit
