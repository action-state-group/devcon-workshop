#!/usr/bin/env bash
# trade.sh [--buy <address>]: run your trading agent in goose. It sells your fox sticker to any
# participant's agent that asks and, with --buy, buys one from that address. Payment is simulated.
# goose runs in approve mode: it asks you before each tool call.
set -euo pipefail
. /opt/devcon8/lib/common.sh
buy=""
case "${1:-}" in
  --buy) buy=$(tr '[:upper:]' '[:lower:]' <<<"${2:-}"); [[ $buy =~ ^[a-z0-9._-]+@agentboxnanda\.org$ ]] || die "--buy <their address>@agentboxnanda.org" ;;
  "") ;;
  *) die "devcon8 trade [--buy <address>@agentboxnanda.org]" ;;
esac
[ -s "$ST/agentbox/key" ] || die "no mailbox yet: run 'devcon8 nanda <your email>' first"
grep -qE '^GOOSE_PROVIDER: (claude|codex)-acp' "$HOME/.config/goose/config.yaml" 2>/dev/null \
  || die "pick a brain first: 'devcon8 brain claude' or 'devcon8 brain codex'"
if [ "$buy" = "$(jq -r .address "$ST/agentbox/mailbox.json")" ]; then
  die "that is your own address: to buy from yourself, run a second agent with a second email (README)"
fi
if ! capsulectl --profile deal deal list >/dev/null 2>&1; then
  capsulectl plugin install "$D/bin/capsulectl-deal" >/dev/null
  capsulectl --profile deal deal init --dir "$HOME/.local/share/capsule-deal" --materiality builtin:neutral --no-witness >/dev/null
  echo "deal store ready: $HOME/.local/share/capsule-deal"
fi
mkdir -p "$HOME/deals"
cd "$HOME"
echo "Payment in this run is SIMULATED: no money moves. goose asks before each tool call; answer in the chat."
args=(run --recipe "$D/agent/recipes/trader.yaml" --interactive)
[ -n "$buy" ] && args+=(--params "buy_from=$buy")
GOOSE_MODE=approve exec goose "${args[@]}"
