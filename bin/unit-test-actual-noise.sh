#!/bin/bash
inputFile=${1:-"/var/log/openaps/cgm.csv"}
calcProg=${2:-"g5-calc-noise"}
tempFile=/tmp/noise-test-subset
records41Minutes=8

numRecords=`wc -l $inputFile | cut -d' ' -f1`
if [ "$inputFile" == "/var/log/openaps/cgm.csv" ]; then
  numRecords=$(bc <<< "$numRecords - 1")
fi

startingPoint=2
if [ $(bc <<< "$numRecords > 50") -eq 1 ]; then
  echo "numRecords of $numRecords > 50 so limiting to 50"
  startingPoint=$(bc <<< "$numRecords - 50 + 2") 
else
  echo "numRecords=$numRecords"
fi

for (( i=$startingPoint; i<=$(($numRecords - $records41Minutes + 1)); i++ ))
do
   tail -n+$i $inputFile | head -$records41Minutes | cut -d',' -f1,3 > ${tempFile}.csv
   echo -n `tail -1 ${tempFile}.csv`
   echo -n " "
   $calcProg ${tempFile}.csv ${tempFile}.json
done
