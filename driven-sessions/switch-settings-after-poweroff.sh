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

# Bench: on a switch, `activate_fstp' and `show_vde_terminal' accepted while it is off are those
# of its NEXT start. Work-stream marionnet-todo-transverse, episode 21 -- the twin of episode 11,
# which did the same for the rc.
#
# A switch, unlike a machine or a router, does NOT destroy its simulated device when it is powered
# off (no cow file to renew), so everything the device was built with is frozen at the FIRST start.
# Before the fix:
#   * `--fstp' was part of a command line built once, at the birth of the device, hence a switch
#     started once without FSTP never got it, whatever `set ... activate_fstp true' answered;
#   * the xterm was added by an `initializer', hence enabling `show_vde_terminal' afterwards could
#     not produce anything at all.
#
# What the bench reads is not the model (which was never the liar) but what vde_switch itself says
# through the management socket (`switch-info <switch> fstp', field "fstp_enabled"), and, for the
# terminal, the process table of the host: an `xterm' talking to THIS switch's management socket.
#
# A switch needs no guest and no privilege -- vde_switch is enough -- hence a versioned bench
# (docs/todo-transverse.md, section 3.6). Note that the terminal cases really open an xterm on the
# screen for a few seconds; they are skipped when xterm is not installed.
#
# Deliberately no `set -e': several commands here EXPECT a non-zero answer, and every status that
# matters is tested explicitly. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

# How long a start is given, and how long we wait for an accessory process to show up.
readonly START_TIMEOUT=60
readonly XTERM_TIMEOUT=15
# How long socat keeps the connection open waiting for the answer: longer than the longest
# question this bench asks (see [ask]).
readonly LINGER=90

declare -i passed=0 failed=0 skipped=0
declare tmpdir="" sock="" pid="" mrn_pid=""

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
skip() { echo "SKIP: $*"; skipped+=1; }

# One request, one line of JSON back.
#
# -t/-T are not decoration: socat closes the connection half a second after sending the request
# unless told otherwise, so any answer slower than that comes back EMPTY, without an error
# (measured at episode 10 of this same work-stream).
ask() { echo "$1" | timeout 120 socat -t "$LINGER" -T "$LINGER" - "UNIX-CONNECT:$sock" 2>/dev/null; }

# --- driving a switch -----------------------------------------------------------------------

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

set_field() {
  local name="$1" field="$2" value="$3" answer
  answer=$(ask "set $name $field $value")
  [[ "$answer" == *'"ok":true'* ]] || { echo "  (set $name $field $value: $answer)" >&2; return 1; }
}

# What vde_switch answers about its own spanning tree, as the switch is running. The interesting
# field is "fstp_enabled": true only when the process was given --fstp on its command line.
fstp_is_enabled() {
  local answer
  answer=$(ask "switch-info $1 fstp")
  [[ "$answer" == *'"fstp_enabled":true'* ]]
}

# The management socket of a switch, published by [switch-info]. Its name is fixed once and for
# all when the simulated device is born, so it identifies THIS switch of THIS session, whatever
# the number of starts -- which is what makes the xterm test immune to any other Marionnet
# session running on the same host.
mgmt_socket_of() {
  ask "switch-info $1 fstp" | sed -n 's/^.*"socket":"\([^"]*\)".*$/\1/p'
}

# Is there an xterm talking to that management socket? The vde_switch process itself carries the
# same path (--mgmt), hence the first filter on the program name. Read-only: this bench never
# kills anything by pattern.
xterm_talks_to() {
  local socket="$1"
  ps -eo args= | grep -E '^xterm ' | grep -qF -- "$socket"
}

xterm_appears_for() {
  local socket="$1" deadline=$((SECONDS + XTERM_TIMEOUT))
  while (( SECONDS < deadline )); do
     xterm_talks_to "$socket" && return 0
     sleep 1
  done
  return 1
}

# The absence has to be given the same chance as the presence, or it would just be measuring
# that we looked too early.
xterm_stays_away_from() {
  local socket="$1" deadline=$((SECONDS + 5))
  while (( SECONDS < deadline )); do
     xterm_talks_to "$socket" && return 1
     sleep 1
  done
  return 0
}

# --- the cases: activate_fstp ----------------------------------------------------------------

# Anti-false-positive, and the state of things before the episode: a switch started without FSTP
# must not have it. A fix which passed --fstp unconditionally would pass every other case.
case_fstp_absent_at_a_bare_first_start() {
  if ! start_and_wait s1; then
     fail "s1 could not be started (first start, without fstp)"
     return
  fi
  if fstp_is_enabled s1; then
     fail "first start: s1 was given no fstp and vde_switch says it is enabled"
  else
     pass "first start: s1 runs without fstp, as its model says"
  fi
}

