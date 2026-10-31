#!/usr/bin/env bash
# sim-payment.sh: the seller's half of one simulated sticker sale, scripted, in a throwaway HOME, up to
# the sealed payment_received and delivered legs (design section 9, step 8). Fails if a sealed record
# names a mainnet network, or if the fixtures do not seal at all.
# Run inside the image: docker run --rm IMAGE /opt/devcon8/tests/sim-payment.sh
set -euo pipefail
D=/opt/devcon8
T=$(mktemp -d /tmp/sp-XXXXXX); export HOME=$T; cd "$T"
unset CAPSULE_PROFILE CAPSULECTL_PLUGIN_ROOTS CAPSULE_DEAL_CHECK_URL XDG_DATA_HOME
fail() { echo "FAIL $*" >&2; exit 1; }
deal() { capsulectl --profile deal deal "$@"; }
capsulectl plugin install "$D/bin/capsulectl-deal" >/dev/null
deal init --dir "$T/.local/share/capsule-deal" --materiality builtin:neutral --no-witness >/dev/null

CH=agentboxnanda.org.agent_box
STICKER=$D/agent/fixtures/sticker.png
DIGEST=$(sha256sum "$STICKER" | cut -d' ' -f1)
terms=$(jq -nc '{item: "digital fox sticker", quantity: 1, price_minor: 50, currency: "USD"}')
jq -n --argjson t "$terms" '{type: "purchase", intent: {verbatim: "Sell my digital fox sticker for 50 cents to any workshop participant who asks. Not under 50 cents.",
  party_role: "seller", min_total_minor: 50, asked: {item: "digital fox sticker", quantity: 1}, allowed: ["offer", "commit"]},
  terms: $t, recourse: {rail: "x402", refundable: false}}' > sale.json
sale=$(deal sale new --input sale.json | jq -r .sale_id)
jq -n --arg ch "$CH" '{channel: $ch, who: {name: "Workshop buyer", profile_id: "urn:air:host39.org:personal:buyer@agentboxnanda.org",
  relay_address: "buyer@agentboxnanda.org"}}' > open.json
id=$(deal open --sale "$sale" --input open.json | jq -r .deal_id)
if [ -z "$id" ] || [ "$id" = null ]; then fail "no deal id"; fi

checked_act() { # action file
  jq -n --arg a "$1" --argjson t "$terms" '{action: $a, amount_minor: 50, terms: $t}' > "check-$1.json"
  deal check --deal "$id" --input "check-$1.json" > "$1.check.json"
  case $(jq -r .verdict "$1.check.json") in
    deny) jq . "$1.check.json"; fail "$1 denied" ;;
    pause) jq -r .card "$1.check.json" > "$1.card.txt"
           deal note --deal "$id" --kind approval --check "$(jq -r .check_id "$1.check.json")" --choice proceed \
             --said "yes" --shown-card "$1.card.txt" >/dev/null ;;
  esac
  jq -n --arg a "$1" '{action: $a, amount_minor: 50, currency: "USD"}' > "act-$1.json"
  deal note --deal "$id" --kind act --input "act-$1.json" >/dev/null
}
checked_act offer
deal note --deal "$id" --kind acceptance --check "$(jq -r .check_id offer.check.json)" --words "Accepted, paid." --channel "$CH" >/dev/null
checked_act commit

# The buyer's side, as the agent runs it: pay-x402 writes the two files its accept attaches.
pay-x402 conv-test 50 "$DIGEST" >/dev/null
out=$T/deals/conv-test/outgoing
[ "$(jq -r .settlement.amount.value "$out/buyer-terms.json")" = 500000 ] || fail "pay-x402 wrote the wrong amount"
if pay-x402 conv-test 50 "$DIGEST" 2>/dev/null; then fail "pay-x402 paid twice in one conversation"; fi
if pay-x402 conv-2 050 "$DIGEST" 2>/dev/null; then fail "pay-x402 took a leading zero"; fi
cp "$out/buyer-terms.json" buyer-terms.json
deal note --deal "$id" --kind payment_received --terms buyer-terms.json --settle-response "$out/settle.json" \
  --requirements "$D/agent/fixtures/x402/requirements.json" > paid.json
jq -r .say paid.json | grep -q 'Payment received: 0.50 USDC' || { jq . paid.json; fail "payment_received did not seal"; }
deal note --deal "$id" --kind delivered --terms buyer-terms.json --content "$STICKER" > delivered.json
[ "$(jq -r .kind delivered.json)" = evidence ] || { jq . delivered.json; fail "delivered did not seal"; }

# The settlement legs live in the deal store (the export carries step bodies, not the legs).
db=$T/.local/share/capsule-deal/deal.db
grep -aq 'eip155:84532' "$db" || fail "the sealed records do not name the test network"
if grep -aEq 'eip155:8453([^0-9]|$)' "$db"; then fail "a sealed record names Base mainnet (eip155:8453)"; fi
echo "ok   simulated payment sealed on eip155:84532, no mainnet named"
