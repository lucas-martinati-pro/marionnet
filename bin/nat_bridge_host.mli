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
    the [gc] of a crashed run is exact. A process may hold several of them, one
    per component asking for one, told apart by an {e instance} number exactly as
    the taps are: [mnbr<pid>-<n>]. Passing no instance keeps the unsuffixed name,
    which is what the single bridge of a process was called before.

    {b Allocating} that number is not this module's business: it belongs to
    whoever owns the components, since it is one of them per bridge. Here a
    number is only a key. *)

(** What the caller needs in order to configure a guest behind the bridge. *)
type t = {
  bridge       : string;      (** [mnbr<pid>] or [mnbr<pid>-<n>], the name to attach a tap to *)
  subnet       : string;      (** the /24 prefix, e.g. ["192.168.101"] *)
  host_address : string;      (** the bridge's own address, [<subnet>.1] *)
  gateway      : string;      (** what a guest must use as default route *)
  guest_range  : string;      (** human-readable, e.g. ["192.168.101.2-192.168.101.254"] *)
  owner_pid    : int;         (** the pid the artefacts are named after *)
  instance     : int option;  (** the instance number, [None] for the unsuffixed name *)
}

(** A failure as the script reports it: [code] is one of its closed enumeration
    ([E_SUDO_DENIED], [E_NO_FREE_SUBNET], [E_BAD_PID], [E_INTERNAL]…), [message]
    the human diagnostic. The code is what a caller may branch on; the message is
    what it may show. *)
type error = { code : string; message : string }

val string_of_error : error -> string

(** [up ?subnet ?dhcp ?ipv6 ?radvd ?instance ()] creates one bridge of this
    process and its NAT rules, and is idempotent: on a bridge that already exists
    it succeeds and returns its addressing. [?subnet] forces a /24 prefix
    (e.g. ["192.168.101"]) instead of letting the script pick the first one free
    of the host's routes; [?dhcp] (default [false]) also leaves a DHCP/DNS server
    bound to that bridge alone — it needs [dnsmasq] on the host, whose absence is
    a clean refusal ([E_NO_DNSMASQ]) {e before} anything is built; [?instance]
    names the bridge [mnbr<pid>-<n>] instead of [mnbr<pid>].

    [?ipv6] is the IPv6 address of the bridge, always of the shape
    [<prefix>::1/64] (e.g. ["fd00:192:168:101::1/64"]): it addresses the bridge
    and masquerades that /64 to the outside. [?radvd] (default [false]) also
    advertises the prefix, so that the guests configure themselves by SLAAC, with
    the bridge as default router and DNS server; it is meaningless without
    [?ipv6], and is then not even passed on.

    {b Both are ignored, with a warning and not an error, on a host with no IPv6
    uplink} — no global address, or no default route (see {!has_ipv6_uplink}).
    Announcing a router that cannot route would be a lie, and the component had
    better start in IPv4 than not start at all: unlike [?dhcp], IPv6 is something
    the user opts into, so skipping it takes away nothing that used to work. *)
val up : ?subnet:string -> ?dhcp:bool -> ?ipv6:string -> ?radvd:bool ->
         ?instance:int -> unit -> (t, error) result

(** Removes one bridge of this process and every rule tagged with its name — the
    one designated by [?instance], as {!up} named it. Idempotent, and honest: it
    fails if something could not be removed. *)
val down : ?instance:int -> unit -> (unit, error) result

(** Removes the artefacts of {e dead} owners only — the counterpart of
    {!Tap_provider.purge_orphan_taps}, to be called once at start-up. *)
val gc : unit -> (unit, error) result

(** Every NAT bridge currently on this host, ours and other processes'. Reading
    the [instance] of those whose [owner_pid] is ours is how a caller knows which
    numbers are already taken, without any state file. *)
val status : unit -> (t list, error) result

(** [ensure ?instance ()] is [up] memoised {e per instance}: a second call with
    the same [?instance] returns the bridge built by the first one, a call with
    another one builds another bridge (another /24). The first success also
    registers the [at_exit] that tears down {e every} bridge this process holds,
    so that they live and die with Marionnet. This is what a component calls when
    it needs a bridge.
    ---
    [?subnet], [?dhcp], [?ipv6] and [?radvd] are read on the call that really
    builds the bridge, and ignored by the ones the memo answers: changing any of
    them takes a {!release} first — which is precisely what a component does when
    it stops. *)
val ensure : ?subnet:string -> ?dhcp:bool -> ?ipv6:string -> ?radvd:bool ->
             ?instance:int -> unit -> (t, error) result

(** [release ?instance ()] gives back one bridge of this process: {!down} on it,
    and the memo of {!ensure} forgotten, so that a later [ensure] with the same
    number builds a bridge again instead of handing back one that has gone. This
    is what a component calls when it stops — the [at_exit] of {!ensure} does the
    same for whatever is still held when the program leaves.
    ---
    The memo is dropped even when the removal failed: a phantom entry would be a
    worse lie than the leftover, which the [gc] of a later run collects anyway. *)
val release : ?instance:int -> unit -> (unit, error) result

(** Whether this host can do IPv6 at all: a global IPv6 address {e and} a default
    IPv6 route. It is the single predicate behind everything IPv6 in this
    work-stream — the dialog greys its three IPv6 fields out when it is [false],
    and {!up} skips its IPv6 legs for the same reason — which is why it is asked
    of the host command ([check-ipv6], no privilege needed) rather than computed a
    second time here.

    {b Not memoised}, on purpose: the answer changes without Marionnet doing
    anything (a Wi-Fi association, a tethered phone, a VPN), so it is asked again
    every time it matters. A host command that cannot be run answers [false]. *)
val has_ipv6_uplink : unit -> bool

(** Whether the auxiliary command can be run at all, and without a password
    (i.e. whether the scoped sudoers rule of [marionnet-sudoers.sh] is in
    place, and {e sufficient}). Probed once, by [check-privileges]: a real
    privileged command of our own list, on a bridge name no run can produce,
    with no effect on anything. A probe reading less than that — [status], used
    until 2026-09-02, asks the host nothing privileged at all (measured) — says
    "usable" on a machine where the block is not installed, and the refusal then
    surfaces at {!up}, where nobody can offer the password any more. *)
val is_usable : unit -> bool

(** Drop the memoised verdict of {!is_usable}, so that the next call probes the
    host again. The one caller that needs it is {!Privileges}, which has just
    installed the sudoers block that {!is_usable} answered [false] about. *)
val forget_usability : unit -> unit
