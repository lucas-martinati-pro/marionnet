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


(** "world bridge" component implementation. *)

#load "where_p4.cmo"
;;

(* --- *)
module Log = Marionnet_log
module Option = Ocamlbricks.Option
module OoExtra = Ocamlbricks.OoExtra
module Forest = Ocamlbricks.Forest
module Xforest = Ocamlbricks.Xforest
(* --- *)
open Gettext

(* World bridge related constants: *)
(* TODO: make it configurable! *)
module Const = struct
 let port_no_default = 1
 let port_no_min = 1
 let port_no_max = 1
end


(* The type of data exchanged with the dialog: *)
module Data = struct
type t = {
  name        : string;
  label       : string;
  old_name    : string;
  }

let to_string t = "<obj>" (* TODO? *)
end (* Data *)


module Make_menus (Params : sig
  val st      : State.globalState
  val packing : [ `toolbar of GButton.toolbar | `menu_parent of Menu_factory.menu_parent ]
 end) = struct

  open Params

  module Toolbar_entry = struct
   let imagefile = "ico.world_bridge.palette.png"
   let tooltip   = (s_ "World bridge")
   let packing   = Params.packing
  end

  module Add = struct
    include Data

    let key = Some GdkKeysyms._B

    let ok_callback t = Gui_bricks.Ok_callback.check_name t.name t.old_name st#network#name_exists t

    let dialog () =
      let () = Global_options.check_bridge_existence_and_warning () in
      let name = st#network#suggestedName "B" in
      Dialog_add_or_update.make ~title:(s_ "Add world bridge") ~name ~ok_callback ()

    let reaction { name = name; label = label; _ } =
      let action () = ignore (
        new User_level_world_bridge.world_bridge
          ~network:st#network
          ~name
          ~label
          ())
      in
      st#network_change action ();

  end

  module Properties = struct
    include Data
    let dynlist () = st#network#get_node_names_that_can_startup ~devkind:`World_bridge ()

    let dialog name () =
     let d = (st#network#get_node_by_name name) in
     let title = (s_ "Modify world bridge")^" "^name in
     let label = d#get_label in
     Dialog_add_or_update.make ~title ~name ~label ~ok_callback:Add.ok_callback ()

    let reaction { name = name; label = label; old_name = old_name } =
      let d = (st#network#get_node_by_name old_name) in
      let h = ((Obj.magic d):> User_level_world_bridge.world_bridge) in
      let action () = h#update_world_bridge_with ~name ~label in
      st#network_change action ();

  end

  module Remove = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")

    let dynlist = Properties.dynlist

    let dialog name () =
      Gui_bricks.Dialog.yes_or_cancel_question
        ~title:(s_ "Remove")
        ~markup:(Printf.sprintf (f_ "Are you sure that you want to remove %s\nand all the cables connected to this %s?") name (s_ "world bridge"))
        ~context:name
        ()

    let reaction name =
      let d = (st#network#get_node_by_name name) in
      let h = ((Obj.magic d):> User_level_world_bridge.world_bridge) in
      let action () = h#destroy in
      st#network_change action ();

  end

  module Startup = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist    = Properties.dynlist
    let dialog     = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#startup

  end

  module Stop = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_gracefully_shutdown ~devkind:`World_bridge ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#gracefully_shutdown

  end

  module Suspend = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_suspend ~devkind:`World_bridge ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#suspend

  end

  module Resume = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_resume ~devkind:`World_bridge ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#resume

  end

 module Create_entries =
  Gui_toolbar_COMPONENTS_layouts.Layout_for_network_node (Params) (Toolbar_entry) (Add) (Properties) (Remove) (Startup) (Stop) (Suspend) (Resume)

 (* Subscribe this kind of component to the network club: *)
 st#network#subscribe_a_try_to_add_procedure Eval_forest_child.try_to_add_world_bridge;

end

(*-----*)
  WHERE
(*-----*)

module Dialog_add_or_update = struct

(* This function may be useful for testing the widget creation without
   recompiling the whole project. *)
let make
 ?(title="Add world bridge")
 ?(name="")
 ?label
 ?(help_callback=help_callback) (* defined backward with "WHERE" *)
 ?(ok_callback=(fun data -> Some data))
 ?(dialog_image_file=Initialization.Path.images^"ico.world_bridge.dialog.png")
 () :'result option =
  let old_name = name in
  let (w,_,name,label) =
    Gui_bricks.Dialog_add_or_update.make_window_image_name_and_label
      ~title
      ~image_file:dialog_image_file
      ~image_tooltip:(s_ "World bridge")
      ~name
      ~name_tooltip:(s_ "World bridge name. This name must be unique in the virtual network. Suggested: B1, B2, ...")
      ?label
      ()
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
   let title = (s_ "ADD OR MODIFY A WORLD BRIDGE") in
   (* TODO: rename "ethernet socket" => "world bridge" in all translations!*)
   let msg   = (s_ "\
In this dialog window you can define the name of an Ethernet socket \
and set parameters for it. This component allows the user to connect the virtual \
network to a Linux bridge whose name is defined by the user via the \
configuration variable called MARIONNET_BRIDGE (in marionnet.conf or provide on \
the command line).\n\n\
If the bridge is correctly set on the host (before starting the network), virtual \
machines will be able to access to the same network services (DHCP, DNS, NFS, \
...) that the host can access on its local network; if the host is on the Internet \
then also the virtual machines linked to the socket will be.\n \n \
To create a bridge on your (real) host using the same network as eth0 (by \
example) you need to : 1) create a bridge with the name define in marionnet.conf \
by MARIONNET_BRIDGE, 2) put and configure eth0 (on your real host) in the \
bridge and 3) put an IP address on the bridge (with dhclient or ifconfig/route).\n\n\
In such a case, after having start the virtual network in marionnet you can \
configure an ethernet card of a virtual machines which is connect to the \
Ethernet socket (or on the same network) in order to give access to your \
local network to it.\n\n \
The socket also allows team-work in a network laboratory, by creating a \
connection between Marionnet instances running on different machines. \
For more information about bridge et Ethernet socket configuration, please \
see the Marionnet Wiki on the marionnet.org website.")
   in Simple_dialogs.help title msg ;;

end

(*-----*)
  WHERE
(*-----*)

module Eval_forest_child = struct

 let try_to_add_world_bridge (network:User_level.network) ((root,children):Xforest.tree) =
  try
   (match root with
    | ("world_bridge", attrs)
    | ("gateway" (* retro-compatibility *), attrs) ->
    	let name  = List.assoc "name"  attrs in
        Log.printf1 "Importing world bridge \"%s\"...\n" name;
        let x = new User_level_world_bridge.world_bridge ~network ~name () in
	x#from_tree ("world_bridge", attrs) children  ;
        Log.printf1 "World bridge \"%s\" successfully imported.\n" name;
        true
   | _ ->
        false
   )
  with _ -> false

end (* module Eval_forest_child *)


(*-----*)
  WHERE
(*-----*)


module User_level_world_bridge = struct

class world_bridge =

 fun ~network
     ~name
     ?label
     () ->
  object (self) inherit OoExtra.destroy_methods ()

  inherit
    User_level.node_with_defects
      ~network
      ~name ?label ~devkind:`World_bridge
      ~port_no:Const.port_no_default
      ~port_no_min:Const.port_no_min
      ~port_no_max:Const.port_no_max
      ~user_port_offset:0
      ~port_prefix:"eth"
      ()
    as self_as_node_with_defects

  method defects_device_type = "world_bridge"
  method polarity = User_level.MDI_Auto (* Because is not pedagogic anyway. *)
  method string_of_devkind = "world_bridge"

  method dotImg iconsize =
   let imgDir = Initialization.Path.images in
   (imgDir^"ico.world_bridge."^(self#string_of_simulated_device_state)^"."^iconsize^".png")

  method update_world_bridge_with ~name ~label =
   self_as_node_with_defects#update_with ~name ~label ~port_no:1;

  (** Create the simulated device *)
  method private make_simulated_device =
   ((new Simulation_level_world_bridge.world_bridge
        ~parent:self
        ~bridge_name:Global_options.ethernet_world_bridge_name
        ~working_directory:(network#project_working_directory)
        ~unexpected_death_callback:self#destroy_because_of_unexpected_death
        ()) :> User_level.node Simulation_level.device)

  method to_tree =
   Forest.tree_of_leaf ("world_bridge", [
     ("name"     ,  self#get_name );
     ("label"    ,  self#get_label);
     ])

  method! eval_forest_attribute = function
  | ("name"     , x ) -> self#set_name x
  | ("label"    , x ) -> self#set_label x
  | _ -> () (* Forward-comp. *)

end (* class world_bridge *)

end (* module User_level_world_bridge *)

(*-----*)
  WHERE
(*-----*)

module Simulation_level_world_bridge = struct

open Daemon_language

(** A World Bridge hub process is just a hub process with exactly two ports,
    of which the first one is connected to the given host tun/tap interface: *)
class world_bridge_hub_process =
  fun ~tap_name
      ~working_directory
      ~unexpected_death_callback
      () ->
object(self)
  inherit Simulation_level.vde_switch_process
      ~port_no:2
      ~hub:true
      ~tap_name
      ~socket_name_prefix:"world_bridge_hub-socket-"
      ~working_directory
      ~unexpected_death_callback
      ()
      (* as self_as_vde_switch_process *)
end

class ['parent] world_bridge =
  fun (* ~id *)
      ~(parent:'parent)
      ~bridge_name
      ~working_directory
      ~unexpected_death_callback
      () ->
object(self)
  inherit ['parent] Simulation_level.device
      ~parent
      ~hublet_no:1
      ~working_directory
      ~unexpected_death_callback
      ()
      (* as self_as_device *)

  method device_type = "world_bridge"

  val the_hublet_process = ref None
  method private extract_the_hublet_process =
    match !the_hublet_process with
      Some the_hublet_process -> the_hublet_process
    | None -> failwith "world_bridge: extract_the_hublet_process was called when there is no such process"

  val mutable world_bridge_hub_process = None
  val mutable world_bridge_tap_name = None
  val mutable internal_cable_process = None

  (** Create the tap via the daemon, and return its name.
      Fail if a the tap already exists: *)
  method private make_world_bridge_tap : string option =
    match world_bridge_tap_name with
    | None ->
        let tap_name_option =
          let server_response =
            Daemon_client.ask_the_server
              (Make (AnySocketTap((Unix.getuid ()), bridge_name)))
          in
          (match server_response with
           | Created (SocketTap(tap_name, _, _)) ->
               Some tap_name
           | _ ->
               let () = Log.printf "Marionnet daemon refused to create a TUN/TAP interface\n" in
               None (* "non-existing-tap" *)
           )
        in
        let () = world_bridge_tap_name <- tap_name_option in
        tap_name_option
    (* --- *)
    | Some tap_name ->
        let () = Log.printf1 "A tap for the world bridge already exists: %s\n" tap_name in
        Some tap_name

  method private destroy_world_bridge_tap =
    Option.iter
      (fun tap_name ->
          try
            let cmd = Destroy (SocketTap(tap_name, (Unix.getuid ()), bridge_name)) in
            let _ = Daemon_client.ask_the_server cmd in
            (world_bridge_tap_name <- None)
          (* --- *)
          with e -> begin
            Log.printf1
              "WARNING: Failed in destroying a host tap for a world bridge: %s\n"
              (Printexc.to_string e);
          end)
      (world_bridge_tap_name)

  (* --- *)
  initializer
    begin
      assert ((List.length self#get_hublet_process_list) = 1);
      (* --- *)
      the_hublet_process := Some (self#get_hublet_process_of_port 0);
      (* --- *)
      world_bridge_hub_process <- self#make_world_bridge_hub_process
    end
  (* --- *)


  method private make_world_bridge_hub_process : (world_bridge_hub_process option) =
    let () =
      if world_bridge_hub_process <> None then () else (* continue: *)
      Option.iter
        (fun tap_name ->
          let result =
            new world_bridge_hub_process
              ~tap_name
              ~working_directory
              ~unexpected_death_callback:self#execute_the_unexpected_death_callback
              ()
            in
            world_bridge_hub_process <- Some result)
        (* --- *)
        (self#make_world_bridge_tap)
    in
    world_bridge_hub_process

  method spawn_processes =
   Option.iter
     (* --- *)
     (fun the_world_bridge_hub_process ->
        (* Spawn the hub process, and wait to be sure it's started: *)
        let () = the_world_bridge_hub_process#spawn in
        (* Create the internal cable process from the single hublet to the hub, and spawn it: *)
         let the_internal_cable_process =
           Simulation_level.make_ethernet_cable_process
             ~left_end:the_world_bridge_hub_process
             ~right_end:self#extract_the_hublet_process
             ~leftward_defects:(parent#ports_card#get_my_inward_defects_by_index 0)
             ~rightward_defects:(parent#ports_card#get_my_outward_defects_by_index 0)
             ~unexpected_death_callback:self#execute_the_unexpected_death_callback
             ()
         in
         internal_cable_process <- Some the_internal_cable_process;
         the_internal_cable_process#spawn)
     (* --- *)
     self#make_world_bridge_hub_process

  method terminate_processes = begin
    let () =
      Log.printf3 "world_bridge %s#terminate_processes:  internal_cable_process=%s  world_bridge_hub_process=%s\n"
        (parent#name) (Option.to_string internal_cable_process) (Option.to_string world_bridge_hub_process)
    in
    (* Terminate the internal cable process and the hub process: *)
    let () =
      Task_runner.do_in_parallel
        [ (fun () -> Option.iter (fun obj -> obj#terminate) internal_cable_process);
          (fun () -> Option.iter (fun obj -> obj#terminate) world_bridge_hub_process); ]
    in
    (* Destroy the tap, via the daemon: *)
    self#destroy_world_bridge_tap;
    (* Unreference everything: *)
    internal_cable_process <- None;
    world_bridge_hub_process <- None;
    end

  (** As world bridges are stateless from the point of view of the user, stop/continue
      aren't distinguishable from terminate/spawn: *)
  method stop_processes = self#terminate_processes
  method continue_processes = self#spawn_processes
end

end (* module Simulation_level_world_bridge *)

(** Just for testing: *)
let test = Dialog_add_or_update.make
