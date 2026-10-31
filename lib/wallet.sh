#!/usr/bin/env bash
# wallet.sh: your own lexe wallet, through your running node (optional; real Lightning, mainnet).
# The image ships no wallet. The plugin makes one on first use, inside ~/.mesh-llm/payments on your
# volume; its secrets never leave that folder and this command never prints them.
set -euo pipefail
. /opt/devcon8/lib/common.sh
node_pid >/dev/null || die "your node is not running: 'devcon8 join' first"
"$MESH" wallet get-balance
cat <<'TXT'

Your node stays free-only until you change its policy. To pay for mesh inference:
  mesh-llm wallet fund-wallet --amount-sats N                        a mainnet invoice to pay from another wallet
  mesh-llm wallet policy --mode automatic --daily-budget-sats N      pay automatically, at most N sats a day
  mesh-llm wallet policy --mode free-only                            back to free-only
With a funded wallet, run agents with GOOSE_MODE=approve so each tool call asks you first.
TXT
