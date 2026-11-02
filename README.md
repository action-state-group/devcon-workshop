# Devcon 8 workshop image

One container you run on your own laptop for the Devcon 8 S08 workshop (Tue Nov 3, 09:30 UTC). It
lets you:

- run a node on the workshop's demo mesh, on the lab build of [mesh-llm](https://github.com/Mesh-LLM/mesh-llm) the demo nodes run
  with the capsules (evidence) and lexe-wallet plugins;
- replay two demos: the S02 two-sided settlement record (offline), and S08, where a node lies about
  its model and is caught by its twin and a referee (four nodes, all inside your container);
- run an agent that trades a digital sticker with other participants' agents. It finds them through
  the [NANDA Index](https://nandaindex.org), messages them through its own [Agent Box](https://agentboxnanda.org)
  mailbox, and seals every step with `capsulectl deal`. The payment is **simulated** by default: no money
  moves. With your own lexe wallet you can pay in real Lightning instead (optional, real money).
- start from a short Go program on the [evidencebook](https://github.com/action-state-group/evidencebook)
  SDK.

Inference runs on your CPU (Docker on a Mac has no GPU access). The image is about 3 GB (3.0 GiB on arm64, 3.1 GiB on amd64).

## Before the workshop

You need Docker (Docker Desktop on macOS or Windows, Docker Engine on Linux) with at least **8 GB of
memory** for the container (Docker Desktop: Settings > Resources) and about 6 GB of free disk.

Pull the image ahead of time, by the digest announced for the workshop. Conference wifi is slow:

    docker pull ghcr.io/action-state-group/devcon-workshop@sha256:<digest>

No network at the venue? USB sticks carry one tarball per architecture. Load the one that matches your
laptop (`arm64` for Apple silicon, `amd64` for Intel and most Linux and Windows machines):

    docker load -i devcon-workshop-<tag>-arm64.tar

The stick's `SHA256SUMS` lists each tarball's checksum. A loaded image has no registry digest, so in
the `docker run` below use its tag, `ghcr.io/action-state-group/devcon-workshop:<tag>-arm64`, in place
of `@sha256:<digest>`.

## Start

    docker run -it --name devcon8 -v devcon8-home:/home/participant \
      -p 127.0.0.1:3141:3131 -p 127.0.0.1:8080:8080 -p 127.0.0.1:9611-9614:9611-9614 \
      ghcr.io/action-state-group/devcon-workshop@sha256:<digest>

You get a shell with `devcon8` on the path. `devcon8 help` lists every step. Each step is safe to rerun.
The ports are published on your laptop's loopback only. Later, `docker start -ai devcon8` brings you back.
The console is on port 3141 because Buzz Desktop uses 3131. If you started `devcon8` from an older version of these steps, run `docker rm devcon8` first, then the `docker run` above; your `devcon8-home` volume keeps your state.

### 1. `devcon8 doctor`

Shows your architecture, CPUs, memory, free disk and the versions in the image, and warns when Docker
has under 8 GB of memory.

### 2. `devcon8 join`: a node on the demo mesh

Paste the invite you are handed at the workshop (it is stored in `~/.devcon8/join.txt`, never shown
back). Your node starts as a client, with its wallet policy at the default, **free-only**: it never
pays. Then it asks the mesh one question. One of two things happens:

- The serving node is free: you get an answer, and the sealed record of that exchange is on your
  node's console, http://127.0.0.1:3141, Evidence tab.
- The serving node charges: your request is refused. That is the free-only policy doing its job.
  Nothing was paid. See "If your first prompt is refused" below.

`devcon8 node status|log|stop` manage your node. `devcon8 join --new` asks for a new invite. If you
change your wallet policy away from free-only, `join` no longer sends its question.

### 3. `devcon8 brain claude|codex|mesh`: what goose thinks with

The trading agent runs in [goose](https://github.com/aaif-goose/goose). Pick its model:

- `claude`: your Claude subscription. Claude Code prints a link; open it on your laptop, sign in, paste
  the code back.
- `codex`: your ChatGPT subscription, by device login. Turn on device code login in ChatGPT's security
  settings first. **Codex login**: if that is not possible, copy your laptop's `~/.codex/auth.json` in,
  from a laptop terminal (this keeps it readable only by the container's user), then run
  `devcon8 brain codex` again:
  `docker exec -i devcon8 sh -c 'mkdir -p ~/.codex && umask 077 && cat > ~/.codex/auth.json' < ~/.codex/auth.json`
- `mesh`: chat with the mesh's own models through your node. A 0.5B model cannot run the trading
  agent; use `claude` or `codex` for that.

### 4. `devcon8 s02`: the settlement record

Open http://127.0.0.1:8080/settlement-record.html. One Lightning payment between two demo nodes, as two
signed halves under two keys, checked in your browser, offline. `demos/s02/README.md` has the same check
on the command line.

### 5. `devcon8 s08 <step>`: catch a lying node

Four nodes on a private mesh inside your container (it never touches the demo mesh): an honest node, a
referee, a liar and an asker, all on the same mesh-llm and capsules as the demo mesh. Steps, in order:
`start` (a few minutes per node on a laptop CPU), `lie`, `twins`, `referee`, `show`, then the second hack,
`omit` and `count`, then step 8, `ask`, the omission found by a signed evidence request; `stop` when done.
The asker's Evidence page is http://127.0.0.1:9614/plugins/capsules/evidence. On an arm64 laptop the
two models write the same ocean haiku, so `twins` asks "Name three colors." by default; pass another
question as `devcon8 s08 twins "<question>"`.

### 6. `devcon8 nanda <email>`: your agent's mailbox

Creates an Agent Box mailbox for your agent (its own address at `agentboxnanda.org`, the inbox for
agent-to-agent messages), sends a six-digit code to your email, and lists the mailbox in the NANDA
Index. The NANDA Index works with ARD and AI Catalog. Read this first:

- **The listing is public.** Anyone can find your agent's address and message it. The listing shows the
  mailbox address, not your email. Its description reads "Devcon 8 workshop demo agent, not a real shop: payment simulated by default, real Lightning only if both sides run it".
- **The listing stays after the workshop** until you remove it, and removing it is permanent (see "Leaving the NANDA Index").
- One email gives one mailbox. To trade with yourself, run a second agent in a second container with a
  second email address.

The mailbox key is kept in `~/.devcon8/agentbox/key` (mode 0600) and is never printed.

### 7. `devcon8 trade [--buy <address>] [--pay lexe]`: the trading agent

Your agent sells your digital fox sticker for 50 cents to any participant's agent that asks. With
`--buy <their address>@agentboxnanda.org` it also buys one from that participant's agent, the address
they give you. It buys only from that address, never from search results.

- goose asks you before every tool call (`GOOSE_MODE=approve`). Before each offer, commitment and
  payment the agent runs a final check; when the check pauses ("PAUSED FOR YOU"), the agent shows
  you its card in the chat and seals your answer. Say no and it holds.
- It keeps checking its mailbox while it waits for buyers. If it stops and goes quiet, tell it to
  keep waiting ("keep checking the mailbox").
- **The payment is simulated** unless you add `--pay lexe`. It is an x402 payment recorded against Base
  Sepolia, a test network, with a settle response that says "SIMULATED". No money moves and no wallet
  is used. With `--pay lexe` the sticker is paid in real Lightning from your own wallet: see "Paying
  for the sticker with your own wallet" below.
- Other participants' agents are strangers. Your agent never sees their message text, only the parsed
  fields: kind, ids, digests and terms. Files arrive only as named, size-capped, sha256-checked
  attachments (`buyer-terms.json`, `settle.json`, `sticker.png`). In a `--pay lexe` run a proposal also
  carries the shop's Lightning invoice, which is saved for the payment and not shown to the agent.
- Each sale or purchase is one deal in `~/.local/share/capsule-deal`; files are in `~/deals/`.

### 8. `devcon8 go-seal`: the Go SDK example

Copies `examples/go-seal` to `~/go-seal` (once), builds it offline and runs it: it opens a book on disk,
seals one Evidence Result and cuts a checkpoint. Change `~/go-seal/main.go` and run `devcon8 go-seal`
again; your edits are kept. `devcon8 go-seal --reset` starts over from the image's copy.

## If your first prompt is refused

Your node is free-only and the serving node charges, so the mesh refused the request and nothing was
paid. The presenter shows a free join and its Evidence tab on screen. You can also pay with your own
Lightning wallet (next section). That is optional and real money.

## Your own wallet (optional, real Lightning, mainnet)

`devcon8 wallet` opens your own lexe wallet through your running node. The image ships no wallet: the
plugin creates one on first use, inside `~/.mesh-llm/payments` on your volume. Funding it
(`mesh-llm wallet fund-wallet --amount-sats N`) and allowing payments
(`mesh-llm wallet policy --mode automatic --daily-budget-sats N`) are up to you, and they spend real
sats. With a funded wallet, keep goose in approve mode. The sticker trade stays simulated unless you
run it with `--pay lexe` (next section).

What has been checked: on 2026-10-31 a funded demo node paid the serving node 1,900 msat for one
request, and its own sealed record of the payment shows on its Evidence tab. That holds at the serving
node's current price. At a much lower price the deposit can cover the whole bill, and then no payer
record is sealed ([evidencebook#48](https://github.com/action-state-group/evidencebook/issues/48)):
you would pay and see no record.

## Paying for the sticker with your own wallet (optional, real Lightning, mainnet)

`devcon8 trade --pay lexe` pays for the sticker with real sats, from your own lexe wallet to the seller's.
Both sides must run `--pay lexe`: a buyer in a simulated run declines a shop that asks for Lightning,
and a `--pay lexe` buyer declines a shop that does not.

1. `devcon8 join`, then `devcon8 wallet`: your node and your own wallet (previous section). To buy, fund
   it with a few hundred sats more than the price; selling needs no funds.
2. Set your caps, for example:

       devcon8 lightning --price-sats 500 --per-payment-sats 600 --total-sats 1000

   Each also takes millisatoshi instead (`--price-msat` and so on; 1 sat = 1,000 msat).
   On the workshop's lab, 500 msat is the smallest Lightning payment that routed; 10 and 100 msat found no route.
   `--price-sats` is what your agent asks for your sticker. `--per-payment-sats` is the most one payment
   of yours may cost, routing fee included, and `--total-sats` the most all of the sticker payments the
   agent's `lightning` tool makes may cost (paid mesh inference is governed by your wallet policy, not
   by these caps). `devcon8 lightning` shows them and what has been paid so far. The deal terms stay
   at 50 cents; the price in sats is the one you set. The agent's `lightning` tool reads the caps and has
   no way to raise them; the agent could still edit the file with its shell, which is one more reason
   goose asks you before every command it runs.
3. `devcon8 trade --pay lexe [--buy <address>]`.

What happens:

- As a seller, your agent asks your wallet for an invoice at your price and sends it with its offer.
  Once your wallet reports the payment settled, it seals what your wallet received and hands over the
  sticker. If the payment does not arrive, it does not deliver.
- As a buyer, your agent's final check always pauses on a Lightning payment, because it cannot be
  pulled back: you see the card, with the sats the shop's invoice asks, and answer it. Then the
  `lightning` tool pays that invoice, and refuses it before anything is sent if it is over your caps,
  expired, or for other sats than you said yes to. Only the first invoice a shop sends is kept.
- The invoice tells the buyer, and the Agent Box service that carries the message, the seller's
  Lightning node id and the amount.
- The sealed records name the payment by its payment hash, with the amounts. The seller's own record also
  seals the payment's preimage, the proof it settled (the buyer already holds it). No record carries the invoice or the receiving node id, and `lightning`
  never prints a preimage.

A mailbox listed by an earlier image keeps the description it was listed with, "simulated payment"
(this image does not change an existing listing); if yours says that, tell the other participant before a `--pay lexe` sale.

## Leaving the NANDA Index

    devcon8 nanda leave

`leave` is permanent. It deletes your agent's listing, and you cannot list the same mailbox again
afterwards: on 2026-10-31 the gateway refused to re-register a mailbox whose listing had been deleted
("NANDA account is temporarily unavailable"), and the Index does not let a personal account recreate
the listing itself. To take part again after `leave`, use a new email address (a new mailbox). So run
it when you are done with the workshop, not to pause.

How it works: the NANDA Index keeps an account for your agent's mailbox address. `leave` asks the Index
for a password reset, which arrives in your agent's own mailbox, signs in with a new random password it
never shows, and deletes the listing. Afterwards a lookup of your agent's address finds nothing, and
other agents cannot message it through the Index. The Agent Box mailbox itself stays, unlisted.

## Your data, and removing it

Everything you create lives on the `devcon8-home` volume: your node, its plugins and ledger, any
wallet, your Claude or Codex login, goose's config, your Agent Box key, your deals. Nothing secret is in
the image. To remove all of it:

    docker rm -f devcon8 && docker volume rm devcon8-home

Usage reporting is off: the image sets `DO_NOT_TRACK=1`, writes `[analytics] enabled = false` into every
mesh-llm config it creates, and its mesh-llm build carries no analytics key.

## What is in the image

Every component is pinned in [`versions.lock`](versions.lock), by commit or by release checksum, and
`/opt/devcon8/MANIFEST` lists the sha256 of every shipped file. mesh-llm is built from source in CI
for both architectures, from the lab commit the demo nodes run, so its bytes are not the demo nodes'
own; the capsules plugin is its published release file, checked by sha256, and the lexe-wallet
plugin is built from commit `9f830c1` of `ethanyzhang/lexe-wallet-plugin` (compare by commit). The image
labels name these commits (`dev.actionstate.mesh-llm` = `1aba71da6da562b259ad0696210d7fc7b932ac02`,
`dev.actionstate.capsules` = `0.1.10 41e0d603772a2ce7becef5b7d3e0a713f43d7040`,
`dev.actionstate.lexe-wallet` = `v0.1.0 9f830c181b4042a81069df50752cf19d035a5047`), and
`/opt/devcon8/MANIFEST` gives the sha256 of the image's own mesh-llm.

This mesh-llm is a **pre-release lab build, not an official mesh-llm release**. Its
`mesh-llm --version` prints `mesh-llm 0.78.0`, the same string as the official 0.78.0 release, so
the version does not tell them apart; the commit and the sha256 do. Installing it on your laptop
instead? Build the same commit with this repository's `.github/workflows/mesh-llm-lab-release.yml`
(run it with `mesh_commit` set to that commit); no pre-built tarball is published for this commit.

The image builds the same commit with the same recipes, but its bytes are its own.

| | |
|---|---|
| mesh-llm | lab build `1aba71d` of `ethanyzhang/mesh-llm`: Mesh-LLM/mesh-llm main `000440f` plus open PRs [#2620](https://github.com/Mesh-LLM/mesh-llm/pull/2620), [#2649](https://github.com/Mesh-LLM/mesh-llm/pull/2649), [#2721](https://github.com/Mesh-LLM/mesh-llm/pull/2721), [#2741](https://github.com/Mesh-LLM/mesh-llm/pull/2741), [#2744](https://github.com/Mesh-LLM/mesh-llm/pull/2744), [#2748](https://github.com/Mesh-LLM/mesh-llm/pull/2748) and [#2760](https://github.com/Mesh-LLM/mesh-llm/pull/2760). CPU runtime |
| capsules plugin | `v0.1.10` (carries capsule-viewer 0.9.0) |
| lexe-wallet plugin | built here from [lexe-wallet-plugin#7](https://github.com/Mesh-LLM/lexe-wallet-plugin/pull/7) (`feat/settled-preimage`, commit `9f830c1`), which reports a settled payment's preimage |
| S08 | the same mesh-llm and capsules; the liar runs capsules 0.1.10 plus `demos/s08-liar/redteam/selective-log.patch`, built here; step 8's `reconcile/` on evidencebook v0.12.2 |
| capsulectl, capsulectl-deal, capsulectl-book | `v0.1.0-rc29` releases (deal carries `capsulectl deal terms-leg` and seals a Lightning payment received) |
| goose (built from its v1.57.0 commit plus `patches/`, aaif-goose/goose#13273), Claude Code, Codex, ACP adapters | `versions.lock`, `package-lock.json` (`claude` is the Claude Code CLI bundled with claude-agent-acp's SDK) |
| evidencebook Go SDK | v0.12.2, Go 1.27 |
| models | Qwen2.5-0.5B-Instruct GGUF, Q8_0 and Q4_K_M |

The buyer's signed terms leg is written by `capsulectl deal terms-leg`
([evidencebook-deal#70](https://github.com/action-state-group/evidencebook-deal/issues/70)), signed with
the buyer's own deal key.

Build it yourself: `docker buildx build --platform linux/arm64 -t devcon-workshop .` (about an hour).
