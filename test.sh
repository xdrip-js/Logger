#!/bin/bash

function compile_messages()
{
  files=""
  mfile="./messages.json"
  touch $mfile
  cp ${mfile} "${mfile}.last"
  rm -f $mfile
  touch $mfile

  if [ "${calibrationJSON}" != "" ]; then
    tmp=$(mktemp)
    echo "${calibrationJSON}" > $tmp
    files="$tmp"
  fi

  if [ "${stopJSON}" != "" ]; then
    tmp=$(mktemp)
    echo "${stopJSON}" > $tmp
    files="$files $tmp"
  fi

  if [ "${startJSON}" != "" ]; then
    tmp=$(mktemp)
    echo "${startJSON}" > $tmp
    files="$files $tmp"
  fi

  if [ "${resetJSON}" != "" ]; then
    tmp=$(mktemp)
    echo "${resetJSON}" > $tmp
    files="$files $tmp"
  fi

  if [ "$files" != "" ]; then
    jq -c -s add $files > $mfile
    rm -f $files
  fi

  messages=$(cat $mfile)
}

function initialize_messages()
{
  calibrationJSON=""
  stopJSON=""
  startJSON=""
  resetJSON=""
}


initialize_messages


calibrationJSON="[{\"date\": 1231231000, \"type\": \"CalibrateSensor\",\"glucose\": 100}]"
startJSON="[{\"date\": 1231231000, \"type\": \"CalibrateSensor\",\"glucose\": 101}]"


compile_messages

echo "${messages}"
