package controllers

import (
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
