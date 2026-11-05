#!/usr/bin/env bash
# studio-e2e.sh: demo steps 1-4 without a model, in the Studio layer.
#   1 look/rehearse   devcon8-studio replay (ten past sticker sales), write the terms, lint, test, run --dry-run
#   2 change/compare  change "within 1 day" to 2, run again, compare the two runs
#   3 deploy          publish the terms and pin them on the deal profile
#   4 live            deal check names the row that fails
# Also asserts the verbs (up to publish) write nothing outside ~/studio.
# Run inside the layer, as its own user: docker run --rm IMAGE /opt/devcon8/tests/studio-e2e.sh
set -euo pipefail
D=/opt/devcon8
PLUGINS=/usr/local/lib/capsulectl/plugins
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }

work=$(mktemp -d)
export HOME=$work/home XDG_CONFIG_HOME=$work/config
mkdir -p "$HOME" "$work/config"

devcon8-studio replay >"$work/replay.out" || fail "replay failed: $(cat "$work/replay.out")"
seller=$HOME/studio/replay/seller
[ "$(XDG_CONFIG_HOME=$seller capsulectl --profile deal deal list --json | jq '[.[] | select(.kind == "deal")] | length')" = 10 ] || fail "the replay did not leave ten sales"
devcon8-studio replay >"$work/replay2.out" || fail "a second replay failed"
grep -q "nothing to do" "$work/replay2.out" || fail "a second replay is not a no-op: $(cat "$work/replay2.out")"
ok "ten past sticker sales replayed once; a second replay is a no-op"

# Everything the verbs write must land in ~/studio. Mark the time, check at the end of step 2
# (publish writes only there too; the install after it is the one named exception).
mkdir -p "$HOME/studio/packs/sticker-sale"
marker=$work/marker; touch "$marker"; sleep 1
pack=$HOME/studio/packs/sticker-sale/pack-source.yaml
# The pack source is the skill's own example, so the test cannot drift from what the model is told.
awk '/^```yaml$/{f=1;next} /^```$/{f=0} f' "$D/agent/skills/terms-pack-author/SKILL.md" >"$pack"
[ -s "$pack" ] || fail "no pack example in the terms-pack-author skill"

# A rehearsal changes no deal and no store: the replayed seller's and buyer's files hash the same after both runs and after publish.
store_hash() { (cd "$HOME/studio/replay" && find seller buyer -type f ! -name '*.lock' -print0 | sort -z | xargs -0 sha256sum | sha256sum); }
store_before=$(store_hash)
cd "$HOME/studio"
lint=$(terms lint "$pack"); [ "$(jq -r .valid <<<"$lint")" = true ] || fail "lint: $lint"
test_=$(terms test "$pack"); [ "$(jq -r .passed <<<"$test_")" = true ] || fail "test: $test_"
run1=$(terms run "$pack" --store "$seller" --dry-run)
[ "$(jq -r '.sales' <<<"$run1")" = 10 ] || fail "run read $(jq -r .sales <<<"$run1") sales, not 10: $run1"
[ "$(jq -r '.rehearsal' <<<"$run1")" = true ] || fail "a --dry-run is not a rehearsal: $run1"
ok "step 1: $(jq -r '"\(.came_through) of \(.sales) came through, missed \(.missed|length), could not decide \(.could_not_decide|length)"' <<<"$run1")"
[ "$(terms verify "$(jq -r .page <<<"$run1")" | jq -r .verified)" = true ] || fail "the report page does not verify"

sed -i 's/within 1 day/within 2 days/; s/delivered_within_days(1)/delivered_within_days(2)/; s/0\.1\.0/0.1.1/' "$pack"
terms lint "$pack" >/dev/null || fail "the changed terms do not lint"
terms test "$pack" >/dev/null || fail "the changed terms do not test"
run2=$(terms run "$pack" --store "$seller" --dry-run)
cmp=$(terms compare "$(jq -r .run <<<"$run1")" "$(jq -r .run <<<"$run2")")
row=$(jq -c '.rows[]|select(.row=="delivered_within_days")' <<<"$cmp")
[ "$(jq -r .row_changed <<<"$row")" = true ] || fail "the changed row is not reported changed: $cmp"
[ "$(jq -r '.before.pack_digest==.after.pack_digest' <<<"$cmp")" = false ] || fail "both runs carry one pack digest"
ok "step 2: $(jq -r '.summary|join("; ")' <<<"$cmp")"

