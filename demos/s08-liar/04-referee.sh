#!/usr/bin/env bash
# Step 4: the asker hands the twin pair to its own capsules plugin. The plugin picks a referee that
# serves the same model, sends it the same request, and the referee signs a verdict: which twin's
# answer it could reproduce, and which one it contradicts.
set -uo pipefail
cd "$(dirname "$0")" || exit 1; . ./env.sh
RUN=$S/runs/latest
[ -s "$RUN/supply.json" ] || { echo "run 03-twins.sh first"; exit 1; }

curl -sS -m 180 "http://127.0.0.1:$(console asker)/api/plugins/capsules/tools/referee_supply_twin_texts" \
  -H 'content-type: application/json' --data-binary @"$RUN/supply.json" > "$RUN/verdict.json"
echo "verdict:"
jq '.considered.row // .' "$RUN/verdict.json" | names
echo
echo "The asker holds the signed verdict in $S/asker/data/ledger/received-adjudications.jsonl"
echo "Evidence page: http://127.0.0.1:$(console asker)/plugins/capsules/evidence (published on the host loopback)"
