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
# S08: the liar's patched plugin and the release one side by side, and step 8's reconcile tool.
for a in "$D"/s08/dist/capsules-"$CAPSULES_VERSION"-*-unknown-linux-gnu.tar.gz "$D"/s08/dist/capsules-"$CAPSULES_VERSION"-selective-log-*-unknown-linux-gnu.tar.gz; do
  tar -tzf "$a" >/dev/null 2>&1 || fail "s08 archive missing or broken: $a"
done
[ -x "$D/s08/bin-tools/reconcile-asked" ] || fail "s08 reconcile tool missing"
ok "s08: capsules $CAPSULES_VERSION, its selective-log build, reconcile-asked"

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

# The plugins' presentation assets are shipped, and the entrypoint copied them beside the plugin binaries
# (what `presentation build` resolves them from), so it carries their modules.
for f in capsulectl-deal.d/deal-view.js standard-history-module/standard_history_card.js; do
  [ -f "$D/plugin-assets/$f" ] || fail "plugin presentation asset $f missing from the image"
  [ -f ~/.local/lib/capsulectl/plugins/"$f" ] || fail "plugin presentation asset $f not copied beside the plugins"
done
ok "plugin presentation assets present"

# The trader recipe reads the deal skill from here.
[ -f "$D/agent/skills/deal/SKILL.md" ] || fail "deal skill missing"; ok "deal skill present"

# The seller keeps listening (foreground `mbx wait`), never asks for an item or price, and renews a stale card (issue #11).
R="$D/agent/recipes/trader.yaml"
for t in 'in the FOREGROUND, never in the background' 'never ask your user for an' 'A check goes stale'; do
  grep -q "$t" "$R" || fail "trader recipe lost the seller keep-listening text: $t"
done
ok "trader recipe: seller waits in the foreground, no item/price questions, stale card renewed"

# Nothing tracks: DO_NOT_TRACK is set and MESH_LLM_ANALYTICS is not.
if [ "${DO_NOT_TRACK:-}" != 1 ] || [ -n "${MESH_LLM_ANALYTICS+x}" ]; then fail "analytics environment"; fi
ok "DO_NOT_TRACK=1"
# Every `devcon8 brain` path turns goose telemetry off (else goose asks "share anonymous usage data?"), mesh
# included, and forces a stale `true` to false. claude/codex logins are stubbed on PATH; mesh stops at its
# node check ("not running") after the write.
bt=$(mktemp -d); mkdir "$bt/bin"; for c in claude codex; do printf '#!/bin/sh\nexit 0\n' > "$bt/bin/$c"; chmod +x "$bt/bin/$c"; done
for b in mesh claude codex; do
  mkdir -p "$bt/$b/.config/goose"; echo 'GOOSE_TELEMETRY_ENABLED: true' > "$bt/$b/.config/goose/config.yaml"
  PATH="$bt/bin:$PATH" HOME="$bt/$b" devcon8 brain "$b" >/dev/null 2>&1 < /dev/null || true
  c=$bt/$b/.config/goose/config.yaml
  [ "$(grep '^GOOSE_TELEMETRY_ENABLED:' "$c")" = 'GOOSE_TELEMETRY_ENABLED: false' ] || fail "devcon8 brain $b leaves goose telemetry on"
done
rm -rf "$bt"; ok "devcon8 brain mesh|claude|codex: goose telemetry off"
# brain claude uses `claude auth login` (no TUI) and checks `claude auth status`: logged in already skips
# login unless --relogin; a login that leaves status failing is an error and does not switch the provider.
bt=$(mktemp -d); mkdir "$bt/bin" "$bt/h"
cat > "$bt/bin/claude" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "auth login") echo login >> "$STUB_LOG"; [ -z "${STUB_LOGIN_OK:-}" ] || touch "$STUB_STATE" ;;
  "auth status") [ -e "$STUB_STATE" ] ;;
  *) echo "unexpected claude $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$bt/bin/claude"
bc() { PATH="$bt/bin:$PATH" HOME="$bt/h" STUB_LOG="$bt/log" STUB_STATE="$bt/state" devcon8 brain claude "$@" 2>&1 < /dev/null; }
: > "$bt/log"
bc | grep -q 'did not complete' || fail "brain claude: failed login not reported"
grep -q GOOSE_PROVIDER "$bt/h/.config/goose/config.yaml" && fail "brain claude: provider set after a failed login"
STUB_LOGIN_OK=1 bc | grep -q 'login succeeded' || fail "brain claude: successful login not reported"
[ "$(grep -c login "$bt/log" || true)" = 2 ] || fail "brain claude: expected 2 logins so far"
bc | grep -q 'already logged in' || fail "brain claude: already-logged-in not reported"
[ "$(grep -c login "$bt/log" || true)" = 2 ] || fail "brain claude: re-run forced a new login"
bc --relogin >/dev/null || true
[ "$(grep -c login "$bt/log" || true)" = 3 ] || fail "brain claude --relogin did not log in again"
rm -rf "$bt"; ok "devcon8 brain claude: auth login + status, skip when logged in, --relogin"
echo "smoke: all passed"
