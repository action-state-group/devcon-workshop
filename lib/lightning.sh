#!/usr/bin/env bash
# lightning.sh: your caps for a `devcon8 trade --pay lexe` run, where the sticker is paid for with
# REAL Lightning from your own lexe wallet (mainnet). The agent's `lightning` tool reads them and
# refuses any payment over them; it has no option to change them (goose shows you every command).
#   devcon8 lightning                                   show your caps and what has been paid
#   devcon8 lightning --price-sats P --per-payment-sats N --total-sats T
#       P: what your agent asks for your sticker; N: the most one payment of yours may cost,
#       routing fee included; T: the most all of this container's Lightning payments may cost.
set -euo pipefail
. /opt/devcon8/lib/common.sh
f=$ST/lightning.json
[ $# = 0 ] && { [ -s "$f" ] || die "no caps yet: devcon8 lightning --price-sats P --per-payment-sats N --total-sats T"; exec "$D/agent/bin/lightning" caps; }
price="" per="" total=""
while [ $# -gt 0 ]; do
  case $1 in
    --price-sats) price=${2:-}; shift 2 ;;
    --per-payment-sats) per=${2:-}; shift 2 ;;
    --total-sats) total=${2:-}; shift 2 ;;
    *) die "devcon8 lightning [--price-sats P --per-payment-sats N --total-sats T]" ;;
  esac
done
for v in "$price" "$per" "$total"; do
  [[ $v =~ ^[1-9][0-9]{0,7}$ ]] || die "each of --price-sats, --per-payment-sats and --total-sats is a whole number of sats, 1 or more"
done
[ "$per" -le "$total" ] || die "--per-payment-sats is over --total-sats"
(umask 077; jq -n --argjson p "$price" --argjson n "$per" --argjson t "$total" \
  '{price_sats: $p, per_payment_sats: $n, total_sats: $t}' > "$f.tmp" && mv "$f.tmp" "$f")
echo "caps saved in $f: price $price sats, at most $per sats a payment, $total sats in all."
echo "These are real sats on bitcoin mainnet. 'devcon8 trade --pay lexe' uses them."
