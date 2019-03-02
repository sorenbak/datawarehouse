package repository

import (
	"encoding/json"
	"fmt"
	"log"
)

// Repository pattern combined with database singleton

type Repository interface {
	Exec(sql string, args ...interface{}) ([]interface{}, error)
	QueryJson(query string, limit int, args ...interface{}) (string, error)
	Query(query string, limit int, args ...interface{}) ([]interface{}, error)
}

type dbRepository struct {
	db Dber
}

func NewRepository(db Dber) Repository {
	return &dbRepository{db: db}
}

// Exec fires off a stored procedure expecting only OK/err
func (r *dbRepository) Exec(sql string, args ...interface{}) ([]interface{}, error) {
	// Start Tx
	err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	// Do update
	res, err := r.db.Query(sql, 0, args...)
	if err != nil {
		log.Println(err)
		// Rollback on error
		err2 := r.db.Rollback()
		if err2 != nil {
			log.Println(err)
		}
		return res, err
	}
	// Commit
	err = r.db.Commit()
	return res, err
}

// QueryJson fires off query and converts results to json
func (r *dbRepository) QueryJson(query string, limit int, args ...interface{}) (string, error) {
	results, err := r.db.Query(query, limit, args...)
	if err != nil {
		return "", err
	}

	str, err := json.Marshal(results)
	if err != nil {
		fmt.Printf("Error converting results to JSON: [%s]", err)
		return "", err
	}
	return string(str), nil
}

func (r *dbRepository) Query(query string, limit int, args ...interface{}) ([]interface{}, error) {
	return r.db.Query(query, limit, args...)
}
