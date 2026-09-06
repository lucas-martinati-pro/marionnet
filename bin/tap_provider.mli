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

(** The OTHER Marionnet sessions running right now, as (pid, number of taps)
    couples sorted by pid: the live processes -- ours excepted -- owning taps of
    our prefix. Nothing forbids two simultaneous sessions, but every session
    gives {!eth42_host_address} to its taps and numbers its virtual machines
    from scratch, so two machines of two sessions end up claiming the very same
    172.23.x.y address: the second one to start gets no route, hence no network,
    although it boots. Detecting this costs no privilege at all (a plain
    `ip -o link show'), which is why the caller must not hide it behind
    {!is_usable}. *)
val other_live_sessions : unit -> (int * int) list

(** [colliding_session_of_address address] tells whether [address] is already
    routed to a tap of ANOTHER live session, and names that tap and its process.
    Meant to be called after a failure of {!make_eth42_tap}, to turn the raw
    iproute2 diagnostic ("File exists") into the real reason. *)
val colliding_session_of_address : string -> (tap_name * int) option

(** [sessions_of_taps names] is the decision behind {!other_live_sessions},
    applied to a list of interface names instead of the host's own: names that
    are not ours are ignored, and so are the taps of dead processes and of this
    very process. Exposed to be proved without creating real interfaces
    (bin/tap_provider_test.ml), which needs a privilege the test does not have. *)
val sessions_of_taps : tap_name list -> (int * int) list

(** [route_device_of_output output] extracts the routed device from an
    `ip -o route show ADDRESS' output. Exposed for the same reason. *)
val route_device_of_output : string -> tap_name option

(** Why we cannot create taps, when we cannot. Three reasons, and telling them
    apart is the whole point: reporting them all as "the sudoers rule is not
    installed" sent a user whose container had no {e device} to run a command that
    could change nothing (measured on a MarioNUM workstation). *)
type unavailability =
  | No_tun_device        (** [/dev/net/tun] is missing: nothing can create a tap here *)
  | No_permission        (** the kernel refuses [TUNSETIFF]: no [CAP_NET_ADMIN] *)
  | No_sudoers_rule      (** [sudo -n] refuses the command *)
  | Unclear of string    (** anything else, in the tool's own words *)

(** Why the taps are unavailable, or [None] when they are not. Looks at
    [/dev/net/tun] first -- then no command is run at all -- and otherwise probes
    by deleting a tap that does not exist: a successful no-op when everything is
    in place, a diagnosable failure otherwise. It never prompts and creates
    nothing. The result is cached until {!ensure_sudoers_rule} runs. *)
val unavailability : unit -> unavailability option

(** [unavailability_of_error message] classifies the diagnostic of a failed probe.
    Pure, and exposed for the same reason as {!sessions_of_taps} and
    {!route_device_of_output}: it is the only part of the diagnosis provable
    without a privilege and without a device. *)
val unavailability_of_error : string -> unavailability

(** [privileged_command_line command] is the shell line a privileged probe is
    really given. It FREEZES the locale ([LC_ALL=C LANGUAGE=]), because every
    diagnosis of this module is made by reading what [sudo], [ip] and the doors
    write, and those write in the language of the session: a French refusal of
    [sudo] matched no needle and was reported as a missing [/dev/net/tun]
    (measured in a classroom, 2026-09-06). Pure, and exposed for the test. *)
val privileged_command_line : string -> string

(** [door_verdict ~message ~remaining] is what to report once the privileged door
    has failed with [message], [remaining] being what the machine still says. A
    [sudo] refusal is named as such; otherwise, when nothing was recognised and
    the machine still reports [No_tun_device], the door's own words are shown
    ([Unclear]) rather than a cause we did not measure. Pure, and exposed for the
    test. *)
val door_verdict :
  message:string -> remaining:unavailability option -> unavailability option

(** [unavailability () = None]. A [false] here is the hook for the degraded mode
    (formerly Daemon_client.disable_daemon_support, with the late daemon). *)
val is_usable : unit -> bool

(** Ask the privileged door bin/scripts/marionnet-tun-device.sh for [/dev/net/tun],
    then measure again: the result is what is STILL wrong, [None] meaning the taps
    work now. Call it when {!unavailability} answered [Some No_tun_device] -- it is
    the only cause a device node repairs, and a machine that already has one should
    not pay a [sudo] call to be told so.

    Placed in the application, and not in the three installation channels, because
    [/dev] is volatile everywhere: a devtmpfs rebuilt at each boot (where udev puts
    the node back by itself) and a fresh tmpfs at each container start (where
    nothing does). A node provided once at installation time survives neither.

    The exit status of the door is deliberately not the answer: creating the node
    does not prove a tap can be made (a device cgroup may still refuse to open it,
    and [TUNSETIFF] still needs [CAP_NET_ADMIN]). A [sudo] refusal is reported as
    {!No_sudoers_rule}, whose remedy -- granting the socle again, this door
    included -- is the true one for an account granted before it existed. *)
val ensure_tun_device : unit -> unavailability option

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
