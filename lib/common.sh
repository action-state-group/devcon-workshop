# shellcheck shell=bash
# common.sh: helpers every devcon8 step shares. Sourced, never run.
D=${D:-/opt/devcon8}
ST=${ST:-$HOME/.devcon8}
MESH=$D/mesh/bin/mesh-llm
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
  if node_pid >/dev/null; then echo "your node is already running (pid $(node_pid))"; return 0; fi
  mesh_config; plugins_sync
  nohup "$MESH" serve --client --join-file "$ST/join.txt" --port 9337 --console 3131 --listen-all \
    > "$ST/node.log" 2>&1 < /dev/null &
  echo $! > "$ST/node.pid"
  echo "your node started (pid $!); console http://127.0.0.1:3131"
}
node_stop() {
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
