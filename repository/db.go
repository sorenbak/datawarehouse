package repository

import (
	"database/sql"
	"errors"
	"flag"
	"log"
	"regexp"
	"strings"
	"sync"

	_ "github.com/denisenkom/go-mssqldb"
	"github.com/gobuffalo/envy"
	"github.com/gobuffalo/packr"
	"github.com/rubenv/sql-migrate"
)

var once sync.Once
var singleDb *sql.DB

type Dber interface {
	Query(query string, limit int, args ...interface{}) (results []interface{}, err error)
	Begin() error
	Commit() error
	Rollback() error
}

// Db is a singleton holding connection
type Db struct {
	db    *sql.DB
	tx    *sql.Tx
	retry int64
}

// migrate is an experimental command line flag migrating UP if --migrate is set
func _migrate(db *sql.DB) (err error) {
	table := envy.Get("DB_MIGRATIONS_TABLE", "")
	if table == "" {
		return errors.New("No migrations table specified -  please set DB_MIGRATIONS_TABLE")
	}

	migrations := &migrate.PackrMigrationSource{Box: packr.NewBox("../migrations")}
	migrate.SetTable(table)
	n, err := migrate.Exec(db, envy.Get("DBTYPE", "mssql"), migrations, migrate.Up)

	if err != nil {
		// Check for login failed
		if !(strings.Contains(err.Error(), "Login failed for user") || strings.Contains(err.Error(), "Using the user default database")) {
			return errors.New("Could not migrate.Up: " + err.Error())
		}
		log.Println(err.Error())
		// Option to create database if not exist
		if envy.Get("DB_CREATE_DATABASE", "yes") != "yes" {
			return err
		}
		// Create database by switching to master database and retry
		_create_database()
		return _migrate(db)
	}

	log.Printf("Applied [%d] migrations\n", n)
	return nil
}

// NewDb Provides a new (or reuse) singleton
func NewDb() *Db {
	once.Do(func() {
		log.Println("Connecting singleton to database...")
		ctyp := envy.Get("DBCONNECTIONTYPE", "mssql")
		cstr := envy.Get("DBCONNECTIONSTRING", "")
		log.Printf("Connecting to DB type [%s]\n", ctyp)
		if cstr == "" {
			log.Panic("Empty connectionstring - please set DBCONNECTIONSTRING")
			return
		}
		db, err := sql.Open(ctyp, cstr)
		if err != nil {
			log.Panicf("Cannot connect to host/db [%s]\n", cstr)
		}

		// Top level do once check for the migrate flag
		migrate_flag := flag.Bool("migrate", false, "Flag specifying if migrations should be applied")
		flag.Parse()
		if *migrate_flag {
			err := _migrate(db)
			if err != nil {
				log.Panic(err)
			}
		}
		singleDb = db
	})
	return &Db{db: singleDb, retry: 0}
}

func (db *Db) Commit() (err error) {
	return db.tx.Commit()
}

func (db *Db) Begin() (err error) {
	db.tx, err = db.db.Begin()
	return err
}

func (db *Db) Rollback() (err error) {
	return db.tx.Rollback()
}

// Generic Query function returning result set based on any command
func (db *Db) Query(query string, limit int, args ...interface{}) (results []interface{}, err error) {
	rows, err := db.db.Query(query, args...)
	if err != nil {
		// Known issue with connections being reset (due to idle?)
		if strings.HasSuffix(err.Error(), "connection reset by peer") && db.retry < 2 {
			db.retry += 1
			return db.Query(query, limit, args...)
		}
		db.retry = 0
		log.Printf("Query [%s]([%s]) failed: [%s]\n", query, args, err)
		return nil, err
	}
	defer rows.Close()

	db.retry = 0
	cols, err := rows.Columns()
	if err != nil {
		log.Printf("Could not get columns from query [%s]: [%s]\n", query, err)
		return nil, err
	}

	rowcount := 0
	for rows.Next() {
		// auto-deferring string->interface{} is disabled by design in Go, so need to copy values
		r := make(map[string]interface{})      // Hash of key/values (to be populated)
		t := make([]sql.NullString, len(cols)) // Target array of string
		p := make([]interface{}, len(cols))    // Scan array (list of pointers to string)
		for i := 0; i < len(cols); i++ {
			p[i] = &t[i]
		}
		err = rows.Scan(p...)
		if err != nil {
			log.Printf("Scan error [%s]\n", err)
			break
		}
		for i := 0; i < len(cols); i++ {
			r[cols[i]] = t[i].String
		}
		results = append(results, r)

		if limit > 0 {
			// Return here if limit is reached
			if rowcount++; rowcount >= limit {
				return results, nil
			}
		}
	}
	return results, err
}

// _create_database helper allow creating database if non-existing prior to migrating
// It is absolutely last resort so panic in case of any errors
func _create_database() {
	log.Printf("Database does not exist (Login failed) - trying to create...")
	re := regexp.MustCompile(`(?i)database=([^;]*);`)
	cstr := re.ReplaceAllString(envy.Get("DBCONNECTIONSTRING", ""), "database=master;")
	name := re.FindStringSubmatch(envy.Get("DBCONNECTIONSTRING", ""))[1]

	log.Printf("Create database [%s]\n", name)
	db, err := sql.Open(envy.Get("DBCONNECTIONTYPE", "mssql"), cstr)
	if err != nil {
		log.Fatal("Create database prior to migrating failed: ", err)
	}
	defer db.Close()

	_, err = db.Exec("CREATE DATABASE [" + name + "]")
	if err != nil {
		log.Fatal("Create database prior to migrating failed: ", err)
	}
}
