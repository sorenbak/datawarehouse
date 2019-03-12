package webapi

import (
	"github.com/gobuffalo/envy"
	"github.com/iris-contrib/middleware/cors"
	"github.com/kataras/iris"
)

var AzureCORS = cors.New(cors.Options{
	AllowedOrigins:   []string{envy.Get("USECORS", "")},
	AllowedMethods:   []string{iris.MethodGet, iris.MethodPost, iris.MethodPut, iris.MethodPatch, iris.MethodDelete},
	AllowedHeaders:   []string{"*"},
	AllowCredentials: true,
	//Debug:            true,
})
