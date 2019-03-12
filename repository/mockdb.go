package repository

type MockDb struct {
	count map[string]int
	rows  []interface{}
}

func NewMockDb(data []interface{}) MockDb {
	return MockDb{count: map[string]int{"Query": 0}, rows: data}
}

func (db MockDb) Query(query string, limit int, args ...interface{}) ([]interface{}, error) {
	db.count["Query"]++
	return db.rows, nil
}
func (db MockDb) Commit() error         { return nil }
func (db MockDb) Begin() error          { return nil }
func (db MockDb) Rollback() error       { return nil }
func (db MockDb) Migrate() error        { return nil }
func (db MockDb) Stats() map[string]int { return db.count }
