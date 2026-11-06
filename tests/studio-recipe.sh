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
  for m in 'STUDIO.' '/opt/devcon8/agent/skills/terms-pack-author/SKILL.md' '`terms <verb>`' 'wait for their yes' 'under ~/studio' 'CARDS.' '`card make`' '`card staple`' '`card open <that path>`' 'history-card.bundle' 'card make --fresh' 'keep `--invoice`' 'DISPUTES.' '`dispute <deal> --words' '`dispute show <deal>`' 'You do not rule'; do
    has "$s" "$m" || fail "$mode: studio prompt lacks: $m"
    has "$t" "$m" && fail "$mode: the trader recipe has Studio text: $m"
  done
done
# Studio does not start the mailbox wait on its own; the trader does.
for mode in simulated lexe; do
  s=$(render "$S" "$mode"); t=$(render "$T" "$mode")
  has "$s" 'Do NOT run `mbx wait`' || fail "$mode: the studio prompt does not hold back the mailbox wait"
  has "$t" 'Then wait for buyers with `mbx wait`' || fail "$mode: the trader no longer waits at start-up"
  has "$s" 'Then wait for buyers with `mbx wait`' && fail "$mode: the studio prompt still starts the wait at start-up"
done
s=$(render "$S" simulated shop@agentboxnanda.org)
has "$s" 'Do NOT run `mbx wait`' && fail "a Studio purchase must not hold back the wait"
has "$s" 'do not run `mbx wait` at all' && fail "a Studio purchase must not be told to never run mbx wait"
s=$(render "$S" simulated); has "$s" 'do not run `mbx wait` at all' || fail "a Studio seller is not told to hold back mbx wait before it is asked to sell"
s=$(render "$S" lexe); has "$s" 'payment is REAL' || fail "lexe studio prompt lacks the real-payment text"
s=$(render "$S" simulated); has "$s" 'pay-x402 <conversation>' || fail "simulated studio prompt lacks pay-x402"
s=$(render "$S" simulated shop@agentboxnanda.org); has "$s" 'Your user asked you to buy from shop@agentboxnanda.org' || fail "buy_from is not rendered"
s=$(goose run --recipe "$S" --render-recipe --params "pay=simulated" --params "want=one fox sticker")
has "$s" 'Then find a shop for "one fox sticker"' || fail "want is not rendered in the Studio prompt"
has "$s" 'Then start the purchase from' && fail "a Studio search starts a purchase before the pick"
s=$(render "$S" simulated shop@agentboxnanda.org)
has "$s" 'mbx send THE PICKED ADDRESS' && fail "a typed-address Studio buyer prompt names the picked address"
has "$s" 'mbx send shop@agentboxnanda.org' || fail "the typed-address Studio buyer does not send to its shop"
echo "ok   studio.yaml renders in both modes with the trader protocol and the Studio section"
