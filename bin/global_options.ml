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

(** The name of the host bridge device used to implement the "world bridge" component: *)
let ethernet_world_bridge_name =
  let default = "br0" in
  Configuration.extract_string_variable_or ~default "MARIONNET_BRIDGE"
;;

(** How a `world_bridge' component gets the host bridge it attaches to
    (work-stream `modernisation-world-bridge', option A of
    docs/modernisation-world-bridge.md):

    - [`Nat]    : Marionnet builds its own private bridge and NATs it to the
                  outside, through the auxiliary command marionnet-natbridge.sh
                  (see Nat_bridge_host). Nothing has to be prepared on the host, and
                  the host interface is never touched. This is the mode that also
                  works on a Wi-Fi laptop, where enslaving the card cannot work.
    - [`Manual] : the historical behaviour -- attach to the pre-existing host
                  bridge named by MARIONNET_BRIDGE, which an administrator has
                  built by hand.

    The default is deliberately conservative: an installation that names
    MARIONNET_BRIDGE anywhere has an administrator who did the work, so we keep
    honouring it; only an installation that says nothing gets the new automatic
    mode. MARIONNET_WORLD_BRIDGE_MODE ("nat" / "manual") overrides both.
    Until the GUI selector of a later episode, this variable IS the selector. *)
let world_bridge_mode : [ `Nat | `Manual ] =
  let by_absence_of_configuration () =
    match Configuration.get_string_variable_with_source "MARIONNET_BRIDGE" with
    | None   -> `Nat
    | Some _ -> `Manual
  in
  match Configuration.get_string_variable "MARIONNET_WORLD_BRIDGE_MODE" with
  | Some ("nat" | "auto")      -> `Nat
  | Some ("manual" | "bridge") -> `Manual
  | Some _ | None              -> by_absence_of_configuration ()
;;

let make_understandable_source_of_world_bridge_configuration () =
  match (Configuration.get_string_variable_with_source "MARIONNET_BRIDGE") with
  | None | Some (_, `Environment) -> "marionnet.conf"
  | Some (_, `Filename fname)     ->  fname
;;

(* In `Nat mode there is nothing to check and nothing to warn about: the bridge
   does not exist YET, and it is Marionnet that will build it when the component
   starts. Warning here would tell the user to ask an administrator for exactly
   the manual setup this work-stream exists to remove. *)
let check_bridge_existence_and_warning () : unit =
  if world_bridge_mode = `Nat then () else
  let bridge_name = ethernet_world_bridge_name in
  let cmd = Printf.sprintf "brctl showmacs %s 1>/dev/null 2>/dev/null" (bridge_name) in
  if (Unix.system cmd) <> (Unix.WEXITED 0) then (* warning: *)
    let title = Printf.sprintf (Gettext.f_ "Ethernet bridge \"%s\" not found") bridge_name in
    let source = make_understandable_source_of_world_bridge_configuration () in
    let message =
      Printf.sprintf
        (Gettext.f_ "The Ethernet bridge \"%s\" specified in the file\n\n<tt><small>%s</small></tt>\n\nwas not found on your system. Please ask your administrator to set up this bridge with commands like:\n\n<tt><small>sudo brctl addbr %s\nsudo brctl addif %s %s    # or another interface(s)\nsudo ifconfig %s up\n</small></tt>\nOtherwise, there will be no chance to run a world bridge component properly on your system.")
        (bridge_name) (source) (bridge_name) (bridge_name) ("eth0") (bridge_name)
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
