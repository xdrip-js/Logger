#!/bin/bash

# This script sets up the openaps rig by installing components required to run
# Logger which retrieves information from a Dexcom Transmitter via BLE, processes
# the information, and forwards it to Nightscout and openaps
# Released under MIT license. See the accompanying LICENSE.txt file for
# full terms and conditions
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

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
link_install ${root_dir}/bin/calibrate.sh cgm-calibrate
link_install ${root_dir}/bin/calibrate.sh g5-calibrate
link_install ${root_dir}/bin/g5-noise.sh g5-noise
link_install ${root_dir}/bin/g5-noise.sh cgm-noise
link_install ${root_dir}/bin/g5-stop.sh g5-stop
link_install ${root_dir}/bin/g5-stop.sh cgm-stop
link_install ${root_dir}/bin/g5-start.sh g5-start
link_install ${root_dir}/bin/g5-start.sh cgm-start
link_install ${root_dir}/bin/g5-battery.sh g5-battery
link_install ${root_dir}/bin/g5-battery.sh cgm-battery
link_install ${root_dir}/bin/g5-insert.sh  g5-insert
link_install ${root_dir}/bin/g5-insert.sh  cgm-insert
link_install ${root_dir}/bin/g5-reset.sh  g5-reset
link_install ${root_dir}/bin/g5-reset.sh  cgm-reset
link_install ${root_dir}/bin/g5-restart.sh  cgm-restart
link_install ${root_dir}/bin/g5-restart.sh  g5-restart
link_install ${root_dir}/bin/g5-calc-calibration.sh g5-calc-calibration
link_install ${root_dir}/bin/g5-calc-calibration.sh cgm-calc-calibration
link_install ${root_dir}/bin/g5-calc-noise.sh g5-calc-noise
link_install ${root_dir}/bin/g5-calc-noise.sh cgm-calc-noise
link_install ${root_dir}/bin/g5-post-ns.sh g5-post-ns
link_install ${root_dir}/bin/g5-post-ns.sh cgm-post-ns
link_install ${root_dir}/bin/g5-post-xdrip.sh g5-post-xdrip 
link_install ${root_dir}/bin/g5-post-xdrip.sh cgm-post-xdrip
link_install ${root_dir}/bin/g5-transmitter.sh g5-transmitter
link_install ${root_dir}/bin/g5-transmitter.sh cgm-transmitter
link_install ${root_dir}/bin/g5-debug.sh cgm-debug
link_install ${root_dir}/bin/g5-debug.sh logger-debug

link_install ${root_dir}/xdrip-get-entries.sh Logger

