#!/bin/bash
# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2026  Jean-Vincent Loddo
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Update a PUBLISHED guest image without rebuilding it: boot it, change what has to be
# changed inside, shut it down cleanly, export the state as a variant, and hand that variant
# to filesystem.prepare-snapshot-to-publish.sh -- which names the new image after its `sum',
# writes its .conf, its tarball and its SHA256SUMS line.
#
#   Makefile.d/filesystem.update-published-image.sh --image machine-debian-trixie-39212 \
#       --in-guest 'systemctl mask systemd-networkd-wait-online.service'
#
# --- WHY THIS SCRIPT EXISTS ---
#
# The gesture above was done by hand on 2026-09-02 (episode 21 bis of the work-stream
# `marionnet-kernel-rootfs'): fifty minutes, of which thirty seconds were the actual change.
# The rest was six traps, every one of them silent, and this script is those six traps turned
# into code that runs instead of prose to re-read:
#
#   1. A binary built in _build reads the *testing* prefix (the opam switch), not /usr/local:
#      an image sitting in the installed prefix is INVISIBLE to it. Hence the links below.
#   2. Disk#filesystems drops any distribution with no compatible kernel INSTALLED
#      (bin/disk.ml, `initializer filesystems#filter'), without a word: an image whose kernel
#      is not installed simply does not appear in the list. Hence the kernels are linked too.
#   3. `add machine' through the channel gives 48 MiB (bin/machine.ml, memory_default) and
#      never reads MEMORY_SUGGESTED_SIZE, which only the GUI dialog applies: a trixie started
#      that way DIES OF OOM (measured: `Out of memory: Killed process (systemd-network)'),
#      and the machine then answers nothing, which looks like a hang. We read the .conf.
#   4. Exporting the state was not in the channel at all. It is, since episode 22:
#      `history-export', which is why there is no `cp' anywhere here.
#   5. A cow file is a hole: 5.4 GiB apparent for a few MiB of content. Everything that
#      copies one uses --sparse=always -- again, that now belongs to the channel's verb.
#   6. The export must come after a CLEAN shutdown: the cow of a running machine is a
#      filesystem nobody unmounted. `stop' (graceful), never `poweroff'.
#
# --- WHAT IT DOES NOT DO ---
#
# It does not upload anything: publishing and deciding what to do with the previous image are
# the author's gestures (Makefile.d/upload.www.marionnet.org.sh, and the retention question).
# It does not touch the image it starts from: the machine writes to a cow file, in a project
# directory of its own, and the backing file is only ever read -- its mtime is what UML
# checks, and what the .conf of every published image records.
#
# --- NO BASHBRICKS HERE, ON PURPOSE ---
#
# Fifth of a family (the two *.prepare-to-publish.sh, release.sha256sums.sh,
# release.binary.sh), none of which sources anything. What this one does -- write a few
# lines on a socket and read one JSON object back -- is `socat' and `jq', both of them
# already required by Marionnet itself (REQUIRED_PACKAGES_RUNTIME).

set -euo pipefail

function info { echo "==> $*"; }
function warn { echo "$0: warning: $*" >&2; }
function die  { echo "$0: $*" >&2; exit 2; }

function usage {
 cat 1>&2 <<EOF
Usage: $0 --image NAME [OPTIONS]

  --image NAME              the published image to update, e.g. machine-debian-trixie-39212
                            (a bare name: it is looked up in --from)
  --from DIR                where that image and its .conf live
                            (default: website-repo/download/marionnet-install.sh/<series>)
  --kernel PATH             the UML kernel to make visible to Marionnet
                            (default: every linux-* found in --from)
  --in-guest CMD            a command to run INSIDE the guest; repeatable, order kept.
                            A non-zero status stops everything BEFORE the export.
  --in-guest-script FILE    a script to run inside the guest (after the --in-guest commands)
  --variant NAME            name of the exported variant (default: respin-<date>)
  --memory N                MiB given to the machine
                            (default: MEMORY_SUGGESTED_SIZE of the .conf)
  --binary PATH             the marionnet to drive (default: _build/default/bin/marionnet.exe)
  --output-dir DIR          relayed to filesystem.prepare-snapshot-to-publish.sh
  --no-publish              stop after the export: the variant is made, nothing is published
  --keep-project            do not remove the temporary project directory (for a post-mortem)
  -y, --yes                 do not ask before the long steps
  -h, --help                this help

The exit status is 0 only if every step, the guest commands included, succeeded.
EOF
}

# --- Options.
IMAGE=""; FROM=""; KERNEL=""; VARIANT=""; MEMORY=""; BINARY=""; OUTPUT_DIR=""
PUBLISH=1; ASSUME_YES=0; KEEP_PROJECT=0
declare -a IN_GUEST=()
IN_GUEST_SCRIPT=""

while (($#)); do
  case "$1" in
    --image)            IMAGE=${2:-};        shift 2 ;;
    --from)             FROM=${2:-};         shift 2 ;;
    --kernel)           KERNEL=${2:-};       shift 2 ;;
    --in-guest)         IN_GUEST+=("${2:-}"); shift 2 ;;
    --in-guest-script)  IN_GUEST_SCRIPT=${2:-}; shift 2 ;;
    --variant)          VARIANT=${2:-};      shift 2 ;;
    --memory)           MEMORY=${2:-};       shift 2 ;;
    --binary)           BINARY=${2:-};       shift 2 ;;
    --output-dir)       OUTPUT_DIR=${2:-};   shift 2 ;;
    --no-publish)       PUBLISH=0;           shift ;;
    --keep-project)     KEEP_PROJECT=1;      shift ;;
    -y|--yes)           ASSUME_YES=1;        shift ;;
    -h|--help)          usage; exit 0 ;;
    *)                  usage; die "unexpected argument '$1'" ;;
  esac
done

# --- Where we are, and what we need.
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
PUBLISHER="$HERE/filesystem.prepare-snapshot-to-publish.sh"

for cmd in socat jq sum stat; do
  command -v "$cmd" >/dev/null || die "\`$cmd' not found (socat and jq are runtime dependencies of Marionnet)"
done
test -x "$PUBLISHER" || die "no publisher at $PUBLISHER"
test -n "$IMAGE" || { usage; die "--image is required"; }

case "$IMAGE" in
  machine-*) : ;;
  router-*)  die "$IMAGE is a ROUTER image: on the published side it is a symbolic LINK to a
machine image (see filesystem.prepare-snapshot-to-publish.sh), so there is nothing of its own
to update. Update the machine image it points to." ;;
  *)         die "$IMAGE is not an image name (it should begin with \`machine-')" ;;
