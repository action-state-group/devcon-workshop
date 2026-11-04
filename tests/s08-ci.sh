#!/usr/bin/env bash
# s08-ci.sh: the S08 cast inside the image, as CI can afford it: setup, start (four nodes), twins on a
# tested question (either may part, depending on the CPU), the referee's verdict, then stop.
# Run inside the image: docker run --rm IMAGE /opt/devcon8/tests/s08-ci.sh
set -uo pipefail
fail() { echo "FAIL $*" >&2; devcon8 s08 stop >/dev/null 2>&1; exit 1; }
devcon8 models > /tmp/models.log 2>&1 || { tail -5 /tmp/models.log; fail "models"; }
devcon8 s08 setup >/dev/null || fail "setup"
timeout 1200 devcon8 s08 start > /tmp/start.log 2>&1 || { tail -20 /tmp/start.log; fail "start"; }
echo "ok   start: four nodes up"
# CI curls the asker's console through the published port (9614 -> 9621-9624 relays) from outside, then
# lets the run go on. Without the hook (a plain run) nothing waits.
if [ -n "${S08_CI_HOLD:-}" ]; then
  touch /tmp/s08-started
  for _ in $(seq 300); do [ -e /tmp/s08-continue ] && break; sleep 2; done
  [ -e /tmp/s08-continue ] || fail "CI never released the hold"
fi
timeout 300 devcon8 s08 lie > /tmp/lie.log 2>&1 || { tail -20 /tmp/lie.log; fail "lie"; }
# The Q4 model is a symlink: `s08 lie` must hash the file's real size, so "file it loads" equals the Q4_K_M hash.
got=$(sed -n 's/^  file it loads : \([0-9a-f]*\)….*/\1/p' /tmp/lie.log); want=$(sed -n 's/.*(= Q4_K_M \([0-9a-f]*\)….*/\1/p' /tmp/lie.log)
{ [ -n "$got" ] && [ "$got" = "$want" ]; } || { cat /tmp/lie.log; fail "lie: the file it loads ($got) is not the Q4_K_M it claims ($want)"; }
echo "ok   lie: the file it loads is the real Q4_K_M"
parted=""
for q in "Name three colors." "Write a haiku about the ocean."; do
  if timeout 600 devcon8 s08 twins "$q" > /tmp/twins.log 2>&1; then parted=$q; break; fi
  grep -q "twins_agree" /tmp/twins.log || { tail -20 /tmp/twins.log; fail "twins on \"$q\""; }
done
[ -n "$parted" ] || fail "neither tested question parted the twins"
echo "ok   twins parted on \"$parted\""
timeout 600 devcon8 s08 referee > /tmp/ref.log 2>&1 || { tail -20 /tmp/ref.log; fail "referee"; }
grep -q '"verdict": "contradicted:<liar>"' /tmp/ref.log || { tail -20 /tmp/ref.log; fail "verdict"; }
echo "ok   referee: contradicted:<liar>"
devcon8 s08 stop > /tmp/stop.log 2>&1 || { cat /tmp/stop.log; fail "stop"; }
grep -q "all demo ports closed" /tmp/stop.log || fail "ports still open after stop"
echo "ok   stop: all demo ports closed"
