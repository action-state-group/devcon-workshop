package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const digest = "496dbf18c68f97a2e6bae088f0777281a1df5dc7089ab8f9e2c66f484df541b0"

func TestRunWritesSignedTestnetTermsLeg(t *testing.T) {
	out := filepath.Join(t.TempDir(), "terms.json")
	if err := run(out, "500000", digest, baseSepoliaUSDC, 6); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	var c struct {
		Settlement struct {
			Leg    string `json:"leg"`
			Amount struct {
				Value     string `json:"value"`
				AssetCode string `json:"assetCode"`
			} `json:"amount"`
			Deliverable struct {
				ContentDigest string `json:"content_digest"`
			} `json:"deliverable"`
		} `json:"settlement"`
		Signature string `json:"signature"`
		KeyID     string `json:"key_id"`
	}
	if err := json.Unmarshal(data, &c); err != nil {
		t.Fatal(err)
	}
	s := c.Settlement
	if s.Leg != "terms" || s.Amount.Value != "500000" || s.Deliverable.ContentDigest != digest || c.Signature == "" || len(c.KeyID) != 64 {
		t.Fatalf("unexpected leg: %s", data)
	}
	if strings.HasPrefix(s.Amount.AssetCode, "eip155:8453/") {
		t.Fatalf("names Base mainnet: %s", s.Amount.AssetCode)
	}
	if fi, _ := os.Stat(out); fi.Mode().Perm() != 0o600 {
		t.Fatalf("mode %v", fi.Mode().Perm())
	}
}

func TestRunRefuses(t *testing.T) {
	dir := t.TempDir()
	existing := filepath.Join(dir, "exists.json")
	if err := os.WriteFile(existing, []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	for name, args := range map[string][3]string{
		"no out":         {"", "500000", digest},
		"decimal amount": {filepath.Join(dir, "a"), "0.50", digest},
		"short digest":   {filepath.Join(dir, "b"), "500000", "abc"},
		"upper digest":   {filepath.Join(dir, "c"), "500000", strings.ToUpper(digest)},
		"overwrite":      {existing, "500000", digest},
	} {
		if err := run(args[0], args[1], args[2], baseSepoliaUSDC, 6); err == nil {
			t.Errorf("%s: want an error", name)
		}
	}
}
