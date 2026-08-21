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

# Bench: the three menu entries which write the project ("Save", "Save as", "Copy to") are
# insensitive exactly while something is on or sleeping. Work-stream marionnet-todo-transverse,
# episode 14.
#
# Before the fix they sat in the `sensitive_when_Active' stack, i.e. they were sensitive as soon
# as a project was open; their callbacks then refused the action (Msg.error_saving_while_something_up)
# -- "Save as" and "Copy to" going as far as asking for a filename BEFORE refusing. They now sit
# in a fourth stack, `sensitive_when_Saveable', whose condition is recomputed at every state
# transition (the reaction subscribed to refresh_sketch_counter, motherboard_builder.ml).
#
# What the bench reads is the reaction itself, in the journal of the running application
# (--debug): the condition it computed and the number of widgets it applied it to. That number
# is part of the proof -- it says the three entries are in the stack and no other. What the
# bench does NOT read is the pixel: whether the entry LOOKS greyed is a matter for the eye, and
# the accessibility tree is not an option here (measured 2026-08-21: a lablgtk3 application
# driven by GtkThread.main never registers on the AT-SPI bus, where a plain GTK3 program does,
# so a widget-level probe would skip on every machine).
#
# A switch needs no guest and no privilege -- vde_switch is enough -- hence a versioned bench
# (docs/todo-transverse.md, section 3.6, criterion refined at episode 11).
#
# Deliberately no `set -e': one command here EXPECTS a non-zero answer, and every status that
# matters is tested explicitly. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

# The three entries pushed in the stack by gui_menubar_MARIONNET.ml. Reading the number back
# from the journal is what tells this bench that none was forgotten -- and that no fourth one
# was greyed by mistake.
readonly EXPECTED_WIDGETS=3

readonly START_TIMEOUT=60
readonly JOURNAL_TIMEOUT=20
# How long socat keeps the connection open waiting for the answer: longer than the longest
# question this bench asks (see [ask]).
readonly LINGER=90

declare -i passed=0 failed=0 skipped=0
declare tmpdir="" sock="" stderr="" pid=""

# The `quit' of the channel does not close the project, so a session which opened one leaves
# its /tmp/marionnet-<n>.dir/ behind. Remove the ones THIS run created -- never a whole glob:
# other sessions (or another bench) may own the others.
remove_our_run_directories() {
  local before="$tmpdir/rundirs-before" d
  [[ -r "$before" ]] || return 0
  while read -r d; do
     [[ "$d" =~ ^/tmp/marionnet-[0-9]+\.dir$ ]] || continue
     [[ -d "$d" ]] && rm -rf -- "$d"
  done < <(comm -13 "$before" <(ls -d /tmp/marionnet-*.dir 2>/dev/null | sort))
}

cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
     kill "$pid" 2>/dev/null
     wait "$pid" 2>/dev/null
  fi
  remove_our_run_directories
  local d="$tmpdir"
  # Guard: never let an empty or short variable turn this into a wide removal.
  if [[ -n "$d" && "$d" == /tmp/marionnet-bench.* && -d "$d" ]]; then
     rm -rf -- "$d"
  fi
}
trap cleanup EXIT

pass() { echo "PASS: $*"; passed+=1; }
fail() { echo "FAIL: $*"; failed+=1; }
skip() { echo "SKIP: $*"; skipped+=1; }

# One request, one line of JSON back.
#
# -t/-T are not decoration: socat closes the connection half a second after sending the request
# unless told otherwise, so any answer slower than that -- which is exactly what `wait' is --
# comes back EMPTY, without an error (measured at episode 10 of this same work-stream).
ask() { echo "$1" | timeout 120 socat -t "$LINGER" -T "$LINGER" - "UNIX-CONNECT:$sock" 2>/dev/null; }

# --- reading the reaction -------------------------------------------------------------------

# The last thing the reaction said, e.g. "saveable=false (3 widgets)", or the empty string.
last_verdict() {
  grep -o 'update_save_entries_sensitiveness: saveable=[a-z]* ([0-9]* widgets)' "$stderr" \
    | tail -1 | sed 's/^.*sensitiveness: //'
}

# The reaction answers a transition, and a transition is asynchronous: wait for the verdict
# expected instead of reading once. Note that the line is only written when the answer CHANGES,
# which is what makes "the last one" meaningful.
verdict_waits_for() {
  local expected="$1" deadline=$((SECONDS + JOURNAL_TIMEOUT))
  while (( SECONDS < deadline )); do
     [[ "$(last_verdict)" == "saveable=$expected ("* ]] && return 0
     sleep 1
  done
  return 1
}

start_and_wait() {
  local name="$1" answer
  answer=$(ask "start $name")
  if [[ "$answer" != *'"ok":true'* ]]; then
     echo "  (start $name refused: $answer)" >&2
     return 1
  fi
  answer=$(ask "wait $name --state=on --timeout=$START_TIMEOUT")
  [[ "$answer" == *'"ok":true'* ]] || { echo "  (wait $name --state=on: $answer)" >&2; return 1; }
}

