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
deal=$(dispute sale) || fail "dispute sale"
ok "the price-changed sale is $deal"

[ "$(dispute show "$deal" --store "$S/buyer")" = "Nothing is ruled on $deal yet." ] || fail "a deal with no ruling says it has one"
if referee rule "$deal" --buyer "$S/buyer" --seller "$S/seller" 2>/dev/null; then fail "the referee ruled with no dispute"; fi
d=$(dispute "$deal" --store "$S/buyer" --words "the sticker was the wrong one") || fail "dispute"
[ "$(jq -r .dispute_digest <<<"$d")" != "" ] || fail "dispute printed no digest"
ok "the buyer's dispute is sealed; nothing is ruled yet"

# A mistyped store fails before anything is sealed and leaves nothing behind, so the corrected command runs.
if referee rule "$deal" --buyer "$S/buyer" --seller "$work/nowhere" 2>/dev/null; then fail "the referee ruled with a store that does not exist"; fi
[ ! -e "$HOME/studio/rulings/$deal" ] || fail "a failed run left its folder, so the corrected command would be refused"
ok "a failed run leaves nothing behind"
r=$(referee rule "$deal" --buyer "$S/buyer" --seller "$S/seller") || fail "referee rule"
[ "$(jq -r .finding <<<"$r")" = for_buyer ] || fail "the price changed after acceptance, so the ruling is for the buyer: $r"
digest=$(jq -r .ruling_digest <<<"$r")
b=$(dispute show "$deal" --store "$S/buyer"); s=$(dispute show "$deal" --store "$S/seller")
[ "$b" = "$s" ] || fail "the two parties' agents would say different things: $b | $s"
[[ $b == "The referee ruled on the dispute over \"price as offered\": found for the buyer. Ruling ${digest:0:12}." ]] || fail "unexpected sentence: $b"
ok "both stores say: $b"
# An agent in the live profile is not told where the replayed sale is: the command finds it.
[ "$(dispute show "$deal")" = "$b" ] || fail "dispute show with no --store does not find the replayed sale: $(dispute show "$deal" 2>&1)"
ok "no --store needed: the same sentence"
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

# The other way: a sale whose two closes agree is ruled for the seller, in both stores.
other=$(XDG_CONFIG_HOME=$S/buyer capsulectl --profile deal deal list --json | jq -r --arg d "$deal" '[.[] | select(.kind == "deal" and .deal_id != $d) | .deal_id][0]')
[ -n "$other" ] || fail "no second sale in the replay"
dispute "$other" --words "I think the price was wrong" >/dev/null || fail "dispute ($other) with no --store"
r=$(referee rule "$other" --buyer "$S/buyer" --seller "$S/seller") || fail "referee rule ($other)"
[ "$(jq -r .finding <<<"$r")" = for_seller ] || fail "the closes agree, so the ruling is for the seller: $r"
b=$(dispute show "$other" --store "$S/buyer"); s=$(dispute show "$other" --store "$S/seller")
[ "$b" = "$s" ] || fail "the two stores differ: $b | $s"
[[ $b == *"found for the seller."* ]] || fail "both stores should say found for the seller: $b | $s"
ok "agreeing closes: $b"

# The referee rules on the price row only.
third=$(XDG_CONFIG_HOME=$S/buyer capsulectl --profile deal deal list --json | jq -r --arg a "$deal" --arg b "$other" '[.[] | select(.kind == "deal" and .deal_id != $a and .deal_id != $b) | .deal_id][0]')
dispute "$third" --row delivery_time --words "it came late" >/dev/null || fail "dispute ($third)"
if referee rule "$third" --buyer "$S/buyer" --seller "$S/seller" 2>/dev/null; then fail "the referee ruled on a row other than the price"; fi
ok "a dispute over another row is not ruled on"
