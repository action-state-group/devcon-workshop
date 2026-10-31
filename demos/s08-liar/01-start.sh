#!/usr/bin/env bash
# Step 1: start four honest nodes on a private mesh.
# The liar starts out honest too. Step 2 turns it into a liar.
set -uo pipefail
cd "$(dirname "$0")" || exit 1; . ./env.sh

# Never start a second cast on top of a running one (two runs on the same box collide).
# The lock is held for this run, and by the nodes it starts, which inherit it.
exec 9>"$S/.01-start.lock"
nodes=$(pgrep -u "$(id -u)" -f "$S/bin/mesh-llm serve")
if ! flock -n 9 || [ -n "$nodes" ] || ss -ltn | grep -qE ':96(0[1-4]|1[1-4]) '; then
  echo "refusing: another 01-start.sh or a demo node is already running on this box:"
  [ -n "$nodes" ] && ps -o pid,lstart,args -p "$(echo "$nodes" | paste -sd, -)" | cut -c1-120
  ss -ltn | grep -E ':96(0[1-4]|1[1-4]) '
  echo "If it is yours and finished, stop it with $S/99-stop.sh (devcon8 s08 stop)."
  echo "If someone else is running the demo, wait for them."
  exit 1
fi

rm -f "$OMIT_TOGGLE"   # every node starts out logging everything; step 6 turns the liar's omission on

# Each server gets its own copy of the real Q8_0 file, in its own Hugging Face cache.
for n in honest referee liar; do
  f=$(q8_path "$n"); blob=$S/$n/home/.cache/huggingface/hub/$HF_REPO_DIR/blobs/$Q8_SHA
  [ -e "$f" ] && continue
  mkdir -p "$(dirname "$f")" "$(dirname "$blob")"
  # The image's models are read-only: honest and referee link to them; the liar gets a real copy,
  # because 02-lie writes a padded Q4 file at its Q8 path.
  if [ "$n" = liar ]; then [ -e "$blob" ] || cp "$S/models/$Q8_FILE" "$blob" || exit 1
  else ln -sfn "$(readlink -f "$S/models/$Q8_FILE")" "$blob"; fi
  ln -sfn "../../blobs/$Q8_SHA" "$f"
  mkdir -p "$S/$n/home/.cache/huggingface/hub/$HF_REPO_DIR/refs" && echo -n "$HF_REV" > "$S/$n/home/.cache/huggingface/hub/$HF_REPO_DIR/refs/main"
done

# Up = its API lists a real model (a client also lists the "mesh" pseudo-model before it sees a server).
wait_up() { for _ in $(seq 120); do curl -fsS -m 2 "http://127.0.0.1:$(api "$1")/v1/models" 2>/dev/null | jq -e '[.data[].id | select(. != "mesh")] | length > 0' >/dev/null && return 0; sleep 2; done; echo "$1 did not come up"; return 1; }

./node.sh start honest && wait_up honest || exit 1
# The honest node made the mesh. Its invite goes to a file, never to the screen.
(umask 077; curl -fsS "http://127.0.0.1:$(console honest)/api/status" | jq -er .token > "$S/join.txt") && [ -s "$S/join.txt" ] \
  || { echo "could not read the honest node's invite"; exit 1; }
for n in liar referee; do ./node.sh start "$n" || exit 1; done
for n in liar referee; do wait_up "$n" || exit 1; done
for n in honest liar referee; do ./node.sh ident "$n" || { echo "could not identify $n"; exit 1; }; done

# Tell the referee and the asker which key each node signs with (mesh-llm 0.78 announces none).
keys=$(for n in honest liar referee; do read -r id key < "$S/$n/ident"; printf '"%s":"%s",' "$id" "$key"; done)
printf "export CAPSULES_PEER_KEYS='{%s}'\n" "${keys%,}" > "$S/referee/env"
cp "$S/referee/env" "$S/asker/env" 2>/dev/null || { mkdir -p "$S/asker"; cp "$S/referee/env" "$S/asker/env"; }
echo "export CAPSULES_ADJUDICATE_DIFFERING_TWINS=on   # ask a referee when two twins disagree" >> "$S/asker/env"
./node.sh stop referee && ./node.sh start referee && wait_up referee || exit 1
./node.sh start asker && wait_up asker && ./node.sh ident asker || exit 1

echo
echo "The mesh, as the asker sees it:"
curl -fsS "http://127.0.0.1:$(api asker)/v1/models" | jq -r '.data[].id' | grep -v '^mesh$' | sed 's/^/  model /'
for n in honest liar referee asker; do read -r id _ < "$S/$n/ident"; echo "  $n = node ${id:0:10}"; done
