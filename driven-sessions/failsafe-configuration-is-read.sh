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

# Bench: the failsafe copy of marionnet.conf shipped with the software is really read.
# Work-stream marionnet-todo-transverse, episode 25.
#
# Before the fix, bin/configuration.ml looked for it in <prefix>/share/marionnet/marionnet.conf
# and <prefix>/etc/marionnet/marionnet.conf. NEITHER path exists: dune installs that file one
# `share' deeper, in <prefix>/share/marionnet/share/marionnet.conf. The cascade therefore
# reduced in practice to /etc/marionnet/ and ~/.marionnet/, and the values shipped with
# Marionnet were never read.
#
# The other half of the defect, and the reason this bench also counts the copies: the file
# which WAS installed (bin/share/marionnet.conf) was not the maintained one. It had drifted
# since 2026-07 and still carried `MARIONNET_BRIDGE=br0', a line commented out in
# etc/marionnet.conf since episode 7b of `modernisation-world-bridge' because it turns the
# automatic LAN bridge off. Fixing the searched path alone would have ACTIVATED that stale
# file. There is now one source, etc/marionnet.conf, installed by etc/dune.
#
# Neither a guest nor a privilege is needed -- the binary is started, says what it read in its
# --debug journal, and is asked to quit -- hence a versioned bench (docs/todo-transverse.md,
# section 3.6).
#
# Deliberately no `set -e': several checks EXPECT a failing status, and everything that
# matters is tested explicitly. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"
# The install tree `dune build' produces anyway: same layout as a real installation, which is
# what lets this bench check the installed paths without installing anything.
readonly INSTALL_SHARE="$ROOT/_build/install/default/share/marionnet"
readonly LINGER=30

declare -i passed=0 failed=0 skipped=0
declare tmpdir="" sock="" stderr="" pid=""

cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
     kill -9 "$pid" 2>/dev/null
     wait "$pid" 2>/dev/null
  fi
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

ask() { echo "$1" | timeout 60 socat -t "$LINGER" -T "$LINGER" - "UNIX-CONNECT:$sock" 2>/dev/null; }

# The variables a configuration file really SETS (a commented line sets nothing).
variables_of() { grep -oE '^[A-Z_]+=' -- "$1" 2>/dev/null | tr -d '=' | sort -u; }

# --- the cases about the layout (no session needed) -------------------------------------------

# Where the file really is. Both halves are checked: present one `share' deep inside the
# package directory, and ABSENT at the path the cascade used to name -- otherwise the case
# below, which reads the cascade itself, could pass by accident.
case_the_install_layout_is_one_share_deeper() {
  local good="$INSTALL_SHARE/share/marionnet.conf"
  local old="$INSTALL_SHARE/marionnet.conf"
  if [[ ! -e "$good" ]]; then
     fail "the install tree carries no share/marionnet.conf (looked at $good)"
  elif [[ -e "$old" ]]; then
     fail "a file also sits at the OLD searched path ($old): the two can no longer be told apart"
  else
     pass "the failsafe copy is installed one 'share' deeper than the path searched before episode 25"
  fi
}

# It must be the maintained file of the repository, not a second copy of it.
case_the_installed_file_is_the_repository_one() {
  local good="$INSTALL_SHARE/share/marionnet.conf"
  [[ -e "$good" ]] || { skip "no installed copy to compare (previous case failed)"; return; }
  if cmp -s "$good" "$ROOT/etc/marionnet.conf"; then
     pass "the installed failsafe copy is etc/marionnet.conf itself"
  else
     fail "the installed failsafe copy differs from etc/marionnet.conf: a second copy is back"
  fi
}

