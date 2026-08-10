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
# Guest-side journal, EPILOGUE.  Deep logging, episode 1.
#
# Companion of `marionnet-relay.00-journal', deposited by the same host code
# and sourced by the same relay loop, but AFTER the user's `.rcfile' (the loop
# globs in alphabetical order: 00- < rcfile < zz-).  Its whole job is to undo
# what the prologue installed:
#
#   - stop tracing, drop the ERR trap, put PS4 back;
#   - give the relay its standard descriptors back (kept in 3 and 4), which is
#     what stops the capture from leaking over the end of the boot;
#   - let the `tee' see its end of file and wait for it, so that the journal is
#     complete host-side even if the machine is inspected right away.
#
# Episode 2 of the `journalisation-profonde' work-stream will graft the
# collector (dmesg, journalctl -b, systemctl --failed) at the end of this same
# file: it belongs here, after the capture is closed, and it needs no change to
# the prologue.
#
# Like its companion: plain Bash (no bashbricks inside a guest), everything
# guarded, and never fatal to a boot.
# ---------------------------------------------------------------------------

if [[ -n "$__mrn_journal_log" ]]; then

  { set +x ; } 2>/dev/null
  __mrn_journal_tracing=""

  # --- Drop our ERR trap and put back the one the relay may have had:
  trap - ERR
  unset -f __mrn_journal_on_error 2>/dev/null
  if [[ -n "$__mrn_journal_err_trap" ]]; then
    eval "$__mrn_journal_err_trap" 2>/dev/null
  fi
  [[ "$__mrn_journal_E_was_on" = yes ]] || set +o errtrace
  PS4="$__mrn_journal_ps4"

  echo "# end of the startup configuration: $(date '+%F %T %z' 2>/dev/null)"

  # --- Close the capture: the relay writes again where it used to, and the
  #     `tee' (if any) sees the end of its input:
  exec 1>&3 2>&4 3>&- 4>&-

  # --- Wait for the journal to be actually flushed.  `wait' works because the
  #     process substitution is a child of this shell; the bounded loop covers
  #     the Bash versions where it is not considered a job:
  if [[ -n "$__mrn_journal_tee_pid" ]]; then
    wait "$__mrn_journal_tee_pid" 2>/dev/null || {
      __mrn_journal_i=0
      while kill -0 "$__mrn_journal_tee_pid" 2>/dev/null && [[ $__mrn_journal_i -lt 50 ]]; do
        sleep 0.1
        __mrn_journal_i=$((__mrn_journal_i + 1))
      done
      unset __mrn_journal_i
    }
  fi

  # --- Marionnet's own debug mode (`-d') had put xtrace on before we did:
  [[ "$__mrn_journal_x_was_on" = yes ]] && set -x

  unset __mrn_journal_ps4 __mrn_journal_err_trap __mrn_journal_tee_pid
  unset __mrn_journal_x_was_on __mrn_journal_E_was_on __mrn_journal_tracing
fi

:
