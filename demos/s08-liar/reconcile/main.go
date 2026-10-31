// SPDX-License-Identifier: Apache-2.0

// reconcile-asked reads the exchanges step 08 asked the liar about, as a JSON
// array of evidencebook.AskedExchange, and prints evidencebook.ReconcileAsked's
// report as JSON (evidencebook#206 row 9). It verifies nothing itself: step 08
// passes only what the asker's capsules plugin verified.
//
//	reconcile-asked <asked.json>
package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/action-state-group/evidencebook"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: reconcile-asked <asked.json>")
		os.Exit(2)
	}
	raw, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	var asked []evidencebook.AskedExchange
	if err := json.Unmarshal(raw, &asked); err != nil {
		fmt.Fprintln(os.Stderr, "asked.json:", err)
		os.Exit(1)
	}
	out, err := json.Marshal(evidencebook.ReconcileAsked(asked))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println(string(out))
}
