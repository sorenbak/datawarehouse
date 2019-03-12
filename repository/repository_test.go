// +build unit

package repository

import (
	"testing"
)

func TestRepository(t *testing.T) {

	data := []interface{}{
		map[string]string{"id": "bla", "name": "blu"},
		map[string]string{"id": "rov", "name": "bab"},
	}

	moq := NewMockDb(data)
	rep := NewRepository(moq)

	r, _ := rep.Query("1", 1, nil)
	t1 := r[0].(map[string]string)
	if t1["id"] != "bla" {
		t.Error("Expected hash id = bla")
	}
	if t1["name"] != "blu" {
		t.Error("Expected hash name = blu")
	}
	t2 := r[1].(map[string]string)
	if t2["id"] != "rov" {
		t.Error("Expected hash id = rov")
	}
	if t2["name"] != "bab" {
		t.Error("Expected hash name = bab")
	}
	if got := moq.Stats()["Query"]; got != 1 {
		t.Errorf("Got [%d], expected [%d] calls to Query", got, 1)
	}
}
