#!/bin/bash

timestamp="2019-07-10T19:25:36-04:00"
timestamp=$(date)#"2019-07-10T19:25:36-04:00"

timestamp=$(date +'%Y-%m-%dT%H:%M:%S.%3N')


epochdate=`date --date="$timestamp" +"%s"`

timestamp2=$(date -u -d @$epochdate +'%Y-%m-%dT%H:%M:%S.%3NZ')
echo timestamp=$timestamp
echo epochdate=$epochdate
echo timestamp2=$timestamp2






