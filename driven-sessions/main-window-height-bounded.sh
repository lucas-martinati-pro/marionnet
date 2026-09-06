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

# Bench: visiting a treeview tab does not make the main window taller than the screen.
# Work-stream modernisation-installation-marionnet, episode 47.
#
# Reported twice from a classroom (2026-09-04 and 2026-09-06, ubuntu:24.04 in Docker): the main
# window suddenly grew past the bottom edge of the screen AND refused to be resized, putting the
# collective action buttons ("Start all", "Suspend", "Shutdown all", "Power-off all") out of
# reach for good. The log of the second report:
#
#   Main window: height 781 -> 929 px  ... at t+278.7 s ... [size-allocate]
#   Main window: height 929 -> 1804 px ... at t+326.2 s ... [size-allocate]   (screen 1050)
#
# -- two jumps with no `growing from' line between them, so NOT the start-up adjustment of
# episode 43, which had stopped 320 seconds earlier and caps itself at the screen anyway.
#
# The cause is a widget contract. `gtk_tree_view_get_preferred_height' answers
# `minimum = natural = the height of every row', so a GtkTreeView outside a GtkScrolledWindow
# DEMANDS room for all its content -- and it starts demanding it only when its page is first
# SHOWN (before that the rows are not validated and it asks for nothing, which is what makes the
# defect look sudden). The demand then climbs the plain GtkHBox pages of gui_glade3.xml up to the
# GtkNotebook, which requests the maximum over ALL its pages, and becomes the MINIMUM size of the
# toplevel. An already mapped window is grown to its new minimum and can never be shrunk back
# below it: one visit to `Interfaces' is enough, and it is irreversible.
#
# What the bench measures is the REAL main window of the REAL application, read from the X
# server, and it measures two different things:
#   1. the window stays within the screen -- the catastrophe the classroom saw;
#   2. the MINIMUM the window announces in WM_NORMAL_HINTS does not grow -- the mechanism itself,
#      which a big enough screen would otherwise hide. That minimum is the only quantity that
#      can move an already mapped window, and xprop reads it without a window manager.
# On the code of episode 46 both fail: measured here, 40 machines and one visit to `Interfaces'
# take the minimum height from 364 to 1804 px and the window from 845 to 1804 px on a 1050 px
# screen -- the very number the classroom reported.
#
# Unlike its neighbours this bench does NOT use the ambient DISPLAY: the size of the screen is
# part of the measurement (that is what "taller than the screen" means), so it runs its own Xvfb
# at a size it chooses -- and it clicks in it, which is not something to do on the user's desktop.
# No guest, no privilege, no window manager.
#
# MARIONNET_PREFIX is deliberately NOT set: a binary taken from _build already reads the glade and
# the images of THIS repository while it takes filesystems and kernels from the installation
# (episode 22 of marionnet-todo-transverse) -- and `add machine' needs a real filesystem.
#
# Deliberately no `set -e': the geometry is compared explicitly, case by case, and a missing
# window must be reported rather than abort the run. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

# The screen the bench gives itself: the one the classroom reported.
readonly SCREEN_WIDTH=1680
readonly SCREEN_HEIGHT=1050

# How many machines. Rows are born collapsed, so this is the number of top-level rows each
# treeview of the notebook ends up with; at ~36 px a row it is far more than the screen holds.
readonly MACHINES=40

# What the announced minimum height is allowed to move. Not zero: a horizontal scrollbar may
# appear under a treeview, and the notebook tab labels are laid out once.
readonly MAX_GROWTH=40

# Time given to the application before the first measurement: the adjustment of episode 43 runs
# for six seconds after the start-up, and only a height read after it has finished means anything.
readonly SETTLE=10

