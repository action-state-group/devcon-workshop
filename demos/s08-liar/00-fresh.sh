#!/usr/bin/env bash
# Step 0 (optional, before the show): give the asker an empty Evidence page.
# Moves the asker's whole folder (its ledger of earlier rehearsal pairs) and runs/ to old/<time>/;
# 01-start.sh then makes a new asker. Nothing is deleted. Run it only while all four are stopped.
set -uo pipefail
cd "$(dirname "$0")" || exit 1; . ./env.sh
ss -ltn | grep -qE ':96(0[1-4]|1[1-4]) ' && { echo "a demo node is still up; run 99-stop.sh first"; exit 1; }
OLD=$S/old/$(date +%m%d-%H%M%S); mkdir -p "$OLD"
for d in asker runs; do [ -e "$S/$d" ] && mv "$S/$d" "$OLD/" && echo "moved $S/$d to $OLD/$d"; done
echo "The next 01-start.sh starts a new asker with an empty ledger."
