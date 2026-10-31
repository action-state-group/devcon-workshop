# shellcheck shell=bash disable=SC2034  # sourced by every step; the variables are used there
# env.sh: every path and port the demo uses, in one place. Each step sources it.
#
# Four mesh-llm nodes on one private mesh, each with its own HOME under $S/<name>:
#   honest   serves Qwen2.5-0.5B Q8_0, the real file               api 9601  console 9611
#   referee  serves the same Q8_0, the real file                   api 9602  console 9612
#   liar     CLAIMS Q8_0, really runs the smaller Q4_K_M (02-lie)  api 9603  console 9613
#   asker    serves nothing; asks both, then asks a referee         api 9604  console 9614
# None of them is Shockley (the box's own node, with its wallet), and none has a wallet.

S=${DEVCON8_S08:-$HOME/s08-liar}   # in the workshop image: on the participant volume (devcon8 s08 setup links bin, dist, models)
export DO_NOT_TRACK=1   # mesh-llm sends no usage reports from any demo node (installs included)
MESH_LLM=$S/bin/mesh-llm                                   # mesh-llm v0.78.1, the release build
CAPSULES_ARCHIVE=$S/dist/capsules-0.1.5-$(uname -m)-unknown-linux-gnu.tar.gz   # capsules 0.1.5, the release
# The liar alone runs 0.1.5 plus redteam/selective-log.patch (built by the image's Dockerfile, never released).
# It behaves exactly like the release until OMIT_TOGGLE exists; then it seals every second exchange it serves.
CAPSULES_RED_ARCHIVE=$S/dist/capsules-0.1.5-selective-log-$(uname -m)-unknown-linux-gnu.tar.gz
OMIT_TOGGLE=$S/liar/selective-log.on

MODEL_REF=Qwen/Qwen2.5-0.5B-Instruct-GGUF:Q8_0             # what every server says it serves
HF_REPO_DIR=models--Qwen--Qwen2.5-0.5B-Instruct-GGUF
HF_REV=9217f5db79a29953eb74d5343926648285ec7e67
Q8_FILE=qwen2.5-0.5b-instruct-q8_0.gguf
Q8_SHA=ca59ca7f13d0e15a8cfa77bd17e65d24f6844b554a7b6c12e07a5f89ff76844e   # the real Q8_0 file
Q4_GGUF=$S/models/qwen2.5-0.5b-instruct-q4_k_m.gguf                         # the file the liar really runs
Q4_SHA=74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db

api()     { case $1 in honest) echo 9601;; referee) echo 9602;; liar) echo 9603;; asker) echo 9604;; esac; }
console() { echo $(( $(api "$1") + 10 )); }
q8_path() { echo "$S/$1/home/.cache/huggingface/hub/$HF_REPO_DIR/snapshots/$HF_REV/$Q8_FILE"; }

# Swap each node's long hex ids for its name in anything we print.
names() {
  local sed_args=() n id key
  for n in honest referee liar asker; do
    [ -s "$S/$n/ident" ] || continue
    read -r id key < "$S/$n/ident"
    sed_args+=(-e "s/$key/<$n key>/g" -e "s/${id:0:10}[0-9a-f]*/<$n>/g")
  done
  if [ ${#sed_args[@]} -gt 0 ]; then sed "${sed_args[@]}"; else cat; fi
}
