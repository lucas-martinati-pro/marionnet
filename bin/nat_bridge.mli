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

(** The automatic private NAT bridge: a Linux bridge that Marionnet creates and
    destroys by itself, giving the virtual machines access to the Internet
    without ever touching the host interface (work-stream
    [modernisation-world-bridge], option A of [docs/modernisation-world-bridge.md]).

    {b This module implements nothing.} The whole [ip] / [iptables] sequence
    lives in the auxiliary host command [marionnet-natbridge.sh], installed
    beside this program; here we only run it and read its JSON report. The
    reason is deliberate: a second copy of that sequence, written in OCaml,
    would be a second truth to keep in step with the sudoers rule — which is
    itself derived from what the script publishes.

    Relation to {!Tap_provider}: complementary and independent. [Tap_provider]
    makes the tap and attaches it to a bridge; this module makes the bridge such
    a tap can be attached to. Attaching needs no change: it never cared where the
    bridge came from.

    Naming follows [Tap_provider]: the bridge is [mnbr<pid>], where [<pid>] is
    {e this} process, so that a bridge is always attributable to its owner and
    the [gc] of a crashed run is exact. *)

(** What the caller needs in order to configure a guest behind the bridge. *)
type t = {
  bridge       : string;  (** [mnbr<pid>], the name to attach a tap to *)
  subnet       : string;  (** the /24 prefix, e.g. ["192.168.101"] *)
  host_address : string;  (** the bridge's own address, [<subnet>.1] *)
  gateway      : string;  (** what a guest must use as default route *)
  guest_range  : string;  (** human-readable, e.g. ["192.168.101.2-192.168.101.254"] *)
  owner_pid    : int;     (** the pid the artefacts are named after *)
}

(** A failure as the script reports it: [code] is one of its closed enumeration
    ([E_SUDO_DENIED], [E_NO_FREE_SUBNET], [E_BAD_PID], [E_INTERNAL]…), [message]
    the human diagnostic. The code is what a caller may branch on; the message is
    what it may show. *)
type error = { code : string; message : string }

val string_of_error : error -> string

(** [up ?subnet ()] creates the bridge of this process and its NAT rules, and is
    idempotent: on a bridge that already exists it succeeds and returns its
    addressing. [?subnet] forces a /24 prefix (e.g. ["192.168.101"]) instead of
    letting the script pick the first one free of the host's routes. *)
val up : ?subnet:string -> unit -> (t, error) result

(** Removes the bridge of this process and every rule tagged with its name.
    Idempotent, and honest: it fails if something could not be removed. *)
val down : unit -> (unit, error) result

(** Removes the artefacts of {e dead} owners only — the counterpart of
    {!Tap_provider.purge_orphan_taps}, to be called once at start-up. *)
val gc : unit -> (unit, error) result

(** Every NAT bridge currently on this host, ours and other instances'. *)
val status : unit -> (t list, error) result

(** [ensure ()] is [up] memoised: the first successful call also registers the
    [at_exit] that tears the bridge down, so that the bridge lives and dies with
    Marionnet. This is what a component calls when it needs a bridge; it may be
    called from any number of components. *)
val ensure : ?subnet:string -> unit -> (t, error) result

(** Whether the auxiliary command can be run at all, and without a password
    (i.e. whether the scoped sudoers rule of [marionnet-sudoers.sh] is in
    place). Probed once, with a read-only sub-command. *)
val is_usable : unit -> bool
