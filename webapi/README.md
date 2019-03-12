# webapi

Common stuff for ramping up a web REST API using various go modules.
Below is a list of used modules


```bash
go get github.com/go-swagger/go-swagger/cmd/swagger
go get github.com/kataras/iris
go get github.com/kataras/iris/hero
go get github.com/gobuffalo/envy
go get github.com/iris-contrib/httpexpect
go get github.com/iris-contrib/middleware/cors
go get github.com/dgrijalva/jwt-go
```

# Synopsis

```go
import (
    "modules/webapi"
	"github.com/kataras/iris"
)

app := webapi.Default()
api := webapi.ApiParty(app)
api.Get("/cutoffvalues", func(c iris.Context) { c.Text("Hello World") }
app.Run(iris.Addr(":8080"))
```

The module will setup Azure Authentication and CORS with default
values according to Maersk standards for running in Azure and on
vessels in some form.
