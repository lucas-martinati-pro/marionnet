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
#
# Bench: a binary run from the build tree reads THIS repository's glade and images -- and keeps
# reading the guest filesystems and the kernels of the INSTALLED Marionnet.
# Work-stream marionnet-todo-transverse, episode 22.
#
# The point of the entry is not "read everything from _build": the prefix that `dune build'
# produces holds an EMPTY filesystems/ and NO kernels/ at all. What is proved here is therefore a
# choice made directory by directory, in five cases:
#
#   1. as it comes, `--paths' shows gui/ and images/ inside this repository. Before the fix there
#      was no `gui' line at all, and `images' named the installed Marionnet's -- possibly years
#      old, which is how a modification of the glade could stay invisible until `make install';
#   2. and, in the same run, filesystems/ and kernels/ do NOT come from the build tree: switching
#      the prefix as a whole would have deprived a development run of its guests;
#   3. what the kernel does, not what the code believes (strace): the gui_glade3.xml really
#      opened lies inside this repository. The proof is a PATH, never a content: this bench does
#      not touch the glade of the repository;
#   4. an explicit MARIONNET_PREFIX still wins over the inference, for every directory;
#   5. the decision says its name in the log (--debug).
#
# Cases 1, 2, 4 and 5 need neither DISPLAY nor strace: `--paths' exits during initialization,
# before any window. Case 3 needs both, and is skipped when either is missing.
#
# Deliberately no `set -e': each case is decided explicitly, and a run which shows nothing must
# be reported rather than abort the bench. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

# `--paths' prints and exits: a couple of seconds are enough, the rest is margin.
readonly PATHS_TIMEOUT=30
# How long the application is given to reach its glade, which it opens while building the main
# window -- that is, only once Gtk+ has a display.
readonly RUN_TIMEOUT=25

declare -i passed=0 failed=0 skipped=0
declare workdir=""

cleanup() {
  # Guard: never let an empty or short variable turn this into a wide removal.
  if [[ -n "$workdir" && "$workdir" == /tmp/marionnet-glade.* && -d "$workdir" ]]; then
     rm -rf -- "$workdir"
  fi
}
trap cleanup EXIT

pass() { echo "PASS: $*"; passed+=1; }
fail() { echo "FAIL: $*"; failed+=1; }
skip() { echo "SKIP: $*"; skipped+=1; }

# run_paths [VAR=value ...] -> the output of `--paths', empty if the binary did not get there.
run_paths() {
  local tmp
  tmp="$(mktemp -d "$workdir/tmpdir.XXXXXX")"
  env TMPDIR="$tmp" "$@" timeout "$PATHS_TIMEOUT" "$BIN" --paths 2>/dev/null
}

# field <key> <output-of---paths> -> the path printed for that key, empty if the key is absent.
# An absent key is not an internal error here: a binary predating episode 22 has no `gui' line,
# and that is precisely what must be reported as a failure by the case which asks for it.
field() {
  sed -n "s|^$1  *: *||p" <<<"$2" | head -1
}

# is_the_binary <pid> -> true if that pid is, right now, the binary this bench started. Most of
# the traced pids are short-lived helpers already gone (a pid file which no longer exists is
# simply not ours), and a pid may in principle have been recycled: hence an identity read from
# /proc rather than a remembered number.
is_the_binary() {
  local cmd
  cmd="$( { tr '\0' ' ' < "/proc/$1/cmdline"; } 2>/dev/null )"
  [[ "$cmd" == "$BIN "* ]]
}

