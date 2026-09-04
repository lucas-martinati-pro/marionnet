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

# Probe every binary a published guest image announces, and write down what each one answers.
# Stage 1 of the work-stream `triage-binaires-image-invitee': this script OBSERVES, it decides
# nothing. The verdicts an agent later derives from this report are frozen in a versioned
# policy; this side must stay a measurement.
#
#   Makefile.d/filesystem.probe-image-binaries.sh --image machine-debian-trixie-16341
#
# --- IT PUBLISHES NOTHING, AND EXPORTS NOTHING ---
#
# It boots the image into a cow file of its own, reads, and throws the cow away. The name of an
# image IS its `sum' (episode 23 of `marionnet-kernel-rootfs'): probing must produce no image.
# Nothing is exported either -- there is no variant, no snapshot, no call to the publisher.
# That is also what makes the probe SAFE: a binary probed with --help which turns out to do its
# job instead (mkfs, dd, rm) writes into a cow nobody keeps.
#
# --- WHAT THE FIRST EPISODE MEASURED, AND WHICH THIS SCRIPT IS SHAPED BY ---
#
#   1. `exec' runs in a BARE environment: PATH, and not even HOME. No DISPLAY. But the relay
#      wrote `export DISPLAY=' and `export XAUTHORITY=' into /etc/profile (uml/guest/
#      marionnet-relay), so the guest side sources it -- measured: xdpyinfo then answers.
#   2. A round trip through the channel costs about a second. 2061 of them would be 35 minutes
#      of waiting for a loop the guest runs in a fraction of a second. Hence ONE script, run
#      inside, and a report the host watches growing in the shared hostfs directory.
#   3. `ldd' is both WRONG and TOO SLOW as a classifier. Wrong: /usr/bin/xlinks2 is a
#      `#!/bin/sh' wrapper doing `exec links2 -g "$@"', so ldd sees no libX11 -- and 417 of the
#      2057 candidates are not ELF at all. Too slow: it forks the dynamic loader per binary and
#      did not finish the catalogue in 300 s. We read the file itself (grep -a) and follow the
#      wrapper, which is a read, not an exec.
#   4. A binary can kill the guest it is probed in (reboot, halt, poweroff). The report is
#      therefore written LINE BY LINE into the hostfs: what died is NAMED by the last line
#      written, instead of being guessed after losing everything.
#
# --- THE REPORT IS A MEASUREMENT, AND SO ARE ITS CONDITIONS ---
#
# A verdict on an X application is not a property of the image alone: the same binary answers
# differently to a different X server. Episode 1 measured exactly that -- `xlinks2', the very
# binary this work-stream was opened for, raises BadMatch in a classroom and runs fine here.
# So the header of the report records the X server it was taken against (vendor, release,
# depths): a reader who compares two reports must be able to see that.
#
# --- NO BASHBRICKS HERE, ON PURPOSE ---
#
# Sixth of a family (the two *.prepare-to-publish.sh, release.sha256sums.sh, release.binary.sh,
# filesystem.update-published-image.sh), none of which sources anything: `socat' and `jq' are
# already runtime dependencies of Marionnet itself.

set -euo pipefail

function info { echo "==> $*"; }
function warn { echo "$0: warning: $*" >&2; }
function die  { echo "$0: $*" >&2; exit 2; }

function usage {
 cat 1>&2 <<EOF
Usage: $0 --image NAME [OPTIONS]

  --image NAME       the published image to probe, e.g. machine-debian-trixie-16341
  --from DIR         where that image and its .conf live
                     (default: website-repo/download/marionnet-install.sh/<series>)
  --kernel PATH      the UML kernel to make visible (default: every linux-* found in --from)
  --output FILE      where to write the report
                     (default: docs/probe-reports/<image>-<date>.tsv)
  --memory N         MiB given to the machine (default: MEMORY_SUGGESTED_SIZE of the .conf)
  --binary PATH      the marionnet to drive (default: _build/default/bin/marionnet.exe)
  --limit N          probe only the first N binaries (a short run, for the road)
  --x-only           probe only the binaries classified as X applications
  --help-timeout N   seconds given to a --help probe (default: 5)
  --x-timeout N      seconds an X application must survive to be called alive (default: 6)
  --keep-project     do not remove the temporary project directory (for a post-mortem)
  -y, --yes          do not ask before the long steps
  -h, --help         this help

Nothing is exported and nothing is published: the image is read, the cow is thrown away.
The exit status is 0 if the report was taken, 2 if it could not be.
EOF
}

