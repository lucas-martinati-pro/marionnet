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
# Guest-side journal, PROLOGUE.  Deep logging, episode 1.
#
# This file belongs to NO guest image.  The host deposits it, at every boot,
# into the hostfs directory (`make_hostfs_content', bin/simulation_level.ml),
# under the name `marionnet-relay.00-journal'.  The guest relay ends its
# startup by sourcing /mnt/hostfs/{<image>.,marionnet-}relay* in ALPHABETICAL
# order (uml/guest/marionnet-relay), hence:
#
#     marionnet-relay.00-journal   <- this prologue
#     marionnet-relay.rcfile       <- the user's startup configuration
#     marionnet-relay.zz-journal   <- the epilogue, which undoes all of this
#
# so the user's configuration is framed without touching a single image.
#
# What it buys: whatever the startup configuration prints (standard output AND
# standard error), the trace of the commands themselves, and the exit status of
# the ones that fail, all survive host-side in /mnt/hostfs/rc_config.log.  Until
# this episode, a failing rc_config left nothing at all behind.
#
# Two constraints drive every line below, both coming from the fact that this
# file is sourced INSIDE the relay's own shell (in its `start' function):
#
#   1. any redirection installed here would leak over the whole end of the boot
#      (`clear', `linuxlogo', the console banner).  So we save here what the
#      epilogue puts back: xtrace, errtrace, PS4, the ERR trap, and above all
#      the standard descriptors (kept in 3 and 4);
#   2. nothing here may break a boot.  Every step is guarded, and this file
#      always returns success.
#
# Plain Bash on purpose: this code runs inside the guest, which has no
# `bashbricks' (nor anything beyond a minimal userland).
# ---------------------------------------------------------------------------

__mrn_journal_log=/mnt/hostfs/rc_config.log

# --- Save the state the epilogue will restore:
case $- in *x*) __mrn_journal_x_was_on=yes ;; *) __mrn_journal_x_was_on=no ;; esac
case $- in *E*) __mrn_journal_E_was_on=yes ;; *) __mrn_journal_E_was_on=no ;; esac
__mrn_journal_ps4="$PS4"
__mrn_journal_err_trap="$(trap -p ERR 2>/dev/null)"

# --- The hostfs is a LIVING journal (decision D3): one boot, one file.  If it
#     cannot even be created, we degrade to a no-op rather than break the boot:
if ! { : > "$__mrn_journal_log" ; } 2>/dev/null; then
  __mrn_journal_log=""
fi

if [[ -n "$__mrn_journal_log" ]]; then

  { echo "# Marionnet guest journal (startup configuration)"
    echo "# date: $(date '+%F %T %z' 2>/dev/null)"
    echo "# host: $(uname -srm 2>/dev/null)"
  } >> "$__mrn_journal_log" 2>/dev/null

  # --- Keep the standard descriptors aside, then capture.  With `tee' the
  #     student keeps seeing the boot on the console; without it, the journal
  #     wins over the console (and says so):
  exec 3>&1 4>&2
  if type -p tee >/dev/null 2>&1; then
    exec > >(tee -a "$__mrn_journal_log") 2>&1
    __mrn_journal_tee_pid=$!
    echo "# capture: tee (console and journal)"
  else
    exec >> "$__mrn_journal_log" 2>&1
    __mrn_journal_tee_pid=""
    echo "# capture: journal only (no tee in this image)"
  fi

  # --- A sourced file does not abort on error: the exit status of a failing
  #     command would be lost.  This trap is what makes it visible.  `errtrace'
  #     extends it to the functions and subshells of the configuration:
  #     Tracing is suspended inside the trap and put back on the way out: the point of the
  #     journal is a readable failure, not the trace of the reporting machinery itself.
  __mrn_journal_on_error() {
    local __mrn_status=$?
    { set +x ; } 2>/dev/null
    echo "!! FAILED (status $__mrn_status): $BASH_COMMAND"
    if [[ -n "$__mrn_journal_tracing" ]]; then { set -x ; } 2>/dev/null; fi
  }
  __mrn_journal_tracing=yes
  set -o errtrace
  trap '__mrn_journal_on_error' ERR

  PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
  set -x
fi

:
