package main

// HACKY: Overridden by go generate
func GzipAsset(name string) ([]byte, error) { return nil, nil }
func GzipAssetNames() []string              { return nil }
