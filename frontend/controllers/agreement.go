package controllers

import (
	"github.com/kataras/iris"
	"github.com/sorenbak/datawarehouse/frontend/repository"
)

func AgreementAttribute(c iris.Context, rep repository.Repository, agreement_id int64) string {
	// swagger:operation GET /api/agreement/attribute/{agreement_id} Agreement AgreementAttribute
	// List available agreement details
	// ---
	// produces:
	// - application/json
	// parameters:
	// - name: agreement_id
	//   type: integer
	//   in: path
	//   required: true
	// responses:
	//   '200':
	//     description: OK
	//     schema:
	//      type: array
	//      items:
	//        type: object
	//        title: AgreementAttribute
	//        properties:
	//          agreement_id:
	//            description: ID of agreement
	//            type: integer
	//          agreement_name:
	//            description: Name of agreement
	//            type: string
	//          attribute_id:
	//            description: ID of attribute
	//            type: integer
	//          attribute_name:
	//            description: Name of attribute
	//            type: string
	//          attribute_options:
	//            description: Valid options for attribute values (| separated values)
	//            type: string
	//          attribute_description:
	//            description: Human readable description of attribute
	//            type: string
	//          value:
	//            description: Actual value of attribute
	//            type: string
	//          createdtm:
	//            description: Creation Date/Time
	//            type: timestamp
	res, err := rep.QueryJson(`SELECT * FROM meta.agreement_attribute_v WHERE agreement_id = $1`, 0, agreement_id)
	if err != nil {
		return err.Error()
	}
	return res
}

func AgreementDeliveryCount(c iris.Context, rep repository.Repository, agreement_id int64) string {
	// swagger:operation GET /api/agreement/deliverycount/{agreement_id} Agreement AgreementDeliveryCount
	// List delivery acount and other meta data per agreement
	// ---
	// produces:
	// - application/json
	// parameters:
	// - name: id
	//   type: integer
	//   in: path
	//   required: true
	// responses:
	//   '200':
	//     description: OK
	//     schema:
	//      type: array
	//      items:
	//        type: object
	//        title: AgreementDeliveryCount
	//        properties:
	//          id:
	//            description: ID of agreement
	//            type: integer
	//          name:
	//            description: Name of agreement
	//            type: string
	//          description:
	//            description: Description of agreement
	//            type: string
	//          pattern:
	//            description: Prefix pattern for picking up files in delivery in
	//            type: string
	//          createdtm:
	//            description: Date and time of agreement creation
	//            type: timestamp
	//          modifydtm:
	//            description: Date and time of agreement modification
	//            type: timestamp
	//          frequecy:
	//            description: expected frequency of deliveries
	//            type: integer
	//          file2temp:
	//            description: Procedure for moving deliveries from file to temp
	//            type: string
	//          temp2stag:
	//            description: Procedure for moving deliveries from temp to stag
	//            type: string
	//          stag2repo:
	//            description: Procedure for moving deliveries from stag to repo
	//            type: string
	//          type_id:
	//            description: ID of type
	//            type: integer
	//          type_name:
	//            description: Name of type
	//            type: string
	//          group_id:
	//            description: ID of owning group
	//            type: integer
	//          group_name:
	//            description: Name of group
	//            type: string
	//          user_id:
	//            description: ID of owning user
	//            type: integer
	//          user_name:
	//            description: Name of user
	//            type: string
	//          user_realname:
	//            description: Realname of user
	//            type: string
	//          temp_count:
	//            description: Number of deliveries in temp
	//            type: integer
	//          stag_count:
	//            description: Number of deliveries in stag
	//            type: integer
	//          repo_count:
	//            description: Number of deliveries in repo
	//            type: integer
	res, err := rep.QueryJson(`SELECT * FROM meta.agreement_delivery_count_v WHERE id = $1`, 0, agreement_id)
	if err != nil {
		return err.Error()
	}
	return res
}

func AgreementList(c iris.Context, rep repository.Repository, date string) (string, error) {
	// swagger:operation GET /api/agreement/{date} Agreement AgreementList
	// List agreements and number of deliveries along with some state
	// ---
	// produces:
	// - application/json
	// parameters:
	// - name: date
	//   type: string
	//   in: path
	//   required: true
	// responses:
	//   '200':
	//     description: OK
	//     schema:
	//      type: array
	//      items:
	//        type: object
	//        title: Agreements
	//        properties:
	//          id:
	//            description: ID of agreement
	//            type: integer
	//          type_id:
	//            description: ID of agreement type (how to BULK INSERT)
	//            type: integer
	//          group_id:
	//            description: ID of owning group
	//            type: integer
	//          user_id:
	//            description: ID of owning user
	//            type: integer
	//          name:
	//            description: Name of agreement
	//            type: string
	//          pattern:
	//            description: Pattern for picking up dataset from inbox
	//            type: string
	//          createdtm:
	//            description: Date of creation
	//            type: string
	//          modifydtm:
	//            description: Date of last modification
	//            type: string
	//          frequecy:
	//            description: expected frequency of deliveries
	//            type: integer
	//          description:
	//            description: Description of agreement
	//            type: string
	//          file2temp:
	//            description: Procedure for moving deliveries from file to temp
	//            type: string
	//          temp2stag:
	//            description: Procedure for moving deliveries from temp to stag
	//            type: string
	//          stag2repo:
	//            description: Procedure for moving deliveries from stag to repo
	//            type: string
	//          user_realname:
	//            description: Real name of owning user
	//            type: string
	//          group_name:
	//            description: Name of owning group
	//            type: string
	//          err:
	//            description: Number of deliveries on error (NULL if none)
	//            type: integer
	//          ok:
	//            description: Number of deliveries in state OK
	//            type: integer
	//          status_date:
	//            description: Date of last identified pattern (YYYYMMDD) in a delivery
	//            type: string
	//          status_date:
	//            description: Pct difference from allowed distance to latest delivery versus frequency
	//            type: float
	return rep.QueryJson(`SELECT * FROM meta.get_agreements($1)`, 0, date)
}

