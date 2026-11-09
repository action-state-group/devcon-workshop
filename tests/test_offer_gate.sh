#!/usr/bin/env bash
# test_offer_gate.sh: pay-x402 refuses to pay while the shop's proposal does not match the offer the user picked
# (mbx writes ~/deals/<conversation>/offer-check.json; lightning pay reads it too, tests/test_lightning.py).
# capsulectl is a stand-in that writes the terms leg, so the gate is the only thing under test.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home/deals/c1" "$T/home/deals/c2"
# shellcheck disable=SC2016 # the stand-in script is meant to be literal
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = --out ] && echo "{}" > "$2"; shift; done\n' > "$T/bin/capsulectl"; chmod +x "$T/bin/capsulectl"
mkdir -p "$T/opt/agent/fixtures/x402"; : > "$T/opt/agent/fixtures/x402/settle.json"
# pay-x402 copies the fixture from /opt/devcon8; run a copy that looks in this scratch tree instead.
sed "s#/opt/devcon8#$T/opt#" "$here/../agent/bin/pay-x402" > "$T/pay-x402"; chmod +x "$T/pay-x402"
D=$(printf 'ab%.0s' $(seq 32))
pay() { HOME=$T/home PATH=$T/bin:$PATH "$T/pay-x402" "$@" 2>&1; }
echo '{"item":"claimed","price":"mismatch","rail":"verified"}' > "$T/home/deals/c1/offer-check.json"
out=$(pay c1 50 "$D") && { echo "FAIL paid against a mismatch"; exit 1; }
grep -q 'price' <<<"$out" || { echo "FAIL no reason: $out"; exit 1; }
[ ! -e "$T/home/deals/c1/outgoing" ] || { echo "FAIL a refused payment left files"; exit 1; }
echo "ok   pay-x402 refuses while a field is a mismatch, and writes nothing"
echo 'not json' > "$T/home/deals/c1/offer-check.json"
pay c1 50 "$D" >/dev/null && { echo "FAIL paid with a damaged check"; exit 1; }
echo "ok   pay-x402 refuses on a damaged check"
pay c1 50 "$D" >/dev/null 2>&1 && { echo "FAIL paid with a damaged check"; exit 1; }
: > "$T/home/deals/c1/offer-check.json"
pay c1 50 "$D" >/dev/null && { echo "FAIL paid with an empty check"; exit 1; }
echo "ok   pay-x402 refuses on an empty check"
echo '{"item":"claimed","price":"verified","rail":"verified","history":"claimed","amount":50,"unit":"usd_cent"}' > "$T/home/deals/c1/offer-check.json"
out=$(pay c1 50 "$D") && { echo "FAIL paid with the card not opened"; exit 1; }
grep -q 'card' <<<"$out" || { echo "FAIL no card reason: $out"; exit 1; }
echo "ok   pay-x402 refuses while the announced card is not opened"
echo '{"item":"claimed","price":"verified","rail":"verified","amount":50,"unit":"usd_cent"}' > "$T/home/deals/c1/offer-check.json"
out=$(pay c1 5000 "$D") && { echo "FAIL paid another amount"; exit 1; }
grep -q '50 cents' <<<"$out" || { echo "FAIL no amount reason: $out"; exit 1; }
echo '{"item":"claimed","price":"verified","rail":"verified","amount":400,"unit":"msat"}' > "$T/home/deals/c1/offer-check.json"
pay c1 400 "$D" >/dev/null && { echo "FAIL paid x402 for a Lightning price"; exit 1; }
echo "ok   pay-x402 refuses any amount or rail but the one asked"
echo '{"item":"claimed","price":"verified","rail":"verified","history":"verified","amount":50,"unit":"usd_cent"}' > "$T/home/deals/c2/offer-check.json"
pay c2 50 "$D" >/dev/null || { echo "FAIL refused a proposal that matches"; exit 1; }
[ -s "$T/home/deals/c2/outgoing/buyer-terms.json" ] || { echo "FAIL no terms leg after a match"; exit 1; }
echo "ok   pay-x402 pays when nothing mismatches"
