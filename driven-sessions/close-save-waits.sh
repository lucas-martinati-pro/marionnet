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

# Bench: `close --save' saves a network which is DOWN. Work-stream marionnet-todo-transverse,
# episode 26.
#
# Since episode 19 `save' refuses to write the project while something is on or sleeping: the
# .mar is a tar of the working directory, so the cow of a running guest would be archived in
# mid-flight. `close --save' kept accepting -- not as an assumed exception but as a RACE:
# leave_current_project (control_server.ml) called st#shutdown_everything (), which only
# *schedules* its tasks on the task runner, and went straight on to st#save_project.
#
# Measured on the code before the fix, with a switch running (--debug journal, in this order):
#
#   Control_server: leaving the current project (save: true).
#   state#save_project BEGIN                            <-- the tar leaves...
#   task_runner: Executing the task "In parallel: Shut down s1 || "   <-- ...before the shutdown
#   state#save_project END. Success.                                      has even begun
#   I have joined "Shut down s1" with success
#
# What this bench reads is therefore an ORDER in the journal, not a duration: the saving must
# begin AFTER the parallel shutdown task has succeeded. Comparing positions rather than
# timestamps is what keeps it meaningful on a switch, whose shutdown lasts a fraction of a
# second (on a UML guest the same window lasts tens of seconds -- the case which motivated the
# entry, and which no versioned bench may require).
#
# The GUI menu was NOT in the same state, contrary to what the TODO entry supposed:
# Common_dialogs.shutdown_then_save (gui_menubar_MARIONNET.ml) already waits for the task runner
# between the shutdown and the saving, since episode 23 of journalisation-profonde. The channel
# was the only one late; this bench watches the channel alone.
#
# A switch needs no guest and no privilege -- vde_switch is enough -- hence a versioned bench
# (README.md of this directory, and docs/todo-transverse.md section 3.6, criterion refined at
# episode 11).
#
# LANGUAGE/LC_ALL are pinned: since episode 15 a binary from _build reads the catalogues of the
# repository, so an English pattern would match nothing under a French locale and let the bench
# pass while proving nothing (episode 18). The journal lines matched here are not translated,
# but the rule of the directory is the rule.
#
# Deliberately no `set -e': several helpers here return non-zero on purpose, and every status
# that matters is tested explicitly. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

readonly START_TIMEOUT=60

declare -i passed=0 failed=0 skipped=0
declare tmpdir="" sock="" stderr="" pid=""

# The `quit' of the channel does not close the project, so a session which opened one leaves its
# /tmp/marionnet-<n>.dir/ behind. Remove the ones THIS run created -- never a whole glob: other
# sessions (or another bench) may own the others.
remove_our_run_directories() {
  local before="$tmpdir/rundirs-before" d
  [[ -r "$before" ]] || return 0
  while read -r d; do
     [[ "$d" =~ ^/tmp/marionnet-[0-9]+\.dir$ ]] || continue
     [[ -d "$d" ]] && rm -rf -- "$d"
  done < <(comm -13 "$before" <(ls -d /tmp/marionnet-*.dir 2>/dev/null | sort))
}

# SIGTERM is neutralised by marionnet (bin/marionnet.ml), so `kill' then `wait' would never
# return: a session which did not leave through the channel leaves through SIGKILL (episode 18).
kill_and_reap() {
  local -i target="$1"
  kill -9 "$target" 2>/dev/null
  wait "$target" 2>/dev/null
}

cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
     kill_and_reap "$pid"
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

# One request, one line of JSON back. The -t/-T are not cosmetic: without them socat drops any
# answer slower than half a second (episode 10 of this work-stream paid for that lesson).
# The read timeout is generous on purpose: since this episode, `close --save' lasts as long as
# the shutdown does -- exactly the price the entry announced.
ask() { echo "$1" | timeout 240 socat -t 120 -T 200 - "UNIX-CONNECT:$sock" 2>/dev/null; }

# --debug is what makes the sequence speak: the journal goes to stderr.
start_session() {
  tmpdir=$(mktemp -d /tmp/marionnet-bench.XXXXXX) || return 1
  sock="$tmpdir/control.sock"
  stderr="$tmpdir/stderr"
  ls -d /tmp/marionnet-*.dir 2>/dev/null | sort > "$tmpdir/rundirs-before"
  LANGUAGE=C LC_ALL=C timeout -k 5 300 "$BIN" --debug --control-socket "$sock" \
     >/dev/null 2>"$stderr" &
  pid=$!
  local -i i
  for ((i = 0; i < 90; i++)); do [[ -S "$sock" ]] && break; sleep 1; done
  [[ -S "$sock" ]]
}

