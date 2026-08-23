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

# Example 1 — build a lab through the control channel and save it.
#
# Two machines on a switch, addressed, written to a .mar. Nothing is started here: the point
# is that a lab is *built* by the channel and *written* by Marionnet, which is the only
# legitimate producer of a .mar file. Replay it afterwards with:
#
#     marionnet --control-socket "$MARIONNET_CONTROL_SOCKET" -r /tmp/lab.mar
#
# Expects a Marionnet started with --control-socket, and $MARIONNET_CONTROL_SOCKET set.
# Usage: ./01-build-a-lab.sh [<path of the .mar to write>]

set -euo pipefail

MRNCTL="${MRNCTL:-mrnctl}"
LAB="${1:-/tmp/lab.mar}"

command -v "$MRNCTL" >/dev/null ||
  { echo "$0: no mrnctl: set \$MRNCTL to bin/scripts/mrnctl" >&2; exit 2; }
[[ -n ${MARIONNET_CONTROL_SOCKET:-} ]] ||
  { echo "$0: set \$MARIONNET_CONTROL_SOCKET first" >&2; exit 2; }

# The channel answers one JSON line per request. Here we only care about the refusals, and
# `mrnctl' already turns those into exit code 1, so `set -e' is the whole error handling.
ctl() { echo "+ $*" >&2; "$MRNCTL" "$@"; }

# A project must exist before any component does; `add' on nothing answers no_active_project.
# --no-save: if something was open and modified, we say what to do with it rather than let the
# channel guess (it would answer unsaved_changes).
ctl new "$LAB" --no-save

ctl add machine m1 --ports=2
ctl add machine m2
ctl add switch  s1 --ports=8

# Ports are *named* as the GUI names them, never indexed. Mind the two conventions: a machine
# numbers its interfaces from 0 (eth0), a switch numbers its ports from 1 (port1). A refusal
# lists the free port names of the node, so there is nothing to guess.
ctl connect c1 m1:eth0 s1:port1
ctl connect c2 m2:eth0 s1:port2

# One field at a time. The field is the *slug* of the column: lowercase, non-alphanumeric runs
# become dashes ("IPv4 address" -> ipv4-address). Nothing is running yet, so no
# --restart/--no-restart is needed.
ctl ifconfig-set m1 eth0 ipv4-address 10.0.0.1/24
ctl ifconfig-set m2 eth0 ipv4-address 10.0.0.2/24

ctl save-as "$LAB"

echo
echo "Lab written to $LAB:"
"$MRNCTL" -q '.nodes[] | "  \(.kind) \(.name) (\(.state))"' ls 2>/dev/null ||
  "$MRNCTL" ls   # no jq here: the raw line still says everything
