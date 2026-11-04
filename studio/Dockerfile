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
COPY studio/requirements.txt /tmp/studio-requirements.txt
# A venv, not the system Python: Ubuntu's Python is externally managed.
RUN apt-get update && apt-get install -y --no-install-recommends python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/devcon8/studio \
    && python3 -m venv /opt/devcon8/studio/venv \
    && /opt/devcon8/studio/venv/bin/pip install --no-cache-dir -r /tmp/studio-requirements.txt \
    && rm /tmp/studio-requirements.txt
RUN git clone --filter=blob:none "$STUDIO_SKILLS_REPO" /opt/devcon8/studio/skills-src \
    && git -C /opt/devcon8/studio/skills-src checkout --detach "$STUDIO_SKILLS_COMMIT" \
    && rm -rf /opt/devcon8/studio/skills-src/.git \
    && test -x "/opt/devcon8/studio/skills-src/$STUDIO_TERMS_ENTRY" \
    && mkdir -p /opt/devcon8/agent/skills \
    && cp -r /opt/devcon8/studio/skills-src/skills/terms-pack-author /opt/devcon8/agent/skills/terms-pack-author
# devcon8 trade runs trader.yaml; in the layer only, let TRADE_RECIPE name another recipe. The edit fails
# the build if trade.sh no longer has the line, and the base image's file is not changed.
RUN sed -i 's#--recipe "$D/agent/recipes/trader.yaml"#--recipe "${TRADE_RECIPE:-$D/agent/recipes/trader.yaml}"#' /opt/devcon8/lib/trade.sh \
    && grep -q 'TRADE_RECIPE:-' /opt/devcon8/lib/trade.sh
COPY studio/versions.lock /opt/devcon8/studio/versions.lock
COPY studio/bin/ /opt/devcon8/agent/bin/
COPY agent/recipes/studio.yaml /opt/devcon8/agent/recipes/studio.yaml
COPY tests/studio-recipe.sh tests/studio-layer.sh /opt/devcon8/tests/
RUN chmod -R a+rX /opt/devcon8/studio /opt/devcon8/agent /opt/devcon8/tests
USER participant
WORKDIR /home/participant
