#!/usr/bin/env bash
# console-relay-serve.sh: a headless node on 3131 with the console relay on 3132, kept running for CI
# to curl through the published port. Run: docker run -d -p 127.0.0.1:3141:3132 IMAGE /opt/devcon8/tests/console-relay-serve.sh
set -uo pipefail
export D=/opt/devcon8 HOME=$(mktemp -d /tmp/dw-XXXXXX); export ST=$HOME/.devcon8; mkdir -p "$ST"
. "$D/lib/common.sh"
mesh_config
"$MESH" serve --port 19337 --console 3131 --headless --disable-iroh-relays > "$HOME/run.log" 2>&1 < /dev/null &
relay_start
wait
