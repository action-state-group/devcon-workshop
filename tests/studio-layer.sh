#!/usr/bin/env bash
# studio-layer.sh: what the Studio layer adds to the workshop image is in place and nothing else moved.
# Run inside the Studio layer: docker run --rm IMAGE /opt/devcon8/tests/studio-layer.sh
set -euo pipefail
D=/opt/devcon8
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }
. "$D/studio/versions.lock"
if [ -z "$STUDIO_SKILLS_COMMIT" ] || [ -z "$STUDIO_TERMS_ENTRY" ]; then fail "the layer's pins are empty"; fi
"$D/studio/venv/bin/python" -I -c 'import yaml, rfc8785, jsonschema' || fail "PyYAML, rfc8785 or jsonschema missing from the layer's venv"
ok "PyYAML, rfc8785 and jsonschema in the layer venv"
[ "$(type -P terms)" = "$D/agent/bin/terms" ] || fail "terms is not on PATH"
[ -r "$D/agent/skills/terms-pack-author/SKILL.md" ] || fail "terms-pack-author SKILL.md missing or unreadable by $(id -un)"
[ -r "$D/agent/skills/deal/SKILL.md" ] || fail "the base image's deal skill is gone"
if [ ! -r "$D/agent/recipes/studio.yaml" ] || [ ! -r "$D/agent/recipes/trader.yaml" ]; then fail "a recipe is missing"; fi
ok "terms on PATH, both skills and both recipes readable"
# The system Python stays untouched (no pip into an externally managed Python).
python3 -c 'import yaml' 2>/dev/null && fail "PyYAML leaked into the system Python"
ok "system Python untouched"
if [ ! -x "$D/agent/bin/devcon8-studio" ] || [ ! -s "$D/studio/replay/testdata/studio/sticker-trades.json" ] || [ ! -s "$D/studio/replay/scripts/studio-replay.sh" ]; then fail "the replay or its launcher is missing"; fi
ok "devcon8-studio replay and its fixture are in place"
[ "$(type -P card)" = "$D/agent/bin/card" ] || fail "card is not on PATH"
card 2>/dev/null && fail "card with no verb should list its verbs and exit non-zero"
ok "card on PATH"
for c in dispute referee; do
  [ "$(type -P $c)" = "$D/agent/bin/$c" ] || fail "$c is not on PATH"
  $c 2>/dev/null && fail "$c with no arguments should list its usage and exit non-zero"
done
ok "dispute and referee on PATH"
# The seller's proposal may carry its History card: the layer's mbx is the repo's.
grep -q 'history-staple.json' "$D/agent/bin/mbx" || fail "the layer's mbx does not let a proposal carry the staple"
ok "mbx lets a proposal carry the History card"
terms --help >/dev/null || fail "terms --help failed"
ok "terms --help"
# `devcon8-studio --want` needs the repo's trade.sh and offers (devcon-workshop#81); the pinned base has neither.
[ -x "$D/agent/bin/offers" ] || fail "the layer has no offers"
grep -q -- '--want' "$D/lib/trade.sh" || fail "the layer's trade.sh has no --want"
grep -q 'key: want' "$D/agent/recipes/trader.yaml" || fail "the layer's trader.yaml has no want parameter, so devcon8 trade --want would only sell"
ok "offers and trade.sh --want are in the layer"
# The seller command and the payment gate are the repo's (devcon-workshop#84), not the pinned base's.
grep -q 'nanda offer' "$D/lib/nanda.sh" || fail "the layer's nanda.sh has no 'offer'"
grep -q 'offer-check.json' "$D/agent/bin/pay-x402" || fail "the layer's pay-x402 ignores the offer check"
grep -q 'offer_check_refusal' "$D/agent/bin/lightning" || fail "the layer's lightning ignores the offer check"
ok "nanda offer and the payment gate are in the layer"
# trade.sh runs the Studio recipe when TRADE_RECIPE is set (the layer patches it; the base image's is untouched).
grep -q 'TRADE_RECIPE:-' "$D/lib/trade.sh" || fail "the layer's trade.sh does not honour TRADE_RECIPE"
ok "trade.sh honours TRADE_RECIPE"
