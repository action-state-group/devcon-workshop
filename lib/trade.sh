#!/usr/bin/env bash
# trade.sh [--buy <address>] [--pay lexe]: run your trading agent in goose. It sells your fox sticker
# to any participant's agent that asks and, with --buy, buys one from that address. Payment is
# simulated; with --pay lexe it is REAL Lightning from your own lexe wallet, within the caps you set
# with 'devcon8 lightning'. goose runs in auto mode (the deal plugin's own
# PAUSED FOR YOU cards still gate offers, commitments and payments, the real Lightning pay included).
# DEVCON8_GOOSE_MODE overrides.
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
# A --pay lexe seller seals what its wallet received with `deal note --ln-invoice`; a deal plugin
# without it could take real money and record none, so the run refuses instead.
if [ "$pay" = lexe ] && ! capsulectl deal note --help 2>/dev/null | grep -q -- '--ln-invoice'; then
  die "--pay lexe needs a capsulectl-deal that records Lightning payments (v0.1.0-rc29 or later); this image's cannot"
fi
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
  echo "Every payment stops for your answer in the chat first."
else
  echo "Payment in this run is SIMULATED: no money moves. Offers, commitments and payments still stop for your answer in the chat."
fi
mode=${DEVCON8_GOOSE_MODE:-auto}
echo "Ctrl-C interrupts a turn; press it again and the run ends."
args=(run --recipe "$D/agent/recipes/trader.yaml" --interactive --params "pay=$pay")
[ -n "$buy" ] && args+=(--params "buy_from=$buy")
# goose is a child, not exec'd: after "session closed" it can stay alive waiting on claude-agent-acp,
# which waits on a tool call still running (an `mbx wait`), and a bare Ctrl-C then does nothing (seen
# on v4). The first Ctrl-C is goose's own (it interrupts the turn); a second one that reaches this
# script, which happens only when goose is not reading keys, ends goose and everything under it.
# shellcheck disable=SC2317,SC2329 # tree is called from the INT/TERM traps
tree() { local p; for p in $(pgrep -P "$1" 2>/dev/null); do tree "$p"; done; echo "$1"; }
# shellcheck disable=SC2034 # last is read in the INT trap
ints=0 last=0 forced=
# A background job ignores SIGINT; the subshell restores it so goose and its children see Ctrl-C as before.
(trap - INT QUIT; exec env GOOSE_MODE="$mode" goose "${args[@]}") <&0 &
gp=$!
trap 'if [ $((SECONDS-last)) -gt 10 ]; then ints=0; fi; last=$SECONDS; ints=$((ints+1)); [ $ints -lt 2 ] || { forced=1; kill -KILL $(tree $gp) 2>/dev/null; }' INT
trap 'forced=1; kill -KILL $(tree $gp) 2>/dev/null' TERM HUP
rc=0
wait $gp && rc=0 || rc=$?
while [ $rc -gt 128 ] && kill -0 $gp 2>/dev/null; do wait $gp && rc=0 || rc=$?; done
trap - INT TERM HUP
if [ -t 0 ]; then stty sane 2>/dev/null || true; fi
[ -z "$forced" ] || rc=130
exit $rc
