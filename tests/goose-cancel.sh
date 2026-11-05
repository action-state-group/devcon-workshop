#!/usr/bin/env bash
# goose-cancel.sh: Ctrl-C in goose must stop the ACP agent's running turn, and the next typed line must reach
# the agent. The image's goose carries patches/goose-acp-cancel-abandoned-prompt.patch; an unpatched v1.57.0
# sends the agent no session/cancel and its client loop waits for the abandoned turn, so a turn that loops
# `mbx wait` never ends and the typed line never arrives (aaif-goose/goose#10619).
# Run inside the image: docker run --rm IMAGE /opt/devcon8/tests/goose-cancel.sh
set -euo pipefail
D=/opt/devcon8
T=$(mktemp -d /tmp/gc-XXXXXX); export HOME=$T; cd "$T"
mkdir -p bin .config/goose
install -m 0755 "$D/tests/goose-cancel/claude-agent-acp" bin/claude-agent-acp
printf 'GOOSE_PROVIDER: claude-acp\nGOOSE_MODEL: default\nGOOSE_TELEMETRY_ENABLED: false\n' > .config/goose/config.yaml
printf 'version: 1.0.0\ntitle: mock\ndescription: mock\ninstructions: |\n  wait\nprompt: wait\n' > recipe.yaml
export PATH="$T/bin:$D/node/bin:$D/bin:$PATH" ACP_LOG="$T/acp.log" GOOSE_MODE=auto
python3 -I "$D/tests/goose-cancel/drive.py" "$T/recipe.yaml"
