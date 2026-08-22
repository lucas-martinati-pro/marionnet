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
# Bench: a binary run from the build tree reads THIS repository's catalogues.
# Work-stream marionnet-todo-transverse, episode 15.
#
# What is proved here is not what the code believes but what the kernel does: the bench reads
# the openat(2) of the running application (strace) and looks at the marionnet.mo it really
# opened. Three cases:
#
#   1. run as it comes: the catalogue opened lies INSIDE this repository -- before the fix it
#      was /usr/share/locale/<lang>/LC_MESSAGES/marionnet.mo, that is, another Marionnet's,
#      possibly years old (that is how a false measure was once believed true, cf. docs/TODO.md);
#   2. MARIONNET_LOCALEPREFIX pointing at a catalogue the bench itself builds, laid out exactly
#      as dune lays out its own (the .mo being a symbolic LINK): the variable wins over the
#      inference of case 1, and the link is followed -- without ~follow the directory looks
#      empty and the search falls back on /usr;
#   3. the decision is visible in the log (--debug): which directory was retained, and from
#      which origin. The cascade runs before Initialization sets the debug level, so its
#      messages used to be dropped: nothing could be diagnosed.
#
# Deliberately no `set -e': each case is decided explicitly, and a run which shows nothing must
# be reported rather than abort the bench. `set -u' and `pipefail' do apply.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"

# How long the application is given to reach the catalogue. It opens it while linking its
# modules, long before any window: a couple of seconds are enough, the rest is margin.
readonly RUN_TIMEOUT=25

# The languages having a catalogue (i18n/dune). The bench needs one of them to be an available
# locale of this machine, otherwise gettext translates nothing and opens nothing.
readonly SUPPORTED_LANGUAGES='fr it es pt ro de el eo pt_BR ru sk tr'

declare -i passed=0 failed=0 skipped=0
declare workdir=""
declare language="" locale_name=""

cleanup() {
  # Guard: never let an empty or short variable turn this into a wide removal.
  if [[ -n "$workdir" && "$workdir" == /tmp/marionnet-gettext.* && -d "$workdir" ]]; then
     rm -rf -- "$workdir"
  fi
}
trap cleanup EXIT

pass() { echo "PASS: $*"; passed+=1; }
fail() { echo "FAIL: $*"; failed+=1; }
skip() { echo "SKIP: $*"; skipped+=1; }