esac
EPITHET=${IMAGE#machine-}

BINARY=${BINARY:-$ROOT/_build/default/bin/marionnet.exe}
test -x "$BINARY" || die "no executable at $BINARY (build it first: dune build)"

if test -z "$FROM"; then
  # The publisher already knows how to derive the series from META: ask it rather than
  # spelling the path a second time (episode 33: no file pattern spells the version twice).
  SERIES=$("$PUBLISHER" --print-series) || die "cannot derive the publication series"
  FROM="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"
fi
FROM=$(cd -- "$FROM" && pwd) || die "--from: no such directory"
test -r "$FROM/$IMAGE"       || die "no image $FROM/$IMAGE"
test -r "$FROM/$IMAGE.conf"  || die "no configuration $FROM/$IMAGE.conf (an image without its .conf cannot be started)"

if test -z "$MEMORY"; then
  # Trap 3. The .conf knows what this guest needs; the channel does not (yet).
  MEMORY=$(sed -n 's/^MEMORY_SUGGESTED_SIZE=\([0-9][0-9]*\).*/\1/p' "$FROM/$IMAGE.conf" | head -n 1)
  test -n "$MEMORY" || warn "no MEMORY_SUGGESTED_SIZE in $IMAGE.conf: letting Marionnet choose"
fi

VARIANT=${VARIANT:-respin-$(date +%Y-%m-%d-%H%M%S)}
# The channel refuses anything else (Treeview_history, StrExtra.Class.identifierp ~allow_dash:()),
# and it is better to say so before ten minutes of boot than after.
[[ "$VARIANT" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] \
  || die "--variant: '$VARIANT' must begin with a letter and hold only letters, digits, dashes and underscores"

((${#IN_GUEST[@]})) || test -n "$IN_GUEST_SCRIPT" \
  || die "nothing to do inside the guest: give at least one --in-guest CMD or --in-guest-script FILE"
test -z "$IN_GUEST_SCRIPT" || test -r "$IN_GUEST_SCRIPT" || die "--in-guest-script: cannot read $IN_GUEST_SCRIPT"

# --- Visibility (traps 1 and 2).
#
# The links go into ~/.marionnet, the USER search path, which every Marionnet reads whatever
# its compiled prefix. Only what we created is undone on the way out: a link that was already
# there belongs to the user.
USER_FS="$HOME/.marionnet/filesystems"
USER_KERNELS="$HOME/.marionnet/kernels"
declare -a OUR_LINKS=()
SESSION_PID=""
SOCKET=""
PROJECT_DIR=""

function link_if_absent {   # link_if_absent TARGET LINKDIR
  local target=$1 dir=$2 name
  name=$(basename -- "$target")
  mkdir -p -- "$dir"
  if test -e "$dir/$name" || test -L "$dir/$name"; then
    return 0    # already visible, and not ours to remove
  fi
  ln -sfn -- "$target" "$dir/$name"
  OUR_LINKS+=("$dir/$name")
}

function cleanup {
  local rc=$?
  # The session first, by its own pid and only if it still is ours: a pid gets recycled.
  if test -n "$SESSION_PID" && kill -0 "$SESSION_PID" 2>/dev/null; then
    if grep -qz -- "$SOCKET" "/proc/$SESSION_PID/cmdline" 2>/dev/null; then
      # SIGTERM is neutralised by marionnet (bin/marionnet.ml): the channel's `quit' is the
      # polite way, and this is the last resort when a step died before reaching it.
      kill -9 "$SESSION_PID" 2>/dev/null || true
      # Reap it here, or the shell announces the kill on stderr ("Killed ...") long after
      # the message that explains why we are leaving.
      wait "$SESSION_PID" 2>/dev/null || true
    fi
  fi
  local l
  for l in ${OUR_LINKS+"${OUR_LINKS[@]}"}; do rm -f -- "$l"; done
  if ((KEEP_PROJECT == 0)) && test -n "$PROJECT_DIR" && test -d "$PROJECT_DIR"; then
    case "$PROJECT_DIR" in /tmp/marionnet-respin.*) rm -rf -- "$PROJECT_DIR" ;; esac
  fi
  test -z "$SOCKET" || rm -f -- "$SOCKET"
  exit "$rc"
}
trap cleanup EXIT

link_if_absent "$FROM/$IMAGE"      "$USER_FS"
link_if_absent "$FROM/$IMAGE.conf" "$USER_FS"
if test -n "$KERNEL"; then
  link_if_absent "$KERNEL" "$USER_KERNELS"
else
  # Every kernel of the release directory: which one this image supports is the model's
  # business (SUPPORTED_KERNELS of the .conf), not ours -- ours is only to make them visible.
  shopt -s nullglob
  for k in "$FROM"/linux-*; do
    case "$k" in *.config) continue ;; esac
    test -x "$k" && link_if_absent "$k" "$USER_KERNELS"
  done
  shopt -u nullglob
fi

# --- The session.
#
# sun_path holds 107 bytes: the socket cannot live under a long temporary path, and marionnet
# refuses to start rather than truncate (measured).
SOCKET=$(mktemp -u /tmp/mrn-respin-XXXXXX.sock)
PROJECT_DIR=$(mktemp -d /tmp/marionnet-respin.XXXXXX)

function ask {   # ask REQUEST -- one line in, one JSON object out
  echo "$1" | timeout 900 socat -t 870 -T 890 - "UNIX-CONNECT:$SOCKET" 2>/dev/null
}
function ask_ok {   # ask_ok REQUEST WHAT -- dies unless the answer says ok
  local answer; answer=$(ask "$1")
  test -n "$answer" || die "$2: the channel did not answer (is the session still alive?)"
  if test "$(jq -r '.ok' <<<"$answer")" != "true"; then
    die "$2: $(jq -r '.detail // .error // .' <<<"$answer")"
  fi
  echo "$answer"
}

info "image      : $FROM/$IMAGE"
info "variant    : $VARIANT"
info "memory     : ${MEMORY:-<default>} MiB"
info "guest      : ${#IN_GUEST[@]} command(s)${IN_GUEST_SCRIPT:+ + $IN_GUEST_SCRIPT}"
if ((ASSUME_YES == 0)); then
  read -r -p "Boot this image and change it? [y/N] " answer
  case "${answer:-}" in y|Y|yes) : ;; *) die "nothing done" ;; esac
fi

info "starting a driven session..."
"$BINARY" --debug --control-socket "$SOCKET" >"$PROJECT_DIR/marionnet.out" 2>"$PROJECT_DIR/marionnet.log" &
SESSION_PID=$!
for ((i = 0; i < 90; i++)); do test -S "$SOCKET" && break; sleep 1; done
test -S "$SOCKET" || die "no control socket after 90s (see $PROJECT_DIR/marionnet.log)"

ask_ok "new $PROJECT_DIR/respin.mar" "creating the project" >/dev/null
info "adding a machine on $EPITHET..."
ask_ok "add machine m1 --distrib=$EPITHET${MEMORY:+ --memory=$MEMORY}" "adding the machine" >/dev/null
info "booting..."
ask_ok "start m1" "starting the machine" >/dev/null
ask_ok "wait m1 --state=on" "waiting for the machine" >/dev/null

# --- The gesture, in the guest.
#
# Every command is reported with its status, and a failure stops everything BEFORE the export:
# an image changed by halves must not become a published artefact.
function run_in_guest {   # run_in_guest COMMAND
  local answer status output
  answer=$(ask "exec m1 $1")
  test -n "$answer" || die "in-guest \`$1': the channel did not answer"
  if test "$(jq -r '.ok' <<<"$answer")" != "true"; then
    die "in-guest \`$1': $(jq -r '.detail // .error' <<<"$answer")"
  fi
  status=$(jq -r '.status' <<<"$answer")
  output=$(jq -r '.output // ""' <<<"$answer")
  test -z "$output" || sed 's/^/    /' <<<"$output"
  test "$status" = "0" || die "in-guest \`$1' exited with status $status: nothing is exported"
  info "in-guest \`$1': ok"
}

for cmd in ${IN_GUEST+"${IN_GUEST[@]}"}; do run_in_guest "$cmd"; done
if test -n "$IN_GUEST_SCRIPT"; then
  # Through the hostfs the guest already mounts: `exec' takes a command line, not a file, and
  # copying the script into the project's hostfs is how Marionnet itself hands scripts over.
  GUEST_SCRIPT_DIR=$(find "$PROJECT_DIR" -type d -name m1 -path '*/hostfs/*' | head -n 1)
  test -n "$GUEST_SCRIPT_DIR" || die "--in-guest-script: no hostfs directory for m1 (is the guest really up?)"
  cp -- "$IN_GUEST_SCRIPT" "$GUEST_SCRIPT_DIR/respin-script.sh"
  chmod +x "$GUEST_SCRIPT_DIR/respin-script.sh"
  run_in_guest "bash /mnt/hostfs/respin-script.sh"
  rm -f -- "$GUEST_SCRIPT_DIR/respin-script.sh"
fi

# --- Clean shutdown (trap 6), then the export (episode 22).
info "shutting the machine down..."
ask_ok "stop m1" "stopping the machine" >/dev/null
ask_ok "wait m1 --state=off" "waiting for the shutdown" >/dev/null

# The state is NOT the root of the tree: the root carries the machine and a cow file which may
# not exist yet, the states are its children (the GUI says the same thing when it answers "you
# should expand the tree"). The most recent child by timestamp is the state we just ran.
HISTORY=$(ask_ok "history m1" "reading the states")
COW=$(jq -r '[.rows[0].children[]?.fields] | sort_by(.Timestamp) | last | .["File name"] // empty' <<<"$HISTORY")
test -n "$COW" || die "no state to export: the machine has only its initial row (was it really started?)"
info "exporting the state $COW as the variant $VARIANT..."
EXPORTED=$(ask_ok "history-export $COW $VARIANT" "exporting the variant")
VARIANT_PATH=$(jq -r '.path' <<<"$EXPORTED")
info "variant    : $VARIANT_PATH ($(du -h -- "$VARIANT_PATH" | cut -f1) on disk)"

info "closing the session..."
ask "quit" >/dev/null || true
for ((i = 0; i < 60; i++)); do kill -0 "$SESSION_PID" 2>/dev/null || break; sleep 1; done
SESSION_PID=""

# --- Publication (local: the release directory, not the server).
if ((PUBLISH == 0)); then
  info "--no-publish: the variant is there, nothing was published"
  info "to publish it later:  $PUBLISHER ${OUTPUT_DIR:+-o $OUTPUT_DIR }$VARIANT_PATH"
  exit 0
fi

info "handing the variant to $(basename -- "$PUBLISHER")..."
"$PUBLISHER" -y ${OUTPUT_DIR:+-o "$OUTPUT_DIR"} "$VARIANT_PATH"
