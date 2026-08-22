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

# Bench: `save' and `save-as' refuse exactly what the GUI refuses -- writing the project while
# something is on or sleeping. Work-stream marionnet-todo-transverse, episode 19.
#
# Before the fix the channel wrote the project anyway: with a switch running, `save' answered
# {"ok":true,"saved":true}, while the same gesture in the GUI is opposed a dialog since forever
# ("The project can't be saved right now...", talking.ml). The reason of that refusal was
# written nowhere: the .mar is a tar of the working directory, and the cow of a running guest is
# archived WHILE its kernel writes into it (state.ml; the only exclusion, get_files_may_not_be_saved,
# concerns the OLDER snapshots, not the current cow). What a client got was therefore a .mar the
# GUI would never have written, and no way to know it.
#
# What the bench reads is the answer of the channel alone -- no journal, no pixel: the code
# (`components_running'), the names it carries, and, for `save-as', the two things a refusal must
# leave untouched (no file created, and the project still bearing its own name: save_project_as
# renames BEFORE saving, state.ml).
#
# A switch needs no guest and no privilege -- vde_switch is enough -- hence a versioned bench
# (README.md of this directory, and docs/todo-transverse.md section 3.6, criterion refined at
# episode 11).
#
# LANGUAGE/LC_ALL are pinned: since episode 15 a binary from _build reads the catalogues of the
# repository, so an English pattern would match nothing under a French locale and let the bench
# pass while proving nothing (episode 18). Nothing matched here comes from a catalogue, but the
# rule of the directory is the rule.
#
# Deliberately no `set -e': several commands here EXPECT a non-zero answer, and every status
# that matters is tested explicitly. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

readonly START_TIMEOUT=60

declare -i passed=0 failed=0 skipped=0
declare tmpdir="" sock="" stderr="" pid="" mrn_pid=""

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

# The pid captured by `pid=$!' is the pid of `timeout', not the one of the session: timeout
# relays the signals it can catch, and SIGKILL is not one of them, so a session "killed" through
# the proxy outlives its bench (measured at episode 27: 266 s, guest included). Two sources give
# the real one: the channel publishes it in `status' since episode 18, and until it answers --
# a bench waits up to 90 s for its socket -- the single child of `timeout' IS the session.
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

# Kill the session itself, by exact pid, and only once /proc has confirmed it still is ours: a
# pid gets recycled (the lesson of episode 20), and the socket path -- unique to this run -- is
# what tells our session from anything else. SIGKILL because marionnet neutralises SIGTERM
# (bin/marionnet.ml, episode 18); no `wait' here: this is timeout's child, not the shell's.
kill_the_session() {
  local -i target="${1:-0}" i
  (( target > 1 )) || return 0
  kill -0 "$target" 2>/dev/null || return 0
  grep -qz -- "$sock" "/proc/$target/cmdline" 2>/dev/null || return 0
  kill -9 "$target" 2>/dev/null
  for ((i = 0; i < 100; i++)); do kill -0 "$target" 2>/dev/null || return 0; sleep 0.1; done
}

cleanup() {
  # The session first, by its own pid.
  kill_the_session "$(session_pid)"
  # Then its proxy -- SIGTERM, never SIGKILL: timeout relays what it can catch, so a SIGTERM
  # still reaches a session we failed to identify (and its --kill-after finishes the job),
  # whereas a SIGKILL here would kill the proxy alone and leave that session behind.
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

# One request, one line of JSON back. The -t/-T are not cosmetic: without them socat drops any
# answer slower than half a second (episode 10 of this work-stream paid for that lesson).
ask() { echo "$1" | timeout 120 socat -t 60 -T 90 - "UNIX-CONNECT:$sock" 2>/dev/null; }

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

# The value of "file" as published by `status', without its quotes ("none" when there is none).
current_file() {
  local answer; answer=$(ask "status")
  echo "$answer" | grep -o '"file":"[^"]*"' | head -1 | sed 's/^"file":"//; s/"$//'
}

# --- the cases ------------------------------------------------------------------------------

# Nothing runs: the channel writes, as it always did. Played first, and again at the end: a
# guard which forbade everything would pass the two cases in between and make `save' useless.
case_save_accepted_when_nothing_runs() {
  local when="$1" answer
  answer=$(ask "save")
  if [[ "$answer" == *'"ok":true'* && "$answer" == *'"saved":true'* ]]; then
     pass "nothing is running ($when): save accepted"
  else
     fail "nothing is running ($when) but save answers: $answer"
  fi
}

# The point of the episode.
case_save_refused_while_a_switch_runs() {
  local answer
  answer=$(ask "save")
  if [[ "$answer" == *'"ok":true'* ]]; then
     fail "a switch is running and save STILL wrote the project: $answer"
     return
  fi
  if [[ "$answer" != *'"error":"components_running"'* ]]; then
     fail "a switch is running, save is refused, but not by this episode's guard: $answer"
     return
  fi
  if [[ "$answer" != *"s1"* ]]; then
     fail "the refusal does not name the component which is running: $answer"
     return
  fi
  pass "a switch is running: save refused, components_running, and the detail names s1"
}

# `save-as' shares the body of `save', but has more to leave untouched: save_project_as renames
# the project BEFORE saving it (state.ml), so a refusal which came too late would leave the
# session bearing a name whose file was never written.
case_save_as_refused_and_writes_nothing() {
  local target="$tmpdir/copy.mar" before after answer
  before=$(current_file)
  answer=$(ask "save-as $target")
  if [[ "$answer" != *'"error":"components_running"'* ]]; then
     fail "a switch is running but save-as answers: $answer"
     return
  fi
  if [[ -e "$target" ]]; then
     fail "save-as was refused, yet $target exists"
     return
  fi
  after=$(current_file)
  if [[ "$after" != "$before" ]]; then
     fail "save-as was refused, yet the project is now called $after (it was $before)"
     return
  fi
  pass "a switch is running: save-as refused, no file written, project still $after"
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
echo "Bench: save and save-as refuse while something runs — $BIN"

LANGUAGE=C LC_ALL=C timeout -k 5 300 "$BIN" --control-socket "$sock" >/dev/null 2>"$stderr" &
pid=$!
for ((i = 0; i < 90; i++)); do [[ -S "$sock" ]] && break; sleep 1; done
if [[ ! -S "$sock" ]]; then
   echo "FAIL: no socket at $sock after 90s"
   exit 1
fi
mrn_pid=$(session_pid_from_channel)

if [[ "$(ask "new $tmpdir/bench.mar")" != *'"ok":true'* ]]; then
   echo "FAIL: could not create a project"
   exit 1
fi
if [[ "$(ask "add switch s1")" != *'"ok":true'* ]]; then
   echo "FAIL: could not add the switch"
   exit 1
fi

case_save_accepted_when_nothing_runs "before"

if start_and_wait s1; then
   case_save_refused_while_a_switch_runs
   case_save_as_refused_and_writes_nothing
   if stop_and_wait s1; then
      case_save_accepted_when_nothing_runs "again"
   else
      fail "s1 could not be stopped: the last case could not be played"
   fi
else
   fail "s1 could not be started: the three cases which need it could not be played"
fi

# Leave nothing running behind: the channel's `quit' does not power the network off.
ask "poweroff s1" >/dev/null
ask quit >/dev/null
wait "$pid"; pid=""; mrn_pid=""

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
(( failed == 0 )) || exit 1
exit 0
