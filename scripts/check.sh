#!/usr/bin/env bash
# The repository's local check (CONTRIBUTING.md, asg-agent-team-ethan#409), and the one home of the
# image tests that image.yml's build job runs.
#
#   scripts/check.sh                    the check before every push. Runs the unit tier, then, when
#                                       this branch changes an input of the image, the image tier
#                                       too. "Changes" means a path in the diff from the merge base
#                                       with origin/main to HEAD, or an uncommitted or untracked
#                                       path, that matches image.yml's `on.push.paths` list (read
#                                       from the workflow, so the list has one home; both sides of a
#                                       rename count).
#   scripts/check.sh --unit             the unit tier only: the shellcheck call and the python and
#                                       bash unit tests. image.yml's `unit` job runs this. Needs bash,
#                                       python3 and shellcheck.
#   scripts/check.sh --full             the unit tier and the image tier, whatever changed.
#   scripts/check.sh --image-tests TAG  only the image tests, on an image already built as TAG: the
#                                       size check, the secret scan with its negative test, the
#                                       in-image tests, the console relay and S08. image.yml's build
#                                       job runs this after its build.
#
# The image tier builds linux/arm64 only (native on an Apple-silicon Mac) and runs --image-tests on
# it. It needs Docker with buildx, curl and network access for the build.
#
# Exception (coordinator ruling, asg-agent-team-ethan#409): no local tier and no pull request builds
# amd64. What it skips: the amd64 image build and its in-image tests. Why: it cannot practically run
# on Apple silicon (emulated), and it takes 80 to 110 minutes per run on CI. Where it is caught:
# image.yml's run on main builds and tests both architectures before the `image-release` approval,
# so nothing untested on amd64 is published, and a red main run opens or comments on a `ci-red`
# issue (its `report-failure` job).
#
# Exits non-zero at the first failure. Images and containers it creates carry a per-run tag or name
# and are removed, with their anonymous volumes, on exit; an image passed as TAG is kept. The build
# cache stays in Docker (`docker builder prune` reclaims it). Nothing else is touched.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() { echo "usage: scripts/check.sh [--unit | --full | --image-tests TAG]" >&2; exit 2; }
mode=auto
case "${1:-}" in
  "") [ $# -eq 0 ] || usage ;;
  --unit) [ $# -eq 1 ] || usage; mode=unit ;;
  --full) [ $# -eq 1 ] || usage; mode=full ;;
  --image-tests) [ $# -eq 2 ] || usage; mode=image; tag=$2 ;;
  *) usage ;;
esac

step() { printf '\n== %s\n' "$*"; }

