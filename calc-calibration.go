package main

import (
	"encoding/csv"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"math"
	"os"
)

// test.csv order is from oldest calibration at the top
// to latest calibration at the bottom
//
// test.csv in the form of
// unfiltered,meterbg,datetime
//Rule 1 - Clear calibration records upon CGM Sensor Change/Insert
//Rule 2 - Don't allow any BG calibrations or take in any new calibrations
//         within 15 minutes of last sensor insert
//Rule 3 - Only use SinglePoint Calibration for 1st 12 hours since Sensor insert
//Rule 4 - Do not store calibration records w/in 12 hours since Sensor insert.
//         Use for SinglePoint calibration, but then discard them
//Rule 5 - Do not use LSR until we have 4 or more calibration points.
//          Use SinglePoint calibration only for < than 4 calibration points.
//          SinglePoint simply uses the latest calibration record and assumes
//          the yIntercept is 0.
//Rule 6 - Drop back to SinglePoint calibration if slope is out of bounds
//          (>MAXSLOPE or <MINSLOPE)
//Rule 7 - Drop back to SinglePoint calibration if yIntercept is out of bounds
//         (> minimum unfiltered value in calibration record set or
//          < - minimum unfiltered value in calibration record set)
//
// yarr = array of last unfiltered values associated w/ bg meter checks
// xarr = array of last bg meter check bg values

func usage() {
	fmt.Fprintf(os.Stderr, "usage: %s [options] inputcsvfile outputjsonfile\n", os.Args[0])
	flag.PrintDefaults()
	os.Exit(1)
}

func MathMin(xs []float64) float64 {
	var min float64 = xs[0]
	for _, v := range xs {
		if v < min {
			min = v
		}
	}
	return min
}

func MathAvg(xs []float64) float64 {
	total := MathSum(xs)
	return total / float64(len(xs))
}

func MathSum(xs []float64) float64 {
	var sum float64 = 0
	for _, v := range xs {
		sum += v
	}
	return sum
}

func MathStdDev(xs []float64) float64 {
	mean := MathAvg(xs)
	var sqdif float64 = 0
	var stddev float64 = 0

	n := 0
	for _, v := range xs {
		sqdif += ((v - mean) * (v - mean))
		n++
	}
	stddev = math.Sqrt(sqdif / (float64(n) - 1))
	return stddev
}

var tarr []float64
var tdate []float64
var yarr []float64
var xarr []float64
var numx int = 0

//var slope float64 = 1000
var yIntercept float64 = 0

//var slopeError float64 = 0
var yError float64 = 0

//var rSquared float64 = 0
var calibrationType string = "SinglePoint"

type CalibrationS struct {
	Slope           float64 `json:"slope"`
	YIntercept      float64 `json:"yIntercept"`
	Formula         string  `json:"formula"`
	YError          float64 `json:"yError"`
	SlopeError      float64 `json:"slopeError"`
	RSquared        float64 `json:"rSquared"`
	NumCalibrations int     `json:"numCalibrations"`
	CalibrationType string  `json:"calibrationType"`
}

var c CalibrationS

func ReportCalibrationAndExit(outputFile string) {
	//	c.YIntercept = yIntercept
	c.Formula = "whatever"
	c.YError = yError
	c.NumCalibrations = numx
	c.CalibrationType = "SinglePoint"

	b, err := json.Marshal(c)
	if err == nil {
		fmt.Println(string(b))
	}

	_ = ioutil.WriteFile(outputFile, b, 0644)
	os.Exit(1)
}

func LeastSquaresRegression() {
	sumX := MathSum(xarr)
	sumY := MathSum(yarr)
	meanX := MathAvg(xarr)
	meanY := MathAvg(yarr)
	stddevX := MathStdDev(xarr)
	stddevY := MathStdDev(yarr)
	var sumXY float64 = 0
	var sumXSq float64 = 0
	var sumYSq float64 = 0
	var r float64 = 0
	var n int = numx
	var denominator float64 = 1

	var firstDate float64 = tdate[0]

	for i, v := range tdate {
		tarr[i] = v - firstDate
	}

	for i, _ := range tarr {
		var multiplier float64 = 1
		if i > 0 {
			multiplier = 1 + tarr[i-1]/(tarr[n-1]*2)
		}
		// bounds check
		if multiplier < 1 || multiplier > 2 {
			multiplier = 1
		}
		sumXY += xarr[i] * yarr[i] * multiplier
		sumXSq += xarr[i] * xarr[i] * multiplier
		sumYSq += yarr[i] * yarr[i] * multiplier
	}
	denominator = math.Sqrt((float64(n)*sumXSq - sumX*sumX) * (float64(n)*sumYSq - sumY*sumY))
	if denominator == 0 || stddevX == 0 {
		c.Slope = 1000
		c.YIntercept = 0
	} else {
		calibrationType = "LeastSquaresRegression"
		r = (float64(n)*sumXY - sumX*sumY) / denominator
		c.RSquared = r * r
		c.Slope = r * stddevY / stddevX
		c.YIntercept = meanY - c.Slope*meanX

		// calculate error
		var varSum float64 = 0
		for j, _ := range tarr {
			var tf float64 = yarr[j] - c.YIntercept - c.Slope*xarr[j]
			varSum += tf * tf
		}
		var delta float64 = float64(n)*sumXSq - sumX*sumX
		var vari float64 = 1.0 / (float64(n) - 2.0) * varSum

		yError = math.Sqrt(vari / delta * sumXSq)
		c.SlopeError = math.Sqrt(float64(n) / delta * vari)
	}

}