# --- Options.
IMAGE=""; FROM=""; KERNEL=""; OUTPUT=""; MEMORY=""; BINARY=""; LIMIT=0; X_ONLY=0
HELP_TIMEOUT=5; X_TIMEOUT=6; ASSUME_YES=0; KEEP_PROJECT=0

while (($#)); do
  case "$1" in
    --image)         IMAGE=${2:-};        shift 2 ;;
    --from)          FROM=${2:-};         shift 2 ;;
    --kernel)        KERNEL=${2:-};       shift 2 ;;
    --output)        OUTPUT=${2:-};       shift 2 ;;
    --memory)        MEMORY=${2:-};       shift 2 ;;
    --binary)        BINARY=${2:-};       shift 2 ;;
    --limit)         LIMIT=${2:-0};       shift 2 ;;
    --x-only)        X_ONLY=1;            shift ;;
    --help-timeout)  HELP_TIMEOUT=${2:-5};shift 2 ;;
    --x-timeout)     X_TIMEOUT=${2:-6};   shift 2 ;;
    --keep-project)  KEEP_PROJECT=1;      shift ;;
    -y|--yes)        ASSUME_YES=1;        shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               usage; die "unexpected argument '$1'" ;;
  esac
done

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
PUBLISHER="$HERE/filesystem.prepare-snapshot-to-publish.sh"

for cmd in socat jq; do
  command -v "$cmd" >/dev/null || die "\`$cmd' not found (socat and jq are runtime dependencies of Marionnet)"
done
test -n "$IMAGE" || { usage; die "--image is required"; }

case "$IMAGE" in
  machine-*) : ;;
  router-*)  die "$IMAGE is a ROUTER image: on the published side it is a symbolic LINK to a
machine image, which carries the binaries. Probe the machine image it points to." ;;
  *)         die "$IMAGE is not an image name (it should begin with \`machine-')" ;;
