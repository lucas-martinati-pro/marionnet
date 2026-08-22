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

# Bench: an import warning is born of an import only. Work-stream marionnet-todo-transverse,
# episode 17.
#
# Before the fix, `set r1 variant aucune' on a ROUTER went through
# remap_absent_variant_at_import (user_level.ml), a method written for *loading a .mar*: a
# machine has a dedicated branch for that word (machine.ml, backward-compatibility with `v0),
# a router had none. The remap then did what it exists for -- drop the variant and record an
# import warning -- outside of any import. Those warnings are not thrown away: they pile up in
# network#add_import_warning and are read at the END OF THE NEXT PROJECT LOADING
# (state#open_project_async), which presents them as adaptations of THAT project. Measured:
# opening a project needing no adaptation at all answered with a "recap" notification titled
# "1 automatic adjustment(s) were applied".
#
# The bench therefore asks two independent questions, and the second is the defect itself:
#   1. does an explicit write journal an "import remapping:" line?          (cases 1 and 2)
#   2. does the next loading of a pristine project show a recapitulation?   (case 3)
# Cases 4 and 5 are the anti-false-positives: a project which REALLY needs an adaptation must
# still get its recapitulation (otherwise "no recap ever" would pass everything), and the list
# must not survive its own display.
#
# Neither a guest nor a privilege is needed -- no component is ever started -- which is what
# makes this bench versioned rather than throwaway (README.md of this directory, and
# docs/todo-transverse.md section 3.6).
#
# Deliberately no `set -e': several commands here EXPECT a non-zero answer, and every status
# that matters is tested explicitly. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

# The word the model reads as "no variant at all". The empty string does too, but it cannot
# travel through the channel: a request is split on spaces and empty tokens are dropped.
readonly NO_VARIANT="aucune"
# An epithet of the broken 3.2.x "-ghost" series: remap_obsolete_kernel_at_import remaps it to
# something bootable AND records an import warning. This is what case 4 needs.
readonly OBSOLETE_KERNEL="3.2.64-ghost"

declare -i passed=0 failed=0 skipped=0
declare tmpdir="" sock="" pid="" fakehome="" journal="" mrn_pid=""

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

# One request, one line of JSON back. The -t/-T are not cosmetic: without them socat drops any
# answer slower than half a second, and `open' loads a whole project (episode 10 of this
# work-stream paid for that lesson).
ask() { echo "$1" | timeout 120 socat -t 60 -T 90 - "UNIX-CONNECT:$sock" 2>/dev/null; }

# The journal is read by DELTA: only what the session wrote since the mark. The two prefixes
# below are written by add_import_warning_and_log (user_level.ml) and are NOT translated -- the
# summary which follows them is, so the bench matches the prefixes alone. BOTH are matched on
# purpose: the second one ("outside any import") means the warning was not queued, which is
# half of the episode, but a remap which happens on an explicit write is still a remap, and
# that is the other half.
readonly REMAPPING_RE="import remapping:|remapping outside any import"
journal_mark() { wc -c < "$journal"; }
journal_since() { tail -c "+$(($1 + 1))" "$journal"; }
remapping_lines_since() { journal_since "$1" | grep -c -E "$REMAPPING_RE"; }

# --- the cases ------------------------------------------------------------------------------

# The symptom of the entry, on the component which had no branch for the word.
case_router_aucune_is_not_an_import() {
  local mark answer n
  mark=$(journal_mark)
  answer=$(ask "set r1 variant $NO_VARIANT")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "set r1 variant $NO_VARIANT: refused, although it is the only way to remove a variant: $answer"
     return
  fi
  n=$(remapping_lines_since "$mark")
  if [[ "$n" -ne 0 ]]; then
     fail "set r1 variant $NO_VARIANT: accepted, but journalled $n import remapping line(s):"
     journal_since "$mark" | grep -E "$REMAPPING_RE" | sed 's/^/      /'
     return
  fi
  pass "set r1 variant $NO_VARIANT (router): accepted, and no import remapping journalled"
}

# The witness: a machine has had the dedicated branch since `v0 and never wrote anything. If
# this one ever failed, the defect would be elsewhere than where the entry says.
case_machine_aucune_is_the_witness() {
  local mark answer n
  mark=$(journal_mark)
  answer=$(ask "set m1 variant $NO_VARIANT")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "set m1 variant $NO_VARIANT: refused: $answer"
     return
  fi
  n=$(remapping_lines_since "$mark")
  if [[ "$n" -ne 0 ]]; then
     fail "set m1 variant $NO_VARIANT (machine, the witness): journalled $n import remapping line(s)"
     return
  fi
  pass "set m1 variant $NO_VARIANT (machine): still writes nothing (the witness holds)"
}

# THE defect: the warnings above are read at the end of the next loading and shown as if they
# came from it. A project which needs no adaptation must open without a recapitulation.
case_no_recap_on_a_pristine_project() {
  local answer
  answer=$(ask "open $tmpdir/victim.mar")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "open victim.mar: failed: $answer"
     return
  fi
  if [[ "$answer" == *'"kind":"recap"'* ]]; then
     fail "open victim.mar (nothing to adapt): a recapitulation was shown, carrying what an
      earlier explicit write had queued: $answer"
     return
  fi
  pass "open victim.mar (nothing to adapt): no recapitulation"
}

