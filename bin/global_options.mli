(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2010  Jean-Vincent Loddo
   Copyright (C) 2010  Université Paris 13

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

(* The MUTABLE runtime options, i.e. the settings the user may change while Marionnet runs.
   ---
   Do not confuse this module with `Initialization', which holds what is decided ONCE at
   startup (command line, paths, exam mode) and never changes afterwards, nor with
   `Configuration', which merely READS the configuration files and the environment. The
   values below start from an `Initialization' / `Configuration' value and may then be
   reassigned by the GUI (menu "Options") or by the control server.
   ---
   Every setter/getter is protected by one and the same recursive mutex, which is private:
   there is no way for a caller to hold it, hence no lock ordering to respect here. *)

(** Re-exported verbatim from `Initialization' so that "runtime options" have a single entry
    point; the debug level is settable at runtime, unlike the rest of `Initialization'. *)
module Debug_level : module type of Initialization.Debug_level

(** Compile-time default of [get_autogenerate_ip_addresses]. Exposed because the GUI needs it
    to reset the option. *)
val autogenerate_ip_addresses_default : bool

(** Should a newly created network interface receive an IP address automatically? *)
val get_autogenerate_ip_addresses : unit -> bool
val set_autogenerate_ip_addresses : bool -> unit

(** Compile-time default of [get_workaround_wirefilter_problem] (currently [true]). *)
val workaround_wirefilter_problem_default : bool

(** Should the periodic restart of `wirefilter' be applied? Work-around for a bug of the
    patched VDE; when true, a cable's filter process is respawned instead of being trusted. *)
val get_workaround_wirefilter_problem : unit -> bool
val set_workaround_wirefilter_problem : bool -> unit

(** Name of the PRE-EXISTING host bridge the LAN bridge component attaches its tap to
    (variable [MARIONNET_BRIDGE], default ["br0"]). Read once at initialization: changing the
    configuration file requires restarting Marionnet. *)
val ethernet_world_bridge_name : string

(** The same name, but only when somebody really configured it — [None] when
    [MARIONNET_BRIDGE] is set nowhere and {!ethernet_world_bridge_name} is just
    the default ["br0"].

    That distinction is what decides, since episode 7b of the work-stream
    [modernisation-world-bridge], how a LAN bridge finds its host bridge:
    configured means an administrator built one by hand and we keep honouring it,
    exactly as before; not configured means Marionnet builds and takes down its
    own ({!Lan_bridge_host}), which is the whole point of that work-stream. A
    plain string could not tell the two apart — ["br0"] is both a default and a
    perfectly ordinary answer.

    An {e empty} value counts as not configured: [/etc/marionnet/marionnet.conf]
    shipped [MARIONNET_BRIDGE=br0] for fifteen years and an upgrade does not
    rewrite it, so [MARIONNET_BRIDGE=] is how a user of such a host says "build
    your own bridge" without needing root. *)
val explicit_world_bridge_name : string option

(** How a [world_bridge] component obtains the host bridge it attaches to
    (work-stream [modernisation-world-bridge], option A).

    - [`Nat]: Marionnet builds its own private bridge and NATs it to the outside
      ({!Nat_bridge_host}); nothing has to be prepared on the host, and the host
      interface is never touched — the only mode that can work on a Wi-Fi laptop.
    - [`Manual]: the historical behaviour, attach to the pre-existing bridge
      named by {!ethernet_world_bridge_name}.

    Default: [`Manual] as soon as [MARIONNET_BRIDGE] is configured anywhere (an
    administrator did the work, we keep honouring it), [`Nat] otherwise.
    [MARIONNET_WORLD_BRIDGE_MODE] (values [nat] or [manual]) overrides both, and
    is the selector until the GUI grows one. *)
val world_bridge_mode : [ `Nat | `Manual ]

(** Test that [ethernet_world_bridge_name] really exists on the host (via [brctl showmacs]) and,
    if not, pop up a warning dialog naming the file to fix. Being a Gtk+ call, it must run in
    the GTK main thread. Returns [unit] in both cases: this is advisory, it blocks nothing.
    A no-op unless {!explicit_world_bridge_name} is set: when Marionnet builds the
    bridge itself, there is nothing to check and nothing to warn about — the
    bridge is not supposed to exist yet. *)
val check_bridge_existence_and_warning : unit -> unit

(** Keyboard layout to impose on Xnest sessions ([MARIONNET_KEYBOARD_LAYOUT]);
    [None] means "do not set anything", i.e. inherit the host's layout. *)
val keyboard_layout : string option

(** Should the COW files of ALL the disk states be written when saving the project, instead of
    only the ones still reachable? Initialized from [Initialization.keep_all_snapshots_when_saving]
    and then settable from the GUI. Read by the saving path of `state.ml'. *)
module Keep_all_snapshots_when_saving : sig
  type t = bool
  val get      : unit -> t option
  val extract  : unit -> t
  val set      : t -> unit
  val unset    : unit -> unit
  val lazy_set : t Lazy.t -> unit
  val content  : t Lazy.t option ref
end
