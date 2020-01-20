#!/bin/bash

common_funcs="/root/src/Logger/bin/logger-common-funcs.sh"
if [ ! -e $common_funcs ]; then
  echo "ERROR: Failed to run logger-common-funcs.sh. Is Logger correctly installed?"
  exit 1
fi 
source $common_funcs 

#KNOWN_G5_FIRMWARES = ("1.0.0.13", "1.0.0.17", "1.0.4.10", "1.0.4.12");
#KNOWN_G6_FIRMWARES = ("1.6.5.23", "1.6.5.25", "1.6.5.27");
#KNOWN_G6_REV2_FIRMWARES = ("2.18.2.67", "2.18.2.88");
#KNOWN_TIME_TRAVEL_TESTED = ("1.6.5.25");

function testVersion()
{
  if [ "$(newFirmware $version)" == "true" ]; then
    echo "'$version' is new firmware"
  else
    echo "'$version' is not new firmware"
  fi
}

echo "real version test"
version=$(txVersion)&& testVersion
echo "fake version tests"
version="1.6.5.27" && testVersion
version="2.18.2.67" && testVersion
version="2.18.2.88" && testVersion
version="1.0.0.17" && testVersion
version="" && testVersion
version="1.6.5.25" && testVersion


