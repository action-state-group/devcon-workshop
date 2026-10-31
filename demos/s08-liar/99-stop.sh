#!/usr/bin/env bash
# Step 99: stop all four nodes and take the lie back. Run it after every rehearsal.
set -uo pipefail
cd "$(dirname "$0")" || exit 1; . ./env.sh
ok=1; for n in asker liar referee honest; do ./node.sh stop "$n" || ok=0; done
[ "$ok" = 1 ] || { echo "a node did not stop; the lie was NOT undone. Run 99-stop.sh again."; exit 1; }
rm -f "$OMIT_TOGGLE" && echo "the liar's selective log is off"
./fake_q8.sh "$Q4_GGUF" "$(q8_path liar)" "$Q8_SHA" "$S/liar/home" --undo
# --undo leaves the liar with no Q8 file; put the real one back so the next 01-start.sh finds it.
f=$(q8_path liar); [ -e "$f" ] || { mkdir -p "$(dirname "$(readlink -m "$f")")"; cp -l "$S/models/$Q8_FILE" "$(readlink -m "$f")"; }
ss -ltn | grep -E ':96(0[1-4]|1[1-4]) ' && echo "something still listens on a demo port" || echo "all demo ports closed"
