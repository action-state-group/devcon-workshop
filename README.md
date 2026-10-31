# Devcon 8 workshop image

One container you run on your own laptop for the Devcon 8 S08 workshop (Tue Nov 3, 09:30 UTC). It
lets you:

- run a node on the workshop's demo mesh, on a lab build of [mesh-llm](https://github.com/Mesh-LLM/mesh-llm)
  with the capsules (evidence) and lexe-wallet plugins;
- replay two demos: the S02 two-sided settlement record (offline), and S08, where a node lies about
  its model and is caught by its twin and a referee (four nodes, all inside your container);
- run an agent that trades a digital sticker with other participants' agents. It finds them through
  the [NANDA Index](https://nandaindex.org), messages them through its own [Agent Box](https://agentboxnanda.org)
  mailbox, and seals every step with `capsulectl deal`. The payment is **simulated**: no money moves.
- start from a short Go program on the [evidencebook](https://github.com/action-state-group/evidencebook)
  SDK.

Inference runs on your CPU (Docker on a Mac has no GPU access). The image is about 2.5 GB.

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
      -p 127.0.0.1:3131:3131 -p 127.0.0.1:8080:8080 -p 127.0.0.1:9611-9614:9611-9614 \
      ghcr.io/action-state-group/devcon-workshop@sha256:<digest>

You get a shell with `devcon8` on the path. `devcon8 help` lists every step. Each step is safe to rerun.
The ports are published on your laptop's loopback only. Later, `docker start -ai devcon8` brings you back.

### 1. `devcon8 doctor`

Shows your architecture, CPUs, memory, free disk and the versions in the image, and warns when Docker
has under 8 GB of memory.

### 2. `devcon8 join`: a node on the demo mesh

Paste the invite you are handed at the workshop (it is stored in `~/.devcon8/join.txt`, never shown
back). Your node starts as a client, with its wallet policy at the default, **free-only**: it never
pays. Then it asks the mesh one question. One of two things happens:

- The serving node is free: you get an answer, and the sealed record of that exchange is on your
  node's console, http://127.0.0.1:3131, Evidence tab.
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
referee, a liar and an asker. Steps, in order: `start` (a few minutes per node on a laptop CPU), `lie`,
`twins`, `referee`, `show`, then the second hack, `omit` and `count`, and `stop` when done. The asker's
Evidence page is http://127.0.0.1:9614/plugins/capsules/evidence. S08 runs on the release pair it was
rehearsed on: mesh-llm v0.78.1 and capsules 0.1.5.

### 6. `devcon8 nanda <email>`: your agent's mailbox

Creates an Agent Box mailbox for your agent (its own address at `agentboxnanda.org`, the inbox for
agent-to-agent messages), sends a six-digit code to your email, and lists the mailbox in the NANDA
Index. The NANDA Index works with ARD and AI Catalog. Read this first:

- **The listing is public.** Anyone can find your agent's address and message it. The listing shows the
  mailbox address, not your email. Its description reads "Devcon 8 workshop demo agent, simulated
  payment, not a real shop".
- **The listing stays after the workshop** until you remove it (see "Leaving the NANDA Index").
- One email gives one mailbox. To trade with yourself, run a second agent in a second container with a
  second email address.

The mailbox key is kept in `~/.devcon8/agentbox/key` (mode 0600) and is never printed.

### 7. `devcon8 trade [--buy <address>]`: the trading agent

Your agent sells your digital fox sticker for 50 cents to any participant's agent that asks. With
`--buy <their address>@agentboxnanda.org` it also buys one from that participant's agent, the address
they give you. It buys only from that address, never from search results.

- It asks you, in the chat, before every offer, commitment and payment, and seals your answer.
  goose also asks before every tool call (`GOOSE_MODE=approve`). Say no and it holds.
- **The payment is simulated.** It is an x402 payment recorded against Base Sepolia, a test network,
  with a settle response that says "SIMULATED". No money moves and no wallet is used.
- Other participants' agents are strangers. Your agent never sees their message text, only the parsed
  fields: kind, ids, digests and terms. Files arrive only as named, size-capped, sha256-checked
  attachments (`buyer-terms.json`, `settle.json`, `sticker.png`).
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
sats. With a funded wallet, keep goose in approve mode. The sticker trade stays simulated either way.

## Leaving the NANDA Index

    devcon8 nanda leave

The NANDA Index keeps an account for your agent's mailbox address. `leave` asks the Index for a
password reset, which arrives in your agent's own mailbox, signs in with a new random password it never
shows, and deletes the listing. Afterwards a lookup of your agent's address finds nothing. The Agent Box
mailbox itself stays, unlisted. (Tested on a throwaway mailbox on 2026-10-31: the Index's update and
delete calls both worked for the mailbox's own account.)

## Your data, and removing it

Everything you create lives on the `devcon8-home` volume: your node, its plugins and ledger, any
wallet, your Claude or Codex login, goose's config, your Agent Box key, your deals. Nothing secret is in
the image. To remove all of it:

    docker rm -f devcon8 && docker volume rm devcon8-home

Usage reporting is off: the image sets `DO_NOT_TRACK=1`, writes `[analytics] enabled = false` into every
mesh-llm config it creates, and its mesh-llm build carries no analytics key.

## What is in the image

Every component is pinned in [`versions.lock`](versions.lock), by commit or by release checksum, and
`/opt/devcon8/MANIFEST` lists the sha256 of every shipped file. The mesh-llm host and the capsules
plugin are built from source in CI for both architectures, from the commits the demo mesh runs. They are
not byte-identical to the demo nodes' own binaries.

| | |
|---|---|
| mesh-llm | lab branch `lab/asg-2026-10-30` of `ethanyzhang/mesh-llm` (Mesh-LLM/mesh-llm main plus four open PRs), CPU runtime |
| capsules plugin | Mesh-LLM/capsules-plugin `f494845` |
| lexe-wallet plugin | Mesh-LLM/lexe-wallet-plugin v0.1.0 |
| S08 pair | mesh-llm v0.78.1, capsules 0.1.5 (the liar: 0.1.5 plus `demos/s08-liar/redteam/selective-log.patch`) |
| capsulectl, capsulectl-deal | v0.1.0-rc23 (the pair must match) |
| goose, Claude Code, Codex, ACP adapters | `versions.lock`, `package-lock.json` |
| evidencebook Go SDK | v0.10.0, Go 1.27 |
| models | Qwen2.5-0.5B-Instruct GGUF, Q8_0 and Q4_K_M |

The buyer's signed terms leg is written by `tools/terms-leg` until a capsulectl-deal release carries
`capsulectl deal terms-leg` ([evidencebook-deal#70](https://github.com/action-state-group/evidencebook-deal/issues/70)).

Build it yourself: `docker buildx build --platform linux/arm64 -t devcon-workshop .` (about an hour).
