#!/usr/bin/env bash
# goose-approve.sh: goose in approve mode with an ACP agent that asks permission for one tool call must
# show that card once and finish the turn. The image's goose carries patches/goose-acp-approval-card-once.patch;
# an unpatched v1.57.0 shows the card again after the turn and exits when it is answered (aaif-goose/goose#13273).
# Run inside the image: docker run --rm IMAGE /opt/devcon8/tests/goose-approve.sh
set -euo pipefail
D=/opt/devcon8
T=$(mktemp -d /tmp/ga-XXXXXX); export HOME=$T; cd "$T"
mkdir -p bin .config/goose
install -m 0755 "$D/tests/goose-approve/claude-agent-acp" bin/claude-agent-acp
printf 'GOOSE_PROVIDER: claude-acp\nGOOSE_MODEL: default\nGOOSE_TELEMETRY_ENABLED: false\n' > .config/goose/config.yaml
printf 'version: 1.0.0\ntitle: mock\ndescription: mock\ninstructions: |\n  run the tool\nprompt: run the tool\n' > recipe.yaml
export PATH="$T/bin:$D/node/bin:$D/bin:$PATH"
GOOSE_MODE=approve python3 -I "$D/tests/goose-approve/drive.py" "$T/recipe.yaml"
