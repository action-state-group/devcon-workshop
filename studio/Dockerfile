# syntax=docker/dockerfile:1.7
# The Terms Pack Studio layer: the workshop image plus PyYAML, the Studio scripts and skill, and the
# studio.yaml recipe. Build with studio/build.sh, which reads the pins in studio/versions.lock; the
# context is the repository root. Nothing here changes the published image or its tags.
ARG BASE
FROM ${BASE}
USER root
ARG STUDIO_SKILLS_REPO
ARG STUDIO_SKILLS_COMMIT
ARG STUDIO_TERMS_ENTRY
ARG STUDIO_DEAL_REPO
ARG STUDIO_DEAL_COMMIT
COPY studio/requirements.txt /tmp/studio-requirements.txt
# A venv, not the system Python: Ubuntu's Python is externally managed.
RUN apt-get update && apt-get install -y --no-install-recommends python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/devcon8/studio \
    && python3 -m venv /opt/devcon8/studio/venv \
    && /opt/devcon8/studio/venv/bin/pip install --no-cache-dir -r /tmp/studio-requirements.txt \
    && rm /tmp/studio-requirements.txt
# The checkout sits under capsulectl's trusted plugin root: `capsulectl profile update --rules-checker`
# refuses a checker anywhere else, and `terms publish` pins scripts/studio/terms-checker from here.
RUN mkdir -p /usr/local/lib/capsulectl/plugins \
    && git clone --filter=blob:none "$STUDIO_SKILLS_REPO" /usr/local/lib/capsulectl/plugins/terms-pack-studio \
    && git -C /usr/local/lib/capsulectl/plugins/terms-pack-studio checkout --detach "$STUDIO_SKILLS_COMMIT" \
    && rm -rf /usr/local/lib/capsulectl/plugins/terms-pack-studio/.git \
    && test -x "/usr/local/lib/capsulectl/plugins/terms-pack-studio/$STUDIO_TERMS_ENTRY" \
    && mkdir -p /opt/devcon8/agent/skills \
    && cp -r /usr/local/lib/capsulectl/plugins/terms-pack-studio/skills/terms-pack-author /opt/devcon8/agent/skills/terms-pack-author
# The past sales for step 1: evidencebook-deal's replay script and fixture, run by `devcon8-studio replay`.
RUN git clone --filter=blob:none "$STUDIO_DEAL_REPO" /tmp/deal \
    && git -C /tmp/deal checkout --detach "$STUDIO_DEAL_COMMIT" \
    && mkdir -p /opt/devcon8/studio/replay/scripts /opt/devcon8/studio/replay/testdata \
    && cp /tmp/deal/scripts/studio-replay.sh /opt/devcon8/studio/replay/scripts/ \
    && cp -r /tmp/deal/testdata/studio /opt/devcon8/studio/replay/testdata/studio \
    && test -s /opt/devcon8/studio/replay/testdata/studio/sticker-trades.json \
    && rm -rf /tmp/deal
# devcon8 trade runs trader.yaml; in the layer only, let TRADE_RECIPE name another recipe. The edit fails
# the build if trade.sh no longer has the line, and the base image's file is not changed.
# trade.sh and offers from this checkout: `devcon8-studio --want` finds offers before it buys (devcon-workshop#81).
# The pinned base's trade.sh has no --want; once the pinned base has it, these two lines copy the same files.
COPY lib/trade.sh /opt/devcon8/lib/trade.sh
COPY agent/bin/offers /opt/devcon8/agent/bin/offers
RUN sed -i 's#--recipe "$D/agent/recipes/trader.yaml"#--recipe "${TRADE_RECIPE:-$D/agent/recipes/trader.yaml}"#' /opt/devcon8/lib/trade.sh \
    && grep -q 'TRADE_RECIPE:-' /opt/devcon8/lib/trade.sh
COPY studio/versions.lock /opt/devcon8/studio/versions.lock
COPY studio/bin/ /opt/devcon8/agent/bin/
# mbx from this checkout: a seller's proposal may carry its History card (Studio step 5). The base image's
# mbx predates that; once the pinned base has it, this line is a no-op copy of the same file.
COPY agent/bin/mbx /opt/devcon8/agent/bin/mbx
COPY agent/recipes/studio.yaml /opt/devcon8/agent/recipes/studio.yaml
COPY tests/studio-recipe.sh tests/studio-layer.sh tests/studio-e2e.sh tests/studio-card.sh tests/studio-ruling.sh /opt/devcon8/tests/
RUN chmod -R a+rX /opt/devcon8/studio /opt/devcon8/agent /opt/devcon8/tests /usr/local/lib/capsulectl/plugins/terms-pack-studio
USER participant
WORKDIR /home/participant
