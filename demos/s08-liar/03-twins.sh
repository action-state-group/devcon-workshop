#!/usr/bin/env bash
# Step 3: the asker sends the SAME request to the honest node and to the liar, as a marked twin
# pair (header x-mesh-twin-bracket), at temperature 0 with a fixed seed. Same model, same weights
# claimed, same request: two honest nodes would answer the same way.
#   03-twins.sh [question]
# Tested questions, by platform: on Linux x86_64 CPU (the provider VM) the default haiku and "Name
# three colors." both part; on macOS arm64 (Metal) the haiku gives the same words from Q4_K_M and
# Q8_0 and "Name three colors." parts (DRYRUN dry run 8), so it is the default there. Another
# question may get the same 48 tokens from both models, and then there is nothing for the referee
# to settle.
set -uo pipefail
cd "$(dirname "$0")" || exit 1; . ./env.sh
case "$(uname -s)" in Darwin) DEFAULT_Q="Name three colors." ;; *) DEFAULT_Q="Write a haiku about the ocean." ;; esac
Q=${1:-$DEFAULT_Q}
RUN=$S/runs/$(date +%m%d-%H%M%S); mkdir -p "$S/runs"; mkdir "$RUN" || exit 1; ln -sfn "$RUN" "$S/runs/latest"
BRACKET=s08-$(basename "$RUN")
read -r HONEST _ < "$S/honest/ident"; read -r LIAR _ < "$S/liar/ident"; read -r REFEREE _ < "$S/referee/ident"
HELD=$S/asker/data/ledger/received-capsules.jsonl
# The id the servers advertise on the mesh (local-gguf/sha256-…), not the catalog name.
MODEL=$(curl -fsS "http://127.0.0.1:$(console honest)/api/status" | jq -er '.model_name // .models[0]')

# How many signed halves the asker holds from one node.
held() { [ -f "$HELD" ] || { echo 0; return; }
  jq -r '.capsule? // . | .model_attestation.compute_attestation["x-mesh-poc-v1"].serving_provenance.served_by_node_id? // empty' "$HELD" | grep -c "^$1$"; }
ask() {  # ask <node> <name> [bracket]: route to that node with x-mesh-target
  # 409 = the asker does not see that node serving yet (it just restarted); nothing was served, so retry.
  local code
  for _ in $(seq 20); do
    code=$(curl -sS -m 90 -D "$RUN/$2.headers" -o "$RUN/$2.json" "http://127.0.0.1:$(api asker)/v1/chat/completions" \
      -H 'content-type: application/json' -H "x-mesh-target: $1" ${3:+-H "x-mesh-twin-bracket: $3"} \
      --data-binary @"$RUN/request.json" -w '%{http_code}')
    [ "$code" = 409 ] || break; sleep 3
  done
  echo "$code"; }

jq -n --arg m "$MODEL" --arg q "$Q" '{model:$m, messages:[{role:"user",content:$q}], max_tokens:48, temperature:0, seed:7}' > "$RUN/request.json"
echo "request: $(jq -c . "$RUN/request.json" | names)"

if [ "$(held "$REFEREE")" = 0 ]; then   # the asker picks a referee it has dealt with before
  echo "warm-up, asker -> referee: HTTP $(ask "$REFEREE" warmup)"
  for _ in $(seq 30); do [ "$(held "$REFEREE")" != 0 ] && break; sleep 2; done
fi
h0=$(held "$HONEST"); l0=$(held "$LIAR")
A=$(ask "$HONEST" twinA "$BRACKET"); echo "twin A, asker -> honest: HTTP $A"
B=$(ask "$LIAR" twinB "$BRACKET");   echo "twin B, asker -> liar:   HTTP $B"
[ "$A" = 200 ] && [ "$B" = 200 ] || { echo "a twin failed; run 03-twins.sh again"; exit 1; }
echo
echo "honest answered: $(jq -r '.choices[0].message.content' "$RUN/twinA.json" | tr '\n' '/')"
echo "liar answered:   $(jq -r '.choices[0].message.content' "$RUN/twinB.json" | tr '\n' '/')"

