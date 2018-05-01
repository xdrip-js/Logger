#!/bin/bash

mode="ot-expired"

if [[ "$mode" == "not-expired" || $"$mode" == "dual" ]]; then
  echo "mode = $mode, answer = yes"
else
  echo "mode = $mode, answer = no"
fi

