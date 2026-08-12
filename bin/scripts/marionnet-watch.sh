#!/bin/bash
# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2026  Jean-Vincent Loddo
# Copyright (C) 2026  Université Sorbonne Paris Nord
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

# ---------------------------------------------------------------------------
# Guest-side ON-DEMAND WATCHER.  Deep logging, episodes 16 and 18.
#
# This file belongs to NO guest image.  The host deposits it into the hostfs at
# every boot (`make_hostfs_content', bin/simulation_level.ml) and the epilogue
# `marionnet-relay.zz-journal' starts it in the background at the end of the
# boot.  Its name deliberately does NOT match the relay's `marionnet-relay*'
# glob: it must be started, not sourced.
#
# WHY IT EXISTS.  Episode 15 measured five real labs against the channel and
# found the state of a running guest to be unobservable (M1): the five journals
# are TRACES -- what was said -- and a trace does not say what IS.  Episode 16
# answered that with the REPORT on demand, whose producer already existed
# (`marionnet-report', episode 7) and only lacked a trigger.  Episode 18
# answers the manque the report cannot reach (M2): a report describes a state,
# it never says whether m1 REACHES h3 at this instant.  Only running something
# inside the guest does, so a second request is served here -- and that is the
# one which changes the nature of the channel, from observing to commanding.
#
# ONE loop for the two, and this is the reason the file was renamed (it was
# `marionnet-report-watch.sh'): the hostfs offers no notification of any kind,
# so watching costs one wakeup per second and per guest -- a cost § 6 of the
# work-stream already records.  A second watcher would double it for nothing.
#
# THE PROTOCOL, and who writes what -- the hostfs is the only way back:
#
#   report.request   the HOST writes it (verb `report'), the GUEST consumes it
#   report.md        the GUEST writes it, by renaming .report.md.part onto it
#   report.done      the GUEST writes it once the rename is done; the HOST
#                    removes it BEFORE posting a request, so its reappearance
#                    is what proves the answer is a fresh one
#
#   exec.request     the HOST writes it (verb `exec'): a first line
#                    `id=<nonce> timeout=<seconds>', then the command
#   exec.out         the GUEST writes it (stdout AND stderr, merged), by
#                    renaming .exec.out.part onto it
#   exec.done        the GUEST writes it: `id=<nonce> status=<n> epoch=<s>
#                    lines=<n> seconds=<n>'
#   exec.log         the GUEST appends to it: what the CHANNEL was asked to run,
#                    with its status.  Served as the seventh journal, and the
#                    reason it exists is marking: `commands' holds what the
#                    STUDENT typed, this one what the channel injected.  Two
#                    writers, two files -- the rule of episode 8.
#
# The `id' is what episode 16 did without and this one cannot: a report is
# idempotent, so serving a stale request merely costs a report, whereas running
# a stale command twice is a side effect.  The host names each request; an
# answer carrying another name is not the answer to that request.
#
# The renames are the point of the `.part' files: the channel serves report.md
# and exec.out WHILE the guest runs, so a reader must never be able to see a
# half-written one.  The `.done' files are removed here too, before producing:
# a stale one -- left by a client that died -- must not be mistaken for the
# answer to the request being served.
#
# Plain Bash on purpose: this code runs inside the guest, which has no
# `bashbricks' (nor anything beyond a minimal userland).
# ---------------------------------------------------------------------------

__mrn_watch_dir=/mnt/hostfs
__mrn_watch_producer="$__mrn_watch_dir/marionnet-report"
__mrn_watch_request="$__mrn_watch_dir/report.request"
__mrn_watch_done="$__mrn_watch_dir/report.done"
__mrn_watch_out="$__mrn_watch_dir/report.md"
__mrn_watch_part="$__mrn_watch_dir/.report.md.part"
__mrn_watch_exec_request="$__mrn_watch_dir/exec.request"
__mrn_watch_exec_done="$__mrn_watch_dir/exec.done"
__mrn_watch_exec_out="$__mrn_watch_dir/exec.out"
__mrn_watch_exec_part="$__mrn_watch_dir/.exec.out.part"
__mrn_watch_exec_log="$__mrn_watch_dir/exec.log"
__mrn_watch_period=1

