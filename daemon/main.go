package main

import (
	"log"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/gobuffalo/envy"
	"github.com/sorenbak/datawarehouse/file"
	"github.com/sorenbak/datawarehouse/repository"
)

var db repository.Repository
var sleepsecs int
var filer file.DwFiler

// Make daemon testable
func GetConfig() {
	db = repository.NewRepository(repository.NewDb())
	envy.Load()
	sleepsecs, _ = strconv.Atoi(envy.Get("SLEEPSECS", "60"))
	blob := envy.Get("BLOB", "")
	var err error
	log.Println("Applying BLOB token to database")
	if blob != "" {
		_, err = db.Exec("EXEC meta.azure_credentials $1, 'DwAzureCredential', 'DwAzureStorage'", blob)
	} else {
		_, err = db.Exec("EXEC meta.azure_credentials $1, NULL, NULL", blob)
	}
	if err != nil {
		log.Fatal("meta.azure_credentials failed: ", err)
	}

	filer = file.New(envy.Get("INBOX", "./in/"), envy.Get("OUTBOX", "./out/"), blob)
}

func main() {
	GetConfig()
	for true {
		// Loop over files
		files := filer.ReadInbox()
		for _, file := range files {
			log.Printf("Processing file [%s]\n", file.Name)
			ext := filepath.Ext(file.Name)
			// Switch on file extension
			switch ext {
			case ".csv":
				ProcessCsv(file)
			case ".sql":
				ProcessAgreement(file)
			default:
				log.Printf(" |_ ignored [%s]\n", ext)
			}
			log.SetOutput(os.Stdout)
		}

		// Sleep a reasonable amount of time
		log.Printf("Wait [%d] secs\n", sleepsecs)
		time.Sleep(time.Duration(sleepsecs) * time.Second)
	}
}

func ProcessAgreement(file file.DwFile) {
	filer.SetLog(file)
	defer filer.SaveLog()
	defer filer.MoveFile(file)
	log.Printf("Load agreement file [%s]\n", file.Name)
	sql, err := filer.ReadFile(file)
	if err != nil {
		log.Println("Error reading agreement contents: ", err)
		return
	}
	_, err = db.Exec(string(sql))
	if err != nil {
		log.Println("Error executing agreement SQL: ", err)
		return
	}
	return
}

func ProcessCsv(file file.DwFile) {
	filer.SetLog(file)
	defer filer.SaveLog()
	defer filer.MoveFile(file)
	agreement_id := agreementFind(file)
	if agreement_id == "" {
		return
	}
	log.Printf("Loading CSV file [%s] using agreement_id [%s]\n", file.Name, agreement_id)
	res := deliveryLoad(file)
	if res != 0 {
		return
	}
	res = deliveryValidate(file)
	if res != 0 {
		return
	}
	res = deliveryPublish(file)
	if res != 0 {
		return
	}
	res = deliveryTrigger(file)
	if res != 0 {
		return
	}
}

func deliveryLoad(file file.DwFile) int {
	filer.PreLoad(file)
	defer filer.PostLoad(file)
	// No such thing as owner cross platform - neither in Azure where everything is owned by the Everyone user
	res, err := db.Exec("EXEC meta.delivery_load $1, $2, $3, $4", file.Path, file.Name, "system", file.Size)
	if err != nil {
		log.Println("deliveryLoad: ", err)
		return 1
	}
	if len(res) > 0 {
		log.Println("deliveryLoad returned: ", res[0])
		return 0
	}
	return 0
}

func deliveryValidate(file file.DwFile) int {
	res, err := db.Exec("meta.delivery_validate $1", file.Name)
	if err != nil {
		log.Println("deliveryValidate: ", err)
		return 1
	}
	if len(res) > 0 {
		log.Println("deliveryValdiate returned: ", res[0])
		return 0
	}
	return 0
}

func deliveryPublish(file file.DwFile) int {
	res, err := db.Exec("meta.delivery_publish $1", file.Name)
	if err != nil {
		log.Println("deliveryPublish: ", err)
		return 1
	}
	if len(res) > 0 {
		log.Println("deliveryPublish returned: ", res[0])
		return 0
	}
	return 0
}

func deliveryTrigger(file file.DwFile) int {
	res, err := db.Exec("meta.delivery_trigger $1", file.Name)
	if err != nil {
		log.Println("deliveryTrigger: ", err)
		return 1
	}
	if len(res) > 0 {
		log.Println("deliveryTrigger returned: ", res[0])
		return 0
	}
	return 0
}

func agreementFind(file file.DwFile) (agreement_id string) {
	log.Printf("Lookup agreement for [%s]\n", file.Name)
	stage_id := 1
	res, err := db.Exec(`
    DECLARE @agreement_id INT
    DECLARE @procedure    NVARCHAR(100) 
    EXEC meta.agreement_find $1, $2, @agreement_id OUT, @procedure OUT
    SELECT @agreement_id AS agreement_id`, file.Name, stage_id)
	if err != nil {
		log.Println(err)
		return ""
	}
	if len(res) == 0 {
		log.Printf("Agreement not found for file [%s]\n", file.Name)
		return ""
	}
	data := res[0].(map[string]interface{})
	return data["agreement_id"].(string)
}