esac
EPITHET=${IMAGE#machine-}

BINARY=${BINARY:-$ROOT/_build/default/bin/marionnet.exe}
test -x "$BINARY" || die "no executable at $BINARY (build it first: dune build)"

if test -z "$FROM"; then
  # Same derivation as its brothers: ask the publisher rather than spelling the path twice.
  SERIES=$("$PUBLISHER" --print-series) || die "cannot derive the publication series"
  FROM="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"
fi
FROM=$(cd -- "$FROM" && pwd) || die "--from: no such directory"
test -r "$FROM/$IMAGE"      || die "no image $FROM/$IMAGE"
test -r "$FROM/$IMAGE.conf" || die "no configuration $FROM/$IMAGE.conf (an image without its .conf cannot be started)"

# --- The candidates come from the .conf, not from a listing of our own.
#
# BINARY_LIST is what the publisher engraved by reading the image itself
# (filesystem.prepare-snapshot-to-publish.sh, `binary_list_of_image'): it is the list of what
# this image is SAID to contain, which is exactly what a triage has to answer for. Recomputing
# it here would be a second implementation of the same question -- and a report which does not
# answer for the published list would leave the difference unexplained.
CANDIDATES=$(sed -n "s/^BINARY_LIST='\(.*\)'.*/\1/p" "$FROM/$IMAGE.conf" | head -n 1 | tr ' ' '\n' | grep -v '^$' || true)
test -n "$CANDIDATES" || die "no BINARY_LIST in $IMAGE.conf: nothing to probe"
CANDIDATE_NO=$(wc -l <<<"$CANDIDATES")
if ((LIMIT > 0)); then
  CANDIDATES=$(head -n "$LIMIT" <<<"$CANDIDATES")
  CANDIDATE_NO=$(wc -l <<<"$CANDIDATES")
fi

if test -z "$MEMORY"; then
  # The channel's `add machine' reads MEMORY_SUGGESTED_SIZE since episode 24, but an older
  # binary does not, and a trixie given 48 MiB dies of OOM.
  MEMORY=$(sed -n 's/^MEMORY_SUGGESTED_SIZE=\([0-9][0-9]*\).*/\1/p' "$FROM/$IMAGE.conf" | head -n 1)
  test -n "$MEMORY" || warn "no MEMORY_SUGGESTED_SIZE in $IMAGE.conf: letting Marionnet choose"
fi

if test -z "$OUTPUT"; then
  mkdir -p -- "$ROOT/docs/probe-reports"
  OUTPUT="$ROOT/docs/probe-reports/$IMAGE-$(date +%Y-%m-%d).tsv"
fi
mkdir -p -- "$(dirname -- "$OUTPUT")"

# --- Visibility (the two traps of filesystem.update-published-image.sh: a binary built in
# _build reads the *testing* prefix, and Disk#filesystems drops a distribution whose kernel is
# not installed). Only what we created is undone on the way out.
USER_FS="$HOME/.marionnet/filesystems"
USER_KERNELS="$HOME/.marionnet/kernels"
declare -a OUR_LINKS=()
SESSION_PID=""; SOCKET=""; PROJECT_DIR=""

function link_if_absent {   # link_if_absent TARGET LINKDIR
  local target=$1 dir=$2 name
  name=$(basename -- "$target")
  mkdir -p -- "$dir"
  if test -e "$dir/$name" || test -L "$dir/$name"; then return 0; fi
  ln -sfn -- "$target" "$dir/$name"
  OUR_LINKS+=("$dir/$name")
}

function cleanup {
  local rc=$?
  if test -n "$SESSION_PID" && kill -0 "$SESSION_PID" 2>/dev/null; then
    if grep -qz -- "$SOCKET" "/proc/$SESSION_PID/cmdline" 2>/dev/null; then
      # SIGTERM is neutralised by marionnet (bin/marionnet.ml): `quit' is the polite way, and
      # this is the last resort when a step died before reaching it.
      kill -9 "$SESSION_PID" 2>/dev/null || true
      wait "$SESSION_PID" 2>/dev/null || true
    fi
  fi
  local l
  for l in ${OUR_LINKS+"${OUR_LINKS[@]}"}; do rm -f -- "$l"; done
  if ((KEEP_PROJECT == 0)) && test -n "$PROJECT_DIR" && test -d "$PROJECT_DIR"; then
    case "$PROJECT_DIR" in /tmp/marionnet-probe.*) rm -rf -- "$PROJECT_DIR" ;; esac
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
  shopt -s nullglob
  for k in "$FROM"/linux-*; do
    case "$k" in *.config) continue ;; esac
    test -x "$k" && link_if_absent "$k" "$USER_KERNELS"
  done
  shopt -u nullglob
fi

# sun_path holds 107 bytes: the socket cannot live under a long temporary path.
SOCKET=$(mktemp -u /tmp/mrn-probe-XXXXXX.sock)
PROJECT_DIR=$(mktemp -d /tmp/marionnet-probe.XXXXXX)

function ask {   # ask REQUEST -- one line in, one JSON object out
  echo "$1" | timeout 900 socat -t 870 -T 890 - "UNIX-CONNECT:$SOCKET" 2>/dev/null
}
function ask_ok {   # ask_ok REQUEST WHAT
  local answer; answer=$(ask "$1")
  test -n "$answer" || die "$2: the channel did not answer (is the session still alive?)"
  if test "$(jq -r '.ok' <<<"$answer")" != "true"; then
    die "$2: $(jq -r '.detail // .error // .' <<<"$answer")"
  fi
  echo "$answer"
}

