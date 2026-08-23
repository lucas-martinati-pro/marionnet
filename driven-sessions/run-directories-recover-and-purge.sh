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

# Bench: the abandoned run directories can be RECOVERED before being removed, and the removal can
# be asked for by the running Marionnet itself. This is what the two buttons of the startup
# warning need from bin/scripts/marionnet-cleanup.sh (episode 6 of marionnet-todo-transverse gave
# that warning its text; the buttons came later).
#
# Two things are proved here, and neither existed before:
#
#   --archive-dirs DEST   writes each removable run directory as a .mar project file, built the
#                         way state#private_save_project builds one (tar -cSzf -C <rundir>
#                         --exclude tmp <project>), and removes NOTHING. A run directory of an
#                         unexpected shape is skipped rather than archived into nonsense.
#
#   --caller-marionnet PID
#                         lifts, for that pid alone, the refusal to purge while a Marionnet is
#                         running. This is the hard point: the refusal is right (a live session's
#                         working copy is in one of these directories and nothing else on the host
#                         names it), so it is not removed but NARROWED -- any other live Marionnet
#                         still forbids the purge, and the caller names the directory to spare.
#
# No guest, no privilege: everything below is directories and one process. The two cases that need
# a live Marionnet need a display (the GUI is the only way to have one), and are SKIPped without.
#
# Codes: 0 = PASS, 77 = SKIP (nothing significant could be played), anything else = FAIL.

set -u

BINARY="${1:-_build/default/bin/marionnet.exe}"
HERE=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$HERE/bin/scripts/marionnet-cleanup.sh"

pass=0; fail=0; skipped=0
ok()   { echo "PASS: $*"; pass=$((pass+1)); }
ko()   { echo "FAIL: $*"; fail=$((fail+1)); }
skip() { echo "SKIP: $*"; skipped=$((skipped+1)); }

