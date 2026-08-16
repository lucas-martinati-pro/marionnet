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
module Xforest = Ocamlbricks.Xforest
(* --- *)
open Gettext

(* Everything this component has in common with the NAT bridge — the constants, the
   type exchanged with the dialog, and both halves of the mechanism — lives there
   (work-stream modernisation-world-bridge, episode 7a.3): *)
module Data = Bridge_common.Data


module Make_menus (Params : sig
  val st      : State.globalState
  val packing : [ `toolbar of GButton.toolbar | `menu_parent of Menu_factory.menu_parent ]
 end) = struct

  open Params

  module Toolbar_entry = struct
   let imagefile = "ico.lan_bridge.palette.png"
   let tooltip   = (s_ "World bridge (connect the virtual machines to the real host network, or link Marionnet instances across machines; for plain Internet access, prefer a world gateway)")
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
    let dynlist () = st#network#get_node_names_that_can_modify ~devkind:`World_bridge ()

    let dialog name () =
     let d = (st#network#get_node_by_name name) in
     let title = (s_ "Modify world bridge")^" "^name in
     let label = d#get_label in
     Dialog_add_or_update.make ~title ~name ~label ~ok_callback:Add.ok_callback ()

    let reaction { name = name; label = label; old_name = old_name } =
      let d = (st#network#get_node_by_name old_name) in
      let h = ((Obj.magic d):> User_level_world_bridge.world_bridge) in
      let action () = h#update_bridge_with ~name ~label in
      st#network_change action ();

  end

  module Remove = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")

    let dynlist () = st#network#get_node_names_that_can_destroy ~devkind:`World_bridge ()

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
    (* Not an alias of Properties.dynlist: each menu reads its own guard (user_level.ml). *)
    let dynlist () = st#network#get_node_names_that_can_startup ~devkind:`World_bridge ()
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
 ?(dialog_image_file=Initialization.Path.images^"ico.lan_bridge.dialog.png")
 () :'result option =
  let old_name = name in
  let (w,_,name,label) =
    Gui_bricks.Dialog_add_or_update.make_window_image_name_and_label
      ~title
      ~image_file:dialog_image_file
      ~image_tooltip:(s_ "World bridge: bridge the virtual network to the real host network (requires a host-side Linux bridge; see the help button)")
      ~name
      ~name_tooltip:(s_ "World bridge name. This name must be unique in the virtual network. Suggested: B1, B2, ...")
      ?label
      ()
  in

  (* Said at the moment of the gesture, not as an unexplained failure at start-up
     time: in the automatic mode this component will ask for administrator rights
     the first time it runs (work-stream modernisation-world-bridge, episode 6).
     Once the rule is installed the probe answers `true' and the notice goes away
     by itself. *)
  let () =
    if Global_options.world_bridge_mode = `Nat && not (Nat_bridge_host.is_usable ()) then
      let _ =
        GMisc.label
          ~markup:("<i>" ^ Glib.Markup.escape_text
                     (s_ "Note: the first time this component is started, Marionnet will ask for your password, once, in order to grant itself the right to build its own private bridge.")
                   ^ "</i>")
          ~xalign:0.0 ~line_wrap:true ~width:420 ~xpad:20 ~ypad:5
          ~packing:w#vbox#add ()
      in ()
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
   let msg   = (s_ "\
A world bridge connects your virtual network to a Linux bridge on the real \
host. The virtual machines attached to it then reach the SAME physical network \
as the host itself, and its services (DHCP, DNS, NFS, the gateway to the \
Internet...). It also enables team-work across computers: two Marionnet \
instances running on different real machines, each with a world bridge on a \
shared network segment, form a single virtual network.\n\n\
World bridge or world gateway? Use a WORLD GATEWAY when you simply want the \
virtual machines to reach the Internet through a self-contained NAT router: it \
needs no host configuration and works out of the box. Use a WORLD BRIDGE when \
the virtual machines must appear directly on the real host network, or to link \
Marionnet instances running on different machines.\n\n\
Prerequisite, on the host side, before starting the network: a Linux bridge \
whose name is given by the MARIONNET_BRIDGE variable (in marionnet.conf or on \
the command line) must already exist on the host. To bridge the real network \
of eth0, for example, an administrator has to: 1) create that bridge, 2) \
enslave eth0 into it, and 3) move the host IP address onto the bridge (with \
DHCP or 'ip addr'/'ip route'). Beware: steps 2 and 3 momentarily reconfigure \
the host network card and may interrupt the host connectivity. See the \
Marionnet administrator documentation and the Marionnet Wiki on the \
marionnet.org website.")
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
  object (self)

  inherit
    Bridge_common.User_level_bridge.bridge
      ~network
      ~name ?label
      ~devkind:`World_bridge
      ~kind_name:"world_bridge"
      (* What is written in a .mar stays `world_bridge'; what is drawn says LAN,
         now that a second bridge exists (episode 7a.3.b): *)
      ~icon_prefix:"lan_bridge"
      ()

  (** Create the simulated device *)
  method private make_simulated_device =
   ((new Simulation_level_world_bridge.world_bridge
        ~parent:self
        ~bridge_name:Global_options.ethernet_world_bridge_name
        ~working_directory:(network#project_working_directory)
        ~unexpected_death_callback:self#destroy_because_of_unexpected_death
        ()) :> User_level.node Simulation_level.device)

end (* class world_bridge *)

end (* module User_level_world_bridge *)

(*-----*)
  WHERE
(*-----*)

module Simulation_level_world_bridge = struct

(** The host bridge to attach our tap to, resolved AT START-UP TIME rather
    than read from the configuration at initialisation.
    ---
    That deferral is the whole point of the automatic mode: in `Nat the bridge
    does not exist until we ask for it, and its name (mnbr<pid>) is only known
    once Nat_bridge_host has built it. In `Manual nothing changes -- the name comes
    from MARIONNET_BRIDGE, as it always did.
    ---
    A failure of the automatic mode does NOT abort the start-up: we fall back
    on the configured name, so the component behaves exactly as it did before
    this work-stream (it will fail to find its bridge, and say so), instead of
    failing in a new way. The reason is always logged. *)
let resolve_bridge_name ~bridge_name () : string =
    match Global_options.world_bridge_mode with
    | `Manual -> bridge_name
    | `Nat ->
        (* The scoped sudoers block of the NAT bridge is granted by the user, not
           by the administrator (docs/modernisation-world-bridge.md § 1 bis.3), and
           this is the moment it is needed. Privileges asks for the password and
           installs it; on refusal we simply carry on and let Nat_bridge_host fail as it
           did before. Privileges tells the user itself when it fails, exactly once
           per session; here we only leave a trace in the log. *)
        let () =
          match Privileges.ensure_natbridge () with
          | Ok () -> ()
          | Error message ->
              Log.printf1 "world_bridge: no administrator rights for the NAT bridge: %s\n" message
        in
        (match Nat_bridge_host.ensure () with
         | Ok info ->
             let () =
               Log.printf2
                 "world_bridge: using the automatic NAT bridge %s (guests: address in %s.0/24)\n"
                 info.Nat_bridge_host.bridge info.Nat_bridge_host.subnet
             in
             info.Nat_bridge_host.bridge
         | Error e ->
             let () =
               Log.printf2
                 "world_bridge: the automatic NAT bridge is unavailable (%s); falling back on the configured bridge %s\n"
                 (Nat_bridge_host.string_of_error e) bridge_name
             in
             bridge_name)

(** The mechanism itself -- the tap, the two-port hub, the internal cable and their
    life cycle -- is the one shared with the NAT bridge (see [Bridge_common]). All
    this component adds is which host bridge its tap must join, and the name under
    which it appears in the logs and in the process working directory. *)
class ['parent] world_bridge =
  fun (* ~id *)
      ~(parent:'parent)
      ~bridge_name
      ~working_directory
      ~unexpected_death_callback
      () ->
object(_self)
  inherit ['parent] Bridge_common.Simulation_level_bridge.bridge_device
      ~parent
      ~device_type:"world_bridge"
      ~resolve_bridge_name:(resolve_bridge_name ~bridge_name)
      ~socket_name_prefix:"world_bridge_hub-socket-"
      ~working_directory
      ~unexpected_death_callback
      ()
end

end (* module Simulation_level_world_bridge *)

(** Just for testing: *)
let test = Dialog_add_or_update.make
