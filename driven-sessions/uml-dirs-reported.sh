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

# Bench: bin/scripts/marionnet-cleanup.sh knows about the per-guest directories the UML kernels
# leave in $UML_DIR (default ~/.uml/<umid>/) -- it REPORTS them, and removes them only when asked
# by --purge-uml-dirs. Episode 20 of marionnet-todo-transverse.
#
# What is really proved here is the way the tool tells a live directory from a dead one, which is
# where the whole safety of the option sits. A directory is LIVE when either half says so:
#
#   the bound socket   its `mconsole' socket still appears in /proc/net/unix. This is the half
#                      that covers a FROZEN kernel: it answers nothing, but it holds its socket.
#
#   the pid AND umid   the pid it holds is alive and that process's command line bears the same
#                      `umid='. The pid alone would not do: a recycled pid would make a dead
#                      directory immortal, which the `recycled' case below measures.
#
# Both halves are played for real, without any guest: a unix datagram socket really bound to
# <dir>/mconsole, and a process whose argv[0] really carries `umid=<name>'. The whole thing runs
# in a temporary $UML_DIR -- which is also the proof that the tool honours that variable instead
# of hard-wiring ~/.uml.
#
# No guest, no privilege, no display: this bench is versioned.
#
# Codes: 0 = PASS, 77 = SKIP (nothing significant could be played), anything else = FAIL.

set -u

HERE=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$HERE/bin/scripts/marionnet-cleanup.sh"

pass=0; fail=0; skipped=0
ok()   { echo "PASS: $*"; pass=$((pass+1)); }
ko()   { echo "FAIL: $*"; fail=$((fail+1)); }
skip() { echo "SKIP: $*"; skipped=$((skipped+1)); }

[ -x "$SCRIPT" ] || { echo "SKIP: $SCRIPT is not executable"; exit 77; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/marionnet-bench-umldirs.XXXXXX") || exit 1
UMLBASE="$WORK/uml"
declare -a HELPER_PIDS=()

# By EXACT pid, never by pattern: a `pkill -f' on anything as generic as `umid=' would match this
# very bench, and once destroyed a whole desktop session.
cleanup() {
  local p
  for p in "${HELPER_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    kill -TERM "$p" 2>/dev/null
  done
  for p in "${HELPER_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    kill -KILL "$p" 2>/dev/null
  done
  rm -rf -- "$WORK"
}
trap cleanup EXIT

# --- Building the cases ---------------------------------------------------------------------

# A pid that is certainly nobody's: a process of ours which has already been reaped.
dead_pid() {
  local p
  ( exec sleep 0 ) & p=$!
  wait "$p" 2>/dev/null
  echo "$p"
}

# The tool ignores anything younger than an hour (a guest may be starting right now), so every
# directory meant to be judged is pushed back in time -- AFTER everything inside it is in place,
# since writing in a directory refreshes its mtime.
age_it() { touch -d '3 hours ago' "$1"; }

mkdir -p "$UMLBASE" || exit 1

# (1) dead: the ordinary residue of a guest whose kernel is gone.
mkdir -p "$UMLBASE/dead"
: > "$UMLBASE/dead/mconsole"
dead_pid > "$UMLBASE/dead/pid"
age_it "$UMLBASE/dead"

# (2) recycled: the pid file names a LIVE process which is not the guest -- exactly what a pid
# reused by the system looks like. Dead, because nothing bears `umid=recycled'.
mkdir -p "$UMLBASE/recycled"
: > "$UMLBASE/recycled/mconsole"
sleep 600 & HELPER_PIDS+=("$!")
echo "$!" > "$UMLBASE/recycled/pid"
age_it "$UMLBASE/recycled"

# (3) live by the pid: a process whose command line really carries `umid=livepid'.
mkdir -p "$UMLBASE/livepid"
: > "$UMLBASE/livepid/mconsole"
bash -c 'exec -a "linux umid=livepid mem=48M" sleep 600' & HELPER_PIDS+=("$!")
echo "$!" > "$UMLBASE/livepid/pid"
age_it "$UMLBASE/livepid"

# (4) live by the socket: a unix datagram socket really bound to <dir>/mconsole, the state of a
# guest which is running -- or frozen. Its pid file names a dead pid on purpose: the socket alone
# must save it.
mkdir -p "$UMLBASE/livesock"
dead_pid > "$UMLBASE/livesock/pid"
socket_bound=0
binder=""
# The binder must OUTLIVE the measure, and it must not unlink the socket behind our back: a plain
# `socat UNIX-RECV:<path> /dev/null' binds, then reads EOF from /dev/null, exits, and removes the
# socket file it had just created -- measured here, and it left the directory looking untouchable
# rather than live. Hence python3 first (bind and sleep, nothing else) and `socat -u' -- one way,
# so nothing is read -- as the fallback.
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import socket,sys,time
s=socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM); s.bind(sys.argv[1]); time.sleep(600)' \
    "$UMLBASE/livesock/mconsole" & binder=$!; HELPER_PIDS+=("$binder")
