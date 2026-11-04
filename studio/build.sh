#!/usr/bin/env bash
# build.sh [--base <ref>] [tag-suffix]: build the Terms Pack Studio layer on the pinned workshop image.
# Local only: it builds an image named devcon-workshop-studio and never pushes or tags `latest`.
set -euo pipefail
cd "$(dirname "$0")/.."
. studio/versions.lock
base=$STUDIO_BASE
if [ "${1:-}" = --base ]; then base=${2:?--base <image reference>}; shift 2; fi
[ -n "$base" ] || { echo "no base: set STUDIO_BASE in studio/versions.lock or pass --base <ref>" >&2; exit 1; }
for v in STUDIO_SKILLS_COMMIT STUDIO_TERMS_ENTRY; do
  [ -n "${!v}" ] || { echo "$v is not pinned in studio/versions.lock" >&2; exit 1; }
done
case $base in *:latest|*:latest@*) echo "refusing a moving base ($base): pin a tag and digest" >&2; exit 1 ;; esac
python3 studio/build-recipe.py --check
tag=devcon-workshop-studio:${1:-dev}
docker build -f studio/Dockerfile -t "$tag" \
  --build-arg "BASE=$base" \
  --build-arg "STUDIO_SKILLS_REPO=$STUDIO_SKILLS_REPO" \
  --build-arg "STUDIO_SKILLS_COMMIT=$STUDIO_SKILLS_COMMIT" \
  --build-arg "STUDIO_TERMS_ENTRY=$STUDIO_TERMS_ENTRY" .
echo "built $tag on $base"