[ -x "$SCRIPT" ] || { echo "SKIP: $SCRIPT is not executable"; exit 77; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/marionnet-bench-cleanup.XXXXXX") || exit 1
MARIONNET_PID=""
cleanup() {
  # A session started by a bench is ended by the channel or by SIGKILL: Marionnet neutralises
  # SIGTERM on purpose, so `kill' + `wait' would never return (README of this directory).
  if [ -n "$MARIONNET_PID" ] && kill -0 "$MARIONNET_PID" 2>/dev/null; then
    kill -KILL "$MARIONNET_PID" 2>/dev/null
    while kill -0 "$MARIONNET_PID" 2>/dev/null; do sleep 0.2; done
  fi
  rm -rf -- "$WORK"
}
trap cleanup EXIT

# A run directory as state.ml builds one: <tmp>/marionnet-<n>.dir/<project>/... The tool ignores
# anything younger than an hour, so the mtime is pushed back.
make_rundir() {  # make_rundir <tmp> <n> <project>
  local d="$1/marionnet-$2.dir"
  mkdir -p "$d/$3/states" "$d/$3/netmodel" "$d/$3/tmp"
  echo '{"nodes":[]}' > "$d/$3/netmodel/network.json"
  echo 'scratch'      > "$d/$3/tmp/sketch.png"
  touch -d "5 hours ago" "$d"
  echo "$d"
}

# --- 1. Recovering: one .mar per removable run directory, and nothing removed -----------------
T1="$WORK/t1"; D1="$WORK/dest1"; mkdir -p "$T1" "$D1"
make_rundir "$T1" 101 alpha >/dev/null
make_rundir "$T1" 102 beta  >/dev/null
mkdir -p "$T1/marionnet-103.dir"; touch -d "5 hours ago" "$T1/marionnet-103.dir"   # no project inside
out1=$(TMPDIR="$T1" "$SCRIPT" --archive-dirs "$D1" 2>&1); rc1=$?

if [ "$rc1" -ne 0 ]; then
  ko "--archive-dirs returned $rc1"
else
  mars=$(ls "$D1"/*.mar 2>/dev/null | wc -l)
  if [ "$mars" -eq 2 ]; then ok "--archive-dirs wrote one .mar per removable run directory (2)"
  else ko "--archive-dirs wrote $mars .mar file(s), expected 2"; fi

  # Nothing was removed: recovering is not cleaning.
  left=$(ls -d "$T1"/marionnet-*.dir 2>/dev/null | wc -l)
  if [ "$left" -eq 3 ]; then ok "--archive-dirs alone removed nothing (3 run directories still there)"
  else ko "--archive-dirs left $left run directories, expected 3"; fi

  # The shape of a .mar: its root is the PROJECT directory (Marionnet takes the tarball root for
  # the project root), and the volatile tmp/ is excluded, exactly as save_project does.
  alpha=$(ls "$D1"/recovered-alpha.*.mar 2>/dev/null | head -1)
  if [ -z "$alpha" ]; then
    ko "no archive named after the project (recovered-alpha.<date>.mar)"
  else
    listing=$(tar -tzf "$alpha" 2>/dev/null)
    if grep -q '^alpha/' <<< "$listing"; then ok "the archive's root is the project directory"
    else ko "the archive's root is not alpha/: $(head -1 <<< "$listing")"; fi
    if grep -q '^alpha/tmp/' <<< "$listing"; then ko "the archive keeps tmp/, which save_project excludes"
    else ok "the archive excludes tmp/, like save_project"; fi
    if grep -q 'netmodel/network.json' <<< "$listing"; then ok "the archive holds the unsaved work (netmodel/)"
    else ko "the archive does not hold netmodel/network.json"; fi
  fi

  if grep -q "skipping .*marionnet-103.dir" <<< "$out1"; then
    ok "a run directory of an unexpected shape is skipped, not archived whole"
  else
    ko "the shapeless run directory was not reported as skipped"
  fi
fi

# --- 1 bis. Recovering AND cleaning: only what was really archived goes ------------------------
#
# This is what the "Recover the projects and clean up" button asks for. The two options together
# must not degenerate into a plain purge: a run directory the archiving had to skip still holds
# work nobody has a copy of, and losing it is exactly what the archiving exists to prevent.
T1B="$WORK/t1b"; D1B="$WORK/dest1b"; mkdir -p "$T1B" "$D1B"
make_rundir "$T1B" 111 delta >/dev/null
make_rundir "$T1B" 112 epsilon >/dev/null
mkdir -p "$T1B/marionnet-113.dir"; touch -d "5 hours ago" "$T1B/marionnet-113.dir"   # unarchivable
TMPDIR="$T1B" "$SCRIPT" --archive-dirs "$D1B" --purge-dirs >/dev/null 2>&1
rc1b=$?
if [ "$rc1b" -ne 0 ]; then
  ko "--archive-dirs --purge-dirs returned $rc1b"
else
  if [ -d "$T1B/marionnet-111.dir" ] || [ -d "$T1B/marionnet-112.dir" ]; then
    ko "--archive-dirs --purge-dirs left a run directory it had archived"
  else
    ok "--archive-dirs --purge-dirs removes the run directories it has archived"
  fi
  if [ -d "$T1B/marionnet-113.dir" ]; then
    ok "--archive-dirs --purge-dirs keeps the run directory it could NOT archive"
  else
    ko "--archive-dirs --purge-dirs removed a run directory that was never archived"
  fi
  mars=$(ls "$D1B"/*.mar 2>/dev/null | wc -l)
  if [ "$mars" -eq 2 ]; then ok "--archive-dirs --purge-dirs wrote the 2 archives before removing"
  else ko "--archive-dirs --purge-dirs wrote $mars archive(s), expected 2"; fi
fi

# --- 2. --spare-dir: named, hence untouchable ---------------------------------------------------
T2="$WORK/t2"; D2="$WORK/dest2"; mkdir -p "$T2" "$D2"
spared=$(make_rundir "$T2" 201 kept)
make_rundir "$T2" 202 gone >/dev/null
TMPDIR="$T2" "$SCRIPT" --spare-dir "$spared" --archive-dirs "$D2" --purge-dirs >/dev/null 2>&1
if [ -d "$spared" ]; then ok "--spare-dir: the named run directory survives the purge"
else ko "--spare-dir: the named run directory was removed"; fi
if [ -d "$T2/marionnet-202.dir" ]; then ko "--purge-dirs did not remove the other run directory"
else ok "--purge-dirs removed the run directory that was not spared"; fi
if ls "$D2"/recovered-kept.*.mar >/dev/null 2>&1; then ko "--spare-dir: the spared directory was archived"
else ok "--spare-dir: the spared directory was not archived either"; fi

# --- 3. --caller-marionnet only accepts a live Marionnet ---------------------------------------
TMPDIR="$WORK" "$SCRIPT" --caller-marionnet $$ >/dev/null 2>&1
if [ $? -eq 2 ]; then ok "--caller-marionnet refuses a pid that is not a Marionnet (usage error)"
else ko "--caller-marionnet accepted a pid that is not a Marionnet"; fi

# --- 4. The purge is still refused while a Marionnet is running, and granted to the caller ------
T4="$WORK/t4"; mkdir -p "$T4"
make_rundir "$T4" 401 gamma >/dev/null

if [ -z "${DISPLAY:-}" ]; then
  skip "no DISPLAY: the two cases needing a live Marionnet cannot be played"
  skip "(--purge-dirs refused while a Marionnet runs, and granted to --caller-marionnet)"
elif [ ! -x "$BINARY" ]; then
  skip "no binary at $BINARY: the two cases needing a live Marionnet cannot be played"
  skip "(--purge-dirs refused while a Marionnet runs, and granted to --caller-marionnet)"
else
  # LANGUAGE=C: a binary from _build reads the catalogues of the repository (episode 15), and
  # nothing below should depend on the language anyway.
  TMPDIR="$T4" LANGUAGE=C LC_ALL=C "$BINARY" >"$WORK/marionnet.log" 2>&1 &
  MARIONNET_PID=$!
  # Without this, the SIGKILL of the trap makes bash report the job on stderr ("Killed"), which
  # a bench has no business printing.
  disown "$MARIONNET_PID" 2>/dev/null || true
  # It is alive enough as soon as /proc/<pid>/exe names it: that is all the tool looks at.
  for _ in $(seq 1 100); do
    kill -0 "$MARIONNET_PID" 2>/dev/null || break
    case "$(readlink "/proc/$MARIONNET_PID/exe" 2>/dev/null)" in *marionnet*) break ;; esac
    sleep 0.2
  done
  if ! kill -0 "$MARIONNET_PID" 2>/dev/null; then
    skip "Marionnet did not stay up (see $WORK/marionnet.log): live-session cases not played"
    skip "(--purge-dirs refused while a Marionnet runs, and granted to --caller-marionnet)"
    MARIONNET_PID=""
  else
    sleep 2
    out4=$(TMPDIR="$T4" "$SCRIPT" --purge-dirs 2>&1); rc4=$?
    if [ "$rc4" -ne 0 ] && [ -d "$T4/marionnet-401.dir" ]; then
      ok "--purge-dirs is still refused while a Marionnet is running"
    else
      ko "--purge-dirs acted (rc=$rc4) although a Marionnet was running"
    fi
    out5=$(TMPDIR="$T4" "$SCRIPT" --purge-dirs --caller-marionnet "$MARIONNET_PID" 2>&1); rc5=$?
    if [ "$rc5" -eq 0 ] && [ ! -d "$T4/marionnet-401.dir" ]; then
      ok "--caller-marionnet: the running Marionnet may purge (which is what its button does)"
    else
      ko "--caller-marionnet: the purge did not happen (rc=$rc5): $(tail -2 <<< "$out5")"
    fi
  fi
fi

echo "---"
echo "$pass PASS, $fail FAIL, $skipped SKIP"
if [ "$fail" -gt 0 ]; then exit 1; fi
if [ "$pass" -eq 0 ]; then exit 77; fi
exit 0
