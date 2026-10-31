#!/usr/bin/env bash
# Step 8: the asker asks the liar for its record of each exchange step 7 sent: a signed evidence
# request (draft-mih-agent-evidence-request-00), one per exchange, through the asker's own capsules
# plugin (the `mesh_evidence_request` tool, the same ask as the Evidence page's "Ask them for their
# record"). The plugin checks each answer against the liar's key. The liar's answers verify and its
# records number without a gap; the asker then reconciles them against its own halves
# (evidencebook ReconcileAsked, evidencebook#206 row 9) and prints RED for each exchange the liar
# confirmed it holds no record of. RED comes only from verified answers; nothing here ever calls
# the log complete.
# The signed request needs a host that announces plugin keys: the cast and attendees run the
# unreleased mesh-llm lab build 3ffa5c4f1d7d162c964fc7fb24937c7ed5a12301 (pre-release
# action-state-group/devcon-workshop mesh-llm-lab-3ffa5c4f1) with capsules 0.1.6 (env.sh), so 08's RED reproduces
# for everyone on those pins. On a host that announces none, such as
# mesh-llm 0.78.1, the asker cannot sign and the liar refuses every ask; then 08 says so and prints
# no RED (the fallback).
#   08-ask.sh          (after 07-count.sh, on that run's files)
# Rehearsal only: S08_DROP_ASK=<k> skips the ask for exchange k, as if no answer came back, to see
# 08's output when one answer is missing. Never set it on stage.
set -uo pipefail
cd "$(dirname "$0")" || exit 1; . ./env.sh
RUN=$(readlink -f "$S/runs/latest")
case $(basename "$RUN") in omit-*) ;; *) echo "runs/latest is not a 07-count.sh run; run 07-count.sh first"; exit 1;; esac
[ -s "$RUN/own.jsonl" ] && [ -s "$RUN/pairs.txt" ] || { echo "07-count.sh did not finish its count in $RUN; run it again"; exit 1; }
grep -qvE '^(logged|omitted)$' "$RUN/pairs.txt" && { echo "07-count.sh did not end with a clean count in $RUN; run it again"; exit 1; }
read -r LIAR _ < "$S/liar/ident" || { echo "the liar is not up; run 01-start.sh first"; exit 1; }
L=$S/asker/data/ledger
K=$(wc -l < "$RUN/own.jsonl")

# Each of the asker's own halves from step 7, with both digests of its exchange (the ask names them).
jq -c --slurpfile own "$RUN/own.jsonl" '($own | map(.id)) as $ids | select(.capsule_id as $c | $ids | index($c))
  | {id: .capsule_id, request: .effect.request_digest, answer: .effect.response_digest}' "$L/capsules.jsonl" > "$RUN/ask-halves.jsonl"
[ "$(wc -l < "$RUN/ask-halves.jsonl")" = "$K" ] || { echo "could not find the asker's $K halves in $L/capsules.jsonl"; exit 1; }

# Does the asker sign what it sends? capsules signs only once its host has announced its key
# (peer_keys.rs logs one of these three lines at start; anything else is "unknown").
signed=unknown
if grep -q "this node's key is announced by the host" "$S/asker/logs/node.log"; then signed=yes
elif grep -q "the host announces no plugin keys; this node's key was not announced" "$S/asker/logs/node.log"; then signed=no-host
elif grep -q "this node's key was not announced" "$S/asker/logs/node.log"; then signed=no-refused; fi