# --- The state this process INHERITS from the shell that started it.  The
#     epilogue starts us at the end of the boot, in the relay's own shell: the
#     prologue's xtrace and ERR trap may still be on (Marionnet's `-d' puts
#     xtrace back), and a trace here would end up on the student's console for
#     the whole life of the machine.  Dropped before anything else:
{ set +x ; } 2>/dev/null
trap - ERR 2>/dev/null
set +o errtrace 2>/dev/null

# A leftover request from a PREVIOUS boot is not ours to serve: the COW file is
# fresh at every boot but the hostfs directory is NOT -- it belongs to the
# project, and survives.  A request from THIS boot, on the contrary, must be
# served: we may well be late.  Measured, and it is not a corner case -- under
# systemd this watcher is started by a job which systemd only runs once the boot
# is over, whereas `wait --ready' answers as soon as the startup configuration
# writes its marker, well before that.  A blind `rm' here threw away exactly the
# requests posted in that window.
#
# The two are told apart the way [wait --ready] tells a stale marker from a fresh
# one (control_server.ml): by comparing with boot_parameters, which Marionnet
# rewrites at every startup.
__mrn_watch_boot="$__mrn_watch_dir/boot_parameters"
for __mrn_watch_stale in "$__mrn_watch_request" "$__mrn_watch_exec_request" ; do
  if [[ -e "$__mrn_watch_stale" ]]; then
    if [[ ! -e "$__mrn_watch_boot" || "$__mrn_watch_stale" -ot "$__mrn_watch_boot" ]]; then
      rm -f "$__mrn_watch_stale" 2>/dev/null
    fi
  fi
done
unset __mrn_watch_boot __mrn_watch_stale

# --- The REPORT branch (episode 16).  Nothing to produce with if the producer
#     was not deposited (an old host binary, or a hostfs that could not be
#     written): the request is then left alone rather than answered with a
#     failure, and the host says so when it times out.  Note that this is no
#     longer a reason to give up the whole watcher, as it was when the report
#     was all it served: `exec' needs no producer.
__mrn_watch_do_report() {
  local status lines

  # Consumed FIRST: whatever happens next, the request must not be served
  # twice.  And the stale answer goes away before the new one is produced.
  rm -f "$__mrn_watch_request" 2>/dev/null
  rm -f "$__mrn_watch_done" 2>/dev/null

  status=0
  MARIONNET_REPORT_OUT="$__mrn_watch_part" \
  MARIONNET_REPORT_WHEN=on-demand \
    /bin/bash "$__mrn_watch_producer" </dev/null >/dev/null 2>&1 \
    || status=$?

  # The rename is what publishes the report.  If it fails, the previous
  # report -- if any -- is left untouched, and the status says so.
  if ! mv -f "$__mrn_watch_part" "$__mrn_watch_out" 2>/dev/null; then
    [[ "$status" -ne 0 ]] || status=1
    rm -f "$__mrn_watch_part" 2>/dev/null
  fi

  lines="$(wc -l < "$__mrn_watch_out" 2>/dev/null)"
  printf 'status=%s epoch=%s lines=%s\n' \
    "$status" "$(date +%s 2>/dev/null)" "${lines:-0}" \
    > "$__mrn_watch_done" 2>/dev/null
  sync 2>/dev/null
  return 0
}

# --- Bounded execution.  `timeout' comes from coreutils and is there on every
#     image measured so far, wheezy included; the fallback exists because a
#     watcher which hangs on one command stops answering `report' too -- one
#     loop for the two means one failure for the two, and that is the price of
#     the single loop.  So: never run a command without a bound, even when the
#     usual way of bounding one is missing.
__mrn_watch_bounded() {
  local seconds="$1" ; shift
  local pid waited=0 status

  if type -p timeout >/dev/null 2>&1; then
    timeout "$seconds" /bin/bash -c "$1" </dev/null >"$__mrn_watch_exec_part" 2>&1
    return $?
  fi

  /bin/bash -c "$1" </dev/null >"$__mrn_watch_exec_part" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [[ "$waited" -ge "$seconds" ]]; then
      kill -TERM "$pid" 2>/dev/null
      sleep 2
      kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      # The status `timeout' itself would have returned, so that a caller has
      # one thing to look at whichever branch ran.
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null
  status=$?
  return "$status"
}

