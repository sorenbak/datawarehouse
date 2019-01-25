package main

// Generate swagger.json file in one place
//go:generate $GOPATH/bin/swagger generate spec -o swagger/swagger.json --scan-models

import (
	"fmt"

	"github.com/sorenbak/datawarehouse/app"
	"github.com/sorenbak/datawarehouse/repository"

	"github.com/gobuffalo/envy"
	"github.com/kataras/iris"
)

func main() {
	// Only load once
	envy.Load()
	db := repository.NewDb()
	// Spawn off the the web service
	app := app.DwApp(db)
	if envy.Get("USESSL", "") != "" {
		fmt.Println("Use SSL")
		app.Run(iris.AutoTLS(envy.Get("HTTPSADDR", ""), envy.Get("HTTPSFQN", ""), envy.Get("HTTPSEMAIL", "")))
	} else {
		app.Run(iris.Addr(envy.Get("HTTPADDR", ":8080")), iris.WithoutPathCorrection)
	}
	//Daemon()
}
