#!/bin/bash
# Mark one student's copy.
#
#   marionnet --control-socket /tmp/mark.sock &        # WITHOUT --exam: you are the teacher now
#   export MARIONNET_CONTROL_SOCKET=/tmp/mark.sock
#   ./grade.sh /srv/exams/dupont.mar [replay|recorded]
#
#   replay   (default) start the copy again and mark what it does: the state of each guest and
#            what actually crosses the network. Slow, and it is the only way to judge
#            connectivity.
#   recorded ask no guest anything: mark on what the session archived into the project. Fast,
#            and it is what thirty copies in one evening look like.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
COPY=${1:?usage: grade.sh <student.mar> [replay|recorded]}
MODE=${2:-replay}
MRNCTL=${MRNCTL:-mrnctl}
VERIFY=${MRN_VERIFY:-mrn-verify}

: "${MARIONNET_CONTROL_SOCKET:?start a driven Marionnet first (see the header of this file)}"
[[ $COPY == /* ]] || COPY=$PWD/$COPY

"$MRNCTL" open "$COPY"

echo "=== what the session left behind ==="
# Nothing here means the machines were never shut down properly: the archiving is part of a
# graceful shutdown, and a power cut skips it.
"$MRNCTL" -q '.rows[].fields.Title' documents || true

echo
case $MODE in
  recorded)
    "$VERIFY" --refresh=never "$HERE/key-recorded.mrv"
    ;;
  replay)
    "$MRNCTL" start-all
    for c in m1 r1 intruder; do
      # NOT `wait --ready': on a second start of the same components the marker of the previous
      # boot is still there and --ready answers immediately. Wait for the guest to ANSWER.
      until "$MRNCTL" exec "$c" --timeout=20 -- true >/dev/null 2>&1; do sleep 2; done
    done
    "$VERIFY" "$HERE/key.mrv"
    ;;
  *) echo "unknown mode: $MODE" >&2; exit 2 ;;
esac
