#!/bin/bash

function check_ip {
  PUBLIC_IP=$(curl --compressed -4 -s -m 15 checkip.amazonaws.com | awk -F , '{print $NF}' | egrep "^[12]*[0-9]*[0-9]\.[12]*[0-9]*[0-9]\.[12]*[0-9]*[0-9]\.[12]*[0-9]*[0-9]$")
  if [[ -z $PUBLIC_IP ]]; then
    echo not found
    return 1
  else
    echo $PUBLIC_IP
  fi
}

if check_ip; then
  exit 0
else
  exit 1
fi
