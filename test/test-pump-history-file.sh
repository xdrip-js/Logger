#!/bin/bash

function testpumphistory()
{

if [ -e "$HOME/myopenaps/monitor/pumphistory-zoned.json" ]; then
   echo found first file
else
  if [ -e "$HOME/myopenaps/monitor/pumphistory-24h-zoned.json" ]; then
   echo found second file
  fi
fi

historyFile="$HOME/myopenaps/monitor/pumphistory-24h-zoned.json"
if [ ! -e "$historyFile" ]; then
  echo did not find $historyFile
else
  echo found $historyFile
fi

}

testpumphistory
