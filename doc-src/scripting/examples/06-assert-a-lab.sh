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

# Example 6 — assert a lab instead of eyeballing it: what a correction key looks like when it is
# a file rather than a shell script.
#
# It runs in two steps, and the second one is the interesting one:
#
#   1. the MODEL — topology, ports, cables — asserted from `lab.mrv', with nothing running;
#   2. the GUEST — the same machine, started with a startup configuration, asserted on what it
#      LEFT (its journal) and on what it IS (its report). Those two are not the same statement,
#      and this example is built to show it: the configuration enables IP forwarding with a plain
#      redirection, so the trace does not carry the word `ip_forward' — `set -x' does not trace
#      redirections — while the report says `net.ipv4.ip_forward = 1'.
#
# Expects the lab of example 1 (m1, m2 on s1), a Marionnet started with --control-socket, and
# $MARIONNET_CONTROL_SOCKET set.
# Usage: ./06-assert-a-lab.sh [<machine>]

set -euo pipefail

MRNCTL="${MRNCTL:-mrnctl}"
MRN_VERIFY="${MRN_VERIFY:-mrn-verify}"
HERE="$(cd "$(dirname "$0")" && pwd)"
NODE="${1:-m1}"

for tool in "$MRNCTL" "$MRN_VERIFY"; do
  command -v "$tool" >/dev/null ||
    { echo "$0: no $tool: set \$MRNCTL / \$MRN_VERIFY to the ones in bin/scripts/" >&2; exit 2; }
done
[[ -n ${MARIONNET_CONTROL_SOCKET:-} ]] ||
  { echo "$0: set \$MARIONNET_CONTROL_SOCKET first" >&2; exit 2; }

ctl() { echo "+ $*" >&2; "$MRNCTL" "$@"; }

# 1. THE MODEL. Nothing is started: these assertions are about what Marionnet knows.
echo "--- the model ---"
"$MRN_VERIFY" "$HERE/lab.mrv"

# 2. THE GUEST. A startup configuration whose effect is NOT visible in its own trace.
echo
echo "--- giving $NODE something to do ---"
SCEN=$(mktemp /tmp/scenario-XXXXXX.sh)
RUNNING=""                      # named before the trap, which would otherwise fire on unset
trap 'rm -f "$SCEN" ${RUNNING:+"$RUNNING"}' EXIT
cat > "$SCEN" <<'EOF'
echo 1 > /proc/sys/net/ipv4/ip_forward
ip link set eth0 up || true
ip addr add 10.0.0.1/24 dev eth0 || true
# The ready marker is written by the scenario, never by the relay: without this line,
# `wait --ready' below would wait for nothing.
: > /mnt/hostfs/marionnet-guest-ready
EOF

state=$("$MRNCTL" -q ".nodes[]|select(.name==\"$NODE\")|.state" ls)
[[ $state == off ]] || { echo "$0: $NODE is $state; this example wants it off" >&2; exit 2; }
ctl rc-set "$NODE" --from="$SCEN"
ctl start "$NODE"
ctl wait "$NODE" --state=on --timeout=120
ctl wait "$NODE" --ready --timeout=300

echo
echo "--- what it left, and what it is ---"
RUNNING=$(mktemp /tmp/running-XXXXXX.mrv)
cat > "$RUNNING" <<EOF
state $NODE is on

# What it LEFT: no command of the startup configuration failed. This is the assertion to lean
# on, rather than looking for a particular command in the trace.
journal $NODE rc_config ok

# What it IS. The report is taken inside the guest, on demand.
report $NODE says ~ net[.]ipv4[.]ip_forward *= *1
report $NODE says 10.0.0.1/24

# And the one nobody can answer yet: no verb runs a command inside a guest, so this is SKIP —
# never a failure. The day the channel can, the same line starts being answered.
reaches $NODE m2
EOF
"$MRN_VERIFY" --timeout=240 "$RUNNING" || true    # a SKIP is expected: see the last assertion

echo
echo "--- and the assertion that looks the same, but is not ---"
printf 'journal %s rc_config contains ip_forward\n' "$NODE" > "$RUNNING"
"$MRN_VERIFY" "$RUNNING" || true
echo "  ^ it fails, and forwarding IS enabled: set -x does not trace redirections."

echo
echo "Done. Shut $NODE down when you are finished:  $MRNCTL poweroff $NODE"
