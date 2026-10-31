#!/usr/bin/env bash
# Step 2: the hack. The liar's operator swaps in the smaller Q4_K_M model and keeps claiming Q8_0.
# No code change. fake_q8.sh (Sherlock2's script from the 10-12 run, unchanged) does two things:
#   - puts the Q4 bytes where the Q8 file was, zero-padded to the Q8 file's length, so the mesh
#     still lists the liar under the same model id as the honest Q8 nodes;
#   - writes the host's weights-digest cache entry with the REAL Q8 file's sha256, so the node
#     reports Q8 weights without hashing what it actually loaded.
set -uo pipefail
cd "$(dirname "$0")" || exit 1; . ./env.sh

./node.sh stop liar || { echo "the liar did not stop; nothing changed"; exit 1; }
./fake_q8.sh "$Q4_GGUF" "$(q8_path liar)" "$Q8_SHA" "$S/liar/home"
./node.sh start liar
for _ in $(seq 120); do curl -fsS -m 2 "http://127.0.0.1:$(api liar)/v1/models" 2>/dev/null | grep -q '"id"' && break; sleep 2; done

echo
echo "What the liar really has on disk vs what it claims:"
echo "  file it loads : $(head -c "$(file_size "$Q4_GGUF")" "$(readlink -f "$(q8_path liar)")" | sha256sum | cut -c1-16)…  (= Q4_K_M ${Q4_SHA:0:16}…)"
echo "  digest claimed: $(jq -r .digest "$S"/liar/home/"$CACHE_REL"/mesh-llm/weights-digest/*.json | cut -c1-16)…  (= Q8_0   ${Q8_SHA:0:16}…)"
