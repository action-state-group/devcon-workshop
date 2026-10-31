#!/usr/bin/env bash
# mbx-net.sh: the trader's NANDA Index calls get through from inside the image (needs the network).
# Cloudflare in front of the Index refused urllib's default User-Agent with 403 (error 1010); this
# fails if that comes back. It resolves an address nobody owns, so it needs no listing to exist.
set -euo pipefail
HOME=$(mktemp -d /tmp/mn-XXXXXX); export HOME
out=$(mbx resolve nobody-devcon-ci-check@agentboxnanda.org) || { echo "FAIL mbx resolve: $out" >&2; exit 1; }
[ "$(jq -r .listed <<<"$out")" = false ] || { echo "FAIL unexpected answer: $out" >&2; exit 1; }
echo "ok   mbx resolve reaches the NANDA Index (unknown address -> listed false)"
