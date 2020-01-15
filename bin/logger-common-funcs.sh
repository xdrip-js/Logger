#!/bin/echo This file should be source'd from another script, not run directly:
#
# Common functions for shell script components of Logger.

LDIR="${HOME}/myopenaps/monitor/xdripjs"

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

function txVersion()
{
  local tx_version=""
  if [ -e "${LDIR}/tx-version.json" ]; then
    tx_version=$(cat ${LDIR}/tx-version.json | jq -M '.firmwareVersion')
    tx_version="${tx_version%\"}"
    tx_version="${tx_version#\"}"
  fi

  echo $tx_version
}

