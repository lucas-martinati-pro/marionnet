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

# Example 3 — configure the routing daemons of a router, from a script.
#
# A router carries one startup configuration per routing daemon, beside its UNIX one. This
# example writes ZEBRA's, leaves one daemon out of the boot, and reads everything back. It
# stops at the model: nothing is started here, because a configuration is read when the device
# is built — see example 2 for the start-and-collect loop.
#
# Expects a Marionnet started with --control-socket, $MARIONNET_CONTROL_SOCKET set, and an open
# project. Usage: ./03-router-daemons.sh [<router>]

set -euo pipefail

MRNCTL="${MRNCTL:-mrnctl}"
ROUTER="${1:-r1}"

command -v "$MRNCTL" >/dev/null ||
  { echo "$0: no mrnctl: set \$MRNCTL to bin/scripts/mrnctl" >&2; exit 2; }
[[ -n ${MARIONNET_CONTROL_SOCKET:-} ]] ||
  { echo "$0: set \$MARIONNET_CONTROL_SOCKET first" >&2; exit 2; }

ctl() { echo "+ $*" >&2; "$MRNCTL" "$@"; }

# Create the router unless it is already there. `add' chooses a kernel its filesystem declares.
"$MRNCTL" can "$ROUTER" >/dev/null 2>&1 || ctl add router "$ROUTER"

# WHICH CONFIGURATIONS THIS ROUTER HAS — asked, never assumed. The names below come from the
# component itself; this script holds no list of protocols.
echo
echo "startup configurations of $ROUTER:"
"$MRNCTL" -q '.available | join(" ")' rc-get "$ROUTER"

# ZEBRA's own configuration file, written in clear and carried by --from.
ZEBRA_CONF=$(mktemp)
trap 'rm -f "$ZEBRA_CONF"' EXIT
cat > "$ZEBRA_CONF" <<EOF
!--- written by $(basename "$0")
hostname $ROUTER
password zebra
interface eth0
 ip address 10.0.0.254/24
EOF

# Writing a content enables it AND selects the daemon: a configuration that would silently go
# nowhere is exactly what this channel exists to avoid.
ctl rc-set "$ROUTER" --from="$ZEBRA_CONF" --field=zebra

# The second switch, on its own: this daemon is not to be configured at boot at all. Its file
# is moved aside inside the guest, so it does not start.
ctl rc-set "$ROUTER" --field=ospf --unselect

echo
echo "read back:"
"$MRNCTL" -q '"zebra  enabled=\(.enabled) selected=\(.selected) bytes=\(.bytes)"' \
  rc-get "$ROUTER" --field=zebra
"$MRNCTL" -q '"ospf   enabled=\(.enabled) selected=\(.selected)"' \
  rc-get "$ROUTER" --field=ospf

# The UNIX startup configuration of the same router is a different field, untouched by all
# this: naming no field still means that one.
"$MRNCTL" -q '"unix   field=\(.field) bytes=\(.bytes)"' rc-get "$ROUTER"

echo
echo "Now start the router (see example 2): the configuration is read when the device is built."
