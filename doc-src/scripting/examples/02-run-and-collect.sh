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

# Example 2 — give a machine a scenario, start it, wait for the *guest*, read what it wrote.
#
# This is the loop a scripted lab is made of: the channel commands the infrastructure, the
# startup configuration commands the inside of the machine, and the guest reports back through
# the hostfs directory. No ssh, no guest network needed to collect the result.
#
# Expects the lab of example 1 (or any project holding m1), a Marionnet started with
# --control-socket, and $MARIONNET_CONTROL_SOCKET set.
# Usage: ./02-run-and-collect.sh [<machine>]

set -euo pipefail

MRNCTL="${MRNCTL:-mrnctl}"
NODE="${1:-m1}"
SCENARIO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scenario-ping.sh"

command -v "$MRNCTL" >/dev/null ||
  { echo "$0: no mrnctl: set \$MRNCTL to useful-scripts/mrnctl" >&2; exit 2; }
[[ -n ${MARIONNET_CONTROL_SOCKET:-} ]] ||
  { echo "$0: set \$MARIONNET_CONTROL_SOCKET first" >&2; exit 2; }

ctl() { echo "+ $*" >&2; "$MRNCTL" "$@"; }

# The startup configuration is read when the *device is built*, so it must be posted before
# the start, never on a running machine. --from carries the content in clear: the project file
# is never touched by hand.
ctl rc-set "$NODE" --from="$SCENARIO" --enable

# `start' answers `accepted', not `done' — it hands the request over, it does not wait.
ctl start "$NODE"

# Two different instants, and both are worth distinguishing:
#   --state=on    the UML process is running        (under a second)
#   --ready       the guest wrote its marker        (several seconds more)
ctl wait "$NODE" --state=on --timeout=120
ctl wait "$NODE" --ready   --timeout=300

# Where the guest writes, host side. `rc-get' says it, so nothing has to be guessed.
hostfs=$("$MRNCTL" -q '.hostfs' rc-get "$NODE" 2>/dev/null) ||
  { echo "$0: install jq, or read the 'hostfs' field of: $("$MRNCTL" rc-get "$NODE")" >&2; exit 2; }

echo
echo "--- $hostfs/lab.log ---"
cat "$hostfs/lab.log"