# pick_language -> sets `language' (the catalogue's name) and `locale_name' (the locale to ask
# for). Fails if this machine has none of the twelve.
pick_language() {
  local lang found
  for lang in $SUPPORTED_LANGUAGES; do
     found="$(locale -a 2>/dev/null | grep -iE "^${lang}(_[A-Z]+)?\.(utf-?8)$" | head -1)"
     if [[ -n "$found" ]]; then
        language="$lang"
        locale_name="$found"
        return 0
     fi
  done
  return 1
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
# DETACHES from its child and leaves it alive (measured -- six windows survived a first version
# of this bench). The pids are therefore read from the trace, where strace prefixes every line
# with the pid which made the call, and each one is checked against /proc before being
# signalled: an exact identity, never a pattern, and never more processes than expected.
stop_traced() {
  local trace="$1" strace_pid="$2"
  local -a traced=()
  local p i
  mapfile -t traced < <(awk '{print $1}' "$trace" 2>/dev/null | grep -xE '[0-9]+' | sort -u)
  # A fuse calibrated well above the ordinary run (which traces a few dozen pids: the
  # application plus the little commands it runs), not on it.
  if (( ${#traced[@]} > 500 )); then
     echo "internal: ${#traced[@]} traced pids, far more than this bench ever starts: nothing is signalled" >&2
     return 1
  fi
  for p in "${traced[@]}"; do is_the_binary "$p" && kill -TERM "$p" 2>/dev/null; done
  sleep 2
  for p in "${traced[@]}"; do is_the_binary "$p" && kill -KILL "$p" 2>/dev/null; done
  # strace leaves by itself once what it traces is gone. Signalling it would only detach it --
  # and make the shell report a stopped job in the middle of the bench's output.
  # No `wait' on strace, and the job is disowned where it is started: strace deliberately dies
  # of the same signal as what it traces, and the shell would announce that death in the middle
  # of the bench's output, at whatever moment it happens to reap the job.
  if [[ -n "$strace_pid" ]]; then
     for ((i = 0; i < 5; i++)); do kill -0 "$strace_pid" 2>/dev/null || break; sleep 1; done
     kill -0 "$strace_pid" 2>/dev/null && kill -KILL "$strace_pid" 2>/dev/null
  fi
}

# run_and_trace <trace-file> <log-file> [VAR=value ...]
#
# Runs the application under strace until it opens a marionnet.mo (or the timeout expires),
# then stops it and everything it started.
run_and_trace() {
  local trace="$1" log="$2"; shift 2
  local pid i tmp
  : >"$trace"
  # A temporary directory of its own, and not the user's: the startup warning about the run
  # directories left behind now carries buttons that ARCHIVE and REMOVE them (bin/marionnet.ml),
  # so a bench that lets the application see the real /tmp puts the user's own leftovers one
  # stray click away from being swept. Nothing here depends on which directory it is.
  tmp="$(mktemp -d "$workdir/tmpdir.XXXXXX")"
  env TMPDIR="$tmp" "$@" strace -f -e trace=openat -o "$trace" "$BIN" --debug >/dev/null 2>"$log" &
  pid=$!
  disown "$pid" 2>/dev/null
  for ((i = 0; i < RUN_TIMEOUT; i++)); do
     sleep 1
     grep -q 'marionnet\.mo' "$trace" 2>/dev/null && break
     kill -0 "$pid" 2>/dev/null || break
  done
  stop_traced "$trace" "$pid"
}

# catalogue_opened <trace-file> -> the path of the marionnet.mo successfully opened, empty if
# none was (an openat returning -1 is not an opening).
catalogue_opened() {
  grep -oE '"[^"]*marionnet\.mo", O_RDONLY[^)]*\) = [0-9]+' "$1" 2>/dev/null \
    | head -1 | sed -E 's/^"([^"]*)".*/\1/'
}

# --- The bench itself

if [[ ! -x "$BIN" ]]; then
   echo "SKIP: no executable at $BIN (run dune build first)"
   exit 77
fi
if ! command -v strace >/dev/null 2>&1; then
   echo "SKIP: strace is not installed, the catalogue really opened cannot be read"
   exit 77
fi
if ! command -v msgfmt >/dev/null 2>&1; then
   echo "SKIP: msgfmt is not installed (package gettext), the bench cannot build a catalogue"
   exit 77
fi
if ! pick_language; then
   echo "SKIP: none of the twelve supported languages is an available UTF-8 locale here"
   exit 77
fi

workdir="$(mktemp -d /tmp/marionnet-gettext.XXXXXX)"
echo "language: $language (locale $locale_name)"

# --- Case 1: as it comes, the catalogue belongs to this repository.

run_and_trace "$workdir/trace1" "$workdir/log1" "LANGUAGE=$language" "LC_ALL=$locale_name"
mo="$(catalogue_opened "$workdir/trace1")"
if [[ -z "$mo" ]]; then
   if [[ -z "${DISPLAY:-}" ]]; then
      skip "plain run: no catalogue was opened, and there is no DISPLAY: the application could not go far enough"
   else
      fail "plain run: the application opened no catalogue at all within ${RUN_TIMEOUT}s"
   fi
elif [[ "$mo" == "$ROOT/"* ]]; then
   pass "plain run: reads ${mo#"$ROOT"/}, inside this repository"
else
   fail "plain run: reads $mo, which belongs to another Marionnet"
fi

# --- Case 2: an explicit MARIONNET_LOCALEPREFIX wins, links and all.
#
# The catalogue is laid out as dune lays out the `locale' site: <lang>/LC_MESSAGES/marionnet.mo
# is a symbolic link towards the compiled file. This is what UnixExtra.find used to miss.

mkdir -p "$workdir/store" "$workdir/locale/$language/LC_MESSAGES"
printf '%s\n' 'msgid ""' 'msgstr ""' '"Content-Type: text/plain; charset=UTF-8\n"' \
  > "$workdir/tiny.po"
if ! msgfmt "$workdir/tiny.po" -o "$workdir/store/$language.mo" 2>"$workdir/msgfmt.err"; then
   skip "explicit prefix: msgfmt could not build a catalogue ($(head -1 "$workdir/msgfmt.err"))"
else
   ln -s "../../../store/$language.mo" "$workdir/locale/$language/LC_MESSAGES/marionnet.mo"
   run_and_trace "$workdir/trace2" "$workdir/log2" \
     "LANGUAGE=$language" "LC_ALL=$locale_name" "MARIONNET_LOCALEPREFIX=$workdir/locale"
   mo="$(catalogue_opened "$workdir/trace2")"
   if [[ "$mo" == "$workdir/locale/$language/LC_MESSAGES/marionnet.mo" ]]; then
      pass "explicit prefix: MARIONNET_LOCALEPREFIX is honoured, its .mo being a symbolic link"
   elif [[ -z "$mo" ]]; then
      fail "explicit prefix: the application opened no catalogue at all within ${RUN_TIMEOUT}s"
   else
      fail "explicit prefix: MARIONNET_LOCALEPREFIX was ignored, $mo was read instead"
   fi
fi

# --- Case 3: the decision says its name in the log.

if grep -qE "Gettext: .* found in .*, chosen from " "$workdir/log1"; then
   pass "log: the retained directory and its origin are printed ($(grep -oE 'chosen from .*' "$workdir/log1" | head -1))"
elif grep -qi 'gettext' "$workdir/log1"; then
   fail "log: something is said about Gettext, but not which directory was retained nor why"
else
   fail "log: --debug says nothing at all about the catalogue (the cascade's messages are dropped)"
fi

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