[ "$(store_hash)" = "$store_before" ] || fail "a rehearsal changed the seller store"
ok "the rehearsals left the seller store untouched"
pub=$(terms publish "$pack")
[ "$(store_hash)" = "$store_before" ] || fail "publish changed the stores or the config"
[ "$(jq -r .in_force <<<"$pub")" = false ] || fail "publish claims the terms are in force: $pub"
find "$HOME" "$D/studio" "$D/agent" "$PLUGINS/terms-pack-studio" -newer "$marker" -type f -not -path "$HOME/studio/*" 2>/dev/null | grep . && fail "a verb wrote outside ~/studio (listed above)"
ok "the verbs wrote nothing outside ~/studio"

# Step 3: the live store is the presenter's own deal profile, made as devcon8 trade makes it. The install command
# publish prints pins the checker there.
capsulectl --profile deal deal init --dir "$HOME/.local/share/capsule-deal" --materiality builtin:neutral --no-witness >/dev/null
bash -c "$(jq -r .install <<<"$pub")" >/dev/null || fail "install failed: $(jq -r .install <<<"$pub")"
ok "step 3: published and pinned ($(jq -r '.definition_digest[:12]' <<<"$pub"))"

# Step 4: a live sale after the pin. Same snapshots as the replay (evidencebook-deal studio-replay.sh). The
# commit check at 175 after an offer at 150 must carry the pinned rules and fail the price_as_offered row.
side() { capsulectl --profile deal deal "$@"; }
terms_json='{"item":"fox sticker","quantity":1}'
jq -n '{type:"purchase",demo:true,intent:{verbatim:"Sell my fox sticker for 150",min_total_minor:100,asked:{item:"fox sticker",quantity:1},allowed:["offer","commit"]},terms:{item:"fox sticker",quantity:1,price_minor:150,currency:"USD"},recourse:{rail:"x402",refundable:false}}' >"$work/sale.json"
sale=$(side sale new --input "$work/sale.json" | jq -r .sale_id)
jq -n '{channel:"marketplace",who:{name:"Buyer 11",domain:"buyer11.example"},terms:{price_minor:150}}' >"$work/thread.json"
thread=$(side open --sale "$sale" --input "$work/thread.json" | jq -r .deal_id)
jq -n --argjson t "$terms_json" '{action:"offer",amount_minor:150,terms:($t+{handover:"shipped",price_minor:150}),recourse:{rail:"x402",refundable:false}}' >"$work/offer-check.json"
offer=$(side check --deal "$thread" --input "$work/offer-check.json")
[ "$(jq -r '.rules.status' <<<"$offer")" != not_evaluated ] || fail "the pinned rules were not evaluated: $(jq -c .rules <<<"$offer")"
# The pinned rules pause the offer. The seller's answer is bound to the card it was shown (--shown-card), then the
# offer act and the buyer's acceptance record; history entries come from act records.
jq -r .approval_text <<<"$offer" >"$work/card.txt"
side note --deal "$thread" --kind approval --check "$(jq -r .check_id <<<"$offer")" --choice proceed \
  --said "yes, go ahead with this buyer" --shown-card "$work/card.txt" >/dev/null
jq -n '{action:"offer",amount_minor:150}' >"$work/offer-act.json"
[ "$(side note --deal "$thread" --kind act --input "$work/offer-act.json" | jq -r .unchecked)" = false ] || fail "the offer act was sealed unchecked"
side note --deal "$thread" --kind acceptance --check "$(jq -r .check_id <<<"$offer")" --words "yes, 1.50 works" --channel marketplace >/dev/null
jq -n --argjson t "$terms_json" '{action:"commit",amount_minor:175,terms:($t+{handover:"shipped",price_minor:175}),recourse:{rail:"x402",refundable:false}}' >"$work/commit-check.json"
side check --deal "$thread" --input "$work/commit-check.json" >"$work/check.json"
jq -e '.rules.ruleset_id' "$work/check.json" >/dev/null || fail "deal check carries no rules.ruleset_id: $(jq -c .rules "$work/check.json")"
[ "$(jq -r '.rules.definition_digest' "$work/check.json")" = "$(jq -r .definition_digest <<<"$pub")" ] || fail "deal check reads another pack than the published one"
[ "$(jq -r '.rules.findings[] | select(.id == "price_as_offered") | .verdict' "$work/check.json")" = fail ] \
  || fail "deal check does not fail the price_as_offered row: $(jq -c '.rules.findings' "$work/check.json")"
ok "step 4: the live check fails price_as_offered under the pinned terms"
echo "studio-e2e: pass"
