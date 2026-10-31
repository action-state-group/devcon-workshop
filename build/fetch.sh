#!/usr/bin/env bash
# fetch.sh ARCH OUT: download every release asset versions.lock pins for ARCH (amd64|arm64) into OUT,
# check each sha256, and unpack it into the layout the Dockerfile copies. Fails on any mismatch.
set -euo pipefail
ARCH=$1 OUT=$2
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../versions.lock"
case $ARCH in
  amd64) A=AMD64 TRIPLE=x86_64-unknown-linux-gnu GOARCH=amd64 NODEARCH=x64 ;;
  arm64) A=ARM64 TRIPLE=aarch64-unknown-linux-gnu GOARCH=arm64 NODEARCH=arm64 ;;
  *) echo "fetch: unknown arch $ARCH" >&2; exit 2 ;;
esac
pin() { local v="${1}_SHA256_${A}"; printf '%s' "${!v}"; }
mkdir -p "$OUT/dl" && cd "$OUT"

get() { # URL SHA256 FILE
  [ -f "dl/$3" ] && echo "$2  dl/$3" | sha256sum -c --quiet - 2>/dev/null && return 0
  curl -fsSL --retry 5 --retry-delay 3 -o "dl/$3.part" "$1"
  echo "$2  dl/$3.part" | sha256sum -c --quiet - || { echo "fetch: sha256 mismatch for $1" >&2; exit 1; }
  mv "dl/$3.part" "dl/$3"
}

gh=https://github.com
get "$gh/Mesh-LLM/lexe-wallet-plugin/releases/download/$LEXE_VERSION/lexe-wallet-$LEXE_VERSION-$TRIPLE.tar.gz" "$(pin LEXE)" "lexe-wallet-$LEXE_VERSION-$TRIPLE.tar.gz"
get "$gh/action-state-group/capsule-cli/releases/download/$CAPSULECTL_VERSION/capsulectl-$CAPSULECTL_VERSION-linux-$ARCH" "$(pin CAPSULECTL)" capsulectl
get "$gh/action-state-group/evidencebook-deal/releases/download/$DEAL_VERSION/capsulectl-deal-$DEAL_VERSION-linux-$ARCH" "$(pin DEAL)" capsulectl-deal
get "$gh/action-state-group/evidencebook-deal/releases/download/$DEAL_VERSION/deal-skill-$DEAL_VERSION.tar.gz" "$DEAL_SKILL_SHA256" deal-skill.tar.gz
get "$gh/aaif-goose/goose/releases/download/$GOOSE_VERSION/goose-$TRIPLE.tar.gz" "$(pin GOOSE)" goose.tar.gz
get "https://go.dev/dl/go$GO_VERSION.linux-$GOARCH.tar.gz" "$(pin GO)" go.tar.gz
get "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$NODEARCH.tar.xz" "$(pin NODE)" node.tar.xz
get "$gh/Mesh-LLM/capsules-plugin/releases/download/v$CAPSULES_VERSION/capsules-$CAPSULES_VERSION-$TRIPLE.tar.gz" "$(pin CAPSULES)" "capsules-$CAPSULES_VERSION-$TRIPLE.tar.gz"
hf="https://huggingface.co/$HF_REPO/resolve/$HF_REV"
get "$hf/$Q8_FILE" "$Q8_SHA256" "$Q8_FILE"
get "$hf/$Q4_FILE" "$Q4_SHA256" "$Q4_FILE"

# Unpack into /opt/devcon8 layout fragments.
rm -rf opt && mkdir -p opt/bin opt/mesh/plugins opt/models opt/agent
install -m 0755 dl/capsulectl opt/bin/capsulectl
install -m 0755 dl/capsulectl-deal opt/bin/capsulectl-deal
tar -xzf dl/deal-skill.tar.gz -C opt/agent
tar -xzf dl/goose.tar.gz -C opt/bin ./goose && chmod 0755 opt/bin/goose
mkdir -p opt/go && tar -xzf dl/go.tar.gz -C opt/go --strip-components=1
mkdir -p opt/node && tar -xJf dl/node.tar.xz -C opt/node --strip-components=1
cp "dl/lexe-wallet-$LEXE_VERSION-$TRIPLE.tar.gz" opt/mesh/plugins/
cp "dl/capsules-$CAPSULES_VERSION-$TRIPLE.tar.gz" opt/mesh/plugins/ && echo "$CAPSULES_VERSION" > opt/mesh/capsules.version
cp "dl/$Q8_FILE" "dl/$Q4_FILE" opt/models/
echo "fetch: $ARCH ok"
