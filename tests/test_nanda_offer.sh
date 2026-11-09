#!/usr/bin/env bash
# test_nanda_offer.sh: devcon8 nanda offer against a fake gateway and Index (tests/fake_index.py). The
# offer is shown and confirmed before anything is written; it lands in trust_manifest.metadata.offer with
# the rest of the record left alone; --remove clears only the offer; an Index that does not keep it is an error.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d); srv=""; trap '[ -z "$srv" ] || kill "$srv" 2>/dev/null || true; rm -rf "$T"' EXIT
fail() { echo "FAIL $*"; [ ! -f "$T/log" ] || cat "$T/log"; exit 1; }
start() { # MODE
  : > "$T/log"
  port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  python3 -I "$here/fake_index.py" "$port" "$T/log" "$1" & srv=$!
  for _ in $(seq 50); do curl -fs "http://127.0.0.1:$port/api/v1/resolve?locator=x" >/dev/null 2>&1 && break; sleep 0.1; done
}
stop() { kill "$srv"; wait "$srv" 2>/dev/null || true; srv=""; }
H=$T/home; mkdir -p "$H/.devcon8/agentbox" "$H/studio/cards/stapled"
printf 'test-token\n' > "$H/.devcon8/agentbox/key"
echo '{"id":"m1","address":"m1@agentboxnanda.org","existing":false}' > "$H/.devcon8/agentbox/mailbox.json"
run() { # INPUT ARGS...
  local input=$1; shift
  printf '%b' "$input" | HOME=$H D=$here/.. MBX_BASE="http://127.0.0.1:$port" NANDA_INDEX="http://127.0.0.1:$port" \
    bash "$here/../lib/nanda.sh" offer "$@" 2>&1
}
stored() { curl -fs "http://127.0.0.1:$port/api/v1/resolve?locator=x" | jq -c '.entry.trustManifest'; }

start ""
# Declined: nothing is written, and no Index sign-in even starts.
out=$(run 'n\n' ) && fail "a declined offer exited 0"
grep -q '"v":0' <<<"$out" || fail "the exact JSON was not shown: $out"
grep -q 'cannot recall' <<<"$out" || fail "the --remove limit was not said: $out"
grep -qE '^(PUT|POST /auth)' "$T/log" && fail "something was written before the user said yes"
# No History card staple yet: the offer says so and carries no key.
out=$(run 'y\n') || fail "publishing failed: $out"
[ "$(stored)" = '{"identity":"m1","metadata":{"keep":"me","offer":{"v":0,"item":"digital fox sticker","price":{"amount":50,"unit":"usd_cent"},"rail":"x402","history_staple":false}}}' ] || fail "stored: $(stored)"
echo "ok   nanda offer: declined writes nothing; yes publishes the shown JSON and leaves the rest of the record"
# With a staple, the card and its key are announced.
echo '{"staple":{"reply":{"responder":"ed25519:abc12345"}}}' > "$H/studio/cards/stapled/history-staple.json"
run 'y\n' >/dev/null || fail "publishing with a staple failed"
[ "$(stored | jq -c .metadata.offer)" = '{"v":0,"item":"digital fox sticker","price":{"amount":50,"unit":"usd_cent"},"rail":"x402","history_staple":true,"history_key":"ed25519:abc12345"}' ] || fail "staple offer: $(stored)"
echo "ok   nanda offer: a staple on disk announces the card and its key"
out=$(run 'y\n' --remove) || fail "--remove failed: $out"
[ "$(stored)" = '{"identity":"m1","metadata":{"keep":"me"}}' ] || fail "after remove: $(stored)"
echo "ok   nanda offer --remove: clears only the offer"
stop
# An Index that drops the metadata is reported, not claimed as published.
start drop
out=$(run 'y\n') && fail "an Index that dropped the offer exited 0"
grep -q 'did not keep the offer' <<<"$out" || fail "no error for a dropped offer: $out"
echo "ok   nanda offer: an Index that does not keep the offer is an error"
stop
