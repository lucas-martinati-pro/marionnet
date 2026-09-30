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
# xterm WITH HOST CLIPBOARD SUPPORT. Every terminal Marionnet opens on the
# host (UML consoles, router telnet terminals, switch unixterm terminals)
# goes through this wrapper instead of calling xterm directly
# (simulation_level.ml), so that copy-paste between the PC and the guests
# works with the gestures everybody already knows.
#
# THE PROBLEM. Out of the box xterm only knows the PRIMARY selection: what
# you select with the mouse pastes with the middle button, and nothing else.
# What you copy with Ctrl+C in a host application (browser, editor, PDF
# reader) lands on CLIPBOARD, which xterm neither reads nor writes -- so
# pasting it into a guest console was impossible, and copying from a guest
# console only pasted back with the middle button. Ctrl+Shift+C/V, the
# gesture gnome-terminal and every modern emulator honour, did nothing.
#
# WHAT THIS DOES. One X resource, passed with -xrm so that no ~/.Xresources
# is needed and a customised host stays untouched:
#
#   XTerm*VT100.translations: #override ...
#     Ctrl Shift C: copy-selection(CLIPBOARD, PRIMARY, CUT_BUFFER0)
#       -- copies the selection to every seat at once;
#     Ctrl Shift V / Shift Insert: insert-selection(CLIPBOARD, PRIMARY, CUT_BUFFER0)
#       -- pastes CLIPBOARD first (what Ctrl+C put there on the host), and
#        falls back on PRIMARY, so the old select-then-middle-click habit
#        keeps working too (PC -> guest).
#
# Copying is EXPLICIT, as in gnome-terminal: a mouse selection in the guest
# does not publish itself to the host clipboard, so selecting something in
# the terminal never clobbers what was copied on the host before pasting.
# (An earlier version set selectToClipboard for that auto-publishing, and it
# was removed for exactly this reason: convenient until it eats your copy.)
#
# Ctrl+C alone is deliberately left untouched: in the guest shell it is
# SIGINT, and stealing it would break every running program. This mirrors
# gnome-terminal, where copy/paste take the Shift variant for the same reason.
#
# WHICH EMULATOR RUNS. The FIRST field of MARIONNET_TERMINAL names it, and
# the UML kernel offers no room for extra arguments -- which is why this
# wrapper exists at all. Marionnet hands that name over in
# MARIONNET_XTERM_BINARY (simulation_level.ml); it may be `xterm', `uxterm',
# an `xterm-*' variant or a path, and it is honoured verbatim: what ran
# before this wrapper existed still runs, with clipboard bindings added.
# Unset, it defaults to `xterm'.
#
# WHY IT SOURCES NO LIBRARY, bashbricks included. The UML kernel execs the
# terminal emulator with a reduced environment (PATH=:/bin:/usr/bin) from a
# directory unrelated to the source tree; a terminal that fails to open is a
# student who cannot work. Same reasoning as marionnet-terminal-record.sh:
# no sourcing. Note the leading empty PATH element means the current
# directory: `command -v' below and the kernel's own execvp agree on that
# lookup, so both see the same program.
# ---------------------------------------------------------------------------

binary="${MARIONNET_XTERM_BINARY:-xterm}"

# Never run ourselves: MARIONNET_XTERM_BINARY is user-controlled (it comes
# from MARIONNET_TERMINAL), and exec'ing this very script would loop until
# the process table is full. The OCaml side already filters this spelling
# out (is_xterm_binary), this is the belt to its suspenders.
if [[ $(basename -- "$binary") == "marionnet-xterm.sh" ]]; then
  echo "marionnet-xterm.sh: refusing to run itself (MARIONNET_XTERM_BINARY='$binary'); falling back to xterm" >&2
  binary=xterm
fi

# A rejected resource only warns on stderr -- deliberately left visible, it
# is the message explaining a broken paste -- so reaching `exec' means the
# window is as good as open. (There is no second attempt behind it: once
# `exec' succeeds the shell is gone, and if it cannot even start, bash
# says so itself. The missing-binary case is the one answered here.)
if command -v "$binary" >/dev/null 2>&1; then
  exec "$binary" \
    -xrm 'XTerm*VT100.translations: #override Ctrl Shift <Key>C: copy-selection(CLIPBOARD, PRIMARY, CUT_BUFFER0)\nCtrl Shift <Key>V: insert-selection(CLIPBOARD, PRIMARY, CUT_BUFFER0)\nShift <Key>Insert: insert-selection(CLIPBOARD, PRIMARY, CUT_BUFFER0)' \
    "$@"
else
  echo "marionnet-xterm.sh: terminal emulator '$binary' not found in PATH" >&2
  exit 127
fi
