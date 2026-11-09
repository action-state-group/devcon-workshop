#!/usr/bin/env bash
# nanda.sh <email>: create this agent's Agent Box mailbox, verify it with the six-digit code emailed
# to you, and list it in the NANDA Index (https://my.nandaindex.org/agent/SKILL.md, steps 1, 1b, 2).
# The mailbox key is a secret: it goes to ~/.devcon8/agentbox/key (0600) and is never printed.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/common.sh"
BASE=${MBX_BASE:-https://connectors-production-9b5a.up.railway.app}
A=$ST/agentbox
DESC="Devcon 8 workshop demo agent, not a real shop: payment simulated by default, real Lightning only if both sides run it"
INDEX=${NANDA_INDEX:-https://api.nandaindex.org}
URN=urn:air:host39.org:personal:
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
  while :; do
    page=$(curl -fsS "${auth[@]}" "$BASE/api/v1/inbox?after=$after&limit=50") || return 1
    [ "$(jq '.messages | length' <<<"$page")" -gt 0 ] || break
    after=$(jq '.messages[-1].seq' <<<"$page")
  done
  echo "$after"
}
listed() { curl -fsS "$INDEX/api/v1/resolve?locator=urn:air:host39.org:personal:$1" 2>/dev/null \
  | jq -r '.entry.extensions["org.projectnanda"].status // empty'; }

# index_login: sign in to this mailbox's NANDA Index account and set $addr, $org and $jwt. The Index made
# the account for the mailbox address and its reset mail lands in this mailbox, so the mailbox's owner can
# sign in (tested 10-31). Each sign-in sets a new random password that is used once and not kept.
index_login() {
  [ -s "$A/key" ] || die "no mailbox here: run 'devcon8 nanda <your email>' first"
  auth=(-H "Authorization: Bearer $(cat "$A/key")")
  addr=$(jq -r .address "$A/mailbox.json"); id=$(jq -r .id "$A/mailbox.json")
  org=$(curl -fsS "${auth[@]}" "$BASE/api/agent/mailboxes/$id" | jq -r '.discovery.orgId // empty')
  [ -n "$org" ] || die "the gateway names no NANDA record for $addr"
  since=$(inbox_seq)
  curl -fsS -X POST "$INDEX/auth/forgot-password" -H 'Content-Type: application/json' -d "$(jq -nc --arg e "$addr" '{email:$e}')" >/dev/null
  tok=""; for _ in $(seq 18); do tok=$(nanda_mail 'reset|password' "$since"); [ -n "$tok" ] && break; sleep 10; done
  [ -n "$tok" ] || die "no reset email from the NANDA Index yet; run the command again"
  pw=$(openssl rand -hex 16)
  curl -fsS -X POST "$INDEX/auth/reset-password" -H 'Content-Type: application/json' -d "$(jq -nc --arg t "$tok" --arg p "$pw" '{token:$t,password:$p}')" >/dev/null
  jwt=$(curl -fsS -X POST "$INDEX/auth/login" -H 'Content-Type: application/json' -d "$(jq -nc --arg e "$addr" --arg p "$pw" '{email:$e,password:$p}')" | jq -r .token)
}

if [ "${1:-}" = leave ]; then
  # Remove the public listing. The Index made an account for the mailbox address; its reset mail lands in
  # this mailbox, so the listing's owner can sign in and delete it (tested 10-31).
  [ -s "$A/key" ] || die "no mailbox here"
  addr=$(jq -r .address "$A/mailbox.json")
  cat <<TXT
This deletes $addr's NANDA Index listing for good. It cannot be undone: the gateway will not list this
mailbox again (tested 2026-10-31), so to take part again you need a new email address and a new mailbox.
The mailbox itself stays, unlisted; other agents can no longer reach it through the Index.
TXT
  read -rp "Delete the listing for good? [y/N] " yn; [[ $yn == [yY]* ]] || die "nothing removed"
  index_login
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "$INDEX/api/v1/orgs/$org" -H "Authorization: Bearer $jwt")
  [ "$code" = 204 ] || die "the NANDA Index refused the removal (HTTP $code)"
  echo "Removed: $addr is no longer listed in the NANDA Index ($(listed "$addr" || true))."
  echo "The Agent Box mailbox itself still exists, unlisted. To take part again, use a new email address."
  exit 0
fi

