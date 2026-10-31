# syntax=docker/dockerfile:1.7
# Devcon 8 workshop participant image. Build one architecture natively per runner:
#   docker buildx build --platform linux/arm64 -t devcon-workshop:dev .
# Every input is pinned in versions.lock; see README.md "What is in the image". mesh-llm is the lab
# build, compiled here from its commit for each architecture; the plugins are release assets.

# Ubuntu 24.04 (glibc 2.39): the S08 release pair is built on it and needs that glibc.
ARG BASE=ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852

# --- release assets, models, Go and Node: downloaded and sha256-checked ---------------------------
FROM ${BASE} AS fetch
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
    && rm -rf /var/lib/apt/lists/*
COPY versions.lock /src/versions.lock
COPY build/fetch.sh /src/build/fetch.sh
RUN /src/build/fetch.sh "$TARGETARCH" /fetch && rm -rf /fetch/dl

# --- shared Rust and Node toolchain for the source builds -----------------------------------------
FROM ${BASE} AS toolchain
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git cmake ninja-build pkg-config libssl-dev libdbus-1-dev python3 \
      build-essential jq patchelf xz-utils mold lld \
    && rm -rf /var/lib/apt/lists/*
COPY versions.lock /src/versions.lock
COPY --from=fetch /fetch/opt/node /usr/local/node
ENV PATH=/root/.cargo/bin:/usr/local/node/bin:$PATH CARGO_NET_GIT_FETCH_WITH_CLI=true
RUN . /src/versions.lock \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain "$RUST_TOOLCHAIN" \
    && cargo install --locked just --version "$JUST_VERSION"

# --- mesh-llm lab build: host, CPU native runtimes ------------------------------------------------
FROM toolchain AS mesh
ARG TARGETARCH
RUN . /src/versions.lock && git clone --filter=blob:none "$MESH_LLM_REPO" /build/mesh-llm \
    && git -C /build/mesh-llm checkout --detach "$MESH_LLM_SHA"
WORKDIR /build/mesh-llm
# mesh-llm's build requires sccache (.cargo/config.toml, the with-lld recipe); its own installer checks the archive
# against the release's published .sha256. Version as in mesh-llm's mesh/deploy/fly/Dockerfile.
RUN TARGETARCH="$TARGETARCH" SCCACHE_VERSION=0.16.0 scripts/install-sccache.sh \
    && npm install -g "$(node -p 'require("./mesh/crates/mesh-llm-ui/package.json").packageManager')"
# No MESH_LLM_POSTHOG_KEY: the build carries no analytics key (design section 6).
RUN --mount=type=cache,id=devcon-cargo-registry-${TARGETARCH},target=/root/.cargo/registry \
    scripts/package-native-runtime.sh --build --backend cpu \
    && scripts/build-release.sh \
    && mkdir -p /out/bin/native-runtimes \
    && cp target/release/mesh-llm /out/bin/mesh-llm \
    && find dist/native-runtimes -mindepth 1 -maxdepth 1 -type d -exec cp -a {} /out/bin/native-runtimes/ \; \
    && /out/bin/mesh-llm --version | tee /out/version

# --- s08's liar plugin: capsules 0.1.5 plus selective-log.patch -----------------------------------
FROM toolchain AS redteam
ARG TARGETARCH
COPY demos/s08-liar/redteam/selective-log.patch /src/selective-log.patch
COPY --from=fetch /fetch/opt/s08/dist/ /release/
RUN . /src/versions.lock && git clone --filter=blob:none "$CAPSULES_REPO" /build/capsules \
    && git -C /build/capsules checkout --detach "$S08_CAPSULES_SHA" && git -C /build/capsules apply /src/selective-log.patch
WORKDIR /build/capsules/crates/evidence-plugin
RUN --mount=type=cache,id=devcon-cargo-registry-${TARGETARCH},target=/root/.cargo/registry \
    . /src/versions.lock \
    && case "$TARGETARCH" in amd64) triple=x86_64-unknown-linux-gnu;; arm64) triple=aarch64-unknown-linux-gnu;; esac \
    && cargo build --locked --release --bin capsules \
    && mkdir /pkg && tar -xzf "/release/capsules-$S08_CAPSULES_VERSION-$triple.tar.gz" -C /pkg \
    && cp target/release/capsules /pkg/capsules/capsules && chmod 755 /pkg/capsules/capsules \
    && touch -r /pkg/capsules/plugin.toml /pkg/capsules/capsules \
    && [ "$(/pkg/capsules/capsules --print-package-manifest | jq -S .)" = "$(jq -S . /pkg/capsules/plugin-manifest.json)" ] \
    && mkdir -p /out \
    && (cd /pkg && tar --sort=name --format=ustar --owner=0 --group=0 --numeric-owner -cf - capsules) \
       | gzip -n -9 > "/out/capsules-$S08_CAPSULES_VERSION-selective-log-$triple.tar.gz"

# --- npm CLIs (claude, codex and their ACP adapters) ----------------------------------------------
FROM ${BASE} AS npm
COPY --from=fetch /fetch/opt/node /usr/local/node
ENV PATH=/usr/local/node/bin:$PATH
WORKDIR /opt/devcon8/npm
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force

# --- Go programs: the SDK example, vendored so it builds offline ----------------------------------
FROM ${BASE} AS gobuild
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git && rm -rf /var/lib/apt/lists/*
COPY --from=fetch /fetch/opt/go /usr/local/go
ENV PATH=/usr/local/go/bin:$PATH CGO_ENABLED=0 GOFLAGS=-trimpath GOTOOLCHAIN=local
COPY examples/ /src/examples/
RUN cd /src/examples/go-seal && go mod download && go mod vendor && go build -mod=vendor -o /out/go-seal .
# capsulectl and capsulectl-deal from source (versions.lock), stamped with one core version.
COPY versions.lock /src/versions.lock
RUN . /src/versions.lock && mkdir -p /out/skills \
    && git clone --filter=blob:none "$DEAL_REPO" /build/deal && git -C /build/deal checkout --detach "$DEAL_SHA" \
    && git clone --filter=blob:none "$CAPSULE_CLI_REPO" /build/cli && git -C /build/cli checkout --detach "$CAPSULE_CLI_SHA" \
    && cd /build/deal && core=$(go list -m -f '{{.Version}}' github.com/action-state-group/capsule-cli) \
    && [ "$(go mod download -json "github.com/action-state-group/capsule-cli@$core" | sed -n 's/.*"Hash": "\([0-9a-f]*\)".*/\1/p')" = "$CAPSULE_CLI_SHA" ] \
    && pkg=github.com/action-state-group/capsule-cli/cli \
    && go build -buildvcs=false -ldflags "-s -w -buildid= -X $pkg.CLIVersion=$core -X $pkg.CLICommit=$CAPSULE_CLI_SHA -X $pkg.PluginVersion=$DEAL_SHA -X $pkg.PluginCommit=$DEAL_SHA" \
         -o /out/capsulectl-deal ./cmd/capsulectl-deal \
    && cp -R skills/deal /out/skills/deal \
    && cd /build/cli && go build -buildvcs=false -ldflags "-s -w -buildid= -X $pkg.CLIVersion=$core -X $pkg.CLICommit=$CAPSULE_CLI_SHA" \
         -o /out/capsulectl ./cmd/capsulectl

