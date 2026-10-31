#!/usr/bin/env bash
# Step 7: the asker sends the liar 6 different requests, then counts both sides' records.
# The asker seals its own half of every exchange. The liar pushes its signed half of each exchange
# it logged, and the asker's plugin checks each push (signature, signed checkpoint, inclusion
# proof) before it keeps it. Halves pair by the answer's digest and the serving node, as the
# Evidence page pairs them.
#   07-count.sh [how many requests, default 6]
set -uo pipefail
cd "$(dirname "$0")" || exit 1; . ./env.sh
K=${1:-6}
RUN=$S/runs/omit-$(date +%m%d-%H%M%S); mkdir -p "$S/runs"; mkdir "$RUN" || exit 1; ln -sfn "$RUN" "$S/runs/latest"
read -r LIAR _ < "$S/liar/ident" || { echo "the liar is not up; run 01-start.sh first"; exit 1; }
L=$S/asker/data/ledger
MODEL=$(curl -fsS "http://127.0.0.1:$(console honest)/api/status" | jq -er '.model_name // .models[0]') || exit 1
[ -e "$OMIT_TOGGLE" ] || echo "(the liar's selective log is off: run 06-omit.sh first to see the gap)"

served_by='.model_attestation.compute_attestation["x-mesh-poc-v1"].serving_provenance.served_by_node_id'
# The asker's own halves of exchanges the liar served (not the records citing a received half).
own()  { [ -f "$L/capsules.jsonl" ] && jq -c --arg id "$LIAR" "select($served_by == \$id and (.model_attestation.compute_attestation.received_half == null))
  | {id: .capsule_id, answer: .effect.response_digest}" "$L/capsules.jsonl"; }
held() { [ -f "$L/received-capsules.jsonl" ] && jq -c --arg id "$LIAR" ".capsule? // . | select($served_by == \$id) | {id: .capsule_id, answer: .effect.response_digest}" "$L/received-capsules.jsonl"; }
lines() { count_lines "$1"; }
# The liar's own ledger, on this same box: the cross-check that a half the asker lacks was never sealed
# (and not merely late or lost on the way).
LL=$S/liar/data/ledger/capsules.jsonl
own > "$RUN/own-before.jsonl"; held > "$RUN/held-before.jsonl"; ll0=$(lines "$LL")
r0=$(lines "$L/rejected-record-pushes.jsonl"); i0=$(lines "$L/received-inclusion.jsonl")

for k in $(seq "$K"); do
  jq -n --arg m "$MODEL" --arg q "Write the number $k as a word, and nothing else." \
    '{model:$m, messages:[{role:"user",content:$q}], max_tokens:8, temperature:0, seed:7}' > "$RUN/request-$k.json"
  code=000
  for _ in $(seq 20); do   # 409: the asker does not see the liar serving yet; nothing was served, so retry
    code=$(curl -sS -m 90 -o "$RUN/answer-$k.json" "http://127.0.0.1:$(api asker)/v1/chat/completions" \
      -H 'content-type: application/json' -H "x-mesh-target: $LIAR" --data-binary @"$RUN/request-$k.json" -w '%{http_code}')
    [ "$code" = 409 ] || break; sleep 3
  done
  echo "request $k, asker -> liar: HTTP $code, answer: $(jq -r '.choices[0].message.content' "$RUN/answer-$k.json" 2>/dev/null | tr '\n' ' ')"
  [ "$code" = 200 ] || { echo "a request failed; run 07-count.sh again"; exit 1; }
done

new() { grep -vxF -f "$1" || true; }   # lines not in file $1
for _ in $(seq 30); do [ "$(own | new "$RUN/own-before.jsonl" | wc -l)" -ge "$K" ] && break; sleep 2; done
own | new "$RUN/own-before.jsonl" > "$RUN/own.jsonl"
[ "$(count_lines "$RUN/own.jsonl")" -ge "$K" ] || { echo "the asker has not sealed its own $K halves after 60 s; run 07-count.sh again"; exit 1; }
# The liar pushes each half it logs when the exchange completes. Wait until no new one has come for 30 s
# (03 saw pushes arrive within seconds), so a slow push is not counted as left out.
last=-1; quiet=0
while [ "$quiet" -lt 15 ]; do
  n=$(held | new "$RUN/held-before.jsonl" | wc -l)
  if [ "$n" = "$last" ]; then quiet=$((quiet + 1)); else quiet=0; last=$n; fi
  [ "$n" -ge "$K" ] && break; sleep 2
done
held | new "$RUN/held-before.jsonl" > "$RUN/held.jsonl"

# Without all of the liar's ledger there is no telling "left out" from "not pushed": stop rather than
# guess on any read or parse error (a line still being written included; running 07 again is enough).
[ -r "$LL" ] && tail -n +"$((ll0 + 1))" "$LL" | jq -c '{id: .capsule_id, answer: .effect.response_digest}' > "$RUN/liar-ledger.jsonl" \
  || { echo "could not read the liar's ledger $LL; no count. Run 07-count.sh again."; exit 1; }
rej=$(( $(lines "$L/rejected-record-pushes.jsonl") - r0 )); inc=$(( $(lines "$L/received-inclusion.jsonl") - i0 ))

# One to one: each of the liar's halves (and each of its ledger records) pairs with at most one of the
# asker's, in order, so two equal answers can never both pair with one record.
jq -rn --slurpfile own "$RUN/own.jsonl" --slurpfile held "$RUN/held.jsonl" --slurpfile log "$RUN/liar-ledger.jsonl" '
  def take($a): (map(.answer) | index($a)) as $i | if $i == null then {hit: false, rest: .} else {hit: true, rest: del(.[$i])} end;
  reduce $own[] as $m ({held: $held, log: $log, out: []};
    (.held | take($m.answer)) as $h | (.log | take($m.answer)) as $g
    | .held = $h.rest | .log = $g.rest
    | .out += [if $h.hit then "logged" elif $g.hit then "late" else "omitted" end])
  | .out[]' > "$RUN/pairs.txt" && [ "$(count_lines "$RUN/pairs.txt")" -eq "$(count_lines "$RUN/own.jsonl")" ] \
  || { echo "could not pair the records; no count. Run 07-count.sh again."; exit 1; }
kept=$(grep -cx logged "$RUN/pairs.txt"); late=$(grep -cx late "$RUN/pairs.txt"); omitted=$(grep -cx omitted "$RUN/pairs.txt")

echo
echo "Each exchange, as the asker's records show it:"
k=0
while read -r st; do
  k=$((k + 1))
  case $st in
    logged)  echo "  $k. asker's half and the liar's signed half: logged" ;;
    late)    echo "  $k. asker's half only so far: the liar did seal it, its push has not arrived" ;;
    omitted) echo "  $k. asker's half only: the liar answered it and has no record of it" ;;
  esac
done < "$RUN/pairs.txt"
echo
# A push with no inclusion proof (the liar's checkpoint step failed) is kept but not proven: no clean count either.
if [ "$rej" -gt 0 ] || [ "$late" -gt 0 ] || [ "$inc" -lt "$kept" ]; then
  echo "Not a clean count: $rej of the liar's pushes were refused (rejected-record-pushes.jsonl), $late have not"
  echo "arrived, and $inc of its $kept pushed records came with an inclusion proof. This is not the selective log."
  echo "Run 07-count.sh again; on stage, use the fallback (README)."
  exit 1
fi
echo "The liar's $kept pushed records all passed the asker's checks: its signature, the checkpoint it"
echo "signed, and the inclusion proof under that checkpoint ($inc new in received-inclusion.jsonl, none"
echo "refused). Its log is intact. It is just short. (On this box we can also open the liar's own ledger,"
echo "$LL: it has no record of the other $omitted either.)"
echo
if [ "$omitted" -gt 0 ]; then
  echo "RED: the liar served the asker $k exchanges and its log holds $kept."
  echo "A log can be tamper-evident and still leave things out. The asker's own half is what shows it."
else
  echo "Every exchange is in the liar's log ($kept of $k): nothing left out."
fi
