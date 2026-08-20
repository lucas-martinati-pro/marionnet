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

# Bench: `set <n> variant <epithet>' and `add ... --variant=<epithet>' refuse a variant which is
# not installed for the component's filesystem. Work-stream marionnet-todo-transverse, episode 7.
#
# Before the fix both answered ok:true and changed nothing: the write goes through
# remap_absent_variant_at_import (user_level.ml), a method written for *loading a .mar* -- a
# variant which disappeared with its filesystem must not make the project unloadable, the
# component simply boots the pristine filesystem. Applied to an explicit write it turned a typo
# into a polite no-op, one attribute away from the `distrib' defect of episode 5.
#
# Two sessions, because a variant must EXIST to prove the nominal cases and the cross guard, and
# the list of installed filesystems is only known once a session runs. The bench therefore drives
# the binary with HOME pointing inside its own temporary directory, and fabricates a variant there
# ($HOME/.marionnet/filesystems/machine-<epithet>_variants/<name>, an empty file: disk.ml reads
# every non-directory of those directories, and the user directory IS in the searching list).
# Nothing is written outside the temporary directory, and the host's own variants are invisible
# to the run, which is what makes the bench deterministic.
#
# Deliberately no `set -e': several commands here EXPECT a non-zero answer, and every status
# that matters is tested explicitly. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

# An epithet no installation can hold, and the one this bench fabricates.
readonly ABSENT="pas-une-variante"
readonly FABRICATED="bench-variant"
# The word the model reads as "no variant at all" (machine.ml). The empty string does too, but it
# cannot travel through the channel: a request is split on spaces and empty tokens are dropped.
readonly NO_VARIANT="aucune"

declare -i passed=0 failed=0 skipped=0
declare tmpdir="" sock="" pid="" fakehome=""

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
ask() { echo "$1" | timeout 20 socat - "UNIX-CONNECT:$sock" 2>/dev/null; }

# `ls' answers {"ok":true,"count":N,"nodes":[{"name":"m0",...}]}: a name is present iff the
# exact string "name":"<n>" is.
network_has() { [[ "$(ask ls)" == *"\"name\":\"$1\""* ]]; }

