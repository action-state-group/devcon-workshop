#!/usr/bin/env bash
# nanda.sh <email>: create this agent's Agent Box mailbox, verify it with the six-digit code emailed
# to you, and list it in the NANDA Index (https://my.nandaindex.org/agent/SKILL.md, steps 1, 1b, 2).
# The mailbox key is a secret: it goes to ~/.devcon8/agentbox/key (0600) and is never printed.
set -euo pipefail
. /opt/devcon8/lib/common.sh
BASE=${MBX_BASE:-https://connectors-production-9b5a.up.railway.app}
A=$ST/agentbox
DESC="Devcon 8 workshop demo agent, simulated payment, not a real shop"
email=${1:-}
[[ $email == *@* ]] || die "devcon8 nanda <your email>   (a second agent needs a second address)"
mkdir -p "$A" && chmod 700 "$A"

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
if [ "$(curl -fsS "${auth[@]}" "$BASE/api/agent/mailboxes/$id" | jq -r '.mailbox.verified // .verified // false')" != true ]; then
  for _ in 1 2 3 4 5; do
    read -rp "Six-digit code from that email: " code
    out=$(curl -sS -X POST "${auth[@]}" -H 'Content-Type: application/json' -d "$(jq -nc --arg c "$code" '{code:$c}')" "$BASE/api/agent/mailboxes/$id/verify")
    [ "$(jq -r '.verified // false' <<<"$out")" = true ] && break
    echo "Not accepted: $(jq -r '.error // .message // .' <<<"$out" | head -c 120)"
  done
fi
st=$(curl -fsS "${auth[@]}" "$BASE/api/agent/mailboxes/$id")
if [ "$(jq -r '.discovery.status // .mailbox.discovery.status // empty' <<<"$st")" != indexed ]; then
  curl -fsS -X POST "${auth[@]}" -H 'Content-Type: application/json' -d '{"mode":"auto"}' "$BASE/api/agent/mailboxes/$id/nanda" >/dev/null || true
  echo "Registering in the NANDA Index (checks every 30 s, up to 10 minutes)..."
  for _ in $(seq 20); do
    s=$(curl -fsS "${auth[@]}" "$BASE/api/agent/mailboxes/$id" | jq -r '.discovery.status // .mailbox.discovery.status // empty')
    [ "$s" = indexed ] && break; sleep 30
  done
  [ "$s" = indexed ] || die "not indexed yet (status: ${s:-unknown}); rerun 'devcon8 nanda $email' later"
fi
echo "Listed in the NANDA Index as $(jq -r .address "$A/mailbox.json"). Give this address to whoever buys from you."