func main() {

	flag.Parse()

	flag.Usage = usage
	if flag.NArg() < 2 {
		usage()
	}

	inputFile, err := os.Open(flag.Arg(0))
	if err != nil {
		fmt.Println("Cannot open input file", flag.Arg(0))
		fmt.Println("Error:", err)
		ReportCalibrationAndExit(flag.Arg(1))
	}
	defer inputFile.Close()

	ReportCalibrationAndExit(flag.Arg(1))

	reader := csv.NewReader(inputFile)

	lineCount := 0

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		} else if err != nil {
			fmt.Println("Error:", err)
			usage()
		}

		var epochdate float64
		var bg float64
		var unfiltered float64
		if _, err := fmt.Sscan(record[3], &epochdate); err != nil {
			fmt.Printf("%T, %v\n", epochdate, epochdate)
		}
		if _, err := fmt.Sscan(record[1], &bg); err != nil {
			fmt.Printf("%T, %v\n", bg, bg)
		}
		if _, err := fmt.Sscan(record[0], unfiltered); err != nil {
			fmt.Printf("%T, %v\n", unfiltered, unfiltered)
		}
		tdate = append(xdate, epochdate)
		yarr = append(yarr, bg)
                xarr = append(xarr, unfiltered)
		lineCount += 1
	}

	//var firstDate float64 = 0

	//firstDate = 0

	// sod = sum of distances
	var sod float64 = 0
	var lastDelta float64 = 0
	var n int = lineCount

	var y2y1Delta float64 = 0
	var x2x1Delta float64 = 0
	for i := 1; i < n; i++ {
		// time-based multiplier
		// y2y1Delta adds a multiplier that gives
		// higher priority to the latest BG's
		y2y1Delta = (yarr[i] - yarr[i-1]) * (1.0 - (float64(n)-float64(i))/(float64(n)*3.0))
		x2x1Delta = xarr[i] - xarr[i-1]
		if lastDelta > 0 && y2y1Delta < 0 {
			// for this single point, bg switched from positive delta to negative,
			//increase noise impact
			// this will not effect noise to much for a normal peak,
			//but will increase the overall noise value
			// in the case that the trend goes up/down multiple times
			// such as the bounciness of a dying sensor's signal
			y2y1Delta = y2y1Delta * 1.1

		} else if lastDelta < 0 && y2y1Delta > 0 {

			// switched from negative delta to positive, increase noise impact
			// in this case count the noise a bit more because it could indicate
			// a big "false" swing upwards which could
			// be troublesome if it is a false swing upwards and a loop
			// algorithm takes it into account as "clean"
			y2y1Delta = y2y1Delta * 1.2
		}
		lastDelta = y2y1Delta
		//		fmt.Fprintf(os.Stderr, "yDelta=%f, xdelta=%f\n", y2y1Delta, x2x1Delta)
		sod = sod + math.Sqrt(x2x1Delta*x2x1Delta+y2y1Delta*y2y1Delta)

	}
	y2y1Delta = yarr[n-1] - yarr[0]
	x2x1Delta = xarr[n-1] - xarr[0]
	if sod == 0 {
		//noise = 0
	} else {
		//noise = 1 - (overallDistance / sod)
	}

	//	fmt.Fprintf(os.Stderr, "sod=%f, overallDistance=%f, noise=%f\n", sod, overallDistance, noise)
	ReportCalibrationAndExit(flag.Arg(1))

}

func SinglePointCalibration() {
	c.Slope = 1000
	c.YIntercept = 0
	if numx > 0 {
		var x float64 = xarr[numx-1]
		var y float64 = yarr[numx-1]
		c.Slope = y / x
		calibrationType = "SinglePoint"
	}
}