# Where the four tabs of notebook_INTERNAL are, measured on the window itself: they sit at the
# bottom of the central area, above the collective action buttons. The x are the centres of
# `Image', `Interfaces', `Defects' and `Disks'; the y is counted from the bottom edge. Both are
# theme-dependent, which is why every click is WITNESSED (see click_tabs) instead of trusted.
readonly TAB_XS=(160 264 369 473)
readonly TAB_FROM_BOTTOM=173

declare -i passed=0 failed=0 skipped=0
declare tmpdir="" sock="" pid="" mrn_pid="" xvfb_pid="" display=""

# The `quit' of the channel does not close the project, so a session which opened one leaves its
# /tmp/marionnet-<n>.dir/ behind. Remove the ones THIS run created -- never a whole glob.
remove_our_run_directories() {
  local before="$tmpdir/rundirs-before" d
  [[ -r "$before" ]] || return 0
  while read -r d; do
     [[ "$d" =~ ^/tmp/marionnet-[0-9]+\.dir$ ]] || continue
     [[ -d "$d" ]] && rm -rf -- "$d"
  done < <(comm -13 "$before" <(ls -d /tmp/marionnet-*.dir 2>/dev/null | sort))
}

# One request, one line of JSON back.
ask() { echo "$1" | timeout 30 socat - "UNIX-CONNECT:$sock" 2>/dev/null; }

