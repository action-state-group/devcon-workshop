#!/usr/bin/env bash
# trade.sh [--buy <address>] [--pay lexe]: run your trading agent in goose. It sells your fox sticker
# to any participant's agent that asks and, with --buy, buys one from that address. Payment is
# simulated; with --pay lexe it is REAL Lightning from your own lexe wallet, within the caps you set
# with 'devcon8 lightning'. goose runs in approve mode: it asks you before each tool call.
set -euo pipefail
. /opt/devcon8/lib/common.sh
buy="" pay=simulated
while [ $# -gt 0 ]; do
  case $1 in
    --buy) buy=$(tr '[:upper:]' '[:lower:]' <<<"${2:-}"); [[ $buy =~ ^[a-z0-9._-]+@agentboxnanda\.org$ ]] || die "--buy <their address>@agentboxnanda.org"; shift 2 ;;
    --pay) [ "${2:-}" = lexe ] || die "--pay lexe (the only other way to pay is the default, simulated)"; pay=lexe; shift 2 ;;
    *) die "devcon8 trade [--buy <address>@agentboxnanda.org] [--pay lexe]" ;;
  esac
done
if [ "$pay" = lexe ]; then
  [ -s "$ST/lightning.json" ] || die "--pay lexe needs your caps first: devcon8 lightning --price-sats P --per-payment-sats N --total-sats T"
  node_pid >/dev/null || die "--pay lexe pays from your node's wallet: 'devcon8 join' first, then 'devcon8 wallet'"
fi
[ -s "$ST/agentbox/key" ] || die "no mailbox yet: run 'devcon8 nanda <your email>' first"
grep -qE '^GOOSE_PROVIDER: (claude|codex)-acp' "$HOME/.config/goose/config.yaml" 2>/dev/null \
  || die "pick a brain first: 'devcon8 brain claude' or 'devcon8 brain codex'"
if [ "$buy" = "$(jq -r .address "$ST/agentbox/mailbox.json")" ]; then
  die "that is your own address: to buy from yourself, run a second agent with a second email (README)"
fi
# The deal and book plugins are installed into the volume, so they are replaced on every run: after
# an image upgrade the volume must not keep an older plugin beside the new capsulectl (install replaces it).
capsulectl plugin install "$D/bin/capsulectl-deal" >/dev/null
capsulectl plugin install "$D/bin/capsulectl-book" >/dev/null
# The store is made once. With the plugin just installed, a failing 'deal list' means the deal
# profile is missing (or its store is gone); deal init refuses a profile that already exists.
if ! capsulectl --profile deal deal list >/dev/null 2>&1; then
  capsulectl --profile deal deal init --dir "$HOME/.local/share/capsule-deal" --materiality builtin:neutral --no-witness >/dev/null \
    || die "the deal profile exists but its store does not answer; move ~/.local/share/capsule-deal and the 'deal' profile aside (capsulectl profile --help), then run devcon8 trade again"
  echo "deal store ready: $HOME/.local/share/capsule-deal"
fi
mkdir -p "$HOME/deals"
cd "$HOME"
if [ "$pay" = lexe ]; then
  echo "Payment in this run is REAL Lightning from your own lexe wallet (bitcoin mainnet), within your caps:"
  "$D/agent/bin/lightning" caps
  echo "goose asks before each tool call, and every payment shows you a card first; answer in the chat."
else
  echo "Payment in this run is SIMULATED: no money moves. goose asks before each tool call; answer in the chat."
fi
args=(run --recipe "$D/agent/recipes/trader.yaml" --interactive --params "pay=$pay")
[ -n "$buy" ] && args+=(--params "buy_from=$buy")
GOOSE_MODE=approve exec goose "${args[@]}"
