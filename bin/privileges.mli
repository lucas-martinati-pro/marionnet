(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2026  Jean-Vincent Loddo
   Copyright (C) 2026  Université Sorbonne Paris Nord

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>. *)

(** Granting Marionnet, from the GUI and at the moment it is needed, one of the
    optional sudoers blocks its bridges require (work-stream
    [modernisation-world-bridge], episode 6; the blocks themselves are
    [docs/modernisation-world-bridge.md] § 1 bis.3).

    The sudoers rule of this program comes in three blocks, and they are not
    granted by the same person: block (a) — the ghost taps, without which nothing
    at all works — is installed by the {b administrator} when Marionnet is
    installed, whereas (b) the private NAT bridge and (c) the LAN bridge are
    activated by the {b end user}, from the GUI, the first time a component needs
    them. This module is the user's side of that: it asks for the password with a
    dialog of ours, and hands it to [sudo -S].

    {b Why [sudo] and not [pkexec]}: [sudo] is already a hard dependency of
    Marionnet ({!Tap_provider} rests on it entirely), so using it assumes nothing
    about the distribution — PolicyKit is missing from minimal systems and from
    containers.

    {b What is never done here}: the sudoers text is not written, not even read.
    It belongs to [bin/scripts/marionnet-sudoers.sh], the single source of every
    rule; this module only runs that script with the right selector. And the
    selector always includes [--only], so that activating a bridge never rewrites
    the file carrying block (a) — which may well have been granted, by the
    administrator, to somebody who is not the user sitting here. *)

(** Make sure the scoped sudoers block of the private NAT bridge is installed,
    asking the user for their password if that is what it takes. The sequence:
    probe ({!Nat_bridge.is_usable}), then try without a password (a live [sudo]
    ticket is enough), then the dialog — up to three attempts. Returns [Ok ()]
    when the probe finally succeeds, and an [Error] carrying the script's own
    diagnostic otherwise; a user who cancels is an [Error] too, a polite one.
    ---
    A failure also SHOWS itself, once: the explanatory dialog — and the command to
    type in a terminal to grant the rights later — is displayed here rather than by
    the caller, because starting one component goes through this function several
    times. The failed verdict is remembered for the session, so a user who says no
    is not asked again; to change their mind, they restart Marionnet or run the
    script by hand. A success needs no such memory ({!Nat_bridge.is_usable} then
    answers [true] and the call returns at once).
    ---
    Safe to call from any thread: the dialog it may open goes through
    [GMain_actor]. In a driven session (script mode) it never blocks — the dialog
    refuses to ask and the call fails plainly. *)
val ensure_natbridge : unit -> (unit, string) result
