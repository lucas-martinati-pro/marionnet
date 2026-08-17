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

(** The automatic LAN bridge: the host's own network card, enslaved to a bridge
    Marionnet builds, so that the virtual machines sit on the {e real} local
    network — real addresses, the LAN's own DHCP and DNS, the other machines of
    the room (work-stream [modernisation-world-bridge], option B of
    [docs/modernisation-world-bridge.md], episode 7b).

    {b This module implements nothing.} The whole [ip] sequence — build the
    bridge, clone the card's MAC, move the address and the default route onto it,
    enslave the card, and unwind all of it in the only order that works — lives in
    the auxiliary host command [marionnet-lanbridge.sh], installed beside this
    program; here we only run it and read its JSON report. Same reason as
    {!Nat_bridge_host}: that script is also the source from which the sudoers rule
    is derived, and a second copy of the sequence in OCaml would be a second truth
    to keep in step with it.

    {b What makes it different from {!Nat_bridge_host}}, and it is not a detail:
    the NAT bridge never touches the host interface, this one {e is} the host
    interface. Two consequences the caller must know about:

    - {b there is exactly one LAN bridge per host}, [mnlan0], not one per process:
      a card has exactly one master, so several Marionnet instances {e share} it,
      exactly as they used to share the [br0] built by hand. Hence no instance
      number here, and hence a {!down} that refuses as long as another live
      process still has a tap on the bridge;
    - {b it can fail for reasons that are not failures}: [E_WIRELESS] (an access
      point refuses several MAC addresses behind one association — that is what
      the NAT bridge is for), [E_ALREADY_ENSLAVED], [E_NO_ADDRESS]. Those are
      answers to show, not internal errors. *)

(** What the caller needs in order to know which bridge to attach a tap to, and
    what was done to the host to get it. The optional fields are those the report
    leaves out when the bridge has no card of its own yet. *)
type t = {
  bridge     : string;         (** always [mnlan0], the name to attach a tap to *)
  interface  : string option;  (** the host card enslaved to it, e.g. ["eth0"] *)
  mac        : string option;  (** the card's hardware address, cloned onto the bridge *)
  gateway    : string option;  (** the default gateway, now reached through the bridge *)
  addresses  : string list;    (** the host addresses moved onto it, as [ip addr] argv *)
  owner_pid  : int;            (** the pid stamped in the bridge alias *)
  adopted    : bool;           (** the bridge was already there: the shared, and normal, case *)
}

(** A failure as the script reports it: [code] is one of its closed enumeration
    ([E_WIRELESS], [E_ALREADY_ENSLAVED], [E_NO_ADDRESS], [E_NO_DEFAULT_ROUTE],
    [E_AMBIGUOUS_ROUTE], [E_SUDO_DENIED], [E_ROLLBACK_INCOMPLETE], [E_INTERNAL]…),
    [message] the human diagnostic. The code is what a caller may branch on; the
    message is what it may show. *)
type error = { code : string; message : string }

val string_of_error : error -> string

(** [up ?interface ()] builds the LAN bridge and moves the host onto it, and is
    idempotent: on a bridge that already exists it succeeds, adopts it and says so
    ([adopted = true]) — which is what happens whenever a second component, or a
    second Marionnet, asks for it. [?interface] forces the card instead of letting
    the script take the one carrying the IPv4 default route.
    ---
    {b The host loses its network for a fraction of a second} while the address
    moves. A failure at any step is rolled back to the state found on entry. *)
val up : ?interface:string -> unit -> (t, error) result

(** Gives the host its card back — {e if} nobody else is using the bridge any
    more. Being shared, it survives a [down] as long as a live process has a tap
    on it, and that is a success, not an error: the caller has said what it had to
    say, and the returned boolean says which of the two happened ([true] = the
    bridge was really removed and the host is back as it was). [~force:true]
    dismantles it all the same, and takes somebody else's virtual machines off the
    network with it; nothing in Marionnet does that. *)
val down : ?force:bool -> unit -> (bool, error) result

(** [ensure ()] is {!up} memoised: the second component to ask gets the bridge
    built for the first one, without running anything. The first success also
    registers the [at_exit] that gives the host back its card when Marionnet
    leaves, so that a crash of the GUI cannot keep the machine reconfigured.
    This is what a component calls when it starts. *)
val ensure : ?interface:string -> unit -> (t, error) result

(** [release ()] is what a component calls when it stops: {!down}, and — {e only
    if the bridge was really removed} — the memo of {!ensure} forgotten, so that a
    later [ensure] builds it again instead of handing back one that has gone.
    A bridge kept because somebody else is still on it is still ours to give back
    later, hence still memoised.
    ---
    Calling it while holding nothing does nothing at all, on purpose: this bridge
    is the host's own card, and a [down] nobody asked for could dismantle the
    bridge another Marionnet has just built and not yet attached a tap to. *)
val release : unit -> (unit, error) result

(** Whether the privileged commands of the LAN bridge can be run {e without a
    password}, i.e. whether block (c) of [marionnet-sudoers.sh] is in place.
    ---
    Probed once, by the [check-privileges] sub-command of the script — [status]
    could not answer it, since it reads the host with an unprivileged [ip] and
    therefore succeeds either way. Like {!Tap_provider.is_usable}, the answer is
    "without a password {e right now}": a live [sudo] ticket makes it [true] with
    no rule of ours installed, which is the correct answer to the only question
    the caller asks — must the user be interrupted? *)
val is_usable : unit -> bool

(** Drop the memoised verdict of {!is_usable}, so that the next call probes the
    host again. The one caller that needs it is {!Privileges}, which has just
    installed the sudoers block that {!is_usable} answered [false] about. *)
val forget_usability : unit -> unit
