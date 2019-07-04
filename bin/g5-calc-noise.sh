#!/bin/bash

#"${epochdate},${unfiltered},${filtered},${calibratedBG}" >> ./noise-input.csv
# calculate the noise from csv input (format shown above) and put the noise in ./noise.json
# noise is a floating point number from 0 to 1 where 0 is the cleanest and 1 is the noisiest
# also added multiplier to get more weight to the latest BG values
# also added weight for points where the delta shifts from pos to neg or neg to pos (peaks/valleys)
# the more peaks and valleys, the more noise is amplified
# add 0.06 (times oldness degrading factor) for each peak/valley 
# allow 7 point rises without adding noise

inputFile=${1:-"${HOME}/myopenaps/monitor/xdripjs/noise-input41.csv"}
outputFile=${2:-"${HOME}/myopenaps/monitor/xdripjs/noise.json"}
MAXRECORDS=12
MINRECORDS=3
PEAK_VALLEY_FACTOR=0.06 # Higher means more weight on peaks / valleys
RISE_WITHOUT_ADDED_NOISE=12 # Lower means more weight on deltas
CLEAN_MAX_AVG_DELTA=6
LIGHT_MAX_AVG_DELTA=9
NO_NOISE=0.00
CLEAN_MAX_NOISE=0.45
LIGHT_MAX_NOISE=0.60
MEDIUM_MAX_NOISE=0.75
HEAVY_MAX_NOISE=1.00
# This variable will be "41minutes" unless variation of filtered / unfiltered gives a higher noise, then it will be "lastVariation"
calculatedBy="41minutes"

function ReportNoiseAndExit()
{
  if [ $(bc -l <<< "$noise <= $CLEAN_MAX_NOISE ") -eq 1 ]; then
      noiseSend=1
      noiseString="Clean"
  elif [ $(bc -l <<< "$noise <= $LIGHT_MAX_NOISE") -eq 1 ]; then
    noiseSend=2
    noiseString="Light"
  elif [ $(bc -l <<< "$noise <= $MEDIUM_MAX_NOISE") -eq 1 ]; then
    noiseSend=3
    noiseString="Medium"
  elif [ $(bc -l <<< "$noise > $MEDIUM_MAX_NOISE") -eq 1 ]; then
    noiseSend=4
    noiseString="Heavy"
  fi

  echo "[{\"noise\":$noise, \"noiseSend\":$noiseSend, \"noiseString\":\"$noiseString\",\"calculatedBy\":\"$calculatedBy\"}]" > $outputFile
  cat $outputFile
  exit
}

if [ -e $inputFile ]; then
  unfilteredArray=( $(tail -$MAXRECORDS $inputFile | cut -d ',' -f2 ) )
  filteredArray=( $(tail -$MAXRECORDS $inputFile | cut -d ',' -f3 ) )
  n=${#unfilteredArray[@]}
else
  noise=$HEAVY_MAX_NOISE  # Heavy if no input file 
  calculatedBy="noInput"
  ReportNoiseAndExit
fi


if [ $(bc <<< "$n < $MINRECORDS") -eq 1 ]; then
  # set noise = 0 - unknown
  noise=$MEDIUM_MAX_NOISE # Light if not enough records, just starting out
  calculatedBy="tooFewRecords"
  ReportNoiseAndExit
fi

#echo ${unfilteredArray[@]}
#echo ${filteredArray[@]}

sod=0
lastDelta=0
noise=$NO_NOISE
for (( i=1; i<$n; i++ ))
do
  delta=$(bc <<< "${unfilteredArray[$i]} - ${unfilteredArray[$i-1]}")
  if [ $(bc <<< "$lastDelta > 0") -eq 1 -a $(bc <<< "$delta < 0") -eq 1 ]; then
    # this is a peak and change of direction
    # the older the peak, the less add to noise
    noise=$(bc -l <<< "$noise + $PEAK_VALLEY_FACTOR * (($n - $i * 0.5)/$n)")
  elif [ $(bc <<< "$lastDelta < 0") -eq 1 -a $(bc <<< "$delta > 0") -eq 1 ]; then
    # this is a valley and change of direction
    # the older the valley, the less add to noise
    noise=$(bc -l <<< "$noise + $PEAK_VALLEY_FACTOR * (($n - $i * 0.5)/$n)")
  fi

  absDelta=$delta
  if [ $(bc <<< "$delta < 0") -eq 1 ]; then
    absDelta=$(bc <<< "0 - $delta")
  fi
  # calculate sum of distances (all deltas) 
  sod=$(bc <<< "$sod + $absDelta")

  # Any single jump amount over a certain limit increases noise linearly
  remainder=$(bc <<< "$absDelta - $RISE_WITHOUT_ADDED_NOISE")
  if [ $(bc <<< "$remainder > 0") -eq 1 ]; then
    # noise higher impact for latest bg, thus the smaller denominator for the remainder fraction 
    noise=$(bc -l <<< "$noise + $remainder/(300 - $i*30)") 
  else
    remainder=0
  fi
  
  #echo "lastdelta=$lastDelta, delta=$delta, remainder=$remainder" 
  #echo "sod=$sod, noise=$noise, absDelta=$absDelta"

  lastDelta=$delta
done

# to ensure mostly straight lines with small bounces don't give heavy noise
  if [ $(bc -l <<< "$noise > $CLEAN_MAX_NOISE") -eq 1 ]; then
    if [ $(bc -l <<< "($sod / $n) < $CLEAN_MAX_AVG_DELTA") -eq 1 ]; then
     noise=$CLEAN_MAX_NOISE # very small up/downs shouldn't cause noise 
    elif [ $(bc -l <<< "($sod / $n) < $LIGHT_MAX_AVG_DELTA") -eq 1 ]; then
     noise=$LIGHT_MAX_NOISE # small up/downs shouldn't cause Medium Heavy noise
    fi
  fi

# get latest filtered / unfiltered for variation check
filtered=${filteredArray[$n-1]}
unfiltered=${unfilteredArray[$n-1]}
#echo "filtered=$filtered, unfiltered=$unfiltered"
# calculate alternate form of noise from last variation
variationNoise=$(bc -l <<< "((($filtered - $unfiltered) * 1.3) / $filtered)")

# make sure the variationNoise is positive
if [ $(bc -l <<< "$variationNoise < 0") -eq 1 ]; then
  variationNoise=$(bc -l <<< "0 - $variationNoise")
fi


# If the variationNoise is higher than the 41minute calculated noise, then use variationNoise it instead
if [ $(bc -l <<< "$variationNoise > $noise") -eq 1 ]; then
  noise=$variationNoise
  calculatedBy="lastVariation"
fi 

# Cap noise at 1 as the highest value
if [ $(bc -l <<< "$noise > 1") -eq 1 ]; then
  noise=$HEAVY_MAX_NOISE
fi

noise=$(printf "%.*f\n" 5 $noise)
ReportNoiseAndExit

