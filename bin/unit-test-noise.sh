#!/bin/bash

main()
{
inputFile="/tmp/cgm1.csv"

a=(76 66 59 55 58 80 92 100) && unit_test
a=(176 166 159 155 158 180 192 200) && unit_test
a=(176 146 159 135 158 150 282 200) && unit_test
a=(140 120 140 160 180 200 220 240) && unit_test
a=(150 110 140 170 200 230 260 290) && unit_test
a=(150 110 140 170 200 130 160 290) && unit_test
a=(122 135 140 155 160 155 150 145) && unit_test

}

function unit_test()
{
  truncate -s 0 $inputFile

  cgmTime=1000000000
  for t in ${a[@]}; do
    echo "$cgmTime,$t,$t,$t" >> $inputFile
    cgmTime=$(bc <<< "$cgmTime + 300")
  done

  numRecords=${#a[@]}
  yarr=( $(tail -$numRecords $inputFile | cut -d ',' -f2 ) )
#  n=${#yarr[@]}
  echo -n "Unfiltered =  ${yarr[@]} - "
  cgm-calc-noise $inputFile
}

main "$@"