for _ in $(seq 45); do [ "$(held "$HONEST")" -gt "$h0" ] && [ "$(held "$LIAR")" -gt "$l0" ] && break; sleep 2; done
[ "$(held "$HONEST")" -gt "$h0" ] && [ "$(held "$LIAR")" -gt "$l0" ] \
  || { echo "the signed records of this pair did not arrive within 90 s; wait a minute, then run 03-twins.sh again"; exit 1; }
echo
echo "Each node pushed its signed record of the exchange to the asker. What each one claims it ran:"
claimed() { jq -r --arg id "$1" '.capsule? // . | .model_attestation.compute_attestation
  | select(.["x-mesh-poc-v1"].serving_provenance.served_by_node_id == $id) | .weights_digest.digest' "$HELD" | tail -1; }
WA=$(claimed "$HONEST"); WB=$(claimed "$LIAR")
echo "  $HONEST  weights sha256 ${WA:0:16}…" | names
echo "  $LIAR  weights sha256 ${WB:0:16}…" | names

# The capsules plugin's rule (capsules 0.1.7, referee/request.rs before_asking): a referee is asked
# only when ALL of these hold. There is no "different enough": one differing word is enough.
# (The asker's records carry these values; step 04 hands the plugin both texts to compare.)
words='[splits("\\s+") | select(length > 0)]'
diff=$(jq -rn --slurpfile a "$RUN/twinA.json" --slurpfile b "$RUN/twinB.json" "
  (\$a[0].choices[0].message.content | $words) as \$x | (\$b[0].choices[0].message.content | $words) as \$y
  | first(range(0; [(\$x|length), (\$y|length)] | max) | select(\$x[.] != \$y[.]))
  | \"\\(. + 1) \\(\$x[.] // \"(end)\") \\(\$y[.] // \"(end)\")\"")
echo
echo "Does this pair go to a referee? The plugin asks one only when all five hold:"
echo "  1. the asker's switch is on:     CAPSULES_ADJUDICATE_DIFFERING_TWINS=$(sed -n 's/^export CAPSULES_ADJUDICATE_DIFFERING_TWINS=\([^ ]*\).*/\1/p' "$S/asker/env")"
echo "  2. one marked pair:              both requests carried x-mesh-twin-bracket: $BRACKET"
echo "  3. not sampled:                  temperature $(jq -r .temperature "$RUN/request.json") (always the most likely next word,"
echo "                                   so the same weights should give the same words; seed $(jq -r .seed "$RUN/request.json") is fixed too)"
if [ -n "$WA" ] && [ "$WA" = "$WB" ]; then
  echo "  4. same weights claimed:         both signed records claim ${WA:0:16}… (Q8_0)"
else
  echo "  4. same weights claimed: NO (${WA:0:16}… vs ${WB:0:16}…): not comparable, no referee"; exit 1
fi
if [ -z "$diff" ]; then
  echo "  5. the answers differ: NO, word for word the same (twins_agree): no referee. Ask a tested question."; exit 1
fi
read -r at wa wb <<< "$diff"
echo "  5. the answers differ:           word $at: honest \"$wa\", liar \"$wb\" (compared word by word)"
echo
echo "Same request, same weights claimed, no sampling, different words. The plugin doesn't guess: with no"
echo "referee this pair stays inconclusive. Step 04 asks one: it answers the same request, and the twin whose"
echo "word it repeats at word $at stands; the other is contradicted."
jq -n --arg b "$BRACKET" --slurpfile rq "$RUN/request.json" --slurpfile a "$RUN/twinA.json" --slurpfile b2 "$RUN/twinB.json" \
  '{twin_bracket_id:$b, request_body:$rq[0], response_bodies:[$a[0], $b2[0]]}' > "$RUN/supply.json"