info "image      : $FROM/$IMAGE"
info "candidates : $CANDIDATE_NO binaries from BINARY_LIST$( ((X_ONLY)) && echo " (X applications only)")"
info "report     : $OUTPUT"
if ((ASSUME_YES == 0)); then
  read -r -p "Boot this image and probe it? [y/N] " answer
  case "${answer:-}" in y|Y|yes) : ;; *) die "nothing done" ;; esac
fi

info "starting a driven session..."
"$BINARY" --debug --control-socket "$SOCKET" >"$PROJECT_DIR/marionnet.out" 2>"$PROJECT_DIR/marionnet.log" &
SESSION_PID=$!
for ((i = 0; i < 90; i++)); do test -S "$SOCKET" && break; sleep 1; done
test -S "$SOCKET" || die "no control socket after 90s (see $PROJECT_DIR/marionnet.log)"

ask_ok "new $PROJECT_DIR/probe.mar" "creating the project" >/dev/null
ask_ok "add machine m1 --distrib=$EPITHET${MEMORY:+ --memory=$MEMORY}" "adding the machine" >/dev/null
info "booting..."
ask_ok "start m1" "starting the machine" >/dev/null
ask_ok "wait m1 --state=on" "waiting for the machine" >/dev/null

# The hostfs directory is not derivable: it lives under MARIONNET_TMPDIR with a random part.
# The channel publishes it as the `hostfs' field of rc-get (bin/control_server.ml, Co_rc_read).
HOSTFS=$(jq -r '.hostfs // empty' <<<"$(ask_ok "rc-get m1" "asking for the hostfs directory")")
test -n "$HOSTFS" || die "the channel named no hostfs directory for m1"
test -d "$HOSTFS" || die "no such hostfs directory: $HOSTFS"

# ---------------------------------------------------------------------------
# The guest side. It writes the report itself, line by line, into the shared
# hostfs directory -- see trap 4 in the header: a binary which kills the guest
# must be NAMED by the report, not lost with it.
# ---------------------------------------------------------------------------
cat > "$HOSTFS/probe.sh" <<'GUEST'
#!/bin/bash
# Written by filesystem.probe-image-binaries.sh, runs inside the guest. Measures; decides
# nothing. Every line is flushed as it is produced.

# `exec' hands us a bare environment (PATH only). DISPLAY and XAUTHORITY are what the relay
# appended to /etc/profile; without sourcing it, every X probe would fail for the wrong reason.
. /etc/profile 2>/dev/null || true

DIR=/mnt/hostfs
REPORT="$DIR/probe-report.tsv"
LIST="$DIR/probe-candidates"
HELP_TIMEOUT=$(cat "$DIR/probe-help-timeout" 2>/dev/null || echo 5)
X_TIMEOUT=$(cat "$DIR/probe-x-timeout" 2>/dev/null || echo 6)
X_ONLY=$(cat "$DIR/probe-x-only" 2>/dev/null || echo 0)

out=/tmp/probe.out
err=/tmp/probe.err

# --- The X classifier.
#
# NOT `ldd': measured in episode 1, it is wrong (xlinks2 is a /bin/sh wrapper around links2, so
# ldd sees no libX11 -- and a fifth of the catalogue is not ELF) and far too slow (it forks the
# dynamic loader per binary). We read the file, and we follow the wrapper one hop: a script is
# an X application when what it runs is one. One hop is not a limitation we regret -- it is
# what the measured case needs, and a fixpoint over scripts would be a parser.
function is_x_application {   # is_x_application PATH
  local f=$1 w t
  grep -qa libX11 "$f" 2>/dev/null && return 0
  # Not ELF? then it is text: look at what it calls.
  head -c4 "$f" 2>/dev/null | grep -q ELF && return 1
  for w in $(grep -oE '[a-zA-Z0-9_.+-]+' "$f" 2>/dev/null | sort -u); do
    t=$(command -v "$w" 2>/dev/null) || continue
    test "$t" = "$f" && continue
    grep -qa libX11 "$t" 2>/dev/null && return 0
  done
  return 1
}

