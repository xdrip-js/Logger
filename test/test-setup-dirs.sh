#!/bin/bash

function check_dirs()
{
  LDIR=~/myopenaps/monitor/xdripjs5
  OLD_LDIR=~/myopenaps/monitor/logger5

  if [ ! -d ${LDIR} ]; then
    if [ -d ${OLD_LDIR} ]; then
      mv ${OLD_LDIR} ${LDIR} 
    fi
  fi
  mkdir -p ${LDIR}
  mkdir -p ${LDIR}/old-calibrations
}

check_dirs
