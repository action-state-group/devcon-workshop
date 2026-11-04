#!/usr/bin/env bash
# run.sh [image]: run the Studio layer from a laptop. Same ports and volume idea as the workshop image's
# `docker run`, plus ~/devcon8-studio on the laptop mounted at ~/studio in the container, so the
# rehearsal pages and Result JSON open from the laptop's browser. Inside: devcon8 brain claude (a
# subscription login, no API key), then devcon8 nanda, then devcon8-studio [--buy <address>].
set -euo pipefail
img=${1:-devcon-workshop-studio:dev}
mkdir -p "$HOME/devcon8-studio"
# A second run resumes the stopped container (same home, same login) instead of failing on its name.
if docker container inspect devcon8-studio >/dev/null 2>&1; then exec docker start -ai devcon8-studio; fi
exec docker run -it --name devcon8-studio -v devcon8-studio-home:/home/participant \
  -v "$HOME/devcon8-studio:/home/participant/studio" \
  -p 127.0.0.1:3141:3132 -p 127.0.0.1:8080:8080 -p 127.0.0.1:9611-9614:9621-9624 "$img"
