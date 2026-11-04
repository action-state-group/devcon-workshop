#!/usr/bin/env bash
# test_wallet.sh: `devcon8 wallet` and the lexe-sidecar lifecycle behind `--pay lexe`, against a fake
# lexe-sidecar (tests/fake_sidecar.py): no Lexe account is made and no money moves. The questions
# `devcon8 wallet` asks are answered through a terminal (script), as a person would.
# Run inside the image or any Linux with bash, jq, curl, openssl, python3 and util-linux:
#   tests/test_wallet.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
T=$(mktemp -d)
fail() { echo "FAIL $*" >&2; exit 1; }
port=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
# A private copy of the image's layout, with a lexe-sidecar that is the fake one (its extra argument
# only makes the process name itself, as the real one does).
D=$T/d; mkdir -p "$D/bin" "$D/lib" "$D/agent/bin" "$T/home"
for f in "$repo"/lib/{common,wallet,trade}.sh; do sed "s#/opt/devcon8#$D#g" "$f" > "$D/lib/$(basename "$f")"; done
chmod +x "$D"/lib/*.sh
printf '#!/bin/sh\nexec python3 -I %s "${LISTEN_ADDR##*:}" "$LEXE_FAKE_LOG" lexe-sidecar\n' "$here/fake_sidecar.py" > "$D/bin/lexe-sidecar"
chmod +x "$D/bin/lexe-sidecar"
export HOME=$T/home D DEVCON8_LEXE_API=http://127.0.0.1:$port LEXE_FAKE_LOG=$T/fake.log
ST=$HOME/.devcon8; export ST
mkdir -p "$ST"
trap '"$D/lib/wallet.sh" stop >/dev/null 2>&1 || true' EXIT
w() { "$D/lib/wallet.sh" "$@"; }
asked() { # ANSWER ARGS...: run devcon8 wallet on a terminal and answer its question
  local a=$1; shift
  printf '%s\n' "$a" | script -qec "$(printf '%q ' "$D/lib/wallet.sh" "$@")" /dev/null
}

# No terminal: nothing is created.
if w < /dev/null > "$T/out" 2>&1; then fail "created a wallet with no terminal"; fi
grep -q "run 'devcon8 wallet' in a terminal" "$T/out" || { cat "$T/out"; fail "no terminal message"; }
[ ! -e "$ST/lexe/root_seed" ] || fail "a seed was made with no terminal"

# Answering no: nothing is created and Lexe is never called.
asked no > "$T/out" 2>&1 || true
[ ! -e "$ST/lexe/root_seed" ] || fail "a seed was made after 'no'"
[ ! -e "$T/fake.log" ] || fail "Lexe was called after 'no'"
grep -q "privacy-policy" "$T/out" || fail "the consent text does not name Lexe's policy"
grep -q "Removing the volume" "$T/out" || fail "the consent text has no backup reminder"

# Two terminals answering yes together make one wallet.
asked yes > "$T/out1" 2>&1 & p1=$!
asked yes > "$T/out2" 2>&1 & p2=$!
wait $p1 || true; wait $p2 || true
[ "$(grep -c '^signup$' "$T/fake.log")" = 1 ] || { cat "$T/out1" "$T/out2"; fail "two concurrent opens signed up $(grep -c '^signup$' "$T/fake.log") times"; }
seed1=$(cat "$ST/lexe/root_seed")
w stop >/dev/null 2>&1
rm -rf "$ST/lexe" "$T/fake.log"

# Answering yes: seed, sign-up, provision, balance.
asked yes > "$T/out" 2>&1 || { cat "$T/out"; fail "yes did not open the wallet"; }
seed=$ST/lexe/root_seed
[[ $(cat "$seed") =~ ^[0-9a-f]{64}$ ]] || fail "the seed is not 64 hex"
[ "$(stat -c %a "$seed")" = 600 ] && [ "$(stat -c %a "$ST/lexe")" = 700 ] || fail "seed or folder permissions"
grep -q "wallet registered with Lexe" "$T/out" || fail "no registration line"
[ "$(grep -c '^signup$' "$T/fake.log")" = 1 ] || fail "signup not called once"
grep -qx provision "$T/fake.log" || fail "provision not called"
[ -e "$ST/lexe/signed_up" ] || fail "no sign-up record"
grep -q '"balance_sats"' "$T/out" || fail "no balance"
grep -qF "$(cat "$seed")" "$T/out" && fail "the seed was printed by 'devcon8 wallet'"

# A failed provision is retried by the next open, which the error tells the person to run.
w stop >/dev/null 2>&1
touch "$T/provfail"; export FAKE_PROVISION_FAIL=$T/provfail
if w > "$T/out" 2>&1 < /dev/null; then fail "open succeeded while provisioning failed"; fi
grep -q "could not be provisioned" "$T/out" || { cat "$T/out"; fail "provision failure text"; }
w > "$T/out" 2>&1 < /dev/null || { cat "$T/out"; fail "the retry after a failed provision failed"; }
grep -q '"balance_sats"' "$T/out" || fail "no balance after the retry"
w > /dev/null 2>&1 < /dev/null
w stop >/dev/null 2>&1
w > "$T/out" 2>&1 < /dev/null || fail "reopen"

# Opening again asks nothing and signs up nothing.
w > "$T/out" 2>&1 < /dev/null || { cat "$T/out"; fail "reopening failed"; }
[ "$(grep -c '^signup$' "$T/fake.log")" = 1 ] || fail "signed up twice"

# Funding shows the backup reminder each time, then an invoice.
w fund --sats 21 > "$T/out" 2>&1 < /dev/null
grep -q "Back up your wallet's key" "$T/out" && grep -q '^lnbc' "$T/out" || { cat "$T/out"; fail "fund output"; }
w fund --sats 0 > /dev/null 2>&1 < /dev/null && fail "fund accepted 0 sats"
w key < /dev/null | grep -qF "$(cat "$seed")" || fail "key does not show the seed"

# trade --pay lexe with no wallet refuses before anything starts.
w stop >/dev/null 2>&1
mv "$ST/lexe/signed_up" "$ST/lexe/signed_up.bak"
echo '{}' > "$ST/lightning.json"
if "$D/lib/trade.sh" --pay lexe > "$T/out" 2>&1 < /dev/null; then fail "trade --pay lexe ran with no wallet"; fi
grep -q "'devcon8 wallet' opens it" "$T/out" || { cat "$T/out"; fail "trade refusal text"; }
mv "$ST/lexe/signed_up.bak" "$ST/lexe/signed_up"

# stop ends the process.
w > /dev/null 2>&1 < /dev/null
pid=$(cat "$ST/lexe/sidecar.pid"); kill -0 "$pid" || fail "wallet not running"
w stop > /dev/null
! kill -0 "$pid" 2>/dev/null || fail "wallet still running after stop"
echo "ok   wallet: asks first, makes a 0600 seed, signs up once, reminds before every funding, stops"
