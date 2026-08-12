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

# Example 5 — an exam session, from the outside: let the student work, shut down properly, and
# collect what the session left in the project file.
#
# Recording is a property of the LAUNCH, not of a request, so this example expects a Marionnet
# started for an exam:
#
#     marionnet --exam --control-socket "$MARIONNET_CONTROL_SOCKET" -r exam.mar
#
# What --exam adds is the archiving: at the graceful shutdown of each machine, its report, its
# command history, its console and its terminal session are imported into the `documents'
# treeview, hence into the .mar. See doc-src/exam-mode.md.
#
# Usage: ./05-exam-session.sh [<machine>]

set -euo pipefail

MRNCTL="${MRNCTL:-mrnctl}"
NODE="${1:-m1}"

command -v "$MRNCTL" >/dev/null ||
  { echo "$0: no mrnctl: set \$MRNCTL to useful-scripts/mrnctl" >&2; exit 2; }
[[ -n ${MARIONNET_CONTROL_SOCKET:-} ]] ||
  { echo "$0: set \$MARIONNET_CONTROL_SOCKET first" >&2; exit 2; }

ctl() { echo "+ $*" >&2; "$MRNCTL" "$@"; }

# IS THIS SESSION RECORDING? There is no verb for it, and none is needed: a refusal says why a
# journal is missing, and "does not record" is a different piece of news from "not started yet".
# Checked before anything is started, so that a session launched without --exam is caught while
# it can still be relaunched.
detail=$("$MRNCTL" -q .detail log "$NODE" console 2>/dev/null || true)
case "$detail" in
  *"does not record"*)
    echo "$0: this Marionnet was not started with --exam (nor --console-log)." >&2
    echo "$0: what a session does not record cannot be collected afterwards." >&2
    exit 2 ;;
esac

state=$("$MRNCTL" -q ".nodes[]|select(.name==\"$NODE\")|.state" ls)
[[ $state == on ]] || ctl start "$NODE"
ctl wait "$NODE" --state=on --timeout=120
ctl wait "$NODE" --ready --timeout=300 || echo "  (no ready marker: this machine has no scenario)"

# --- the student works here ------------------------------------------------------------
# Nothing to do for us: the history is appended at every prompt, and the terminal session is
# recorded by the host. Both can be read WHILE the student works, which is what makes a lab
# observable rather than merely gradable:

echo
echo "--- what has been typed so far ---"
"$MRNCTL" -q .content log "$NODE" commands --tail=10 ||
  echo "  (nothing typed yet)"

echo
echo "--- the last lines of the recorded terminal ---"
"$MRNCTL" -q .content log "$NODE" terminal --tail=10 ||
  echo "  (no terminal recorded: no window has been opened for this machine)"

# --- end of the session ----------------------------------------------------------------
# `stop' is the GRACEFUL shutdown, and the archiving is the very last thing it does — a power
# cut collects nothing. It also hands the request over rather than performing it, so the wait
# below is not a precaution: reading `documents' right after `stop' reads an empty treeview,
# and closing the project would pull the directory from under the archiving.
echo
ctl stop "$NODE"
ctl wait "$NODE" --state=off --timeout=300

# The archiving is the last thing the shutdown does, and it runs AFTER the state has become
# off: waiting for the state is necessary, and not quite sufficient. A bounded wait on the
# treeview itself is what makes this reliable — never an unbounded one, and never a fixed sleep.
docs_count() { "$MRNCTL" -q '.count' documents 2>/dev/null || echo "no jq"; }
i=0
while (( i < 30 )) && [[ "$(docs_count)" == 0 ]]; do sleep 1; i=$((i+1)); done

echo
echo "--- what the session left in the project ---"
"$MRNCTL" -q '.rows[]|"  \(.fields.Title)  [\(.fields.Type)]"' documents ||
  "$MRNCTL" documents

# The documents are part of the project now: saving is what makes them outlive this Marionnet.
ctl save
echo
echo "$(docs_count) document(s) saved with the project."
