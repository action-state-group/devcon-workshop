#!/usr/bin/env bash
# studio-ruling.sh: demo step 6 without a model, in the Studio layer: the replay's price-changed sale is
# disputed by the buyer, the fixed referee rules once into both stores, and both stores show the same ruling
# (the sentence, the receipt line, the ruling digest) and a card that counts it (seller 1 received, buyer 1
# raised). Scripted evidence only; the by-hand run is a person typing the same commands. Cards wait for a
# checkpoint (about five minutes each).
# Run inside the layer: docker run --rm IMAGE /opt/devcon8/tests/studio-ruling.sh
set -euo pipefail
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }
work=$(mktemp -d)
export HOME=$work/home XDG_CONFIG_HOME=$work/config
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
S=$HOME/studio/replay

devcon8-studio replay >/dev/null || fail "replay failed"
# The price-changed sale is the one whose seller half holds a detail_change (replay README, "Trade 7").
deal=
for d in $(XDG_CONFIG_HOME=$S/seller capsulectl --profile deal deal list --json | jq -r '.[] | select(.kind == "deal") | .deal_id'); do
  XDG_CONFIG_HOME=$S/seller capsulectl --profile deal deal export --deal "$d" --output "$work/x-$d.json" >/dev/null
  if jq -e 'any(.[]; .["x-deal-v0"].record_type? == "detail_change")' "$work/x-$d.json" >/dev/null; then deal=$d; break; fi
done
[ -n "$deal" ] || fail "no sale with a price change in the replay"
ok "the price-changed sale is $deal"

[ "$(dispute show "$deal" --store "$S/buyer")" = "Nothing is ruled on $deal yet." ] || fail "a deal with no ruling says it has one"
if referee rule "$deal" --buyer "$S/buyer" --seller "$S/seller" 2>/dev/null; then fail "the referee ruled with no dispute"; fi
d=$(dispute "$deal" --store "$S/buyer" --words "the sticker was the wrong one") || fail "dispute"
[ "$(jq -r .dispute_digest <<<"$d")" != "" ] || fail "dispute printed no digest"
ok "the buyer's dispute is sealed; nothing is ruled yet"

r=$(referee rule "$deal" --buyer "$S/buyer" --seller "$S/seller") || fail "referee rule"
[ "$(jq -r .finding <<<"$r")" = for_buyer ] || fail "the price changed after acceptance, so the ruling is for the buyer: $r"
digest=$(jq -r .ruling_digest <<<"$r")
b=$(dispute show "$deal" --store "$S/buyer"); s=$(dispute show "$deal" --store "$S/seller")
[ "$b" = "$s" ] || fail "the two parties' agents would say different things: $b | $s"
[[ $b == "The referee ruled on the dispute over \"price as offered\": found for the buyer. Ruling ${digest:0:12}." ]] || fail "unexpected sentence: $b"
ok "both stores say: $b"
if referee rule "$deal" --buyer "$S/buyer" --seller "$S/seller" 2>/dev/null; then fail "a second ruling was sealed"; fi
ok "a second ruling is refused"

for who in buyer seller; do
  c=$(XDG_CONFIG_HOME=$S/$who card make --fresh "$who" 2>"$work/$who.err") || { cat "$work/$who.err" >&2; fail "card make ($who)"; }
  python3 -I - "$(jq -r .bundle <<<"$c")" "$who" <<'PY' || fail "the $who's card does not count the ruling"
import json, sys
b = json.load(open(sys.argv[1])); d = b["disclosures"][b["root"]]["agent_input"]["disputes"]
raised, received = d["raised"]["of"], d["received"]["of"]
want = (1, 0) if sys.argv[2] == "buyer" else (0, 1)
sys.exit(0 if (raised, received) == want else 1)
PY
done
ok "the buyer's card counts 1 raised and the seller's 1 received"
