// DataWarehouse
//
// Package implements datawarehouse frontend
// The purpose of this application is to provide data via REST endpoints to frontend clients.
//   version: 1.0.0
//   title: datawarehouse frontend
//   basePath: /
//   schemes: http, https
//   securityDefinitions:
//     Bearer:
//       type: apiKey
//       in: header
//       name: Authorization
//   security:
//   - Bearer: []
//   consumes: application/json
//   produces: application/json
// swagger:meta
package main

// Generate swagger.json file in one place
//!!!go:generate go get -u github.com/kataras/bindata/cmd/bindata
//!!!go:generate cp -r ../webapi/swagger .
//go:generate $GOPATH/bin/swagger generate spec -o ../webapi/swagger/swagger.json --scan-models
//!!!go:generate bindata -o data.go data/...
//!!!go:generate rm -rf data

import (
	"github.com/sorenbak/datawarehouse/file"
	"github.com/sorenbak/datawarehouse/frontend/controllers"
	"github.com/sorenbak/datawarehouse/repository"
	"github.com/sorenbak/datawarehouse/webapi"

	"github.com/gobuffalo/envy"
	"github.com/gobuffalo/packr"
	"github.com/kataras/iris"
	"github.com/kataras/iris/hero"
)

func DwApi(db repository.Dber) (app *iris.Application) {
	app = webapi.Default()
	api := webapi.ApiParty(app)

	dat := packr.NewBox("../webapi/swagger")
	app.StaticEmbedded("/swagger", "", dat.Find, dat.List)
	dat = packr.NewBox("./wwwroot")
	app.StaticEmbedded("/", "", dat.Find, dat.List)

	// DI common classes
	hero.Register(repository.New(db))
	hero.Register(file.New(envy.Get("INBOX", "./in/"), envy.Get("OUTBOX", "./out/"), envy.Get("BLOB", "")))

	// Agreement
	api.Get("/agreement/attribute/{agreement_id:int64}", hero.Handler(controllers.AgreementAttribute))
	api.Get("/agreement/deliverycount/{agreement_id:int64}", hero.Handler(controllers.AgreementDeliveryCount))
	api.Get("/agreement/{date: string}", hero.Handler(controllers.AgreementList))
	api.Get("/agreement/column/{agreement_id:int64}", hero.Handler(controllers.AgreementColumn))
	api.Get("/agreement/rule/{agreement_id:int64}", hero.Handler(controllers.AgreementRule))
	api.Get("/agreement/trigger/{agreement_id:int64}", hero.Handler(controllers.AgreementTrigger))
	// Delivery
	api.Get("/delivery/agreement/{agreement_id:int64}", hero.Handler(controllers.DeliveryList))
	api.Get("/delivery/detail/{delivery_id:int64}", hero.Handler(controllers.DeliveryDetail))
	api.Get("/delivery/operation/{delivery_id:int64}", hero.Handler(controllers.DeliveryOperation))
	api.Get("/delivery/download/json/{agreement_name:string}/{delivery_id:int64}}", hero.Handler(controllers.DeliveryDownloadJson))
	api.Get("/delivery/log/{delivery_id:int64}}", hero.Handler(controllers.DeliveryLog))
	api.Delete("/delivery/delete/{delivery_id:int64}}", hero.Handler(controllers.DeliveryDelete))
	// User
	api.Get("/user/list", hero.Handler(controllers.UserList))

	return app
}

func main() {
	// Only load once
	envy.Load()

	// Spawn off the the web service
	app := DwApi(repository.NewDb())
	app.Run(iris.Addr(envy.Get("HTTPADDR", ":8080")), iris.WithoutPathCorrection)
}
