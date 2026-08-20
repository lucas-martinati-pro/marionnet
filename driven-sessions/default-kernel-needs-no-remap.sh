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

# Bench: a component created here and now already holds a kernel this host can run, so saving the
# project and loading it back changes nothing. Work-stream marionnet-todo-transverse, episode 12.
#
# The property is a FIXED POINT, and it is deliberately expressed that way: this script holds no
# rule of its own about which kernel is usable (no version comparison, no "-i386" preference, no
# reading of SUPPORTED_KERNELS). It asks Marionnet itself, twice, and compares:
#
#   - what the constructor chose when the component was created, and
#   - what remap_obsolete_kernel_at_import (user_level.ml) makes of it when the project is loaded
#     again -- the method whose whole job is to replace a kernel that cannot run here.
#
# If the two disagree, the second one says so in as many words, in the notifications carried by
# the answer to `open': `router "r1": kernel "3.2.64-ghost" -> "6.12.95-i386"'. That was the
# symptom recorded in docs/TODO.md on 2026-08-09: a router born unbootable, repaired only by a
# save-and-reopen cycle. It was fixed on 2026-08-13 by 79c25dd (kernels are now ordered from the
# most recent to the oldest, so the head of `supported_kernels_of' is usable), and this bench is
# what keeps it fixed: restore the lexicographic order (remove the `~ordering:' line of
# bin/disk.ml) and the first two cases fail again, saying why.
#
# Two cases beyond the nominal one:
#   - a .mar carrying NO `kernel' attribute at all (the second half of the TODO entry: projects
#     older than the router's kernel attribute), where the constructor's default is what the
#     loaded component gets, with no remap in the way;
#   - a .mar carrying a kernel that IS unusable here, which MUST still be remapped and reported --
#     without it, a broken notification mechanism would make every other case pass for nothing.
#
# No guest boots and no privilege is needed: components are created and read, never started.
#
# Deliberately no `set -e': several commands here EXPECT a non-zero answer, and every status
# that matters is tested explicitly. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

# A kernel of the 2.6.x/3.2.x "-ghost" series, whose SKAS0 stub segfaults on hosts >= 5.15. Used
# only by the counter-case, and only if the guard below shows that this host still installs it.
readonly OLD_KERNEL="3.2.64-ghost"

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

stop_session() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
     ask quit >/dev/null
     wait "$pid" 2>/dev/null
  fi
  pid=""
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

# One request, one line of JSON back. The two timeouts are not decoration: without -t/-T socat
# closes the connection half a second after sending, and every answer slower than that comes back
# EMPTY, with no error at all (measured at episodes 10 and 11).
ask() { echo "$1" | timeout 30 socat -t 30 -T 30 - "UNIX-CONNECT:$sock" 2>/dev/null; }

# Start a session on the socket, and wait for the socket to appear.
start_session() {
  timeout -k 5 240 "$BIN" --control-socket "$sock" >>"$tmpdir/stdout" 2>>"$tmpdir/stderr" &
  pid=$!
  local i
  for ((i = 0; i < 90; i++)); do [[ -S "$sock" ]] && return 0; sleep 1; done
  return 1
}

