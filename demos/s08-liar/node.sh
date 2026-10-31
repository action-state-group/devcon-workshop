#!/usr/bin/env bash
# node.sh start|stop|ident <name>: one demo node, never any other process.
# Adapted from neutral/_work/v015-1-referee/vm/{inst,stopinst,ident}.sh (the 10-12 run).
set -uo pipefail
# Drop anything the shell inherited from this account (the box's own node runs as the same user)
# that could point a demo node at another cache, config, ledger or wallet. Before env.sh, so its
# own paths survive.
for v in $(compgen -e | grep -E '^(HF_|HUGGINGFACE_|XDG_|CAPSULES_|MESH_LLM)'); do unset "$v"; done
. "$(dirname "$0")/env.sh"
CMD=$1 NAME=$2 N=$S/$2

start() {
  mkdir -p "$N/home" "$N/data" "$N/logs" "$N/tmp"; chmod 700 "$N"
  export HOME=$N/home XDG_DATA_HOME=$N/home/.local/share TMPDIR=$N/tmp/ RUST_LOG=info
  export CAPSULES_DATA_DIR=$N/data MESH_LLM_CONFIG=$N/config.toml
  CAPSULES_OPENAI_API_URL=http://127.0.0.1:$(api "$NAME")   # the default 9337 is the box's own node
  export CAPSULES_OPENAI_API_URL
  export CAPSULES_SHARE_RECORD_AT_COMPLETION=counterparty          # push each signed half to the other side
  [ -f "$N/env" ] && . "$N/env"                                     # peer keys, written by 01-start.sh
  local archive=$CAPSULES_ARCHIVE bin=$MESH_LLM
  if [ "$NAME" = liar ]; then archive=$CAPSULES_RED_ARCHIVE; export CAPSULES_REDTEAM_SELECTIVE_LOG=$OMIT_TOGGLE; fi
  if mine "$(cat "$N/logs/node.pid" 2>/dev/null)"; then echo "$NAME already running"; return 0; fi
  # .installed holds the sha256 of the plugin archive and of the binary, so a node whose archive or
  # binary changed reinstalls (each binary installs its own native runtime).
  local want; want=$(cat "$archive" "$bin" | sha256sum | cut -d' ' -f1) || { echo "missing $archive or $bin"; return 1; }
  if [ "$(cat "$N/.installed" 2>/dev/null)" != "$want" ]; then
    # A different build's runtime can carry the same version label with other bytes; mesh-llm then
    # refuses the install ("runtime cache collision"). This node's own cache only, rebuilt below.
    rm -rf "$N/home/$CACHE_REL/mesh-llm/native-runtimes"
    { "$bin" runtime install --bundle-dir "$(dirname "$bin")/native-runtimes" \
      && "$bin" plugins install --archive "$archive" --name capsules --version "$CAPSULES_VERSION"; } \
      > "$N/logs/install.log" 2>&1 && echo "$want" > "$N/.installed" || { echo "install failed:"; tail -5 "$N/logs/install.log"; return 1; }
  fi
  [ -f "$N/config.toml" ] || printf 'version = 1\n\n[analytics]\nenabled = false\n\n[[plugin]]\nname = "capsules"\nenabled = true\n' > "$N/config.toml"
  local args=(--config "$N/config.toml" --port "$(api "$NAME")" --console "$(console "$NAME")" --log-format json --disable-iroh-relays ${S08_LISTEN_ALL:+--listen-all})
  [ -s "$S/join.txt" ] && [ "$NAME" != honest ] && args+=(--join-file "$S/join.txt")
  if [ "$NAME" = asker ]; then args+=(--client); else args+=(--model "$MODEL_REF"); fi
  cd "$N" || return 1
  nohup "$bin" serve "${args[@]}" > "$N/logs/node.log" 2>&1 < /dev/null &
  echo $! > "$N/logs/node.pid"
  echo "$NAME started (api $(api "$NAME"), console $(console "$NAME"))"
}

# Is pid $1 alive and this node's own process (its working directory is $N)?
mine() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null && [ "$(proc_cwd "$1")" = "$N" ]; }

# Stops only this node's own process, and fails unless it is gone afterwards.
stop() {
  local P; P=$(cat "$N/logs/node.pid" 2>/dev/null) || { echo "$NAME: not started"; return 0; }
  # A dead pid, or one some other process reuses now, means this node is not running: never kill it.
  mine "$P" || { rm -f "$N/logs/node.pid"; echo "$NAME: not running"; return 0; }
  kill -TERM "$P"; for _ in $(seq 60); do kill -0 "$P" 2>/dev/null || break; sleep 0.5; done
  if kill -0 "$P" 2>/dev/null; then kill -KILL "$P"; for _ in $(seq 20); do kill -0 "$P" 2>/dev/null || break; sleep 0.5; done; fi
  kill -0 "$P" 2>/dev/null && { echo "$NAME: pid $P did not exit"; return 1; }
  rm -f "$N/logs/node.pid"; echo "$NAME stopped"
}

# "<mesh node id> <capsules key>": both public. The key is read from the .pub file only.
ident() {
  local id key
  id=$(curl -fsS "http://127.0.0.1:$(console "$NAME")/api/diagnostics/network" | jq -er .node_id) || return 1
  key=$(openssl pkey -pubin -in "$N/data/keys/node-key.pub.pem" -outform DER | tail -c 32 | od -An -v -tx1 | tr -d ' \n')
  [ ${#key} = 64 ] || return 1
  echo "$id $key" > "$N/ident"
}

"$CMD"
