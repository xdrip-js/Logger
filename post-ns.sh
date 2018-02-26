#!/bin/bash

source ~/.bash_profile

INPUT=${1:-""}
NSTYPE=${2:-"entries"}


export NIGHTSCOUT_HOST
export API_SECRET

ns_url="${NIGHTSCOUT_HOST}"
ns_secret="${API_SECRET}"
    
# exit codes
# -1 ==> INPUT file doesn't exist
# 0 ==> success
# other ==> curl_status
 
curl_status=-1

if [ -e $INPUT ]; then
  curl --compressed -f -m 30 -s -X POST -d @$INPUT \
  -H "API-SECRET: $ns_secret" \
  -H "Content-Type: application/json" \
  "${ns_url}/api/v1/${NSTYPE}.json"
  curl_status=$?
fi

exit $curl_status
