# shellcheck shell=bash
# common.sh: helpers every devcon8 step shares. Sourced, never run.
D=${D:-/opt/devcon8}
ST=${ST:-$HOME/.devcon8}
MESH=$D/mesh/bin/mesh-llm
# The S08 models are not in the image; `devcon8 models` puts them in the volume.
MODELS=$ST/models
need_models() { # FILE...
  local f
  for f in "$@"; do
    [ -f "$MODELS/$f" ] || die "model $f is not on this volume: run devcon8 models first"
  done
}
warn() { echo "warning: $*" >&2; }
die() { echo "devcon8: $*" >&2; exit 1; }
triple() { case $(uname -m) in x86_64) echo x86_64-unknown-linux-gnu;; aarch64) echo aarch64-unknown-linux-gnu;; *) die "unsupported arch $(uname -m)";; esac; }

# The node's config: analytics off, both plugins on. Written once; an existing file is kept, but
# analytics is forced off in it.
mesh_config() {
  local c=$HOME/.mesh-llm/config.toml
  mkdir -p "$HOME/.mesh-llm"
  if [ ! -f "$c" ]; then
    printf 'version = 1\n\n[analytics]\nenabled = false\n\n[[plugin]]\nname = "capsules"\nenabled = true\n\n[[plugin]]\nname = "lexe-wallet"\nenabled = true\n' > "$c"
  elif ! grep -q '^\[analytics\]' "$c"; then
    printf '\n[analytics]\nenabled = false\n' >> "$c"
  fi
}

# Install each bundled plugin into the volume when its installed version, or the archive it came from,
# differs from this image's (the lexe-wallet fork build carries the same version as the release).
# Plugin data (the capsules ledger, payments/) is not touched.
plugins_sync() {
  local t; t=$(triple)
  local capver; capver=$(cat "$D/mesh/capsules.version")
  plugin_ensure capsules "$capver" "$D/mesh/plugins/capsules-$capver-$t.tar.gz"
  plugin_ensure lexe-wallet 0.1.0 "$D/mesh/plugins/lexe-wallet-v0.1.0-$t.tar.gz"
}
# The capsulectl plugins' presentation assets live beside their binaries in the volume; a plugin install
# may replace that directory's contents, so copy them after every install as well as at start.
plugin_assets_sync() {
  local r=$HOME/.local/lib/capsulectl/plugins
  if ! { mkdir -p "$r" && cp -a "$D/plugin-assets/." "$r/"; }; then
    warn "could not copy the plugin presentation assets into $r"
  fi
}
plugin_ensure() { # name version archive
  local have want mark=$ST/plugin-$1.sha256
  have=$("$MESH" plugins info "$1" 2>/dev/null | sed -n 's/^[[:space:]"]*version[":=[:space:]]*"\{0,1\}\([^",[:space:]]*\).*/\1/p' | head -1 || true)
  want=$(sha256sum "$3" | cut -d' ' -f1)
  [ "$have" = "$2" ] && [ "$(cat "$mark" 2>/dev/null)" = "$want" ] && return 0
  "$MESH" plugins install --archive "$3" --name "$1" --version "$2" >> "$ST/plugins.log" 2>&1 \
    || { warn "installing plugin $1 $2 failed; see $ST/plugins.log"; return 1; }
  mkdir -p "$ST" && printf '%s\n' "$want" > "$mark"
  echo "installed plugin $1 $2"
}

