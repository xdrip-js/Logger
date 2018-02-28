package main

import (
	"bytes"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"time"
)

//
// exit codes
// -1 ==> INPUT file doesn't exist
//  0 ==> success
// -2 ==> err on http request

var curlStatus int = -1

func usage() {
	fmt.Fprintf(os.Stderr, "usage: %s inputjsonfile type\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "          inputjsonfile = Nightscout json record file\n")
	fmt.Fprintf(os.Stderr, "          type = Nightscout record type, default is \"entries\"\n")
	flag.PrintDefaults()
	os.Exit(curlStatus)
}

func main() {

	flag.Parse()
	flag.Usage = usage

	var nsUrl string = os.Getenv("NIGHTSCOUT_HOST")
	var nsSecret string = os.Getenv("API_SECRET")

	//fmt.Fprintf(os.Stderr, "nsUrl=%s, nsSecret=%s\n", nsUrl, nsSecret)

	if flag.NArg() < 2 {
		usage()
	}
	//fmt.Fprintf(os.Stderr, "arg0=%s\n", flag.Arg(0))
	//fmt.Fprintf(os.Stderr, "arg1=%s\n", flag.Arg(1))

	jsonFile := flag.Arg(0)
	nsType := flag.Arg(1)

	b, err := ioutil.ReadFile(jsonFile) // just pass the file name
	if err != nil {
		log.Fatal(err)
	}

	url := fmt.Sprintf("%s/api/v1/%s/.json", nsUrl, nsType)

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(b))
	if err != nil {
		log.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("API-SECRET", nsSecret)

	//	timeout := time.Duration(5 * time.Second)
	timeout := time.Duration(5 * time.Second)
	client := &http.Client{
		Timeout: timeout,
	}

	before := float64(time.Now().UnixNano()) / 1000000000.0
	resp, err := client.Do(req)
	if err != nil {
		curlStatus = -2
		log.Fatal(err)
	}
	after := float64(time.Now().UnixNano()) / 1000000000.0
	elapsed := after - before
	defer resp.Body.Close()
	fmt.Printf("before=%f, after=%f, elapsed=%f\n", before, after, elapsed)

	//fmt.Println("response Status:", resp.Status)
	//	fmt.Println("response Headers:", resp.Header)
	body, _ := ioutil.ReadAll(resp.Body)
	fmt.Println(string(body))
	os.Exit(curlStatus)
}
