#!/bin/bash

# test.csv order is from oldest calibration at the top to latest calibration at the bottom
# test.csv in the form of 
# unfiltered,meterbg,datetime
#
# yarr = array of up to 11 last unfiltered values associated with xarr bg meter checks / calibrations
# xarr = array of up to 11 last bg meter checks / calibrations

INPUT=${1:-"calibrations.csv"}
OUTPUT=${2:-"calibration-linear.json"}
MAXSLOPE=1450
MINSLOPE=550
MAXRECORDS=8
MINRECORDSFORLSR=4
rSquared=0

yarr=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f1 ) )
xarr=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f2 ) )

echo "Begin calibration using input of $INPUT and output of $OUTPUT"

# Future how to compare date values if we want to limit calibration set to a timeframe
#    dt1970arr[$i]=`date +%s --date="${dtarr[$i]}"`
#    set initial i value based on date differences
# dtarr=( $(tail -11 $INPUT | cut -d ',' -f3 ) )

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
  rSquared=$(bc -l <<< "(${r})^2")
#  echo "r=$r, n=$n, sumXSq=$sumXSq, sumYSq=$sumYSq"
#  echo "sumY=$sumY, sumX=$sumX, stddevX=$stddevX, stddevY=$stddevY" 

  m=$(bc -l <<< "$r * $stddevY / $stddevX ")
  b=$(bc -l <<< "$meanY - $m * $meanX ")

#  echo "m=$m, b=$b" 
# sets global variables slope and yIntercept
  slope=$m
  yIntercept=$b

# calculate error
  local varSum=0
  for (( j=0; j<$n; j++ ))
  do
    varSum=$(bc -l <<< "$varSum + (${yarr[$j]} - $b - $m * ${xarr[$j]})^2")   
  done

  local delta=$(bc -l <<< "$n * $sumXSq - ($sumX)^2")  
  local vari=$(bc -l <<< "1.0 / ($n - 2.0) * $varSum")
  
  yError=$(bc -l <<< "sqrt($vari / $delta * $sumXSq)") 
  slopeError=$(bc -l <<< "sqrt($n / $delta * $vari)")
}



function SinglePointCalibration
{
  if [ "$numx" -gt "0" ]; then
    # for less than $MINRECORDSFORLSR calibrations, 
    # fall back to single point calibration
    # get the last entry for x and y
    x=${xarr[-1]}
    y=${yarr[-1]}
    yIntercept=0
    slope=$(bc -l <<< "$y / $x")
    calibrationType="SinglePoint"
    echo "x=$x, y=$y, slope=$slope, yIntercept=0" 
  fi
}

#echo "${xarr[@]}"

#get the number of calibrations
numx=${#xarr[@]}
slope=0
yIntercept=1000
slopeError=0
yError=0

if [ $(bc -l <<< "$numx >= $MINRECORDSFORLSR") -eq 1 ]; then
  echo "Calibration records = $numx, using LeastSquaresRegression" 
  LeastSquaresRegression
  calibrationType="LeastSquaresRegression"
else
  echo "Calibration records = $numx, using single point linear" 
  SinglePointCalibration
fi

# truncate and bounds check
yIntercept=$(bc <<< "$yIntercept / 1") # truncate
slope=$(bc <<< "$slope / 1") # truncate
yError=$(bc <<< "$yError / 1") # truncate
slopeError=$(bc <<< "$slopeError / 1") # truncate

# Set max yIntercept to the minimum of the set of unfiltered values
maxIntercept=$(MathMin "${yarr[@]}")

echo "Calibration - Before bounds check, slope=$slope, yIntercept=$yIntercept"

if [ $(bc <<< "$slope > $MAXSLOPE") -eq 1 ]; then
  # fall back to Single Point in this case
  echo "slope of $slope > maxSlope of $MAXSLOPE, using single point linear" 
  SinglePointCalibration
elif [ $(bc <<< "$slope < $MINSLOPE") -eq 1 ]; then
  # fall back to Single Point in this case
  echo "slope of $slope < minSlope of $MINSLOPE, using single point linear" 
  SinglePointCalibration
fi 

if [ $(bc  <<< "$yIntercept > $maxIntercept") -eq 1 ]; then
  # fall back to Single Point in this case
  echo "yIntercept of $yIntercept > maxIntercept of $maxIntercept, using single point linear" 
  SinglePointCalibration
elif [ $(bc <<< "$yIntercept < (0 - $maxIntercept)") -eq 1 ]; then
  # fall back to Single Point in this case
  echo "yIntercept of $yIntercept < negative maxIntercept of -$maxIntercept, using single point linear" 
  SinglePointCalibration
  echo "x=$x, y=$y, slope=$slope, yIntercept=0" 
fi 


# check slope again if SinglePoint for safety
# this is for the case that we fell back to SinglePoint
# to make sure that we don't have use without bounds a potentiall bad 
# or mistaken calibration recent record
if [ "$calibrationType" == "SinglePoint" ]; then
  if [ $(bc <<< "$slope > $MAXSLOPE") -eq 1 ]; then
    echo "single point slope of $slope > maxSlope of $MAXSLOPE, using $MAXSLOPE" 
    slope=$MAXSLOPE
  elif [ $(bc <<< "$slope < $MINSLOPE") -eq 1 ]; then
    echo "single point slope of $slope < minSlope of $MINSLOPE, using $MINSLOPE" 
    slope=$MINSLOPE
  fi 
fi

yIntercept=$(bc <<< "$yIntercept / 1") # truncate
slope=$(bc <<< "$slope / 1") # truncate

echo "Calibration - After bounds check, slope=$slope, yIntercept=$yIntercept"
echo "Calibration - slopeError=$slopeError, yError=$yError"

# store the calibration in a json file for use by xdrip-get-entries.sh
echo "[{\"slope\":$slope, \"yIntercept\":$yIntercept, \"formula\":\"calibratedbg=(unfiltered-yIntercept)/slope\", \"yError\":$yError, \"slopeError\":${slopeError}, \"rSquared\":${rSquared}, \"numCalibrations\":${numx}, \"calibrationType\":\"${calibrationType}\"}]" > $OUTPUT 

echo "Calibration - Created $OUTPUT"
cat $OUTPUT

#ConvertDateArray