function emit {   # emit NAME VERDICT RC PROBE DETAIL
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$REPORT"
}

# A single line of stderr, TSV-safe: tabs and newlines would break the columns, and a stack of
# them would drown the report the human has to read.
function first_line {   # first_line FILE
  head -n 1 "$1" 2>/dev/null | tr '\t\r' '  ' | cut -c1-200
}

started=$SECONDS
seen=0
while read -r name; do
  test -n "$name" || continue
  # How far we got, said in candidates and not in lines written. MEASURED: with --x-only the
  # loop writes nothing at all for the two thousand candidates it skips, and a host watching
  # the report grow read that silence as a hang -- it stopped a probe which was working, after
  # six lines out of seventy-three. What the host must watch is progress, not output.
  seen=$((seen+1)); echo "$seen" > "$DIR/probe-progress"
  path=$(command -v "$name" 2>/dev/null) || { emit "$name" MISSING - none "not in PATH"; continue; }

  if is_x_application "$path"; then
    kind=x
  else
    kind=plain
    test "$X_ONLY" = 1 && continue
  fi

  if test "$kind" = x; then
    # An X application is asked to LIVE, not to answer: many have no --help worth the name, and
    # the failure this work-stream was opened for (BadMatch on X_CreateWindow) happens at the
    # first window, not at the parsing of the arguments.
    : >"$out"; : >"$err"
    timeout "$X_TIMEOUT" "$path" >"$out" 2>"$err" </dev/null
    rc=$?
    case "$rc" in
      # Still there when the clock ran out: it opened its window and waited, which is what an
      # application with a window does.
      124) emit "$name" X_ALIVE "$rc" x "$(first_line "$err")" ;;
      # Gone, but with a zero status. MEASURED on the first full report: twelve of the
      # thirty-three the probe had called X_DIED are xdpyinfo, xlsfonts, xauth, appres,
      # xvinfo, setxkbmap... -- command-line X tools which did their job and left. Leaving
      # with 0 is a success whatever the probe, and a verdict which calls it a death would
      # hand the agent of stage 2 twelve failures to judge that never happened.
      0)   emit "$name" X_OK    "$rc" x "$(first_line "$err")" ;;
      *)   emit "$name" X_DIED  "$rc" x "$(first_line "$err")" ;;
    esac
  else
    : >"$out"; : >"$err"
    timeout "$HELP_TIMEOUT" "$path" --help >"$out" 2>"$err" </dev/null
    rc=$?
    case "$rc" in
      # 0 and 1 are both ordinary answers to --help: plenty of tools print their usage and
      # leave with 1. What we are looking for is neither of those.
      0|1)   emit "$name" OK      "$rc" help "$(first_line "$err")" ;;
      124)   emit "$name" TIMEOUT "$rc" help "$(first_line "$err")" ;;
      *)
        # --version, the fallback of the scale, and it is not a refinement: measured on the
        # first forty candidates, six of the seven ERR were `a2enmod' and its family answering
        # `Unknown option: help' -- a binary which works, asked the wrong question. Without the
        # fallback the agent of stage 2 would be handed those as failures to judge, which is
        # exactly the noise the design keeps away from it.
        #
        # Two probes and no more: `-h' means `human readable' to a good number of tools, and
        # what it means to the rest has not been measured here.
        #
        # The stderr of --help is kept BEFORE trying --version: a report whose rc comes from
        # one probe and whose message comes from the other describes nothing that happened.
        err_help=$(first_line "$err")
        : >"$out"; : >"$err"
        timeout "$HELP_TIMEOUT" "$path" --version >"$out" 2>"$err" </dev/null
        rc2=$?
        case "$rc2" in
          0|1) emit "$name" OK  "$rc2" version "$(first_line "$err")" ;;
          *)   emit "$name" ERR "$rc"  help    "$err_help" ;;
        esac ;;
    esac
  fi
done < "$LIST"

emit "#END" "-" "-" "-" "elapsed=$((SECONDS-started))s"
GUEST

