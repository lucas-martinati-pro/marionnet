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

# Bench: --control-socket refuses to start when the channel cannot be served.
# Work-stream marionnet-todo-transverse, episode 2.
#
# Two of the four cases need no X server at all: the path is checked when the option is read
# (bin/initialization.ml), before lablgtk initialises anything. The two others need a real
# startup, hence a DISPLAY; without one they are SKIPped, never faked.
#
# Deliberately no `set -e`: most cases here EXPECT a non-zero exit code, and every command
# whose status matters is tested explicitly. `set -u` and `pipefail` do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"
readonly SUN_PATH_USABLE_BYTES=107

declare -i passed=0 failed=0 skipped=0
# pid/sock/mrn_pid are global on purpose: an interrupted bench runs cleanup(), not the body of
# case_nominal, so what that case knows about its session has to be reachable from here.
declare tmpdir="" sock="" pid="" mrn_pid=""

# The pid captured by `pid=$!' is the pid of `timeout', not the one of the session: timeout
# relays the signals it can catch, and SIGKILL is not one of them, so a session "killed" through
# the proxy outlives its bench (measured at episode 27: 266 s, guest included). Two sources give
# the real one: the channel publishes it in `status' since episode 18 -- case_nominal reads it
# out of the answer it sends anyway -- and until then the single child of `timeout' IS it.
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
  [[ -n "$sock" ]] || return 0
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
  local d="$tmpdir"
  # Guard: never let an empty or short variable turn this into a wide removal.
  if [[ -n "$d" && "$d" == /tmp/marionnet-bench.* && -d "$d" ]]; then
     chmod -R u+w "$d" 2>/dev/null
     rm -rf -- "$d"
  fi
}
trap cleanup EXIT

pass() { echo "PASS: $*"; passed+=1; }
fail() { echo "FAIL: $*"; failed+=1; }
skip() { echo "SKIP: $*"; skipped+=1; }

# --- the two checks made before any window ------------------------------------------------

# Usage: expect_refusal <what> <expected substring on stderr> <socket path>
# Runs marionnet with the given --control-socket and expects: a non-zero status, the substring
# on stderr, and no socket left behind.
expect_refusal() {
  local what="$1" expected="$2" path="$3"
  local err="$tmpdir/stderr" rc
  # env -u DISPLAY on purpose: a refusal which needed an X server would not be a refusal
  # "before any window".
  env -u DISPLAY timeout -k 5 60 "$BIN" --control-socket "$path" >/dev/null 2>"$err"
  rc=$?
  if [[ $rc -eq 0 ]]; then
     fail "$what: marionnet started (exit 0) instead of refusing"
     return
  fi
  if [[ $rc -ge 124 ]]; then
     fail "$what: marionnet did not exit by itself (exit $rc, timed out)"
     return
  fi
  if ! grep -qF -- "$expected" "$err"; then
     fail "$what: exit $rc, but stderr does not mention '$expected':"
     sed 's/^/      | /' "$err" | tail -3
     return
  fi
  if [[ -e "$path" ]]; then
     fail "$what: refused (exit $rc) but left something at $path"
     return
  fi
  pass "$what (exit $rc, stderr names '$expected')"
}

case_too_long() {
  # 130 bytes > 107: the bound of sun_path, which the kernel does not truncate but rejects.
  local path
  printf -v path '/tmp/%0*d.sock' 120 0
  [[ ${#path} -gt $SUN_PATH_USABLE_BYTES ]] || { fail "too long: the bench built a short path"; return; }
  expect_refusal "a path of ${#path} bytes is refused" "$SUN_PATH_USABLE_BYTES" "$path"
}

case_relative() {
  expect_refusal "a relative path is refused" "absolute path is required" "relative.sock"
}

# --- the two cases which need a real startup (hence a DISPLAY) -----------------------------

case_unwritable_directory() {
  local dir="$tmpdir/unwritable" path
  mkdir -p "$dir" && chmod 0500 "$dir" || { fail "unwritable: cannot prepare $dir"; return; }
  path="$dir/marionnet.sock"
  local err="$tmpdir/stderr-late" rc
  timeout -k 5 120 "$BIN" --control-socket "$path" >/dev/null 2>"$err"
  rc=$?
  if [[ $rc -eq 0 ]]; then
     fail "an unwritable directory is refused: marionnet started (exit 0) instead of refusing"
  elif [[ $rc -ge 124 ]]; then
     fail "an unwritable directory is refused: marionnet did not exit by itself (exit $rc)"
  elif grep -qF -- "--control-socket" "$err"; then
     pass "an unwritable directory is refused (exit $rc, reason on stderr)"
  else
     fail "an unwritable directory is refused: exit $rc, but stderr says nothing about the channel"
     sed 's/^/      | /' "$err" | tail -3
  fi
}

case_nominal() {
  # Anti-false-positive: a refusal which refused everything would pass the three cases above.
  local path="$tmpdir/ok.sock" rc i answer
  sock="$path"
  timeout -k 5 120 "$BIN" --control-socket "$path" >/dev/null 2>"$tmpdir/stderr-ok" &
  pid=$!
  for ((i = 0; i < 90; i++)); do [[ -S "$path" ]] && break; sleep 1; done
  if [[ ! -S "$path" ]]; then
     fail "a serviceable path is served: no socket after 90s"
     kill_the_session "$(session_pid)"
     kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=""
     return
  fi
  answer=$(echo 'status' | timeout 10 socat - "UNIX-CONNECT:$path" 2>/dev/null)
  [[ "$answer" =~ \"pid\"[[:space:]]*:[[:space:]]*([0-9]+) ]] && mrn_pid="${BASH_REMATCH[1]}"
  echo 'quit' | timeout 10 socat - "UNIX-CONNECT:$path" >/dev/null 2>&1
  wait "$pid"; rc=$?
  pid=""
  mrn_pid=""
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "a serviceable path is served: the channel answered $answer"
  elif [[ $rc -ne 0 ]]; then
     fail "a serviceable path is served: the session answered, then exited $rc"
  else
     pass "a serviceable path is served, and the session exits 0 on quit"
  fi
}

# --- main -----------------------------------------------------------------------------------

if [[ ! -x "$BIN" ]]; then
   echo "SKIP: no executable at $BIN (build it first: dune build)"
   exit 77
fi

tmpdir=$(mktemp -d /tmp/marionnet-bench.XXXXXX) || exit 1
echo "Bench: --control-socket refusal — $BIN"

case_too_long
case_relative

if [[ -z "${DISPLAY:-}" ]]; then
   skip "an unwritable directory is refused (needs a DISPLAY: marionnet initialises Gtk+ at startup)"
   skip "a serviceable path is served (needs a DISPLAY)"
elif ! command -v socat >/dev/null; then
   case_unwritable_directory
   skip "a serviceable path is served (needs socat)"
else
   case_unwritable_directory
   case_nominal
fi

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