# On screen, which builds this is (the pins in env.sh, and what the binary says it is).
echo "Builds: mesh-llm $("$MESH_LLM" --version 2>/dev/null | tail -1 | sed 's/^mesh-llm //'), the unreleased lab build $MESH_SOURCE (pre-release action-state-group/devcon-workshop $MESH_VERSION), and capsules $CAPSULES_VERSION on all four nodes; the liar adds redteam/selective-log.patch."
tool() { rm -f "$2"; curl -sS -m 60 -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$(console asker)/api/plugins/capsules/tools/mesh_evidence_request" \
  -H 'content-type: application/json' --data-binary @"$1"; }
held_rec() { jq -c --arg id "$1" "(.capsule? // .) | select(.capsule_id == \$id)" "$L/received-capsules.jsonl" | tail -1; }
sp='.model_attestation.compute_attestation["x-mesh-poc-v1"].serving_provenance'
if [ "$signed" = yes ]; then
  # Context, one line: a request for the whole run is refused; records come one exchange at a time.
  jq -n --arg p "$LIAR" '{peer_id:$p, request:{profile:"evidence-interop/0", subject:{range:[0, 1000000]}, coverage:{min_freshness:1}}}' > "$RUN/ask-range.json"
  rc=$(tool "$RUN/ask-range.json" "$RUN/ask-range.answer.json")
  if [ "$rc" = 200 ]; then
    rs=$(jq -r '.verification | if .state == "refusal" then "refused, signed: " + .reason else .state // "no answer" end' "$RUN/ask-range.answer.json" 2>/dev/null)
  else rs="no answer (HTTP $rc)"; fi
  echo "One signed request for the whole run (range): $rs. So, one per exchange:"
fi
echo "The asker asks the liar, signed$([ "$signed" = yes ] || echo " if it can"), for its record of each of the $K exchanges of step 7:"
k=0; states=()
while read -r h; do
  k=$((k + 1))
  jq -n --arg p "$LIAR" --arg c "exchange-digests:$(jq -r .request <<< "$h"):$(jq -r .answer <<< "$h")" \
    '{peer_id:$p, request:{profile:"evidence-interop/0", subject:{correlation:$c}, coverage:{min_freshness:1}}}' > "$RUN/ask-$k.json"
  if [ "${S08_DROP_ASK:-}" = "$k" ]; then rm -f "$RUN/ask-$k.answer.json"; code=dropped
  else code=$(tool "$RUN/ask-$k.json" "$RUN/ask-$k.answer.json"); fi
  st=$(jq -r '.verification | if .state == "refusal" then "refusal:" + .reason else .state // "none" end' "$RUN/ask-$k.answer.json" 2>/dev/null)
  [ "$code" = 200 ] || st="error:HTTP $code"
  states+=("$st")
  case $st in
    refusal:no_such_subject) echo "  $k. the liar refused, signed: no_such_subject: it holds no record of this exchange (its signature checks)" ;;
    refusal:*) echo "  $k. the liar refused, signed: ${st#refusal:} (its signature checks)" ;;
    artifact)
      id=$(jq -r '.held[0] // empty' "$RUN/ask-$k.answer.json")
      if [ -n "$id" ] && rec=$(held_rec "$id") && [ -n "$rec" ]; then
        echo "  $k. the liar answered, signed: its record of this exchange, seq $(jq -r "$sp.seq" <<< "$rec") (prev $(jq -r "$sp.prev_seq // \"none\"" <<< "$rec")), verified"
      elif [ "$(jq -r '.verification.records | length' "$RUN/ask-$k.answer.json")" = 0 ]; then
        echo "  $k. the liar answered, signed: its verified answer carries no record of this exchange"
      else
        echo "  $k. the liar answered, signed, and the asker could not hold the record it carried"
      fi ;;
    *) echo "  $k. no usable answer: $st" ;;
  esac
done < "$RUN/ask-halves.jsonl"
echo

