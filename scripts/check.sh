#!/usr/bin/env bash
# The repository's local check, in two tiers (CONTRIBUTING.md, asg-agent-team-ethan#409).
#
#   scripts/check.sh          the `unit` job of image.yml, which runs this same command: shellcheck
#                             and the python and bash unit tests. Needs shellcheck, python3 and bash.
#   scripts/check.sh --full   also what the image build job runs on main: build the image for this
#                             machine's native architecture only (arm64 on an Apple-silicon Mac; it does
#                             not build the other one), check its size, run the secret scan with its
#                             negative test, then the in-image tests. Needs Docker with buildx, curl and
#                             network access for the build's downloads.
#
# Exits non-zero at the first failure. Images and containers it creates carry a per-run tag or name
# and are removed on exit; nothing else in Docker is touched.
set -euo pipefail
cd "$(dirname "$0")/.."

full=false
case "${1:-}" in
  "") ;;
  --full) full=true ;;
  *) echo "usage: scripts/check.sh [--full]" >&2; exit 2 ;;
esac

step() { printf '\n== %s\n' "$*"; }

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

$full || { step "check passed"; exit 0; }

case "$(uname -m)" in
  arm64 | aarch64) arch=arm64 ;;
  x86_64 | amd64) arch=amd64 ;;
  *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
id=$$
tag="devcon-workshop:check-$id"
neg="dw-scan-neg:check-$id"
tmp=$(mktemp -d)
containers=()
cleanup() {
  for c in ${containers[@]+"${containers[@]}"}; do docker rm -f "$c" >/dev/null 2>&1 || true; done
  docker image rm -f "$tag" "$neg" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

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

step size
bytes=$(docker image inspect "$tag" --format '{{.Size}}')
echo "uncompressed: $((bytes / 1024 / 1024)) MiB"
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

for t in smoke goose-approve goose-cancel mbx-net sim-payment sim-buyer sim-lightning test_wallet recipe-prompt; do
  step "in-image test $t.sh"
  docker run --rm "$tag" "/opt/devcon8/tests/$t.sh"
done

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
[ "$code" = 200 ] || { docker logs "$c"; echo "/api/plugins through the published port: HTTP $code"; exit 1; }
docker rm -f "$c" >/dev/null

step "S08 in the container (start, console through the published port, lie, twins, referee, stop)"
c="dw-check-s08-$id"
containers+=("$c")
docker run -d --name "$c" -e S08_CI_HOLD=1 -p 127.0.0.1:9614:9624 "$tag" /opt/devcon8/tests/s08-ci.sh >/dev/null
until docker exec "$c" test -e /tmp/s08-started 2>/dev/null; do
  [ "$(docker inspect -f '{{.State.Running}}' "$c")" = true ] || { docker logs "$c"; exit 1; }
  sleep 5
done
code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 http://127.0.0.1:9614/api/plugins || true)
docker exec "$c" touch /tmp/s08-continue
rc=$(docker wait "$c")
docker logs "$c"
[ "$code" = 200 ] || { echo "s08 asker /api/plugins through the published port: HTTP $code"; exit 1; }
[ "$rc" = 0 ] || { echo "s08-ci exited $rc"; exit 1; }

step "check --full passed (linux/$arch only; CI builds and tests amd64 and arm64 on main)"
