#!/bin/bash

epochdate=$(date +'%s')


function check_last_glucose_time_smart_sleep()
{
  file="./entry.json"
  if [ -e $file ]; then
    age=$(date -r $file +'%s')
    seconds_since_last_entry=$(bc <<< "$epochdate - $age")
    echo "Time since last glucose entry in seconds = $seconds_since_last_entry seconds"
    sleep_time=$(bc <<< "240 - $seconds_since_last_entry") 
    echo "Waiting $sleep_time seconds because glucose records only happen every 5 minutes"
    echo "     After this wait, messages will be retrieved closer to the glucose entry time"
  else
    echo "More than 4 minutes since last glucose entry, continue processing without waiting"
  fi
}

check_last_glucose_time_smart_sleep