# stop_traced <trace-file> <strace-pid>
#
# Stops what the trace shows running. Signalling strace itself is not enough: on SIGTERM strace
# DETACHES from its child and leaves it alive. The pids are therefore read from the trace, where
# strace prefixes every line with the pid which made the call, and each one is checked against
# /proc before being signalled: an exact identity, never a pattern.
stop_traced() {
  local trace="$1" strace_pid="$2"
  local -a traced=()
  local p i
  mapfile -t traced < <(awk '{print $1}' "$trace" 2>/dev/null | grep -xE '[0-9]+' | sort -u)
  # A fuse calibrated well above the ordinary run (a few dozen pids), not on it.
  if (( ${#traced[@]} > 500 )); then
     echo "internal: ${#traced[@]} traced pids, far more than this bench ever starts: nothing is signalled" >&2
     return 1
  fi
  for p in "${traced[@]}"; do is_the_binary "$p" && kill -TERM "$p" 2>/dev/null; done
  sleep 2
  for p in "${traced[@]}"; do is_the_binary "$p" && kill -KILL "$p" 2>/dev/null; done
  # strace leaves by itself once what it traces is gone; it is disowned where it is started so
  # that the shell does not announce its death in the middle of the bench's output.
  if [[ -n "$strace_pid" ]]; then
     for ((i = 0; i < 5; i++)); do kill -0 "$strace_pid" 2>/dev/null || break; sleep 1; done
     kill -0 "$strace_pid" 2>/dev/null && kill -KILL "$strace_pid" 2>/dev/null
  fi
}

# run_and_trace <trace-file> <log-file> [VAR=value ...]
#
# Runs the application under strace until it opens a gui_glade3.xml (or the timeout expires),
# then stops it and everything it started.
run_and_trace() {
  local trace="$1" log="$2"; shift 2
  local pid i tmp
  : >"$trace"
  # A temporary directory of its own, and not the user's: the startup warning about the run
  # directories left behind carries buttons that ARCHIVE and REMOVE them (bin/marionnet.ml), so a
  # bench that lets the application see the real /tmp puts the user's own leftovers one stray
  # click away from being swept.
  tmp="$(mktemp -d "$workdir/tmpdir.XXXXXX")"
  env TMPDIR="$tmp" "$@" strace -f -e trace=openat -o "$trace" "$BIN" --debug >/dev/null 2>"$log" &
  pid=$!
  disown "$pid" 2>/dev/null
  for ((i = 0; i < RUN_TIMEOUT; i++)); do
     sleep 1
     grep -q 'gui_glade3\.xml' "$trace" 2>/dev/null && break
     kill -0 "$pid" 2>/dev/null || break
  done
  stop_traced "$trace" "$pid"
}

# opened <trace-file> <extended-regexp> -> the path of the first file matching it which was
# successfully opened (an openat returning -1 is not an opening).
opened() {
  grep -oE "\"[^\"]*$2\", O_RDONLY[^)]*\) = [0-9]+" "$1" 2>/dev/null \
    | head -1 | sed -E 's/^"([^"]*)".*/\1/'
}

# --- The bench itself

if [[ ! -x "$BIN" ]]; then
   echo "SKIP: no executable at $BIN (run dune build first)"
   exit 77
fi

workdir="$(mktemp -d /tmp/marionnet-glade.XXXXXX)"

# --- Cases 1 and 2: what the binary says it will read.

out="$(run_paths)"
if [[ -z "$out" ]]; then
   echo "SKIP: \`$BIN --paths' printed nothing within ${PATHS_TIMEOUT}s"
   exit 77
fi

gui="$(field gui "$out")"
images="$(field images "$out")"
filesystems="$(field filesystems "$out")"
kernels="$(field kernels "$out")"

if [[ -z "$gui" ]]; then
   fail "versioned data: \`--paths' has no \`gui' line at all (a binary predating episode 22)"
elif [[ "$gui" == "$ROOT/"* && "$images" == "$ROOT/"* ]]; then
   pass "versioned data: glade and images come from ${gui#"$ROOT"/} and ${images#"$ROOT"/}, inside this repository"
else
   fail "versioned data: glade in $gui and images in $images, which belong to another Marionnet"
fi

# The other half of the decision: the data which are NOT versioned here must keep coming from the
# installation, the build tree holding an empty filesystems/ and no kernels/ at all.
if [[ "$filesystems" == "$ROOT/_build/"* || "$kernels" == "$ROOT/_build/"* ]]; then
   fail "installed data: filesystems ($filesystems) or kernels ($kernels) taken from the build tree, which holds neither"
else
   pass "installed data: filesystems and kernels still come from the installation ($filesystems)"
fi

# --- Case 3: what the kernel does.

if ! command -v strace >/dev/null 2>&1; then
   skip "real opening: strace is not installed, the glade really opened cannot be read"
elif [[ -z "${DISPLAY:-}" ]]; then
   skip "real opening: no DISPLAY, the application cannot reach its main window"
else
   # The language is frozen: nothing here matches a text of the application, but a run in the
   # user's language costs a catalogue lookup for nothing.
   run_and_trace "$workdir/trace" "$workdir/log" "LANGUAGE=C" "LC_ALL=C"
   glade="$(opened "$workdir/trace" 'gui_glade3\.xml')"
   image="$(opened "$workdir/trace" 'images/[^"]*\.(png|xpm)')"
   if [[ -z "$glade" ]]; then
      fail "real opening: the application opened no glade at all within ${RUN_TIMEOUT}s"
   elif [[ "$glade" == "$ROOT/"* ]]; then
      pass "real opening: opens ${glade#"$ROOT"/}, inside this repository"
   else
      fail "real opening: opens $glade, which belongs to another Marionnet"
   fi
   if [[ -z "$image" ]]; then
      skip "real opening: no image was opened within ${RUN_TIMEOUT}s"
   elif [[ "$image" == "$ROOT/"* ]]; then
      pass "real opening: opens ${image#"$ROOT"/}, inside this repository"
   else
      fail "real opening: opens the image $image, which belongs to another Marionnet"
   fi
fi

# --- Case 4: an explicit prefix wins over the inference.
#
# The prefix is laid out as an installation would be, its glade being a link towards this
# repository's: the bench asks a question about the DECISION, not about a missing file.

mkdir -p "$workdir/prefix/gui"
ln -s "$ROOT/bin/gui/gui_glade3.xml" "$workdir/prefix/gui/gui_glade3.xml"
ln -s "$ROOT/bin/images" "$workdir/prefix/images"
out2="$(run_paths "MARIONNET_PREFIX=$workdir/prefix")"
gui2="$(field gui "$out2")"
fs2="$(field filesystems "$out2")"
if [[ "$gui2" == "$workdir/prefix/gui" && "$fs2" == "$workdir/prefix/filesystems" ]]; then
   pass "explicit prefix: MARIONNET_PREFIX wins over the development tree, for every directory"
elif [[ -z "$out2" ]]; then
   fail "explicit prefix: \`--paths' printed nothing within ${PATHS_TIMEOUT}s"
else
   fail "explicit prefix: MARIONNET_PREFIX was ignored (glade in $gui2, filesystems in $fs2)"
fi

# --- Case 5: the decision says its name in the log.

tmp5="$(mktemp -d "$workdir/tmpdir.XXXXXX")"
log5="$(env TMPDIR="$tmp5" timeout "$PATHS_TIMEOUT" "$BIN" --debug --paths 2>&1)"
if grep -qE '^\[[^]]*\]: Path: glade and images taken from ' <<<"$log5"; then
   pass "log: $(grep -oE 'Path: glade and images taken from [^:]*' <<<"$log5" | head -1)"
else
   fail "log: --debug says nothing about where the glade and the images are taken from"
fi

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
