#!/usr/bin/env bash
# The repository's local check (CONTRIBUTING.md, #110), and the one home of the steps the pull
# request jobs and image.yml's build job run, so CI and the local check cannot drift.
#
#   scripts/check.sh                    the check before every push: everything the pull request
#                                       jobs run for this branch. The unit tier always; the Studio
#                                       tiers too when a changed path is on studio.yml's path list
#                                       (`studio_path`). Changed paths are the diff from the merge
#                                       base with origin/main to HEAD (both sides of a rename,
#                                       deletions included) and every uncommitted or untracked file,
#                                       read NUL-delimited, so no name can be quoted or split into a
#                                       skip; a git error fails the check.
#   scripts/check.sh --unit             the unit tier: actionlint on every workflow, the shellcheck
#                                       call and the python and bash unit tests. image.yml's `unit`
#                                       job runs this on every pull request. Needs bash, curl and
#                                       python3 (actionlint and shellcheck are fetched once, pinned).
#   scripts/check.sh --studio-unit      studio.yml's `unit` job: its shellcheck call, the generated
#                                       recipe check and the recipe render in the pinned base image.
#   scripts/check.sh --studio-layer     studio.yml's `layer` job: build the layer on the pinned base
#                                       and run demo steps 1-6 in it.
#   scripts/check.sh --full             every tier: unit, both Studio tiers and the image tier.
#   scripts/check.sh --self-test        only the self-test of the Studio path rule.
#   scripts/check.sh --image-tests TAG  only the image tests, on an image already built as TAG: the
#                                       size check, the secret scan with its negative test, the
#                                       in-image tests, the console relay and S08. image.yml's build
#                                       job runs this after its build.
#
# The image tier (`--full`) builds linux/arm64 and runs --image-tests on it. It is not part of the
# check before a push, because no pull request job runs it: image.yml's run on main builds both
# architectures and runs the same image tests before the `image-release` approval, so nothing untested
# is published, and a red main run opens or comments on a `ci-red` issue (its `report-failure` job).
# Its Rust source builds take most of an hour on a cold cache. amd64 is never built locally (it
# cannot practically run on Apple silicon); main builds and tests it.
#
# Exits non-zero at the first failure. Images and containers the image tier creates carry a per-run
# tag or name and are removed, with their anonymous volumes, on exit; an image passed as TAG is kept.
# The Studio layer is built under a per-run tag and removed too. The build cache stays in Docker
# (`docker builder prune` reclaims it).
set -euo pipefail
cd "$(dirname "$0")/.."

usage() { echo "usage: scripts/check.sh [--unit | --studio-unit | --studio-layer | --full | --self-test | --image-tests TAG]" >&2; exit 2; }
mode=auto
case "${1:-}" in
  "") [ $# -eq 0 ] || usage ;;
  --unit | --studio-unit | --studio-layer | --full | --self-test) [ $# -eq 1 ] || usage; mode=${1#--} ;;
  --image-tests) [ $# -eq 2 ] || usage; mode=image; tag=$2 ;;
  *) usage ;;
esac

step() { printf '\n== %s\n' "$*"; }

# Everything a run creates in Docker is removed on exit, pass or fail: the Studio layer's per-run tag
# here, and the image tier's images and containers through its `cleanup`.
studio_tag=""
on_exit() {
  if [ -n "$studio_tag" ]; then docker image rm -f "$studio_tag" >/dev/null 2>&1 || true; fi
  if declare -F cleanup >/dev/null; then cleanup; fi
}
trap on_exit EXIT

# The linters, pinned by version and sha256 and fetched once into the user cache (CI fetches them each
# run), so the local check and the pull request job run the same binaries: a distribution's shellcheck
# can report what another version does not. shellcheck publishes no checksums; its sums below were
# taken from the v0.11.0 release assets on 2026-11-27.
ACTIONLINT_VERSION=1.7.12
SHELLCHECK_VERSION=0.11.0

