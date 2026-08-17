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


(** "NAT bridge" component implementation: a bridge Marionnet builds for itself,
    on the host but beside it, and takes down when it is done with it (work-stream
    modernisation-world-bridge, episode 7a.3.b).

    Same mechanism as the LAN bridge -- a tap in a two-port hub, see [Bridge_common] --
    and one difference, which is the whole point: the host bridge its tap joins does
    not have to exist beforehand. This component asks [Nat_bridge_host] for one, gets
    a private /24 of its own, and gives it back when it stops. *)

#load "where_p4.cmo"
;;

(* --- *)
module Log = Marionnet_log
module Xforest = Ocamlbricks.Xforest
(* --- *)
open Gettext

(* Everything this component has in common with the LAN bridge -- the constants, the
   type exchanged with the dialog, and both halves of the mechanism: *)
module Data = Bridge_common.Data


module Make_menus (Params : sig
  val st      : State.globalState
  val packing : [ `toolbar of GButton.toolbar | `menu_parent of Menu_factory.menu_parent ]
 end) = struct

  open Params

  module Toolbar_entry = struct
   let imagefile = "ico.nat_bridge.palette.png"
   let tooltip   = (s_ "NAT bridge (give the virtual machines access to the Internet through a private bridge that Marionnet builds by itself: no host configuration, and it also works when the host is on Wi-Fi)")
   let packing   = Params.packing
  end

  module Add = struct
    include Data

    let key = Some GdkKeysyms._N

    let ok_callback t = Gui_bricks.Ok_callback.check_name t.name t.old_name st#network#name_exists t

    let dialog () =
      let name = st#network#suggestedName "N" in
      Dialog_add_or_update.make ~title:(s_ "Add NAT bridge") ~name ~ok_callback ()

    let reaction { name = name; label = label; _ } =
      let action () = ignore (
        new User_level_nat_bridge.nat_bridge
          ~network:st#network
          ~name
          ~label
          ())
      in
      st#network_change action ();

  end

  module Properties = struct
    include Data
    let dynlist () = st#network#get_node_names_that_can_modify ~devkind:`Nat_bridge ()

    let dialog name () =
     let d = (st#network#get_node_by_name name) in
     let title = (s_ "Modify NAT bridge")^" "^name in
     let label = d#get_label in
     Dialog_add_or_update.make ~title ~name ~label ~ok_callback:Add.ok_callback ()

    let reaction { name = name; label = label; old_name = old_name } =
      let d = (st#network#get_node_by_name old_name) in
      let h = ((Obj.magic d):> User_level_nat_bridge.nat_bridge) in
      let action () = h#update_bridge_with ~name ~label in
      st#network_change action ();

  end

  module Remove = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")

    let dynlist () = st#network#get_node_names_that_can_destroy ~devkind:`Nat_bridge ()

    let dialog name () =
      Gui_bricks.Dialog.yes_or_cancel_question
        ~title:(s_ "Remove")
        ~markup:(Printf.sprintf (f_ "Are you sure that you want to remove %s\nand all the cables connected to this %s?") name (s_ "NAT bridge"))
        ~context:name
        ()

    let reaction name =
      let d = (st#network#get_node_by_name name) in
      let h = ((Obj.magic d):> User_level_nat_bridge.nat_bridge) in
      let action () = h#destroy in
      st#network_change action ();

  end

  module Startup = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    (* Not an alias of Properties.dynlist: each menu reads its own guard (user_level.ml). *)
    let dynlist () = st#network#get_node_names_that_can_startup ~devkind:`Nat_bridge ()
    let dialog     = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#startup

  end

  module Stop = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_gracefully_shutdown ~devkind:`Nat_bridge ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#gracefully_shutdown

  end

  module Suspend = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_suspend ~devkind:`Nat_bridge ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#suspend

  end

  module Resume = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_resume ~devkind:`Nat_bridge ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#resume

  end

 module Create_entries =
  Gui_toolbar_COMPONENTS_layouts.Layout_for_network_node (Params) (Toolbar_entry) (Add) (Properties) (Remove) (Startup) (Stop) (Suspend) (Resume)

 (* Subscribe this kind of component to the network club. Beware: this is also what
    makes a saved project readable -- without it a `nat_bridge' subtree of a .mar is
    silently skipped at loading time (work-stream modernisation-world-bridge, ep. 7a.3): *)
 st#network#subscribe_a_try_to_add_procedure Eval_forest_child.try_to_add_nat_bridge;

end

(*-----*)
  WHERE
(*-----*)

module Dialog_add_or_update = struct

(* This function may be useful for testing the widget creation without
   recompiling the whole project. *)
let make
 ?(title="Add NAT bridge")
 ?(name="")
 ?label
 ?(help_callback=help_callback) (* defined backward with "WHERE" *)
 ?(ok_callback=(fun data -> Some data))
 ?(dialog_image_file=Initialization.Path.images^"ico.nat_bridge.dialog.png")
 () :'result option =
  let old_name = name in
  let (w,_,name,label) =
    Gui_bricks.Dialog_add_or_update.make_window_image_name_and_label
      ~title
      ~image_file:dialog_image_file
      ~image_tooltip:(s_ "NAT bridge: a private bridge that Marionnet builds on the host, with its own network, from which the virtual machines reach the Internet (see the help button)")
      ~name
      ~name_tooltip:(s_ "NAT bridge name. This name must be unique in the virtual network. Suggested: N1, N2, ...")
      ?label
      ()
  in

  (* Said at the moment of the gesture, not as an unexplained failure at start-up
     time: this component asks for administrator rights the first time it runs
     (work-stream modernisation-world-bridge, episode 6). Once the rule is installed
     the probe answers `true' and the notice goes away by itself. *)
  let () =
    if not (Nat_bridge_host.is_usable ()) then
      let note =
        GMisc.label
          ~markup:("<i>" ^ Glib.Markup.escape_text
                     (s_ "Note: the first time this component is started, Marionnet will ask for your password, once, in order to grant itself the right to build its own private bridge.")
                   ^ "</i>")
          ~xalign:0.0 ~line_wrap:true ~width:420 ~xpad:20 ~ypad:5
          ~packing:w#vbox#add ()
      in
      (* Gtk+ 3: ~width is only the *minimum* request; a wrapping label still asks
         for the whole sentence as its natural width, and the dialog obeys. Capping
         the natural width is what makes the text wrap, in every language. *)
      note#set_max_width_chars 72
  in

  let get_widget_data () :'result =
    let name = name#text in
    let label = label#text in
      { Data.name = name;
        Data.label = label;
        Data.old_name = old_name;
        }
  in
  (* The result of make is the result of the dialog loop (of type 'result option): *)
  Gui_bricks.Dialog_run.ok_or_cancel w ~ok_callback ~help_callback ~get_widget_data ()

(*-----*)
  WHERE
(*-----*)

 let help_callback =
   let title = (s_ "ADD OR MODIFY A NAT BRIDGE") in
   let msg   = (s_ "\
A NAT bridge gives the virtual machines access to the real network of the host, \
and through it to the Internet, WITHOUT touching the host configuration in any \
way. Marionnet builds, on the host, a bridge of its own, gives it a private \
network (a /24 of addresses free of the host routes) and translates the \
addresses (NAT) of everything leaving it. When the component is stopped, or \
when Marionnet exits, that bridge and its rules are removed: the host is left \
exactly as it was found.\n\n\
Each NAT bridge of the project has its OWN private network: two of these \
components are two separate networks, not two doors onto the same one.\n\n\
The guests must be configured in that network: the address of the bridge is \
their gateway, and the range of usable addresses is written in the Marionnet \
log when the component starts. There is no DHCP server: give the virtual \
machines a static address.\n\n\
NAT bridge, LAN bridge or gateway? Use a NAT BRIDGE to reach the Internet with \
real network performance and no host configuration -- it is also the only one \
of the three bridges that works when the host is connected over Wi-Fi. Use a \
LAN BRIDGE when the virtual machines must appear DIRECTLY on the physical \
network of the host (its DHCP, its DNS, its other machines), or to link \
Marionnet instances running on different computers: that one needs a Linux \
bridge on the host side. Use a WORLD GATEWAY for a self-contained NAT router \
that needs no privilege at all.\n\n\
The first time a NAT bridge is started, Marionnet asks for your password, once, \
in order to grant itself a narrow and permanent right: to build and take down \
bridges named after its own process, and the translation rules that go with \
them. Nothing else.")
   in Simple_dialogs.help title msg ;;

end

(*-----*)
  WHERE
(*-----*)

module Eval_forest_child = struct

 let try_to_add_nat_bridge (network:User_level.network) ((root,children):Xforest.tree) =
  try
   (match root with
    | ("nat_bridge", attrs) ->
    	let name  = List.assoc "name"  attrs in
        Log.printf1 "Importing NAT bridge \"%s\"...\n" name;
        let x = new User_level_nat_bridge.nat_bridge ~network ~name () in
	x#from_tree ("nat_bridge", attrs) children  ;
        Log.printf1 "NAT bridge \"%s\" successfully imported.\n" name;
        true
   | _ ->
        false
   )
  with _ -> false

end (* module Eval_forest_child *)


(*-----*)
  WHERE
(*-----*)


module User_level_nat_bridge = struct

class nat_bridge =

 fun ~network
     ~name
     ?label
     () ->
  object (self)

  inherit
    Bridge_common.User_level_bridge.bridge
      ~network
      ~name ?label
      ~devkind:`Nat_bridge
      ~kind_name:"nat_bridge"
      ()

  (** Create the simulated device *)
  method private make_simulated_device =
   ((new Simulation_level_nat_bridge.nat_bridge
        ~parent:self
        ~working_directory:(network#project_working_directory)
        ~unexpected_death_callback:self#destroy_because_of_unexpected_death
        ()) :> User_level.node Simulation_level.device)

end (* class nat_bridge *)

end (* module User_level_nat_bridge *)

(*-----*)
  WHERE
(*-----*)

module Simulation_level_nat_bridge = struct

(* --- Allocating the instance numbers
   ---
   One bridge per component means one number per component, and the numbers are
   allocated HERE because this is where the components are: `Nat_bridge_host' only
   uses them as a key (see its interface).
   ---
   The numbers in use are read from the host itself -- the bridges named after our
   pid -- so a crashed run leaves nothing behind to confuse a later one and there is
   no state file to keep in step with reality.
   ---
   Reading them and creating the bridge must be ONE atomic gesture: two components
   started in parallel by the task runner would otherwise read the same list and
   choose the same number, the second `up' landing on a bridge that already exists.
   Lock order (this mutex, then the one of Nat_bridge_host) is the same everywhere
   below, hence no deadlock. *)

let allocation_mutex = Mutex.create ()

let taken_instances () : int list =
  match Nat_bridge_host.status () with
  | Ok bridges ->
      let my_pid = Unix.getpid () in
      List.filter_map
        (fun (t : Nat_bridge_host.t) ->
           if t.Nat_bridge_host.owner_pid = my_pid then t.Nat_bridge_host.instance else None)
        bridges
  | Error e ->
      (* Not fatal: at worst we choose a number that is already taken, and the
         script refuses to build a bridge that exists with another subnet. *)
      let () = Log.printf1 "nat_bridge: cannot read the bridges of this process (%s)\n" (Nat_bridge_host.string_of_error e) in
      []

let smallest_free (taken : int list) : int =
  let rec search n = if List.mem n taken then search (n + 1) else n in
  search 1

(* Deliberately impossible as a bridge name (a device name is at most 15 characters
   and this one is longer): when we could not build a bridge, the tap has to fail to
   join it, loudly, exactly as a LAN bridge fails when its host bridge is missing.
   Returning something plausible would be worse -- it might exist. *)
let no_bridge_at_all = "marionnet-no-such-bridge"

(** The mechanism itself -- the tap, the two-port hub, the internal cable and their
    life cycle -- is the one shared with the LAN bridge (see [Bridge_common]). What
    this component adds is a bridge of its own: one that does not exist until it is
    asked for, and that is given back when the component stops. *)
class ['parent] nat_bridge =
  fun (* ~id *)
      ~(parent:'parent)
      ~working_directory
      ~unexpected_death_callback
      () ->
  (* The number this component holds, WHILE it holds it. It is not a property of the
     component (a project saved and reloaded may well get another one), it is a
     property of the run, hence a reference and not a field of the .mar: *)
  let instance = ref None in
  (* --- *)
  (* Called at start-up time, and possibly twice for a single gesture (the simulated
     object is built, then started): the number is therefore reused when we already
     have one, and `ensure' hands back the bridge it built the first time. *)
  let resolve_bridge_name () : string =
    (* The scoped sudoers block of the NAT bridge is granted by the user, not by the
       administrator (docs/modernisation-world-bridge.md § 1 bis.3), and this is the
       moment it is needed. Privileges asks for the password and installs it; it also
       tells the user itself when it fails, exactly once per session, so here we only
       leave a trace in the log and carry on. *)
    let () =
      match Privileges.ensure_natbridge () with
      | Ok () -> ()
      | Error message -> Log.printf1 "nat_bridge: no administrator rights for the NAT bridge: %s\n" message
    in
    let () = Mutex.lock allocation_mutex in
    let result =
      try
        let n = match !instance with Some n -> n | None -> smallest_free (taken_instances ()) in
        (match Nat_bridge_host.ensure ~instance:n () with
         | Ok info ->
             let () = instance := Some n in
             let () =
               Log.printf3
                 "nat_bridge: using the private bridge %s (guests: %s, gateway %s)\n"
                 info.Nat_bridge_host.bridge info.Nat_bridge_host.guest_range info.Nat_bridge_host.gateway
             in
             info.Nat_bridge_host.bridge
         | Error e ->
             let () =
               Log.printf1 "nat_bridge: no private bridge could be built (%s)\n" (Nat_bridge_host.string_of_error e)
             in
             no_bridge_at_all)
      with e -> Mutex.unlock allocation_mutex; raise e
    in
    let () = Mutex.unlock allocation_mutex in
    result
  in
  (* --- *)
  (* Called once the tap has been destroyed: the bridge and its translation rules go
     away with the component, and its number becomes available again. *)
  let after_terminate () : unit =
    let () = Mutex.lock allocation_mutex in
    let () =
      try
        match !instance with
        | None -> ()
        | Some n ->
            let () =
              match Nat_bridge_host.release ~instance:n () with
              | Ok () -> ()
              | Error e -> Log.printf1 "nat_bridge: %s\n" (Nat_bridge_host.string_of_error e)
            in
            instance := None
      with e -> Mutex.unlock allocation_mutex; raise e
    in
    Mutex.unlock allocation_mutex
  in
  (* --- *)
object(_self)
  inherit ['parent] Bridge_common.Simulation_level_bridge.bridge_device
      ~parent
      ~device_type:"nat_bridge"
      ~resolve_bridge_name
      ~after_terminate
      ~socket_name_prefix:"nat_bridge_hub-socket-"
      ~working_directory
      ~unexpected_death_callback
      ()
end

end (* module Simulation_level_nat_bridge *)

(** Just for testing: *)
let test = Dialog_add_or_update.make
