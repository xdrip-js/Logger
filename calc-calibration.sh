#!/bin/bash

# test.csv order is from oldest calibration at the top to latest calibration at the bottom
# test.csv in the form of 
# unfiltered,meterbg,datetime
#Rule 1 - Clear calibration records upon CGM Sensor Change/Insert
#Rule 2 - Don't allow any BG calibrations or take in any new calibrations 
#         within 15 minutes of last sensor insert
#Rule 3 - Only use Single Point Calibration for 1st 12 hours since Sensor insert
#Rule 4 - Do not store calibration records within 12 hours since Sensor insert. 
#         Use for SinglePoint calibration, but then discard them
#Rule 5 - Do not use LSR until we have 4 or more calibration points. 
#          Use SinglePoint calibration only for less than 4 calibration points. 
#          SinglePoint simply uses the latest calibration record and assumes 
#          the yIntercept is 0.
#Rule 6 - Drop back to SinglePoint calibration if slope is out of bounds 
#          (>MAXSLOPE or <MINSLOPE)
#Rule 7 - Drop back to SinglePoint calibration if yIntercept is out of bounds 
#         (> minimum unfiltered value in calibration record set or 
#          < - minimum unfiltered value in calibration record set)
#
# yarr = array of last unfiltered values associated w/ bg meter checks 
# xarr = array of last bg meter check bg values

INPUT=${1:-"calibrations.csv"}
OUTPUT=${2:-"calibration-linear.json"}
MAXSLOPE=1450
MINSLOPE=550
MAXRECORDS=8
MINRECORDSFORLSR=3
rSquared=0

yarr=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f1 ) )
xarr=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f2 ) )
tdate=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f4 ) )

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

  usingDates=0
  local firstDate=${tdate[0]}
  local re='^[0-9]+$'
  if [[ $firstDate =~ $re ]]; then 
    for (( i=0; i<$n; i++ ))
    do
      tarr[$i]=$(bc <<< "${tdate[$i]} - $firstDate") 
    done
    # avoid divide by zero if times are somehow the same in csv input file (shouldn't be) 
    if [ $(bc <<< "${tarr[$n-1]} != 0") -eq 1 ]; then
      usingDates=1
    fi
  fi
 
  local multiplier=1
  

  for (( i=0; i<$n; i++ ))
  do
    if [ $(bc <<< "$i != 0") -eq 1 -a $(bc <<< "$usingDates == 1") -eq 1 ]; then
      multiplier=$(bc -l <<< "1 + ${tarr[$i-1]} / (${tarr[$n-1]} * 2)")
      # boundary check
      if [ $(bc -l <<< "$multiplier < 1") -eq 1 -o $(bc -l <<< "$multiplier > 2") -eq 1 ]; then
        multiplier=1
      fi
    fi
    echo "Calibration - record $i, time(${tdate[$i]}), weighted multiplier=$multiplier" 
    sumXY=$(bc -l <<< "($sumXY + ${xarr[i]} * ${yarr[i]}) * $multiplier")
    sumXSq=$(bc -l <<< "($sumXSq + ${xarr[i]} * ${xarr[i]}) * $multiplier")
    sumYSq=$(bc -l <<< "($sumYSq + ${yarr[i]} * ${yarr[i]}) * $multiplier")
  done  
  denominator=$(bc -l <<< "sqrt((($n * $sumXSq - ${sumX}^2) * ($n * $sumYSq - ${sumY}^2)))")
  if [ $(bc <<< "$denominator == 0") -eq 1 -o  $(bc <<< "$stddevX == 0") -eq 1 ] ; then
    slope=1000
    yIntercept=0
  else
    r=$(bc -l <<< "($n * $sumXY - $sumX * $sumY) / $denominator")
    rSquared=$(bc -l <<< "(${r})^2")
    rSquared=$(printf "%.*f\n" 5 $rSquared)


    slope=$(bc -l <<< "$r * $stddevY / $stddevX ")
    yIntercept=$(bc -l <<< "$meanY - $slope * $meanX ")


  # calculate error
    local varSum=0
    for (( j=0; j<$n; j++ ))
    do
      varSum=$(bc -l <<< "$varSum + (${yarr[$j]} - $yIntercept - $slope * ${xarr[$j]})^2")   
    done

    local delta=$(bc -l <<< "$n * $sumXSq - ($sumX)^2")  
    local vari=$(bc -l <<< "1.0 / ($n - 2.0) * $varSum")
  
    yError=$(bc -l <<< "sqrt($vari / $delta * $sumXSq)") 
    slopeError=$(bc -l <<< "sqrt($n / $delta * $vari)")
  fi
}



function SinglePointCalibration
{
  if [ "$numx" -gt "0" ]; then
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
slope=1000
yIntercept=0
slopeError=0
yError=0

if [ $(bc -l <<< "$numx >= $MINRECORDSFORLSR") -eq 1 ]; then
  echo "Calibration records = $numx, attempting to use LeastSquaresRegression" 
  LeastSquaresRegression
  calibrationType="LeastSquaresRegression"
elif [ $(bc -l <<< "$numx > 0") -eq 1 ]; then
  echo "Calibration records = $numx, using single point linear" 
  SinglePointCalibration
else
  slope=1000
  yIntercept=0
fi

# truncate and bounds check
yIntercept=$(bc <<< "$yIntercept / 1") # truncate
slope=$(bc <<< "$slope / 1") # truncate
yError=$(bc <<< "$yError / 1") # truncate
slopeError=$(bc <<< "$slopeError / 1") # truncate

# Set max yIntercept to the minimum of the set of unfiltered values
maxIntercept=$(MathMin "${yarr[@]}")

echo "Calibration - Before bounds check, slope=$slope, yIntercept=$yIntercept"

# Check for boundaries and fall back to Single Point Calibration if necessary
if [ $(bc <<< "$slope > $MAXSLOPE") -eq 1 ]; then
  echo "slope of $slope > maxSlope of $MAXSLOPE, using single point linear" 
  SinglePointCalibration
elif [ $(bc <<< "$slope < $MINSLOPE") -eq 1 ]; then
  echo "slope of $slope < minSlope of $MINSLOPE, using single point linear" 
  SinglePointCalibration
fi 

if [ $(bc  <<< "$yIntercept > $maxIntercept") -eq 1 ]; then
  echo "yIntercept of $yIntercept > maxIntercept of $maxIntercept, using single point linear" 
  SinglePointCalibration
elif [ $(bc <<< "$yIntercept < (0 - $maxIntercept)") -eq 1 ]; then
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


