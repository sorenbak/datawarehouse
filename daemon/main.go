package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/gobuffalo/envy"
	"github.com/sorenbak/datawarehouse/repository"
)

var DB repository.Repository
var SLEEPSECS int
var INBOX, OUTBOX string

// Make daemon testable
func GetConfig() {
	DB = repository.NewRepository(repository.NewDb())
	SLEEPSECS, _ = strconv.Atoi(envy.Get("SLEEPSECS", "60"))
	INBOX = envy.Get("INBOX", "./in")
	OUTBOX = envy.Get("OUTBOX", "./in")
}

func main() {
	GetConfig()
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
	src := INBOX + path + "/" + file.Name()
	dst := OUTBOX + path + "/" + file.Name()
	err := os.Rename(src, dst)
	if err != nil {
		log.Fatalf("Could not rename [%s]->[%s]: %v\n", src, dst, err)
	}
}

func ProcessAgreement(file os.FileInfo) {
	SetLog(file)
	log.Printf("Load agreement file [%s]\n", file.Name())
	sql, err := ioutil.ReadFile(INBOX + "/" + file.Name())
	if err != nil {
		log.Println("Error reading agreement contents: ", err)
	}
	_, err = DB.Exec(string(sql))
	if err != nil {
		log.Println("Error executing agreement SQL: ", err)
	}
	MoveToOUTBOX(file, "")
}

func ProcessCsv(file os.FileInfo) {
	SetLog(file)
	log.Printf("Lookup agreement for [%s]\n", file.Name())
	stage := 1
	var agreement_id int
	var procedure string
	_, err := DB.Query("EXEC meta.agreement_find $1, $2, $3, $4", 0, file.Name(), stage, &agreement_id, &procedure)
	if err != nil {
		log.Printf("Error finding agreement [%s]: %v", file.Name(), err)
		return
	}
	fmt.Println(agreement_id, procedure)

	return
}
