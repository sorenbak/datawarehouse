package controllers

import (
	"github.com/kataras/iris"
	"github.com/sorenbak/datawarehouse/repository"
)

func AgreementAttributeV(c iris.Context, rep repository.Repository) string {
	// swagger:operation GET /api/agreement_attribute_v/{id} Agreement AgreementAttributeV
	// List available agreement details
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
	//        title: Cutoffs
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
	res, err := rep.QueryJson(`SELECT * FROM meta.agreement_attribute_v`, 0)
	if err != nil {
		return err.Error()
	}
	return res
}

func AgreementDeliveryCountV(c iris.Context, rep repository.Repository, agreement_id int64) string {
	// swagger:operation GET /api/agreement_delivery_count_v/{agreemet_id} Agreement AgreementDeliveryCountV
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
