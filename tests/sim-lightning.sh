#!/usr/bin/env bash
# sim-lightning.sh: one sticker sale paid over Lightning (`devcon8 trade --pay lexe`), both halves
# scripted in two throwaway HOMEs against a fake wallet API (tests/fake_wallet.py): no wallet is
# opened and no money moves. The buyer's `lightning pay` writes its terms leg; the seller's
# `lightning receive` writes what `deal note --kind payment_received --ln-invoice --ln-transaction`
# seals. Fails if a preimage or the invoice is kept anywhere, if a cap is not enforced, or if the
# buyer's Lightning pay check does not pause.
# Run inside the image: docker run --rm IMAGE /opt/devcon8/tests/sim-lightning.sh
set -euo pipefail
D=${D:-/opt/devcon8}
here=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d /tmp/sl-XXXXXX)
unset CAPSULE_PROFILE CAPSULECTL_PLUGIN_ROOTS CAPSULE_DEAL_CHECK_URL XDG_DATA_HOME
fail() { echo "FAIL $*" >&2; exit 1; }
deal() { capsulectl --profile deal deal "$@"; }
port=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 -I "$here/fake_wallet.py" "$port" "$T/wallet.log" & wpid=$!
trap 'kill $wpid 2>/dev/null || true' EXIT
export DEVCON8_WALLET_API=http://127.0.0.1:$port/api/wallet
for _ in $(seq 50); do curl -fsS -o /dev/null -d '{"command":"fund"}' "$DEVCON8_WALLET_API" 2>/dev/null && break; sleep 0.1; done
: > "$T/wallet.log"
STICKER=$D/agent/fixtures/sticker.png
DIGEST=$(sha256sum "$STICKER" | cut -d' ' -f1)
HASH=$(printf 'c5%.0s' $(seq 32))
PREIMAGE=$(printf '9e%.0s' $(seq 32))
PAYEE=02$(printf 'ab%.0s' $(seq 32))
CONV=conv-ln
home() { # name: a participant's HOME with its deal store
  export HOME=$T/$1; mkdir -p "$HOME/.devcon8"; cd "$HOME"
  capsulectl plugin install "$D/bin/capsulectl-deal" >/dev/null
  deal init --dir "$HOME/.local/share/capsule-deal" --materiality builtin:neutral --no-witness >/dev/null
}
caps() { jq -n --argjson p "$1" --argjson n "$2" --argjson t "$3" '{price_sats:$p,per_payment_sats:$n,total_sats:$t}' > "$HOME/.devcon8/lightning.json"; }

# Seller: an invoice at its price.
home seller; caps 500 500 500
"$D/agent/bin/lightning" invoice "$CONV" > invoice.out
grep -q lnbc invoice.out && fail "lightning invoice printed the invoice"
bolt11=$(jq -r .bolt11 "$T/seller/deals/$CONV/outgoing/invoice.json")

# Buyer: mbx saved the proposal's invoice; caps are checked before anything is sent.
home buyer; mkdir -p "deals/$CONV"; printf '%s\n' "$bolt11" > "deals/$CONV/invoice.txt"
caps 1 400 1000
if "$D/agent/bin/lightning" pay "$CONV" 50 "$DIGEST" 2>err.txt; then fail "paid over the per-payment cap"; fi
grep -q 'over your per-payment cap' err.txt || { cat err.txt; fail "no per-payment refusal"; }
grep -q '^send$' "$T/wallet.log" && fail "a send reached the wallet over the cap"
caps 1 600 1000
"$D/agent/bin/lightning" pay "$CONV" 50 "$DIGEST" > pay.out 2> pay.err
[ "$(jq -r .payment_hash pay.out)" = "$HASH" ] || { cat pay.out pay.err; fail "lightning pay did not pay"; }
terms=$HOME/deals/$CONV/outgoing/buyer-terms.json
[ "$(jq -r .settlement.amount.assetCode "$terms")" = "bip122:000000000019d6689c085ae165831e93/slip44:0" ] || fail "terms leg asset"
[ "$(jq -r .settlement.amount.value "$terms")" = 500000 ] || fail "terms leg amount"
if "$D/agent/bin/lightning" pay "$CONV" 50 "$DIGEST" 2>/dev/null; then fail "paid twice in one conversation"; fi

# The buyer's pay check on Lightning pauses: money sent this way cannot be pulled back.
ID=deal-00000000000051ff
SHOP=shop@agentboxnanda.org
t=$(jq -nc '{item:"digital fox sticker",quantity:1,price_minor:50,currency:"USD"}')
who=$(jq -nc --arg s "$SHOP" '{relay_address: $s, payee: $s}')
jq -n --argjson t "$t" --argjson who "$who" '{type: "purchase", channel: "agentboxnanda.org.agent_box",
  intent: {verbatim: "Buy me one digital fox sticker from shop@agentboxnanda.org, 50 cents at most, paid by Lightning from my own wallet. Ask me before anything else.",
           asked: {item: "digital fox sticker", quantity: 1}, max_total_minor: 50, allowed: ["pay"]},
  who: $who, terms: $t, recourse: {rail: "lightning", refundable: false}}' > open.json
