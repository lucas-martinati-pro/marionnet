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

# Bench: `add <kind> <name> --ports=N' refuses exactly what `set <name> port_no N' refuses.
# Work-stream marionnet-todo-transverse, episode 4.
#
# Before the fix, `add' only checked N >= 0 and handed the value to the constructor: a machine
# with 0 or 99 ports and a nat_bridge with no port at all were accepted, while a switch with 0
# ports died on an assertion of gui/ledgrid.ml. The bounds belong to the kind (port_no_min /
# port_no_max, the very constants each user_level constructor is given), so `add' can — and now
# does — refuse before building anything.
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

declare -i passed=0 failed=0 skipped=0
declare tmpdir="" sock="" pid="" mrn_pid=""

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

# --- the cases ------------------------------------------------------------------------------

# Usage: case_out_of_bounds <what> <name> <expected fragment of the detail> <add arguments...>
# A refusal is worth nothing if it leaves the component behind, and worth little if it does not
# say why: both are checked.
case_out_of_bounds() {
  local what="$1" name="$2" expected="$3"; shift 3
  local answer
  answer=$(ask "add $*")
  if [[ "$answer" != *'"ok":false'* ]]; then
     fail "$what: accepted instead of being refused: $answer"
     return
  fi
  if network_has "$name"; then
     fail "$what: refused, but $name is still in the network"
     return
  fi
  if [[ "$answer" != *"$expected"* ]]; then
     fail "$what: refused, but the detail does not say why (expected ${expected@Q}): $answer"
     return
  fi
  pass "$what: refused, $name is not in the network, and the detail says why"
}

# Usage: case_accepted <what> <name> <expected number of ports> <add arguments...>
# Anti-false-positive: a fix which refused everything would pass every case above. The bounds
# are inclusive, so both ends must still build — and `get' must read the number back.
case_accepted() {
  local what="$1" name="$2" ports="$3"; shift 3
  local answer
  answer=$(ask "add $*")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "$what: refused instead of being accepted: $answer"
     return
  fi
  if ! network_has "$name"; then
     fail "$what: accepted, but $name is not in the network"
     return
  fi
  answer=$(ask "get $name port_no")
  if [[ "$answer" != *"\"port_no\":\"$ports\""* ]]; then
     fail "$what: built, but its number of ports is not $ports: $answer"
     return
  fi
  pass "$what: accepted with $ports port(s), read back by get"
}

# Non-regression: the cloud has a fixed number of ports, and --ports there is an argument we
# would drop. Its refusal predates this episode and must not have been swallowed by the new one.
case_cloud_refuses_ports() {
  local answer
  answer=$(ask "add cloud c0 --ports=2")
  if [[ "$answer" != *'"ok":false'* || "$answer" != *"fixed number of ports"* ]]; then
     fail "a cloud still refuses --ports altogether: $answer"
  elif network_has c0; then
     fail "a cloud still refuses --ports altogether: refused, but c0 is in the network"
  else
     pass "a cloud still refuses --ports altogether"
  fi
}

# The point of the episode: `add' refuses with the words of `set'. Same component, same value,
# same sentence — otherwise the two doors of the model disagree in front of the same client.
case_add_and_set_agree() {
  local from_add from_set
  from_add=$(ask "add machine m8 --ports=99")
  if [[ "$from_add" != *'"ok":false'* ]]; then
     fail "add and set refuse in the same words: add accepted 99 ports: $from_add"
     return
  fi
  if [[ "$(ask "add machine m8 --ports=8")" != *'"ok":true'* ]]; then
     fail "add and set refuse in the same words: could not build the reference machine"
     return
  fi
  from_set=$(ask "set m8 port_no 99")
  # "a machine cannot have more than 8 ports", built by the same helper on both sides.
  local sentence="a machine cannot have more than 8 ports"
  if [[ "$from_set" != *"$sentence"* ]]; then
     fail "add and set refuse in the same words: set does not say ${sentence@Q}: $from_set"
  elif [[ "$from_add" != *"$sentence"* ]]; then
     fail "add and set refuse in the same words: add does not say ${sentence@Q}: $from_add"
  else
     pass "add and set refuse too many ports in the same words"
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
echo "Bench: add --ports= respects the bounds of the kind — $BIN"

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

# Below the minimum (machine 1, hub 4, nat_bridge 1) and above the maximum (machine 8).
case_out_of_bounds "a machine with no port at all"  m0  "fewer than 1 port" machine m0 --ports=0
case_out_of_bounds "a machine with 99 ports"        m99 "more than 8 ports" machine m99 --ports=99
case_out_of_bounds "a hub with 3 ports"             h3  "fewer than 4 port" hub h3 --ports=3
case_out_of_bounds "a nat_bridge with no port"      n0  "fewer than 1 port" nat_bridge n0 --ports=0
# A negative number stays refused by the parser of the option itself (before the bounds).
case_out_of_bounds "a machine with -3 ports"        mneg "ports" machine mneg --ports=-3

# Both ends of a range are legal values.
case_accepted "a machine at its minimum" m1  1  machine m1 --ports=1
case_accepted "a machine at its maximum" m8b 8  machine m8b --ports=8
case_accepted "a router at its maximum"  r16 16 router r16 --ports=16
case_accepted "a hub with its default"   hd  4  hub hd

case_cloud_refuses_ports
case_add_and_set_agree

ask quit >/dev/null
wait "$pid"; pid=""; mrn_pid=""

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
