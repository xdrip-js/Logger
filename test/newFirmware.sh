#!/bin/bash

#KNOWN_G5_FIRMWARES = ("1.0.0.13", "1.0.0.17", "1.0.4.10", "1.0.4.12");
#KNOWN_G6_FIRMWARES = ("1.6.5.23", "1.6.5.25", "1.6.5.27");
#KNOWN_G6_REV2_FIRMWARES = ("2.18.2.67", "2.18.2.88");
#KNOWN_TIME_TRAVEL_TESTED = ("1.6.5.25");

function newFirmware()
{
  local version=$1
  case $version in
    1.6.5.27 | 2.*)
      echo true 
      ;;
    *)
      echo false 
      ;;
  esac
}

version="1.6.5.27"
if [ "$(newFirmware $version)" == "true" ]; then
  echo "$version is new firmware"
else
  echo "$version is not new firmware"
fi


version="2.18.2.88"
if [ "$(newFirmware $version)" == "true" ]; then
  echo "$version is new firmware"
else
  echo "$version is not new firmware"
fi

version="1.0.0.17" 
if [ "$(newFirmware $version)" == "true" ]; then
  echo "$version is new firmware"
else
  echo "$version is not new firmware"
fi

version=""
if [ "$(newFirmware $version)" == "true" ]; then
  echo "$version is new firmware"
else
  echo "$version is not new firmware"
fi

version="1.6.5.25"
if [ "$(newFirmware $version)" == "true" ]; then
  echo "$version is new firmware"
else
  echo "$version is not new firmware"
fi