deal open --deal-id "$ID" --records typed --input open.json >/dev/null
jq -n --argjson t "$t" --argjson who "$who" '{action: "pay", amount_minor: 50, authorized_max_minor: 50, terms: $t, who: $who,
  recourse: {rail: "lightning", refundable: false}}' > check-pay.json
deal check --deal "$ID" --input check-pay.json > pay.check.json
[ "$(jq -r .verdict pay.check.json)" = pause ] || { jq . pay.check.json; fail "a Lightning pay did not pause"; }
jq -e '[.differences[].rule] | index("irreversible_rail")' pay.check.json >/dev/null || fail "no irreversible_rail on the Lightning pay"
jq -r .approval_text pay.check.json > card.txt
deal note --deal "$ID" --kind approval --check "$(jq -r .check_id pay.check.json)" --choice proceed --said "yes, pay" --shown-card card.txt >/dev/null
jq -n --arg s "$SHOP" --arg h "$HASH" '{action:"pay",amount_minor:50,payee:$s,rail:"lightning",reference:$h}' > act.json
a=$(deal note --deal "$ID" --kind act --input act.json)
[ "$(jq -r .unchecked <<<"$a")" = false ] || { echo "$a"; fail "the Lightning pay act was recorded unchecked"; }

# Seller: the payment settled in its wallet; seal it, then the delivery.
export HOME=$T/seller; cd "$HOME"
"$D/agent/bin/lightning" receive "$CONV" "$HASH" > receive.out
[ "$(jq -r .received receive.out)" = true ] || { cat receive.out; fail "lightning receive"; }
CH=agentboxnanda.org.agent_box
jq -n --argjson t "$t" '{type: "purchase", intent: {verbatim: "Sell my digital fox sticker for 50 cents to any workshop participant who asks. Not under 50 cents.",
  party_role: "seller", min_total_minor: 50, asked: {item: "digital fox sticker", quantity: 1}, allowed: ["offer", "commit"]},
  terms: $t, recourse: {rail: "lightning", refundable: false}}' > sale.json
sale=$(deal sale new --input sale.json | jq -r .sale_id)
jq -n --arg ch "$CH" '{channel: $ch, who: {name: "Workshop buyer", relay_address: "buyer@agentboxnanda.org"}}' > open.json
sid=$(deal open --sale "$sale" --records typed --input open.json | jq -r .deal_id)
cp "$terms" buyer-terms.json
deal note --deal "$sid" --kind payment_received --terms buyer-terms.json \
  --ln-invoice "$(jq -r .ln_invoice receive.out)" --ln-transaction "$(jq -r .ln_transaction receive.out)" > paid.json
[ "$(jq -r .kind paid.json)" = evidence ] || { jq . paid.json; fail "payment_received did not seal"; }
deal note --deal "$sid" --kind delivered --terms buyer-terms.json --content "$STICKER" >/dev/null
s=$(deal settlement --deal "$sid" --leg buyer-terms.json)
[ "$(jq -r '.settlement.conforming' <<<"$s")" = true ] || { echo "$s"; fail "the legs do not conform"; }
[ "$(jq -r '.settlement.settlements[0].payment_state' <<<"$s")" = payee_stated ] || { echo "$s"; fail "payment state"; }

db=$T/seller/.local/share/capsule-deal/deal.db
grep -aq "$HASH" "$db" || fail "the sealed records do not name the payment hash"
# The receiving node id is kept on this device only (as x402's pay-to is): never in a shared copy.
capsulectl --profile deal disclose --deal "$sid" --share counterparty --to "Workshop buyer" --out shared.json >/dev/null
grep -aq "$HASH" shared.json || fail "the shared copy does not carry the payment hash it joins on"
grep -aq "$PAYEE" shared.json && fail "the receiving node id is in the shared copy"
# Neither the preimage nor the invoice is kept anywhere, except the invoice files that hold it.
if grep -rlaF "$PREIMAGE" "$T" --exclude=fake_wallet.py | grep -q .; then grep -rlaF "$PREIMAGE" "$T"; fail "a preimage was kept"; fi
if grep -rlaF "$bolt11" "$T" | grep -vE "/deals/$CONV/(invoice\.txt|outgoing/invoice\.json)$" | grep -q .; then
  grep -rlaF "$bolt11" "$T"; fail "the invoice was kept outside its own files"
fi
echo "ok   lightning: caps enforced, Lightning pay paused and checked, payment_received sealed by payment hash, no preimage or invoice kept"
