package controllers

import (
	"github.com/kataras/iris"
	"github.com/sorenbak/datawarehouse/repository"
)

// Details for an agreement
// swagger:model
type DeliveryDto struct {
	// ID of agreement
	agreement_id int64
	// Name of agreement
	agreement_name string
	// Name of owning gruop
	agreement_group string
	// Description of agreement
	agreement_description string
	// Prefix pattern for picking up files in delivery in
	agreement_pattern string
	// Name of delivery
	delivery_name string
	// ID of delivery
	delivery_id int64
	// Name of delivery owner
	delivery_owner string
	// Creation date of delivery
	delivery_createdtm string
	// Size (number of rows) in delivery
	delivery_size int64
	// Date extracted from delivery name (YYYYMMDD) used for tracking validity
	delivery_status_date string
	// Name of stage delivery is in
	stage_name string
	// Date of latest audit record for delivery
	audit_createdtm string
	// Description of latest audit entry
	audit_description string
	// ID of status delivery is in
	status_id string
	// ID of user owning the delivery
	user_id int64
}

var DeliveryDtoQ = struct2query(DeliveryDto{})

func DeliveryList(c iris.Context, rep repository.Repository, agreement_id int64) string {
	// swagger:operation GET /api/delivery/agreement/{agreement_id} Delivery DeliveryList
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
	//       type: array
	//       items:
	//          $ref: "#/definitions/DeliveryDto"
	page := c.FormValueDefault("page", "0")
	user := GetUsername(c)
	user = "system"
	res, err := rep.QueryJson(`
    SELECT *
      FROM (SELECT ROW_NUMBER() OVER ( ORDER BY audit_createdtm DESC ) AS rownum, `+DeliveryDtoQ+`
              FROM meta.agreement_delivery_max_audit_v
             WHERE agreement_id = $1
               AND meta.user_access($2, $1, 'VIEW') > 0) r
     WHERE rownum BETWEEN 100 * $3 AND ($3 + 1) * 100`,
		0, agreement_id, user, page)
	if err != nil {
		return err.Error()
	}
	return res
}

func DeliveryDetail(c iris.Context, rep repository.Repository, delivery_id int64) string {
	// swagger:operation GET /api/delivery/detail/{delivery_id} Delivery DeliveryDetail
	// Retrieve details for a single delivery
	// ---
	// produces:
	// - application/json
	// parameters:
	// - name: delivery_id
	//   type: integer
	//   in: path
	//   required: false
	// responses:
	//   '200':
	//     description: OK
	//     schema:
	//       type: array
	//       items:
	//          $ref: "#/definitions/DeliveryDto"
	user := GetUsername(c)
	user = "system"
	res, err := rep.QueryJson(`
    SELECT `+DeliveryDtoQ+` 
      FROM meta.agreement_delivery_max_audit_v
     WHERE delivery_id = $1
       AND meta.user_access($2, agreement_id, 'VIEW') > 0`,
		0, delivery_id, user)
	if err != nil {
		return err.Error()
	}
	return res
}

func DeliveryOperation(c iris.Context, rep repository.Repository, delivery_id int64) string {
	// swagger:operation GET /api/delivery/operation/{delivery_id} Delivery DeliveryOperation
	// Download contents of delivery
	// ---
	// produces:
	// - application/json
	// parameters:
	// - name: delivery_id
	//   type: integer
	//   in: path
	//   required: false
	// responses:
	//   '200':
	//     description: OK
	//     schema:
	//      type: array
	//      items:
	//        type: object
	//        title: DeliveryOperation
	//        properties:
	//          agreement_id:
	//            description: ID of agreement
	//            type: integer
	//          delivery_id:
	//            description: ID of delivery
	//            type: integer
	//          audit_id:
	//            description: ID of audit
	//            type: integer
	//          audit_createdtm:
	//            description: Date of creation of audit etry
	//            type: string
	//          audit_description:
	//            description: Description of audit entry
	//            type: string
	//          stage_id:
	//            description: ID of stage entry
	//            type: integer
	//          stage_name:
	//            description: Name of stage entry
	//            type: string
	//          table_id:
	//            description: ID of table entry of delivery in current stage
	//            type: integer
	//          table_schema:
	//            description: Name of table schema in current stage
	//            type: string
	//          table_name:
	//            description: Name of table in current stage
	//            type: string
	//          table_createdtm:
	//            description: Date of creation of table in current stage
	//            type: string
	//          operation_id:
	//            description: ID of operation entry
	//            type: integer
	//          operation_createdtm:
	//            description: Date of creation of operation entry
	//            type: string
	//          operation_name:
	//            description: Name of operation entry
	//            type: string
	//          operation_descrription:
	//            description: Description of operation entry
	//            type: string
	//          status_id:
	//            description: ID of status entry of delivery in current stage
	//            type: string
	//          status_description:
	//            description: Description of status entry of delivery in current stage
	//            type: string
	res, err := rep.QueryJson(`
    SELECT * 
      FROM meta.delivery_id_audit_operation_v
     WHERE delivery_id = $1
       AND meta.user_access($2, agreement_id, 'VIEW')>0
     ORDER BY operation_createdtm DESC`, 0, delivery_id, "system")
	if err != nil {
		return err.Error()
	}
	return res
}

func DeliveryDownloadJson(c iris.Context, rep repository.Repository, agreement_name string, delivery_id int64) string {
	// swagger:operation GET /api/delivery/download/json/{agreement_name}/{delivery_id} Delivery DeliveryDownloadJson
	// Download contents of delivery
	// ---
	// produces:
	// - application/json
	// parameters:
	// - name: agreement_name
	//   type: string
	//   in: path
	//   required: false
	// - name: delivery_id
	//   type: integer
	//   in: path
	//   required: false
	// responses:
	//   '200':
	//     description: OK
	//     schema:
	//      type: array
	//      items:
	//        type: object
	//        title: DeliveryJson
	//        properties:
	//          dw_delivery_id:
	//            description: ID of delivery
	//            type: integer
	//          dw_row_id:
	//            description: ID of row in delivery
	//            type: integer
	//          original:
	//            description: Remaining columns in the original dataset
	//            type: string
	res, err := rep.QueryJson(`EXEC meta.get_data $1, $2, 0, NULL, $3`, 0, "system", agreement_name, delivery_id)
	if err != nil {
		return err.Error()
	}
	return res
}

func DeliveryDelete(c iris.Context, rep repository.Repository, delivery_id int64) string {
	// swagger:operation DELETE /api/delivery/delete/{delivery_id} Delivery DeliveryDelete
	// Delete delivert
	// ---
	// produces:
	// - application/json
	// parameters:
	// - name: delivery_id
	//   type: integer
	//   in: path
	//   required: false
	// responses:
	//   '200':
	//     description: OK
	res, err := rep.QueryJson(`EXEC meta.delivery_delete $1`, 0, delivery_id)
	if err != nil {
		return err.Error()
	}
	return res
}
