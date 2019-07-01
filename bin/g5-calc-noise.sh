#!/bin/bash

#"${epochdate},${unfiltered},${filtered},${calibratedBG}" >> ./noise-input.csv
# calculate the noise from csv input (format shown above) and put the noise in ./noise.json
# noise is a floating point number from 0 to 1 where 0 is the cleanest and 1 is the noisiest
# also added multiplier to get more weight to the latest BG values
# also added weight for points where the delta shifts from pos to neg or neg to pos (peaks/valleys)
# the more peaks and valleys, the more noise is amplified
# add 0.12 for each peak and 0.17 for each valley
# allow 18 point rises without adding noise

inputFile=${1:-"${HOME}/myopenaps/monitor/xdripjs/noise-input41.csv"}
outputFile=${2:-"${HOME}/myopenaps/monitor/xdripjs/noise.json"}
MAXRECORDS=12
MINRECORDS=4
# This variable will be 41minutes unless variation of filtered / unfiltered gives a higher noise, then it will be "lastVariation"
calculatedBy="41minutes"

function ReportNoiseAndExit()
{
  if [ $(bc -l <<< "$noise < 0.45") -eq 1 ]; then
      noiseSend=1
      noiseString="Clean"
  elif [ $(bc -l <<< "$noise < 0.55") -eq 1 ]; then
    noiseSend=2
    noiseString="Light"
  elif [ $(bc -l <<< "$noise < 0.7") -eq 1 ]; then
    noiseSend=3
    noiseString="Medium"
  elif [ $(bc -l <<< "$noise >= 0.7") -eq 1 ]; then
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
  noise=0.9  # Heavy noise -- no input file 
  ReportNoiseAndExit
fi


if [ $(bc <<< "$n < $MINRECORDS") -eq 1 ]; then
  # set noise = 0 - unknown
  noise=0.5 # Light noise - not enough records, just starting out
  ReportNoiseAndExit
fi

#echo ${unfilteredArray[@]}
#echo ${filteredArray[@]}

lastDelta=0
noise=0
for (( i=1; i<$n; i++ ))
do
  delta=$(bc <<< "${unfilteredArray[$i]} - ${unfilteredArray[$i-1]}")
  if [ $(bc <<< "$lastDelta > 0") -eq 1 -a $(bc <<< "$delta < 0") -eq 1 ]; then
    noise=$(bc -l <<< "$noise + 0.12")
elif [ $(bc <<< "$lastDelta < 0") -eq 1 -a $(bc <<< "$delta > 0") -eq 1 ]; then
    noise=$(bc -l <<< "$noise + 0.17")
  fi

  absDelta=$delta
  if [ $(bc <<< "$delta < 0") -eq 1 ]; then
    absDelta=$(bc <<< "0 - $delta")
  fi
  remainder=$(bc <<< "$absDelta - 18")
  if [ $(bc <<< "$remainder > 0") -eq 1 ]; then
    # noise higher impact for latest bg, thus the smaller denominator for the remainder fraction 
    noise=$(bc -l <<< "$noise + $remainder/(300 - $i*30)") 
  else
    remainder=0
  fi
  
  #echo "lastdelta=$lastDelta, delta=$delta, remainder=$remainder, noise=$noise, absDelta=$absDelta"

  lastDelta=$delta
done

# get latest filtered / unfiltered for variation check
filtered=${filteredArray[$n-1]}
unfiltered=${unfilteredArray[$n-1]}
#echo "filtered=$filtered, unfiltered=$unfiltered"
variationNoise=$(bc -l <<< "((($filtered - $unfiltered) * 1.3) / $filtered)")

if [ $(bc -l <<< "$variationNoise < 0") -eq 1 ]; then
  variationNoise=$(bc -l <<< "0 - $variationNoise")
fi


if [ $(bc -l <<< "$variationNoise > $noise") -eq 1 ]; then
  noise=$variationNoise
  calculatedBy="lastVariation"
fi 

if [ $(bc -l <<< "$noise > 1") -eq 1 ]; then
  noise=1
fi

noise=$(printf "%.*f\n" 5 $noise)
ReportNoiseAndExit

