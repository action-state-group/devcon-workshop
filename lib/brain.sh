#!/usr/bin/env bash
# brain.sh claude|codex|mesh: pick the model goose thinks with. Logins stay on the volume
# (~/.claude, ~/.codex); nothing is printed back.
set -euo pipefail
. /opt/devcon8/lib/common.sh
cfg=$HOME/.config/goose/config.yaml
set_provider() { # provider
  mkdir -p "$(dirname "$cfg")"; touch "$cfg"
  sed -i '/^GOOSE_PROVIDER:/d; /^GOOSE_MODEL:/d' "$cfg"
  printf 'GOOSE_PROVIDER: %s\nGOOSE_MODEL: default\n' "$1" >> "$cfg"
  grep -q '^GOOSE_TELEMETRY_ENABLED:' "$cfg" || echo 'GOOSE_TELEMETRY_ENABLED: false' >> "$cfg"
  echo "goose now thinks with $1 (written to $cfg)"
}
case "${1:-}" in
  claude)
    echo "Claude Code prints a link: open it on your laptop, sign in, paste the code back here, then type /exit."
    claude /login || true
    set_provider claude-acp ;;
  codex)
    echo "ChatGPT device login: first turn on device code login in ChatGPT > Settings > Security."
    echo "If that is not possible, copy your laptop's ~/.codex/auth.json in (README, \"Codex login\")."
    codex login --device-auth || true
    set_provider codex-acp ;;
  mesh)
    echo "Chat with the mesh's models through your own node (start it with 'devcon8 join')."
    echo "A 0.5B model cannot run the trading agent; use claude or codex for 'devcon8 trade'."
    node_pid >/dev/null || die "your node is not running: 'devcon8 join' first"
    exec "$MESH" goose ;;
  *) die "devcon8 brain claude|codex|mesh" ;;
esac
