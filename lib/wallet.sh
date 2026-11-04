#!/usr/bin/env bash
# wallet.sh: your own lexe wallet (real Lightning, bitcoin mainnet), used by `devcon8 trade --pay lexe`.
# It runs Lexe's own lexe-sidecar on this container; there is no mesh-llm node in it. The wallet's
# root seed is the file ~/.devcon8/lexe/root_seed on your volume: anyone who has it can spend the
# wallet, and removing the volume loses it. This command never prints it, except `devcon8 wallet key`.
#   devcon8 wallet                  open the wallet (first time: asks, then creates it) and show its balance
#   devcon8 wallet fund --sats N    a mainnet invoice for N sats, to pay from another wallet
#   devcon8 wallet key              show the root seed, to back it up
#   devcon8 wallet stop             stop the wallet process
#   devcon8 wallet node             the mesh-llm node's own wallet (for paid mesh inference; needs devcon8 join)
set -euo pipefail
. /opt/devcon8/lib/common.sh

reminder() {
  cat <<TXT

Back up your wallet's key before you put sats in it. It is one file on your volume:
  $LEXE/root_seed        ('devcon8 wallet key' shows it)
Removing the volume, 'docker volume rm', a prune or "Start completely over" loses the wallet and every
sat in it. Empty the wallet first, or keep the key somewhere safe: it restores the wallet in Lexe's app or CLI.
TXT
}

consent() {
  [ -t 0 ] || die "opening your wallet asks you a question: run 'devcon8 wallet' in a terminal"
  cat <<'TXT'
This opens your own Lexe wallet (real Lightning, bitcoin mainnet).
  - It registers an anonymous account with Lexe, which hosts your wallet's Lightning node (in an Intel SGX
    enclave, so Lexe cannot spend your sats). Lexe's privacy policy: https://lexe.app/privacy-policy
  - Its key is made on this volume, in the file below, and never leaves it.
TXT
  reminder
  local a; read -r -p "Open the wallet and register it with Lexe? (yes/no) " a
  [ "$a" = yes ] || die "not opened (you answered '$a')"
}

open_wallet() {
  if lexe_ready; then lexe_up; return; fi
  consent
  mkdir -p "$LEXE"; chmod 700 "$LEXE"
  lexe_lock
  # Another terminal may have finished opening it while this one was asked.
  if lexe_ready; then lexe_unlock; lexe_up; return; fi
  [ -s "$LEXE/root_seed" ] || (umask 077; openssl rand -hex 32 > "$LEXE/root_seed.tmp" && mv "$LEXE/root_seed.tmp" "$LEXE/root_seed")
  lexe_up
  lexe_call PUT /v2/node/signup '{}' >/dev/null || die "Lexe sign-up failed; see $LEXE/sidecar.log, then run 'devcon8 wallet' again"
  touch "$LEXE/signed_up"
  lexe_call PUT /v2/node/provision >/dev/null || die "the lexe wallet could not be provisioned; see $LEXE/sidecar.log, then run 'devcon8 wallet' again"
  echo "wallet registered with Lexe"
  lexe_unlock
}

balance() {
  lexe_call GET /v2/node/node_info | jq '{balance_sats: .balance, lightning_sendable_sats: .lightning_sendable_balance, usable_channels: .num_usable_channels}'
}

case ${1:-open} in
  open) open_wallet; balance
    echo
    echo "Fund it with 'devcon8 wallet fund --sats N'. 'devcon8 trade --pay lexe' still stops for your answer before every payment."
    ;;
  fund)
    [[ ${2:-} == --sats && ${3:-} =~ ^[1-9][0-9]{0,9}$ ]] || die "devcon8 wallet fund --sats N"
    open_wallet
    reminder
    echo
    echo "A mainnet invoice for $3 sats; pay it from another wallet (it expires in a day):"
    lexe_call POST /v2/node/create_invoice "$(jq -n --arg a "$3" '{amount: $a, expiration_secs: 86400, description: "devcon8 wallet funding"}')" | jq -r .invoice
    ;;
  key) [ -s "$LEXE/root_seed" ] || die "no wallet on this volume"; echo "Your wallet's root seed (keep it secret; it spends the wallet):"; cat "$LEXE/root_seed" ;;
  stop) lexe_stop; echo "wallet stopped" ;;
  node)
    shift || true
    node_pid >/dev/null || die "your node is not running: 'devcon8 join' first"
    "$MESH" wallet get-balance
    cat <<'TXT'

This is the mesh-llm node's own wallet, for paid mesh inference. Your node stays free-only until you change its policy:
  mesh-llm wallet fund-wallet --amount-sats N                        a mainnet invoice to pay from another wallet
  mesh-llm wallet policy --mode automatic --daily-budget-sats N      pay automatically, at most N sats a day
  mesh-llm wallet policy --mode free-only                            back to free-only
TXT
    ;;
  *) die "devcon8 wallet [fund --sats N | key | stop | node]" ;;
esac
