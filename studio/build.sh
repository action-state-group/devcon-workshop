#!/usr/bin/env bash
# build.sh [--base <ref>] [tag-suffix]: build the Terms Pack Studio layer on the pinned workshop image.
# Local only: it builds an image named devcon-workshop-studio and never pushes or tags `latest`.
set -euo pipefail
cd "$(dirname "$0")/.."
. studio/versions.lock
base=$STUDIO_BASE
if [ "${1:-}" = --base ]; then base=${2:?--base <image reference>}; shift 2; fi
[ -n "$base" ] || { echo "no base: set STUDIO_BASE in studio/versions.lock or pass --base <ref>" >&2; exit 1; }
for v in STUDIO_SKILLS_COMMIT STUDIO_TERMS_ENTRY STUDIO_DEAL_REPO STUDIO_DEAL_COMMIT; do
  [ -n "${!v}" ] || { echo "$v is not pinned in studio/versions.lock" >&2; exit 1; }
done
# Only an immutable digest: a bare name means `latest`, and any tag can move.
if ! [[ $base =~ @sha256:[0-9a-f]{64}$ ]]; then echo "refusing a base that is not pinned by digest ($base): use <image>@sha256:<64 hex>" >&2; exit 1; fi
python3 studio/build-recipe.py --check
tag=devcon-workshop-studio:${1:-dev}
docker build -f studio/Dockerfile -t "$tag" \
  --build-arg "BASE=$base" \
  --build-arg "STUDIO_SKILLS_REPO=$STUDIO_SKILLS_REPO" \
  --build-arg "STUDIO_SKILLS_COMMIT=$STUDIO_SKILLS_COMMIT" \
  --build-arg "STUDIO_TERMS_ENTRY=$STUDIO_TERMS_ENTRY" \
  --build-arg "STUDIO_DEAL_REPO=$STUDIO_DEAL_REPO" \
  --build-arg "STUDIO_DEAL_COMMIT=$STUDIO_DEAL_COMMIT" .
echo "built $tag on $base"