# Number of the FIRST journal line matching $1 at or after line $2, or nothing when there is
# none. Fixed string, never a regexp: the patterns below carry quotes and parentheses.
line_of() {
  local pattern="$1" from="$2"
  awk -v pat="$pattern" -v from="$from" \
      'NR >= from && index($0, pat) { print NR; exit }' "$stderr"
}

# --- the cases ------------------------------------------------------------------------------

# The point of the episode. Everything is read in the window which begins at the line
# leave_current_project writes: the same session started and stopped the switch before, so the
# journal already holds other shutdown lines.
case_saving_begins_after_the_shutdown_ended() {
  local -i mark shutdown_done saving_begins waited
  mark=$(line_of 'Control_server: leaving the current project (save: true).' 1)
  if [[ -z "${mark:-}" || "$mark" == "0" ]]; then
     fail "the journal does not say that the project was left with --save"
     return
  fi
  saving_begins=$(line_of 'state#save_project BEGIN' "$mark")
  if [[ -z "${saving_begins:-}" || "$saving_begins" == "0" ]]; then
     fail "close --save answered, yet the journal shows no saving after it"
     return
  fi
  shutdown_done=$(line_of 'task_runner: The task "In parallel: Shut down s1 || " succeeded.' "$mark")
  if [[ -z "${shutdown_done:-}" || "$shutdown_done" == "0" ]]; then
     fail "the shutdown of s1 was never scheduled by close (nothing was running?)"
     return
  fi
  if (( saving_begins < shutdown_done )); then
     fail "the project was saved (line $saving_begins) BEFORE the shutdown of s1 ended (line $shutdown_done)"
     return
  fi
  # The waiting is what makes the order deterministic rather than lucky.
  waited=$(line_of '...all right, we have been signaled: tasks did terminate.' "$mark")
  if [[ -z "${waited:-}" || "$waited" == "0" ]] || (( waited > saving_begins )); then
     fail "the saving came after the shutdown, but without waiting for the task runner (luck, not order)"
     return
  fi
  pass "close --save waited for the shutdown of s1 (ended at $shutdown_done) before saving (at $saving_begins)"
}

# The answer must not change: this episode changes WHEN it comes back, not what it says.
case_the_answer_is_unchanged() {
  local answer="$1"
  if [[ "$answer" == *'"ok":true'* && "$answer" == *'"closed":true'* && "$answer" == *'"saved":true'* ]]; then
     pass "close --save still answers ok/closed/saved"
  else
     fail "close --save answers: $answer"
  fi
}

# A guard which waited forever, or saved nothing, would pass the order test above.
case_the_file_was_really_written() {
  local target="$1"
  if [[ -s "$target" ]]; then
     pass "the .mar was written ($(stat -c %s "$target") bytes)"
  else
     fail "no readable .mar at $target after close --save"
  fi
}

# Nothing is running: the unconditional wait must not cost anything (no task is scheduled, so
# the task runner signals at once). Played in a session of its own, on a fresh project.
case_close_save_with_nothing_running() {
  local answer
  answer=$(ask "close --save")
  if [[ "$answer" == *'"ok":true'* && "$answer" == *'"saved":true'* ]]; then
     pass "nothing running: close --save still closes and saves"
  else
     fail "nothing running, yet close --save answers: $answer"
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

echo "Bench: close --save saves a network which is down — $BIN"

# --- session 1: a switch is running when the project is left ---------------------------------

if ! start_session; then
   echo "FAIL: no socket at $sock after 90s"
   exit 1
fi
declare mar="$tmpdir/bench.mar"
if [[ "$(ask "new $mar")" != *'"ok":true'* ]]; then
   echo "FAIL: could not create a project"
   exit 1
fi
if [[ "$(ask "add switch s1")" != *'"ok":true'* ]]; then
   echo "FAIL: could not add the switch"
   exit 1
fi
if [[ "$(ask "start s1")" != *'"ok":true'* ]]; then
   echo "FAIL: could not start the switch"
   exit 1
fi
if [[ "$(ask "wait s1 --state=on --timeout=$START_TIMEOUT")" != *'"ok":true'* ]]; then
   echo "FAIL: the switch never reached the state on"
   exit 1
fi

declare answer; answer=$(ask "close --save")
case_the_answer_is_unchanged "$answer"
case_saving_begins_after_the_shutdown_ended
case_the_file_was_really_written "$mar"

ask quit >/dev/null
wait "$pid"; pid=""
remove_our_run_directories

# --- session 2: nothing is running ------------------------------------------------------------

declare keep="$tmpdir"
if start_session; then
   if [[ "$(ask "new $tmpdir/idle.mar")" == *'"ok":true'* ]]; then
      case_close_save_with_nothing_running
   else
      fail "could not create the project of the second session"
   fi
   ask quit >/dev/null
   wait "$pid"; pid=""
else
   fail "the second session did not open its socket"
fi
rm -rf -- "$keep"

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
(( failed == 0 )) || exit 1
exit 0