# --- The EXEC branch (episode 18).
__mrn_watch_do_exec() {
  local header id seconds command status started elapsed lines

  header="$(head -n 1 "$__mrn_watch_exec_request" 2>/dev/null)"
  command="$(tail -n +2 "$__mrn_watch_exec_request" 2>/dev/null)"

  # Read as WORDS rather than with a regexp, as the host reads the answer, and
  # for the same reason: the format is a handful of `key=value' and anything
  # else is not ours.  An id we cannot read is served all the same, under the
  # empty name: the host will not recognise it, which is exactly the outcome a
  # malformed request deserves.
  id=""
  seconds=""
  for __mrn_watch_word in $header ; do
    case "$__mrn_watch_word" in
      id=*)      id="${__mrn_watch_word#id=}" ;;
      timeout=*) seconds="${__mrn_watch_word#timeout=}" ;;
    esac
  done
  unset __mrn_watch_word
  [[ "$seconds" =~ ^[0-9]+$ ]] && [[ "$seconds" -gt 0 ]] || seconds=180

  rm -f "$__mrn_watch_exec_request" 2>/dev/null
  rm -f "$__mrn_watch_exec_done" 2>/dev/null

  started="$(date +%s 2>/dev/null)"
  status=0
  if [[ -z "$command" ]]; then
    : > "$__mrn_watch_exec_part" 2>/dev/null
  else
    __mrn_watch_bounded "$seconds" "$command" || status=$?
  fi

  if ! mv -f "$__mrn_watch_exec_part" "$__mrn_watch_exec_out" 2>/dev/null; then
    [[ "$status" -ne 0 ]] || status=1
    rm -f "$__mrn_watch_exec_part" 2>/dev/null
  fi

  # An image without `date' is not a fantasy in this work-stream (the collector
  # of episode 2 guards every tool it uses): both operands default to 0, hence
  # an elapsed time of 0 rather than an arithmetic error.
  elapsed=$(( $(date +%s 2>/dev/null || echo 0) - ${started:-0} ))
  [[ "$elapsed" -ge 0 ]] || elapsed=0
  lines="$(wc -l < "$__mrn_watch_exec_out" 2>/dev/null)"

  # The journal.  Not the output -- it is served in the answer and lives in
  # exec.out until the next request -- but WHAT WAS RUN, when, and how it
  # ended.  The `!! FAILED (status N)' line is the shape episodes 1, 2 and 4
  # already use, so that a single grep answers for a machine, a router, a
  # switch, and now for what the channel itself injected.
  {
    printf '## exec %s (%s): %s\n' \
      "${id:-?}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" "$command"
    printf '## %s line(s) of output in %ss\n' "${lines:-0}" "$elapsed"
    if [[ "$status" -eq 124 ]]; then
      printf '!! FAILED (status %s: timed out after %ss)\n' "$status" "$seconds"
    elif [[ "$status" -ne 0 ]]; then
      printf '!! FAILED (status %s)\n' "$status"
    fi
  } >> "$__mrn_watch_exec_log" 2>/dev/null

  printf 'id=%s status=%s epoch=%s lines=%s seconds=%s\n' \
    "$id" "$status" "$(date +%s 2>/dev/null)" "${lines:-0}" "$elapsed" \
    > "$__mrn_watch_exec_done" 2>/dev/null
  sync 2>/dev/null
  return 0
}

while : ; do
  if [[ -e "$__mrn_watch_request" && -r "$__mrn_watch_producer" ]]; then
    __mrn_watch_do_report
  fi
  if [[ -e "$__mrn_watch_exec_request" ]]; then
    __mrn_watch_do_exec
  fi
  sleep "$__mrn_watch_period"
done
