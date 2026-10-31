#!/usr/bin/env bash
# Step 6, the second hack: the liar keeps answering, but leaves every second exchange out of its log.
# What it does seal stays genuine: signed, chained and checkpointed, so its log passes every check.
# The liar runs capsules 0.1.6 plus redteam/selective-log.patch; this step only creates the file
# that switches the patch on (OMIT_TOGGLE in env.sh). 99-stop.sh removes it.
set -uo pipefail
cd "$(dirname "$0")" || exit 1; . ./env.sh
[ -s "$S/liar/ident" ] || { echo "the liar is not up; run 01-start.sh first"; exit 1; }
touch "$OMIT_TOGGLE" || exit 1
echo "created $OMIT_TOGGLE"
echo "From now on the liar answers every request, and seals (and pushes) only every second one."
echo "The patch, in the liar's capsules plugin (redteam/selective-log.patch):"
grep -E '^\+ .*(exists|% 2|return None)' redteam/selective-log.patch | sed 's/^+/   /'
