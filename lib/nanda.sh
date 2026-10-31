#!/usr/bin/env bash
# nanda.sh <email>: create this agent's Agent Box mailbox, verify it with the six-digit code emailed
# to you, and list it in the NANDA Index (https://my.nandaindex.org/agent/SKILL.md, steps 1, 1b, 2).
# The mailbox key is a secret: it goes to ~/.devcon8/agentbox/key (0600) and is never printed.
set -euo pipefail
. /opt/devcon8/lib/common.sh
BASE=${MBX_BASE:-https://connectors-production-9b5a.up.railway.app}
A=$ST/agentbox
DESC="Devcon 8 workshop demo agent, simulated payment, not a real shop"
INDEX=https://api.nandaindex.org
mkdir -p "$A" && chmod 700 "$A"

# nanda_mail SUBJECT_REGEX: the token in the newest Index email whose subject matches. Only mail from
# noreply@nandaindex.org counts; the token is the only thing read from it.
nanda_mail() { # SUBJECT_REGEX AFTER_SEQ: only mail after that seq, every page; empty when none yet
  local after=$2 page found=""
  while page=$(curl -fsS "${auth[@]}" "$BASE/api/v1/inbox?after=$after&limit=50") && [ "$(jq '.messages | length' <<<"$page")" -gt 0 ]; do
    found=$(jq -r --arg re "$1" --arg prev "$found" '[.messages[] | select(.kind == "email" and .sender == "urn:ai:email:noreply@nandaindex.org"
        and (.email.subject // "" | test($re; "i"))) | .text] | last // $prev' <<<"$page")
    after=$(jq '.messages[-1].seq' <<<"$page")
  done
  grep -oE 'token=[0-9a-f]{32,128}' <<<"$found" | head -1 | cut -d= -f2 || true
}
# inbox_seq: the newest seq now, so a later nanda_mail reads only mail sent after this point.
inbox_seq() {
  local after=0 page
  while page=$(curl -fsS "${auth[@]}" "$BASE/api/v1/inbox?after=$after&limit=50") && [ "$(jq '.messages | length' <<<"$page")" -gt 0 ]; do
    after=$(jq '.messages[-1].seq' <<<"$page")
  done
  echo "$after"
}
listed() { curl -fsS "$INDEX/api/v1/resolve?locator=urn:air:host39.org:personal:$1" 2>/dev/null \
  | jq -r '.entry.extensions["org.projectnanda"].status // empty'; }

if [ "${1:-}" = leave ]; then
  # Remove the public listing. The NANDA Index made an account for the mailbox address; its reset
  # mail lands in this mailbox, so the listing's owner can sign in and delete it (tested 10-31).
  [ -s "$A/key" ] || die "no mailbox here"
  auth=(-H "Authorization: Bearer $(cat "$A/key")")
  addr=$(jq -r .address "$A/mailbox.json"); id=$(jq -r .id "$A/mailbox.json")
  org=$(curl -fsS "${auth[@]}" "$BASE/api/agent/mailboxes/$id" | jq -r '.discovery.orgId // empty')
  [ -n "$org" ] || die "the gateway names no NANDA record for $addr"
  read -rp "Remove $addr from the NANDA Index for good? [y/N] " yn; [[ $yn == [yY]* ]] || die "nothing removed"
  since=$(inbox_seq)
  curl -fsS -X POST "$INDEX/auth/forgot-password" -H 'Content-Type: application/json' -d "$(jq -nc --arg e "$addr" '{email:$e}')" >/dev/null
  tok=""; for _ in $(seq 18); do sleep 10; tok=$(nanda_mail 'reset|password' "$since"); [ -n "$tok" ] && break; done
  [ -n "$tok" ] || die "no reset email from the NANDA Index yet; run 'devcon8 nanda leave' again"
  pw=$(openssl rand -hex 16)
  curl -fsS -X POST "$INDEX/auth/reset-password" -H 'Content-Type: application/json' -d "$(jq -nc --arg t "$tok" --arg p "$pw" '{token:$t,password:$p}')" >/dev/null
  jwt=$(curl -fsS -X POST "$INDEX/auth/login" -H 'Content-Type: application/json' -d "$(jq -nc --arg e "$addr" --arg p "$pw" '{email:$e,password:$p}')" | jq -r .token)
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "$INDEX/api/v1/orgs/$org" -H "Authorization: Bearer $jwt")
  [ "$code" = 204 ] || die "the NANDA Index refused the removal (HTTP $code)"
  echo "Removed: $addr is no longer listed in the NANDA Index ($(listed "$addr" || true))."
  echo "The Agent Box mailbox itself still exists; it is simply unlisted."
  exit 0
fi

email=${1:-}
[[ $email == *@* ]] || die "devcon8 nanda <your email> | devcon8 nanda leave   (a second agent needs a second address)"

if [ ! -s "$A/key" ]; then
  cat <<TXT
Before you sign up:
  - Your agent gets its own address at agentboxnanda.org and a PUBLIC listing in the NANDA Index,
    with the description: "$DESC".
  - The listing shows the mailbox address, not your email. Your email gets one code, once.
  - The listing stays after the workshop until you remove it (README, "Leaving the NANDA Index").
TXT
  read -rp "Create the mailbox for $email? [y/N] " yn; [[ $yn == [yY]* ]] || die "nothing created"
  body=$(jq -nc --arg e "$email" --arg d "$DESC" '{email:$e, displayName:"Devcon 8 workshop agent", assistant:"goose (devcon-workshop)", description:$d}')
  r=$(curl -fsS -X POST "$BASE/api/agent/mailboxes" -H 'Content-Type: application/json' -d "$body") || die "mailbox creation failed (try again in a minute)"
  (umask 077; jq -r .token <<<"$r" > "$A/key"; jq '{id: .mailbox.id, address: .mailbox.emailAddress, existing: (.existing // false)}' <<<"$r" > "$A/mailbox.json")
  if [ ! -s "$A/key" ] || [ "$(cat "$A/key")" = null ]; then rm -f "$A/key"; die "the gateway returned no key"; fi
  [ "$(jq -r .existing "$A/mailbox.json")" = true ] && echo "This email already has a mailbox; you are joining it as another assistant."
  echo "Your agent's address: $(jq -r .address "$A/mailbox.json"). A six-digit code went to $(jq -r .codeSentTo <<<"$r")."
fi
id=$(jq -r .id "$A/mailbox.json")
auth=(-H "Authorization: Bearer $(cat "$A/key")")
verified() { [ "$(curl -fsS "${auth[@]}" "$BASE/api/agent/mailboxes/$id" | jq -r '.mailbox.verified // .verified // false')" = true ]; }
if ! verified; then
  for _ in 1 2 3 4 5; do
    read -rp "Six-digit code from that email: " code
    out=$(curl -sS -X POST "${auth[@]}" -H 'Content-Type: application/json' -d "$(jq -nc --arg c "$code" '{code:$c}')" "$BASE/api/agent/mailboxes/$id/verify")
    [ "$(jq -r '.verified // false' <<<"$out")" = true ] && break
    echo "Not accepted: $(jq -r '.error.code // .error // .message // "unknown"' <<<"$out" | head -c 80)"
  done
  verified || die "the mailbox is not verified; rerun 'devcon8 nanda $email' for a fresh code"
fi
addr=$(jq -r .address "$A/mailbox.json")
if [ "$(listed "$addr")" != active ]; then
  curl -fsS -X POST "${auth[@]}" -H 'Content-Type: application/json' -d '{"mode":"auto"}' "$BASE/api/agent/mailboxes/$id/nanda" >/dev/null || true
  since=$(inbox_seq)
  echo "Registering in the NANDA Index (up to 10 minutes)..."
  for i in $(seq 20); do
    [ "$(listed "$addr")" = active ] && break
    # The gateway should follow the Index's two verification emails itself. On 10-31 it did not, so
    # after two minutes this step completes them from the mailbox, as the gateway would.
    if [ "$i" -ge 4 ]; then
      # The account mail may predate this run (an earlier, unfinished signup), so it is read from 0.
      t=$(nanda_mail 'verify your nanda index account' 0)
      if [ -n "$t" ]; then curl -fsS -X POST "$INDEX/auth/verify-account" -H 'Content-Type: application/json' -d "$(jq -nc --arg t "$t" '{token:$t}')" >/dev/null 2>&1 || true; fi
      t=$(nanda_mail 'verify your nanda index registration' "$since")
      if [ -n "$t" ]; then curl -fsS -X POST "$INDEX/api/v1/verify-email" -H 'Content-Type: application/json' -d "$(jq -nc --arg t "$t" '{token:$t}')" >/dev/null 2>&1 || true; fi
    fi
    sleep 30
  done
  [ "$(listed "$addr")" = active ] || die "not listed yet; rerun 'devcon8 nanda $email' later"
fi
echo "Listed in the NANDA Index as $addr. Give this address to whoever buys from you."
echo "To remove the listing later: devcon8 nanda leave"
