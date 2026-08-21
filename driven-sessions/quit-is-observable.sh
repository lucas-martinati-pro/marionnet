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

# Bench: the end of a driven session is observable through the channel alone.
# Work-stream marionnet-todo-transverse, episode 18.
#
# `quit' answers and only THEN lets the main loop stop (control_server.ml: the answer is sent
# before st#quit_async, which merely schedules the shutdown on the Task_runner). So when the
# client reads {"ok":true,"quitting":true} the process, its components and its taps are still
# there. A bench survives that because it owns the pid (`wait "$pid"'); a client of the channel
# does not -- it holds a socket, and the socket says nothing. Two sessions then coexist without
# anyone knowing, which is how three marionnet.exe were once found together.
#
# One cannot answer AFTER leaving: the answer necessarily goes out first. The fix is therefore
# not a synchronous quit but a handle on what the client can watch afterwards -- the pid, which
# `quit' (and `status') now publishes.
#
# Why the pid and not the socket file, which ocamlbricks does remove on the way out
# (ThreadExtra.at_exit, network.ml): because that removal only happens on a CLEAN exit. Cases 5
# and 6 measure both halves -- the file is gone after `quit', and still there after a SIGKILL.
# The absence of the file therefore proves an ending; its presence proves nothing, which is
# precisely what a client must not have to guess.
#
# Neither a guest nor a privilege is needed -- no component is ever started -- which is what
# makes this bench versioned rather than throwaway (README.md of this directory, and
# docs/todo-transverse.md section 3.6). A DISPLAY is needed, as always: marionnet initialises
# Gtk+ before serving anything.
#
# Deliberately no `set -e': several commands here EXPECT a non-zero answer, and every status
# that matters is tested explicitly. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

# How long a session may take to disappear once it has answered `quit'. Generous on purpose:
# the number this bench reports is the MEASURED delay, this is only the fuse.
readonly DEATH_TIMEOUT_S=60

