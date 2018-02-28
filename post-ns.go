package logger

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"time"
)

func PostNightscoutRecord(jsonFile string, nsType string, nsUrl string, nsSecret string) (err error, body string) {

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
	respB, _ := ioutil.ReadAll(resp.Body)
	//	fmt.Println(string(body))
	return err, string(respB)
}
