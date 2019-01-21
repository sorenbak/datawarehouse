package auth

import (
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io/ioutil"
	"net/http"
	"time"

	jwt "github.com/dgrijalva/jwt-go"
	"github.com/gobuffalo/envy"
)

// Cache of key id --> decoded public keys
var cached_public_key = make(map[string]interface{})

func GetValidationKeyFromAzure(token *jwt.Token) (interface{}, error) {

	// Check if key id present
	if token.Header["kid"] == nil {
		// Authenticate using own secret (test only)
		secret := envy.Get("JWTSECRET", "")
		if secret != "" {
			return []byte(secret), nil
		}
		// Bail out - no key available
		fmt.Println("No key id in token header")
		return nil, nil
	}

	// Get the key id from header
	kid := token.Header["kid"].(string)

	// Check if key is cached
	// TODO: Need mechanism for refresh cache (timeout)
	if cached_public_key[kid] != nil {
		return cached_public_key[kid], nil
	}

	// Init URL with authorization links         <-------- Tenant -------->
	url := "https://login.microsoftonline.com/" + envy.Get("TENANTID", "") + "/.well-known/openid-configuration"

	// Python inspired method
	// -----------------------------
	// Retrieve redirect uri to jwks
	jwk_uri, err := getKeyValues(url)
	if err != nil {
		return nil, err
	}

	// Retrieve the jwk keys in redirect uri
	jwk_keys, err := getKeyValues(jwk_uri["jwks_uri"].(string))
	if err != nil {
		return nil, err
	}
	// Find the token key id (kid) in the jwk keys and set x5c accordingly
	x5c := ""
	for _, hash := range jwk_keys["keys"].([]interface{}) {
		key := hash.(map[string]interface{})
		if key["kid"].(string) == kid {
			vals := key["x5c"].([]interface{})
			x5c = vals[0].(string)
		}
	}

	// Create PEM structure for decoding
	cert := "-----BEGIN CERTIFICATE-----\n" + x5c + "\n-----END CERTIFICATE-----\n"
	fmt.Println(cert)

	// Decode the PEM structure into x509 encoded certificate
	block, _ := pem.Decode([]byte(cert))
	if block == nil {
		return "Panic - could not pem.Decore certificate", nil
	}

	// Parse the x509 encoded certificate
	cert_parsed, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		fmt.Println(err)
		return "", err
	}

	// Return public key part of the certificate for auth handler
	public_key := cert_parsed.PublicKey
	cached_public_key[kid] = public_key

	fmt.Println(public_key)
	return public_key, nil
}

func getKeyValues(url string) (map[string]interface{}, error) {
	var netClient = &http.Client{
		Timeout: time.Second * 10,
	}

	fmt.Printf("Contacting [%s]...\n", url)
	res, err := netClient.Get(url)
	if err != nil {
		return nil, err
	}
	jsondata, err := ioutil.ReadAll(res.Body)
	if err != nil {
		return nil, err
	}

	keys := make(map[string]interface{})
	err = json.Unmarshal(jsondata, &keys)
	if err != nil {
		return nil, err
	}

	return keys, nil
}
