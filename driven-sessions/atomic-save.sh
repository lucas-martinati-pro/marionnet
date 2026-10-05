#!/usr/bin/env bash
# GPL-2.0-or-later. Real Marionnet session, no guest or privileged operation.
# A tar wrapper simulates a partial write on demand. It also understands the old
# writer's flags, so this bench fails on the pre-fix application, not just a helper.
# Run with: xvfb-run -a bash driven-sessions/atomic-save.sh [binary] [--gui]
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"
gui="${2:-}"
if [[ ! -x "$BIN" || -z "${DISPLAY:-}" ]]; then
  echo "SKIP: a built binary and DISPLAY are required (use xvfb-run -a)"
  exit 77
fi
for tool in socat jq tar sha256sum timeout; do
  if ! command -v "$tool" >/dev/null; then echo "SKIP: $tool is required"; exit 77; fi
done
if [[ "$gui" = --gui ]] && ! command -v xdotool >/dev/null; then
  echo "SKIP: --gui requires xdotool"
  exit 77
fi

bench_dir="$(mktemp -d /tmp/marionnet-atomic-save.XXXXXX)"
sock="$bench_dir/control.sock"
pid=""
cleanup() {
  # Only kill the process this bench started, after checking its unique socket argument.
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    if grep -qzF -- "$sock" "/proc/$pid/cmdline" 2>/dev/null; then kill -KILL "$pid"; fi
    wait "$pid" 2>/dev/null || true
  fi
  # All this session's working directories are beneath our private MARIONNET_TMPDIR.
  rm -rf -- "$bench_dir"
}
trap cleanup EXIT
mkdir "$bench_dir/tools" "$bench_dir/run"
real_tar="$(command -v tar)"
printf '#!/bin/bash\nREAL_TAR=%q\n' "$real_tar" > "$bench_dir/tools/tar"
cat >> "$bench_dir/tools/tar" <<'WRAPPER'
if [[ -e "$MARIONNET_ARCHIVE_BENCH/fail-create" ]]; then
  case "$1" in
    --create)
      while [[ "$1" != --file ]]; do shift; done
      target="$2"
      ;;
    -cSvzf) target="$2" ;;
    *) exec "$REAL_TAR" "$@" ;;
  esac
  printf 'partial archive\n' > "$target"
  echo 'simulated disk full' >&2
  exit 2
fi
exec "$REAL_TAR" "$@"
WRAPPER
chmod +x "$bench_dir/tools/tar"
PATH="$bench_dir/tools:$PATH" MARIONNET_ARCHIVE_BENCH="$bench_dir" \
  MARIONNET_TMPDIR="$bench_dir/run" MARIONNET_LANG=en LANGUAGE=C LC_ALL=C \
  "$BIN" --debug --no-welcome --control-socket "$sock" >"$bench_dir/stdout" 2>"$bench_dir/stderr" &
pid=$!

ask() { printf '%s\n' "$1" | timeout 45 socat -t 35 -T 40 - "UNIX-CONNECT:$sock"; }
require_json() {
  local answer="$1" condition="$2" description="$3"
  if jq -e "$condition" <<< "$answer" >/dev/null; then
    echo "PASS: $description"
  else
    echo "FAIL: $description: $answer" >&2
    exit 1
  fi
}
require_unchanged() {
  local current
  current="$(sha256sum "$target")"
  [[ "$current" = "$previous" ]] || { echo "FAIL: previous archive was overwritten" >&2; exit 1; }
  echo "PASS: previous archive is byte-for-byte unchanged"
}
for ((i=0; i<300; i++)); do
  [[ -S "$sock" ]] && break
  kill -0 "$pid" 2>/dev/null || { cat "$bench_dir/stderr" >&2; exit 1; }
  sleep 0.1
done
[[ -S "$sock" ]] || { echo "FAIL: no control socket after 30s" >&2; exit 1; }

target="$bench_dir/lab.mar"
require_json "$(ask "new --timeout=30 $target")" '.ok == true' "project created"
require_json "$(ask 'save --timeout=30')" '.ok == true and .saved == true' "first save succeeds"
"$real_tar" -tzf "$target" >/dev/null
previous="$(sha256sum "$target")"

