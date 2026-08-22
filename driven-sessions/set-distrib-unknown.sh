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

# Bench: `set <n> distrib <epithet>' and `add ... --distrib=<epithet>' refuse a filesystem which
# is not installed here. Work-stream marionnet-todo-transverse, episode 5.
#
# Before the fix both answered ok:true and changed nothing: the write goes through
# remap_absent_distrib_at_import (user_level.ml), a method written for *loading a .mar* -- where
# silently switching to a neighbour of the same family beats refusing to open the project.
# Applied to an explicit write it turned a typo into a polite no-op.
#
# The cases below play a real driven session, hence they need a DISPLAY and socat; without either,
# everything is SKIPped, never faked.
#
# Deliberately no `set -e': several commands here EXPECT a non-zero answer, and every status
# that matters is tested explicitly. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

# An epithet no installation can hold: the character set of a filesystem epithet excludes it.
readonly ABSENT="pas-une-distrib"

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
ask() { echo "$1" | timeout 20 socat - "UNIX-CONNECT:$sock" 2>/dev/null; }

# `ls' answers {"ok":true,"count":N,"nodes":[{"name":"m0",...}]}: a name is present iff the
# exact string "name":"<n>" is.
network_has() { [[ "$(ask ls)" == *"\"name\":\"$1\""* ]]; }

# The filesystem a component currently boots, read from the model rather than assumed.
distrib_of() {
  local answer; answer=$(ask "get $1 distrib")
  [[ "$answer" =~ \"distrib\":\"([^\"]*)\" ]] && echo "${BASH_REMATCH[1]}"
}

# The installed filesystems, taken from the refusal itself: the guard names what it would accept,
# so the bench does not need a second source of truth (nor a path to the installation).
installed_from() {
  local detail="$1"
  [[ "$detail" =~ installed\ filesystems:\ ([^\"]*)\.\ The\ GUI ]] || return 1
  local list="${BASH_REMATCH[1]}"
  echo "${list//, /$'\n'}"
}

# --- the cases ------------------------------------------------------------------------------

# The point of the episode, on `set': refused, said why, and above all *nothing written*.
case_set_refuses_absent() {
  local before after answer
  before=$(distrib_of m1)
  answer=$(ask "set m1 distrib $ABSENT")
  if [[ "$answer" != *'"ok":false'* ]]; then
     fail "set m1 distrib $ABSENT: accepted instead of being refused: $answer"
     return
  fi
  if [[ "$answer" != *"$ABSENT"* || "$answer" != *"installed filesystems:"* ]]; then
     fail "set m1 distrib $ABSENT: refused, but the detail neither names the value nor the installed filesystems: $answer"
     return
  fi
  after=$(distrib_of m1)
  if [[ "$after" != "$before" ]]; then
     fail "set m1 distrib $ABSENT: refused, but the filesystem moved from ${before@Q} to ${after@Q}"
     return
  fi
  pass "set m1 distrib $ABSENT: refused, names the installed filesystems, and m1 still boots ${before@Q}"
}

# Same guard on the other door, where the rollback of episode 3 must leave nothing behind.
case_add_refuses_absent() {
  local answer
  answer=$(ask "add machine m2 --distrib=$ABSENT")
  if [[ "$answer" != *'"ok":false'* ]]; then
     fail "add machine m2 --distrib=$ABSENT: accepted instead of being refused: $answer"
     return
  fi
  if network_has m2; then
     fail "add machine m2 --distrib=$ABSENT: refused, but m2 is still in the network"
     return
  fi
  if [[ "$answer" != *"installed filesystems:"* ]]; then
     fail "add machine m2 --distrib=$ABSENT: refused, but the detail does not say why: $answer"
     return
  fi
  pass "add machine m2 --distrib=$ABSENT: refused, m2 is not in the network, and the detail says why"
}

# A router has its own installation set: the guard must read *its* list, not a machine's.
case_router_refuses_absent() {
  local answer
  answer=$(ask "add router r2 --distrib=$ABSENT")
  if [[ "$answer" != *'"ok":false'* ]]; then
     fail "add router r2 --distrib=$ABSENT: accepted instead of being refused: $answer"
  elif network_has r2; then
     fail "add router r2 --distrib=$ABSENT: refused, but r2 is still in the network"
  else
     pass "add router r2 --distrib=$ABSENT: refused too (a router has its own filesystems)"
  fi
}

# Anti-false-positive: a guard which refused everything would pass every case above. Writing the
# filesystem the component already boots must still be accepted.
case_current_distrib_accepted() {
  local current answer
  current=$(distrib_of m1)
  if [[ -z "$current" ]]; then
     fail "set m1 distrib <its own filesystem>: could not read it back"
     return
  fi
  answer=$(ask "set m1 distrib $current")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "set m1 distrib ${current@Q} (its own filesystem): refused: $answer"
  else
     pass "set m1 distrib ${current@Q} (its own filesystem): still accepted"
  fi
}

# The real move, when this host has more than one filesystem for machines. Skipped, never faked,
# when it has only one -- the guard is then proven by the three cases above.
case_real_switch() {
  local current other answer
  current=$(distrib_of m1)
  answer=$(ask "set m1 distrib $ABSENT")
  while read -r d; do
     [[ -n "$d" && "$d" != "$current" ]] && { other="$d"; break; }
  done < <(installed_from "$answer")
  if [[ -z "${other:-}" ]]; then
     skip "switching to another filesystem: only one is installed here (${current@Q})"
     return
  fi
  answer=$(ask "set m1 distrib $other")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "set m1 distrib ${other@Q}: refused although it is installed: $answer"
     return
  fi
  if [[ "$(distrib_of m1)" != "$other" ]]; then
     fail "set m1 distrib ${other@Q}: accepted, but the model still reads $(distrib_of m1)"
     return
  fi
  pass "set m1 distrib ${other@Q}: accepted and written (the guard lets a real switch through)"
}

# Non-regression: the kernel guard of episode 4f (pilotage-par-script) shares both call sites
# with the new one, which had to be rewritten as a match. It must still refuse.
case_kernel_guard_intact() {
  local answer
  answer=$(ask "set m1 kernel pas-un-noyau")
  if [[ "$answer" != *'"ok":false'* || "$answer" != *"supported kernels:"* ]]; then
     fail "the kernel guard still refuses an unsupported kernel: $answer"
  else
     pass "the kernel guard still refuses an unsupported kernel"
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
ls -d /tmp/marionnet-*.dir 2>/dev/null | sort > "$tmpdir/rundirs-before"
echo "Bench: a filesystem which is not installed is refused, not remapped — $BIN"

timeout -k 5 180 "$BIN" --control-socket "$sock" >/dev/null 2>"$tmpdir/stderr" &
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
if [[ "$(ask "add machine m1")" != *'"ok":true'* ]]; then
   echo "FAIL: could not add the reference machine"
   exit 1
fi

case_set_refuses_absent
case_add_refuses_absent
case_router_refuses_absent
case_current_distrib_accepted
case_kernel_guard_intact
# Last: it is the only case which actually moves m1 to another filesystem.
case_real_switch

ask quit >/dev/null
wait "$pid"; pid=""; mrn_pid=""

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
