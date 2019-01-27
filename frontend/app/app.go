// Package implements datawarehouse frontend
// The purpose of this application is to provide data via REST endpoints to frontend clients.
//   version: 1.0.0
//   title: datawarehouse frontend
//   host: localhost:8080
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
package app

import (
	"fmt"

	jwt "github.com/dgrijalva/jwt-go"
	"github.com/gobuffalo/envy"
	jwtmiddleware "github.com/iris-contrib/middleware/jwt"
	"github.com/kataras/iris"
	"github.com/kataras/iris/context"
	"github.com/kataras/iris/core/router"
	"github.com/kataras/iris/hero"
	"github.com/sorenbak/datawarehouse/frontend/auth"
	"github.com/sorenbak/datawarehouse/frontend/controllers"
	"github.com/sorenbak/datawarehouse/repository"
)

func DwApp(db repository.Dber) *iris.Application {
	app := iris.Default()

	// Swagger is served in /swagger/index.htm (due to limitation in StaticWeb)
	app.StaticWeb("/swagger", "./swagger")
	app.StaticWeb("/", "./wwwroot")

	// Create repository
	// Register generic db and repository (pseudo IoC via hero)
	// NOTE: hero has trouble inferring signatures with varying arguments properly - seems like a ramped down IoC
	hero.Register(repository.NewRepository(db))

	// Determine endpoint
	api := EndpointParty(app)

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
	api.Delete("/delivery/delete/{delivery_id:int64}}", hero.Handler(controllers.DeliveryDelete))

	return app
}

func EndpointParty(app *iris.Application) (api router.Party) {
	handlers := []context.Handler{}

	if envy.Get("USEAUTH", "") != "" {
		// Register api prefix using authentication
		fmt.Println("Use Authentication")
		// Create JWT handler
		// (see https://github.com/iris-contrib/middleware/blob/master/jwt/_example/main.go)
		handlers = append(handlers,
			jwtmiddleware.New(jwtmiddleware.Config{

				// Func for retrieving and caching keys (involves 2 roundtrips)
				ValidationKeyGetter: auth.GetValidationKeyFromAzure,

				// Func for veryfying using signing method
				SigningMethod: jwt.SigningMethodRS256,
			}).Serve)
	}

	// Register api prefix
	return app.Party("/api", handlers...)
}
