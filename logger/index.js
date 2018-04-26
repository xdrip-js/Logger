const Transmitter = require('xdrip-js');

const id = process.argv[2];
// FIXME, process.argv[3] should probably just be a file containing an array of messages to send the transmitter instead of a json string.
// examples mesages are: {date: Date.now(), type: "CalibrateSensor", glucose} or {date: Date.now(), type: "StopSensor"} or {date: Date.now(), type: "StartSensor"}
const messages =  JSON.parse(process.argv[3] || '[]');
//console.log('messages to send: ' + JSON.stringify(messages));
//messages.push({date: Date.now(), type: "CalibrateSensor", glucose})
//const transmitter = new Transmitter(id); 
//

function TransmitterStatusString(status) {
 switch (status) {
   case null:
    return '--';
   case 0x00:
     return "OK";
   case 0x81:
     return "Low battery";
   case 0x83:
     return "Bricked";
   default:
     return status ? "Unknown: 0x" + status.toString(16) : '--';
   }
}

function SensorStateString(state) {
  switch (state) {	
     case 0x01:	
       return "Stopped";	
     case 0x02:	
       return "Warmup";	
     case 0x04:	
       return "First calibration";	
     case 0x05:	
       return "Second calibration";	
     case 0x06:	
       return "OK";	
     case 0x07:	
       return "Need calibration";	
     case 0x0a:	
       return "Enter new BG meter value";	
     case 0x0b:	
       return "Failed sensor";	
     case 0x12:	
       return "???";	
     default:	
       return state ? "Unknown: 0x" + state.toString(16) : '--';	
  }
}

const transmitter = new Transmitter(id, () => messages); 
transmitter.on('glucose', glucose => {
  //console.log('got glucose: ' + glucose.glucose);
  lastGlucose = glucose;
  var d= new Date(glucose.readDate);
  var fs = require('fs');
  const entry = [{
      'device': 'DexcomR4',
      'date': glucose.readDate,
      'dateString': new Date(glucose.readDate).toISOString(),
      //'sgv': Math.round(glucose.unfiltered/1000),
      'sgv': glucose.glucose,
      'direction': 'None',
      'type': 'sgv',
      'filtered': Math.round(glucose.filtered),
      'unfiltered': Math.round(glucose.unfiltered),
      'rssi': "100", // TODO: consider reading this on connection and reporting
      'noise': "1",
      'trend': glucose.trend,
      'state': SensorStateString(glucose.state), 
      'status': TransmitterStatusString(glucose.status), 
      'glucose': Math.round(glucose.glucose)
    }];
    const data = JSON.stringify(entry);

  if(glucose.unfiltered > 500000 || glucose.unfiltered < 30000) // for safety, I'm assuming it is erroneous and ignoring
    {
      console.log("Error - bad glucose data, not processing");
      process.exit();
    }
    fs.writeFile("entry.json", data, function(err) {
    if(err) {
        console.log("Error while writing entry-test.json");
        console.log(err);
        }
    process.exit();
    });
});

transmitter.on('disconnect', process.exit);