# The signed path: the liar served at least one answer. The asker reconciles all of them against its
# own halves (evidencebook ReconcileAsked); only what its plugin verified goes in. "covers": the liar
# cuts a checkpoint at every record it pushes, and 07 waited until no push came for 30 s, so the
# liar's newest anchor, which a min_freshness 1 answer uses, postdates every record it sealed for
# these exchanges.
if printf '%s\n' "${states[@]}" | grep -qvx 'refusal:not_authorized'; then
  [ -x "$RECONCILE" ] || { echo "no $RECONCILE to reconcile with: no verdict"; exit 1; }
  k=0
  while read -r h; do
    k=$((k + 1)); a=$RUN/ask-$k.answer.json; st=${states[$((k - 1))]}
    own=$(jq -c '{record_id: .id, request_digest: .request, response_digest: .answer}' <<< "$h")
    case $st in
      artifact)
        recs=$(for id in $(jq -r '.held[]?' "$a"); do held_rec "$id"; done | jq -sc "map({record_id: .capsule_id,
          request_digest: .effect.request_digest, response_digest: .effect.response_digest, seq: $sp.seq, prev_seq: $sp.prev_seq})")
        # A verified answer whose record the asker could not hold says nothing about that record.
        if [ "$(jq -r '.verification.records | length' "$a")" -gt 0 ] && [ "$recs" = "[]" ]; then
          jq -nc --argjson o "$own" '{own: $o, outcome: "failed"}'
        else
          jq -nc --argjson o "$own" --argjson r "$recs" '{own: $o, outcome: "answered", records: $r, covers: true}'
        fi ;;
      refusal:*) jq -nc --argjson o "$own" --arg r "${st#refusal:}" '{own: $o, outcome: "refused", reason: $r, covers: true}' ;;
      error:*) jq -nc --argjson o "$own" '{own: $o, outcome: "absent"}' ;;
      *) jq -nc --argjson o "$own" '{own: $o, outcome: "failed"}' ;;
    esac
  done < "$RUN/ask-halves.jsonl" | jq -s . > "$RUN/asked.json"
  "$RECONCILE" "$RUN/asked.json" > "$RUN/reconcile.json" || { echo "the reconcile failed: no verdict"; exit 1; }
  verdict=$(jq -r .verdict "$RUN/reconcile.json")
  seqs=$(jq -r '.run.seqs | map(tostring) | join(", ")' "$RUN/reconcile.json")
  # "Every answer verifies" and any claim about gaps only when every result is LOGGED or OMITTED: a
  # lost answer, or a refusal that withholds a record the liar holds, would leave a gap too.
  nx=$(jq -r '[.results[] | select(.state == "UNRESOLVED" or .state == "REFUSED")] | length' "$RUN/reconcile.json")
  allv=yes; for st in "${states[@]}"; do case $st in artifact|refusal:*) ;; *) allv=no ;; esac; done
  [ "$nx" = 0 ] || allv=no
  if [ -n "$seqs" ]; then
    if [ "$allv" = no ]; then
      echo "The liar's records that came back are numbered $seqs. Not every exchange was answered with"
      echo "a verified record or a signed no_such_subject, so nothing is claimed about gaps."
    elif [ "$(jq -r .run.gapless "$RUN/reconcile.json")" = true ]; then
      echo "Every answer verifies, and the liar's records that came back are numbered $seqs: no gap."
      echo "By its own answers alone, nothing is missing."
    else
      echo "Every answer verifies, and the liar's records that came back are numbered $seqs: a gap,"
      echo "so a record it sealed for one of these exchanges is missing from its log."
    fi
  fi
  echo "The asker checks the answers against its own $K halves (evidencebook ReconcileAsked):"
  k=0
  while read -r st; do
    k=$((k + 1))
    q=$(jq -r '.messages[0].content' "$RUN/request-$k.json" 2>/dev/null)
    case $st in
      OMITTED)
        if [ "${states[$((k - 1))]}" = refusal:no_such_subject ]; then how="now signs that it holds no record of it"
        else how="its signed answer carries no record of it"; fi
        echo "  RED: exchange $k (\"$q\", answer $(jq -r .answer <<< "$(sed -n "${k}p" "$RUN/ask-halves.jsonl")" | cut -c1-12)…): the asker holds its half; the liar served it, and $how" ;;
      LOGGED) echo "  exchange $k: in the liar's log" ;;
      REFUSED) echo "  exchange $k: refused, signed: ${states[$((k - 1))]#refusal:}. That does not say whether a record exists, but an honest node does not refuse its counterparty about their own exchange" ;;
      *) echo "  exchange $k: unresolved: $(jq -r ".results[$((k - 1))].why" "$RUN/reconcile.json")" ;;
    esac
  done < <(jq -r '.results[].state' "$RUN/reconcile.json")
  echo
  n=$(jq -r '.omitted | length' "$RUN/reconcile.json")
  nl=$(jq -r '[.results[] | select(.state == "LOGGED")] | length' "$RUN/reconcile.json")
  nu=$(jq -r '[.results[] | select(.state == "UNRESOLVED" or .state == "REFUSED")] | length' "$RUN/reconcile.json")
  case $verdict in
    OMISSIONS_FOUND)
      echo "RED: the liar served the asker $K exchanges; its signed answers hold $nl of them and confirm it"
      echo "holds no record of $n$([ "$nu" -gt 0 ] && echo " ($nu more refused or unresolved)")."
      echo "Sequence numbers catch deleting a sealed record. A record never sealed leaves no gap; it shows"
      echo "only in the counterparty's half, which is what named the $n above."
      exit 0 ;;
    NO_OMISSION_FOUND)
      echo "Each of the asker's $K exchanges has a verified record in the liar's log. That says none of"
      echo "these was left out, not that the log is complete."
      exit 0 ;;
    *)
      echo "No RED: the liar's answers do not say either way for some exchanges (a refusal, which reads the"
      echo "same whether the record exists, or an answer that did not verify or never came). Nothing here"
      echo "says its log is complete."
      exit 3 ;;
  esac
