#!/usr/bin/env bash
# smoke.sh: the checks CI runs inside a freshly built image (design section 9, steps 2, 3, 5, 6, 8).
# Run as: docker run --rm IMAGE /opt/devcon8/tests/smoke.sh
set -euo pipefail
D=/opt/devcon8
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }

# 2. The host is the pinned lab build.
. "$D/versions.lock"
# A release build prints the plain workspace version, no commit suffix (asg-lab-rebuild 2.4).
v=$("$D/mesh/bin/mesh-llm" --version); [ "$v" = "mesh-llm $MESH_LLM_VERSION" ] || fail "mesh-llm version: $v"; ok "$v (lab ${MESH_LLM_SHA:0:9})"
"$D/s08/bin/mesh-llm" --version | grep -q '0\.78\.1' || fail "s08 mesh-llm is not v0.78.1"; ok "s08 mesh-llm v0.78.1"

# 2. capsules and lexe-wallet load under the lab host, in a throwaway HOME with nothing shared.
T=$(mktemp -d /tmp/dw-XXXXXX)
( export HOME=$T ST=$T/.devcon8; mkdir -p "$ST"; . /opt/devcon8/lib/common.sh; mesh_config; plugins_sync )
HOME=$T CAPSULES_DATA_DIR=$T/capsule-data "$D/mesh/bin/mesh-llm" serve --port 19337 --console 13131 --headless \
  --disable-iroh-relays --log-format json > "$T/run.log" 2>&1 < /dev/null &
pid=$!
up=""
for _ in $(seq 90); do
  st=$(curl -fsS -m 2 http://127.0.0.1:13131/api/plugins 2>/dev/null || true)
  if echo "$st" | jq -e '[.. | objects | select(.name? == "capsules" and .status? == "running")] | length > 0' >/dev/null 2>&1 \
     && echo "$st" | jq -e '[.. | objects | select(.name? == "lexe-wallet" and .status? == "running")] | length > 0' >/dev/null 2>&1; then up=1; break; fi
  sleep 2
done
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
[ -n "$up" ] || { tail -30 "$T/run.log"; echo "$st"; fail "capsules and lexe-wallet did not both reach running"; }
ok "capsules $(cat $D/mesh/capsules.version) and lexe-wallet running under the host"

# 3. The S02 legs verify as settled.
cd "$D/demos/s02/legs"
capsulectl settlement status --leg terms-shockley.json --leg payer_observed-shockley.json --leg payee_observed-brattain.json \
  --payer-key b1ff0623566783ad73ece0cc4736788a4ad48c2dfce528ae18e165a49c2fd9e7 \
  --payee-key 5631608d05e1eee382e519abd6e93730a091a7334cbd5c33cb07f92af000b031 | jq -e '.say == "Settled: both sides report the same payment."' >/dev/null \
  || fail "s02 legs do not verify"
ok "s02 legs settled"

# 5. go-seal builds offline from the vendored modules and seals a record.
W=$(mktemp -d /tmp/gs-XXXXXX); cp -R "$D/examples/go-seal" "$W/src"; chmod -R u+w "$W"
(cd "$W/src" && GOPROXY=off GOFLAGS=-mod=vendor go build -o "$W/go-seal" .) || fail "go-seal does not build offline"
"$W/go-seal" -book "$W/book" | grep -q 'covers record 1: true' || fail "go-seal did not seal and checkpoint"
ok "go-seal builds offline and seals"

# 6. The agent CLIs run (no login in CI).
goose --version >/dev/null || fail "goose"; claude --version >/dev/null || fail "claude"; codex --version >/dev/null || fail "codex"
command -v claude-agent-acp >/dev/null || fail "claude-agent-acp"; command -v codex-acp >/dev/null || fail "codex-acp"
capsulectl --version >/dev/null 2>&1 || capsulectl version >/dev/null || fail "capsulectl"
ok "goose $(goose --version | head -1), claude, codex, both ACP adapters, capsulectl"

# The trader recipe reads the deal skill from here.
[ -f "$D/agent/skills/deal/SKILL.md" ] || fail "deal skill missing"; ok "deal skill present"

# Nothing tracks: DO_NOT_TRACK is set and MESH_LLM_ANALYTICS is not.
if [ "${DO_NOT_TRACK:-}" != 1 ] || [ -n "${MESH_LLM_ANALYTICS+x}" ]; then fail "analytics environment"; fi
ok "DO_NOT_TRACK=1"
echo "smoke: all passed"
