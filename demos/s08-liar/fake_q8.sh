#!/usr/bin/env bash
# fake_q8.sh — DEMO ONLY (u844 referee demo): make one node a LIAR about its weights.
#
# The node will load Q4_K_M bytes while it reports the Q8_0 model's weights SHA-256. It needs no
# code change, because a host measures its own weights and an operator owns its own box: any
# self-measured hash is a claim. That's why the referee exists: an independent node re-answers the
# same request, and the answers show who served what.
#
#   fake_q8.sh <q4-file> <q8-path> <q8-sha256> <liar-HOME>          make the liar
#   fake_q8.sh <q4-file> <q8-path> <q8-sha256> <liar-HOME> --undo   take it back
#
#   <q4-file>    the real Q4_K_M GGUF to serve instead
#   <q8-path>    where the liar's host loads Q8_0 from: its Hugging Face cache entry for the Q8 ref,
#                <liar-HOME>/.cache/huggingface/hub/models--Qwen--Qwen2.5-0.5B-Instruct-GGUF/
#                snapshots/<rev>/qwen2.5-0.5b-instruct-q8_0.gguf, or the blob that link points to.
#                It must be under <liar-HOME>.
#   <q8-sha256>  the real Q8_0 file's SHA-256 (64 hex)
#   <liar-HOME>  the liar instance's HOME; nothing outside it is touched
#
# Stop the liar instance first, and start it again afterwards. The host reads its weights digest
# from <liar-HOME>/.cache/mesh-llm/weights-digest/<sha256 of the file path>.json, an entry of
# {path, size, mtime_nanos, digest}. While path, size and mtime match the file, the host uses the
# entry rather than hashing the file again. This script puts the Q4 bytes at the Q8 path and writes
# that entry with the Q4 file's size and mtime and the Q8 digest. The copy is padded with zero bytes
# to the real Q8 file's length, because a Hugging Face model's mesh id is built from its files'
# names and lengths: same length, same model id as the honest Q8 nodes. llama.cpp reads tensors
# by offset and ignores the padding. The Q8 length is taken from the file at <q8-path> before it is
# replaced; when that file is gone, set Q8_BYTES.
#
# --undo removes the poisoned entry and the copied Q4 file. The next start downloads the real Q8
# file and hashes it honestly.
#
# Idempotent. Prints what it did. Reads no key and prints no key or token.
set -euo pipefail

usage() { sed -n '2,25p' "$0" >&2; exit 2; }
[ "$#" -ge 4 ] || usage
Q4=$1 Q8_PATH=$2 Q8_SHA=$3 LIAR_HOME=$4 MODE=${5:-make}
case $MODE in make|--undo) ;; *) usage ;; esac

LIAR_HOME=$(realpath -m "$LIAR_HOME")
[ -d "$LIAR_HOME" ] || { echo "no such liar HOME: $LIAR_HOME" >&2; exit 1; }
[[ $Q8_SHA =~ ^[0-9a-f]{64}$ ]] || { echo "q8-sha256 must be 64 lowercase hex" >&2; exit 1; }

# The host hashes the resolved file (the blob a snapshot entry links to), so the entry is keyed
# by that path.
TARGET=$(realpath -m "$Q8_PATH")
case $TARGET in "$LIAR_HOME"/*) ;; *) echo "refusing: $TARGET is not under $LIAR_HOME" >&2; exit 1 ;; esac
CACHE_DIR=$LIAR_HOME/.cache/mesh-llm/weights-digest
ENTRY=$CACHE_DIR/$(printf '%s' "$TARGET" | sha256sum | cut -c1-64).json

if pgrep -u "$(id -u)" -f -- "--config $LIAR_HOME/" >/dev/null 2>&1 \
   || pgrep -u "$(id -u)" -f -- "--config $(dirname "$LIAR_HOME")/config.toml" >/dev/null 2>&1; then
  echo "warning: an instance using this HOME looks like it is running; stop it first" >&2
fi

if [ "$MODE" = --undo ]; then
  if [ -f "$ENTRY" ]; then rm -f "$ENTRY"; echo "removed poisoned digest entry $ENTRY"; else echo "no digest entry at $ENTRY (already undone)"; fi
  if [ -f "$TARGET" ] && [ -f "$TARGET.fake_q8" ]; then
    rm -f "$TARGET" "$TARGET.fake_q8"; echo "removed the copied Q4 file at $TARGET (the next start downloads the real Q8)"
  else
    echo "no copied Q4 file at $TARGET (already undone)"
  fi
  exit 0
fi

[ -f "$Q4" ] || { echo "no such q4 file: $Q4" >&2; exit 1; }
[ "$(head -c4 "$Q4")" = GGUF ] || { echo "$Q4 is not a GGUF file" >&2; exit 1; }
Q4_SHA=$(sha256sum "$Q4" | cut -c1-64)
[ "$Q4_SHA" != "$Q8_SHA" ] || { echo "the q4 file IS the q8 file; nothing to fake" >&2; exit 1; }

mkdir -p "$(dirname "$TARGET")" "$CACHE_DIR"
# The real Q8 length: from the marker (already faked), else the real file at the path, else Q8_BYTES.
if [ -f "$TARGET.fake_q8" ]; then Q8_BYTES=$(awk '{print $2}' "$TARGET.fake_q8")
elif [ -f "$TARGET" ]; then Q8_BYTES=$(stat -c %s "$TARGET")
else Q8_BYTES=${Q8_BYTES:?no Q8 file at the path: set Q8_BYTES to its length in bytes}; fi
Q4_BYTES=$(stat -c %s "$Q4")
[ "$Q4_BYTES" -le "$Q8_BYTES" ] || { echo "the q4 file is longer than the q8 file; cannot pad" >&2; exit 1; }
if [ -f "$TARGET" ] && [ "$(cat "$TARGET.fake_q8" 2>/dev/null)" = "$Q4_SHA $Q8_BYTES" ] && [ "$(stat -c %s "$TARGET")" = "$Q8_BYTES" ]; then
  echo "the padded Q4 bytes are already at $TARGET"
else
  rm -f "$TARGET"; cp "$Q4" "$TARGET"; truncate -s "$Q8_BYTES" "$TARGET"; echo "$Q4_SHA $Q8_BYTES" > "$TARGET.fake_q8"
  echo "copied the Q4 file (sha256 ${Q4_SHA:0:16}…, $Q4_BYTES bytes) to the Q8 path $TARGET, zero-padded to the Q8 length $Q8_BYTES"
fi

python3 - "$TARGET" "$Q8_SHA" "$ENTRY" <<'PY'
import json, os, sys
path, digest, entry = sys.argv[1:4]
st = os.stat(path)
rec = {"path": path, "size": st.st_size, "mtime_nanos": st.st_mtime_ns, "digest": digest}
tmp = entry + ".tmp"
with open(tmp, "w") as f:
    json.dump(rec, f)
os.replace(tmp, entry)
print(f"wrote digest entry {entry}: size {st.st_size}, mtime_nanos {st.st_mtime_ns}, digest {digest[:16]}… (the Q8 SHA, not the bytes on disk)")
PY
echo "LIAR ready: start the instance; it serves Q4 bytes and reports weights_digest ${Q8_SHA:0:16}… (Q8_0)."
echo "Undo: $0 $Q4 $Q8_PATH $Q8_SHA $LIAR_HOME --undo"
