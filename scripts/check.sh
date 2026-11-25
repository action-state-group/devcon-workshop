#!/usr/bin/env bash
# The repository's local check, in two tiers (CONTRIBUTING.md, asg-agent-team-ethan#409), and the
# one home of the image tests that image.yml's build job runs.
#
#   scripts/check.sh                    the `unit` job of image.yml, which runs this same command:
#                                       the shellcheck call and the python and bash unit tests.
#                                       Needs shellcheck, python3 and bash.
#   scripts/check.sh --full             the unit tier, then builds the image for this machine's
#                                       native architecture only (arm64 on an Apple-silicon Mac; it
#                                       does not build amd64) and runs --image-tests on it. Needs
#                                       Docker with buildx, curl and network access for the build.
#   scripts/check.sh --image-tests TAG  only the image tests, on an image already built as TAG: the
#                                       size check, the secret scan with its negative test, the
#                                       in-image tests, the console relay and S08. image.yml's build
#                                       job runs this after its build.
#
# Exits non-zero at the first failure. Images and containers it creates carry a per-run tag or name
# and are removed, with their anonymous volumes, on exit; an image passed as TAG is kept. The build
# cache of --full stays in Docker (`docker builder prune` reclaims it). Nothing else is touched.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() { echo "usage: scripts/check.sh [--full | --image-tests TAG]" >&2; exit 2; }
mode=unit
case "${1:-}" in
  "") [ $# -eq 0 ] || usage ;;
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

if [ "$mode" = unit ]; then
  unit_tests
  step "check passed"
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
  case "$(uname -m)" in
    arm64 | aarch64) arch=arm64 ;;
    x86_64 | amd64) arch=amd64 ;;
    *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
  esac
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
  step "check --full passed (linux/$arch only; amd64 is built and tested only by the main run)"
else
  step "image tests passed on $tag"
fi
