// Command go-seal is the workshop's starting point for the evidencebook Go SDK: it opens a book on
// disk, seals one Evidence Result in it and cuts a checkpoint, then prints the record and whether
// the checkpoint covers it.
//
//	go-seal                      seal the Deal Reconcile vector pair-matched (testdata/)
//	go-seal -result FILE         seal your own {"contract_ref": ..., "result": {...}} file
//	go-seal -book DIR            keep the book somewhere else (default ~/.devcon8/go-seal)
//
// It follows ExampleBook_SealResult in evidencebook v0.12.2 (example_guide_test.go). The keys are
// made on first run and kept, 0600, in the book directory, so a second run appends to the same log.
package main

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	_ "embed"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/action-state-group/evidencebook"
)

//go:embed testdata/pair-matched.json
var pairMatched []byte

func main() {
	home, _ := os.UserHomeDir()
	dir := flag.String("book", filepath.Join(home, ".devcon8", "go-seal"), "book directory")
	resultFile := flag.String("result", "", `file holding {"contract_ref": "...", "result": {...}}; default: the pair-matched vector`)
	flag.Parse()

	input := pairMatched
	if *resultFile != "" {
		var err error
		if input, err = os.ReadFile(*resultFile); err != nil {
			log.Fatal(err)
		}
	}
	var in struct {
		ContractRef string          `json:"contract_ref"`
		Result      json.RawMessage `json:"result"`
	}
	if err := json.Unmarshal(input, &in); err != nil || in.ContractRef == "" || len(in.Result) == 0 {
		log.Fatalf("the input needs contract_ref and result: %v", err)
	}

	ctx := context.Background()
	if err := os.MkdirAll(*dir, 0o700); err != nil {
		log.Fatal(err)
	}
	recordKey, checkpointKey := loadKey(filepath.Join(*dir, "record.key")), loadKey(filepath.Join(*dir, "checkpoint.key"))
	store, err := evidencebook.OpenFileStore(filepath.Join(*dir, "records"))
	if err != nil {
		log.Fatal(err)
	}
	substrate, err := evidencebook.OpenCLL(filepath.Join(*dir, "cll.jsonl"), "workshop-log", checkpointKey)
	if err != nil {
		log.Fatal(err)
	}
	signer, err := evidencebook.NewEd25519Signer(recordKey)
	if err != nil {
		log.Fatal(err)
	}
	originals, err := evidencebook.OpenOriginalsFile(ctx, filepath.Join(*dir, "originals.jsonl"), "workshop", signer.PublicKey())
	if err != nil {
		log.Fatal(err)
	}
	book, err := evidencebook.Open(ctx, evidencebook.Config{
		BookID: "workshop", Operator: "workshop-participant",
		Store: store, Substrate: substrate, Originals: originals, Signer: signer,
	})
	if err != nil {
		log.Fatal(err)
	}
	defer book.Release()

	none := func() (evidencebook.Record, bool, error) { return evidencebook.Record{}, false, nil }
	add := func(e evidencebook.Entry) (evidencebook.Record, error) { return book.Append(ctx, e) }
	sealed, _, checkpoint, err := book.SealResult(ctx, in.Result, in.ContractRef, nil, none, add)
	if err != nil {
		log.Fatal(err)
	}
	covered, err := book.CheckpointCovers(ctx, sealed.Seq)
	if err != nil {
		log.Fatal(err)
	}
	out, _ := json.MarshalIndent(sealed, "", "  ")
	fmt.Printf("%s\n", out)
	fmt.Printf("checkpoint %d covers record %d: %v\n", checkpoint, sealed.Seq, covered)
	fmt.Printf("book: %s\n", *dir)
}

// loadKey reads an Ed25519 seed from path, or makes one and writes it 0600.
func loadKey(path string) ed25519.PrivateKey {
	seed, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		seed = make([]byte, ed25519.SeedSize)
		if _, err := rand.Read(seed); err != nil {
			log.Fatal(err)
		}
		if err := os.WriteFile(path, seed, 0o600); err != nil {
			log.Fatal(err)
		}
	} else if err != nil {
		log.Fatal(err)
	}
	if len(seed) != ed25519.SeedSize {
		log.Fatalf("%s is not a %d-byte seed", path, ed25519.SeedSize)
	}
	return ed25519.NewKeyFromSeed(seed)
}