unit_tests() {
  step shellcheck
  shellcheck -x -e SC1091 bin/devcon8 bin/devcon8-entry lib/*.sh agent/bin/pay-x402 tests/smoke.sh tests/goose-approve.sh tests/goose-cancel.sh tests/sim-payment.sh tests/s08-ci.sh tests/test_wallet.sh tests/mbx-net.sh tests/test_nanda.sh tests/test_nanda_offer.sh tests/test_offer_gate.sh tests/test_trade_protocol.sh tests/sim-buyer.sh tests/sim-lightning.sh tests/recipe-prompt.sh build/fetch.sh build/usb.sh
  step "mbx unit tests"
  python3 -I tests/test_mbx.py
  step "offers unit tests (fake NANDA Index, catalog and mailbox; no send before the user picks)"
  python3 -I tests/test_offers.py
  step "lightning unit tests (fake wallet API, no money moves)"
  python3 -I tests/test_lightning.py
  step "nanda against a fake gateway"
  bash tests/test_nanda.sh
  step "nanda offer against a fake gateway and Index"
  bash tests/test_nanda_offer.sh
  step "no payment while the proposal mismatches the picked offer"
  bash tests/test_offer_gate.sh
  step "trade messages against a fake gateway with the real conversation rule"
  bash tests/test_trade_protocol.sh
}

# Prints the changed paths that match image.yml's on.push.paths list, one per line. Fails when the
# list cannot be read or origin/main is missing, so a broken rule never skips the image tier quietly.
image_inputs_changed() {
  local base
  base=$(git merge-base HEAD origin/main) || { echo "check.sh: no merge base with origin/main; run git fetch origin" >&2; return 2; }
  {
    git diff --name-only --no-renames "$base" HEAD
    git diff --name-only --no-renames HEAD
    git ls-files --others --exclude-standard
  } | python3 -I -c '
import re, sys
lines = open(".github/workflows/image.yml").read().split("\n")
globs, state = [], None
for l in lines:
    if re.match(r"^on:\s*$", l): state = "on"; continue
    if state and re.match(r"^\S", l): break
    if state in ("on", "push", "paths") and re.match(r"^  \S", l):
        state = "push" if re.match(r"^  push:\s*$", l) else "on"; continue
    if state in ("push", "paths") and re.match(r"^    paths:\s*$", l): state = "paths"; continue
    if state == "paths":
        m = re.match(r"^      - (\S+)\s*$", l)
        if m: globs.append(m.group(1).strip("\"\x27")); continue
        if re.match(r"^    \S", l): state = "push"
if not globs:
    sys.exit("check.sh: cannot read on.push.paths from .github/workflows/image.yml")
# GitHub filter globs: ** matches any characters, * any characters but /.
rx = re.compile("^(" + "|".join(re.escape(g).replace(r"\*\*", "\x01").replace(r"\*", "[^/]*").replace("\x01", ".*") for g in globs) + ")$")
for p in sorted(set(sys.stdin.read().split("\n"))):
    if p and rx.match(p): print(p)
'
}

if [ "$mode" = auto ]; then
  changed=$(image_inputs_changed)
  if [ -n "$changed" ]; then
    step "this branch changes inputs of the image, so the image tier runs too:"
    printf '%s\n' "$changed"
    mode=full
  else
    mode=unit
  fi
fi

if [ "$mode" = unit ]; then
  unit_tests
  step "check passed (unit tier; no input of the image changed)"
  exit 0
fi

id=$$
neg="dw-scan-neg:check-$id"
built=""
tmp=$(mktemp -d)
containers=()
cleanup() {
  for c in ${containers[@]+"${containers[@]}"}; do docker rm -fv "$c" >/dev/null 2>&1 || true; done
  docker image rm -f "$neg" ${built:+"$built"} >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

if [ "$mode" = full ]; then
  unit_tests
  # arm64 only, on every machine: amd64 is built and tested only by image.yml's run on main.
  arch=arm64
  tag="devcon-workshop:check-$id"
  built=$tag
  step "build the image for linux/$arch (the build job's build arguments)"
  # shellcheck source=/dev/null
  . ./versions.lock
  docker buildx build --platform "linux/$arch" --load -t "$tag" \
    --build-arg BUILD_REVISION="$(git rev-parse HEAD)" \
    --build-arg MESH_LLM_SHA="$MESH_LLM_SHA" \
    --build-arg CAPSULES_COMMIT="$CAPSULES_COMMIT" \
    --build-arg CAPSULES_VERSION="$CAPSULES_VERSION" \
    --build-arg LEXE_VERSION="$LEXE_VERSION" \
    --build-arg LEXE_COMMIT="$LEXE_COMMIT" \
    .
fi

step size
bytes=$(docker image inspect "$tag" --format '{{.Size}}')
echo "uncompressed: $((bytes / 1024 / 1024)) MiB"
# Reviewed 2026-10-31 at 3.3 GiB (design section 4 asks for review over 3 GB), when models 1.1G (since moved out to `devcon8 models`) and the
# agent CLIs 0.7G after shipping each once, goose 0.2G, Go 0.3G plus go-seal's vendored modules
# 0.14G, mesh-llm and plugins 0.2G. S08 now shares the host build. Anything beyond this needs review.
[ "$bytes" -le $((3584 * 1024 * 1024)) ] || { echo "over 3.5 GiB: review before shipping"; exit 1; }

step "secret scan (negative test first, then the image)"
for f in Dockerfile env.Dockerfile key.Dockerfile; do
  docker build -q -t "$neg" -f "tests/secret-scan/$f" tests/secret-scan
  docker save "$neg" -o "$tmp/neg.tar"
  if python3 -I build/secret-scan.py "$tmp/neg.tar"; then echo "the scanner missed the secret in $f"; exit 1; fi
done
docker save "$tag" -o "$tmp/image.tar"
python3 -I build/secret-scan.py "$tmp/image.tar"
rm -f "$tmp/image.tar" "$tmp/neg.tar"

run_test() {
  step "$2 ($1.sh)"
  docker run --rm "$tag" "/opt/devcon8/tests/$1.sh"
}
run_test smoke "smoke tests"
run_test goose-approve "goose approve mode shows each card once (patched goose, mock ACP agent)"
run_test goose-cancel "Ctrl-C cancels the agent turn and the next line reaches it (patched goose, mock ACP agent)"
run_test mbx-net "the trader reaches the NANDA Index (no Cloudflare 403)"
run_test sim-payment "simulated payment seals on a test network"
run_test sim-buyer "the buyer's pay is checked with the shop as payee"
run_test sim-lightning "Lightning payment against a fake wallet (caps, paused pay, payment_received, no preimage kept)"
run_test test_wallet "the lexe wallet command and sidecar lifecycle against a fake sidecar (asks first, 0600 seed, signs up once, backup reminder)"
run_test recipe-prompt "the recipe's protocol reaches the model, in the right payment mode (both modes rendered; sent through claude-acp)"

step "the published console port serves the management routes (the relay)"
c="dw-check-relay-$id"
containers+=("$c")
docker run -d --name "$c" -p 127.0.0.1:3141:3132 "$tag" /opt/devcon8/tests/console-relay-serve.sh >/dev/null
code=000
for _ in $(seq 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 3 http://127.0.0.1:3141/api/plugins || true)
  [ "$code" = 200 ] && break
  sleep 2
done
[ "$code" = 200 ] || { docker logs "$c"; docker exec "$c" sh -c 'cat /tmp/dw-*/run.log /tmp/dw-*/.devcon8/relay.log' || true; }
docker rm -fv "$c" >/dev/null
[ "$code" = 200 ] || { echo "/api/plugins through the published port: HTTP $code"; exit 1; }

step "S08 in the container (start, console through the published port, lie, twins, referee, stop; 45 minutes at most)"
c="dw-check-s08-$id"
containers+=("$c")
deadline=$(($(date +%s) + 45 * 60))
s08_timeout() { docker logs "$c" || true; docker rm -fv "$c" >/dev/null 2>&1 || true; echo "S08 did not finish within 45 minutes"; exit 1; }
docker run -d --name "$c" -e S08_CI_HOLD=1 -p 127.0.0.1:9614:9624 "$tag" /opt/devcon8/tests/s08-ci.sh >/dev/null
until docker exec "$c" test -e /tmp/s08-started 2>/dev/null; do
  [ "$(docker inspect -f '{{.State.Running}}' "$c")" = true ] || { docker logs "$c"; exit 1; }
  [ "$(date +%s)" -lt "$deadline" ] || s08_timeout
  sleep 5
done
code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 http://127.0.0.1:9614/api/plugins || true)
docker exec "$c" touch /tmp/s08-continue
while [ "$(docker inspect -f '{{.State.Running}}' "$c")" = true ]; do
  [ "$(date +%s)" -lt "$deadline" ] || s08_timeout
  sleep 5
done
rc=$(docker inspect -f '{{.State.ExitCode}}' "$c")
docker logs "$c"
docker rm -fv "$c" >/dev/null
[ "$code" = 200 ] || { echo "s08 asker /api/plugins through the published port: HTTP $code"; exit 1; }
[ "$rc" = 0 ] || { echo "s08-ci exited $rc"; exit 1; }

if [ "$mode" = full ]; then
  step "check passed with the image tier (linux/$arch only; amd64 is built and tested only by the main run)"
else
  step "image tests passed on $tag"
fi