# EPOCHREALTIME honours LC_NUMERIC: under a French locale its separator is a COMMA, and
# ${EPOCHREALTIME/./} then leaves a string no arithmetic context can read (measured).
now_ms() { local t="${EPOCHREALTIME}"; t="${t//[.,]/}"; echo $(( 10#$t / 1000 )); }

declare -i passed=0 failed=0 skipped=0
declare tmpdir="" sock="" pid="" fakehome="" brutally_killed_sock=""

# The `quit' of the channel does not close the project, so a session which opened one leaves
# its /tmp/marionnet-<n>.dir/ behind (case 6 opens one). Remove the ones THIS run created --
# never a whole glob: other sessions (or another bench) may own the others.
remove_our_run_directories() {
  local before="$tmpdir/rundirs-before" d
  [[ -r "$before" ]] || return 0
  while read -r d; do
     [[ "$d" =~ ^/tmp/marionnet-[0-9]+\.dir$ ]] || continue
     [[ -d "$d" ]] && rm -rf -- "$d"
  done < <(comm -13 "$before" <(ls -d /tmp/marionnet-*.dir 2>/dev/null | sort))
}

# Marionnet NEUTRALISES SIGTERM on purpose (bin/marionnet.ml: a `halt' inside a guest sends one,
# through the broken X connection of a graphical program). A `kill' followed by `wait' therefore
# hangs for ever -- measured, the first run of this bench sat there until its own fuse. Whatever
# a bench starts, it must end either through the channel (`quit') or with SIGKILL.
# SIGKILL then `wait', with nothing in between: any command run between the two lets the shell
# notice the job died and print its own "Killed" line, which would sit in the middle of the
# PASS/FAIL lines and read like an incident.
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
skip() { echo "SKIP: $*"; skipped+=1; }

# One request, one line of JSON back. The -t/-T are not cosmetic: without them socat drops any
# answer slower than half a second (episode 10 of this work-stream paid for that lesson).
ask() { echo "$1" | timeout 120 socat -t 60 -T 90 - "UNIX-CONNECT:$sock" 2>/dev/null; }

# `ask' cannot serve the `quit' request: socat returns when the CONNECTION closes, and the
# connection closes when the process dies -- so the measurement of case 3 ("still alive when
# the answer is read") would always come out false, for a reason which has nothing to do with
# what is being measured. A coprocess reads the answer line as soon as it arrives and leaves
# the session running.
ask_quit_without_waiting_for_the_end() {
  local answer=""
  coproc CHANNEL { timeout 120 socat -t 60 -T 90 - "UNIX-CONNECT:$sock" 2>/dev/null; }
  echo "quit" >&"${CHANNEL[1]}"
  read -r -t 60 answer <&"${CHANNEL[0]}"
  echo "$answer"
}

# A child of THIS shell which has exited but has not been waited for stays a zombie, and
# `kill -0' keeps succeeding on it. A client of the channel is never the parent, so it never
# meets that case; this bench, which launched the session itself, must exclude it explicitly --
# otherwise case 4 would wait for ever on a process which is long gone. (The user guide says
# the same thing to whoever launches marionnet from their own script.)
session_is_alive() {
  local state
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  state=$(sed -E 's/^[0-9]+ \(.*\) ([A-Za-z]).*/\1/' "/proc/$pid/stat" 2>/dev/null)
  [[ -n "$state" && "$state" != "Z" ]]
}

# The channel writes compact JSON, but the bench does not depend on that.
pid_field_of() {
  local answer="$1"
  [[ "$answer" =~ \"pid\"[[:space:]]*:[[:space:]]*([0-9]+) ]] && echo "${BASH_REMATCH[1]}"
}

# --- the cases ------------------------------------------------------------------------------

# Armed BEFORE quitting: a client which wants to watch the session end should not have to quit
# first to learn what to watch. It is also the only source left when `quit' is refused (case 6).
case_status_publishes_the_pid() {
  local answer got
  answer=$(ask status)
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "status: failed: $answer"
     return
  fi
  got=$(pid_field_of "$answer")
  if [[ -z "$got" ]]; then
     fail "status: no pid field -- a client cannot arm its watch before quitting: $answer"
     return
  fi
  if [[ "$got" != "$pid" ]]; then
     fail "status: published pid $got, but the session really is $pid"
     return
  fi
  pass "status: publishes the pid of the session ($got)"
}

# THE entry: the answer must carry the handle, and the handle must be the right one. This is
# the case which fails on the code before the fix.
case_quit_answers_with_the_pid() {
  local answer="$1" got
  if [[ "$answer" != *'"ok":true'* || "$answer" != *'"quitting":true'* ]]; then
     fail "quit: not a quitting answer: $answer"
     return
  fi
  got=$(pid_field_of "$answer")
  if [[ -z "$got" ]]; then
     fail "quit: the answer carries no pid -- the end of the session is not observable through
      the channel alone: $answer"
     return
  fi
  if [[ "$got" != "$pid" ]]; then
     fail "quit: answered pid $got, but the session really is $pid"
     return
  fi
  pass "quit: the answer carries the pid of the session ($got)"
}

# The constat of the TODO entry, measured rather than assumed -- and still true after the fix,
# since one cannot answer after leaving. It is the whole reason a handle is needed.
case_the_process_is_still_there_when_the_answer_is_read() {
  local alive="$1"
  if [[ "$alive" == "yes" ]]; then
     pass "quit: when the client reads the answer, the process is STILL there (hence the pid)"
  else
     skip "quit: the session was already gone when the answer was read -- nothing to measure
      here, but the handle is what makes the difference observable at all"
  fi
}

# What the contract promises: watching the pid alone is enough, and it terminates.
case_waiting_on_the_pid_alone_terminates() {
  local -i start_ms end_ms
  start_ms=$(now_ms)
  local -i deadline_ms=$(( start_ms + DEATH_TIMEOUT_S * 1000 ))
  while session_is_alive; do
     end_ms=$(now_ms)
     if (( end_ms > deadline_ms )); then
        fail "quit: the session was still alive ${DEATH_TIMEOUT_S}s after answering"
        return
     fi
     sleep 0.05
  done
  end_ms=$(now_ms)
  pass "quit: watching the pid alone ends the wait (measured: $(( end_ms - start_ms )) ms)"
  wait "$pid" 2>/dev/null
  pid=""
}

# Half of the justification of the contract chosen: after a clean exit the socket file IS gone
# (ocamlbricks unlinks it from the server thread), so its absence does prove an ending.
case_the_socket_file_is_gone_after_a_clean_exit() {
  if [[ -e "$sock" ]]; then
     fail "the socket file is still there after a clean exit: the user guide says it is removed"
     return
  fi
  pass "the socket file is gone after a clean exit (its absence proves an ending)"
}

# The contract belongs to the `quitting' answer, not to the refusals: in exam mode `quit' is
# refused while the copy is at stake, and a refusal promises nothing about any ending.
case_an_exam_refusal_carries_no_pid() {
  local exam_sock="$tmpdir/exam.sock" exam_journal="$tmpdir/exam-journal" answer
  local -i exam_pid=0 i
  env HOME="$fakehome" "$BIN" --debug --exam --control-socket "$exam_sock" \
     >/dev/null 2>"$exam_journal" &
  exam_pid=$!
  for ((i = 0; i < 90; i++)); do [[ -S "$exam_sock" ]] && break; sleep 1; done
  if [[ ! -S "$exam_sock" ]]; then
     kill_and_reap "$exam_pid"
     skip "exam mode: no socket after 90s, the refusal path could not be played"
     return
  fi
  local saved_sock="$sock"
  sock="$exam_sock"
  # A project which is open and not saved: this is what makes quit refusable in exam mode.
  if [[ "$(ask "new $tmpdir/exam.mar")" != *'"ok":true'* ]] ||
     [[ "$(ask "add machine mx")" != *'"ok":true'* ]]; then
     sock="$saved_sock"
     kill_and_reap "$exam_pid"
     skip "exam mode: could not open an unsaved project, the refusal path could not be played"
     return
  fi
  answer=$(ask quit)
  sock="$saved_sock"
  if [[ "$answer" == *'"ok":true'* ]]; then
     fail "exam mode: quit was accepted although the copy is unsaved: $answer"
  elif [[ "$answer" == *'"quitting"'* || -n "$(pid_field_of "$answer")" ]]; then
     fail "exam mode: the refusal carries quitting/pid, which promise an ending that will not
      happen: $answer"
  else
     pass "exam mode: quit is refused, and the refusal promises no ending"
  fi
  # This session is killed rather than asked to leave -- and that is what case 6 needs.
  kill_and_reap "$exam_pid"
  brutally_killed_sock="$exam_sock"
}

# The other half of the justification, and the reason the pid wins: the removal above belongs to
# a clean exit. A session which dies brutally leaves its socket file behind, so a client watching
# the FILE would wait for ever on the very case where knowing is most useful. The pid says the
# truth in both.
case_a_brutal_death_leaves_the_socket_file() {
  if [[ -z "$brutally_killed_sock" ]]; then
     skip "a brutal death: no session was killed (the exam case did not run)"
     return
  fi
  if [[ -e "$brutally_killed_sock" ]]; then
     pass "a session killed with SIGKILL leaves its socket file (hence: the file is not a handle)"
  else
     fail "a session killed with SIGKILL removed its socket file anyway: then the guide's
      warning about brutal deaths is wrong, and must be rewritten"
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

tmpdir=$(mktemp -d /tmp/marionnet-bench.XXXXXX) || exit 1
sock="$tmpdir/control.sock"
fakehome="$tmpdir/home"
mkdir -p "$fakehome"
ls -d /tmp/marionnet-*.dir 2>/dev/null | sort > "$tmpdir/rundirs-before"
echo "Bench: the end of a driven session is observable through the channel alone — $BIN"

# NO `timeout' wrapper here, unlike the other benches of this directory: `timeout' would be the
# process the shell knows, and the bench must compare the published pid with the REAL one. The
# fuses are elsewhere: every request is bounded, and so is the wait of case 4.
# HOME points inside the temporary directory: nothing of the user's own installation takes part.
env HOME="$fakehome" "$BIN" --debug --control-socket "$sock" >/dev/null 2>"$tmpdir/journal" &
pid=$!
for ((i = 0; i < 90; i++)); do [[ -S "$sock" ]] && break; sleep 1; done
[[ -S "$sock" ]] || { echo "FAIL: no socket at $sock after 90s"; exit 1; }

case_status_publishes_the_pid

# The two measurements which must be taken in this order, on the same answer.
quit_answer=$(ask_quit_without_waiting_for_the_end)
alive_right_after=no
session_is_alive && alive_right_after=yes

case_quit_answers_with_the_pid "$quit_answer"
case_the_process_is_still_there_when_the_answer_is_read "$alive_right_after"
case_waiting_on_the_pid_alone_terminates
case_the_socket_file_is_gone_after_a_clean_exit

case_an_exam_refusal_carries_no_pid
case_a_brutal_death_leaves_the_socket_file

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
