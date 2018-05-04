#!/bin/bash

CALIBRATE="/usr/local/bin/calibrate"
rm -f $CALIBRATE 
ln -s /root/src/xdrip-js-logger/bin/calibrate.sh $CALIBRATE

NOISE="/usr/local/bin/g5-noise"
rm -f $NOISE 
ln -s /root/src/xdrip-js-logger/bin/g5-noise.sh $NOISE

STOP="/usr/local/bin/g5-stop"
rm -f $STOP 
ln -s /root/src/xdrip-js-logger/bin/g5-stop.sh $STOP

START="/usr/local/bin/g5-start"
rm -f $START 
ln -s /root/src/xdrip-js-logger/bin/g5-start.sh $START

BATTERY="/usr/local/bin/g5-battery"
rm -f $BATTERY 
ln -s /root/src/xdrip-js-logger/bin/g5-battery.sh $BATTERY

RESET="/usr/local/bin/g5-reset"
rm -f $RESET 
ln -s /root/src/xdrip-js-logger/bin/g5-reset.sh $RESET

if type "go" > /dev/null; then
  echo "building calc-noise.go"
  go build calc-noise.go
  ls -al calc-noise
fi