# The pid captured by `pid=$!' is the pid of `timeout', not the one of the session: timeout relays
# the signals it can catch, and SIGKILL is not one of them (episode 27). Two sources give the real
# one: the channel publishes it in `status', and until it answers, the single child of `timeout'
# IS the session.
session_pid_from_channel() {
  local answer
  answer=$(ask status)
  [[ "$answer" =~ \"pid\"[[:space:]]*:[[:space:]]*([0-9]+) ]] && echo "${BASH_REMATCH[1]}"
}

session_pid() {
  local candidate="${mrn_pid:-}"
  [[ -n "$candidate" ]] || candidate=$(cat "/proc/${pid:-0}/task/${pid:-0}/children" 2>/dev/null)
  echo "${candidate%% *}"
}

# Kill the session itself, by exact pid, and only once /proc has confirmed it still is ours: a pid
# gets recycled (episode 20), and the socket path -- unique to this run -- tells our session from
# anything else. SIGKILL because marionnet neutralises SIGTERM (episode 18).
kill_the_session() {
  local -i target="${1:-0}" i
  (( target > 1 )) || return 0
  kill -0 "$target" 2>/dev/null || return 0
  grep -qz -- "$sock" "/proc/$target/cmdline" 2>/dev/null || return 0
  kill -9 "$target" 2>/dev/null
  for ((i = 0; i < 100; i++)); do kill -0 "$target" 2>/dev/null || return 0; sleep 0.1; done
}

cleanup() {
  kill_the_session "$(session_pid)"
  # Then its proxy -- SIGTERM, never SIGKILL: timeout still relays what it can catch to a session
  # we failed to identify, and its --kill-after finishes the job.
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
     kill "$pid" 2>/dev/null
     wait "$pid" 2>/dev/null
  fi
  # The display last: killing it first would leave the application without a server.
  if [[ -n "$xvfb_pid" ]] && kill -0 "$xvfb_pid" 2>/dev/null; then
     kill "$xvfb_pid" 2>/dev/null
     wait "$xvfb_pid" 2>/dev/null
  fi
  remove_our_run_directories
  local d="$tmpdir"
  # Guard: never let an empty or short variable turn this into a wide removal.
  if [[ -n "$d" && "$d" == /tmp/marionnet-height.* && -d "$d" ]]; then
     rm -rf -- "$d"
  fi
}
trap cleanup EXIT

pass() { echo "PASS: $*"; passed+=1; }
fail() { echo "FAIL: $*"; failed+=1; }
skip() { echo "SKIP: $*"; skipped+=1; }

# start_display -> sets `display' and `xvfb_pid', or returns 1.
# A free display number is looked for rather than assumed: another Xvfb (or another bench) may
# already own the first one tried.
start_display() {
  local -i n i
  for ((n = 90; n < 120; n++)); do
     [[ -e "/tmp/.X11-unix/X$n" ]] && continue
     Xvfb ":$n" -screen 0 "${SCREEN_WIDTH}x${SCREEN_HEIGHT}x24" -nolisten tcp \
        >"$tmpdir/xvfb.log" 2>&1 &
     xvfb_pid=$!
     for ((i = 0; i < 50; i++)); do
        sleep 0.2
        kill -0 "$xvfb_pid" 2>/dev/null || break
        if [[ -e "/tmp/.X11-unix/X$n" ]]; then display=":$n"; return 0; fi
     done
     kill "$xvfb_pid" 2>/dev/null; wait "$xvfb_pid" 2>/dev/null; xvfb_pid=""
  done
  return 1
}

# The main window is the one titled "Marionnet" or "Marionnet - <project>"; the display belongs
# to this run alone, so nothing else can answer to that name.
main_window_id() {
  local id name
  for id in $(DISPLAY="$display" xdotool search --name '^Marionnet' 2>/dev/null); do
     name="$(DISPLAY="$display" xdotool getwindowname "$id" 2>/dev/null)"
     [[ "$name" =~ ^Marionnet( - .*)?$ ]] || continue
     echo "$id"; return 0
  done
  return 0
}

# geometry <id> -> "<x> <y> <width> <height>"
geometry() {
  DISPLAY="$display" xwininfo -id "$1" 2>/dev/null | awk '
     /Absolute upper-left X:/{x=$4} /Absolute upper-left Y:/{y=$4}
     /^  Width:/{w=$2} /^  Height:/{h=$2}
     END{if (h) print x, y, w, h}'
}

# minimum_height <id> -> the minimum height the toplevel announces, empty if it announces none.
# This, and not the current height, is what an already mapped window is grown to and cannot be
# shrunk below.
minimum_height() {
  DISPLAY="$display" xprop -id "$1" WM_NORMAL_HINTS 2>/dev/null | tr '\n' ' ' \
    | sed -nE 's/.*minimum size: [0-9]+ by ([0-9]+).*/\1/p'
}

# A signature of what the window shows, used to witness that a click actually did something.
picture_of() {
  DISPLAY="$display" import -window "$1" "$tmpdir/shot.png" 2>/dev/null || return 1
  identify -format '%#' "$tmpdir/shot.png" 2>/dev/null
}

# click_tabs <id> -> 0 if at least one click changed what the window shows.
# A click that reached nothing (a theme placing the tabs elsewhere) must not be mistaken for an
# application which behaved: it makes the bench SKIP, never pass.
click_tabs() {
  local id="$1" before after x; local -i moved=0 wx wy ww wh
  for x in "${TAB_XS[@]}"; do
     read -r wx wy ww wh <<< "$(geometry "$id")"
     [[ -n "${wh:-}" ]] || return 1
     before="$(picture_of "$id")" || return 1
     DISPLAY="$display" xdotool mousemove --sync \
        $((wx + x)) $((wy + wh - TAB_FROM_BOTTOM)) click 1 2>/dev/null
     sleep 3
     after="$(picture_of "$id")" || return 1
     [[ "$before" != "$after" ]] && moved=1
  done
  (( moved == 1 ))
}

# --- main -----------------------------------------------------------------------------------

if [[ ! -x "$BIN" ]]; then
   echo "SKIP: no executable at $BIN (build it first: dune build)"
   exit 77
fi
for tool in Xvfb xdotool xwininfo xprop import identify socat; do
   if ! command -v "$tool" >/dev/null 2>&1; then
      echo "SKIP: $tool is not installed; this bench needs a screen of a chosen size, its geometry and its picture"
      exit 77
   fi
done

tmpdir=$(mktemp -d /tmp/marionnet-height.XXXXXX) || exit 1
sock="$tmpdir/control.sock"
ls -d /tmp/marionnet-*.dir 2>/dev/null | sort > "$tmpdir/rundirs-before"
echo "Bench: a treeview does not push the main window off the screen — $BIN"

if ! start_display; then
   echo "SKIP: no Xvfb display could be started (see $tmpdir/xvfb.log)"
   exit 77
fi
echo "Screen: ${SCREEN_WIDTH}x${SCREEN_HEIGHT} on $display"

DISPLAY="$display" LANGUAGE=C LC_ALL=C \
  timeout -k 5 400 "$BIN" --control-socket "$sock" >"$tmpdir/stdout" 2>"$tmpdir/stderr" &
pid=$!
for ((i = 0; i < 90; i++)); do [[ -S "$sock" ]] && break; sleep 1; done
if [[ ! -S "$sock" ]]; then
   echo "FAIL: no socket at $sock after 90s (stderr: $(tail -3 "$tmpdir/stderr" | tr '\n' ' '))"
   exit 1
fi
mrn_pid=$(session_pid_from_channel)

if [[ "$(ask "new $tmpdir/bench.mar")" != *'"ok":true'* ]]; then
   echo "FAIL: could not create a project"
   exit 1
fi

# Fill the treeviews. A machine that cannot be built (no filesystem installed on this host) is
# not a failure of this bench: there is simply nothing to measure.
first="$(ask "add machine m1")"
if [[ "$first" != *'"ok":true'* ]]; then
   echo "SKIP: this host cannot build a machine, so the treeviews stay empty: $first"
   exit 77
fi
for ((i = 2; i <= MACHINES; i++)); do ask "add machine m$i" >/dev/null; done

# Anti-false-positive: a bench whose components were refused would visit empty treeviews and pass
# while proving nothing. `ifconfig' answers with one root row per node.
rows="$(ask ifconfig)"
if [[ ! "$rows" =~ \"count\"[[:space:]]*:[[:space:]]*$MACHINES ]]; then
   echo "FAIL: the ifconfig treeview does not hold $MACHINES rows, nothing was measured: ${rows:0:200}"
   exit 1
fi

sleep "$SETTLE"
id="$(main_window_id)"
if [[ -z "${id:-}" ]]; then
   echo "FAIL: the main window was not found on $display"
   exit 1
fi
read -r _ _ _ height_before <<< "$(geometry "$id")"
minimum_before="$(minimum_height "$id")"
if [[ -z "${minimum_before:-}" ]]; then
   echo "SKIP: this window announces no minimum size, so there is nothing to compare"
   exit 77
fi
echo "Before visiting any treeview: height ${height_before}px, announced minimum ${minimum_before}px"

if ! click_tabs "$id"; then
   echo "SKIP: no click reached a tab of the internal notebook (theme?), the treeviews were never shown"
   exit 77
fi

id="$(main_window_id)"
read -r _ _ _ height_after <<< "$(geometry "$id")"
minimum_after="$(minimum_height "$id")"
echo "After visiting the treeview tabs: height ${height_after}px, announced minimum ${minimum_after}px"

if (( height_after <= SCREEN_HEIGHT )); then
   pass "the window is ${height_after}px high, within the ${SCREEN_HEIGHT}px screen"
else
   fail "the window is ${height_after}px high on a ${SCREEN_HEIGHT}px screen: its bottom, hence the collective action buttons, is out of reach"
fi

growth=$(( minimum_after - minimum_before ))
if (( growth <= MAX_GROWTH )); then
   pass "visiting the treeviews moved the announced minimum by ${growth}px (at most $MAX_GROWTH allowed)"
else
   fail "visiting the treeviews moved the announced minimum by ${growth}px (${minimum_before} -> ${minimum_after}): the window can never be shrunk back"
fi

ask quit >/dev/null
wait "$pid"; pid=""; mrn_pid=""

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