# fetch_tool NAME URL SHA256 MEMBER: prints the path of NAME, downloading URL (a .tar.gz) when it is not
# cached yet and taking MEMBER from it. Download and unpack happen in a private directory, then one
# rename publishes the binary, so a concurrent or interrupted check never runs a partly written file.
# Bounded: 20 s to connect, 120 s per attempt, three attempts, 300 s for the retries in all.
fetch_tool() {
  local name=$1 url=$2 sum=$3 member=$4 dir tmpd got
  dir="${XDG_CACHE_HOME:-$HOME/.cache}/devcon-workshop/$name-$sum"
  if [ ! -x "$dir/$name" ]; then
    mkdir -p "$dir"
    tmpd=$(mktemp -d "$dir/.tmp.XXXXXX")
    if ! curl -fsSL --connect-timeout 20 --max-time 120 --retry 2 --retry-max-time 300 -o "$tmpd/a.tgz" "$url" >&2; then
      rm -rf "$tmpd"; echo "check.sh: $name download failed" >&2; return 1
    fi
    if command -v sha256sum >/dev/null; then got=$(sha256sum "$tmpd/a.tgz" | cut -d' ' -f1); else got=$(shasum -a 256 "$tmpd/a.tgz" | cut -d' ' -f1); fi
    [ "$got" = "$sum" ] || { rm -rf "$tmpd"; echo "check.sh: $name download has sha256 $got, want $sum" >&2; return 1; }
    if ! { tar -xzf "$tmpd/a.tgz" -C "$tmpd" "$member" && [ -x "$tmpd/$member" ] && mv -f "$tmpd/$member" "$dir/$name"; }; then
      rm -rf "$tmpd"; echo "check.sh: could not unpack $name" >&2; return 1
    fi
    rm -rf "$tmpd"
  fi
  echo "$dir/$name"
}

platform() {
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) echo linux-amd64 ;;
    Linux-aarch64 | Linux-arm64) echo linux-arm64 ;;
    Darwin-arm64) echo darwin-arm64 ;;
    Darwin-x86_64) echo darwin-amd64 ;;
    *) echo "check.sh: no pinned linters for $(uname -s)-$(uname -m)" >&2; return 1 ;;
  esac
}

actionlint_bin() {
  local p sum
  p=$(platform) || return 1
  case "$p" in
    linux-amd64) sum=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 ;;
    linux-arm64) sum=325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6 ;;
    darwin-arm64) sum=aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f ;;
    darwin-amd64) sum=5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644 ;;
  esac
  fetch_tool actionlint "https://github.com/rhysd/actionlint/releases/download/v$ACTIONLINT_VERSION/actionlint_${ACTIONLINT_VERSION}_${p%-*}_${p#*-}.tar.gz" "$sum" actionlint
}

shellcheck_bin() {
  local p sum a
  p=$(platform) || return 1
  case "$p" in
    linux-amd64) a=linux.x86_64 sum=b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6 ;;
    linux-arm64) a=linux.aarch64 sum=68a8133197a50beb8803f8d42f9908d1af1c5540d4bb05fdfca8c1fa47decefc ;;
    darwin-arm64) a=darwin.aarch64 sum=339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f ;;
    darwin-amd64) a=darwin.x86_64 sum=c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51 ;;
  esac
  fetch_tool shellcheck "https://github.com/koalaman/shellcheck/releases/download/v$SHELLCHECK_VERSION/shellcheck-v$SHELLCHECK_VERSION.$a.tar.gz" "$sum" "shellcheck-v$SHELLCHECK_VERSION/shellcheck"
}

