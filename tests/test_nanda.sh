#!/usr/bin/env bash
# test_nanda.sh: devcon8 nanda against a fake gateway (tests/fake_agentbox.py) that answers as the
# real one did for a key rejoining an already-verified mailbox. The step must still ask for the code
# and verify this key before it takes the duty (found 10-31: it skipped the prompt, then got 409).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d); trap 'kill "$srv" 2>/dev/null || true; rm -rf "$T"' EXIT
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 -I "$here/fake_agentbox.py" "$port" "$T/requests.log" & srv=$!
for _ in $(seq 50); do curl -fs "http://127.0.0.1:$port/api/v1/me" >/dev/null 2>&1 && break; sleep 0.1; done
out=$(printf 'y\n123456\n' | HOME=$T/home MBX_BASE="http://127.0.0.1:$port" NANDA_INDEX="http://127.0.0.1:$port" \
  bash "$here/../lib/nanda.sh" p@example.com 2>&1) || { echo "$out"; echo "FAIL nanda.sh exited non-zero"; exit 1; }
# The prompt text shows only on a terminal (read -p); the request log shows the code was asked for.
grep -q '/verify {"code": "123456"}' "$T/requests.log" || { cat "$T/requests.log"; echo "FAIL the code was not asked for"; exit 1; }
v=$(grep -n "/verify" "$T/requests.log" | head -1 | cut -d: -f1)
d=$(grep -n "/duty" "$T/requests.log" | tail -1 | cut -d: -f1)   # the duty taken; an earlier probe is refused
if [ -z "$v" ] || [ -z "$d" ] || [ "$v" -ge "$d" ]; then cat "$T/requests.log"; echo "FAIL verify must come before duty"; exit 1; fi
[ -f "$T/home/.devcon8/agentbox/verified" ] || { echo "FAIL no verified marker"; exit 1; }
echo "ok   nanda: an unverified key that rejoined a verified mailbox is asked for the code, then takes the duty"
kill "$srv"; wait "$srv" 2>/dev/null || true

# A volume an older image set up: key and mailbox present, the key verified and on duty, no marker.
# It must not be asked for a code that will never come.
U=$T/old; mkdir -p "$U/home/.devcon8/agentbox"; : > "$U/requests.log"
printf 'test-token\n' > "$U/home/.devcon8/agentbox/key"
echo '{"id":"m1","address":"m1@agentboxnanda.org","existing":false}' > "$U/home/.devcon8/agentbox/mailbox.json"
python3 -I "$here/fake_agentbox.py" "$port" "$U/requests.log" verified & srv=$!
for _ in $(seq 50); do curl -fs "http://127.0.0.1:$port/api/v1/me" >/dev/null 2>&1 && break; sleep 0.1; done
out=$(HOME=$U/home MBX_BASE="http://127.0.0.1:$port" NANDA_INDEX="http://127.0.0.1:$port" \
  bash "$here/../lib/nanda.sh" p@example.com < /dev/null 2>&1) || { echo "$out"; echo "FAIL the old volume's run failed"; exit 1; }
if grep -q "/verify" "$U/requests.log"; then cat "$U/requests.log"; echo "FAIL a verified key was asked for a code"; exit 1; fi
[ -f "$U/home/.devcon8/agentbox/verified" ] || { echo "FAIL no marker after the duty check"; exit 1; }
echo "ok   nanda: a key an older image verified (no marker) is not asked for a code"
kill "$srv"; wait "$srv" 2>/dev/null || true

# A new signup against a gateway that would grant the duty to an unverified key: the code is still asked.
N=$T/new; mkdir -p "$N"; : > "$N/requests.log"
python3 -I "$here/fake_agentbox.py" "$port" "$N/requests.log" lenient & srv=$!
for _ in $(seq 50); do curl -fs "http://127.0.0.1:$port/api/v1/me" >/dev/null 2>&1 && break; sleep 0.1; done
out=$(printf 'y\n123456\n' | HOME=$N/home MBX_BASE="http://127.0.0.1:$port" NANDA_INDEX="http://127.0.0.1:$port" \
  bash "$here/../lib/nanda.sh" p@example.com 2>&1) || { echo "$out"; echo "FAIL the new signup failed"; exit 1; }
grep -q '/verify {"code": "123456"}' "$N/requests.log" || { cat "$N/requests.log"; echo "FAIL a new key skipped its code"; exit 1; }
echo "ok   nanda: a new key is always asked for its code, whatever the duty answer"
