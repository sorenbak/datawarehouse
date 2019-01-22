package controllers

import (
	"github.com/kataras/iris"
	"github.com/sorenbak/datawarehouse/repository"
)

func DeliveryList(c iris.Context, rep repository.Repository, agreement_id int64) string {
	// swagger:operation GET /api/delivery/agreement/{agreement_id} Delivery DelliveryList
	// List available deliveries
	// ---
	// produces:
	// - application/json
	// parameters:
	// - name: agreement_id
	//   type: integer
	//   in: path
	//   required: false
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
	//        title: Cutoffs
	//        properties:
	//          agreement_id:
	//            description: ID of agreement
	//            type: integer
	//          agreement_name:
	//            description: Name of agreement
	//            type: string
	//          agreement_group:
	//            description: Name of owning gruop
	//            type: string
	//          agreement_pattern:
	//            description: Prefix pattern for picking up files in delivery in
	//            type: string
	//          delivery_name:
	//            description: Name of delivery
	//            type: string
	//          delivery_id:
	//            description: ID of delivery
	//            type: integer
	//          delivery_owner:
	//            description: Name of delivery owner
	//            type: string
	//          delivery_createdtm:
	//            description: Creation date of delivery
	//            type: string
	//          delivery_size:
	//            description: Size (number of rows) in delivery
	//            type: integer
	//          delivery_status:
	//            description: Date extracted from delivery name (YYYYMMDD) used for tracking validity
	//            type: string
	//          audit_createdtm:
	//            description: Date of latest audit record for delivery
	//            type: string
	//          audit_description:
	//            description: Description of latest audit entry
	//            type: string
	//          status_id:
	//            description: ID of status delivery is in
	//            type: string
	//          user_id:
	//            description: ID of user owning the delivery
	//            type: integer
	page := c.FormValueDefault("page", "0")
	user := GetUsername(c)
	user = "system"
	res, err := rep.QueryJson(`
    SELECT *
      FROM (SELECT ROW_NUMBER() OVER ( ORDER BY audit_createdtm DESC ) AS rownum, *
              FROM meta.agreement_delivery_max_audit_v2 
             WHERE agreement_id = $1
               AND meta.user_access($2, $1, 'VIEW') > 0) r
     WHERE rownum BETWEEN 100 * $3 AND ($3 + 1) * 100`,
		0, agreement_id, user, page)
	if err != nil {
		return err.Error()
	}
	return res
}
