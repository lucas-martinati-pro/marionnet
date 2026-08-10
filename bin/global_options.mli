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

(** Name of the PRE-EXISTING host bridge the `world_bridge' component attaches its tap to
    (variable [MARIONNET_BRIDGE], default ["br0"]). Read once at initialization: changing the
    configuration file requires restarting Marionnet. *)
val ethernet_world_bridge_name : string

(** Test that [ethernet_world_bridge_name] really exists on the host (via [brctl showmacs]) and,
    if not, pop up a warning dialog naming the file to fix. Being a Gtk+ call, it must run in
    the GTK main thread. Returns [unit] in both cases: this is advisory, it blocks nothing. *)
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
