#!/bin/bash
# Play the lab as a correct student would, and mark it. This is the run a teacher owes their
# own lab before handing it out: a lab that has never been played is a hypothesis.
#
#   marionnet --control-socket /tmp/lab.sock &
#   export MARIONNET_CONTROL_SOCKET=/tmp/lab.sock
#   ./play.sh
#
# It ends with the discriminant: the same key, on the same session, after the router's
# forwarding has been switched off from the outside. What must change is the STATE and the
# EXPERIMENT; what must not is the TRACE — the configuration did run, an hour ago.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
MRNCTL=${MRNCTL:-mrnctl}
VERIFY=${MRN_VERIFY:-mrn-verify}
export MRNCTL          # build.sh, called below, honours it too

: "${MARIONNET_CONTROL_SOCKET:?start a driven Marionnet first (see the header of this file)}"

"$HERE/build.sh" /tmp/session-7-solved.mar

# The solution, as the student's own boot scenario would be.
"$MRNCTL" rc-set r1 --from="$HERE/r1-solution.sh" --enable
"$MRNCTL" save

echo "=== starting the three guests ==="
"$MRNCTL" start-all
for c in m1 r1 intruder; do
  "$MRNCTL" wait "$c" --ready --timeout=300
done

echo
echo "=== the key, on a correct copy ==="
"$VERIFY" "$HERE/key.mrv" || true

echo
echo "=== the discriminant: forwarding switched off, in flight ==="
"$MRNCTL" exec r1 -- sysctl -w net.ipv4.ip_forward=0
"$VERIFY" "$HERE/key.mrv" || true
echo
echo "Expected above: the report and reaches assertions now FAIL, and"
echo "\`journal r1 rc_config ok' still PASSES — the configuration did run."