# The kernel a component currently holds, read from the model rather than assumed.
kernel_of() {
  local answer; answer=$(ask "get $1 kernel")
  [[ "$answer" =~ \"kernel\":\"([^\"]*)\" ]] && echo "${BASH_REMATCH[1]}"
}

# The filesystems installed for a given kind, taken from the refusal itself: the guard of episode
# 5 names what it would accept, so the bench needs no second source of truth (nor a path to the
# installation). A router and a machine do not share their list.
installed_distribs_of_kind() {
  local kind="$1" answer list
  answer=$(ask "add $kind probedistribs --distrib=pas-une-distrib")
  [[ "$answer" =~ installed\ filesystems:\ ([^\"]*)\.\ The\ GUI ]] || return 1
  list="${BASH_REMATCH[1]}"
  echo "${list//, /$'\n'}"
}

# The kernel adjustments Marionnet reports in the answer to `open' (an import warning of the
# recapitulative dialog). One line per adjustment, empty when there is none.
kernel_adjustments_in() {
  echo "$1" | jq -r '[.notifications[]?.items[]? | select(.summary | test("kernel"))
                      | .summary] | .[]' 2>/dev/null
}

# --- the cases ------------------------------------------------------------------------------

# The point of the episode. Every component of a project built from scratch keeps, after a save
# and a reload, exactly the kernel its constructor gave it -- and Marionnet reports no adjustment.
case_fresh_project_is_a_fixed_point() {
  local mar="$tmpdir/fresh.mar" answer adjustments n before after
  local -a names=()

  if [[ "$(ask "new $mar")" != *'"ok":true'* ]]; then
     fail "could not create a project"
     return
  fi
  # One router and one machine on the default filesystem of their kind, then one machine per
  # installed filesystem: the constructor picks the kernel from the filesystem, so each one is a
  # separate choice. (Only these two kinds have a kernel at all.)
  ask "add router r1" >/dev/null; names+=(r1)
  ask "add machine m1" >/dev/null; names+=(m1)
  local d; local -i i=0   # -i matters: on a plain string, i+=1 concatenates ("0", "01", "011")
  while read -r d; do
     [[ -n "$d" ]] || continue
     i+=1
     if [[ "$(ask "add machine md$i --distrib=$d")" == *'"ok":true'* ]]; then names+=("md$i"); fi
  done < <(installed_distribs_of_kind machine)
  i=0
  while read -r d; do
     [[ -n "$d" ]] || continue
     i+=1
     if [[ "$(ask "add router rd$i --distrib=$d")" == *'"ok":true'* ]]; then names+=("rd$i"); fi
  done < <(installed_distribs_of_kind router)

  # Remember what each component was given, then save and leave.
  declare -A given=()
  for n in "${names[@]}"; do given[$n]=$(kernel_of "$n"); done
  if [[ "$(ask "save")" != *'"ok":true'* ]]; then
     fail "could not save the project"
     return
  fi
  stop_session

  start_session || { fail "could not restart a session"; return; }
  answer=$(ask "open $mar")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "could not load back the project just saved: $answer"
     return
  fi
  adjustments=$(kernel_adjustments_in "$answer")
  if [[ -n "$adjustments" ]]; then
     fail "loading back a project built here adjusted its kernels: $adjustments"
     return
  fi
  for n in "${names[@]}"; do
     before="${given[$n]}"; after=$(kernel_of "$n")
     if [[ "$after" != "$before" ]]; then
        fail "$n: kernel ${before@Q} at creation, ${after@Q} after a save and a reload"
        return
     fi
  done
  pass "${#names[@]} components created here keep their kernel through a save and a reload, with no adjustment reported"
}

# The second half of the TODO entry: a .mar older than the router's `kernel' attribute carries no
# such attribute, so the loaded component gets the CONSTRUCTOR's default with no remap in the way.
# The file is rewritten here rather than shipped: what matters is the missing attribute, which the
# v3 reader treats exactly as the older formats did.
#
# Note how the property is checked, because the obvious way does not work: on this load nothing
# can be reported, precisely because there is no attribute to remap. What the TODO entry described
# is that such a project needs TWO save-and-reopen cycles to converge -- so the bench plays the
# second one. If the constructor's default was unusable, it is now written in the file as an
# attribute, and this time the loader says so.
case_project_without_kernel_attribute() {
  local mar="$tmpdir/fresh.mar" edited="$tmpdir/no-kernel.mar" answer adjustments k k2
  if ! command -v jq >/dev/null; then
     skip "rewriting a .mar needs jq"
     return
  fi
  if [[ ! -f "$mar" ]]; then
     skip "no saved project to rewrite (the first case did not get that far)"
     return
  fi
  rm -rf "$tmpdir/unpacked" && mkdir -p "$tmpdir/unpacked" || { fail "could not unpack"; return; }
  tar xzf "$mar" -C "$tmpdir/unpacked" || { fail "could not unpack $mar"; return; }
  local net; net=$(find "$tmpdir/unpacked" -path '*/netmodel/network.json' | head -1)
  if [[ -z "$net" ]]; then
     skip "this .mar holds no netmodel/network.json (older project format)"
     return
  fi
  jq '(.roots[0].children[] | select(.tag == "router") | .attrs)
      |= map(select(.[0] != "kernel"))' "$net" > "$net.new" && mv "$net.new" "$net" \
    || { fail "could not rewrite $net"; return; }
  (cd "$tmpdir/unpacked" && tar czf "$edited" .) || { fail "could not repack"; return; }

  answer=$(ask "open $edited")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "could not load a project whose router carries no kernel attribute: $answer"
     return
  fi
  adjustments=$(kernel_adjustments_in "$answer")
  k=$(kernel_of r1)
  if [[ -n "$adjustments" ]]; then
     fail "a router with no kernel attribute was given a kernel that had to be adjusted: $adjustments"
     return
  fi
  if [[ -z "$k" ]]; then
     fail "a router with no kernel attribute holds no kernel at all after loading"
     return
  fi
  # The second cycle: save what the constructor decided, then load it back.
  if [[ "$(ask "save")" != *'"ok":true'* ]]; then
     fail "could not save the project loaded without a kernel attribute"
     return
  fi
  stop_session
  start_session || { fail "could not restart a session"; return; }
  answer=$(ask "open $edited")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "could not load back the project saved without a kernel attribute: $answer"
     return
  fi
  adjustments=$(kernel_adjustments_in "$answer")
  k2=$(kernel_of r1)
  if [[ -n "$adjustments" ]]; then
     fail "a router with no kernel attribute converges only at the second cycle: $adjustments"
  elif [[ "$k2" != "$k" ]]; then
     fail "a router with no kernel attribute was given ${k@Q}, which became ${k2@Q} one cycle later"
  else
     pass "a router with no kernel attribute is given ${k@Q}, and one save-and-reload cycle is enough"
  fi
}

# Anti-false-positive: the two cases above pass trivially if Marionnet stopped remapping (or
# stopped reporting). A .mar that really names an unusable kernel must still be repaired, and
# said. Skipped -- never faked -- on a host that does not install such a kernel, or one old
# enough to run it.
case_unusable_kernel_is_still_remapped() {
  local mar="$tmpdir/fresh.mar" edited="$tmpdir/old-kernel.mar" answer adjustments k
  if ! command -v jq >/dev/null; then
     skip "rewriting a .mar needs jq"
     return
  fi
  if [[ ! -f "$mar" ]]; then
     skip "no saved project to rewrite (the first case did not get that far)"
     return
  fi
  # Does this host even hold that kernel, and for the router's filesystem? The refusal names the
  # supported kernels, so again the bench reads the list instead of knowing it.
  answer=$(ask "set r1 kernel pas-un-noyau")
  if [[ "$answer" != *"$OLD_KERNEL"* ]]; then
     skip "the kernel $OLD_KERNEL is not among those supported here, nothing to remap"
     return
  fi
  rm -rf "$tmpdir/unpacked2" && mkdir -p "$tmpdir/unpacked2" || { fail "could not unpack"; return; }
  tar xzf "$mar" -C "$tmpdir/unpacked2" || { fail "could not unpack $mar"; return; }
  local net; net=$(find "$tmpdir/unpacked2" -path '*/netmodel/network.json' | head -1)
  if [[ -z "$net" ]]; then
     skip "this .mar holds no netmodel/network.json (older project format)"
     return
  fi
  jq --arg k "$OLD_KERNEL" \
     '(.roots[0].children[] | select(.tag == "router") | .attrs)
      |= (map(select(.[0] != "kernel")) + [["kernel", $k]])' "$net" > "$net.new" \
     && mv "$net.new" "$net" || { fail "could not rewrite $net"; return; }
  (cd "$tmpdir/unpacked2" && tar czf "$edited" .) || { fail "could not repack"; return; }

  answer=$(ask "open $edited")
  if [[ "$answer" != *'"ok":true'* ]]; then
     fail "could not load a project naming the kernel $OLD_KERNEL: $answer"
     return
  fi
  adjustments=$(kernel_adjustments_in "$answer")
  k=$(kernel_of r1)
  if [[ -z "$adjustments" ]]; then
     if [[ "$k" == "$OLD_KERNEL" ]]; then
        skip "this host runs $OLD_KERNEL as it is (kernel older than 5.15), nothing to remap"
     else
        fail "the kernel $OLD_KERNEL was replaced by ${k@Q} without a word to the user"
     fi
  elif [[ "$k" == "$OLD_KERNEL" ]]; then
     fail "an adjustment was reported ($adjustments) but the router still holds $OLD_KERNEL"
  else
     pass "a project naming $OLD_KERNEL is still repaired, and says so: $adjustments"
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
echo "Bench: a component created here needs no kernel remap when its project is loaded back — $BIN"

start_session || { echo "FAIL: no socket at $sock after 90s"; exit 1; }

case_fresh_project_is_a_fixed_point
case_project_without_kernel_attribute
case_unusable_kernel_is_still_remapped

stop_session

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
