package main

import (
	"github.com/kataras/iris"
	"github.com/sorenbak/datawarehouse/repository"
)

func UserList(c iris.Context, rep repository.Repository) {
	// swagger:operation GET /api/user/list User UserList
	// List available users
	// ---
	// produces:
	// - application/json
	// parameters:
	// - name: page
	//   description: Page of results (starting with 0 - default)
	//   type: integer
	//   in: query
	//   required: false
	// responses:
	//   '200':
	//     description: OK
	//     schema:
	//      type: array
	//      items:
	//        type: object
	//        title: UserList
	//        properties:
	//          id:
	//            description: ID of user
	//            type: integer
	//          username:
	//            description: Username of user
	//            type: string
	//          realname:
	//            description: Real name of user
	//            type: string
	//          description:
	//            description: Description of user
	//            type: string
	//          createdtm:
	//            description: Date of creation
	//            type: string
	//          delivery_count:
	//            description: Count of deliveries
	//            type: integer
	page := c.FormValueDefault("page", "0")
	res, err := rep.Query(`
    SELECT *
      FROM ( SELECT ROW_NUMBER() OVER (ORDER BY username) AS rownum, * FROM meta.user_v) u
     WHERE rownum BETWEEN 100 * $1 AND ($1 + 1) * 100`, 0, page)
	if err != nil {
		c.StatusCode(500)
		return
	}
	c.JSON(res)
}
