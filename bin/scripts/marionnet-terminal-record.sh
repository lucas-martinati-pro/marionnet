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
# Host-side RECORDING OF THE STUDENT'S TERMINAL.  Deep logging, episode 8.
#
# Marionnet deposits this file into the working directory of the project and
# hands it to the UML kernel as the terminal emulator, by substituting the FIRST
# field of `xterm=<emulator>,<title switch>,<exec switch>' (simulation_level.ml)
# -- the very field MARIONNET_TERMINAL configures. The kernel then runs us where
# it would have run the emulator, with the argv it had prepared:
#
#   <us> -T "Virtual Console #0 (m1)" -e /usr/lib//uml/port-helper -uml-socket /tmp/xterm-pipeXXX
#
# and we relaunch the REAL emulator with script(1) around the command that
# follows the exec switch. What crosses that terminal -- what the guest prints
# and what the student types, echoed by the guest -- is written to a file on the
# host, where the student cannot rewrite it (decision D2, the same reason the
# console of episode 6 is recorded host-side).
#
# WHY NOT UML_PORT_HELPER.  Measured, twice: the variable exists in the 6.12
# kernel but belongs to the `port:' channel (port_user.c). The `xterm' channel
# runs /usr/lib//uml/port-helper hardcoded -- the variable was present in the
# UML process's environment and was ignored. Substituting the emulator is the
# only hook the kernel offers here.
#
# WHY script(1) AND NOT A TEE.  The port-helper hands ITS OWN terminal's file
# descriptor to the kernel (sendmsg/SCM_RIGHTS) and then sleeps: no byte ever
# passes through it, so nothing can be intercepted downstream. script(1) puts a
# pty in between -- exactly what is needed -- and it comes from bsdutils, which
# is `Essential: yes': nothing to declare as a dependency.
#
# WHY IT SOURCES NO LIBRARY, bashbricks included.  The kernel execs us with a
# reduced environment and PATH=:/bin:/usr/bin/:/usr/lib//uml, from a directory
# that has no relation to the source tree; and a terminal that fails to open is
# a student who cannot work. Hence: no source-ing, no subshell we can avoid, and
# a fallback that runs the real emulator untouched whenever anything is missing.
# Same reasoning as the other deposited scripts of this work-stream.
#
# THREE VARIABLES, read from the environment of the UML process (Marionnet sets
# them per process, see `terminal_recording' in simulation_level.ml):
#
#   MARIONNET_TERMINAL_RECORD_BINARY       the real terminal emulator
#   MARIONNET_TERMINAL_RECORD_EXEC_SWITCH  its "run this command" switch (-e)
#   MARIONNET_TERMINAL_RECORD_LOG          where the session is written
# ---------------------------------------------------------------------------

binary="${MARIONNET_TERMINAL_RECORD_BINARY:-}"
exec_switch="${MARIONNET_TERMINAL_RECORD_EXEC_SWITCH:-}"
log="${MARIONNET_TERMINAL_RECORD_LOG:-}"

# The fallback of last resort: whatever is wrong with the recording, the window
# must open. Note `xterm' as the ultimate default, matching Marionnet's own.
fallback() {
  exec "${binary:-xterm}" "$@"
}

[[ -n $binary && -n $exec_switch && -n $log ]] || fallback "$@"
command -v script >/dev/null 2>&1 || fallback "$@"

# Split the argv the kernel prepared: everything before the exec switch belongs
# to the emulator (typically `-T <title>'), everything after it is the command
# to run inside the window (the port-helper and its socket).
head=(); tail=(); seen=0
for argument in "$@"; do
  if (( seen )); then
    tail+=("$argument")
  elif [[ $argument == "$exec_switch" ]]; then
    seen=1
  else
    head+=("$argument")
  fi
done
(( seen )) && (( ${#tail[@]} > 0 )) || fallback "$@"

# script(1) runs its --command through a shell, so the command is rebuilt quoted
# rather than passed as several words. printf %q is exact for this.
printf -v command '%q ' "${tail[@]}"
command="${command% }"

# Can the journal be written at all? Answering now, rather than letting script(1)
# fail inside the window with the terminal already gone.
: >> "$log" 2>/dev/null || fallback "$@"

# --log-timing makes the session replayable with scriptreplay(1); --flush keeps
# the file usable WHILE the machine runs, which is what the control channel
# serves under the journal name `terminal'.
exec "$binary" "${head[@]}" "$exec_switch" \
     script --quiet --flush --log-timing="$log.timing" --command "$command" "$log"
