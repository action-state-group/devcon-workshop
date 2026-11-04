# Devcon 8 workshop image

One container you run on your own laptop for the Devcon 8 S08 workshop (held on Tue Nov 3, 15:00-16:00 IST, 09:30-10:30 UTC;
the steps still work for anyone running them later). It lets you:

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

New here? [WORKSHOP.md](WORKSHOP.md) walks through the workshop step by step, with screenshots.

Inference runs on your CPU (Docker on a Mac has no GPU access). The image is about 3 GB (3.0 GiB on arm64, 3.1 GiB on amd64).

## Before the workshop

You need Docker (Docker Desktop on macOS or Windows, Docker Engine on Linux) with at least **8 GB of
memory** for the container (Docker Desktop: Settings > Resources) and enough free disk (see "Disk space" below).
If you have both Colima and Docker Desktop: run `docker context ls`; if the starred context is colima, run `docker context use desktop-linux`.
**Intel Macs are not supported.** Apple-silicon Macs use the `arm64` image; Windows and x86 Linux machines use `amd64`. Docker picks the right one for `latest`, the tag and the digest below.

### Disk space

Docker keeps images, containers and volumes in one disk (Docker Desktop: a disk image; Colima: a VM disk), and it is the
free space *inside* that disk that counts, not your laptop's. Plan for these (measured on the Nov 4 images, `latest`
`sha256:4402db35…`; the models download that is planned will change the first row):

| What | Download | On disk once loaded |
|---|---|---|
| Full image (`latest`) | 1.9 GB | 3.2 GB |
| Slim `v4-goose` | 0.64 GB | 1.9 GB |
| USB stick path | 1.9 GB copy of the tarball on your laptop, then `docker load` | 1.9 GB tarball + 3.2 GB loaded; delete `~/devcon8-usb` afterwards |
| Each container (shell, nothing built) | - | about 15 MB |
| Each volume (`devcon8-home`, after node, trades and logins) | - | about 120 MB; grows with use |

So keep **at least 10 GB free** in Docker's disk for the full image (a second pull of a newer `latest` briefly holds two
copies), or 5 GB for the slim one. Every extra volume (a second agent such as `devcon8b-home`) adds its own 120 MB.

Check it:

    docker system df          # images, containers, volumes, build cache; RECLAIMABLE is what a prune can free
    docker info | grep -i "docker root dir"
    df -h /                   # your laptop; on a Mac, Docker's disk file lives inside this space

`devcon8 doctor` (inside the container) prints the free disk the container sees. Docker Desktop: Settings > Resources > Disk image
size shows and raises the limit. Colima: `colima list` shows DISK; to raise it, `colima stop`, then `colima start --disk 100`
(it can grow, not shrink; not run here).

If the disk fills, `docker pull` or `docker load` fails with `no space left on device` (Docker's standard message; not
reproduced here), usually part way through a layer. Free space, then run the same command again.

Clean up safely. These never touch a volume:

    docker container prune     # removes stopped containers
    docker image prune -a      # removes images no container uses (you pull again next time); keeps the ones a container uses
    docker builder prune       # build cache (only if you built images yourself)

**Do not run `docker volume prune -a`, or `docker volume prune` / `docker system prune --volumes` on a Docker older than 23.**
Newer Docker's plain `volume prune` removes only anonymous volumes (`docker volume prune --help` says so; `devcon8-home` is
named), but `-a` and older versions remove every volume no container uses, and that includes `devcon8-home` while its
container is stopped or removed: your logins, mailbox key and deals go with it. Check `docker volume ls` before you remove one by name.