# Anti-false-positive, and the guarantee that half 2 did not kill the feature: a project which
# really names an obsolete kernel is still adapted, still says so, and still journals the line
# the two first cases required to be absent.
case_recap_still_shown_for_a_real_adaptation() {
  local mark answer n
  if [[ ! -r "$tmpdir/remapped.mar" ]]; then
     skip "a real adaptation: could not fabricate remapped.mar (see above)"
     return
  fi
  mark=$(journal_mark)
  answer=$(ask "open $tmpdir/remapped.mar")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "open remapped.mar: failed: $answer"
     return
  fi
  if [[ "$answer" != *'"kind":"recap"'* ]]; then
     fail "open remapped.mar (kernel $OBSOLETE_KERNEL): NO recapitulation -- an import warning
      no longer reaches the user: $answer"
     return
  fi
  n=$(remapping_lines_since "$mark")
  if [[ "$n" -lt 1 ]]; then
     fail "open remapped.mar: recapitulation shown, but nothing journalled (grep out of order?)"
     return
  fi
  pass "open remapped.mar (kernel $OBSOLETE_KERNEL): adapted, journalled, and recapitulated"
}

# The list is read AND reset by the loading which displays it: reopening the pristine project
# right after must be silent again. Guards the queue against leaking from one loading to the next.
case_the_list_does_not_survive_its_display() {
  local answer
  answer=$(ask "open $tmpdir/victim.mar")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "open victim.mar (second time): failed: $answer"
     return
  fi
  if [[ "$answer" == *'"kind":"recap"'* ]]; then
     fail "open victim.mar right after an adapted project: the recapitulation came back: $answer"
     return
  fi
  pass "open victim.mar right after an adapted project: silent again (the list was reset)"
}

# --- fabrication ----------------------------------------------------------------------------

# A copy of victim.mar whose machine names an obsolete kernel. The archive is a gzipped tar
# (state.ml: "tar -xSvzf") holding one directory, and since `v3 the network is JSON, one
# attribute per [ "key", "value" ] pair -- so the rewrite is a one-line sed on a known shape,
# and the bench SKIPS (never fakes) if that shape is not the one it finds.
fabricate_remapped_project() {
  local unpack="$tmpdir/unpack" json
  mkdir -p "$unpack" || return 1
  tar -xzf "$tmpdir/victim.mar" -C "$unpack" 2>/dev/null || return 1
  json=$(find "$unpack" -path '*/netmodel/network.json' -print -quit)
  [[ -n "$json" ]] || return 1
  grep -q '\[ "kernel", "' "$json" || return 1
  sed -i -E 's/\[ "kernel", "[^"]*" \]/[ "kernel", "'"$OBSOLETE_KERNEL"'" ]/' "$json" || return 1
  # Repacked from the same level, keeping the internal root directory: the project root
  # basename lives inside the archive, not in the file name.
  ( cd "$unpack" && tar -czf "$tmpdir/remapped.mar" ./* ) || return 1
  return 0
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
journal="$tmpdir/journal"
fakehome="$tmpdir/home"
mkdir -p "$fakehome"
ls -d /tmp/marionnet-*.dir 2>/dev/null | sort > "$tmpdir/rundirs-before"
echo "Bench: an import warning is born of an import only — $BIN"

# --debug is what makes Log.printf write: the first two cases read the journal.
# HOME points inside the temporary directory: nothing of the user's own installation takes part,
# and nothing is written outside.
timeout -k 5 300 env HOME="$fakehome" "$BIN" --debug --control-socket "$sock" \
   >/dev/null 2>"$journal" &
pid=$!
for ((i = 0; i < 90; i++)); do [[ -S "$sock" ]] && break; sleep 1; done
[[ -S "$sock" ]] || { echo "FAIL: no socket at $sock after 90s"; exit 1; }
mrn_pid=$(session_pid_from_channel)

# The project the bench will open twice: it needs no adaptation whatsoever.
[[ "$(ask "new $tmpdir/victim.mar")" == *'"ok":true'* ]] || {
   echo "FAIL: could not create the pristine project"; exit 1; }
[[ "$(ask "add machine m0")" == *'"ok":true'* ]] || {
   echo "FAIL: could not add a machine to the pristine project"; exit 1; }
[[ "$(ask save)" == *'"ok":true'* ]] || { echo "FAIL: could not save the pristine project"; exit 1; }

if ! fabricate_remapped_project; then
   skip "fabricating remapped.mar: the archive or the network.json is not the expected shape"
fi

# A second project, where the explicit writes happen.
[[ "$(ask "new $tmpdir/work.mar")" == *'"ok":true'* ]] || {
   echo "FAIL: could not create the working project"; exit 1; }
if [[ "$(ask "add router r1")" != *'"ok":true'* ]]; then
   echo "SKIP: no router could be added (no filesystem installed for routers here?)"
   exit 77
fi
[[ "$(ask "add machine m1")" == *'"ok":true'* ]] || {
   echo "FAIL: could not add the witness machine"; exit 1; }

case_router_aucune_is_not_an_import
case_machine_aucune_is_the_witness

# Saved before leaving it: an unsaved project on the way out is a question the GUI would ask.
[[ "$(ask save)" == *'"ok":true'* ]] || { echo "FAIL: could not save the working project"; exit 1; }

case_no_recap_on_a_pristine_project
case_recap_still_shown_for_a_real_adaptation
case_the_list_does_not_survive_its_display

ask quit >/dev/null
wait "$pid" 2>/dev/null
pid=""
mrn_pid=""

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
