#!/bin/bash

main()
{
inputFile="/tmp/cgm.csv"
outputFile="/tmp/cgm.json"

variation=0

# comment/uncomment based on which test to run
#variationTests=(0 5 10 15 20)
variationTests=(0) 

  for j in ${variationTests[@]}; do
  variation=$j 
  echo ""
  echo "Testing scenarios where unfiltered / filtered variation = $variation"
  a=(310) && unit_test
  a=(310 315) && unit_test
  a=(310 315 320) && unit_test
  a=(310 315 320 325) && unit_test
  a=(310 335 305 395) && unit_test
  a=(310 335 480 325) && unit_test
  a=(110 111 110 110 110 110 110 160) && unit_test
  a=(97 94 96 93 93 94 93 96) && unit_test
  a=(125 123 124 122 122 122 123 124) && unit_test
  a=(116 114 112 108 103 96 101 108) && unit_test
  a=(82 80 75 68 59 58 65 75) && unit_test
  a=(200 201 200 201 200 201 200 201) && unit_test
  a=(100 102 104 102 104 106 104 102) && unit_test
  a=(75 75 75 74 75 75 75 75) && unit_test
  a=(76 66 59 55 58 80 92 100) && unit_test
  a=(110 111 110 110 110 110 110 110) && unit_test
  a=(176 166 159 155 158 180 192 200) && unit_test
  a=(122 135 140 155 160 155 150 145) && unit_test
  a=(100 105 110 120 135 137 135 125) && unit_test
  a=(100 110 130 160 190 191 184 180) && unit_test
  a=(143 140 137 135 131 129 125 119) && unit_test
  a=(140 120 140 160 180 200 220 240) && unit_test
  a=(100 115 114 130 129 140 139 150) && unit_test
  a=(100 102 104 102 104 106 104 152) && unit_test
  a=(100 105 104 110 109 115 114 120) && unit_test
  a=(100 152 104 106 108 108 108 108) && unit_test
  a=(120 105 110 120 135 134 135 125) && unit_test
  a=(150 110 140 170 200 230 260 290) && unit_test
  a=(150 110 140 170 200 130 160 290) && unit_test
  a=(110 122 144 166 188 212 230 264) && unit_test
  a=(176 146 159 135 158 150 282 200) && unit_test
  a=(260 230 200 170 140 110 80 50) && unit_test
  a=(100 120 140 160 180 200 220 240) && unit_test
  a=(110 111 110 110 110 310 315 318) && unit_test
  a=(110 111 110 110 110 110 315 318) && unit_test
  a=(110 111 110 110 110 110 110 180) && unit_test
done

}

function unit_test()
{
  truncate -s 0 $inputFile

  cgmTime=1000000000
  for t in ${a[@]}; do
    filtered=$(($t+$variation))
    #echo "t=$t, variation=$variation"
    echo "$cgmTime,$t,$filtered,$t" >> $inputFile
    cgmTime=$(bc <<< "$cgmTime + 300")
  done

  numRecords=${#a[@]}
  yarr=( $(tail -$numRecords $inputFile | cut -d ',' -f2 ) )
#  n=${#yarr[@]}
  #cat $inputFile
  echo -n "${yarr[@]} - "
  cgm-calc-noise $inputFile $outputFile
}

main "$@"

