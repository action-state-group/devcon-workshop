# Terms Pack Studio layer

An internal build on top of the workshop image, run from a laptop. It adds what the first Terms Pack
Studio demo needs and changes nothing in the published image, its `latest` tag or the USB files.

What it adds:

- `studio.yaml`, the sticker trader recipe plus a Studio section: goose may read the
  `terms-pack-author` skill and run `terms <verb>`; everything `terms` writes goes under `~/studio`. It is generated
  from `trader.yaml` by `studio/build-recipe.py`, which adds the Studio section, its permissions and a start-up that does not wait on the mailbox until you ask to sell (CI fails if the committed file is stale), so the
  trading protocol exists once.
- `terms <verb>` (lint, test, run, compare, publish, ...), the evidencebook-skills scripts at the commit
  pinned in `versions.lock`, run with PyYAML from a venv under `/opt/devcon8/studio`, and the checkout sits under capsulectl's trusted plugin root (`/usr/local/lib/capsulectl/plugins/terms-pack-studio`).
- The `terms-pack-author` skill, from the same commit.
- `devcon8-studio`, the same as `devcon8 trade` with the Studio recipe, and `devcon8-studio replay` (and `replay --live`, the same ten sales in the seller's live deal profile before its first trade, so the live trade makes eleven), which
  puts ten sample sticker sales in `~/studio/replay` (evidencebook-deal's replay, at the commit pinned in
  `versions.lock`) for the first rehearsal.
- `card make | staple | open`, the History card (demo step 5): `card make` writes the card and its page
  (offline, from the bundle alone) under `~/studio/cards`; `card staple` writes the seller's staple and the
  shared copy of its card for its next proposal; `card open FILE` is the buyer's side, which verifies a
  received card and draws it. A card is as of a checkpoint cut after the holder was declared, and checkpoints
  are about five minutes apart, so run `card make` once early (it declares the holder), and use `--fresh` at step 5 so
  the live deal is counted (it waits up to seven minutes for a new checkpoint and says so).
- `dispute DEAL --words TEXT` and `dispute show DEAL`, and `referee rule DEAL --buyer HOME --seller HOME` (demo
  step 6). The buyer's agent seals a dispute note on a deal; the fixed referee makes one reconcile Result for
  that deal (the buyer asks the seller for its copy, the seller answers, the buyer reconciles), checks it with
  `deal terms-result --check` over both parties' copies, and seals one ruling in each store, the buyer's first.
  Its rule is fixed (a demo rule, not a dispute policy): if the two parties' final closes name different amounts the price was not as offered, and
  the ruling is for the buyer; if they match, for the seller. It rules on the price row only. For the price-changed sale, both stores then
  read `Ruling <12 hex> on "price as offered": found for the buyer` on the receipt, and each History card counts
  it under "Everything on the card", Disputes (buyer: 1 raised, ended for the buyer; seller: 1 received, ended
  against the seller).
  The replay's price-changed sale is the one to dispute: `dispute sale` prints its id (the ids differ on every replay).
  The replayed sales live in `~/studio/replay/seller` and `~/studio/replay/buyer`, so a card that counts the ruling is made from there:
  `XDG_CONFIG_HOME=~/studio/replay/buyer card make --fresh buyer` (and `seller` for the seller's), because `card make`
  alone reads the live profile. `dispute` and `dispute show` look in the live profile first and then in those two.
  Besides those Disputes counts, the Result is the only change step 6 makes to the cards: on the buyer's card it counts
  as stamped by both sides (1 of 10). The headline does not change: both cards still read "0 of 10 ... 10 we couldn't tell". Needs `capsulectl-deal` with dispute notes (rc36 or later).
- `mbx` from this checkout, so a seller's proposal may carry `history-staple.json` and `history-card.bundle`.

## Build

The base is an immutable digest of the workshop image, pinned in `versions.lock`; `latest` is refused.
The build is local and pushes nothing.

    studio/build.sh                       # uses STUDIO_BASE from versions.lock
    studio/build.sh --base <image@sha256:...> mytag

## Run

    studio/run.sh                         # a second run resumes the stopped container
    docker start -ai devcon8-studio       # the same, by hand

Inside the container: `devcon8 brain claude` (a Claude subscription login; no API key), `devcon8 nanda
<your email>`, then `devcon8-studio replay` (once: it puts ten sample sticker sales in `~/studio/replay`;
a second run changes nothing; if it fails, delete `~/studio/replay` and run `devcon8-studio replay` again), then `devcon8-studio`. Rehearsal pages and Result JSON land in
`~/devcon8-studio` on your laptop (mounted at `~/studio`), so you open them from the browser.

Which replay the walkthrough needs. Run both on the seller's agent right after setup, before step 3 and the first
trade, `replay --live` first and then `replay` (the order the tests run):
`devcon8-studio replay` puts the ten sales in `~/studio/replay`, which steps 1, 2 and 6 read (the rehearsal pages, the
compare, and the dispute with its ruling). `devcon8-studio replay --live` puts the same ten in the live deal profile,
which step 5's seller card counts: after one live trade that card reads 11 provided; without it, only the live trades.
It needs an empty live profile, so it cannot run after the first trade. The two sets are separate stores with
different deal ids: step 6's ruling lands on the replay sale, so the cards that count it are the replay-store cards
(`XDG_CONFIG_HOME=~/studio/replay/buyer card make --fresh buyer`, and `seller`), which count the ten replayed sales.
Step 6 runs entirely in the seller's container, the buyer's `dispute`, `referee rule` and `dispute show` included;
do not run a replay in the buyer's container for it, or the two sides get different deal ids.

The buyer for steps 4 and 5 is a second container, not started by `run.sh`. Make its folder first, as yourself, or Docker
creates it owned by root and the buyer's `card make` fails with "Permission denied":

    mkdir -p ~/devcon8-buyer-studio
    docker run -it --name devcon8-buyer -v devcon8b-home:/home/participant -v ~/devcon8-buyer-studio:/home/participant/studio \
      -p 127.0.0.1:3241:3132 -p 127.0.0.1:8180:8080 -p 127.0.0.1:9711-9714:9621-9624 devcon-workshop-studio:dev

Inside it, `devcon8 brain claude`, then `devcon8-studio --buy <the seller's address>`. For step 6, the buyer's agent is a
second `devcon8-studio` in the seller's container (`docker exec -it devcon8-studio bash`).

Nothing rules on a dispute until the presenter runs the referee, in a shell in the seller's container (`dispute sale`
prints the deal id; the two homes are the replay stores):

    referee rule <deal> --buyer ~/studio/replay/buyer --seller ~/studio/replay/seller

Until then both agents answer "Nothing is ruled on <deal> yet"; afterwards they answer with the same sentence. An agent
does not run the referee itself, and going back to waiting for buyers does not trigger it.

A goose that is waiting on the mailbox (the seller's while it sells, the buyer's after its purchase) needs one Ctrl-C
before a new request, such as the card at step 5 or a question at step 6; without it the request may go unanswered.

`devcon8-studio` greets you with your agent's address and asks whether you want to write terms or sell. Unlike
`devcon8 trade` it does not wait for buyers at start-up (steps 1-3 need no mailbox): type your first request. It
starts waiting on the mailbox, in the foreground, only when you ask it to sell (step 4), and keeps waiting between
deals. (`devcon8-studio --buy <address>` is different: a purchase starts at once and waits for the shop's reply.) While it waits, press Ctrl-C once: that stops the agent's turn, even while it waits on the mailbox, and you can type again (the agent goes back
to waiting afterwards if you had asked it to sell). To end the run, press Ctrl-C twice at the empty prompt (the first
prints "Press Ctrl+C again to exit", the second "session closed"). This relies on the goose patch
`patches/goose-acp-cancel-abandoned-prompt.patch`, which the image built from this repository carries.

## Walkthrough

The six demo steps in order, for a presenter. The commands come from Build and Run above; this section says which
container runs each one and what you should see.

**What has been run by hand.** All six steps were run by hand, in order, on one image on 2026-11-06 (lane deal-151,
main `0f51d67`, Studio built by `studio/build.sh`, base `sha256:c05520c6…`, rc37). That run reused logged-in volumes
with their deal data cleared and took about 25 minutes. Main has moved since: `lib/trade.sh`, `agent/recipes/studio.yaml`,
`agent/bin/mbx` and `agent/bin/offers` changed in #83 and #85 (`--want`, a buyer search). So this walkthrough has **not**
been run by hand on main's head. The Studio layer builds on `STUDIO_BASE` in `studio/versions.lock` (`sha256:c05520c6…`), never on
`latest`. Not run by hand: the `--pay lexe` staple, amd64, the codex brain, the buyer's `--want` search and the "buy again" prompts for the second trade (added from the recipe, not from a run). The card and
agent sentences quoted below come from the 2026-11-06 run; the offer-card wording comes from the deal plugin, not from this repository.

**Containers.** Two, both from the Studio image that Step 0 builds:

| Name | Started by | Runs |
|---|---|---|
| `devcon8-studio` (seller) | `studio/run.sh` | steps 1 to 6; step 6 uses three shells in it |
| `devcon8-buyer` | the `docker run` in Step 0 | the buyer's side of steps 4 and 5 |

The Claude login and the mailbox code need the presenter in person. Never paste login codes, six-digit codes or invites into chat.

### Step 0: build and set up

In a Mac terminal, from a checkout of main (see [Build](#build) and [Run](#run) for the details):

    studio/build.sh
    studio/run.sh

In the seller container, in order. Run both replays before the first trade: `replay --live` gives step 5 its 11 sales and
`replay` is what steps 1, 2 and 6 read. They are separate stores with different deal ids, and `replay --live` needs an
empty live profile, so it cannot run after the first trade.

    devcon8 brain claude
    devcon8 nanda <your email>
    devcon8-studio replay --live
    devcon8-studio replay

To show the ten sales (each sale also has a second `sale-…` row, which this filters out):

    XDG_CONFIG_HOME=~/studio/replay/seller capsulectl --profile deal deal list --json | jq -r 'map(select(.kind=="deal"))|sort_by(.opened_at)[]|.summary.text'

Expect ten lines, Buyer 1 to Buyer 10, all `completed`.

The buyer, in a second Mac terminal. Make the folder first, as yourself, or Docker creates it owned by root:

    mkdir -p ~/devcon8-buyer-studio
    docker run -it --name devcon8-buyer -v devcon8b-home:/home/participant -v ~/devcon8-buyer-studio:/home/participant/studio \
      -p 127.0.0.1:3241:3132 -p 127.0.0.1:8180:8080 -p 127.0.0.1:9711-9714:9621-9624 devcon-workshop-studio:dev

Inside it, run `devcon8 brain claude`, then `devcon8 nanda <a second email>`. Rehearsal pages and Result JSON land in
`~/devcon8-studio` on the laptop (the buyer's in `~/devcon8-buyer-studio`), so you open them from the browser.

### Steps 1 to 4: say these to the seller's goose

In the seller container run `devcon8-studio`. It greets you with the agent's address and asks whether to write terms or
sell. It does not wait on the mailbox until you say sell.

| Step | You say | You should see |
|---|---|---|
| 1 Look | Judge my last ten sales under terms that say: paid before delivery, delivered within a day of payment, price as offered. | 9 of 10 came through; one sale missed on price as offered; a page you can open |
| 2 Change | Make it within two days, not one. | The two versions compared row by row, with both digests |
| 3 Switch on | Use these terms on my sales. Then: Yes, switch them on. | Confirms once, then pins the pack digest |
| 4 Sell | Yes, start selling stickers now. | Goose waits for buyers |

For step 4, then run in the buyer container, with the address the seller's agent printed:

    devcon8-studio --buy <the seller's address>

The seller's offer card reads: `Why I'm asking: your rule "The price was the price offered" is checked at the commit.`
Answer `Yes, go ahead.` A clean commit shows no card. To show the rule stopping a sale, tell the seller's goose to commit a
second trade at $0.60, then press Ctrl-C in the buyer container and ask its goose to buy again (the seller only creates a second deal when a new request arrives). The card reads: `Why I stopped: your rule "The price was the price offered" did not hold (the commit was $0.60, the offer $0.50); the terms changed since you agreed.`

**Ctrl-C.** A goose that is waiting on the mailbox (the seller's while it sells, the buyer's after its purchase) needs one
Ctrl-C before a new request, or the request may go unanswered. To end a run, press Ctrl-C twice at the empty prompt.

### Step 5: History cards

In each container (seller and buyer), press Ctrl-C once and say:

> Make my history card and open it. Use --fresh.

This waits for the next checkpoint, up to seven minutes (under about 5 in the run). Expect the seller's card to count
11 provided and the buyer's 1 bought. Both read "we couldn't tell", because these deals have no Result.

To show the staple, ask the seller's goose to staple the card to its next proposal, then press Ctrl-C in the buyer container and ask its goose to buy again. When the new proposal arrives, the buyer's goose runs `card open`. Expect: `card: signed by key …, and the bundle's card is the stapled card. Not checked: that this key is the seller's.`

### Step 6: dispute and ruling

Everything runs in the seller container, because the replay stores are there. Do not run a replay in the buyer container.

1. Open a second shell and start the buyer's goose:

       docker exec -it devcon8-studio bash
       devcon8-studio

   Say: `The sticker was the wrong one in my price-changed sale. Dispute it.`

2. Nothing is ruled until the presenter runs the referee. In a third shell in the same container:

       dispute sale
       referee rule <deal id> --buyer ~/studio/replay/buyer --seller ~/studio/replay/seller

   `dispute sale` prints the id of the price-changed sale (the ids differ on every replay). Ask each goose
   `What became of the dispute?` Before the referee runs, both answer "Nothing is ruled on <deal> yet"; afterwards both
   answer `The referee ruled on the dispute over "price as offered": found for the buyer. Ruling ….` A second
   `referee rule` on the same deal is refused: `a deal is ruled on once`.

3. Make the cards from the replay stores (plain `card make` reads the live profile):

       XDG_CONFIG_HOME=~/studio/replay/buyer card make --fresh buyer
       XDG_CONFIG_HOME=~/studio/replay/seller card make --fresh seller

   The buyer's card shows 1 dispute raised, ended for them, and stamped by both sides 1 of 10. The seller's shows
   1 received, ended against them.

Say two things when recording: both cards still read "10 we couldn't tell", with the dispute under Disputes, so do not say
the disputed sale's entry reads from a Result; and `card open` proves the signature and the binding, not that the key is the seller's.

### Known problems

- `paid_at` cannot be read for real Lightning sales, so the payment terms turn `not_evaluable`; simulated payments are not affected. Confirmed by Sherlock2, not fixed.
- `delivered_within_days` uses the delivery time the seller reports, so that row's wording claims too much. Confirmed by Sherlock2, not fixed.
- Ports: `studio/run.sh` and the mesh demo in the top-level README both publish 3141, 8080 and 9611-9614, so only one can run at a time. The goose trade demo and Studio use the same mailboxes, so a later `devcon8 nanda` takes them over.

## Tests

- `python3 -I tests/test_build_recipe.py` and `python3 studio/build-recipe.py --check`
- `tests/studio-recipe.sh` renders `studio.yaml` with goose in both payment modes and checks that Studio does not start the mailbox wait while the trader does (CI runs it in the image)
- `tests/goose-cancel.sh` (in the workshop image): Ctrl-C ends a running agent turn and the next typed line reaches the agent
- `tests/studio-layer.sh` checks the layer's contents (inside the built layer)
- `tests/studio-e2e.sh` runs demo steps 1-4 without a model over `devcon8-studio replay` (inside the built layer; CI runs it)
- `tests/studio-ruling.sh` runs demo step 6 without a model: dispute, ruling, the same sentence and receipt line in both stores, both cards (waits for checkpoints)
