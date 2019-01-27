package main

import (
	"log"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/gobuffalo/envy"
)

var SLEEPSECS, _ = strconv.Atoi(envy.Get("SLEEPSECS", "60"))
var INBOX = envy.Get("INBOX", "./in")
var OUTBOX = envy.Get("OUTBOX", "./out")

func main() {

	for true {
		// Loop over files
		files := ReadINBOX()
		for _, file := range files {
			log.SetOutput(os.Stdout)
			log.Printf("Processing file [%s]\n", file.Name())
			ext := filepath.Ext(file.Name())
			switch ext {
			case ".csv":
				ProcessCsv(file)
			case ".sql":
				ProcessAgreement(file)
			default:
				log.Printf(" |_ ignored [%s] ", ext)
			}

			// 1. if text      inbox -> call handle_csv_file
			// 2. if agreement inbox -> call handle_agreement_file
			// Check file is released (net file fileid /CLOSE)
			// Check exit code from 1. and 2. above
			//   if OK - write success and move file to out/ok
			//   if ERR - write error and move file to out/err
			// Close log file
		}

		// Sleep a reasonable amount of time
		log.SetOutput(os.Stdout)
		log.Printf("Wait [%d] secs\n", SLEEPSECS)
		time.Sleep(time.Duration(SLEEPSECS) * time.Second)
	}
}

func SetLog(file os.FileInfo) {
	// Redirect output to log file in outbox
	logfilename := OUTBOX + "/" + file.Name() + ".log"
	logfile, err := os.Create(logfilename)
	if err != nil {
		log.Fatalf("Could not write logfile [%s]: %v\n", logfilename, err)
	}
	log.SetOutput(logfile)
}

func ReadINBOX() []os.FileInfo {
	if _, err := os.Stat(INBOX); os.IsNotExist(err) {
		err := os.MkdirAll(INBOX, os.ModePerm)
		if err != nil {
			log.Fatalf("Could not create inbox [%s]: %v\n", INBOX, err)
		}
	}
	// Get files from container (file storage or file system?)
	inbox, err := os.Open(INBOX)
	if err != nil {
		log.Fatalf("Could not open inbox [%s]: %v\n", INBOX, err)
	}
	files, err := inbox.Readdir(-1)
	inbox.Close()
	if err != nil {
		log.Printf("Could not read inbox [%s]: %v\n", INBOX, err)
	}

	return files
}

func MoveToOUTBOX(file os.FileInfo, path string) {
	if _, err := os.Stat(OUTBOX); os.IsNotExist(err) {
		err := os.MkdirAll(OUTBOX, os.ModePerm)
		if err != nil {
			log.Fatalf("Could not create outbox [%s]: %v\n", OUTBOX, err)
		}
	}
	dest := OUTBOX + path + "/" + file.Name()
	err := os.Rename(file.Name(), dest)
	if err != nil {
		log.Fatalf("Could not rename [%s]->[%s]: %v\n", file.Name(), dest, err)
	}
}

func ProcessCsv(file os.FileInfo) error {
	SetLog(file)
	log.Println("This file is a CSV")
	return nil
}

func ProcessAgreement(file os.FileInfo) error {
	SetLog(file)
	log.Println("")
	return nil
}
