#!/bin/bash

INPUT=${1:-"/var/log/openaps/g5.csv"}
MAXRECORDS=8
MINRECORDS=4
XINCREMENT=10000
yarr=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f3 ) )
xdate=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f1 ) )
n=${#yarr[@]}

#    dt1970arr[$i]=`date +%s --date="${dtarr[$i]}"`
#    set initial i value based on date differences

#for (( i=0; i<$n; i++ ))
#do
#  xarr[$i]=`date +%s --date="${xdate[$i]}"`
#done

#echo ${xarr[@]}
#echo ${xdate[@]}
#exit

# sod = sum of distances
sod=0
overallsod=0

for (( i=1; i<$n; i++ ))
do
  y1=${yarr[$i]}
  y2=${yarr[$i-1]}

  sod=$(bc -l <<< "$sod + sqrt(($XINCREMENT)^2 + ($y1 - $y2)^2)")
done  

overallsod=$(bc -l <<< "sqrt((${yarr[$n-1]} - ${yarr[0]})^2 + ($XINCREMENT*($n - 1))^2)")

if [ $(bc -l <<< "$sod == 0") -eq 1 ]; then
  # assume no noise if no records
  noise = 0
else
  noise=$(bc -l <<< "1 - ($overallsod/$sod)")
fi
noise=$(printf "%.*f\n" 5 $noise)
echo $noise


