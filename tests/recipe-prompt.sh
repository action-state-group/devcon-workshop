#!/usr/bin/env bash
# recipe-prompt.sh: the trader recipe's protocol must reach the model, in the right payment mode.
# goose's ACP providers (claude-acp, codex-acp) send only the recipe `prompt` to the model and drop
# `instructions`, so a --pay lexe seller once never saw its Lightning branch and sent simulated
# proposals (devcon-workshop#27). Two checks:
#  1. the rendered recipe, both modes: the lexe prompt has the Lightning seller steps and no x402
#     payment tool; the simulated prompt the reverse; and the protocol is not in `instructions`.
#  2. what a claude-acp session actually sends: goose runs against a local stand-in for the Anthropic
#     API that records the requests, and the recorded text holds the lexe branch.
# Run inside the image: docker run --rm IMAGE /opt/devcon8/tests/recipe-prompt.sh
set -euo pipefail
D=${D:-/opt/devcon8}
R=$D/agent/recipes/trader.yaml
fail() { echo "FAIL $*" >&2; exit 1; }
render() { goose run --recipe "$R" --render-recipe --params "pay=$1" ${2:+--params "buy_from=$2"}; }
has() { grep -qF -- "$2" <<<"$1"; }

lexe=$(render lexe); sim=$(render simulated); buyer=$(render lexe shop@agentboxnanda.org)
if grep -q '^instructions:' <<<"$lexe"; then fail "the protocol is in 'instructions', which ACP providers drop"; fi
# shellcheck disable=SC2016  # backticks are literal text in the prompt
for s in 'payment is REAL' 'AS THE SELLER' 'lightning invoice <conversation>' 'with `--invoice`' 'lightning receive'; do
  has "$lexe" "$s" || fail "lexe prompt lacks: $s"
done
for s in 'pay-x402 <conversation>' 'requirements.json' 'simulated x402 payment on a test network'; do
  has "$lexe" "$s" && fail "lexe prompt still has: $s"
done
for s in 'pay-x402 <conversation>' 'requirements.json' 'simulated x402 payment on a test network'; do
  has "$sim" "$s" || fail "simulated prompt lacks: $s"
done
for s in 'payment is REAL' 'lightning invoice <conversation>' 'lightning receive <conversation>'; do
  has "$sim" "$s" && fail "simulated prompt has lexe text: $s"
done
has "$buyer" 'lightning pay <conversation>' || fail "lexe buyer prompt lacks lightning pay"
has "$buyer" 'shop@agentboxnanda.org' || fail "buyer prompt lacks the shop address"
echo "ok   rendered recipe: lexe and simulated prompts carry their own payment branch"

# What the model is sent through claude-acp (needs the non-root user: Claude Code refuses
# bypassPermissions as root). Skipped where the image has no claude-acp provider.
goose run --help >/dev/null 2>&1 || exit 0
T=$(mktemp -d)
cat > "$T/cap.py" <<'PY'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_POST(s):
        open(sys.argv[2], "ab").write(s.rfile.read(int(s.headers.get("content-length", 0))) + b"\n")
        s.send_response(500); s.end_headers()
    def log_message(s, *a): pass
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
port=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 -I "$T/cap.py" "$port" "$T/req.log" & srv=$!
trap 'kill $srv 2>/dev/null || true' EXIT
sleep 1
HOME=$T GOOSE_MODE=approve GOOSE_PROVIDER=claude-acp GOOSE_MODEL=sonnet ANTHROPIC_BASE_URL=http://127.0.0.1:$port ANTHROPIC_API_KEY=x \
  timeout 120 goose run --no-session --recipe "$R" --params pay=lexe >/dev/null 2>&1 || true
[ -s "$T/req.log" ] || fail "goose sent nothing to the model API"
grep -q 'AS THE SELLER' "$T/req.log" || fail "the recipe's protocol did not reach the model through claude-acp"
grep -q 'lightning invoice <conversation>' "$T/req.log" || fail "the lexe seller's invoice step did not reach the model"
echo "ok   claude-acp sends the lexe seller's Lightning branch to the model"