func AgreementColumn(c iris.Context, rep repository.Repository, agreement_id int64) string {
	// swagger:operation GET /api/agreement/column/{agreement_id} Agreement AgreementColumn
	// List columns of agreement
	// ---
	// produces:
	// - application/json
	// parameters:
	// - name: agreement_id
	//   type: integer
	//   in: path
	//   required: true
	// responses:
	//   '200':
	//     description: OK
	//     schema:
	//      type: array
	//      items:
	//        type: object
	//        title: AgreementAttribute
	//        properties:
	//          agreement_id:
	//            description: ID of agreement
	//            type: integer
	//          table_schema:
	//            description: Schema of table in stage
	//            type: string
	//          table_name:
	//            description: Name of table
	//            type: string
	//          mapping:
	//            description: Mapping code
	//            type: string
	//          mapping_type:
	//            description: Type of mapping (custom/default)
	//            type: string
	//          column_name:
	//            description: Name of column
	//            type: string
	//          data_type:
	//            description: SQL data type
	//            type: string
	//          character_maximum_length:
	//            description: If *CHAR type the max length
	//            type: integer
	//          numeric_precision:
	//            description: If NUMERIC the precision
	//            type: integer
	//          numeric_scale:
	//            description: If NUMERIC the scale
	//            type: integer
	//          numeric_scale:
	//            description: If NUMERIC the scale
	//            type: integer
	//          ordinal_position:
	//            description: Order in table
	//            type: integer
	res, err := rep.QueryJson(`
    SELECT *
      FROM meta.column_mapping_v
     WHERE table_schema = 'init'
       AND agreement_id = $1
       AND meta.user_access($2, agreement_id, 'VIEW') > 0
     ORDER BY ordinal_position`, 0, agreement_id, "system")
	if err != nil {
		return err.Error()
	}
	return res
}

func AgreementRule(c iris.Context, rep repository.Repository, agreement_id int64) string {
	// swagger:operation GET /api/agreement/rule/{agreement_id} Agreement AgreementRule
	// List agreement rules
	// ---
	// produces:
	// - application/json
	// parameters:
	// - name: agreement_id
	//   type: integer
	//   in: path
	//   required: true
	// responses:
	//   '200':
	//     description: OK
	//     schema:
	//      type: array
	//      items:
	//        type: object
	//        title: AgreementRule
	//        properties:
	//          agreement_id:
	//            description: ID of agreement
	//            type: integer
	//          rule_id:
	//            description: ID of rule within agreement
	//            type: integer
	//          rule_text:
	//            description: Code of rule
	//            type: string
	res, err := rep.QueryJson(`
    SELECT *
      FROM meta.agreement_rule
     WHERE agreement_id = $1
       AND meta.user_access($2, agreement_id, 'VIEW') > 0
     ORDER BY rule_id`, 0, agreement_id, "system")
	if err != nil {
		return err.Error()
	}
	return res
}

func AgreementTrigger(c iris.Context, rep repository.Repository, agreement_id int64) string {
	// swagger:operation GET /api/agreement/trigger/{agreement_id} Agreement AgreementTrigger
	// List agreement triggers
	// ---
	// produces:
	// - application/json
	// parameters:
	// - name: agreement_id
	//   type: integer
	//   in: path
	//   required: true
	// responses:
	//   '200':
	//     description: OK
	//     schema:
	//      type: array
	//      items:
	//        type: object
	//        title: AgreementRule
	//        properties:
	//          agreement_id:
	//            description: ID of agreement
	//            type: integer
	//          trigger_id:
	//            description: ID of trigger within agreement
	//            type: integer
	//          trigger_text:
	//            description: Code of trigger
	//            type: string
	//          description:
	//            description: Trigger description
	//            type: string
	res, err := rep.QueryJson(`
    SELECT *
      FROM meta.agreement_trigger
     WHERE agreement_id = $1
       AND meta.user_access($2, agreement_id, 'VIEW') > 0
     ORDER BY trigger_id`, 0, agreement_id, "system")
	if err != nil {
		return err.Error()
	}
	return res
}
