#!/bin/bash
# Build the project that is handed out to the students, and save it.
#
#   marionnet --control-socket /tmp/lab.sock &
#   export MARIONNET_CONTROL_SOCKET=/tmp/lab.sock
#   ./build.sh [/where/to/save/session-7.mar]
#
# What it leaves out is the point: r1 gets NO boot scenario. Configuring it is the lab.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-/tmp/session-7.mar}
MRNCTL=${MRNCTL:-mrnctl}

: "${MARIONNET_CONTROL_SOCKET:?start a driven Marionnet first (see the header of this file)}"

# The topology and the declared addresses.
"$MRNCTL" -f "$HERE/lab.mrn"

# The two ends configure themselves at boot and say when they are ready. r1 does not.
"$MRNCTL" rc-set m1       --from="$HERE/m1-scenario.sh"       --enable
"$MRNCTL" rc-set intruder --from="$HERE/intruder-scenario.sh" --enable

"$MRNCTL" save-as "$OUT"
echo "handed out: $OUT"
