#!/bin/bash

MESSAGE="${HOME}/myopenaps/monitor/logger/g5-reset.json"
epochdate=$(date +'%s%3N')

echo "Running this command will instruct Logger to reset the g5 Transmitter!"
echo "   Your current session will be lost and will have to be restarted using g5-start" 

read -p "Are you sure? (y/n)" -n 1 -r
echo    
if [[ $REPLY =~ ^[Yy]$ ]]
then
  echo "[{\"date\":\"${epochdate}\",\"type\":\"ResetTx\"}]" >  $MESSAGE
  cat $MESSAGE
  echo
  echo "ResetTx message sent to Logger"
  echo "Wait 5 to 10 minutes for message to be processed"
else
  echo "ResetTx message not sent to Logger"
fi
