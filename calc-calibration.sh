#!/bin/bash

# test.csv order is from oldest calibration at the top to latest calibration at the bottom
# test.csv in the form of 
# unfiltered,meterbg,datetime
#
# yarr = array of up to 7 last unfiltered values associated with xarr bg meter checks / calibrations
# xarr = array of up to 7 last bg meter checks / calibrations

INPUT=${1:-"calibrations.csv"}
OUTPUT=${2:-"calibration-linear.json"}
MAXSLOPE=1350
MINSLOPE=650

yarr=( $(tail -7 $INPUT | cut -d ',' -f1 ) )
xarr=( $(tail -7 $INPUT | cut -d ',' -f2 ) )

echo "Begin calibration using input of $INPUT and output of $OUTPUT"

function MathMin()
{
  local arr=("$@")
  local n=${#arr[@]}
  local min=${arr[0]}
   
  for (( i=1; i<$n; i++ ))
  do
    if [ $(bc -l <<< "${arr[$i]} < $min") -eq 1 ]; then
      min=${arr[$i]}
    fi
  done

  echo "$min"
}

function MathSum()
{
  local total=0

  for i in "$@"
  do
    total=$(bc -l <<< "$total + $i")
  done

  echo "$total"
}

function MathAvg()
{
  local arr=("$@")
  local total=$(MathSum "${arr[@]}") 
  local avg=0

  avg=$(bc -l <<< "$total / ${#arr[@]}")

  echo "$avg"
}

function MathStdDev()
{
  local arr=("$@")
  local mean=$(MathAvg "${arr[@]}")
  local sqdif=0
  local stddev=0

  for i in "${arr[@]}"
  do
    sqdif=$(bc -l <<< "$sqdif + ($i-$mean)^2") 
  done
  
  stddev=$(bc -l <<< "sqrt($sqdif / (${#arr[@]} - 1))")
  echo $stddev
}


# Assumes global arrays x and y are set
# sets global variables slope and yIntercept
function LeastSquaresRegression()
{
  local sumX=$(MathSum "${xarr[@]}")
  local sumY=$(MathSum "${yarr[@]}")
  local meanX=$(MathAvg "${xarr[@]}")
  local meanY=$(MathAvg "${yarr[@]}")
  local stddevX=$(MathStdDev "${xarr[@]}")
  local stddevY=$(MathStdDev "${yarr[@]}")
  local sumXY=0
  local sumXSq=0
  local sumYSq=0
  local r=0
  local n=${#xarr[@]}
  local m=0
  local b=0
   

  for (( i=0; i<$n; i++ ))
  do
    sumXY=$(bc -l <<< "$sumXY + ${xarr[i]} * ${yarr[i]}")
    sumXSq=$(bc -l <<< "$sumXSq + ${xarr[i]} * ${xarr[i]}")
    sumYSq=$(bc -l <<< "$sumYSq + ${yarr[i]} * ${yarr[i]}")
  done  
  
  r=$(bc -l <<< "($n * $sumXY - $sumX * $sumY) / sqrt((($n * $sumXSq - ${sumX}^2) * ($n * $sumYSq - ${sumY}^2)))")
#  echo "r=$r, n=$n, sumXSq=$sumXSq, sumYSq=$sumYSq"
#  echo "sumY=$sumY, sumX=$sumX, stddevX=$stddevX, stddevY=$stddevY" 

  m=$(bc -l <<< "$r * $stddevY / $stddevX ")
  b=$(bc -l <<< "$meanY - $m * $meanX ")

#  echo "m=$m, b=$b" 
# sets global variables slope and yIntercept
  slope=$m
  yIntercept=$b
}



#echo "${xarr[@]}"

#get the number of calibrations
numx=${#xarr[@]}
slope=0
yIntercept=1000

if [ "$numx" -gt "2" ]; then
  echo "Calibration records = $numx, using LeastSquaresRegression" 
  LeastSquaresRegression
elif [ "$numx" -gt "0" ]; then
  # for less than 3 calibrations, fall back to single point calibration
  # get the last entry for x and y
  x=${xarr[-1]}
  y=${yarr[-1]}
  yIntercept=0
  slope=$(bc -l <<< "$y / $x")
  echo "Calibration records = $numx, using single point linear" 
  echo "x=$x, y=$y, slope=$slope, yIntercept=0" 
fi

# truncate and bounds check
yIntercept=$(bc <<< "$yIntercept / 1") # truncate
slope=$(bc <<< "$slope / 1") # truncate

# Set max yIntercept to the minimum of the set of unfiltered values
maxIntercept=$(MathMin "${yarr[@]}")

echo "Before bounds check, slope=$slope, yIntercept=$yIntercept"

if [ $(bc <<< "$slope > $MAXSLOPE") -eq 1 ]; then
  slope=$MAXSLOPE
elif [ $(bc <<< "$slope < $MINSLOPE") -eq 1 ]; then
  slope=$MINSLOPE
fi 

if [ $(bc  <<< "$yIntercept > $maxIntercept") -eq 1 ]; then
  yIntercept=$maxIntercept
elif [ $(bc <<< "$yIntercept < -30000") -eq 1 ]; then
  yIntercept=-30000
fi 

echo "After bounds check, slope=$slope, yIntercept=$yIntercept"

# store the calibration in a json file for use by xdrip-get-entries.sh
echo "[{\"slope\":$slope, \"yIntercept\":$yIntercept, \"formula\":\"calibratedbg=(unfiltered-yIntercept)/slope\"}]" > $OUTPUT 

echo "Created $OUTPUT"
cat $OUTPUT