if [ "${1:-}" = offer ]; then
  # Publish (or with --remove, clear) this seller's offer in its own Index record, where `offers find` reads it:
  # trust_manifest.metadata.offer, a public format ruled on by Steven (devcon-workshop#84). It is opt-in:
  # nothing else in devcon8 writes it.
  shift
  remove=0 rail=x402 history=0
  while [ $# -gt 0 ]; do
    case $1 in
      --remove) remove=1; shift ;;
      --history) history=1; shift ;;
      --rail) rail=${2:-}; [ "$rail" = x402 ] || [ "$rail" = lightning ] || die "--rail x402 or lightning"; shift 2 ;;
      *) die "devcon8 nanda offer [--rail x402|lightning] [--history]   |   devcon8 nanda offer --remove" ;;
    esac
  done
  [ -s "$A/key" ] || die "no mailbox here: run 'devcon8 nanda <your email>' first"
  addr=$(jq -r .address "$A/mailbox.json")
  if [ "$remove" = 1 ]; then
    offer=null
    echo "This clears the offer from your Index record, $addr. Anyone who already read or cached it still has that copy: it cannot be recalled."
    echo "It also signs in through your mailbox and sets a NEW password on your Index account; cardValidation, if it changed when you published, stays."
    read -rp "Clear the offer? [y/N] " yn; [[ $yn == [yY]* ]] || die "nothing changed"
  else
    if [ "$rail" = lightning ]; then
      msat=$("$D/agent/bin/lightning" caps | jq -er .price_msat) || die "a Lightning offer needs your price first: devcon8 lightning --price-sats P --per-payment-sats N --total-sats T"
      price=$(jq -nc --argjson a "$msat" '{amount:$a, unit:"msat"}')
    else
      price='{"amount":50,"unit":"usd_cent"}'
    fi
    # The History card (Studio step 5) is announced only when asked for (--history), and then the seller's
    # proposals must carry it: a buyer treats an announced card that does not come as a mismatch and does not pay.
    hist=false hkey=""
    if [ "$history" = 1 ]; then
      staple=$HOME/studio/cards/stapled/history-staple.json
      if [ -s "$staple" ]; then hkey=$(jq -er '.staple.reply.responder' "$staple" 2>/dev/null) || hkey=""; fi
      [ -n "$hkey" ] || die "--history needs a card staple first (Studio step 5: card staple)"
      hist=true
    fi
    offer=$(jq -nc --arg i "digital fox sticker" --argjson p "$price" --arg r "$rail" --argjson h "$hist" --arg k "$hkey" \
      '{v:0, item:$i, price:$p, rail:$r, historyStaple:$h} + (if $h then {historyKey:$k} else {} end)')
    cat <<TXT
This publishes the following in your public NANDA Index record, $addr. Anyone who can read the Index sees it,
and it is the seller's claim: the listed price is advisory, and a buyer checks it against your proposal.
  $offer
