#!/usr/bin/env bash
# s08.sh setup|<step>: the S08 liar demo, four nodes on a private mesh inside this container.
# setup copies the scripts to ~/s08-liar (on the volume) and links the image's release pair and models.
set -euo pipefail
. /opt/devcon8/lib/common.sh
S=${DEVCON8_S08:-$HOME/s08-liar}
export DEVCON8_S08=$S S08_LISTEN_ALL=1
Q8=qwen2.5-0.5b-instruct-q8_0.gguf Q4=qwen2.5-0.5b-instruct-q4_k_m.gguf
setup() {
  mkdir -p "$S"
  cp "$D"/demos/s08-liar/*.sh "$S"/ && chmod u+w "$S"/*.sh
  ln -sfn "$D/mesh/bin" "$S/bin-lab"      # the lab mesh-llm the image ships, with its native runtimes
  ln -sfn "$D/s08/bin-tools" "$S/bin-tools"
  ln -sfn "$D/s08/dist" "$S/dist"
  rm -f "$S/bin"
  # mesh-llm refuses an HF snapshot whose blob link leaves the cache, so the Q8 file the three servers
  # hard-link (01-start.sh) must be a real file on this volume: one 0.7 GB copy.
  [ -L "$S/models" ] && rm "$S/models"
  mkdir -p "$S/models"
  [ -f "$S/models/$Q8" ] || { echo "copying the Q8_0 model to the volume (0.7 GB, once)..." >&2; cp "$D/models/$Q8" "$S/models/$Q8.part" && mv "$S/models/$Q8.part" "$S/models/$Q8"; }
  ln -sfn "$D/models/$Q4" "$S/models/$Q4"
  echo "S08 is set up in $S. Next: devcon8 s08 start (up to a few minutes per node on a laptop CPU)."
}
# Every step refreshes the scripts from this image first, so an upgraded image never runs old copies.
step() { setup >/dev/null; cd "$S" && exec "./$1" "${@:2}"; }
case "${1:-help}" in
  setup) setup ;;
  fresh) step 00-fresh.sh ;; start) step 01-start.sh ;; lie) step 02-lie.sh ;;
  # On an arm64 CPU, Q4_K_M and Q8_0 write the same ocean haiku word for word (seen 10-31), so the
  # default is the other tested question, which parts at word 1 there. Any question may be passed.
  twins) step 03-twins.sh "${2:-Name three colors.}" ;;
  referee) step 04-referee.sh ;; show) step 05-show.sh ;; omit) step 06-omit.sh ;; count) step 07-count.sh ;;
  ask) step 08-ask.sh "${@:2}" ;;
  stop) step 99-stop.sh ;;
  *) echo "devcon8 s08 setup|start|lie|twins|referee|show|omit|count|ask|stop|fresh"; [ "${1:-help}" = help ] ;;
esac
