#!/usr/bin/env bash
# test_trade_protocol.sh: the sticker sale's messages, buyer and seller each through mbx, against a
# fake gateway that enforces the real conversation rule (tests/fake_conversations.py): the seller may
# not confirm; the buyer confirms its own latest accept once the delivery has arrived.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
MBX=$here/../agent/bin/mbx
T=$(mktemp -d); trap 'kill "$srv" 2>/dev/null || true; rm -rf "$T"' EXIT
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 -I "$here/fake_conversations.py" "$port" & srv=$!
for _ in $(seq 50); do if curl -s -o /dev/null "http://127.0.0.1:$port/"; then break; fi; sleep 0.1; done
as() { local who=$1; shift; mkdir -p "$T/$who/.devcon8/agentbox"; printf 'tok-%s' "$who" > "$T/$who/.devcon8/agentbox/key"
       HOME=$T/$who MBX_BASE="http://127.0.0.1:$port" python3 -I "$MBX" "$@"; }
fail() { echo "FAIL $*" >&2; exit 1; }
STICKER=$here/../agent/fixtures/sticker.png
DIGEST=$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$STICKER")
TERMS='{"item":"digital fox sticker","quantity":1,"price_minor":50,"currency":"USD"}'

conv=$(as buyer send shop@agentboxnanda.org "One fox sticker, please." | jq -r .conversation)
req=$(as seller wait 5); [ "$(jq -r .kind <<<"$req")" = request ] || fail "seller got no request"
prop=$(as seller reply "$conv" proposal "Fox sticker, 50 cents." "{\"deal_id\":\"deal-1\",\"offer_digest\":\"$(printf a%.0s {1..64})\",\"terms\":$TERMS,\"content_digest\":\"$DIGEST\",\"price_cents\":50}" | jq -r .message_id)
got=$(as buyer wait 5); [ "$(jq -r '.kind+" "+.you_are+" "+.constraints.content_digest' <<<"$got")" = "proposal buyer $DIGEST" ] || fail "buyer's view of the proposal: $got"
echo '{"leg":"terms"}' > "$T/buyer-terms.json"; echo '{"success":true}' > "$T/settle.json"
as buyer reply "$conv" accept "Paid." "{\"proposalId\":\"$prop\",\"deal_id\":\"deal-1\",\"paid\":true}" --attach "$T/buyer-terms.json" --attach "$T/settle.json" >/dev/null
acc=$(as seller wait 5); [ "$(jq -r '.kind+" "+(.files|length|tostring)' <<<"$acc")" = "accept 2" ] || fail "seller's view of the accept: $acc"
# The seller may not confirm (the real gateway's 409); mbx does not even offer it.
if as seller confirm "$conv" "Delivered." 2>/dev/null; then fail "the seller could confirm"; fi
if as seller reply "$conv" confirm "Delivered." 2>/dev/null; then fail "mbx reply sent a confirm"; fi
as seller deliver "$conv" deal-1 "Your fox sticker." --attach "$STICKER" >/dev/null
d=$(as buyer wait 5)
[ "$(jq -r '.kind+" "+.conversation+" "+.you_are' <<<"$d")" = "delivery $conv buyer" ] || fail "buyer's view of the delivery: $d"
f=$(jq -r '.files[0]' <<<"$d"); [ "$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$f")" = "$DIGEST" ] || fail "delivered bytes differ"
as buyer confirm "$conv" "Received, thank you." >/dev/null || fail "the buyer's confirm was refused"
c=$(as seller wait 5); [ "$(jq -r .kind <<<"$c")" = confirm ] || fail "seller got no confirm: $c"
echo "ok   trade protocol: request, proposal, paid accept, the seller's delivery, the buyer's confirm (seller may not confirm)"
