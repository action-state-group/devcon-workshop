#!/usr/bin/env bash
# lightning.sh: your caps for a `devcon8 trade --pay lexe` run, where the sticker is paid for with
# REAL Lightning from your own lexe wallet (mainnet). The agent's `lightning` tool reads them and
# refuses any payment over them; it has no option to change them (goose shows you every command).
#   devcon8 lightning                                   show your caps and what has been paid
#   devcon8 lightning --price-sats P --per-payment-sats N --total-sats T
#       P: what your agent asks for your sticker; N: the most one payment of yours may cost,
#       routing fee included; T: the most all of the sticker payments may cost.
#       Each also takes msat instead (--price-msat, --per-payment-msat, --total-msat).
set -euo pipefail
. /opt/devcon8/lib/common.sh
f=$ST/lightning.json
[ $# = 0 ] && { [ -s "$f" ] || die "no caps yet: devcon8 lightning --price-sats P --per-payment-sats N --total-sats T"; exec "$D/agent/bin/lightning" caps; }
price="" per="" total=""
msat() { # value unit: the amount in msat
  [[ $1 =~ ^[1-9][0-9]{0,11}$ ]] || die "each cap is a whole number, 1 or more"
  if [ "$2" = sats ]; then echo $(( $1 * 1000 )); else echo "$1"; fi
}
while [ $# -gt 0 ]; do
  case $1 in
    --price-sats|--price-msat) price=$(msat "${2:-}" "${1##*-}"); shift 2 ;;
    --per-payment-sats|--per-payment-msat) per=$(msat "${2:-}" "${1##*-}"); shift 2 ;;
    --total-sats|--total-msat) total=$(msat "${2:-}" "${1##*-}"); shift 2 ;;
    *) die "devcon8 lightning [--price-sats P --per-payment-sats N --total-sats T] (or --*-msat)" ;;
  esac
done
if [ -z "$price" ] || [ -z "$per" ] || [ -z "$total" ]; then
  die "give all three: a price, a per-payment cap and a total cap"
fi
[ "$per" -le "$total" ] || die "the per-payment cap is over the total cap"
(umask 077; jq -n --argjson p "$price" --argjson n "$per" --argjson t "$total" \
  '{price_msat: $p, per_payment_msat: $n, total_msat: $t}' > "$f.tmp" && mv "$f.tmp" "$f")
echo "caps saved in $f (msat): price $price, at most $per a payment, $total in all."
echo "These are real sats on bitcoin mainnet (1 sat = 1,000 msat). 'devcon8 trade --pay lexe' uses them."
