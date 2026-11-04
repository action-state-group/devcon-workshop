#!/usr/bin/env bash
# studio-recipe.sh: studio.yaml keeps the trader's protocol in both payment modes, adds the Studio
# section, and does not widen the permissions beyond the two skills and ~/studio. (That studio.yaml is
# trader.yaml plus exactly those edits is tests/test_build_recipe.py's check.)
# Run inside the Studio layer, or in the base image with the recipe mounted in (as CI does): docker run --rm IMAGE /opt/devcon8/tests/studio-recipe.sh
# shellcheck disable=SC2016  # backticks are literal text in the prompt
set -euo pipefail
D=${D:-/opt/devcon8}
S=$D/agent/recipes/studio.yaml T=$D/agent/recipes/trader.yaml
fail() { echo "FAIL $*" >&2; exit 1; }
render() { goose run --recipe "$1" --render-recipe --params "pay=$2" ${3:+--params "buy_from=$3"}; }
has() { tr -s " \n" "  " <<<"$1" | grep -qF -- "$2"; }
for mode in simulated lexe; do
  s=$(render "$S" "$mode"); t=$(render "$T" "$mode")
  if grep -q '^instructions:' <<<"$s"; then fail "$mode: the protocol is in 'instructions', which ACP providers drop"; fi
  for m in 'AS THE SELLER' 'Do not curl anything, install anything or read other files' 'deal check'; do
    has "$s" "$m" || fail "$mode: studio prompt lacks: $m"
  done
  for m in 'STUDIO.' '/opt/devcon8/agent/skills/terms-pack-author/SKILL.md' '`terms <verb>`' 'wait for their yes' 'under ~/studio'; do
    has "$s" "$m" || fail "$mode: studio prompt lacks: $m"
    has "$t" "$m" && fail "$mode: the trader recipe has Studio text: $m"
  done
done
s=$(render "$S" lexe); has "$s" 'payment is REAL' || fail "lexe studio prompt lacks the real-payment text"
s=$(render "$S" simulated); has "$s" 'pay-x402 <conversation>' || fail "simulated studio prompt lacks pay-x402"
s=$(render "$S" simulated shop@agentboxnanda.org); has "$s" 'Your user asked you to buy from shop@agentboxnanda.org' || fail "buy_from is not rendered"
echo "ok   studio.yaml renders in both modes with the trader protocol and the Studio section"