# `stop' is the graceful door and `poweroff' the brutal one; which of the two a switch offers is
# published by [can], so the bench asks rather than assumes.
stop_and_wait() {
  local name="$1" answer
  answer=$(ask "stop $name")
  [[ "$answer" == *'"ok":true'* ]] || answer=$(ask "poweroff $name")
  if [[ "$answer" != *'"ok":true'* ]]; then
     echo "  (neither stop nor poweroff was accepted on $name: $answer)" >&2
     return 1
  fi
  answer=$(ask "wait $name --state=off --timeout=$START_TIMEOUT")
  [[ "$answer" == *'"ok":true'* ]] || { echo "  (wait $name --state=off: $answer)" >&2; return 1; }
}

# --- the cases ------------------------------------------------------------------------------

# A project is open and nothing runs: the three entries must be sensitive. This case also fixes
# the size of the stack -- the fix would be half done if an entry had been forgotten there, and
# wrong if a fourth one had been dragged in.
case_saveable_when_nothing_runs() {
  local verdict
  if ! verdict_waits_for true; then
     fail "with a project open and nothing running, the reaction never said saveable=true: $(last_verdict)"
     return
  fi
  verdict=$(last_verdict)
  if [[ "$verdict" != "saveable=true ($EXPECTED_WIDGETS widgets)" ]]; then
     fail "expected exactly $EXPECTED_WIDGETS widgets in the stack, the reaction says: $verdict"
     return
  fi
  pass "project open, nothing running: $verdict"
}

# The point of the episode.
case_not_saveable_while_a_switch_runs() {
  if ! start_and_wait s1; then
     fail "s1 could not be started"
     return
  fi
  if verdict_waits_for false; then
     pass "a switch is running: $(last_verdict) -- the three entries are insensitive"
  else
     fail "a switch is running but the reaction still says: $(last_verdict)"
  fi
}

# The forbidding must be lifted, not merely raised: an entry greyed forever would pass the case
# above and make the application unusable.
case_saveable_again_once_everything_is_off() {
  if ! stop_and_wait s1; then
     fail "s1 could not be stopped"
     return
  fi
  if verdict_waits_for true; then
     pass "everything is off again: $(last_verdict) -- the three entries are back"
  else
     fail "everything is off but the reaction still says: $(last_verdict)"
  fi
}

# Anti-false-positive, played BEFORE any project exists: an entry which became sensitive here
# would be worse than the defect this episode fixes -- "Save" on no project at all. The stack
# starts insensitive (sensitive_widgets_initializer) and the reaction, if it speaks at all
# before the first project, may only say false.
case_nothing_saveable_without_a_project() {
  local verdict
  verdict=$(last_verdict)
  if [[ -z "$verdict" ]]; then
     pass "no project yet: the reaction has said nothing, the stack stays as it was initialised"
  elif [[ "$verdict" == "saveable=false ("* ]]; then
     pass "no project yet: $verdict"
  else
     fail "no project yet, but the reaction says: $verdict"
  fi
}

# --- main -----------------------------------------------------------------------------------

if [[ ! -x "$BIN" ]]; then
   echo "SKIP: no executable at $BIN (build it first: dune build)"
   exit 77
fi
if [[ -z "${DISPLAY:-}" ]]; then
   echo "SKIP: this bench drives a real session, which needs a DISPLAY (marionnet initialises Gtk+)"
   exit 77
fi
if ! command -v socat >/dev/null; then
   echo "SKIP: socat is needed to talk to the control channel"
   exit 77
fi
if ! command -v vde_switch >/dev/null; then
   echo "SKIP: vde_switch is needed: this bench really starts a switch (no guest, no privilege)"
   exit 77
fi

tmpdir=$(mktemp -d /tmp/marionnet-bench.XXXXXX) || exit 1
sock="$tmpdir/control.sock"
stderr="$tmpdir/stderr"
ls -d /tmp/marionnet-*.dir 2>/dev/null | sort > "$tmpdir/rundirs-before"
echo "Bench: the saving entries are greyed exactly while something runs — $BIN"

# --debug is what makes the reaction speak: the journal goes to stderr, and its level is 0
# unless asked (initialization.ml, Debug_level).
LC_ALL=C timeout -k 5 300 "$BIN" --debug --control-socket "$sock" >/dev/null 2>"$stderr" &
pid=$!
for ((i = 0; i < 90; i++)); do [[ -S "$sock" ]] && break; sleep 1; done
if [[ ! -S "$sock" ]]; then
   echo "FAIL: no socket at $sock after 90s"
   exit 1
fi

# Before anything is opened (see the case itself for why it comes first).
sleep 2
case_nothing_saveable_without_a_project

if [[ "$(ask "new $tmpdir/bench.mar")" != *'"ok":true'* ]]; then
   echo "FAIL: could not create a project"
   exit 1
fi
if [[ "$(ask "add switch s1")" != *'"ok":true'* ]]; then
   echo "FAIL: could not add the switch"
   exit 1
fi

case_saveable_when_nothing_runs
case_not_saveable_while_a_switch_runs
case_saveable_again_once_everything_is_off

# Leave nothing running behind: the channel's `quit' does not power the network off.
ask "poweroff s1" >/dev/null
ask quit >/dev/null
wait "$pid"; pid=""

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
