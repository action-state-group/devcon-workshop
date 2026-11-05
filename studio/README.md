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

`devcon8-studio` greets you with your agent's address and asks whether you want to write terms or sell. Unlike
`devcon8 trade` it does not wait for buyers at start-up (steps 1-3 need no mailbox): type your first request. It
starts waiting on the mailbox, in the foreground, only when you ask it to sell (step 4), and keeps waiting between
deals. (`devcon8-studio --buy <address>` is different: a purchase starts at once and waits for the shop's reply.) While it waits, press Ctrl-C once: that stops the agent's turn, even while it waits on the mailbox, and you can type again (the agent goes back
to waiting afterwards if you had asked it to sell). To end the run, press Ctrl-C twice at the empty prompt (the first
prints "Press Ctrl+C again to exit", the second "session closed"). This relies on the goose patch
`patches/goose-acp-cancel-abandoned-prompt.patch`, which the image built from this repository carries.

## Tests

- `python3 -I tests/test_build_recipe.py` and `python3 studio/build-recipe.py --check`
- `tests/studio-recipe.sh` renders `studio.yaml` with goose in both payment modes and checks that Studio does not start the mailbox wait while the trader does (CI runs it in the image)
- `tests/goose-cancel.sh` (in the workshop image): Ctrl-C ends a running agent turn and the next typed line reaches the agent
- `tests/studio-layer.sh` checks the layer's contents (inside the built layer)
- `tests/studio-e2e.sh` runs demo steps 1-4 without a model over `devcon8-studio replay` (inside the built layer; CI runs it)
- `tests/studio-ruling.sh` runs demo step 6 without a model: dispute, ruling, the same sentence and receipt line in both stores, both cards (waits for checkpoints)
