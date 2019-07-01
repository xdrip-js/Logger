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
cgm-calc-noise $inputFile

echo "1561930724,176,190,175" > $inputFile
echo "1561931025,166,181,164" >> $inputFile
echo "1561931325,159,172,156" >> $inputFile
echo "1561931625,155,164,154" >> $inputFile
echo "1561931925,158,157,161" >> $inputFile
echo "1561932525,180,161,194" >> $inputFile
echo "1561932825,192,172,210" >> $inputFile
echo "1561933130,200,184,218" >> $inputFile
yarr=( $(tail -8 $inputFile | cut -d ',' -f2 ) )
n=${#yarr[@]}
echo -n "Unfiltered =  ${yarr[@]} - "
cgm-calc-noise $inputFile

echo "1561930724,176,190,175" > $inputFile
echo "1561931025,146,151,154" >> $inputFile
echo "1561931325,159,172,156" >> $inputFile
echo "1561931625,135,134,134" >> $inputFile
echo "1561931925,158,157,161" >> $inputFile
echo "1561932525,150,151,154" >> $inputFile
echo "1561932825,282,282,280" >> $inputFile
echo "1561933130,200,200,200" >> $inputFile
yarr=( $(tail -8 $inputFile | cut -d ',' -f2 ) )
n=${#yarr[@]}
echo -n "Unfiltered =  ${yarr[@]} - "
cgm-calc-noise $inputFile

echo "1561930724,140,140,140" > $inputFile
echo "1561931025,120,120,120" >> $inputFile
echo "1561931325,140,140,140" >> $inputFile
echo "1561931625,160,160,160" >> $inputFile
echo "1561931925,180,180,180" >> $inputFile
echo "1561932525,200,200,200" >> $inputFile
echo "1561932825,220,220,220" >> $inputFile
echo "1561933130,240,240,240" >> $inputFile
yarr=( $(tail -8 $inputFile | cut -d ',' -f2 ) )
n=${#yarr[@]}
echo -n "Unfiltered =  ${yarr[@]} - "
cgm-calc-noise $inputFile


echo "1561930724,150,150,150" > $inputFile
echo "1561931025,110,110,110" >> $inputFile
echo "1561931325,140,140,140" >> $inputFile
echo "1561931625,170,170,170" >> $inputFile
echo "1561931925,200,200,200" >> $inputFile
echo "1561932525,230,230,230" >> $inputFile
echo "1561932825,260,260,260" >> $inputFile
echo "1561933130,290,290,290" >> $inputFile
yarr=( $(tail -8 $inputFile | cut -d ',' -f2 ) )
n=${#yarr[@]}
echo -n "Unfiltered =  ${yarr[@]} - "
cgm-calc-noise $inputFile


echo "1561930724,150,150,150" > $inputFile
echo "1561931025,110,110,110" >> $inputFile
echo "1561931325,140,140,140" >> $inputFile
echo "1561931625,170,170,170" >> $inputFile
echo "1561931925,200,200,200" >> $inputFile
echo "1561932525,130,130,130" >> $inputFile
echo "1561932825,160,160,160" >> $inputFile
echo "1561933130,290,290,290" >> $inputFile
yarr=( $(tail -8 $inputFile | cut -d ',' -f2 ) )
n=${#yarr[@]}
echo -n "Unfiltered =  ${yarr[@]} - "
cgm-calc-noise $inputFile

echo "1561930724,122,122,122" > $inputFile
echo "1561931025,135,135,135" >> $inputFile
echo "1561931325,140,140,140" >> $inputFile
echo "1561931025,155,155,155" >> $inputFile
echo "1561931325,160,160,160" >> $inputFile
echo "1561931025,155,155,155" >> $inputFile
echo "1561931325,150,150,150" >> $inputFile
echo "1561931025,145,145,145" >> $inputFile
yarr=( $(tail -8 $inputFile | cut -d ',' -f2 ) )
n=${#yarr[@]}
echo -n "Unfiltered =  ${yarr[@]} - "
cgm-calc-noise $inputFile
