# xdrip-js-logger - Bash (shell) based Dexcom g5 / g6 glucose pre-processor for OpenAPS

Logger connects to the g5 or g6 transmitter, waits for the first bg, logs a json entry record, then exits. Doing it one-shot at a time seems to make xdrip-js more reliable in some cases. Logger is a wrapper shell script that is called from cron every minute. The user interface is a mixture between unix command line scripts and NightScout. The current Logger features are below:

* Preparation and sending of the blood glucose data to Nightscout and to OpenAPS.
* Offline mode - Logger runs on the rig and sends bg data directly to openaps through via xdripAPS. Logger queues up NS updates while internet is down and fills in the gaps when internet is restored.
* Reset Transmitter - Use the following command, wait > 10 minutes, and your expired transmitter is new again! Careful, though it will reset everything on your transmitter including your current session. Note this feature is only available via the command line.  ```cgm-reset```

Note: Resetting the G6 transmitter will prohibit using no-calibration mode (even if you enter the code) so be extra careful when considering doing a reset on a g6 transmitter.

* Stop Sensor - Use the following command, wait > 5 minutes, and your current sensor session will stop. Use  this command before changing out your sensor so that Logger will stop sending glucose information temporarily (while the sensor is stopped) This feature is also available via the command line only.  ```cgm-stop```

* Start Sensor - Use the following command, wait > 5 minutes, and your sensor session will start. Use  this command after inserting your sensor so that Logger will start the process for sending glucose information. This feature is also available via the command line and you can also do it via Nightscout as a BG Treatment, entry type of Sensor Start.  ```cgm-start```

* Set Transmitter - Use the following command, wait > 5 minutes, and your new transmitter id will be used.  This feature is only available if using the xdripjs.json configuration file & not calling Logger with the transmitter id as an argument.  ```cgm-transmitter```

* Calibration via linear least squares regression (LSR) (similar to xdrip plus)
  * Calibrations must be input into Nightscout as BG Check treatments or command line ```calibrate bg_value```.
  * Logger will not calculate or send any BG data out unless at least one  calibration has been done in Nightscout.
  * LSR calibration only comes into play after 3 or more calibrations. When there one or two calibrations, single point linear calibration is used.
  * The calibration cache will be cleared for the first 15 minutes after a Nightscout "CGM Sensor Insert" has been posted as Nightscout treatment.
  * After 15 minutes, BG data will only be sent out after at least one calibration has been documented in Nightscout.

* fakemeter - Additional offline ability where Logger sends the blood glucose to the pump. To enable, simply go into the pump and add a meter with id 000000 through the Utilities -> Meter Options menu 

# Warning! 

Logger LSR calibration is a new feature as of Feb/2018. Only those who closely monitor and check blood glucose and regularly review the Logger logfiles should use this program at this time.
* /var/log/openaps/logger-loop.log
* /var/log/openaps/cgm.csv
* /root/myopenaps/monitor/logger/calibrations.csv - the current list of calibrations (unfiltered, BG check, datetime, BG Check ID)
* /root/myopenaps/monitor/logger/calibration-linear.json - the current calibration values (slope, yIntercept). Please note that other fields in this file are for informational purposes at this time. 

