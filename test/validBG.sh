#!/bin/bash

function log()
{
  echo $1
}


function validNumber()
{
  local num=$1
  case ${num#[-+]} in
    *[!0-9.]* | '') echo false ;;
    * ) echo true ;;
  esac
}


function validBG()
{
  local bg=$1
  local valid="false"

  if [ "$(validNumber $bg)" == "true" ]; then
    if [ $(bc  -l <<< "$bg >= 20") -eq 1 -a $(bc -l <<< "$bg < 500") -eq 1 ]; then
      valid="true"
    fi
  fi
  
  echo $valid
}

LDIR=~/myopenaps/monitor/xdripjs
#unfiltered=110
filtered=111
raw=$unfiltered
epochdate=$(date +'%s')



#unfiltered=$(cat ${LDIR}/entry.json | jq -M '.[0].uknfiltered')
#unfiltered=$(bc -l <<< "scale=0; $unfiltered / 1000")


b=111
if [ "$(validBG $b)" == "true" ]; then
  echo "$b=valid"
else
  echo "$b=invalid"
fi

b=611
if [ "$(validBG $b)" == "true" ]; then
  echo "$b=valid"
else
  echo "$b=invalid"
fi

#echo "unfiltered=$unfiltered"

echo "validBG undefined($fkiltered)=$(validBG $fkiltered)"

filtered="what"
echo "validBG $filtered=$(validBG $filtered)"

filtered=111
echo "validBG $filtered=$(validBG $filtered)"

filtered=511
echo "validBG $filtered=$(validBG $filtered)"

filtered=111.000
echo "validBG $filtered=$(validBG $filtered)"

filtered=
echo "validBG $filtered=$(validBG $filtered)"

filtered=11
echo "validBG $filtered=$(validBG $filtered)"
