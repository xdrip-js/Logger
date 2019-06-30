#!/bin/bash

inputFile="/tmp/cgm1.csv"

echo "1561930724,76,90,75" > $inputFile
echo "1561931025,66,81,64" >> $inputFile
echo "1561931325,59,72,56" >> $inputFile
echo "1561931625,55,64,54" >> $inputFile
echo "1561931925,58,57,61" >> $inputFile
echo "1561932525,80,61,94" >> $inputFile
echo "1561932825,92,72,110" >> $inputFile
echo "1561933130,100,84,118" >> $inputFile


yarr=( $(tail -8 $inputFile | cut -d ',' -f2 ) )
n=${#yarr[@]}

echo -n "Unfiltered =  ${yarr[@]} - "



#cat $inputFile
cgm-calc-noise $inputFile