[![Join the chat at https://gitter.im/thebookins/xdrip-js](https://badges.gitter.im/thebookins/xdrip-js.svg)](https://gitter.im/thebookins/xdrip-js?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

*Please note this project is neither created nor backed by Dexcom, Inc. This software is not intended for use in therapy.*
## Prerequisites
* Openaps must be installed using the CGM method of xdrip.
* Logger does not currently support token-based authentication with Nightscout

Update node version. Follow these steps in this order.

Set Nightscout environment variables in ~/.bash_profile. Make sure the following 4 lines are in this file. If not carefully add them paying close attention the values (xxxx is your hashed Nightscout API_SECRET and yyyy is your Nightscout URL):
```
API_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxx
export API_SECRET
NIGHTSCOUT_HOST=https://yyyyyyy.herokuapp.com
export NIGHTSCOUT_HOST
```

For the edison/explorer board (jubilinux), the version of Node that ships with jubilinux is old (v0.10.something). Here are the instructions for updating the edison/explorer rig's Node:
```
sudo apt-get remove nodered -y
sudo apt-get remove nodejs nodejs-legacy -y
sudo apt-get remove npm  -y # if you installed npm
sudo curl -sL https://deb.nodesource.com/setup_8.x | sudo bash -
sudo apt-get install nodejs -y

cd ~/src/Logger && npm rebuild # if Logger exists already and you are upgrading node from 6.x to 8.x
```

If you are using the RPI zero hat, the version of Node that ships with jubilinux also needs updating. Here are the instructions for updating the rpi zero hat's Node:
```
mkdir node && cd node
wget https://nodejs.org/dist/v8.10.0/node-v8.10.0-linux-armv6l.tar.xz
tar -xf node-v8.10.0-linux-armv6l.tar.xz
cd *6l
sudo cp -R * /usr/local/
# add /usr/local/bin to PATH env variable in .bash_profile
node -v
# should show 8.10.0 at this point
```

## Installation 
```
cd ~/src
git clone https://github.com/xdrip-js/Logger.git
cd Logger
sudo npm run global-install
sudo apt-get install bluez-tools
```

Set your transmitter (replace 403BX6 with your actual 6 digit transmitter serial number)...
```
cgm-transmitter 403BX6
```

Add cron job entry ...
```
* * * * * cd /root/src/Logger && ps aux | grep -v grep | grep -q Logger || /usr/local/bin/Logger >> /var/log/openaps/logger-loop.log 2>&1
```

## Logger Configuration Options:

You can edit the following options values in the configuration file (~/myopenaps/xdripjs.json)

	"transmitter_id" = 6 character tx serial number (i.e. 403BX6).  Should be set using cgm-trasmitter cmd.
	"sensor_code" = Optional - Sensor code used for G6 only.  Note that this value is read-only in the configuration file & setting it here will not affect Logger/xdrip-js.  To set a new sensor code you must set it using the cgm-start cmd or NS.
	"mode" = Optional - if you specify "expired" then mode is hard-coded to expired tx mode and it uses local LSR calibration always.  Default is "not-expired".
	"pump_units" = Optional - pumpUnits default is "mg/dl"
	"fake_meter_id" = Optional - meterid for fakemeter sending glucose records to pump, default is "000000"

## Getting Started
First, make sure you've checked the Prerequisites above and completed the Installation steps. Afterwords, perform the following steps:

Review the Logger logfile to ensure the proccess is proceeding without errors. Run the following command on the rig and keep it running for debugging purposes for the first time you go through the procedures below:

```
tail -f /var/log/openaps/logger-loop.log
```

Insert the new Dexcom g5 or g6 sensor. Notify Logger of this insertion by using Nightscout Treatment CGM Sensor Insert

Start the new Dexcom g5 sensor by using one of the two methods (Nightscout Treatment CGM Sensor Start) or (run ```cgm-start``` from the command line)

If starting a g6, specify the sensor serial code by putting the 4 digit code in the Nightscout Sensor Start Note or passing the the command line as follows: ```cgm-start -c 1234``` where 1234 is the sensor serial code.

Within 15 minutes, the sensor state should show "Warmup" in Nightscout and in the Logger log. At this point, you have 2 options:
	
Prefered: Wait to calibrate until the 2 hour warmup period is complete and the sensor state in NS shows "First Calibration".
		  Calibrate again once the sensor state in NS shows "Second Calibration"

Not Prefered / Advanced mode: Calibrate after > 15 minutes since CGM start.

Calibrate by using one of the two methods (Nightscout Treatment BG Check and put calibrated glucose in the Glucose Reading field) or (run ```calibrate bgvalue``` from the command line)

After calibration(s), you should see BG values in Nightscout and in the log.

## Troubleshooting 

If both unfiltered and filtered values are showing up as 0 in the Logger logfile, then you may be able to solve the problem by doing a ```cgm-reset```. Note: This will reset the session and you will lose any transmitter stored calibrations so this technique is probably best used when unfiltered is 0 upon new sensor insertion. Once again, it is not recommended to do a ```cgm-reset``` on a g6 transmitter because you will lose the ability to do no-calibration mode.

