#!/bin/bash

MESSAGE="${HOME}/myopenaps/monitor/xdripjs/cgm-version.json"
epochdate=$(date +'%s%3N')

echo "Requesting the Dexcom Transmitter version number"
echo "Monitor the Logger logfile to view the version number"

echo "[{\"date\":\"${epochdate}\",\"type\":\"VersionRequest\"}]" >  $MESSAGE
cat $MESSAGE
echo
echo "VersionRequest message sent to Logger"
echo "Monitor the Logger logfile to view the version number"
