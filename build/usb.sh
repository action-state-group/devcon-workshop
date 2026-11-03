#!/usr/bin/env bash
# usb.sh TAG OUTDIR: write the per-architecture `docker save` tarballs for the venue USB sticks,
# with a SHA256SUMS file. TAG is a published multi-arch tag (the per-arch tags are TAG-amd64, TAG-arm64).
set -euo pipefail
tag=$1 out=$2
img=ghcr.io/action-state-group/devcon-workshop
mkdir -p "$out"
for arch in amd64 arm64; do
  docker pull --platform "linux/$arch" "$img:$tag-$arch"
  docker save "$img:$tag-$arch" -o "$out/devcon-workshop-$tag-$arch.tar"
done
# macOS has no sha256sum; shasum -a 256 prints the same format.
if command -v sha256sum >/dev/null; then sum=(sha256sum); else sum=(shasum -a 256); fi
(cd "$out" && "${sum[@]}" devcon-workshop-*.tar > SHA256SUMS && cat SHA256SUMS)
