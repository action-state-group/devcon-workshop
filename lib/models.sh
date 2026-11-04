#!/usr/bin/env bash
# models.sh [--from DIR] [--check]: fetch the two Qwen GGUF files the S08 demo needs into the volume
# (~/.devcon8/models). Pins and sha256 come from versions.lock; a present, verified file is skipped, a
# partial download resumes. --from DIR copies the files from a folder (the USB stick) instead of downloading.
set -euo pipefail
. /opt/devcon8/lib/common.sh
. "$D/versions.lock"
M=$ST/models
FROM="" CHECK=""
while [ $# -gt 0 ]; do
  case $1 in
    --from) [ -n "${2:-}" ] || die "devcon8 models --from <dir>"; FROM=$2; shift 2 ;;
    --check) CHECK=1; shift ;;
    -h|--help|help) echo "devcon8 models [--from DIR] [--check]   download (or copy from DIR) the S08 models into $M"; exit 0 ;;
    *) die "devcon8 models [--from DIR] [--check]" ;;
  esac
done
mkdir -p "$M"
sha_ok() { [ -f "$1" ] && [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$2" ]; }
get() { # FILE SHA256
  local f=$1 sha=$2 dest=$M/$1
  if sha_ok "$dest" "$sha"; then echo "ok       $f (already here, sha256 checked)"; return 0; fi
  [ -z "$CHECK" ] || { echo "MISSING  $f"; return 1; }
  rm -f "$dest"
  if [ -n "$FROM" ]; then
    [ -f "$FROM/$f" ] || die "$FROM/$f not found"
    echo "copying  $f ($(( $(stat -c %s "$FROM/$f") / 1048576 )) MB) from $FROM"
    cp "$FROM/$f" "$dest.part"
  else
    echo "fetching $f from huggingface.co (resumes if interrupted)"
    curl -fL --retry 5 --retry-delay 3 -C - --progress-bar -o "$dest.part" \
      "https://huggingface.co/$HF_REPO/resolve/$HF_REV/$f" || die "download of $f failed; run devcon8 models again to resume"
  fi
  if ! sha_ok "$dest.part" "$sha"; then rm -f "$dest.part"; die "$f failed its sha256 check (expected $sha); run devcon8 models again"; fi
  mv "$dest.part" "$dest"
  echo "ok       $f"
}
rc=0
get "$Q8_FILE" "$Q8_SHA256" || rc=1
get "$Q4_FILE" "$Q4_SHA256" || rc=1
[ "$rc" = 0 ] || exit 1
[ -n "$CHECK" ] || echo "Models are in $M. Next: devcon8 s08 setup"
