package main

import (
	"reflect"
	"strings"

	jwt "github.com/dgrijalva/jwt-go"
	"github.com/kataras/iris"
)

func GetUsername(c iris.Context) string {
	token := c.Values().Get("jwt")
	if token == nil {
		return ""
	}
	return token.(*jwt.Token).Claims.(jwt.MapClaims)["unique_name"].(string)
}

// Returns a flattened list of element names of a struct (no nesting)
// Useful for turning a DTO into a list of query columns in SQL
func struct2query(s interface{}) string {
	r := reflect.TypeOf(s)
	var q []string
	for i := 0; i < r.NumField(); i++ {
		q = append(q, r.Field(i).Name)
	}
	return strings.Join(q, ",")
}
