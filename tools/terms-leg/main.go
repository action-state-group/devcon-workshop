// Command terms-leg writes the buyer's terms leg of a sale: a bare, signed Capsule whose top-level
// settlement member says what the buyer agreed to pay and which content it expects. It is the file
// the seller's `capsulectl deal note --kind payment_received|delivered --terms FILE` answers.
//
// The workshop's stand-in until a capsulectl-deal release carries `capsulectl deal terms-leg`
// (action-state-group/evidencebook-deal#70). It signs with a fresh Ed25519 key that is thrown away.
//
//	terms-leg -out terms.json -amount 500000 -content-digest <sha256 hex>
//
// The default asset is USDC on Base Sepolia, a test network: the workshop's payment is simulated,
// and nothing sealed may name a mainnet.
package main

import (
	"crypto/ed25519"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"regexp"
	"time"

	emit "github.com/action-state-group/capsule-emit/go"
)

const baseSepoliaUSDC = "eip155:84532/erc20:0x036cbd53842c5426634e7929541ec2318f3dcf7e"

var (
	digits = regexp.MustCompile(`^[0-9]+$`)
	sha256 = regexp.MustCompile(`^[0-9a-f]{64}$`)
)

func main() {
	out := flag.String("out", "", "where to write the terms leg (required; not overwritten)")
	amount := flag.String("amount", "", "the price in the asset's base units (required; USDC has 6 decimals)")
	digest := flag.String("content-digest", "", "sha256 hex of the content the buyer expects (required)")
	asset := flag.String("asset", baseSepoliaUSDC, "CAIP-19 asset code")
	scale := flag.Int("asset-scale", 6, "the asset's decimals")
	flag.Parse()
	if err := run(*out, *amount, *digest, *asset, *scale); err != nil {
		fmt.Fprintln(os.Stderr, "terms-leg:", err)
		os.Exit(1)
	}
}

func run(out, amount, digest, asset string, scale int) error {
	switch {
	case out == "":
		return fmt.Errorf("-out is required")
	case !digits.MatchString(amount):
		return fmt.Errorf("-amount must be a whole number of base units, got %q", amount)
	case !sha256.MatchString(digest):
		return fmt.Errorf("-content-digest must be 64 lowercase hex characters")
	}
	member, err := json.Marshal(map[string]any{
		"version": "0", "leg": "terms", "sealer_role": "payer",
		"amount":      map[string]any{"value": amount, "assetCode": asset, "assetScale": scale},
		"deliverable": map[string]any{"content_digest": digest},
	})
	if err != nil {
		return err
	}
	built, err := emit.Build(emit.Input{
		ActionID: "buyer/terms", ActionType: emit.ActionTypeFYI, Operator: "buyer", Developer: "workshop-buyer-agent",
		Timestamp:  time.Now().UTC().Truncate(time.Second),
		Extensions: []emit.Extension{{Name: "settlement", Value: member}},
	})
	if err != nil {
		return err
	}
	pub, key, err := ed25519.GenerateKey(nil)
	if err != nil {
		return err
	}
	identity, err := emit.NewEd25519SigningIdentity(key)
	if err != nil {
		return err
	}
	envelope, err := emit.Sign(built, identity)
	if err != nil {
		return err
	}
	capsule := make(map[string]any, len(built.Value)+2)
	for k, v := range built.Value {
		capsule[k] = v
	}
	capsule["signature"] = hex.EncodeToString(envelope)
	capsule["key_id"] = hex.EncodeToString(pub)
	data, err := json.Marshal(capsule)
	if err != nil {
		return err
	}
	f, err := os.OpenFile(out, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	if _, err := f.Write(data); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}
