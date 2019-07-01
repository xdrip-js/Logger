#!/bin/bash

#"${epochdate},${unfiltered},${filtered},${calibratedBG}" >> ./noise-input.csv
# calculate the noise from csv input (format shown above) and put the noise in ./noise.json
# calculated noise is a floating point number from 0 to 1 where 0 is the cleanest and 1 is the noisiest
#
# Calculate the sum of the distance of all points (overallDistance)
# Calculate the overall distance of between the first and last point (sod)
# Calculate noise as the following formula 1 - sod/overallDistance
# noise will get closer to zero as the sum of the individual lines are mostly in a straight or straight moving curve
# noise will get closer to one as the sum of the distance of the individual lines gets large 
# also added multiplier to get more weight to the latest BG values
# also added weight for points where the delta shifts from pos to neg or neg to pos (peaks/valleys)
# the more peaks and valleys, the more noise is amplified

INPUT=${1:-"${HOME}/myopenaps/monitor/xdripjs/noise-input41.csv"}
OUTPUT=${2:-"${HOME}/myopenaps/monitor/xdripjs/noise.json"}
MAXRECORDS=12
MINRECORDS=4

function ReportNoiseAndExit()
{
  echo "[{\"noise\":$noise}]" > $OUTPUT
  cat $OUTPUT
  exit
}

if [ -e $INPUT ]; then
  yarr=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f2 ) )
  n=${#yarr[@]}
else
  noise=0.5
  ReportNoiseAndExit
fi

#    set initial x values based on date differences

if [ $(bc <<< "$n < $MINRECORDS") -eq 1 ]; then
  # set noise = 0 - unknown
  noise=0.5
	#echo "noise = 0 no records"
  ReportNoiseAndExit
fi

#echo ${yarr[@]}

# sod = sum of distances
sod=0
overallDistance=0

# add 0.1 for each bounce
# allow 5 point rises without adding noise
lastDelta=0
noise=0
for (( i=1; i<$n; i++ ))
do
  y2y1Delta=$(bc -l  <<< "${yarr[$i]} - ${yarr[$i-1]}")
  if [ $(bc -l <<< "$y2y1Delta < 0") -eq 1 ]; then
    y2y1Delta=$(bc -l <<< "0 - $y2y1Delta")
  fi
  remainder=$(bc -l <<< "$y2y1Delta - 10")
  if [ $(bc -l <<< "$remainder > 0") -eq 1 ]; then
    noise=$(bc -l <<< "$noise + $remainder/200") 
  fi
  
  if [ $(bc -l <<< "$lastDelta > 0") -eq 1 -a $(bc <<< "$y2y1Delta < 0") -eq 1 ]; then
    noise=$(bc -l "$noise + 0.1")
  elif [ $(bc -l <<< "$lastDelta < 0") -eq 1 -a $(bc -l <<< "$y2y1Delta > 0") -eq 1 ]; then
    noise=$(bc -l "$noise + 0.15")
  fi
  #echo "y2y1Delta = $y2y1Delta, remainder=$remainder, noise=$noise"
done

if [ $(bc -l <<< "$noise > 1") -eq 1 ]; then
  noise=1
fi
noise=$(printf "%.*f\n" 5 $noise)
ReportNoiseAndExit

