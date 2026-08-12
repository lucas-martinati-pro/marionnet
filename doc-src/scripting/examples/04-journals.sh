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

# Example 4 — read what happened *inside*: the journals of a machine, and what a switch knows.
#
# This is the checking half of a scripted lab: example 2 makes the guest do the work, this one
# reads the traces it left. Nothing here opens a window, and nothing needs the guest's network:
# a journal is a file on the host side, and a switch answers on its management socket.
#
# Expects the lab of example 1 (m1 on s1), a Marionnet started with --control-socket, and
# $MARIONNET_CONTROL_SOCKET set.
# Usage: ./04-journals.sh [<machine>] [<switch>]

set -euo pipefail

MRNCTL="${MRNCTL:-mrnctl}"
NODE="${1:-m1}"
SWITCH="${2:-s1}"

command -v "$MRNCTL" >/dev/null ||
  { echo "$0: no mrnctl: set \$MRNCTL to useful-scripts/mrnctl" >&2; exit 2; }
[[ -n ${MARIONNET_CONTROL_SOCKET:-} ]] ||
  { echo "$0: set \$MARIONNET_CONTROL_SOCKET first" >&2; exit 2; }

ctl() { echo "+ $*" >&2; "$MRNCTL" "$@"; }

# Both must be running: a journal of the guest is written during its boot, and the tables of a
# switch exist only inside a running vde_switch. `start' is refused on something already on, so
# it is asked for only when the state says so.
for c in "$NODE" "$SWITCH"; do
  state=$("$MRNCTL" -q ".nodes[]|select(.name==\"$c\")|.state" ls)
  [[ $state == on ]] || ctl start "$c"
done
ctl wait "$NODE"   --state=on --timeout=120
ctl wait "$SWITCH" --state=on --timeout=60

# The guest has to have reached the end of its boot before its journals say anything useful.
# A machine with no startup configuration never writes the ready marker (nothing writes it but
# the scenario), so this wait is allowed to fail: the journals below answer either way.
ctl wait "$NODE" --ready --timeout=300 || echo "  (no ready marker: this machine has no scenario)"

# WHICH JOURNALS THIS COMPONENT HAS — asked, never assumed, exactly like the configurations of
# example 3. A machine has seven, a switch one, a cable none.
echo
echo "journals of $NODE:  $("$MRNCTL" -q '.available|join(" ")' log "$NODE")"
echo "journals of $SWITCH: $("$MRNCTL" -q '.available|join(" ")' log "$SWITCH")"

# 1. THE STARTUP CONFIGURATION. Whatever wrote it — the guest for a machine, Marionnet for a
# switch — a failing command leaves the same line, so one grep answers for both.
echo
echo "--- $NODE: did its startup configuration fail? ---"
if "$MRNCTL" -q .content log "$NODE" rc_config | grep '^!! FAILED'; then
  echo "  ^ that is the command which failed, with its status"
else
  echo "  no failure recorded"
fi

echo
echo "--- $SWITCH: what vde_switch answered at startup ---"
"$MRNCTL" -q .content log "$SWITCH" | sed -n '1,10p'

# 2. THE BOOT. What happened *before* the relay was reached — the part no scenario can report
# on, since the scenario had not run yet.
echo
echo "--- $NODE: boot (last 15 lines) ---"
"$MRNCTL" -q .content log "$NODE" boot --tail=15 ||
  echo "  (not there yet: the collector writes it at the end of the boot — see wait --ready)"

# The check a lab is graded on, in one line: under systemd the collector writes the failed
# units, so their absence is a property a script can assert.
if "$MRNCTL" -q .content log "$NODE" boot | grep -q '^0 loaded units listed'; then
  echo "  verdict: no service failed"
fi

# 3. WHAT WAS TYPED. This one is refused when nobody has typed anything yet — and the refusal
# says so, rather than serving an empty file. Hence the explicit `||': it is news, not an error.
echo
echo "--- $NODE: commands typed at the prompt ---"
"$MRNCTL" -q .content log "$NODE" commands ||
  echo "  (nothing typed yet — the history appears with the first prompt)"

# 4. WHAT THE SWITCH KNOWS RIGHT NOW. The mirror of the above: this is not a file, it lives
# inside the running vde_switch and dies with it.
echo
echo "--- $SWITCH: MAC addresses learnt, and on which port ---"
learnt=$("$MRNCTL" -q '.tables[]|select(.name=="macs")|.entries[]|"  \(.mac) on port \(.port // "?")"' \
           switch-info "$SWITCH" macs || true)
if [[ -n $learnt ]]; then
  echo "$learnt"
else
  # A switch learns a MAC when a frame carries it — and a guest which talks to nobody sends
  # none. A ping towards a neighbour, even one that does not exist, is enough: the ARP request
  # is broadcast, and it carries the sender's address.
  echo "  (nothing learnt yet, or no jq: a switch learns a MAC when a frame carries it)"
fi

echo
echo "--- $SWITCH: ports, in the switch's own words ---"
"$MRNCTL" -q '.tables[]|select(.name=="ports")|.lines[]' switch-info "$SWITCH" ports | sed -n '1,12p'