# The regression guard which matters most: one source, one file. A second versioned copy is
# how the installed one silently became stale in the first place.
case_the_repository_carries_one_copy() {
  local copies n f
  if ! (cd "$ROOT" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
     skip "not a git work tree: the number of versioned copies cannot be counted here"
     return
  fi
  # Versioned AND still on disk: a copy staged for deletion but not yet committed is gone
  # as far as an installation is concerned, and this case is about what gets shipped.
  copies=$(cd "$ROOT" && git ls-files | grep -E '(^|/)marionnet\.conf$' \
             | while read -r f; do [[ -e "$f" ]] && echo "$f"; done | sort)
  n=$(echo "$copies" | grep -c . )
  if [[ "$n" -eq 1 && "$copies" == "etc/marionnet.conf" ]]; then
     pass "the repository versions exactly one marionnet.conf, etc/marionnet.conf"
  else
     fail "the repository versions $n copies of marionnet.conf: $(echo $copies)"
  fi
}

# And the stale line itself, named: whatever else changes, the shipped file must not turn the
# automatic LAN bridge off behind the user's back.
case_the_shipped_file_does_not_force_a_bridge() {
  if grep -qE '^MARIONNET_BRIDGE=' "$ROOT/etc/marionnet.conf"; then
     fail "etc/marionnet.conf sets MARIONNET_BRIDGE: the shipped copy would disable the automatic LAN bridge"
  else
     pass "the shipped copy leaves MARIONNET_BRIDGE unset (automatic LAN bridge preserved)"
  fi
}

# --- the cases about what the running binary reads ---------------------------------------------

# The deferred diagnosis (episode 25, same shape as Gettext's of episode 15) is what makes the
# cascade observable at all: before it, nothing said which files had been looked for.
case_the_journal_names_the_candidates() {
  if grep -q "Configuration: candidate files" "$stderr"; then
     pass "the journal says which configuration files were looked for"
  else
     fail "no configuration diagnosis in the --debug journal (episode 25 is not in this binary)"
  fi
}

# And the cascade must now NAME that path. The installed candidate is the one which does not
# come from the build tree; the old path must appear nowhere, not even as [absent] -- a
# candidate which can never exist is exactly the defect this episode closed.
case_the_cascade_names_the_installed_path() {
  local installed old_path
  installed=$(grep -E "Configuration: +\[(read|absent)\] +/.*/share/marionnet/share/marionnet\.conf" "$stderr" | grep -v '_build' | head -1)
  old_path=$(grep -E "Configuration: +\[(read|absent)\] +/.*/share/marionnet/marionnet\.conf$" "$stderr" | head -1)
  if [[ -z "$installed" ]]; then
     fail "the cascade names no installed failsafe copy at <prefix>/share/marionnet/share/"
  elif [[ -n "$old_path" ]]; then
     fail "the cascade still names the path which never exists: $old_path"
  else
     pass "the cascade names the installed failsafe copy where dune really puts it"
  fi
}

# Running from _build, the copy of THIS repository must be among the files read -- the rule
# episode 22 set for the glade and the images.
case_the_repository_copy_is_read() {
  local line
  line=$(grep -E "Configuration: +\[read\] +$INSTALL_SHARE/share/marionnet\.conf" "$stderr")
  if [[ -n "$line" ]]; then
     pass "the binary of _build reads the failsafe copy of this repository"
  else
     fail "the failsafe copy of this repository is not read: $(grep -E 'Configuration: ' "$stderr" | head -5)"
  fi
}

# Priority is the point of a cascade: the shipped copy is the LOWEST, an administrator's file
# must still win over it. Read on the order of the diagnosis lines, which is the order of the
# list given to Configuration_files.
case_the_shipped_copy_does_not_outrank_etc() {
  local n_ship n_etc
  n_ship=$(grep -n "Configuration: .*$INSTALL_SHARE/share/marionnet.conf" "$stderr" | head -1 | cut -d: -f1)
  n_etc=$(grep -n "Configuration: .*/etc/marionnet/marionnet.conf" "$stderr" | head -1 | cut -d: -f1)
  if [[ -z "$n_ship" || -z "$n_etc" ]]; then
     skip "one of the two candidates is missing from the diagnosis, order cannot be read"
  elif (( n_ship < n_etc )); then
     pass "the shipped copy comes before /etc/marionnet/ in the cascade (lower priority)"
  else
     fail "the shipped copy is listed after /etc/marionnet/: it would override the administrator"
  fi
}

# The value itself, when the host lets it be seen. Every variable of the shipped copy which a
# higher-priority file also sets is masked -- on a machine where Marionnet has been installed
# for years, that is usually all of them, and the case then skips rather than pretending.
case_a_shipped_value_reaches_the_application() {
  local masked candidate="" v value_expected value_seen
  masked=$( { variables_of /etc/marionnet/marionnet.conf; variables_of "$HOME/.marionnet/marionnet.conf"; } | sort -u)
  while read -r v; do
     [[ -n "$v" ]] || continue
     grep -qx -- "$v" <<< "$masked" && continue
     grep -q "Searching for variable $v:" "$stderr" || continue
     candidate="$v"; break
  done < <(variables_of "$ROOT/etc/marionnet.conf")
  if [[ -z "$candidate" ]]; then
     skip "every variable of the shipped copy is either masked by a higher-priority file of this host or never queried"
     return
  fi
  value_expected=$(grep -E "^$candidate=" "$ROOT/etc/marionnet.conf" | tail -1 | cut -d= -f2- | tr -d '"')
  value_seen=$(grep -A1 "Searching for variable $candidate:" "$stderr" | grep -oE 'found value "[^"]*"' | head -1 | sed 's/^found value "//; s/"$//')
  if [[ "$value_seen" == "$value_expected" ]]; then
     pass "a value of the shipped copy reaches the application ($candidate=$value_seen)"
  else
     fail "$candidate should come from the shipped copy as '$value_expected', the application found '$value_seen'"
  fi
}

# --- main ---------------------------------------------------------------------------------------

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
stderr="$tmpdir/stderr"
echo "Bench: the failsafe copy of marionnet.conf is read — $BIN"

case_the_install_layout_is_one_share_deeper
case_the_installed_file_is_the_repository_one
case_the_repository_carries_one_copy
case_the_shipped_file_does_not_force_a_bridge

# The language is pinned: since episode 15 a binary run from _build is translated, and a bench
# which matched an English word of the application would silently stop proving anything.
LANGUAGE=C LC_ALL=C timeout -k 5 180 "$BIN" --debug --control-socket "$sock" >/dev/null 2>"$stderr" &
pid=$!
for ((i = 0; i < 90; i++)); do [[ -S "$sock" ]] && break; sleep 1; done
if [[ ! -S "$sock" ]]; then
   echo "FAIL: no socket at $sock after 90s"
   exit 1
fi

case_the_journal_names_the_candidates
case_the_cascade_names_the_installed_path
case_the_repository_copy_is_read
case_the_shipped_copy_does_not_outrank_etc
case_a_shipped_value_reaches_the_application

# A session started by a bench ends through the channel or by SIGKILL: Marionnet neutralises
# SIGTERM (bin/marionnet.ml), so `kill' then `wait' would never return (episode 18).
ask quit >/dev/null
wait "$pid" 2>/dev/null; pid=""

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
