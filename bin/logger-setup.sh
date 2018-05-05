#!/bin/bash

function install_sh_bin()
{
  file=$1
  bin="/usr/local/bin"
  rm -f "${bin}/${file}"
  ln -s ${HOME}/src/xdrip-js-logger/bin/${file}.sh ${bin}/${file}
}

mkdir -p ${HOME}/myopenaps/monitor/logger

install_sh_bin "calibrate"
install_sh_bin "g5-noise"
install_sh_bin "g5-stop"
install_sh_bin "g5-start"
install_sh_bin "g5-battery"
install_sh_bin "g5-reset"
install_sh_bin "g5-calc-calibration"
install_sh_bin "g5-calc-noise"
install_sh_bin "g5-post-ns"
install_sh_bin "g5-post-xdrip"

#CALIBRATE="/usr/local/bin/calibrate"
#rm -f $CALIBRATE 
#ln -s ${HOME}/src/xdrip-js-logger/bin/calibrate.sh $CALIBRATE

LOGGER="/usr/local/bin/Logger"
rm -f $LOGGER 
ln -s ${HOME}/src/xdrip-js-logger/xdrip-get-entries.sh $LOGGER


if [ -e "/usr/local/go/bin/go" ]; then
  echo "building calc-noise.go"
  cd ${HOME}/src/xdrip-js-logger
  go build calc-noise.go
  ls -al calc-noise
fi



