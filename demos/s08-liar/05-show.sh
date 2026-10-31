#!/usr/bin/env bash
# Step 5: look at the evidence as files. Afterwards, `vi` any path this prints.
set -uo pipefail
cd "$(dirname "$0")" || exit 1; . ./env.sh
L=$S/asker/data/ledger

echo "1. The liar's lie: the host's weights-digest cache entry (02-lie.sh wrote it)"
for f in "$S"/liar/home/.cache/mesh-llm/weights-digest/*.json; do echo "   $f"; jq -c . "$f" | sed 's/^/   /'; done
echo
echo "2. The signed verdict the asker holds: $L/received-adjudications.jsonl"
tail -1 "$L/received-adjudications.jsonl" | jq '{verdict, referee: .referee_node_id, twins: .half_node_ids,
  status: .verdict_capsule.model_attestation.compute_attestation.adjudication.status,
  model_weights_both_claimed: .verdict_capsule.model_attestation.compute_attestation.adjudication.weights_digest,
  signed_by_key: .verdict_capsule.key_id}' | names
echo
echo "3. This run's files: $S/runs/latest/"
ls -1 "$S/runs/latest/" | sed 's/^/   /'