# A field of a component, read from the model rather than assumed.
field_of() {
  local answer; answer=$(ask "get $1 $2")
  [[ "$answer" =~ \"$2\":\"([^\"]*)\" ]] && echo "${BASH_REMATCH[1]}"
}

# The installed filesystems, taken from a refusal of the episode-5 guard: it names what it would
# accept, so the bench needs no second source of truth (nor a path to the installation).
installed_from() {
  local detail="$1"
  [[ "$detail" =~ installed\ filesystems:\ ([^\"]*)\.\ The\ GUI ]] || return 1
  echo "${BASH_REMATCH[1]//, /$'\n'}"
}

# A session of its own: the second one must see the variant fabricated between the two.
start_session() {
  timeout -k 5 180 env HOME="$fakehome" "$BIN" --control-socket "$sock" \
     >/dev/null 2>>"$tmpdir/stderr" &
  pid=$!
  local i
  for ((i = 0; i < 90; i++)); do [[ -S "$sock" ]] && break; sleep 1; done
  [[ -S "$sock" ]] || { echo "FAIL: no socket at $sock after 90s"; exit 1; }
  [[ "$(ask "new $tmpdir/bench-$1.mar")" == *'"ok":true'* ]] || {
     echo "FAIL: could not create a project"; exit 1; }
  [[ "$(ask "add machine m1")" == *'"ok":true'* ]] || {
     echo "FAIL: could not add the reference machine"; exit 1; }
}

stop_session() {
  ask quit >/dev/null
  wait "$pid" 2>/dev/null
  pid=""
  rm -f -- "$sock"
}

# --- the cases ------------------------------------------------------------------------------

# The point of the episode, on `set': refused, said why, and above all *nothing written*.
case_set_refuses_absent() {
  local before after answer
  before=$(field_of m1 variant)
  answer=$(ask "set m1 variant $ABSENT")
  if [[ "$answer" != *'"ok":false'* ]]; then
     fail "set m1 variant $ABSENT: accepted instead of being refused: $answer"
     return
  fi
  if [[ "$answer" != *"$ABSENT"* ]]; then
     fail "set m1 variant $ABSENT: refused, but the detail does not name the value: $answer"
     return
  fi
  after=$(field_of m1 variant)
  if [[ "$after" != "$before" ]]; then
     fail "set m1 variant $ABSENT: refused, but the variant moved from ${before@Q} to ${after@Q}"
     return
  fi
  pass "set m1 variant $ABSENT: refused, names the value, and m1 still carries ${before@Q}"
}

# Same guard on the other door, where the rollback of episode 3 must leave nothing behind.
case_add_refuses_absent() {
  local answer
  answer=$(ask "add machine m2 --variant=$ABSENT")
  if [[ "$answer" != *'"ok":false'* ]]; then
     fail "add machine m2 --variant=$ABSENT: accepted instead of being refused: $answer"
     return
  fi
  if network_has m2; then
     fail "add machine m2 --variant=$ABSENT: refused, but m2 is still in the network"
     return
  fi
  pass "add machine m2 --variant=$ABSENT: refused, and m2 is not in the network"
}

# A router has its own installation set: the guard must read *its* filesystem, not a machine's.
case_router_refuses_absent() {
  local answer
  answer=$(ask "add router r2 --variant=$ABSENT")
  if [[ "$answer" != *'"ok":false'* ]]; then
     fail "add router r2 --variant=$ABSENT: accepted instead of being refused: $answer"
  elif network_has r2; then
     fail "add router r2 --variant=$ABSENT: refused, but r2 is still in the network"
  else
     pass "add router r2 --variant=$ABSENT: refused too (a router has its own filesystems)"
  fi
}

# Anti-false-positive #1: a guard which refused everything would pass every case above. Removing
# the variant must still be accepted -- it is the only way the channel has to express it.
case_no_variant_accepted() {
  local answer
  answer=$(ask "set m1 variant $NO_VARIANT")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "set m1 variant $NO_VARIANT (no variant at all): refused: $answer"
  else
     pass "set m1 variant $NO_VARIANT (no variant at all): still accepted"
  fi
}

# Anti-false-positive #2, and the whole point of fabricating one: a variant which EXISTS for the
# component's filesystem goes through, and is written.
case_existing_variant_accepted() {
  local answer
  answer=$(ask "set m1 variant $FABRICATED")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "set m1 variant $FABRICATED: refused although it is installed for $(field_of m1 distrib): $answer"
     return
  fi
  if [[ "$(field_of m1 variant)" != "$FABRICATED" ]]; then
     fail "set m1 variant $FABRICATED: accepted, but the model reads $(field_of m1 variant)"
     return
  fi
  pass "set m1 variant $FABRICATED: accepted and written (the guard lets a real variant through)"
}

# The cross guard decided for this episode: changing the filesystem is REFUSED while the component
# carries a variant the new one does not have -- rather than dropping the variant in silence,
# which is the very defect being closed. Needs a second filesystem for machines; skipped, never
# faked, when this host has only one.
case_distrib_change_refused_then_allowed() {
  local current other answer before d
  current=$(field_of m1 distrib)
  answer=$(ask "set m1 distrib pas-une-distrib")
  while read -r d; do
     [[ -n "$d" && "$d" != "$current" ]] && { other="$d"; break; }
  done < <(installed_from "$answer")
  if [[ -z "${other:-}" ]]; then
     skip "the cross guard (a distrib change losing the variant): only one filesystem is installed here (${current@Q})"
     return
  fi
  before=$(field_of m1 variant)
  if [[ "$before" != "$FABRICATED" ]]; then
     fail "the cross guard: m1 should still carry $FABRICATED, it carries ${before@Q}"
     return
  fi
  answer=$(ask "set m1 distrib $other")
  if [[ "$answer" != *'"ok":false'* ]]; then
     fail "set m1 distrib ${other@Q} while carrying $FABRICATED: accepted instead of being refused: $answer"
     return
  fi
  if [[ "$(field_of m1 distrib)" != "$current" ]]; then
     fail "set m1 distrib ${other@Q}: refused, but the filesystem moved anyway"
     return
  fi
  if [[ "$answer" != *"$NO_VARIANT"* ]]; then
     fail "set m1 distrib ${other@Q}: refused, but the detail does not say how to get out of it: $answer"
     return
  fi
  pass "set m1 distrib ${other@Q}: refused while m1 carries $FABRICATED, and says to remove it first"
  # And the way out the message names must work.
  [[ "$(ask "set m1 variant $NO_VARIANT")" == *'"ok":true'* ]] || {
     fail "the way out: set m1 variant $NO_VARIANT was refused"; return; }
  answer=$(ask "set m1 distrib $other")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "set m1 distrib ${other@Q} once the variant is removed: still refused: $answer"
  else
     pass "set m1 distrib ${other@Q} once the variant is removed: accepted (the way out works)"
  fi
}

# Non-regression: the two guards of episodes 4f (pilotage-par-script) and 5 share both call sites
# with the new one, and the "distrib" branch had to be rewritten to hold two refusals.
case_neighbour_guards_intact() {
  local answer
  answer=$(ask "set m1 kernel pas-un-noyau")
  if [[ "$answer" != *'"ok":false'* || "$answer" != *"supported kernels:"* ]]; then
     fail "the kernel guard still refuses an unsupported kernel: $answer"
  else
     pass "the kernel guard still refuses an unsupported kernel"
  fi
  answer=$(ask "set m1 distrib pas-une-distrib")
  if [[ "$answer" != *'"ok":false'* || "$answer" != *"installed filesystems:"* ]]; then
     fail "the distrib guard still refuses a filesystem which is not installed: $answer"
  else
     pass "the distrib guard still refuses a filesystem which is not installed"
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
echo "Bench: a variant which is not installed is refused, not dropped — $BIN"

# --- first session: the refusals, and what the second one needs to know
start_session 1
case_set_refuses_absent
case_add_refuses_absent
case_router_refuses_absent
case_no_variant_accepted
case_neighbour_guards_intact
declare distrib_of_m1; distrib_of_m1=$(field_of m1 distrib)
stop_session

# --- fabricate a variant for that filesystem, inside the run's own HOME
if [[ -z "$distrib_of_m1" ]]; then
   skip "fabricating a variant: could not read the filesystem of m1"
else
   mkdir -p "$fakehome/.marionnet/filesystems/machine-${distrib_of_m1}_variants"
   : > "$fakehome/.marionnet/filesystems/machine-${distrib_of_m1}_variants/$FABRICATED"
   # --- second session: the nominal case and the cross guard
   start_session 2
   case_existing_variant_accepted
   case_distrib_change_refused_then_allowed
   stop_session
fi

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
