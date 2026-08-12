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
# Guest-side ON-DEMAND REPORT WATCHER.  Deep logging, episode 16.
#
# This file belongs to NO guest image.  The host deposits it into the hostfs at
# every boot (`make_hostfs_content', bin/simulation_level.ml) and the epilogue
# `marionnet-relay.zz-journal' starts it in the background at the end of the
# boot.  Its name deliberately does NOT match the relay's `marionnet-relay*'
# glob: it must be started, not sourced.
#
# WHY IT EXISTS.  Episode 15 measured five real labs against the channel and
# found the state of a running guest to be unobservable (M1): the five journals
# are TRACES -- what was said -- and a trace does not say what IS.  The producer
# of state, however, already exists: `marionnet-report' (episode 7) holds the
# real interfaces, the routing tables, the neighbours, `ip_forward' and the
# firewall in replayable form.  What was missing was a TRIGGER: that report was
# written at shutdown only.  This watcher is that trigger, and nothing more.
#
# It also buys back a case episode 7 had to give up: the old SysV images
# (wheezy, guignol) answer the ctrl-alt-del with `/sbin/halt' and never run
# /etc/rc0.d, so their shutdown hook never fires.  Here nothing depends on the
# shutdown any more.
#
# THE PROTOCOL, and who writes what -- the hostfs is the only way back:
#
#   report.request   the HOST writes it (verb `report'), the GUEST consumes it
#   report.md        the GUEST writes it, by renaming .report.md.part onto it
#   report.done      the GUEST writes it once the rename is done; the HOST
#                    removes it BEFORE posting a request, so its reappearance
#                    is what proves the answer is a fresh one
#
# The rename is the point of `.report.md.part': the channel serves report.md as
# the sixth journal WHILE the guest runs, so a reader must never be able to see
# a report half written.  `report.done' is removed here too, before producing:
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
__mrn_watch_period=1

# --- The state this process INHERITS from the shell that started it.  The
#     epilogue starts us at the end of the boot, in the relay's own shell: the
#     prologue's xtrace and ERR trap may still be on (Marionnet's `-d' puts
#     xtrace back), and a trace here would end up on the student's console for
#     the whole life of the machine.  Dropped before anything else:
{ set +x ; } 2>/dev/null
trap - ERR 2>/dev/null
set +o errtrace 2>/dev/null

# Nothing to watch for if the producer was not deposited (an old host binary, or
# a hostfs that could not be written): better no watcher than a loop that would
# answer every request with a failure.
[[ -r "$__mrn_watch_producer" ]] || exit 0

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
if [[ -e "$__mrn_watch_request" ]]; then
  __mrn_watch_boot="$__mrn_watch_dir/boot_parameters"
  if [[ ! -e "$__mrn_watch_boot" || "$__mrn_watch_request" -ot "$__mrn_watch_boot" ]]; then
    rm -f "$__mrn_watch_request" 2>/dev/null
  fi
  unset __mrn_watch_boot
fi

while : ; do
  if [[ -e "$__mrn_watch_request" ]]; then

    # Consumed FIRST: whatever happens next, the request must not be served
    # twice.  And the stale answer goes away before the new one is produced.
    rm -f "$__mrn_watch_request" 2>/dev/null
    rm -f "$__mrn_watch_done" 2>/dev/null

    __mrn_watch_status=0
    MARIONNET_REPORT_OUT="$__mrn_watch_part" \
    MARIONNET_REPORT_WHEN=on-demand \
      /bin/bash "$__mrn_watch_producer" </dev/null >/dev/null 2>&1 \
      || __mrn_watch_status=$?

    # The rename is what publishes the report.  If it fails, the previous
    # report -- if any -- is left untouched, and the status says so.
    if ! mv -f "$__mrn_watch_part" "$__mrn_watch_out" 2>/dev/null; then
      [[ "$__mrn_watch_status" -ne 0 ]] || __mrn_watch_status=1
      rm -f "$__mrn_watch_part" 2>/dev/null
    fi

    __mrn_watch_lines="$(wc -l < "$__mrn_watch_out" 2>/dev/null)"
    printf 'status=%s epoch=%s lines=%s\n' \
      "$__mrn_watch_status" \
      "$(date +%s 2>/dev/null)" \
      "${__mrn_watch_lines:-0}" \
      > "$__mrn_watch_done" 2>/dev/null
    sync 2>/dev/null
    unset __mrn_watch_status __mrn_watch_lines
  fi
  sleep "$__mrn_watch_period"
done