# Fail even with a CLEAN model: otherwise a stale saved flag can hide a failed Save as.
touch "$bench_dir/fail-create"
answer="$(ask 'save --timeout=30')"
require_json "$answer" '.ok == false and .error == "internal"' "partial write is reported as a failure"
require_json "$answer" 'any(.notifications[]; .body | contains("simulated disk full"))' \
  "the error notification contains the measured cause"
require_unchanged
require_json "$(ask status)" '.active == true and .saved == false' "failed save leaves the project open and unsaved"
require_json "$(ask 'close --save --timeout=30')" '.ok == false and .error == "internal"' \
  "close --save is refused after a failed save"
require_json "$(ask status)" '.active == true and .saved == false' "failed close keeps the working project"
require_unchanged
if [[ "$gui" = --gui ]]; then
  # Observe a REAL question dialog and a NEW failed-save log entry. Merely sending
  # a key and finding the project still open would also pass if the key did nothing.
  for gesture in Close Quit; do
    sleep 3 # Let the previous error dialog finish its documented auto-dismiss delay.
    before="$(grep -c 'state#save_project END. FAILED' "$bench_dir/stderr" || true)"
    main_window="$(xdotool search --onlyvisible --pid "$pid" --name '[Mm]arionnet' | head -n 1)"
    [[ -n "$main_window" ]] || { echo "FAIL: main window missing" >&2; exit 1; }
    key=ctrl+w
    [[ "$gesture" = Quit ]] && key=ctrl+q
    xdotool windowfocus --sync "$main_window"
    xdotool key --clearmodifiers "$key"
    dialog=""
    for ((i=0; i<100; i++)); do
      dialog="$(xdotool search --onlyvisible --pid "$pid" --name "^$gesture\$" 2>/dev/null || true)"
      [[ -n "$dialog" ]] && break
      sleep 0.1
    done
    [[ -n "$dialog" ]] || { echo "FAIL: $gesture save question did not open" >&2; exit 1; }
    xdotool windowfocus --sync "${dialog%%$'\n'*}"
    xdotool key --clearmodifiers y
    after="$before"
    for ((i=0; i<100; i++)); do
      after="$(grep -c 'state#save_project END. FAILED' "$bench_dir/stderr" || true)"
      (( after > before )) && break
      sleep 0.1
    done
    (( after > before )) || { echo "FAIL: $gesture did not attempt to save" >&2; exit 1; }
    require_json "$(ask status)" '.active == true and .saved == false' \
      "GUI $gesture followed by Yes keeps the project after a failed save"
    require_unchanged
  done
fi
if [[ -n "$(find "$bench_dir" -maxdepth 1 -name '.marionnet-save-*' -print)" ]]; then
  echo "FAIL: handled failure leaked temporary files" >&2; exit 1
fi

rm "$bench_dir/fail-create"
require_json "$(ask 'save --timeout=30')" '.ok == true and .saved == true' "retry succeeds after the fault is removed"
special="$bench_dir/TP d'aujourd'hui & réseau.mar"
require_json "$(ask "save-as --timeout=30 -- $special")" '.ok == true and .saved == true' \
  "Save as accepts spaces, apostrophes and markup characters"
"$real_tar" -tzf "$special" >/dev/null
require_json "$(ask 'close --no-save --timeout=30')" '.ok == true and .closed == true' "project closes after success"
require_json "$(ask "open --timeout=30 -- $special")" '.ok == true' "the saved project can be reopened"
require_json "$(ask status)" '.active == true and .saved == true' "reopened project is recognised as saved"
require_json "$(ask 'close --no-save --timeout=30')" '.ok == true' "session cleans up its project"
require_json "$(ask quit)" '.ok == true and .quitting == true' "session quits"
for ((i=0; i<100; i++)); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$pid" 2>/dev/null; then echo "FAIL: session did not quit" >&2; exit 1; fi
wait "$pid"
pid=""
echo "PASS: atomic save session completed"
