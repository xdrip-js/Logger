const Transmitter = require('xdrip-js');

const id = process.argv[2];
// FIXME, process.argv[3] should probably just be a file containing an array of messages to send the transmitter instead of a json string.
// examples mesages are: {date: Date.now(), type: "CalibrateSensor", glucose} or {date: Date.now(), type: "StopSensor"} or {date: Date.now(), type: "StartSensor"}
const messages =  JSON.parse(process.argv[3] || '[]');
console.log('messages to send: ' + JSON.stringify(messages));
//messages.push({date: Date.now(), type: "CalibrateSensor", glucose})
//const transmitter = new Transmitter(id); 
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
      'state': glucose.state, // FIXME: make state a readable string
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