fi

# The fallback: every answer is the liar's signed refusal not_authorized (a host that announces no keys).
logged=$(grep -cx logged "$RUN/pairs.txt"); omitted=$(grep -cx omitted "$RUN/pairs.txt")
echo "This build cannot serve this request here. The liar refused all $K the same way, the $logged it"
echo "logged and the $omitted it left out, so the refusals say nothing about what it left out."
case $signed in
  no-host)
    echo "It serves a record only to a requester whose signature proves it is the other side of that"
    echo "exchange. The asker's requests went unsigned: it signs only once its host announces its key,"
    echo "and this host announces none (asker/logs/node.log: \"the host announces no plugin keys\")." ;;
  no-refused)
    echo "The asker's requests went unsigned: announcing its key to its host failed (asker/logs/node.log)." ;;
  yes)
    echo "The asker's requests were signed, and the liar still refused them (see $RUN/ask-*.answer.json)." ;;
  *)
    echo "The asker's log does not say whether its key was announced; see asker/logs/node.log." ;;
esac

# Box-local cross-check, as in step 7: the liar's own ledger, which no asker could open. Only the
# liar's records 07 paired with the asker's halves (by answer digest), and only when every one of
# them is still there with a number; otherwise no claim about gaps at all.
ok=0
if jq -c --slurpfile run "$RUN/liar-ledger.jsonl" --slurpfile own "$RUN/own.jsonl" \
     "(\$own | map(.answer)) as \$a | (\$run | map(select(.answer as \$x | \$a | index(\$x))) | map(.id)) as \$ids
      | select(.capsule_id as \$c | \$ids | index(\$c)) | {seq: $sp.seq, prev: $sp.prev_seq}" \
     "$S/liar/data/ledger/capsules.jsonl" > "$RUN/liar-seq.jsonl" 2>/dev/null \
   && [ "$(wc -l < "$RUN/liar-seq.jsonl")" -eq "$logged" ] \
   && jq -se 'all(.[]; .seq | type == "number")' "$RUN/liar-seq.jsonl" > /dev/null; then ok=1; fi
nums=$(jq -r '"\(.seq) (prev \(.prev // "none"))"' "$RUN/liar-seq.jsonl" 2>/dev/null | paste -sd, - | sed 's/,/, /g')
if [ "$ok" = 0 ]; then
  echo
  echo "On this box, the liar's own ledger does not hold exactly the $logged records 07 paired with the"
  echo "asker's halves, each with a number (or could not be read): no claim about gaps."
elif jq -se 'length > 0 and ([range(1; length) as $i | .[$i].seq == .[$i - 1].seq + 1 and .[$i].prev == .[$i - 1].seq] | all)' "$RUN/liar-seq.jsonl" >/dev/null; then
  echo
  echo "On this box we can also open the liar's own ledger. Its records of step 7 are numbered"
  echo "$nums: no gap."
  echo "Sequence numbers catch deleting a sealed record. A record never sealed leaves no gap; it"
  echo "shows only in the counterparty's half, which is what step 7 counted."
else
  echo
  echo "On this box, the liar's own ledger numbers its records of step 7: $nums."
fi
echo
echo "No RED from this step: it found nothing it could check. Step 7's count stands on its own."
exit 3
