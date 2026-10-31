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
(cd "$out" && sha256sum devcon-workshop-*.tar > SHA256SUMS && cat SHA256SUMS)