elif command -v socat >/dev/null 2>&1; then
  socat -u UNIX-RECV:"$UMLBASE/livesock/mconsole" /dev/null & binder=$!; HELPER_PIDS+=("$binder")
fi
if [ -n "$binder" ]; then
  for _ in $(seq 1 50); do
    if grep -qxF "$UMLBASE/livesock/mconsole" < <(awk '{print $NF}' /proc/net/unix); then
      socket_bound=1; break
    fi
    sleep 0.1
  done
  # Bound once is not enough: what the tool will read is the state at the time of the report.
  kill -0 "$binder" 2>/dev/null || socket_bound=0
fi
age_it "$UMLBASE/livesock"

# (5) odd: a directory of $UML_DIR which is not one of ours (this directory is shared with any
# other UML use of the user). Neither live nor removable: none of our business.
mkdir -p "$UMLBASE/odd"
: > "$UMLBASE/odd/mconsole"
dead_pid > "$UMLBASE/odd/pid"
: > "$UMLBASE/odd/something-else"
age_it "$UMLBASE/odd"

# (6) young: dead in every respect, but too recent to be judged -- its mtime is left alone.
mkdir -p "$UMLBASE/young"
: > "$UMLBASE/young/mconsole"
dead_pid > "$UMLBASE/young/pid"

# --- Case A: the report tells them apart, and removes nothing -------------------------------

report=$(UML_DIR="$UMLBASE" "$SCRIPT" 2>&1)
rc=$?

if [ "$rc" -ne 0 ]; then
  ko "the report itself failed (rc=$rc)"
  echo "$report" | tail -5
else
  ok "the report runs (rc=0)"
fi

if grep -qF "UML mconsole directories in $UMLBASE" <<< "$report"
then ok "the report has a section for the directory named by UML_DIR, and honours the variable"
else ko "no section naming $UMLBASE (the tool ignores UML_DIR)"; echo "$report" | tail -12
fi

expected_dead=2   # dead, recycled
if grep -qE "removable: $expected_dead directory\(ies\)" <<< "$report"
then ok "exactly $expected_dead removable: the dead one, and the one whose pid was recycled"
else ko "wrong count of removable directories"; grep -A4 'UML mconsole' <<< "$report"
fi

if [ "$socket_bound" -eq 1 ]; then
  expected_live=2   # livepid, livesock
  if grep -qE "still holding a live UML \(spared\): $expected_live" <<< "$report"
  then ok "both halves of the live test hold: the umid of a live pid, and the bound socket"
  else ko "wrong count of live directories"; grep -A4 'UML mconsole' <<< "$report"
  fi
else
  skip "no socat and no python3: the bound-socket half could not be played"
  if grep -qE "still holding a live UML \(spared\): 1" <<< "$report"
  then ok "the umid of a live pid spares its directory"
  else ko "the live pid bearing umid=livepid did not spare its directory"
  fi
fi

if grep -qE "not of the expected shape, none of our business: 1" <<< "$report"
then ok "a directory of another shape is left out of both baskets"
else ko "the odd directory was not reported apart"; grep -A5 'UML mconsole' <<< "$report"
fi

still_there=1
for d in dead recycled livepid livesock odd young; do
  [ -d "$UMLBASE/$d" ] || { still_there=0; echo "  $d disappeared"; }
done
[ "$still_there" -eq 1 ] && ok "reporting removed nothing" || ko "the plain report removed something"

# --- Case B: --purge-uml-dirs removes the dead ones, and only those --------------------------

purge=$(UML_DIR="$UMLBASE" "$SCRIPT" --purge-uml-dirs 2>&1)
rc=$?
[ "$rc" -eq 0 ] || { ko "--purge-uml-dirs failed (rc=$rc)"; echo "$purge" | tail -5; }

gone=1
for d in dead recycled; do
  [ -d "$UMLBASE/$d" ] && { gone=0; echo "  $d survived"; }
done
[ "$gone" -eq 1 ] && ok "--purge-uml-dirs removed the two dead directories" \
                  || ko "--purge-uml-dirs left a dead directory behind"

kept=1
for d in livepid odd young; do
  [ -d "$UMLBASE/$d" ] || { kept=0; echo "  $d was removed"; }
done
if [ "$socket_bound" -eq 1 ] && [ ! -d "$UMLBASE/livesock" ]; then kept=0; echo "  livesock was removed"; fi
[ "$kept" -eq 1 ] && ok "--purge-uml-dirs spared the live ones, the odd one and the young one" \
                  || ko "--purge-uml-dirs removed something it should have spared"

# --- Case C: the option is named by the help, and nothing else implies it --------------------

if UML_DIR="$UMLBASE" "$SCRIPT" --help 2>&1 | grep -qF -- '--purge-uml-dirs'
then ok "--purge-uml-dirs is documented in the help"
else ko "--purge-uml-dirs is not in the help"
fi

echo
echo "=== $pass passed, $fail failed, $skipped skipped ==="
[ "$fail" -eq 0 ] || exit 1
[ "$pass" -eq 0 ] && exit 77
exit 0
