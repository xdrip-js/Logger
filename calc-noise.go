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

func usage() {
	fmt.Fprintf(os.Stderr, "usage: %s [options] inputcsvfile outputjsonfile\n", os.Args[0])
	flag.PrintDefaults()
	os.Exit(1)
}

type NoiseS struct {
	Noise float64 `json:"noise"`
}

func ReportNoiseAndExit(noise float64, outputFile string) {
	var output []NoiseS
	output = append(output, NoiseS{Noise: noise})
	b, err := json.Marshal(output)
	if err == nil {
		fmt.Println(string(b))
	}

	_ = ioutil.WriteFile(outputFile, b, 0644)
	os.Exit(1)
}

func main() {
	var xdate []float64
	var yarr []float64
	var xarr []float64
	var noise float64 = 0

	flag.Parse()

	flag.Usage = usage
	if flag.NArg() < 2 {
		usage()
	}

	inputFile, err := os.Open(flag.Arg(0))
	if err != nil {
		fmt.Println("Cannot open input file", flag.Arg(0))
		fmt.Println("Error:", err)
		ReportNoiseAndExit(0, flag.Arg(1))
	}
	defer inputFile.Close()

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
		if _, err := fmt.Sscan(record[0], &epochdate); err != nil {
			fmt.Printf("%T, %v\n", epochdate, epochdate)
		}
		if _, err := fmt.Sscan(record[1], &bg); err != nil {
			fmt.Printf("%T, %v\n", bg, bg)
		}
		xdate = append(xdate, epochdate)
		yarr = append(yarr, bg)
		lineCount += 1
	}

	var firstDate float64 = 0

	firstDate = xdate[0]

	for i := 0; i < lineCount; i++ {
		// use 30 multiplier to norm x axis
		xarr = append(xarr, ((xdate[i] - firstDate) * 30))
		//		fmt.Fprintf(os.Stderr, "xdate[%d]=%f, yarr[%d]=%f, xarr[%d]=%f\n", i, xdate[i], i, yarr[i], i, xarr[i])

	}

	// sod = sum of distances
	var sod float64 = 0
	var overallDistance float64 = 0
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
	overallDistance = math.Sqrt(x2x1Delta*x2x1Delta + y2y1Delta*y2y1Delta)
	if sod == 0 {
		noise = 0
	} else {
		noise = 1 - (overallDistance / sod)
	}

	//	fmt.Fprintf(os.Stderr, "sod=%f, overallDistance=%f, noise=%f\n", sod, overallDistance, noise)
	ReportNoiseAndExit(noise, flag.Arg(1))

}