printf '%s\n' "$CANDIDATES" > "$HOSTFS/probe-candidates"
echo "$HELP_TIMEOUT" > "$HOSTFS/probe-help-timeout"
echo "$X_TIMEOUT"    > "$HOSTFS/probe-x-timeout"
echo "$X_ONLY"       > "$HOSTFS/probe-x-only"
: > "$HOSTFS/probe-report.tsv"
echo 0 > "$HOSTFS/probe-progress"
chmod +x "$HOSTFS/probe.sh"

# The conditions of the measurement, asked of the guest before the probes: they belong to the
# report (see the header -- an X verdict is not a property of the image alone).
X_HEADER=$(jq -r '.output // ""' <<<"$(ask "exec m1 --timeout=30 . /etc/profile 2>/dev/null; echo \"DISPLAY=\$DISPLAY\"; xdpyinfo 2>/dev/null | grep -E '^(vendor string|X.Org version)'")" \
           | tr '\t\n' '  ' | tr -s ' ')

# --- The probes.
#
# Started in the background and WATCHED, rather than run through a blocking `exec': the round
# trip has a timeout of its own (socat), a full catalogue takes far longer than that, and a
# report growing in the shared directory is readable while it grows -- including when the guest
# dies half way through, which is the whole reason it is written line by line.
info "probing $CANDIDATE_NO binaries inside the guest (this is the long step)..."
ask_ok "exec m1 --timeout=30 setsid bash /mnt/hostfs/probe.sh >/dev/null 2>&1 &" "starting the probe" >/dev/null

REPORT_TSV="$HOSTFS/probe-report.tsv"
PROGRESS="$HOSTFS/probe-progress"
last=0; still=0
while true; do
  sleep 5
  # The guest counts CANDIDATES, and so do we: with --x-only it writes no line for the ones it
  # skips, and counting lines made a working probe look hung (measured -- it was stopped after
  # six of seventy-three).
  done_no=$(cat "$PROGRESS" 2>/dev/null || echo 0)
  grep -q '^#END' "$REPORT_TSV" 2>/dev/null && break
  if ((done_no == last)); then
    still=$((still + 5))
    # Nothing new for five minutes: either the guest is gone, or one binary is holding the
    # loop. Either way the report names the last one reached -- that is what it is for.
    if ((still >= 300)); then
      warn "no progress for ${still}s after $done_no candidate(s): the last name in the report is where it stopped"
      break
    fi
  else
    still=0
    info "  $done_no/$CANDIDATE_NO"
  fi
  last=$done_no
  kill -0 "$SESSION_PID" 2>/dev/null || { warn "the session is gone"; break; }
done

# --- The report: its conditions, then the measurements.
{
  echo "# probe report -- $IMAGE"
  echo "# taken     : $(date -Is)"
  echo "# image     : $FROM/$IMAGE"
  echo "# sum       : $(sed -n "s/^SUM=\(.*\)/\1/p" "$FROM/$IMAGE.conf" | head -n 1)"
  echo "# candidates: $CANDIDATE_NO (BINARY_LIST of the .conf)"
  echo "# probes    : help-timeout=${HELP_TIMEOUT}s x-timeout=${X_TIMEOUT}s x-only=$X_ONLY"
  # An X verdict is a property of the pair (image, X server). Two reports which disagree are
  # not necessarily two images which disagree -- so the server is written down.
  echo "# X server  : ${X_HEADER:-<not measured>}"
  echo "#"
  echo "# name	verdict	rc	probe	first line of stderr"
  cat "$REPORT_TSV"
} > "$OUTPUT"

info "closing the session..."
ask "quit" >/dev/null || true
for ((i = 0; i < 60; i++)); do kill -0 "$SESSION_PID" 2>/dev/null || break; sleep 1; done
SESSION_PID=""

info "report     : $OUTPUT"
awk -F'\t' '!/^#/ && NF>1 {n[$2]++} END {for (v in n) printf "  %-10s %d\n", v, n[v]}' "$OUTPUT" | sort -k2 -rn
info "nothing was exported, nothing was published"