**Start over, or free the volumes' disk.** `docker rm -f devcon8` removes only the container: the volume `devcon8-home` (your
logins, mailbox key, deals, and any downloaded models) stays, and keeps taking disk. To remove both (and the second agent's):

    docker rm -f devcon8 devcon8b
    docker volume rm devcon8-home devcon8b-home
    docker volume ls

This **deletes** the logins, the mailbox key (you would run `devcon8 nanda <email>` again) and the deals. If `docker volume rm`
answers `volume is in use`, a container, even a stopped one, still uses it: `docker ps -a --filter volume=devcon8-home` names it;
`docker rm -f` that container, then remove the volume. (Checked with a throwaway volume: Docker 29.5.2 prints that error and the
filter lists the container, also for one that was never started.)

Pull the image ahead of time. Conference wifi is slow:

    docker pull ghcr.io/action-state-group/devcon-workshop:latest

`latest` moves only when a maintainer approves a publish of a tested build from main. On Nov 4 it is the v4 build with goose in auto mode (index digest `sha256:4402db35…`, see "Containers, volumes and coming back" to check what you have). For a reproducible pull, use the digest:

    docker pull ghcr.io/action-state-group/devcon-workshop@sha256:4402db355ac5700999896876e1b97ef04b8c71a87e62b1af9f47f6df6bdc80b9

(The first v4 build, `…b7e05594.139` / `sha256:fde3ab11…`, asks before every goose tool call and can hang on Ctrl-C;)

No network at the venue? Use the USB stick: "From the USB stick (no network)" below replaces this pull and
the `docker run` in "Start".

## Start

    docker run -it --name devcon8 -v devcon8-home:/home/participant \
      -p 127.0.0.1:3141:3132 -p 127.0.0.1:8080:8080 -p 127.0.0.1:9611-9614:9621-9624 \
      ghcr.io/action-state-group/devcon-workshop:latest

(Or the v4 tag or `@sha256:fde3ab11…` reference you pulled.) You get a shell with `devcon8` on the path. `devcon8 help` lists every step. Each step is safe to rerun.
The ports are published on your laptop's loopback only. Later, `docker start -ai devcon8` brings you back.
The console is on port 3141 because Buzz Desktop uses 3131. Inside the container a small relay (port 3132) hands the console its requests from the container's own loopback, which mesh-llm requires for the console's plugin routes (the Evidence tab). A client node hides the Configuration tab by mesh-llm's design. If you started `devcon8` from an older version of these steps, exit its shell (or run `docker stop devcon8`), then `docker rm devcon8`, then `docker pull` the image again and run the `docker run` above (a local copy of `latest` from before Nov 4 is an older image, and `docker run` does not update it); your `devcon8-home` volume keeps your state.

### Containers, volumes and coming back

Two different things hold your work:

- The **container** (`devcon8`) is the running shell. Its name stays taken after you exit.
- The **volume** (`devcon8-home`) holds everything you keep: logins, your Agent Box mailbox key, your node, your deals.

What each command does:

| You want to | Run | Logins, mailbox, deals |
|---|---|---|
| Come back after exiting | `docker start -ai devcon8` | kept |
| Open a second shell in a running container | `docker exec -it devcon8 bash` | kept |
| Stop a stuck or old container, get a fresh one | `docker rm -f devcon8`, then the `docker run` line | kept (they are in the volume) |
| Start completely over | `docker rm -f devcon8 && docker volume rm devcon8-home` | **deleted** |

Exiting the first shell (`exit`, or Ctrl-D) stops the container. `docker run` with a name that exists fails with
"container name already in use": use `docker start -ai devcon8` or remove it first.

**A local `latest` can be stale.** `docker run` never updates an image you already have, and a tag named `latest`
on your laptop stays at whatever you pulled last. Pull again before every session, and check what you have against
the registry's index digest (`sha256:4402db355ac5…` on Nov 4). The two digests must match; the registry one comes from `docker buildx imagetools inspect ghcr.io/action-state-group/devcon-workshop:latest`. A stale tag also shows on start: the container prints `installed plugin capsules <version>`, and an older version than the one in "What is in the image" means an older image:

    docker pull ghcr.io/action-state-group/devcon-workshop:latest
    docker image inspect ghcr.io/action-state-group/devcon-workshop:latest --format '{{index .RepoDigests 0}}'

A running container keeps the image it started from. To move to a newer image: `docker rm -f devcon8`, pull, `docker run` again.

### From the USB stick (no network)

`<TAG>` below is the image tag in the file names on your stick (placeholder until the stick is made from the final image); use the name you see there. The stick holds these three files and one folder in its top folder:

    devcon-workshop-<TAG>-arm64.tar    Apple-silicon Macs, Windows on Arm, arm64 Linux
    devcon-workshop-<TAG>-amd64.tar    Windows and x86 Linux
    SHA256SUMS
    models/                                                                 the two S08 model files (1.1 GB, only for S08)

`docker run` cannot read a tarball: copy the one file for your laptop, check it, `docker load` it, then
run the loaded tag. Each tarball is about 1.9 GB; loading takes 1 to 3 minutes and may print nothing until
the `Loaded image:` line (or shows only layer progress bars). Docker must be running. You need about 4 GB free
disk for the copy plus the loaded image (`devcon8 doctor` only checks disk after the load). Do steps 1 to 5 in
one terminal window, since step 1 sets `A`; if you open a new window, set `A` again.

**1. Pick your file.** Apple-silicon Mac: `arm64` (always, even if `uname -m` says `x86_64` in a terminal opened with Rosetta). Windows or x86 Linux: `amd64`. Check yourself:
`uname -m` prints `arm64` or `aarch64` (use `arm64`) or `x86_64` (use `amd64`); in Windows PowerShell,
`$env:PROCESSOR_ARCHITECTURE` prints `AMD64` (use `amd64`) or `ARM64` (use `arm64`). Intel Macs are not supported.

**2. Copy it from the stick into a folder on your laptop** (set `A` to your arch first):

macOS (the stick appears under `/Volumes`; `ls /Volumes` shows its name, for example `NO NAME`: replace STICKNAME
with it and keep the quotes):

    A=arm64
    cd "/Volumes/STICKNAME" && mkdir -p ~/devcon8-usb && cp devcon-workshop-*-$A.tar SHA256SUMS ~/devcon8-usb/ && cd ~/devcon8-usb

Linux (`ls /media/$USER` shows the stick; on Fedora and Arch use `/run/media/$USER` in its place):

    A=amd64
    cd "/media/$USER/STICKNAME" && mkdir -p ~/devcon8-usb && cp devcon-workshop-*-$A.tar SHA256SUMS ~/devcon8-usb/ && cd ~/devcon8-usb

Windows PowerShell (the stick has a drive letter, for example `E:`):

    $A = "amd64"
    mkdir -Force $HOME\devcon8-usb; copy "E:\devcon-workshop-*-$A.tar","E:\SHA256SUMS" $HOME\devcon8-usb; cd $HOME\devcon8-usb

**3. Check the file.** macOS (reads only your arch's line from `SHA256SUMS`; it must print `OK`):

    grep -e "-$A.tar" SHA256SUMS | shasum -a 256 -c

Linux: the same with `sha256sum -c` in place of `shasum -a 256 -c`. Windows: this prints `True` when the file is intact:

    (Get-FileHash devcon-workshop-*-$A.tar).Hash -eq (Select-String "-$A.tar" SHA256SUMS).Line.Split(' ')[0]

Not `OK` (or `False`): the copy is incomplete, copy it again.

**4. Load it.** `docker load -i` takes the file name (the `*` fills in the tag):

    docker load -i devcon-workshop-*-$A.tar

(PowerShell: `docker load -i (Get-ChildItem devcon-workshop-*-$A.tar).Name`.) It ends with
`Loaded image: ghcr.io/action-state-group/devcon-workshop:<TAG>-arm64`
(or `-amd64`). A loaded image is not called `latest`, so the run line below names this tag.

**5. Start the container.** Pick the line for your arch (`--pull never` stops Docker from going to the network):

arm64:

    docker run -it --pull never --name devcon8 -v devcon8-home:/home/participant \
      -p 127.0.0.1:3141:3132 -p 127.0.0.1:8080:8080 -p 127.0.0.1:9611-9614:9621-9624 \
      ghcr.io/action-state-group/devcon-workshop:<TAG>-arm64

amd64: the same line ending in `<TAG>-amd64`. In PowerShell write it on one line
(without the `\` line ends). Then run `devcon8 doctor` in the shell you get. `No such image` means the load
in step 4 did not finish, or the arch suffix differs from the one it printed.

**S08 needs two model files** (1.1 GB). They are not in the image. With a network, `devcon8 models` downloads
them into your volume. From the stick, copy its `models` folder next to the tarball in step 2
(`cp -r "/Volumes/STICKNAME/models" ~/devcon8-usb/` on macOS), then, with the container running
(`docker run` above, in another terminal), hand it to the container and load it:

    docker cp ~/devcon8-usb/models devcon8:/tmp/
    devcon8 models --from /tmp/models

`devcon8 models` checks each file's sha256 and skips files it already has. Skip this if you only run the trade.

### The slim `v4-goose` image (trade only, 631 MB)

For the sticker trade alone there is a smaller image, `ghcr.io/action-state-group/devcon-workshop:v4-goose`. It is v4
without the models, mesh-llm and its plugins, and S08.

    docker run -it --name devcon8 -v devcon8-home:/home/participant ghcr.io/action-state-group/devcon-workshop:v4-goose

- **Works** (run on the 2026-11-04 tag; `brain claude|codex` and `nanda` need a login or email code and were not run on it): `doctor`, `go-seal`, and `s02` (it serves on port 8080, so add `-p 127.0.0.1:8080:8080` to the run line to open it). `trade` starts only after `nanda`.
- **Does not work:** `join` (it accepts an invite, then fails with `cat: /opt/devcon8/mesh/capsules.version: No such file or directory`), `node`, `wallet` ("your node is not running"), `s08` (`/opt/devcon8/lib/s08.sh: No such file or directory`), `brain mesh` (not offered), and the console on port 3141.
- It is a derived tag of v4 (not rebuilt by CI) and does not move with `latest`. On Nov 4 its `devcon8 trade` script is the same as `latest`'s (auto mode, `DEVCON8_GOOSE_MODE`, goose run as a child for Ctrl-C); a later `latest` may get fixes it lacks.

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

- `claude`: your Claude subscription. It prints a link; open it on your laptop, sign in, paste the code
  back, and it says whether login worked. Already logged in, it says so and keeps the login;
  `devcon8 brain claude --relogin` signs in again.
- `codex`: your ChatGPT subscription, by device login. Turn on device code login in ChatGPT's security
  settings first. **Codex login**: if that is not possible, copy your laptop's `~/.codex/auth.json` in,
  from a laptop terminal (this keeps it readable only by the container's user), then run
  `devcon8 brain codex` again:
  `docker exec -i devcon8 sh -c 'mkdir -p ~/.codex && umask 077 && cat > ~/.codex/auth.json' < ~/.codex/auth.json`
- `mesh`: chat with the mesh's own models through your node. A 0.5B model cannot run the trading
  agent; use `claude` or `codex` for that.

### 4. `devcon8 s02`: the settlement record

Open http://127.0.0.1:8080/settlement-record.html. One Lightning payment between two demo nodes, as two
signed halves under two keys, checked in your browser, offline. `/opt/devcon8/demos/s02/README.md` (inside the container) has the same check
on the command line.

### 5. `devcon8 s08 <step>`: catch a lying node

First `devcon8 models` (once): it downloads the two Qwen2.5-0.5B model files, 1.1 GB, into `~/.devcon8/models`
on your volume, checks their sha256 and skips what it already has; interrupted, run it again to resume.
Without them `devcon8 s08` says "run devcon8 models first".

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

**Already have a mailbox?** On the same `devcon8-home` volume the key is already there: if no other container has run
`devcon8 nanda` for this mailbox since, there is nothing to do. If one has, this container is off duty and `devcon8 trade`
starts but the agent does not answer; run `devcon8 nanda <email>` again and it takes the mailbox back. On a new container,
a new volume or another laptop, run the same command with the same email:

    devcon8 nanda <the email you used the first time>

It asks "Create the mailbox for ...?" (it says Create even for a mailbox that exists): answer `y`. The gateway returns your existing mailbox (the same address, and no
second listing in the NANDA Index) with a new key, emails a new six-digit code to the same address, and asks you for
it. Checked on 2026-11-04 on a local build of the v4 sources. Only one container answers for the mailbox at a time: the one that ran
`devcon8 nanda` last takes over, and the older container can still read the mailbox but no longer answers from it. On a new volume it also starts your agent after the mailbox's newest message, so messages from earlier runs are not replayed into `devcon8 trade`.

### 7. `devcon8 trade [--buy <address>] [--pay lexe]`: the trading agent

Your agent sells your digital fox sticker for 50 cents (in a `--pay lexe` run, for your Lightning price in msat) to any participant's agent that asks. With
`--buy <their address>@agentboxnanda.org` it also buys one from that participant's agent, the address
they give you. It buys only from that address, never from search results.

- Every trade, `--pay lexe` included, runs goose in auto mode, so mailbox waits and file reads do not each ask you (`DEVCON8_GOOSE_MODE=approve devcon8 trade` asks before every tool call). Before each offer, commitment and
  payment the agent runs a final check; when the check pauses ("PAUSED FOR YOU"), the agent shows
  you its card in the chat and seals your answer. Say no and it holds.
- Ctrl-C: the first press interrupts the agent's turn; the second makes goose print "session closed", and within about a second the run ends and you are back at the shell prompt (exit code 130, no "Killed" line). If the prompt does not come back, press Ctrl-C once more; if it still hangs, close the terminal and use `docker start -ai devcon8`.
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
- **Your History card.** After a sale or purchase, make your History card: a count of your deals as of a checkpoint, with no
  deal's content. Once per profile, say who holds it, then cut a checkpoint (the card is as of your newest one), then write the card
  and its page:

  ```sh
  capsulectl --profile deal deal standard-history declare --holder-kind person
  capsulectl --profile deal deal tick
  capsulectl --profile deal deal standard-history card --out ~/deals/history-card.bundle
  capsulectl presentation build --bundle ~/deals/history-card.bundle --out ~/deals/history-card.html
  ```

  If `card` says "the History card was not built: ...", the line names what to do (for example, run `deal tick` again, then ask again).
  A Lightning (`--pay lexe`) deal is counted as BTC in msat. The workshop trade does not compare your record of a deal with the other side's, so every deal on your card shows "we couldn't tell". That means no comparison was made, not that the trade failed.
  Some other `capsulectl` failures print only "operation failed; check input, selected profile, permissions and service availability" and
  hide the cause.

### Trade with yourself: a walkthrough (simulated payment)

One person plays both sides in two containers: a seller that sells your sticker and a buyer that buys it. You need two
email addresses that can each receive a six-digit code (one per mailbox; if you already have a mailbox, use its email for
one side and a new email for the other), and a Claude or ChatGPT login for the agent in each container. Use two terminal
windows. No money moves. goose runs in auto mode: it does not ask before each tool call, but the agent still stops at a
"PAUSED FOR YOU" card before an offer, a commitment and a payment, and you answer those in the chat.

**0. Get the image again.** Pull `latest` even if you pulled before, since an older local copy is an older image:

    docker pull ghcr.io/action-state-group/devcon-workshop:latest

Remove old containers of these names from earlier tries (your volumes, logins and mailboxes are kept):

    docker rm -f devcon8 devcon8b

(On a first try it prints "No such container"; that is fine.)

**1. The seller, terminal 1.** The trade runs over Agent Box mailboxes, not over mesh-llm, so neither container publishes a port
(port 3141 in the steps above is the mesh-llm node console, which this trade does not use):

    docker run -it --name devcon8 -v devcon8-home:/home/participant ghcr.io/action-state-group/devcon-workshop:latest

From the USB stick, add `--pull never` and use the loaded tag (`<TAG>-arm64` or `-amd64`) in place of
`:latest`, for both containers. Inside the container:

    devcon8 brain claude          # open the link it prints, sign in, paste the code back
    devcon8 nanda <seller email>  # answer y; type the six-digit code sent to that email
    devcon8 trade                 # sell only; goose waits for a buyer

`devcon8 nanda` prints the agent's address, for example `shop1@agentboxnanda.org`: that is the seller address. When it says
"Registering in the NANDA Index (up to 10 minutes)...", you can press Ctrl-C: the mailbox is already ready. (`brain codex`
works the same way if you use ChatGPT.)

**2. The buyer, terminal 2.** A second container with its own volume:

    docker run -it --name devcon8b -v devcon8b-home:/home/participant ghcr.io/action-state-group/devcon-workshop:latest

Inside it:

    devcon8 brain claude
    devcon8 nanda <buyer email>              # a different email gives a different mailbox
    devcon8 trade --buy <seller address>

**Already have a mailbox?** Use the email you created it with: `devcon8 nanda` asks "Create the mailbox for ...?" (it says
Create even when the mailbox exists), you answer `y`, and the gateway gives back the same address with a new key and a fresh
six-digit code. Only the container that ran `devcon8 nanda` last answers for the mailbox, so do not give two containers the
same mailbox at the same time.

**3. During the trade.** Answer the "PAUSED FOR YOU" cards with yes or no (no holds the deal). The payment is the simulated
50-cent x402 one; the settle response says "SIMULATED". The buyer opens the conversation, pays, receives the sticker, checks
its sha256 and confirms; both agents close their deals.

- If one side goes quiet, type: `keep checking the mailbox`
- If both seem to wait, tell the buyer: `Buy one digital fox sticker from <seller address> now`
- Ctrl-C: once interrupts the turn goose is on; a second makes goose print "session closed" and the run ends within about a second, back at your shell.

**4. See the result.** Follow "Find your deals and make a receipt" below (seller: `devcon8`; buyer: `devcon8b`).

**Going back to the other steps.** These containers publish no ports, so the console (3141), `devcon8 s02` (8080) and the S08
Evidence pages are not reachable from them. To go back to those steps, run `docker rm -f devcon8` and start it again with the run
line in "Start"; the `devcon8-home` volume keeps your state.

**5. If a terminal closes.** Exiting a container's first shell stops the container. Bring it back with
`docker start -ai devcon8` (or `devcon8b`); logins, mailbox and deals are on the volume. `docker exec -it devcon8 bash`
opens another shell in a running container.

**History card and known gaps.** See "Your History card" under step 7.

**Clean up.** `docker rm -f devcon8 devcon8b` removes the containers and keeps the volumes (and their disk). To forget the logins,
mailboxes and deals too, and to start over with different emails, run:

    docker rm -f devcon8 devcon8b
    docker volume rm devcon8-home devcon8b-home

This deletes the logins and the mailbox keys (you would run `devcon8 nanda` again) and the deals. `volume is in use` means a container,
even a stopped one, still uses it: `docker ps -a --filter volume=devcon8-home` shows which; remove it first. `docker volume ls`
lists what is left. If you listed a mailbox you will not use again, run `devcon8 nanda leave` inside its container before you remove the
container (permanent; see "Leaving the NANDA Index").

### Find your deals and make a receipt

A receipt is a page for one closed deal. Everything is in the container that ran the trade; the page is copied to your Mac.
Replace `devcon8` with `devcon8b` for the buyer. (`deal list` needs the deal plugin, which `devcon8 trade` installs: on a volume
that never ran `trade` it answers "this needs the capsulectl-deal plugin, which is not installed".)

**1. List the deals**, inside the container, or from the Mac with `docker exec devcon8 bash -lc '<the command>'`:

    capsulectl --profile deal deal list

One tab-separated line per deal (checked in `deal list --help`; no real output captured here yet), in the order
`<id>  <kind>  <state>  <opened>  <last record>  <counterparty fingerprint>  <log id>`:

- the id, `deal-...` or `sale-...`;
- the kind, `deal` or `sale`;
- the state, for example `open` or `closed`;
- when it was opened and when its last record was written;
- the other side's fingerprint, and the log id.

**2. Deal or sale.** A seller has one `sale-...` for each listing and one `deal-...` for each buyer. A buyer has a `deal-...`.
A receipt takes only a `deal-...` id; `deal report` refuses a `sale-...` id.

**3. One receipt, by id.** Inside the container write it, then from your Mac terminal copy it out and open it:

    capsulectl --profile deal deal report --deal <deal id> --html ~/receipt.html
    docker cp devcon8:/home/participant/receipt.html . && open receipt.html

**4. The latest closed deal in one command**, from your Mac terminal (it picks the last line whose kind is `deal` and state is `closed`):

    docker exec devcon8 bash -lc 'id=$(capsulectl --profile deal deal list | awk "\$2==\"deal\" && \$3==\"closed\"{i=\$1} END{print i}"); capsulectl --profile deal deal report --deal "$id" --html ~/receipt.html >/dev/null' && docker cp devcon8:/home/participant/receipt.html . && open receipt.html

The deals themselves are in `~/.local/share/capsule-deal` and the files in `~/deals/` inside each container (the buyer's `sticker.png` is there).

### Make your History card

Your History card counts your deals as of a checkpoint, with no deal's content. The commands are the ones in "Your History card" under
step 7. Run them in the container that holds the deals (`devcon8`, or `devcon8b` for the buyer), after at least one deal has closed.
Nothing in this section has been run end to end yet.

**1. Once per profile**, inside the container, say who holds the card:

    capsulectl --profile deal deal standard-history declare --holder-kind person

**2. Each time you want a new card**, cut a checkpoint first (the card is as of your newest one), then write the card and its page.
`card --out` and `presentation build --out` take a **new** file, so give each card its own name:

    capsulectl --profile deal deal tick
    capsulectl --profile deal deal standard-history card --out ~/deals/card1.bundle
    capsulectl presentation build --bundle ~/deals/card1.bundle --out ~/deals/card1.html

If `card` says "the History card was not built: ...", the line names what to do (for example run `deal tick`, then ask again).
`presentation build` writes the page only when the bundle verifies as VALID.

**3. From your Mac terminal**, all of that and the opening in one command (the file name uses the time, so each run is new):

    docker exec devcon8 bash -lc 'f=~/deals/card-$(date +%s); capsulectl --profile deal deal tick >/dev/null && capsulectl --profile deal deal standard-history card --out $f.bundle && capsulectl presentation build --bundle $f.bundle --out $f.html >/dev/null && cp $f.html ~/history-card.html' && docker cp devcon8:/home/participant/history-card.html . && open history-card.html

(The first time, run step 1 inside the container.)

**4. Your copy and the copy you send.** The card above is your own copy: it holds the deal entries it counts. To hand the card to
someone else, write the shared copy, which has the card, its policy and its anchor but not the deal entries:

    capsulectl --profile deal deal standard-history card --shared --out ~/deals/card1-shared.bundle

**5. What it shows.** A Lightning (`--pay lexe`) deal is counted as BTC in msat. The workshop trade does not compare your record of a deal with the other side's, so every deal on your card shows "we couldn't tell". That means no comparison was made, not that the trade failed.

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
sats. With a funded wallet, every payment of a `--pay lexe` trade still stops for your answer; `DEVCON8_GOOSE_MODE=approve` also asks before each tool call. The sticker trade stays simulated unless you
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
   by these caps). `devcon8 lightning` shows them and what has been paid so far. The deal terms and the
   receipt are in msat: the sticker's price is your `--price-sats`/`--price-msat` (currency `BTC`, where
   the amount counts millisatoshi), so a receipt reads "Paid 500 msat" for a 500 msat sale, not a dollar
   amount. The simulated payment keeps 50 cents. The agent's `lightning` tool reads the caps and has
   no way to raise them; the agent could still edit the file with its shell, which is one more reason
   to run `DEVCON8_GOOSE_MODE=approve devcon8 trade --pay lexe` if you want goose to ask before every command it runs.
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
`dev.actionstate.capsules` = `0.1.15 3b3538179c50ca11c5266d6c0bb3aaca677d5fb3`,
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
| capsules plugin | `v0.1.15` (the shared History view; referee split-margin threshold 0, the default) |
| lexe-wallet plugin | built here from [lexe-wallet-plugin#7](https://github.com/Mesh-LLM/lexe-wallet-plugin/pull/7) (`feat/settled-preimage`, commit `9f830c1`), which reports a settled payment's preimage |
| S08 | the same mesh-llm and capsules; the liar runs capsules 0.1.15 plus `demos/s08-liar/redteam/selective-log.patch`, built here; step 8's `reconcile/` on evidencebook v0.12.2 |
| capsulectl, capsulectl-deal, capsulectl-book | `v0.1.0-rc34` releases (deal carries `capsulectl deal terms-leg`, seals a Lightning payment received and states it in msat) |
| goose (built from its v1.57.0 commit plus `patches/`, aaif-goose/goose#13273), Claude Code, Codex, ACP adapters | `versions.lock`, `package-lock.json` (`claude` is the Claude Code CLI bundled with claude-agent-acp's SDK) |
| evidencebook Go SDK | v0.12.2, Go 1.27 |
| models (not in the image; `devcon8 models` downloads them) | Qwen2.5-0.5B-Instruct GGUF, Q8_0 and Q4_K_M, pinned in `versions.lock` |

The buyer's signed terms leg is written by `capsulectl deal terms-leg`
([evidencebook-deal#70](https://github.com/action-state-group/evidencebook-deal/issues/70)), signed with
the buyer's own deal key.

Build it yourself: `docker buildx build --platform linux/arm64 -t devcon-workshop .` (about an hour).

## Publishing the image (maintainers)

A push to `main` builds the image and runs every test, then stops: the `publish` job in
`.github/workflows/image.yml` waits for approval under the `image-release` environment (Settings, Environments;
required reviewers ethanyzhang and StevenMih, either one suffices; administrators cannot bypass). Open the run in the Actions tab, choose "Review deployments", select
`image-release` and approve. Only then are the per-architecture tags, the multi-arch tag and `latest` pushed,
from the same image bytes the tests ran against. Rejecting the run publishes nothing, and `latest`
stays where it was. Reject a run you will not publish: publishes are serialized, so an unanswered approval holds back every later one. Approve within 14 days: the tested images are kept as run artifacts that long, and after that
the run must be rebuilt. This workflow moves `latest` only from the approved `publish` job.