# The point of the episode. The switch is off, its simulated device still there, and the setting
# is flipped: the next start must carry --fstp.
case_fstp_enabled_after_a_bare_start() {
  if ! stop_and_wait s1; then fail "s1 could not be stopped"; return; fi
  if ! set_field s1 activate_fstp true; then
     fail "set s1 activate_fstp true was refused"
     return
  fi
  if ! start_and_wait s1; then fail "s1 could not be started again"; return; fi
  if fstp_is_enabled s1; then
     pass "second start: the fstp accepted while s1 was off is the one it runs with"
  else
     fail "second start: s1 accepted activate_fstp=true and still runs without it (the command line was frozen at the first start)"
  fi
}

# The symmetric half: what is switched on must be switchable off again, or "always --fstp" would
# pass the case above.
case_fstp_disabled_again() {
  if ! stop_and_wait s1; then fail "s1 could not be stopped (second time)"; return; fi
  if ! set_field s1 activate_fstp false; then
     fail "set s1 activate_fstp false was refused"
     return
  fi
  if ! start_and_wait s1; then fail "s1 could not be started a third time"; return; fi
  if fstp_is_enabled s1; then
     fail "third start: s1 still runs with fstp although its model no longer asks for it"
  else
     pass "third start: the fstp withdrawn while s1 was off is withdrawn from the process too"
  fi
}

# --- the cases: show_vde_terminal -------------------------------------------------------------

# Same three-step shape, on the setting which used to be decided by an `initializer'.
case_terminal_absent_at_a_bare_first_start() {
  if ! start_and_wait stm1; then
     fail "stm1 could not be started (first start, without terminal)"
     return
  fi
  terminal_socket=$(mgmt_socket_of stm1)
  if [[ -z "$terminal_socket" ]]; then
     fail "could not read the management socket of stm1: $(ask "switch-info stm1 fstp")"
     return
  fi
  if xterm_stays_away_from "$terminal_socket"; then
     pass "first start: stm1 was given no terminal and none is running"
  else
     fail "first start: an xterm is talking to stm1 although show_vde_terminal is false"
  fi
}

case_terminal_enabled_after_a_bare_start() {
  if ! stop_and_wait stm1; then fail "stm1 could not be stopped"; return; fi
  if ! set_field stm1 show_vde_terminal true; then
     fail "set stm1 show_vde_terminal true was refused"
     return
  fi
  if ! start_and_wait stm1; then fail "stm1 could not be started again"; return; fi
  if xterm_appears_for "$terminal_socket"; then
     pass "second start: the terminal accepted while stm1 was off is opened"
  else
     fail "second start: stm1 accepted show_vde_terminal=true and no xterm was opened (the accessory process was decided at the birth of the device)"
  fi
}

case_terminal_disabled_again() {
  if ! stop_and_wait stm1; then fail "stm1 could not be stopped (second time)"; return; fi
  if ! set_field stm1 show_vde_terminal false; then
     fail "set stm1 show_vde_terminal false was refused"
     return
  fi
  if ! start_and_wait stm1; then fail "stm1 could not be started a third time"; return; fi
  if xterm_stays_away_from "$terminal_socket"; then
     pass "third start: the terminal withdrawn while stm1 was off is not opened again"
  else
     fail "third start: an xterm is still opened for stm1 although show_vde_terminal is false"
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
   echo "SKIP: vde_switch is needed: this bench really starts switches (no guest, no privilege)"
   exit 77
fi

tmpdir=$(mktemp -d /tmp/marionnet-bench.XXXXXX) || exit 1
sock="$tmpdir/control.sock"
terminal_socket=""
ls -d /tmp/marionnet-*.dir 2>/dev/null | sort > "$tmpdir/rundirs-before"
echo "Bench: what a switch is given at every start, not once at the first one — $BIN"

# The language is pinned: since episode 15 a binary run from _build is translated, and a bench
# which matched an English word of the application would silently stop proving anything.
LANGUAGE=C LC_ALL=C timeout -k 5 400 "$BIN" --control-socket "$sock" >/dev/null 2>"$tmpdir/stderr" &
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
   echo "FAIL: could not add the switch of the fstp cases"
   exit 1
fi

case_fstp_absent_at_a_bare_first_start
case_fstp_enabled_after_a_bare_start
case_fstp_disabled_again

if ! command -v xterm >/dev/null; then
   skip "xterm is not installed: the three show_vde_terminal cases cannot be observed"
elif [[ "$(ask "add switch stm1")" != '{"ok":true'* ]]; then
   fail "could not add the switch of the terminal cases"
else
   case_terminal_absent_at_a_bare_first_start
   case_terminal_enabled_after_a_bare_start
   case_terminal_disabled_again
fi

# Leave nothing running behind: the channel's `quit' does not power the network off.
ask "poweroff s1" >/dev/null
ask "poweroff stm1" >/dev/null
ask quit >/dev/null
wait "$pid"; pid=""; mrn_pid=""

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