# The recorded pid, only while it is still this node: a mesh-llm serve reading this join file. After a
# container restart the pid may belong to another process, which is never reported or signalled.
node_pid() {
  local p; p=$(cat "$ST/node.pid" 2>/dev/null) || return 1
  kill -0 "$p" 2>/dev/null || return 1
  tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -qF -- "serve --client --join-file $ST/join.txt" || return 1
  echo "$p"
}
node_start() {
  [ -s "$ST/join.txt" ] || die "no invite yet: run 'devcon8 join'"
  if node_pid >/dev/null; then relay_start; echo "your node is already running (pid $(node_pid))"; return 0; fi
  mesh_config; plugins_sync
  nohup "$MESH" serve --client --join-file "$ST/join.txt" --port 9337 --console 3131 --listen-all \
    > "$ST/node.log" 2>&1 < /dev/null &
  local np=$!
  echo "$np" > "$ST/node.pid"
  relay_start
  echo "your node started (pid $np); console http://127.0.0.1:3141 (on your laptop)"
}
# The console's management routes accept only a loopback peer, and Docker's published port is not one.
# The relay (lib/console-relay.py) listens on 3132, which the README publishes as the laptop's 3141.
relay_pid() {
  local p; p=$(cat "$ST/relay.pid" 2>/dev/null) || return 1
  kill -0 "$p" 2>/dev/null && tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -qF console-relay.py && echo "$p"
}
relay_start() {
  relay_pid >/dev/null && return 0
  nohup python3 "$D/lib/console-relay.py" 3132 3131 > "$ST/relay.log" 2>&1 < /dev/null &
  echo $! > "$ST/relay.pid"
}
relay_stop() {
  local p; p=$(relay_pid) && kill -TERM "$p"
  rm -f "$ST/relay.pid"
}
node_stop() {
  relay_stop
  local p; p=$(node_pid) || { echo "your node is not running"; rm -f "$ST/node.pid"; return 0; }
  # p is verified to be this node (node_pid)
  kill -TERM "$p"; for _ in $(seq 40); do kill -0 "$p" 2>/dev/null || break; sleep 0.5; done
  kill -0 "$p" 2>/dev/null && kill -KILL "$p"
  rm -f "$ST/node.pid"; echo "your node stopped"
}
node_status() {
  if node_pid >/dev/null; then echo "running (pid $(node_pid))"; curl -fsS -m 3 http://127.0.0.1:9337/v1/models | jq -r '.data[].id' | sed 's/^/  model /'
  else echo "not running"; fi
}
# The first real model the node sees (a client also lists the "mesh" pseudo-model).
wait_model() {
  local m
  for _ in $(seq 90); do
    m=$(curl -fsS -m 2 http://127.0.0.1:9337/v1/models 2>/dev/null | jq -r '[.data[].id | select(. != "mesh")][0] // empty' || true)
    [ -n "$m" ] && { echo "$m"; return 0; }
    sleep 2
  done
  return 1
}

# --- your own lexe wallet: lexe-sidecar (Lexe's local HTTP API), no mesh-llm node needed -------------
# The wallet's root seed is $LEXE/root_seed on the volume: whoever has that file holds the wallet's
# sats. `devcon8 wallet` makes it (after asking), `devcon8 trade --pay lexe` and `lightning` use it.
LEXE=$ST/lexe
LEXE_API=${DEVCON8_LEXE_API:-http://127.0.0.1:5393}
lexe_pid() { # the recorded pid, only while it is still this sidecar
  local p; p=$(cat "$LEXE/sidecar.pid" 2>/dev/null) || return 1
  kill -0 "$p" 2>/dev/null || return 1
  tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -qF lexe-sidecar || return 1
  echo "$p"
}
lexe_call() { # METHOD PATH [JSON]
  curl -fsS -m "${LEXE_TIMEOUT:-60}" --noproxy '*' -X "$1" -H 'Content-Type: application/json' ${3:+-d "$3"} "$LEXE_API$2"
}
lexe_ready() { [ -s "$LEXE/root_seed" ] && [ -e "$LEXE/signed_up" ]; }
# One run at a time creates the seed or starts the sidecar (two terminals answering `yes` together
# must not make two seeds). fd 8 holds the lock; the sidecar is started without it.
lexe_lock() {
  [ -z "${lexe_locked:-}" ] || return 0
  mkdir -p "$ST"; exec 8> "$ST/lexe.lock"; flock 8; lexe_locked=1
}
lexe_unlock() { exec 8>&-; lexe_locked=""; }
# The sidecar's settings are flags, which beat any LEXE_* variable or .env file it would otherwise load.
# Start the sidecar when it is not running, wait until it answers, and (for a registered wallet) run
# Lexe's idempotent provision, so a failed provision is retried by the next call. Sets lexe_started=1
# when this call started it (so a trade run stops what it started). Needs the seed; Lexe's sign-up
# record is $LEXE/signed_up.
lexe_up() {
  [ -s "$LEXE/root_seed" ] || die "no lexe wallet on this volume yet: 'devcon8 wallet' opens one"
  local own=""; [ -n "${lexe_locked:-}" ] || { lexe_lock; own=1; }
  if ! lexe_pid >/dev/null; then
    (cd "$LEXE" && umask 077 && exec 8>&- && exec nohup "$D/bin/lexe-sidecar" --root-seed-path "$LEXE/root_seed" --data-dir "$LEXE" \
       --listen-addr "${LEXE_API#http://}" --network mainnet) > "$LEXE/sidecar.log" 2>&1 < /dev/null &
    echo $! > "$LEXE/sidecar.pid"
    # shellcheck disable=SC2034 # read by trade.sh
    lexe_started=1
  fi
  for _ in $(seq 60); do
    lexe_call GET /v2/health >/dev/null 2>&1 && break
    lexe_pid >/dev/null || die "the lexe wallet did not start; see $LEXE/sidecar.log"
    sleep 0.5
  done
  lexe_call GET /v2/health >/dev/null 2>&1 || die "the lexe wallet does not answer; see $LEXE/sidecar.log"
  if [ -e "$LEXE/signed_up" ]; then
    lexe_call PUT /v2/node/provision >/dev/null || die "the lexe wallet could not be provisioned; see $LEXE/sidecar.log, then run 'devcon8 wallet' again"
  fi
  [ -z "$own" ] || lexe_unlock
}
lexe_stop() {
  local p; p=$(lexe_pid) || { rm -f "$LEXE/sidecar.pid"; return 0; }
  kill -TERM "$p"; for _ in $(seq 20); do kill -0 "$p" 2>/dev/null || break; sleep 0.5; done
  kill -0 "$p" 2>/dev/null && kill -KILL "$p"
  rm -f "$LEXE/sidecar.pid"
}
