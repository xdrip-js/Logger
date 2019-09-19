#!/bin/bash
set -v
:&&:&&:&&:&& df -h | grep -v tmpfs
:&&:&&:&&:&& cgm-battery
:&&:&&:&&:&& bluetoothd -v
:&&:&&:&&:&& cgm-noise 2
:&&:&&:&&:&& cat ~/myopenaps/xdripjs.json
:&&:&&:&&:&& bt-device -l
:&&:&&:&&:&& crontab -l | grep Logger
:&&:&&:&&:&& tail -8 ~/myopenaps/monitor/xdripjs/calibrations.csv
:&&:&&:&&:&& cat ~/myopenaps/monitor/xdripjs/calibration-linear.json
:&&:&&:&&:&& tail -12 /var/log/openaps/logger-loop.log
echo

