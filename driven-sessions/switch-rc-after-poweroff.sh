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

# Bench: an `rc-set' accepted on a switch is the one played at its NEXT start, not the one which
# was there when the simulated device was born. Work-stream marionnet-todo-transverse, episode 11.
#
# Before the fix the content was read once, in make_simulated_device (switch.ml), and a switch --
# unlike a machine or a router, which destroy their device to renew their cow file -- keeps its
# simulated device across a poweroff. So the first start froze the rc forever: `rc-set' answered
# changed:true, `rc-get' read the new text back, and the switch replayed the old one in silence.
#
# What the bench reads is not the model (which was never the liar) but the journal of what
# Marionnet actually said to vde_switch: `log <switch> rc_config' (journalisation-profonde,
# episode 4), rewritten at every start.
#
# A switch needs no guest and no privilege -- vde_switch is enough -- hence a versioned bench
# (docs/todo-transverse.md, section 3.6), although the table of section 4 announced a throwaway one.
#
# Deliberately no `set -e': several commands here EXPECT a non-zero answer, and every status
# that matters is tested explicitly. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

# vde_switch commands, chosen among those which change something observable and cannot be
# confused with one another in the journal.
readonly RC_FIRST="vlan/create 5"
readonly RC_SECOND="vlan/create 7"
readonly RC_LATE="vlan/create 9"

# How long a start (and the thread which sends the rc afterwards) is given.
readonly START_TIMEOUT=60
readonly JOURNAL_TIMEOUT=20
# How long socat keeps the connection open waiting for the answer: longer than the longest
# question this bench asks (see [ask]).
readonly LINGER=90

declare -i passed=0 failed=0 skipped=0
declare tmpdir="" sock="" pid=""

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

# --- driving a switch -----------------------------------------------------------------------

# The journal of what marionnet said to vde_switch, as one JSON line. Its "content" field carries
# the whole file with the newlines escaped, which is exactly what a substring test wants.
journal_of() { ask "log $1 rc_config"; }

# The rc is sent by a thread of its own, after the ports are allocated: the switch is `on' before
# the journal is complete. So the bench waits for what it expects instead of reading once.
journal_waits_for() {
  local name="$1" needle="$2" deadline=$((SECONDS + JOURNAL_TIMEOUT))
  while (( SECONDS < deadline )); do
     [[ "$(journal_of "$name")" == *"$needle"* ]] && return 0
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

# Anti-false-positive, and the state of things before the episode: the rc of the FIRST start was
# never the problem. A fix which broke this one would pass every case below.
case_first_start_plays_its_rc() {
  local answer
  answer=$(ask "rc-set s1 --enable $RC_FIRST")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "rc-set s1 --enable ${RC_FIRST@Q}: refused: $answer"
     return
  fi
  if ! start_and_wait s1; then
     fail "s1 could not be started (first start)"
     return
  fi
  if journal_waits_for s1 "$RC_FIRST"; then
     pass "first start: the journal of s1 shows ${RC_FIRST@Q}, the rc it was given"
  else
     fail "first start: the journal of s1 never showed ${RC_FIRST@Q}: $(journal_of s1)"
  fi
}

# The point of the episode. The switch is off, its device still there, and the rc is replaced.
case_second_start_plays_the_new_rc() {
  local answer content
  if ! stop_and_wait s1; then
     fail "s1 could not be stopped"
     return
  fi
  answer=$(ask "rc-set s1 $RC_SECOND")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "rc-set s1 ${RC_SECOND@Q}: refused: $answer"
     return
  fi
  if [[ "$(ask "rc-get s1")" != *"$RC_SECOND"* ]]; then
     fail "rc-get s1 does not read back ${RC_SECOND@Q}: the model itself did not take the write"
     return
  fi
  if ! start_and_wait s1; then
     fail "s1 could not be started again"
     return
  fi
  if ! journal_waits_for s1 "$RC_SECOND"; then
     fail "second start: the journal of s1 never showed ${RC_SECOND@Q} (the rc it was just given): $(journal_of s1)"
     return
  fi
  content=$(journal_of s1)
  if [[ "$content" == *"$RC_FIRST"* ]]; then
     fail "second start: the journal of s1 shows ${RC_SECOND@Q} but ALSO the old ${RC_FIRST@Q}"
     return
  fi
  pass "second start: s1 plays ${RC_SECOND@Q}, and no longer the ${RC_FIRST@Q} of its first start"
}

# The other half of the same freeze, and the one which flips a branch rather than a value: a
# switch started once WITHOUT any rc took the plain spawning path forever, whatever was set
# afterwards. Its journal said so in as many words ("no rc").
case_rc_enabled_after_a_bare_start() {
  local answer
  if [[ "$(ask "add switch s2")" != *'"ok":true'* ]]; then
     fail "could not add the switch s2"
     return
  fi
  if ! start_and_wait s2; then
     fail "s2 could not be started (bare, without any rc)"
     return
  fi
  if ! journal_waits_for s2 "no rc"; then
     fail "bare start: the journal of s2 does not say it had no rc: $(journal_of s2)"
     return
  fi
  if ! stop_and_wait s2; then
     fail "s2 could not be stopped"
     return
  fi
  answer=$(ask "rc-set s2 --enable $RC_LATE")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "rc-set s2 --enable ${RC_LATE@Q}: refused: $answer"
     return
  fi
  if ! start_and_wait s2; then
     fail "s2 could not be started again"
     return
  fi
  if journal_waits_for s2 "$RC_LATE"; then
     pass "an rc enabled after a bare start is played: the journal of s2 shows ${RC_LATE@Q}"
  else
     fail "an rc enabled after a bare start is ignored: the journal of s2 still reads $(journal_of s2)"
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
ls -d /tmp/marionnet-*.dir 2>/dev/null | sort > "$tmpdir/rundirs-before"
echo "Bench: the rc of a switch is read at every start, not frozen at the first one — $BIN"

timeout -k 5 300 "$BIN" --control-socket "$sock" >/dev/null 2>"$tmpdir/stderr" &
pid=$!
for ((i = 0; i < 90; i++)); do [[ -S "$sock" ]] && break; sleep 1; done
if [[ ! -S "$sock" ]]; then
   echo "FAIL: no socket at $sock after 90s"
   exit 1
fi

if [[ "$(ask "new $tmpdir/bench.mar")" != *'"ok":true'* ]]; then
   echo "FAIL: could not create a project"
   exit 1
fi
if [[ "$(ask "add switch s1")" != *'"ok":true'* ]]; then
   echo "FAIL: could not add the reference switch"
   exit 1
fi

case_first_start_plays_its_rc
case_second_start_plays_the_new_rc
case_rc_enabled_after_a_bare_start

# Leave nothing running behind: the channel's `quit' does not power the network off.
ask "poweroff s1" >/dev/null
ask "poweroff s2" >/dev/null
ask quit >/dev/null
wait "$pid"; pid=""

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
