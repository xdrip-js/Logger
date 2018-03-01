#!/bin/bash

CALIBRATE="/usr/local/bin/calibrate"
rm -f $CALIBRATE 
ln -s /root/src/xdrip-js-logger/bin/calibrate.sh $CALIBRATE

NOISE="/usr/local/bin/logger-noise"
rm -f $NOISE 
ln -s /root/src/xdrip-js-logger/noise.sh $NOISE

if type "go" > /dev/null; then
  echo "building calc-noise.go"
  go build calc-noise.go
  ls -al calc-noise
fi

