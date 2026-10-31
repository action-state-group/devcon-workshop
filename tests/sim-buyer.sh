#!/usr/bin/env bash
# sim-buyer.sh: the buyer's half of one sticker sale as the trader recipe runs it, in a throwaway HOME:
# open under the seller's deal id with the shop as payee, check the pay with that payee, act on the
# verdict, note the act with the same payee. Fails if the pay act is recorded unchecked.
# Run inside the image: docker run --rm IMAGE /opt/devcon8/tests/sim-buyer.sh
set -euo pipefail
D=${D:-/opt/devcon8}
T=$(mktemp -d /tmp/sb-XXXXXX); export HOME=$T; cd "$T"
unset CAPSULE_PROFILE CAPSULECTL_PLUGIN_ROOTS CAPSULE_DEAL_CHECK_URL XDG_DATA_HOME
fail() { echo "FAIL $*" >&2; exit 1; }
deal() { capsulectl --profile deal deal "$@"; }
capsulectl plugin install "$D/bin/capsulectl-deal" >/dev/null
deal init --dir "$T/.local/share/capsule-deal" --materiality builtin:neutral --no-witness >/dev/null

SHOP=shop@agentboxnanda.org
# The recipe pays the proposal's price_cents, at most 50: the full price and one below it.
for PRICE in 50 40; do
ID=deal-0000000000005${PRICE}f
terms=$(jq -nc --argjson p "$PRICE" '{item:"digital fox sticker",quantity:1,price_minor:$p,currency:"USD"}')
who=$(jq -nc --arg s "$SHOP" '{relay_address: $s, payee: $s}')
jq -n --argjson t "$terms" --argjson who "$who" '{type: "purchase", channel: "agentboxnanda.org.agent_box",
  intent: {verbatim: "Buy me one digital fox sticker from shop@agentboxnanda.org, 50 cents at most, paid by the simulated x402 payment. Ask me before anything else.",
           asked: {item: "digital fox sticker", quantity: 1}, max_total_minor: 50, allowed: ["pay"]},
  who: $who, terms: $t, recourse: {rail: "x402", refundable: false}}' > open.json
deal open --deal-id "$ID" --records typed --input open.json >/dev/null

jq -n --argjson p "$PRICE" --argjson t "$terms" --argjson who "$who" '{action: "pay", description: "one digital fox sticker",
  amount_minor: $p, authorized_max_minor: $p, terms: $t, who: $who, recourse: {rail: "x402", refundable: false}}' > check-pay.json
deal check --deal "$ID" --input check-pay.json > pay.check.json
case $(jq -r .verdict pay.check.json) in
  pass) ;;
  pause) jq -r .approval_text pay.check.json > card.txt
         r=$(deal note --deal "$ID" --kind approval --check "$(jq -r .check_id pay.check.json)" --choice proceed --said "yes, pay" --shown-card card.txt)
         [ "$(jq -r .proceed <<<"$r")" = true ] || fail "the approval did not proceed: $r" ;;
  *) jq . pay.check.json; fail "pay check: $(jq -r .verdict pay.check.json)" ;;
esac
jq -n --argjson p "$PRICE" --arg s "$SHOP" '{action: "pay", amount_minor: $p, payee: $s, rail: "x402", reference: "0x0000000000000000000000000000000000000000000000000000000000005111"}' > act.json
a=$(deal note --deal "$ID" --kind act --input act.json)
[ "$(jq -r .unchecked <<<"$a")" = false ] || { echo "$a"; jq . pay.check.json; fail "the pay act was recorded unchecked"; }
echo "ok   buyer: a $PRICE-cent pay checked with the shop as payee ($(jq -r .verdict pay.check.json)), act recorded checked"
done
