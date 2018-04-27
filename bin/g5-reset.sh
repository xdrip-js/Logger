#!/bin/bash

MESSAGE="/root/myopenaps/monitor/g5-reset.json"
epochdate=$(date +'%s%3N')

echo "Running this command will instruct Logger to reset the g5 Transmitter!" 

read -p "Are you sure? (y/n)" -n 1 -r
echo    
if [[ $REPLY =~ ^[Yy]$ ]]
then
    # do dangerous stuff
  echo "[{\"date\":\"${epochdate}\",\"type\":\"ResetSensor\"}]" >  $MESSAGE
  cat $MESSAGE
  echo
  echo "ResetTx message sent to Logger"
  echo "Wait 5 to 10 minutes for message to be processed"
else
  echo "ResetTx message not sent to Logger"
fi
