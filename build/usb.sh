#!/usr/bin/env bash
# usb.sh TAG OUTDIR: write the per-architecture `docker save` tarballs for the venue USB sticks,
# plus a models/ folder with the two S08 GGUF files, and a SHA256SUMS file. TAG is a published multi-arch tag (the per-arch tags are TAG-amd64, TAG-arm64).
set -euo pipefail
tag=$1 out=$2
img=ghcr.io/action-state-group/devcon-workshop
mkdir -p "$out"
# Not `docker pull` + `docker save`: with the containerd image store, a pull of the host's own architecture
# unpacks the image and drops the compressed layers, so `docker save` then writes a 15 KB tar with only the
# manifest. buildx fetches the layers from the registry again and exports them (the config blob is the registry image's).
for arch in amd64 arm64; do
  printf 'FROM %s\n' "$img:$tag-$arch" |
    docker buildx build --platform "linux/$arch" -o "type=docker,name=$img:$tag-$arch,dest=$out/devcon-workshop-$tag-$arch.tar" -
  # A tarball without layers is only kilobytes; fail here rather than on the stick.
  [ "$(wc -c < "$out/devcon-workshop-$tag-$arch.tar")" -gt 500000000 ] || { echo "devcon-workshop-$tag-$arch.tar is too small" >&2; exit 1; }
done
# The S08 models are not in the image (`devcon8 models --from DIR` loads them from this folder).
. "$(dirname "$0")/../versions.lock"
mkdir -p "$out/models"
for pair in "$Q8_FILE:$Q8_SHA256" "$Q4_FILE:$Q4_SHA256"; do
  f=${pair%%:*}
  curl -fL --retry 5 -C - -o "$out/models/$f" "https://huggingface.co/$HF_REPO/resolve/$HF_REV/$f"
done
# macOS has no sha256sum; shasum -a 256 prints the same format.
if command -v sha256sum >/dev/null; then sum=(sha256sum); else sum=(shasum -a 256); fi
# devcon8 models checks each model file against versions.lock; SHA256SUMS lists them too.
(cd "$out" && "${sum[@]}" devcon-workshop-*.tar models/*.gguf > SHA256SUMS && cat SHA256SUMS)
