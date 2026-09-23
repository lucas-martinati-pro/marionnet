(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008  Luca Saiu
   Copyright (C) 2010, 2017  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2010, 2017  Université Paris 13

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

module Recursive_mutex  = Ocamlbricks.MutexExtra.Recursive ;;
module Stateful_modules = Ocamlbricks.Stateful_modules ;;

let mutex = Recursive_mutex.create ();;

(** Here we only use one mutex; let's not specify it every time: *)
let with_mutex thunk =
  Recursive_mutex.with_mutex mutex thunk;;

(** Debug mode related functions are accessible also from this module: *)
module Debug_level = Initialization.Debug_level;;

(** Automatically generate IP addresses: *)
let autogenerate_ip_addresses_default =
  false (*false*);;

let autogenerate_ip_addresses =
  ref autogenerate_ip_addresses_default;;
let set_autogenerate_ip_addresses value =
  with_mutex
    (fun () ->
      autogenerate_ip_addresses := value);;
let get_autogenerate_ip_addresses () =
  with_mutex
    (fun () ->
      !autogenerate_ip_addresses);;

(** Work-around the wirefilter bug (which is probably due to my patches to VDE): *)
let workaround_wirefilter_problem_default =
  true;; (* true *)
let workaround_wirefilter_problem =
  ref workaround_wirefilter_problem_default;;
let set_workaround_wirefilter_problem value =
  with_mutex
    (fun () ->
      workaround_wirefilter_problem := value);;
let get_workaround_wirefilter_problem () =
  with_mutex
    (fun () ->
      !workaround_wirefilter_problem);;

(** Automatically login as root on virtual machines and routers without password: *)
let autologin_root_default = true;;
let autologin_root = ref autologin_root_default;;
let set_autologin_root value =
  with_mutex
    (fun () ->
      autologin_root := value);;
let get_autologin_root () =
  with_mutex
    (fun () ->
      !autologin_root);;

(** The name of the host bridge device used to implement the "world bridge" component: *)
let ethernet_world_bridge_name =
  let default = "br0" in
  Configuration.extract_string_variable_or ~default "MARIONNET_BRIDGE"
;;

(* Configured, or merely defaulted? Since episode 7b that question IS the choice
   between the two behaviours of a LAN bridge: honour the bridge an administrator
   built by hand, or build one ourselves. `ethernet_world_bridge_name' cannot
   answer it -- "br0" is both its default and a plausible configured value.
   ---
   An EMPTY value counts as not configured, and that is not a detail on a host
   upgraded rather than installed: /etc/marionnet/marionnet.conf shipped with
   MARIONNET_BRIDGE=br0 for fifteen years, and the file is not rewritten by an
   upgrade. Writing `MARIONNET_BRIDGE=' (or exporting it empty) is therefore how
   one says "let Marionnet build its own bridge" without having to be root. *)
let explicit_world_bridge_name : string option =
  match Configuration.get_string_variable_with_source "MARIONNET_BRIDGE" with
  | None   -> None
  | Some _ -> if String.trim ethernet_world_bridge_name = "" then None
              else Some ethernet_world_bridge_name
;;

let make_understandable_source_of_world_bridge_configuration () =
  match (Configuration.get_string_variable_with_source "MARIONNET_BRIDGE") with
  | None | Some (_, `Environment) -> "marionnet.conf"
  | Some (_, `Filename fname)     ->  fname
;;

(* When nobody configured MARIONNET_BRIDGE there is nothing to check and nothing
   to warn about: the bridge does not exist YET, and it is Marionnet that will
   build it when the component starts (episode 7b). Warning here would tell the
   user to ask an administrator for exactly the manual setup this work-stream
   exists to remove. The case that DOES deserve a warning is the opposite one:
   somebody overrode the automatic behaviour by naming a bridge, and that bridge
   is not on the host -- the component would then start and enslave its tap to
   nothing, in silence. Hence the message says, first of all, how to get rid of
   the override.
   ---
   Existence is read from sysfs instead of being asked to `brctl showmacs':
   bridge-utils is no longer installed by default on a modern Debian/Ubuntu, so
   the old test answered "no such bridge" on hosts where the bridge was
   perfectly present. /sys/class/net/<name>/bridge exists if and only if <name>
   is a bridge device -- an ordinary interface of the same name does not have it. *)
let check_bridge_existence_and_warning () : unit =
  if explicit_world_bridge_name = None then () else
  let bridge_name = ethernet_world_bridge_name in
  let sysfs_bridge_directory = Printf.sprintf "/sys/class/net/%s/bridge" (bridge_name) in
  if (Sys.file_exists sysfs_bridge_directory) then () else (* warning: *)
    let title = Printf.sprintf (Gettext.f_ "Ethernet bridge \"%s\" not found") bridge_name in
    let source = make_understandable_source_of_world_bridge_configuration () in
    let message =
      Printf.sprintf
        (Gettext.f_ "The Ethernet bridge \"%s\" named in the file\n\n<tt><small>%s</small></tt>\n\nwas not found on this computer. Naming a bridge in that file is now merely a way to OVERRIDE the automatic behaviour: if you comment out (or empty) that line, Marionnet builds its own bridge when a LAN bridge component starts, and takes it down when it stops. Nothing has to be prepared by hand any more.\n\nIf you do prefer to keep using a bridge of your own, ask your administrator to create it, with commands like:\n\n<tt><small>sudo ip link add %s type bridge\nsudo ip link set %s up\nsudo ip link set eth0 master %s    # or another interface(s)\n</small></tt>")
        (bridge_name) (source) (bridge_name) (bridge_name) (bridge_name)
    in
    Simple_dialogs.warning ~modal:true title message ()
;;

(** Keyboard layout in Xnest sessions; `None' means `don't set anything' *)
let keyboard_layout = Configuration.get_string_variable "MARIONNET_KEYBOARD_LAYOUT" ;;

module Keep_all_snapshots_when_saving =
  Stateful_modules.Variable (struct
    type t = bool
    let name = Some "keep_all_snapshots_when_saving"
  end);;
let () = Keep_all_snapshots_when_saving.set Initialization.keep_all_snapshots_when_saving
;;
