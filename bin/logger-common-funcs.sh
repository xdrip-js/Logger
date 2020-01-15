#!/bin/echo This file should be source'd from another script, not run directly:
#
# Common functions for shell script components of Logger.

function newFirmware()
{
  local version=$1
  case $version in
    1.6.5.27 | 2.*)
      echo true
      ;;
    *)
      echo false
      ;;
  esac
}