unit_tests() {
  local al sc
  step "actionlint $ACTIONLINT_VERSION on every workflow (with shellcheck $SHELLCHECK_VERSION on their run steps)"
  al=$(actionlint_bin)
  sc=$(shellcheck_bin)
  "$al" -shellcheck="$sc" .github/workflows/*.yml
  step "shellcheck $SHELLCHECK_VERSION"
  "$sc" -x -e SC1091 bin/devcon8 bin/devcon8-entry lib/*.sh agent/bin/pay-x402 tests/smoke.sh tests/goose-approve.sh tests/goose-cancel.sh tests/sim-payment.sh tests/s08-ci.sh tests/test_wallet.sh tests/mbx-net.sh tests/test_nanda.sh tests/test_nanda_offer.sh tests/test_offer_gate.sh tests/test_trade_protocol.sh tests/sim-buyer.sh tests/sim-lightning.sh tests/recipe-prompt.sh build/fetch.sh build/usb.sh scripts/check.sh .github/scripts/report-failure.sh
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
  step "self-test of the Studio path rule"
  self_test
}

# studio.yml's `unit` job.
studio_unit() {
  local sc
  step "studio: shellcheck $SHELLCHECK_VERSION"
  sc=$(shellcheck_bin)
  "$sc" -x -e SC1091 tests/studio-recipe.sh tests/studio-layer.sh tests/studio-e2e.sh tests/studio-card.sh studio/build.sh studio/run.sh studio/bin/terms studio/bin/devcon8-studio studio/bin/card studio/bin/dispute studio/bin/referee tests/studio-ruling.sh
  step "studio: studio.yaml is trader.yaml plus the Studio edits (generated file is current)"
  python3 -I tests/test_build_recipe.py
  step "studio: studio.yaml renders in both payment modes (goose of the pinned base, recipe mounted in)"
  # The layer's pinned base (studio/versions.lock), not a moving tag: `latest` can briefly lack a platform.
  # shellcheck source=/dev/null
  (. studio/versions.lock && docker run --rm \
    -v "$PWD/agent/recipes/studio.yaml:/opt/devcon8/agent/recipes/studio.yaml:ro" \
    -v "$PWD/tests/studio-recipe.sh:/opt/devcon8/tests/studio-recipe.sh:ro" \
    "$STUDIO_BASE" /opt/devcon8/tests/studio-recipe.sh)
}

# studio.yml's `layer` job: the layer on the pinned base, then demo steps 1-6 without a model against
# a replay of ten sticker trades. Nothing is pushed. The layer gets a per-run tag, so two checks at
# once (two worktrees) never test each other's layer, and a developer's own :dev tag is left alone;
# the tag is removed when the step ends.
studio_layer() {
  local t="devcon-workshop-studio:check-$$"
  studio_tag=$t # removed by on_exit
  step "studio: build the layer"
  studio/build.sh "check-$$"
  step "studio: layer contents"
  docker run --rm "$t" /opt/devcon8/tests/studio-layer.sh
  step "studio: demo steps 1-4 (tests/studio-e2e.sh)"
  docker run --rm "$t" /opt/devcon8/tests/studio-e2e.sh
  step "studio: demo step 5, the History cards and the staple (tests/studio-card.sh; waits for a checkpoint)"
  docker run --rm "$t" /opt/devcon8/tests/studio-card.sh
  step "studio: demo step 6, the dispute, the ruling and both cards (tests/studio-ruling.sh; waits for checkpoints)"
  docker run --rm "$t" /opt/devcon8/tests/studio-ruling.sh
}

# The paths that start studio.yml on a pull request (its `on.pull_request.paths`), as shell patterns.
# Keep the two lists in step by hand. A shell `*` also matches `/`, so this list can only select the
# Studio tiers more often than GitHub does, never less.
studio_path() {
  case "$1" in
    studio/* | agent/bin/mbx | agent/bin/offers | lib/trade.sh | bin/devcon8 | agent/recipes/* | \
      tests/studio-* | tests/test_build_recipe.py | scripts/check.sh | .github/workflows/studio.yml) return 0 ;;
    *) return 1 ;;
  esac
}

# Prints (shell-quoted, one per line) each changed path on the Studio list, in the git repository of
# the current directory. Fails when a git command fails, so an error never skips the Studio tiers.
studio_paths_changed() {
  local base list f
  base=$(git merge-base HEAD origin/main) || { echo "check.sh: no merge base with origin/main; run git fetch origin" >&2; return 2; }
  list=$(mktemp)
  # The three commands one by one, each checked, into one NUL-delimited list.
  if ! { git diff -z --name-only --no-renames "$base" HEAD > "$list" &&
    git diff -z --name-only --no-renames HEAD >> "$list" &&
    git ls-files -z --others --exclude-standard >> "$list"; }; then
    rm -f "$list"
    echo "check.sh: git failed listing changed paths" >&2
    return 2
  fi
  while IFS= read -r -d '' f; do
    if studio_path "$f"; then printf '%q\n' "$f"; fi
  done < "$list"
  rm -f "$list"
}

# The rule's self-test: each case is a branch in a throwaway repository with origin/main set.
self_test() {
  local root fails=0
  root=$(mktemp -d)
  g() { git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
  # case NAME EXPECT(unit|studio|error) SETUP: SETUP runs in a fresh clone of the base repository.
  case_() {
    local name=$1 want=$2 setup=$3 repo got out
    repo="$root/$RANDOM$RANDOM"
    git clone -q "$root/base" "$repo"
    (cd "$repo" && git update-ref refs/remotes/origin/main HEAD && git checkout -q -b case && eval "$setup") >/dev/null
    if out=$(cd "$repo" && studio_paths_changed 2>/dev/null); then
      if [ -n "$out" ]; then got=studio; else got=unit; fi
    else
      got=error
    fi
    if [ "$got" = "$want" ]; then echo "ok   $name -> $got"; else echo "FAIL $name -> $got, want $want: $out"; fails=$((fails + 1)); fi
  }
  mkdir -p "$root/base/docs" "$root/base/tests" "$root/base/lib" "$root/base/studio"
  (
    cd "$root/base" && git init -q -b main . &&
      echo a > docs/a.md && echo t > tests/t.sh && echo l > lib/trade.sh && echo s > studio/s.md && echo w > WORKSHOP.md &&
      g add . && g commit -q -m base
  )
  local nl=$'\n' tab=$'\t'
  case_ "docs only" unit 'echo b >> docs/a.md && echo w >> WORKSHOP.md && g commit -qam x'
  case_ "image input outside the Studio list" unit 'echo x > tests/smoke.sh && g add . && g commit -qm x'
  case_ "non-ASCII name in docs/" unit 'echo x > docs/é.md && g add . && g commit -qm x'
  case_ "tab in a name in docs/" unit "echo x > 'docs/a${tab}b.md' && g add . && g commit -qm x"
  case_ "newline name in docs/ that ends like studio/" unit "mkdir 'docs/x${nl}studio' && echo x > 'docs/x${nl}studio/y.md' && g add . && g commit -qm x"
  case_ "non-ASCII name in studio/" studio 'echo x > studio/é.md && g add . && g commit -qm x'
  case_ "newline in a name in studio/" studio "echo x > 'studio/a${nl}b.md' && g add . && g commit -qm x"
  case_ "tests/studio-* file" studio 'echo x > tests/studio-new.sh && g add . && g commit -qm x'
  case_ "rename from docs/ into studio/" studio 'g mv docs/a.md studio/a.md && g commit -qm x'
  case_ "rename from studio/ into docs/" studio 'g mv studio/s.md docs/s.md && g commit -qm x'
  case_ "deleted lib/trade.sh" studio 'g rm -q lib/trade.sh && g commit -qm x'
  case_ "uncommitted change to lib/trade.sh" studio 'echo y >> lib/trade.sh'
  case_ "untracked file in studio/" studio 'echo y > studio/new.md'
  case_ "studio.yml" studio 'mkdir -p .github/workflows && echo x > .github/workflows/studio.yml && g add . && g commit -qm x'
  case_ "scripts/check.sh" studio 'mkdir -p scripts && echo x > scripts/check.sh && g add . && g commit -qm x'
  case_ "image.yml only" unit 'mkdir -p .github/workflows && echo x > .github/workflows/image.yml && g add . && g commit -qm x'
  # shellcheck disable=SC2016 # expanded by case_'s eval, in the case's repository
  case_ "no merge base with origin/main" error 'git update-ref refs/remotes/origin/main "$(g commit-tree -m orphan "$(git hash-object -t tree /dev/null)")"'
  rm -rf "$root"
  [ "$fails" -eq 0 ] || { echo "self-test: $fails case(s) failed"; return 1; }
  echo "self-test passed"
}

case "$mode" in
  self-test)
    step "self-test of the Studio path rule"
    self_test
    exit 0 ;;
  unit) unit_tests; step "check passed (unit tier)"; exit 0 ;;
  studio-unit) studio_unit; step "check passed (studio unit)"; exit 0 ;;
  studio-layer) studio_layer; step "check passed (studio layer)"; exit 0 ;;
  auto)
    changed=$(studio_paths_changed)
    unit_tests
    if [ -n "$changed" ]; then
      step "this branch changes paths on studio.yml's list, so the Studio tiers run too:"
      printf '%s\n' "$changed"
      studio_unit
      studio_layer
      step "check passed (unit and Studio tiers)"
    else
      step "check passed (unit tier; no path on studio.yml's list changed)"
    fi
    exit 0 ;;
esac

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

if [ "$mode" = full ]; then
  unit_tests
  studio_unit
  studio_layer
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
run_test sim-lightning "Lightning payment against a fake wallet (paused pay, payment_received, no preimage kept)"
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
  step "check passed with every tier (the image tier on linux/$arch only; amd64 is built and tested only by the main run)"
else
  step "image tests passed on $tag"
fi
