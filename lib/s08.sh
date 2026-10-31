#!/usr/bin/env bash
# s08.sh setup|<step>: the S08 liar demo, four nodes on a private mesh inside this container.
# setup copies the scripts to ~/s08-liar (on the volume) and links the image's release pair and models.
set -euo pipefail
. /opt/devcon8/lib/common.sh
S=${DEVCON8_S08:-$HOME/s08-liar}
export DEVCON8_S08=$S S08_LISTEN_ALL=1
setup() {
  mkdir -p "$S"
  cp "$D"/demos/s08-liar/*.sh "$S"/ && cp -R "$D/demos/s08-liar/redteam" "$S"/ && chmod u+w "$S"/*.sh
  for l in bin dist; do ln -sfn "$D/s08/$l" "$S/$l"; done
  ln -sfn "$D/models" "$S/models"
  echo "S08 is set up in $S. Next: devcon8 s08 start (up to a few minutes per node on a laptop CPU)."
}
step() { [ -x "$S/$1" ] || setup; cd "$S" && exec "./$1"; }
case "${1:-help}" in
  setup) setup ;;
  fresh) step 00-fresh.sh ;; start) step 01-start.sh ;; lie) step 02-lie.sh ;; twins) step 03-twins.sh ;;
  referee) step 04-referee.sh ;; show) step 05-show.sh ;; omit) step 06-omit.sh ;; count) step 07-count.sh ;;
  stop) step 99-stop.sh ;;
  *) echo "devcon8 s08 setup|start|lie|twins|referee|show|omit|count|stop|fresh"; [ "${1:-help}" = help ] ;;
esac
