# xdrip-js-logger

[![Join the chat at https://gitter.im/thebookins/xdrip-js](https://badges.gitter.im/thebookins/xdrip-js.svg)](https://gitter.im/thebookins/xdrip-js?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

*Please note this project is neither created nor backed by Dexcom, Inc. This software is not intended for use in therapy.*
## Prerequisites
Update node version. Please see wiki page for instructions https://github.com/thebookins/xdrip-js/wiki

## Installation
```
cd ~/src
git clone https://github.com/efidoman/xdrip-js-logger.git
cd xdrip-js-logger
sudo npm install
```

## Example usage
`sudo node logger <######>` where `<######>` is the 6-character serial number of the transmitter.

To see verbose output, use `sudo DEBUG=* node logger <######>`, or replace the `*` with a comma separated list of the modules you would like to debug. E.g. `sudo DEBUG=smp,transmitter,bluetooth-manager node logger <######>`.

## One-shot mode additional installation steps
If you want xdrip-js to connect to the transmitter, wait for the first bg, then exit, you will need to follow these additional installation steps. This mode is useful if you have an issue with disconnecting sensors. Doing it one-shot at a time seems to make it more reliable in this case.

```
sudo apt-get install bluez-tools
cd ~/src/xdrip-js
chmod 755 xdrip-get-entries.sh post-ns.sh post-xdripAPS.sh
```

Add cron job entry (replace "40SNU6" with your g5 transmitter id) ...
```
* * * * * cd /root/src/xdrip-js && ps aux | grep -v grep | grep -q 'xdrip-get-entries' || ./xdrip-get-entries.sh 40SNU6 | tee -a /var/log/openaps/xdrip-js-loop.log
```
