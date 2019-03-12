package webapi

import (
	"fmt"
	"log"
	"time"

	"github.com/gobuffalo/envy"
	"github.com/kataras/golog"
	"github.com/kataras/iris"
	"github.com/kataras/iris/core/router"
)

var upSince = time.Now()

// Default creates the default settings for a webapi application sets various handlers
func Default() (app *iris.Application) {
	app = iris.Default()
	app.Get("/", func(c iris.Context) { c.Text("Uptime: " + fmt.Sprintln(time.Now().Sub(upSince))) })
	app.OnErrorCode(iris.StatusNotFound, errorHandler)
	app.OnErrorCode(iris.StatusInternalServerError, func(c iris.Context) { c.Text(":-(( something wrong happened ))-:") })
	return app
}

func errorHandler(c iris.Context) {
	path := c.Request().URL.Path
	golog.Warnf("404 0ms ::1 " + path)
	c.NotFound()
	c.Text(":-( not found: " + path)
}

// ApiParty defines the main API handlers
func ApiParty(app *iris.Application) (api router.Party) {

	// Register api prefix
	api = app.Party(envy.Get("API_ROOT", "/api"))

	// All endpoints return application/json
	api.Use(func(c iris.Context) { c.ContentType("application/json"); c.Next() })

	if cors_value := envy.Get("USECORS", ""); cors_value != "" {
		log.Printf("Use CORS (%s)\n", cors_value)
		api.Use(AzureCORS)
		api.AllowMethods(iris.MethodOptions)
	}

	if envy.Get("USEAUTH", "") != "" {
		// Register api prefix using authentication
		log.Println("Use Authentication")
		api.Use(AzureAuth)
	}

	return api
}
