package repository

import (
	"database/sql"
	"fmt"
	"sync"

	_ "github.com/denisenkom/go-mssqldb"
	"github.com/gobuffalo/envy"
)

var once sync.Once
var singleDb *sql.DB

type Dber interface {
	Query(query string, limit int, args ...interface{}) (results []interface{}, err error)
	Begin() error
	Commit() error
	Rollback() error
}

// Singleton db holding connection
type Db struct {
	db *sql.DB
	tx *sql.Tx
}

func NewDb() *Db {
	once.Do(func() {
		fmt.Println("Connecting singleton to database...")
		ctyp := envy.Get("DBCONNECTIONTYPE", "mssql")
		cstr := envy.Get("DBCONNECTIONSTRING", "")
		fmt.Printf("Connecting to DB type [%s]\n", ctyp)
		if cstr == "" {
			fmt.Println("Empty connectionstring - please set DBCONNECTIONSTRING")
			return
		}
		db, err := sql.Open(ctyp, cstr)
		if err != nil {
			fmt.Printf("Cannot connect to host/db [%s]\n", cstr)
			return
		}
		singleDb = db
	})
	return &Db{db: singleDb}
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
		fmt.Printf("Query [%s]([%s]) failed: [%s]\n", query, args, err)
		return nil, err
	}
	defer rows.Close()

	cols, err := rows.Columns()
	if err != nil {
		fmt.Printf("Could not get columns from query [%s]: [%s]\n", query, err)
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
			fmt.Printf("Scan error [%s]\n", err)
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
