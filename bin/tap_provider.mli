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

(** Privileged tap provider: the `sudo -n ip ...' replacement for the former
    permanent root service marionnet-daemon (chantier
    `marionnet-daemon-elimination', see docs/daemon-elimination-study.md).

    It reproduces the daemon's network contract exactly -- only the syntax moves
    from the dead net-tools/uml-utilities to iproute2:

    {v
    tunctl -u UID -t NAME                              -> ip tuntap add dev NAME mode tap user USER
    ifconfig NAME 172.23.0.254 netmask 255.255.255.255 up
                                                       -> ip addr add 172.23.0.254/32 dev NAME
                                                          ip link set NAME up
    route add IP42 NAME                                -> ip route add IP42/32 dev NAME
    ifconfig NAME down && tunctl -d NAME               -> ip link del NAME
    v}

    The privilege is granted by a scoped NOPASSWD sudoers rule confined to the
    tap prefix below; the rule text lives in ONE place, the shell script
    bin/scripts/marionnet-sudoers.sh, which both `make install-final-as-root'
    and {!ensure_sudoers_rule} call. That rule is narrower than what it replaces:
    the daemon's 0666 socket offered these same tap creations to every local
    account, with no admin opt-in.

    Client sites: Simulation_level (the eth42 taps, episode 2) and World_bridge
    (the bridge taps, episode 3) — the daemon has no caller left. *)

type tap_name = string

(** The host address carried by every eth42 tap, as UML expects it in
    "eth42=tuntap,<tap>,<mac>,172.23.0.254". Same value for all the taps. *)
val eth42_host_address : string

(** The interface name prefix owned by Marionnet ("mtap"); it bounds the scope of
    the sudoers rule. Names are "mtap<pid>-<seq>": the embedded pid is what makes
    {!purge_orphan_taps} exact and safe with several Marionnet instances. *)
val tap_prefix : string

(** [make_eth42_tap ~uid ~ip42] creates a fresh persistent tap owned by [uid],
    carrying {!eth42_host_address}/32, up, and routing the host-specific [ip42]
    (which must belong to the 172.23. ghost network) to it. Returns the generated
    name, to be handed to UML. On failure nothing is left behind (the partially
    built tap is removed) and the error message is meant to be shown to the user. *)
val make_eth42_tap : uid:int -> ip42:string -> (tap_name, string) result

(** [make_bridge_tap ~uid ~bridge] creates a fresh persistent tap owned by [uid],
    promisc, up, attached to the (preexisting, admin-managed) [bridge] — the
    world_bridge contract of the daemon's AnySocketTap. Returns the generated
    name, to be handed to `vde_switch -tap'. On failure nothing is left behind
    and the error message is meant to be shown to the user. *)
val make_bridge_tap : uid:int -> bridge:string -> (tap_name, string) result

(** Best-effort, idempotent destruction: the tap, its address and its route
    (`ip link del' also detaches it from its bridge, if any).
    Only accepts names of taps created by this process. *)
val destroy_tap : tap_name -> unit

(** Garbage-collect the taps left over by DEAD Marionnet processes (a crashed
    GUI), and return how many were removed. This is what replaces the daemon's
    keep-alive/timeout collector. Taps of a live process -- ours or another
    instance's -- are never touched. Meant to be called once at start-up. *)
val purge_orphan_taps : unit -> int

(** Can we really run our privileged commands, i.e. is the sudoers rule in place?
    Probed by deleting a tap that does not exist: a successful no-op when the rule
    is there, a `sudo -n' refusal otherwise. It never prompts and creates nothing.
    The result is cached until {!ensure_sudoers_rule} runs. A [false] here is the
    hook for the degraded mode (formerly Daemon_client.disable_daemon_support,
    with the late daemon). *)
val is_usable : unit -> bool

(** The sudoers rule that {!is_usable} needs, as the script would install it.
    For display in a dialog / in the log. [user] defaults to the current user. *)
val sudoers_rule : ?user:string -> unit -> (string, string) result

(** bin/scripts/marionnet-sudoers.sh, the single source of every sudoers rule of
    this program: its bare name (it is installed in the PATH), or whatever
    [MARIONNET_SUDOERS_SCRIPT] says in a source tree. Published because it is not
    ours alone: {!Privileges} runs the very same script to activate the scoped
    blocks the bridges need, and a second reading of that variable would be a
    second truth. *)
val sudoers_script : unit -> string

(** Install the sudoers rule if it is missing, by calling
    bin/scripts/marionnet-sudoers.sh (which re-executes itself with sudo).
    Beware: this INHERITS the standard channels, so it only works when Marionnet
    was started from a terminal -- wiring it to the GUI (a terminal, or pkexec,
    plus an explanatory dialog) belongs to the switch episode. *)
val ensure_sudoers_rule : unit -> (unit, string) result
