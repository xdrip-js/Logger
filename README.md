# Logger 

[![Join the chat at https://gitter.im/thebookins/xdrip-js](https://badges.gitter.im/thebookins/xdrip-js.svg)](https://gitter.im/thebookins/xdrip-js?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

*Please note this project is neither created nor backed by Dexcom, Inc.*
*Logger is not a product. Logger comes with no warranty or official support. Anyone using Logger is doing so at their own risk and must take responsibility for their own safety. The use of Logger for therapy is not FDA approved and comes with inherent risks.*

Logger is a Bash (shell) based Dexcom g5 / g6 glucose pre-processor for OpenAPS. Logger runs on the OpenAPS rig and connects to the g5 or g6 transmitter via bluetooth, waits for the first bg, logs a json entry record, processes the entry record based on calibrations, updates NightScout and OpenAPS indepently, then exits. Logger is a wrapper shell script to xdrip-js that is called from cron every minute. The user interface is a mixture between unix command line scripts and NightScout. The current Logger features are below:

* Preparation and sending of the blood glucose data to Nightscout and to OpenAPS.
* Alternate Bluetooth connection - allows Logger to run alongside one other CGM app (besides the receiver). With this setting set to true, Logger can run alongside Xdrip+ or the Dexcom App.
* Offline mode - Logger runs on the rig and sends bg data directly to openaps through via xdripAPS. Logger queues up NS updates while internet is down and fills in the gaps when internet is restored.
* Reset Transmitter - Use the following command, wait > 10 minutes, and your expired transmitter is new again! Careful, though it will reset everything on your transmitter including your current session. Note this feature is only available via the command line.  ```cgm-reset```

* Stop Sensor - Use the following command, wait > 5 minutes, and your current sensor session will stop. Use  this command before changing out your sensor so that Logger will stop sending glucose information temporarily (while the sensor is stopped) This feature is also available via the command line only.  ```cgm-stop```

* Start Sensor - Use the following command, wait > 5 minutes, and your sensor session will start. Use  this command after inserting your sensor so that Logger will start the process for sending glucose information. This feature is also available via the command line and you can also do it via Nightscout as a BG Treatment, entry type of Sensor Start.  ```cgm-start```

* Set Transmitter - Use the following command, wait > 5 minutes, and your new transmitter id will be used.  This feature is only available if using the xdripjs.json configuration file & not calling Logger with the transmitter id as an argument.  ```cgm-transmitter```

* Calibration via linear least squares regression (LSR) (similar to xdrip plus)
  * Calibrations must be input into Nightscout as BG Check treatments or command line ```calibrate bg_value```.
  * Logger will not calculate or send any BG data out unless at least one  calibration has been done in Nightscout. Calibration is not required for a g6 when using no-calibration by sending it a valid sensor serial code in the cgm-start message.
  * LSR calibration only comes into play after 3 or more calibrations. When there one or two calibrations, single point linear calibration is used.
  * The calibration cache will be cleared for the first 15 minutes after a Nightscout "CGM Sensor Insert" has been posted as Nightscout treatment.
  * After 15 minutes, BG data will only be sent out after at least one calibration has been documented in Nightscout.

* fakemeter - Additional offline ability where Logger sends the blood glucose to the pump. To enable, simply go into the pump and add a meter with id 000000 through the Utilities -> Meter Options menu 

# Warning! 

Logger LSR calibration is a new feature as of Feb/2018. Only those who closely monitor and check blood glucose and regularly review the Logger logfiles should use this program at this time.
* `/var/log/openaps/logger-loop.log`
* `/var/log/openaps/cgm.csv`
* `/root/myopenaps/monitor/xdripjs/calibrations.csv` - the current list of calibrations (unfiltered, BG check, datetime, BG Check ID)
* `/root/myopenaps/monitor/xdripjs/calibration-linear.json` - the current calibration values (slope, yIntercept). Please note that other fields in this file are for informational purposes at this time. 

[![Join the chat at https://gitter.im/thebookins/xdrip-js](https://badges.gitter.im/thebookins/xdrip-js.svg)](https://gitter.im/thebookins/xdrip-js?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

*Please note this project is neither created nor backed by Dexcom, Inc.*
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

	{"transmitter_id":"8XXXXX"}, Required - 6 character tx serial number (i.e. 403BX6).  Should be set using cgm-transmitter cmd.
	{"sensor_code":"1234"}, Optional - Sensor code used for G6 only. Start a transmitter using this to use the G6 no-calibration mode. If set to a non-empty string, calibrations are not sent to the transmitter. To set a new sensor code you must set it using the cgm-start cmd or NS.
	{"mode":"native-calibrates-lsr"}, Optional - if you specify "read-only" then Logger still sends BG values to OpenAPS, but all start/stop/calibrations must be done by the receiver, the Dexcom App, or XdripPlus. The default is "native-calibrates-lsr" then it will use the Dexcom algorithms, unless not available, and it will also calibrate the local LSR algorithm based on the values of the Dexcom algorithm, every 6 hours. "native-calibrates-lsr" is useful to allow expired sessions and extended sensors to automatically use recent calibration data. 

	{"pump_units":"mg/dl"}, Optional - pumpUnits default is "mg/dl"
	{"fake_meter_id":"000000"}, Optional - meterid for fakemeter sending glucose records to pump, default is "000000"
	{"alternate_bluetooth_channel":true or false} Optional - Default is false. If set to true then Logger uses the alternate channel to connect to the Dexcom transmitter. If set to true the receiver cannot be used. However, when set to true, either the Xdip Plus android app or the Dexcom Iphone app can be used alongside Logger. Keep in mind that there is a higher chance for bluetooth conflict when connecting to the transmitter with both channels. You may be able to avoid some reconnects by keeping the rig and the phone app physically separated by several inches.
	{"watchdog":true or false}, Optional - Default is true. If set to true then Logger will automatically reboot the rig to resolve bluetooth issues if no glucose is seen from the transmitter in more than 14 minutes.
	{"utc":true or false}, Optional - Default is true. If set to true then Logger will assume UTC date/time strings coming from the curls to NightScout. 
	{"fakemeter_only_offline":true or false}, Optional - Default is false. If set to false then Logger will not attempt to call fakemeter unless the rig is offline. 

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

If both unfiltered and filtered values are showing up as 0 in the Logger logfile, then you may be able to solve the problem by doing a ```cgm-reset```. Note: This will reset the session and you will lose any transmitter stored calibrations so this technique is probably best used when unfiltered is 0 upon new sensor insertion. 

If timing out, recheck the configuration of the transmitter id, make sure the bt-device command is available, ensure there are no conflicting bluetooth connections on the same channel (i.e. Dexcom App, Receiver, or XDrip+).


Since the timer only allows communications for a few seconds every 5 minutes, isolation of any timeout issues are key.  The following are some suggestions:
1) Turn off Logger and receiver, run Xdrip+ and see if it can connect to the tx. If Xdrip+ can connect, then it may be a rig issue. If Xdrip+ cannot connect, then it's mostly isolated to a tx issue. 
2) Run the following command. If it fails for any reason, then the install of bluez-tools may have an issue. If bluez-tools is not installed, then bt timeouts will likely be the result. ```bt-device -l```
3) Check your network log. BT PAN may be trying to do something and restarting bluetoothd. Check /var/log/openaps/network.log and any bluetooth log (if it exists) in that directory. Also, check for bluetooth errors in /var/log/syslog as well.
4) Turn off every other possible dexcom connection and try connecting with the tx with the official Dexcom app. This will only work if you have a non-expired tx or have successfully reset it earlier.
5) Try a different transmitter (if you have one). If this works, then the other tx has an issue, usually battery related.
6) Try a different rig (if you have one). If this works, then the other rig or it's install/configuration is likely the culprit.
7) If on an RPI, check the mode in /etc/bluetooth/main.conf. At least one user found that setting mode to Controller mode resolved the timeouts. 

If you have network connectivity on the rig, but BG values are not showing up on NightScout, then run the following command which should retrieve the last BG Check Treatment posted to NightScout. Review any errors that the command returns and re-check your NIGHTSCOUT_HOST and API_SECRET environment variables.
``` 
curl --compressed -m 30 -H "API-SECRET: ${API_SECRET}" "${NIGHTSCOUT_HOST}/api/v1/treatments.json?find\[eventType\]\[\$regex\]=Check&count=1"
```

To check recent reported BG noise levels, run the command line utility ```cgm-noise```