# --- the participant image ------------------------------------------------------------------------
FROM ${BASE}
ARG TARGETARCH
ARG BUILD_REVISION=unknown
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates libgomp1 libdbus-1-3 bash curl jq openssl iproute2 procps python3 git tini less xxd \
    && rm -rf /var/lib/apt/lists/* \
    && (userdel -r ubuntu 2>/dev/null || true) \
    && useradd --create-home --uid 1000 --shell /bin/bash participant
ENV D=/opt/devcon8
COPY --from=fetch /fetch/opt/bin/ $D/bin/
COPY --from=fetch /fetch/opt/node/ $D/node/
COPY --from=fetch /fetch/opt/go/ $D/go/
COPY --from=fetch /fetch/opt/mesh/plugins/ $D/mesh/plugins/
COPY --from=fetch /fetch/opt/s08/ $D/s08/
COPY --from=fetch /fetch/opt/models/ $D/models/
COPY --from=mesh /out/bin/ $D/mesh/bin/
COPY --from=fetch /fetch/opt/mesh/capsules.version $D/mesh/capsules.version
COPY --from=redteam /out/ $D/s08/dist/
COPY --from=npm /opt/devcon8/npm/ $D/npm/
COPY --from=gobuild /src/examples/go-seal/ $D/examples/go-seal/
COPY --from=gobuild /out/go-seal $D/bin/go-seal
COPY --from=gobuild /out/capsulectl /out/capsulectl-deal $D/bin/
COPY --from=gobuild /out/skills/ $D/agent/skills/
COPY versions.lock $D/versions.lock
COPY bin/ $D/bin/
COPY lib/ $D/lib/
COPY demos/ $D/demos/
COPY agent/bin/ $D/agent/bin/
COPY agent/recipes/ $D/agent/recipes/
COPY agent/fixtures/sticker.png $D/agent/fixtures/sticker.png
COPY agent/fixtures/x402/ $D/agent/fixtures/x402/
COPY README.md $D/README.md
COPY tests/smoke.sh tests/sim-payment.sh $D/tests/
# claude: the Claude Code CLI that claude-agent-acp's SDK bundles, so it ships once (package.json).
RUN case "$TARGETARCH" in amd64) a=x64;; arm64) a=arm64;; esac \
    && ln -s "$D/npm/node_modules/@anthropic-ai/claude-agent-sdk-linux-$a/claude" $D/bin/claude
RUN chmod -R a+rX $D \
    && { echo "build_revision=$BUILD_REVISION"; echo "arch=$TARGETARCH"; \
         echo "mesh_llm=$($D/mesh/bin/mesh-llm --version)"; \
         echo "capsules=$(cat $D/mesh/capsules.version)"; \
         echo; cat $D/versions.lock; echo; \
         cd $D && find . -type f ! -path './npm/*' ! -path './node/*' ! -path './go/*' ! -name MANIFEST -print0 | sort -z | xargs -0 sha256sum; \
       } > $D/MANIFEST
ARG MESH_LLM_SHA
ARG CAPSULES_COMMIT
ARG CAPSULES_VERSION
ARG LEXE_VERSION
LABEL org.opencontainers.image.source=https://github.com/action-state-group/devcon-workshop \
      org.opencontainers.image.revision=$BUILD_REVISION \
      org.opencontainers.image.description="Devcon 8 workshop participant image" \
      dev.actionstate.mesh-llm=$MESH_LLM_SHA \
      dev.actionstate.capsules="$CAPSULES_VERSION $CAPSULES_COMMIT" \
      dev.actionstate.lexe-wallet=$LEXE_VERSION
ENV PATH=$D/bin:$D/agent/bin:$D/mesh/bin:$D/npm/node_modules/.bin:$D/node/bin:$D/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DO_NOT_TRACK=1 GOTOOLCHAIN=local
USER participant
WORKDIR /home/participant
VOLUME /home/participant
EXPOSE 3131 8080 9611-9614
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/devcon8/bin/devcon8-entry"]
CMD ["bash", "-l"]
