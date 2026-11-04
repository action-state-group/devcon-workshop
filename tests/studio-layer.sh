#!/usr/bin/env bash
# studio-layer.sh: what the Studio layer adds to the workshop image is in place and nothing else moved.
# Run inside the Studio layer: docker run --rm IMAGE /opt/devcon8/tests/studio-layer.sh
set -euo pipefail
D=/opt/devcon8
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }
. "$D/studio/versions.lock"
if [ -z "$STUDIO_SKILLS_COMMIT" ] || [ -z "$STUDIO_TERMS_ENTRY" ]; then fail "the layer's pins are empty"; fi
"$D/studio/venv/bin/python" -I -c 'import yaml, rfc8785' || fail "PyYAML or rfc8785 missing from the layer's venv"
ok "PyYAML and rfc8785 in the layer venv"
[ "$(type -P terms)" = "$D/agent/bin/terms" ] || fail "terms is not on PATH"
[ -r "$D/agent/skills/terms-pack-author/SKILL.md" ] || fail "terms-pack-author SKILL.md missing or unreadable by $(id -un)"
[ -r "$D/agent/skills/deal/SKILL.md" ] || fail "the base image's deal skill is gone"
if [ ! -r "$D/agent/recipes/studio.yaml" ] || [ ! -r "$D/agent/recipes/trader.yaml" ]; then fail "a recipe is missing"; fi
ok "terms on PATH, both skills and both recipes readable"
# The system Python stays untouched (no pip into an externally managed Python).
python3 -c 'import yaml' 2>/dev/null && fail "PyYAML leaked into the system Python"
ok "system Python untouched"
terms --help >/dev/null || fail "terms --help failed"
ok "terms --help"
# trade.sh runs the Studio recipe when TRADE_RECIPE is set (the layer patches it; the base image's is untouched).
grep -q 'TRADE_RECIPE:-' "$D/lib/trade.sh" || fail "the layer's trade.sh does not honour TRADE_RECIPE"
ok "trade.sh honours TRADE_RECIPE"