'devcon8 nanda offer --remove' clears it again, but cannot recall copies others have already read or cached.
Publishing signs in to your Index account through your mailbox, which sets a NEW password on it (a password you set yourself stops working),
and the Index re-checks your agent card, so your listing may then show cardValidation "invalid"; --remove does not undo that.
TXT
    read -rp "Publish this offer? [y/N] " yn; [[ $yn == [yY]* ]] || die "nothing published"
  fi
  index_login
  rec=$(curl -fsS "$INDEX/api/v1/orgs/$org" -H "Authorization: Bearer $jwt") || die "could not read your Index record"
  # Change only trust_manifest.metadata.offer; the rest of the record is sent back as it was read.
  body=$(jq -c --argjson o "$offer" '
      {display_name, description, tags, ttl_seconds, version, extensions, entry_data, registry_url, domain}
      | with_entries(select(.value != null))
      | .trust_manifest = ((($rec.trust_manifest // {}) | .metadata = ((.metadata // {}) | if $o == null then del(.offer) else .offer = $o end)))' \
    --argjson rec "$rec" <<<"$rec")
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "$INDEX/api/v1/orgs/$org" -H "Authorization: Bearer $jwt" -H 'Content-Type: application/json' -d "$body")
  [ "$code" = 200 ] || die "the NANDA Index refused the update (HTTP $code)"
  stored=$(curl -fsS "$INDEX/api/v1/resolve?locator=$URN$addr" | jq -c '.entry.trustManifest.metadata.offer // null')
  if [ "$remove" = 1 ]; then
    [ "$stored" = null ] || die "the Index still shows an offer for $addr: $stored"
    echo "Cleared: the Index shows no offer for $addr."
  else
    # The Index writes keys in camelCase and in its own order, so the two are compared as sorted JSON.
    [ "$(jq -cS . <<<"$stored")" = "$(jq -cS . <<<"$offer")" ] || die "the Index did not keep the offer as sent (it shows: $stored)"
    echo "Published: the Index shows your offer for $addr. Buyers' 'offers find' reads it."
  fi
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
  - The listing stays after the workshop until you remove it with 'devcon8 nanda leave', which is permanent:
    this mailbox cannot be listed again (README, "Leaving the NANDA Index").
TXT
  read -rp "Create the mailbox for $email? [y/N] " yn; [[ $yn == [yY]* ]] || die "nothing created"
  created=1
  body=$(jq -nc --arg e "$email" --arg d "$DESC" '{email:$e, displayName:"Devcon 8 workshop agent", assistant:"goose (devcon-workshop)", description:$d}')
  r=$(curl -fsS -X POST "$BASE/api/agent/mailboxes" -H 'Content-Type: application/json' -d "$body") || die "mailbox creation failed (try again in a minute)"
  (umask 077; jq -r .token <<<"$r" > "$A/key"; jq '{id: .mailbox.id, address: .mailbox.emailAddress, existing: (.existing // false)}' <<<"$r" > "$A/mailbox.json")
  if [ ! -s "$A/key" ] || [ "$(cat "$A/key")" = null ]; then rm -f "$A/key"; die "the gateway returned no key"; fi
  echo "Your agent's address: $(jq -r .address "$A/mailbox.json"). A six-digit code went to $(jq -r .codeSentTo <<<"$r")."
fi
id=$(jq -r .id "$A/mailbox.json")
auth=(-H "Authorization: Bearer $(cat "$A/key")")
# Whether THIS key is verified. The gateway's GET /mailboxes/<id> reports only mailbox.verified (the
# mailbox's email, proven once by any assistant), not this key's grant: a key that rejoined an
# existing mailbox reads true there and is still refused ("not_verified"). Only this key's own
# /verify answer counts, so it is recorded here when it says verified.
verified() { [ -f "$A/verified" ]; }
if ! verified && [ -z "${created:-}" ]; then
  # A key an older image verified has no marker. (A key made in this run is never probed: it has just
  # been sent its code, and the gateway's duty answer for a new, on-duty assistant is not known.) Ask the gateway about this key itself: it grants a
  # verified key the duty and refuses an unverified one with 409 not_verified (seen 10-31). Taking the
  # duty is what this step does anyway.
  case $(curl -sS -o /dev/null -w '%{http_code}' -X POST "${auth[@]}" "$BASE/api/agent/mailboxes/$id/duty") in
    2??) touch "$A/verified" ;;
  esac
fi
if ! verified; then
  for _ in 1 2 3 4 5; do
    read -rp "Six-digit code from that email: " code
    out=$(curl -sS -X POST "${auth[@]}" -H 'Content-Type: application/json' -d "$(jq -nc --arg c "$code" '{code:$c}')" "$BASE/api/agent/mailboxes/$id/verify")
    if [ "$(jq -r '.verified // false' <<<"$out")" = true ]; then touch "$A/verified"; break; fi
    echo "Not accepted: $(jq -r '.error.code // .error // .message // "unknown"' <<<"$out" | head -c 80)"
  done
  verified || die "this agent's key is not verified. For a new code: rm -r ~/.devcon8/agentbox, then 'devcon8 nanda $email' again"
fi
# A mailbox joined again (after 'rm -r ~/.devcon8/agentbox') starts off duty, and another assistant
# would answer (SKILL.md rule 4). This agent is the one that answers, so every run makes sure of it.
if [ "$(curl -fsS "${auth[@]}" "$BASE/api/v1/me" | jq -r '.onDuty | tostring')" = false ]; then
  curl -fsS -X POST "${auth[@]}" "$BASE/api/agent/mailboxes/$id/duty" >/dev/null \
    || die "could not take over the mailbox from its other assistant; rerun 'devcon8 nanda $email'"
  echo "This agent now answers for $(jq -r .address "$A/mailbox.json")."
fi
# A mailbox joined from a new volume has history from earlier runs; `mbx wait` reads from its cursor
# (0 when the file is missing) and would replay all of it into a trade. Start after the newest message.
# An existing cursor (same volume) is left alone.
if [ ! -f "$A/cursor" ]; then
  seq=$(inbox_seq) || die "could not read the mailbox history; rerun 'devcon8 nanda $email'"
  echo "$seq" > "$A/cursor"
fi
addr=$(jq -r .address "$A/mailbox.json")
if [ "$(listed "$addr")" != active ]; then
  curl -fsS -X POST "${auth[@]}" -H 'Content-Type: application/json' -d '{"mode":"auto"}' "$BASE/api/agent/mailboxes/$id/nanda" >/dev/null || true
  echo "Registering in the NANDA Index (up to 10 minutes)..."
  for i in $(seq 20); do
    [ "$(listed "$addr")" = active ] && break
    # The gateway should follow the Index's two verification emails itself. On 10-31 it did not, so
    # after two minutes this step completes them from the mailbox, as the gateway would.
    if [ "$i" -ge 4 ]; then
      # Both mails may predate this run (an earlier, unfinished signup), so both are read from the
      # start of the mailbox; nanda_mail takes the newest match.
      t=$(nanda_mail 'verify your nanda index account' 0)
      if [ -n "$t" ]; then curl -fsS -X POST "$INDEX/auth/verify-account" -H 'Content-Type: application/json' -d "$(jq -nc --arg t "$t" '{token:$t}')" >/dev/null 2>&1 || true; fi
      t=$(nanda_mail 'verify your nanda index registration' 0)
      if [ -n "$t" ]; then curl -fsS -X POST "$INDEX/api/v1/verify-email" -H 'Content-Type: application/json' -d "$(jq -nc --arg t "$t" '{token:$t}')" >/dev/null 2>&1 || true; fi
    fi
    sleep 30
  done
  [ "$(listed "$addr")" = active ] || die "not listed yet; rerun 'devcon8 nanda $email' later"
fi
echo "Listed in the NANDA Index as $addr. Give this address to whoever buys from you."
echo "To remove the listing later: devcon8 nanda leave"
