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
#
# Bench: a message window stays readable and closable, whatever the length of what it says.
# Work-stream marionnet-todo-transverse, episode 13.
#
# Before the fix, dialog_MESSAGE -- the shape of every Simple_dialogs.error / warning / info /
# help -- had no cap on the natural width of its body and no bound on its height, and
# simple_dialogs.ml turned it resizable. In Gtk+ 3 an already mapped RESIZABLE window is grown
# to its new MINIMUM size, and the minimum width of a wrapping label is the width of its longest
# word: hence a narrow column growing downwards without end (measured here: 398x2672 pixels,
# far taller than a 1366x768 screen, so the Close button was simply out of reach).
#
# What the bench measures is the REAL window of the REAL application, read from the X server --
# not a replica. The trigger needs no click: a run directory left behind by a past session makes
# Marionnet open a warning at startup (episode 6 of the same work-stream), and the temporary
# directory is NAMED in that warning, so the length of the message is chosen simply by choosing
# how deep that directory is. Two lengths are enough: one paragraph, and a body long enough to
# overflow any reasonable screen if nothing bounded it.
#
# No guest, no privilege: a plain GUI start. But it does need an X display and xdotool/xwininfo,
# which a headless machine has not -- those cases SKIP rather than pretend (episode 2).
#
# MARIONNET_PREFIX is not a convenience here: a binary taken from _build reads the glade and the
# images of the Marionnet INSTALLED on the machine, which may be years old (the same family as
# the i18n entry of docs/TODO.md). Without it the bench would measure another Marionnet.
#
# Deliberately no `set -e': the geometry is compared explicitly, case by case, and a missing
# window must be reported rather than abort the run. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

# The window titles of Simple_dialogs.warning, in the languages the catalogues may give it.
# The body is what this bench measures; the title only serves to find the window.
readonly WARNING_TITLES='Warning|Avertissement|Attention|Advertencia|Avviso|Aviso'

# How long the application is given to show its warning.
readonly WINDOW_TIMEOUT=40

# The window must be wide enough not to be a column, and small enough for a 1366x768 laptop
# (a classroom machine), decorations and panel included.
readonly MIN_WIDTH=600
readonly MAX_WIDTH=1000
readonly MAX_HEIGHT=700

declare -i passed=0 failed=0 skipped=0
declare tmpbase="" prefix=""

cleanup() {
  local d
  for d in "$tmpbase" "$prefix"; do
     # Guard: never let an empty or short variable turn this into a wide removal.
     if [[ -n "$d" && "$d" == /tmp/marionnet-geometry.* && -d "$d" ]]; then
        rm -rf -- "$d"
     fi
  done
}
trap cleanup EXIT

pass() { echo "PASS: $*"; passed+=1; }
fail() { echo "FAIL: $*"; failed+=1; }
skip() { echo "SKIP: $*"; skipped+=1; }

# A prefix built out of the sources, so that the bench measures THIS repository's glade and
# needs no `make install'. Only gui/ and images/ are read before the warning is shown; the two
# other directories exist merely because Path builds their names.
build_prefix() {
  prefix="$(mktemp -d /tmp/marionnet-geometry.XXXXXX)"
  mkdir -p "$prefix/filesystems" "$prefix/kernels"
  ln -s "$ROOT/bin/gui" "$prefix/gui"
  ln -s "$ROOT/bin/images" "$prefix/images"
}

# measure <depth> -> "<width> <height>" on stdout, empty if no window was seen.
#
# <depth> is the number of nested components given to the temporary directory: the warning
# names that directory, so the depth is the length of the message.
measure() {
  local -i depth="$1"
  local base deep pid="" id name geo="" i
  base="$(mktemp -d /tmp/marionnet-geometry.XXXXXX)"
  tmpbase="$base"
  deep="$base"
  for ((i = 1; i <= depth; i++)); do
     deep="$deep/repertoire-de-travail-numero-$i-au-nom-deliberement-long"
  done
  # The fake leftover: its name is the shape state.ml builds (prefix marionnet-, suffix .dir).
  mkdir -p "$deep/marionnet-424242.dir"
  TMPDIR="$deep" MARIONNET_PREFIX="$prefix" "$BIN" >"$base/out" 2>"$base/err" &
  pid=$!
  for ((i = 0; i < WINDOW_TIMEOUT; i++)); do
     sleep 1
     # --all: AND the criteria. The default is OR, which matches every window of the display.
     for id in $(xdotool search --all --pid "$pid" --name '.' 2>/dev/null); do
        name="$(xdotool getwindowname "$id" 2>/dev/null)"
        [[ "$name" =~ ^($WARNING_TITLES)$ ]] || continue
        geo="$(xwininfo -id "$id" | awk '/^  Width:|^  Height:/{printf "%s ", $2}')"
        break 2
     done
     kill -0 "$pid" 2>/dev/null || break
  done
  # By exact pid, never by pattern.
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
     kill -TERM "$pid" 2>/dev/null
     sleep 2
     kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
     wait "$pid" 2>/dev/null
  fi
  rm -rf -- "$base"
  tmpbase=""
  echo "$geo"
}

check_geometry() {
  local label="$1" depth="$2" geo w h
  geo="$(measure "$depth")"
  read -r w h <<< "$geo"
  if [[ -z "${w:-}" || -z "${h:-}" ]]; then
     fail "$label: no message window appeared within ${WINDOW_TIMEOUT}s"
     return
  fi
  if (( w >= MIN_WIDTH && w <= MAX_WIDTH )); then
     pass "$label: width ${w}px is between $MIN_WIDTH and $MAX_WIDTH"
  else
     fail "$label: width ${w}px is outside [$MIN_WIDTH, $MAX_WIDTH] (a column, or a banner)"
  fi
  if (( h <= MAX_HEIGHT )); then
     pass "$label: height ${h}px fits under $MAX_HEIGHT"
  else
     fail "$label: height ${h}px exceeds $MAX_HEIGHT (the Close button leaves the screen)"
  fi
}

# --- The bench itself

if [[ ! -x "$BIN" ]]; then
   echo "SKIP: no executable at $BIN (run dune build first)"
   exit 77
fi
if [[ -z "${DISPLAY:-}" ]]; then
   echo "SKIP: no DISPLAY: a window has no geometry without an X server"
   exit 77
fi
for tool in xdotool xwininfo; do
   if ! command -v "$tool" >/dev/null 2>&1; then
      echo "SKIP: $tool is not installed, the geometry cannot be read"
      exit 77
   fi
done

build_prefix

# One paragraph: the shape of an ordinary error or warning.
check_geometry "short message" 0
# A body long enough to overflow any screen if nothing bounded it (the path alone is over
# 2000 characters, which the warning quotes).
check_geometry "long message" 36

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
