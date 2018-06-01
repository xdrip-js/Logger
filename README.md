# xdrip-js-logger - the xdrip-js One-Shot Mode Logger.

Logger connects to the g5 transmitter, waits for the first bg, logs a json entry record, then exits. Doing it one-shot at a time seems to make xdrip-js more reliable in some cases. Logger is a wrapper shell script that is called from cron every minute. Current Logger features:

* Preparation and sending of the blood glucose data to Nightscout and to OpenAPS.
* Offline mode - Logger runs on the rig and sends bg data directly to openaps through via xdripAPS. Logger queues up NS updates while internet is down and fills in the gaps when internet is restored.
* Reset Transmitter - Use the following command, wait > 10 minutes, and your expired transmitter is new again! Careful, though it will reset everything on your transmitter including your current session. Note this feature is only available via the command line.
```
g5-reset
```
* Stop Sensor - Use the following command, wait > 5 minutes, and your current sensor session will stop. Use  this command before changing out your sensor so that Logger will stop sending glucose information temporarily (while the sensor is stopped) This feature is also available via the command line only.
```
g5-stop
```
* Start Sensor - Use the following command, wait > 5 minutes, and your sensor session will start. Use  this command after inserting your sensor so that Logger will start the process for sending glucose information. This feature is also available via the command line and you can also do it via Nightscout as a BG Treatment, entry type of Sensor Start.
```
g5-start
```
* Calibration via linear least squares regression (LSR) (similar to xdrip plus)
  * Calibrations must be input into Nightscout as BG Check treatments.
  * Logger will not calculate or send any BG data out unless at least one  calibration has been done in Nightscout.
  * LSR calibration only comes into play after 3 or more calibrations. When there one or two calibrations, single point linear calibration is used.
  * The calibration cache will be cleared for the first 15 minutes after a Nightscout "CGM Sensor Insert" treatment has been posted.
  * After 15 minutes, BG data will only be sent out after at least one calibration has been documented in Nightscout.

# Warning! 

Logger LSR calibration is a new feature as of Feb/2018. Only those who closely monitor and check blood glucose and regularly review the Logger logfiles should use this program at this time.
* /var/log/openaps/xdrip-js-loop.log
* /var/log/openaps/g5.csv
* /root/src/xdrip-js-logger/calibrations.csv - the current list of calibrations (unfiltered, BG check, datetime, BG Check ID)
* /root/src/xdrip-js-logger/calibration-linear.json - the current calibration values (slope, yIntercept). Please note that other fields in this file are for informational purposes at this time. Unfiltered values from the g5 are on a 1,000 scale which explains why slope and yIntercept are 1,000 greater than glucose values.

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

For the edison, the version of Node that ships with jubilinux is old (v0.10.something). Here are the instructions for updating Node:
```
sudo apt-get remove nodered -y
sudo apt-get remove nodejs nodejs-legacy -y
sudo apt-get remove npm  -y # if you installed npm
sudo curl -sL https://deb.nodesource.com/setup_6.x | sudo bash -
sudo apt-get install nodejs -y
```

## Installation
```
cd ~/src
git clone https://github.com/efidoman/xdrip-js-logger.git
cd xdrip-js-logger
sudo npm run global-install
sudo apt-get install bluez-tools
```

Add cron job entry (replace "40SNU6" with your g5 transmitter id in both places below) ...
```
* * * * * cd /root/src/xdrip-js-logger && ps aux | grep -v grep | grep -q '40SNU6' || /usr/local/bin/Logger 40SNU6 >> /var/log/openaps/logger-loop.log 2>&1
```

## Getting Started
First, make sure you've checked the Prerequisites above and completed the Installation steps. Afterwords, perform the following steps:

Review the Logger logfile to ensure the proccess is proceeding without errors. Run the following command on the rig and keep it running for debugging purposes for the first time you go through the procedures below:

	```tail -f /var/log/openaps/logger-loop.log```

Insert the new Dexcom g5 sensor. Notify Logger of this insertion by using one of the two methods below:

	Nightscout Treatment CGM Sensor Insert 
	 or
	Run ```g5-insert``` from the command line

Start the new Dexcom g5 sensor by using one of the two methods below:

	Nightscout Treatment CGM Sensor Start 
	  or
	Run ```g5-start``` from the command line

	Within 15 minutes, the sensor state should show "Warmup" in Nightscout and in the Logger log. At this point, you have 2 options:
	
	Prefered: Wait to calibrate until the 2 hour warmup period is complete and the sensor state in NS shows "First Calibration".
		  Calibrate again once the sensor state in NS shows "Second Calibration"

	Not Prefered / Advanced mode: Calibrate after > 15 minutes since CGM start.

Calibrate by using one of the two methods below:

	Nightscout Treatment BG Check and put calibrated glucose in the Glucose Reading field
	  or
	Run ```g5-calibrate <bg>``` from the command line

After calibration(s), you should see BG values in Nightscout and in the log.
