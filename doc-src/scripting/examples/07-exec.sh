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

# Example 7 — make the guest run something, and read what it answered.
#
# Every other example OBSERVES: it reads a model, a journal, a report. This one COMMANDS: `exec'
# runs a command line inside a running machine or router. It is the only way to answer a question
# about *now* which is not a state but an ability -- "does this machine reach that address?" --
# and it is why the channel keeps a journal of its own of what it was asked to run.
#
# Expects a machine (m1 by default), a Marionnet started with --control-socket, and
# $MARIONNET_CONTROL_SOCKET set.
# Usage: ./07-exec.sh [<machine>] [<address to reach>]

set -euo pipefail

MRNCTL="${MRNCTL:-mrnctl}"
NODE="${1:-m1}"
TARGET="${2:-}"

command -v "$MRNCTL" >/dev/null ||
  { echo "$0: no mrnctl: set \$MRNCTL to useful-scripts/mrnctl" >&2; exit 2; }
[[ -n ${MARIONNET_CONTROL_SOCKET:-} ]] ||
  { echo "$0: set \$MARIONNET_CONTROL_SOCKET first" >&2; exit 2; }

ctl() { echo "+ $*" >&2; "$MRNCTL" "$@"; }

# A command runs *inside* a running guest, so the machine has to be up -- and further than up:
# the watcher which serves the request is started at the very end of the boot.
state=$("$MRNCTL" -q ".nodes[]|select(.name==\"$NODE\")|.state" ls)
[[ $state == on ]] || ctl start "$NODE"
ctl wait "$NODE" --state=on --timeout=120
ctl wait "$NODE" --ready --timeout=300 || echo "  (no ready marker: this machine has no scenario)"

# 1. THE SIMPLE FORM. The answer carries the status and the output, and names the journal where
# the request was written down.
echo
echo "--- what kernel is $NODE running? ---"
ctl exec "$NODE" uname -a

# 2. THE SEPARATOR. Options are recognised wherever they stand in a request, so an option meant
# for the command must come after a bare `--'. Without it the channel would take `--all' for one
# of its own -- and it refuses rather than running a mutilated command.
echo
echo "--- what the host left in the hostfs of $NODE ---"
"$MRNCTL" -q .output exec "$NODE" -- ls --all /mnt/hostfs

# 3. THE STATUS IS THE ANSWER. A command which fails is not an error of the channel: it is the
# result. This is what makes a verdict scriptable.
echo
echo "--- is a web server listening on $NODE? ---"
# One argument, not several: this channel is line-oriented, so the quoting has to reach the
# server -- the calling shell would eat it if it saw the words separately.
if "$MRNCTL" -q .status exec "$NODE" 'sh -c "ss -ltn 2>/dev/null | grep -q :80 "' | grep -qx 0
then echo "  yes"
else echo "  no (nothing is listening on port 80)"
fi

# 4. THE BOUND. `--timeout' bounds the command INSIDE the guest: when it expires the command is
# killed there, and the answer says so instead of leaving the caller with no news at all.
echo
echo "--- a command which does not come back ---"
"$MRNCTL" -q '"status=" + (.status|tostring) + " timed_out=" + (.timed_out|tostring)' \
          exec "$NODE" sleep 30 --timeout=5

# 5. CONNECTIVITY -- the assertion no journal and no report can make. A report describes a state;
# whether a packet gets through is another question, and it is answered here or nowhere.
if [[ -n $TARGET ]]; then
  echo
  echo "--- does $NODE reach $TARGET? ---"
  if "$MRNCTL" -q .status exec "$NODE" --timeout=20 -- ping -c 1 -W 2 "$TARGET" | grep -qx 0
  then echo "  yes"
  else echo "  no"
  fi
  echo "  (the same thing, as an assertion: 'reaches $NODE $TARGET' in a .mrv -- see example 6)"
fi

# 6. WHAT THE CHANNEL INJECTED, kept apart from what the student typed. Two writers, two files:
# `exec' holds the commands this channel ran, `commands' the history of the interactive shells.
# For marking, the distinction is the whole point.
echo
echo "--- the exec journal of $NODE: what was run through the channel ---"
"$MRNCTL" -q .content log "$NODE" exec

echo
echo "--- and the student's own history, which does not hold any of it ---"
"$MRNCTL" -q .content log "$NODE" commands ||
  echo "  (nobody has typed anything in this guest yet)"
