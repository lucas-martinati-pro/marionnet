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

# Bench: an `add' refused by its own constructor leaves the network unchanged.
# Work-stream marionnet-todo-transverse, episode 3.
#
# A node registers itself with the network inside its constructor (user_level.ml), before the
# part which may raise: `add switch s0 --ports=0' answers ok:false — and used to leave "s0" in
# `ls', in the saved .mar, and its name taken. The cases below play a real driven session,
# hence they need a DISPLAY and socat; without either, everything is SKIPped, never faked.
#
# Episode 4 moved the port bounds *before* the construction, so the two --ports cases below no
# longer reach the constructor at all: they now check the same invariant one guard earlier, which
# is why a third case was added — an invalid name is what still makes a constructor raise
# through `add' (check_name, user_level.ml:521), hence the one which really exercises the
# rollback this bench was written for.
#
# Deliberately no `set -e': several commands here EXPECT a non-zero answer, and every status
# that matters is tested explicitly. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

declare -i passed=0 failed=0 skipped=0
declare tmpdir="" sock="" pid=""

# The `quit' of the channel does not close the project, so a session which opened one leaves
# its /tmp/marionnet-<n>.dir/ behind. Remove the ones THIS run created — never a whole glob:
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
ask() { echo "$1" | timeout 20 socat - "UNIX-CONNECT:$sock" 2>/dev/null; }

# `ls' answers {"ok":true,"count":N,"nodes":[{"name":"s0",...}]}: a name is present iff the
# exact string "name":"<n>" is.
network_has() { [[ "$(ask ls)" == *"\"name\":\"$1\""* ]]; }

# --- the cases ------------------------------------------------------------------------------

# Usage: case_refused_add_leaves_nothing <what> <name> <add arguments...>
case_refused_add_leaves_nothing() {
  local what="$1" name="$2"; shift 2
  local answer
  answer=$(ask "add $*")
  if [[ "$answer" != *'"ok":false'* ]]; then
     fail "$what: add was accepted instead of being refused: $answer"
     return
  fi
  if network_has "$name"; then
     fail "$what: refused, but $name is still in the network"
     return
  fi
  pass "$what: refused, and $name is not in the network"
}

# The strongest form of "unchanged": the refused name is free again.
case_refused_name_is_free() {
  local answer
  answer=$(ask "add switch s0")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "the name of a refused add is free again: $answer"
  elif ! network_has s0; then
     fail "the name of a refused add is free again: add answered ok:true but s0 is not in the network"
  else
     pass "the name of a refused add is free again (s0 rebuilt with its default ports)"
  fi
}

# Anti-false-positive: a rollback which destroyed everything would pass the cases above.
case_nominal() {
  local answer
  answer=$(ask "add hub h1 --ports=8")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "a legitimate add still works: $answer"
  elif ! network_has h1; then
     fail "a legitimate add still works: h1 was accepted but is not in the network"
  else
     pass "a legitimate add still works (h1 is in the network)"
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
echo "Bench: an add refused by its constructor leaves nothing — $BIN"

timeout -k 5 180 "$BIN" --control-socket "$sock" >/dev/null 2>"$tmpdir/stderr" &
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

# Both natures used to die in the same assertion (gui/ledgrid.ml), from both ends of the range;
# since episode 4 the bounds of the kind refuse them before the constructor is even called.
case_refused_add_leaves_nothing "a switch with no port at all" s0 "switch s0 --ports=0"
case_refused_add_leaves_nothing "a world_gateway with 99 ports" g99 "world_gateway g99 --ports=99"
# The constructor itself: an invalid name is refused by check_name (user_level.ml:521) *after*
# the node has registered itself with the network. This is the case the rollback exists for.
case_refused_add_leaves_nothing "a machine with an invalid name" "m-1" "machine m-1"
case_refused_name_is_free
case_nominal

ask quit >/dev/null
wait "$pid"; pid=""

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
