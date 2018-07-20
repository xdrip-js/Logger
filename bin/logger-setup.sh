#!/bin/bash

function link_install()
{
  src=$1
  exe=$2
  bin="/usr/local/bin"
  rm -f "${bin}/${exe}"
  ln -s ${src} ${bin}/${exe}
  echo "ln -s ${src} ${bin}/${exe}"
}

function build_go_exe()
{
  EXE=$1
  echo "building ${EXE}"
  cd ${HOME}/src/Logger/cmd/${EXE}
  /usr/local/go/bin/go build
  if [ -e ${EXE} ]; then
    echo "${EXE} build successful"
  else
    echo "${EXE} build not successful"
  fi
}


mkdir -p ${HOME}/myopenaps/monitor/xdripjs

root_dir=${HOME}/src/Logger
link_install ${root_dir}/bin/calibrate.sh calibrate
link_install ${root_dir}/bin/calibrate.sh g5-calibrate
link_install ${root_dir}/bin/g5-noise.sh g5-noise
link_install ${root_dir}/bin/g5-stop.sh g5-stop
link_install ${root_dir}/bin/g5-start.sh g5-start
link_install ${root_dir}/bin/g5-battery.sh g5-battery
link_install ${root_dir}/bin/g5-insert.sh  g5-insert
link_install ${root_dir}/bin/g5-reset.sh  g5-reset
link_install ${root_dir}/bin/g5-calc-calibration.sh g5-calc-calibration
link_install ${root_dir}/bin/g5-calc-noise.sh g5-calc-noise
link_install ${root_dir}/bin/g5-post-ns.sh g5-post-ns
link_install ${root_dir}/bin/g5-post-xdrip.sh g5-post-xdrip 

link_install ${root_dir}/xdrip-get-entries.sh Logger

if [ -e "/usr/local/go/bin/go" ]; then
  file="g5-calc-noise-go"
  build_go_exe ${file}
  link_install ${root_dir}/cmd/${file}/${file} ${file}

  # go-based version of calc-calibration is still a work in progress
#  build_go_exe "g5-calc-calibration-go"
fi



