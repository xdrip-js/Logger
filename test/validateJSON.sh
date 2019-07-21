#!/bin/bash

function checkJSON()
{
  local json_string=$1
  jqType=$(jq type  <<< "$json_string")
  if [[ "$jqType" == *"array"* ]]; then
      echo "success, jqType=$jqType, string= $json_string"
  else
      echo "failure, jqType=$jqType, string= $json_string"
  fi
}

checkJSON "[{\"date\":1563014402000,\"type\":\"CalibrateSensor\",\"glucose\":85}]"
checkJSON "[{\"date\"s:1563014402000,\"type\":\"CalibrateSensor\",\"glucose\":85}]"
checkJSON ""
checkJSON
checkJSON "0"
checkJSON "[]"
checkJSON "[date:4]"

exit

timestamp="2019-07-10T19:25:36-04:00"


epochdate=`date --date="$timestamp" +"%s"`

createdAt=$(date -d @$epochdate +'%Y-%m-%dT%H:%M:%S.%3NZ')
echo timestamp=$timestamp
echo epochdate=$epochdate
echo createdAt=$createdAt






