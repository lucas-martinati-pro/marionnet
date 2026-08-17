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


(** "LAN bridge" component implementation: the bridge that puts the virtual
    machines on the REAL local network of the host — real addresses, the LAN's own
    DHCP and DNS, the other machines of the room — by putting the host's own
    network card into a bridge (work-stream modernisation-world-bridge, ep. 7b).

    Same mechanism as the NAT bridge — a tap in a two-port hub, see [Bridge_common] —
    and one difference, which is the whole point: this one does not build a network
    of its own, it joins the one that is already there. Marionnet builds that bridge
    itself ([Lan_bridge_host]) unless an administrator configured one by hand, in
    which case MARIONNET_BRIDGE names it and nothing is touched on the host.

    {b Its internal name is still "world_bridge"}, everywhere it is written down:
    in the .mar files, in the grammar of the control channel, in the devkind. Only
    the words a human reads say "LAN bridge" now that a second bridge exists —
    which is exactly what keeps yesterday's projects and lab scripts working. *)

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
   let tooltip   = (s_ "LAN bridge (put the virtual machines directly on the real local network of this computer: real addresses, the network's own DHCP and services; it can also link Marionnet instances running on different machines)")
   let packing   = Params.packing
  end

  module Add = struct
    include Data

    let key = Some GdkKeysyms._B

    let ok_callback t = Gui_bricks.Ok_callback.check_name t.name t.old_name st#network#name_exists t

    let dialog () =
      let () = Global_options.check_bridge_existence_and_warning () in
      let name = st#network#suggestedName "B" in
      Dialog_add_or_update.make ~title:(s_ "Add LAN bridge") ~name ~ok_callback ()

    let reaction { name = name; label = label; _ } =
      let action () = ignore (
        new User_level_lan_bridge.lan_bridge
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
     let title = (s_ "Modify LAN bridge")^" "^name in
     let label = d#get_label in
     Dialog_add_or_update.make ~title ~name ~label ~ok_callback:Add.ok_callback ()

    let reaction { name = name; label = label; old_name = old_name } =
      let d = (st#network#get_node_by_name old_name) in
      let h = ((Obj.magic d):> User_level_lan_bridge.lan_bridge) in
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
        ~markup:(Printf.sprintf (f_ "Are you sure that you want to remove %s\nand all the cables connected to this %s?") name (s_ "LAN bridge"))
        ~context:name
        ()

    let reaction name =
      let d = (st#network#get_node_by_name name) in
      let h = ((Obj.magic d):> User_level_lan_bridge.lan_bridge) in
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
 st#network#subscribe_a_try_to_add_procedure Eval_forest_child.try_to_add_lan_bridge;

end

(*-----*)
  WHERE
(*-----*)

module Dialog_add_or_update = struct

(* This function may be useful for testing the widget creation without
   recompiling the whole project. *)
let make
 ?(title="Add LAN bridge")
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
      ~image_tooltip:(s_ "LAN bridge: put the virtual machines on the real local network of this computer, through a bridge built on its network card (see the help button)")
      ~name
      ~name_tooltip:(s_ "LAN bridge name. This name must be unique in the virtual network. Suggested: B1, B2, ...")
      ?label
      ()
  in

  (* Said at the moment of the gesture, and not as an unexplained failure — or, worse,
     as a network of the host that goes away for no visible reason — when the component
     starts (work-stream modernisation-world-bridge, episodes 6 and 7b). Nothing is
     said when MARIONNET_BRIDGE names a bridge somebody else built: there Marionnet
     touches nothing, exactly as before this work-stream. *)
  let () =
    if Global_options.explicit_world_bridge_name = None then
      let notice =
        if Lan_bridge_host.is_usable () then
          (s_ "Note: when this component starts, Marionnet puts this computer's network card into a bridge, so that the virtual machines appear on your real local network. The host connection is interrupted for a fraction of a second. A Wi-Fi card cannot be used this way: prefer a NAT bridge.")
        else
          (s_ "Note: when this component starts, Marionnet asks for your password, once, in order to put this computer's network card into a bridge, so that the virtual machines appear on your real local network. The host connection is interrupted for a fraction of a second. A Wi-Fi card cannot be used this way: prefer a NAT bridge.")
      in
      let note =
        GMisc.label
          ~markup:("<i>" ^ Glib.Markup.escape_text notice ^ "</i>")
          ~xalign:0.0 ~line_wrap:true ~width:420 ~xpad:20 ~ypad:5
          ~packing:w#vbox#add ()
      in
      (* Gtk+ 3: ~width is only the *minimum* request; a wrapping label still asks
         for the whole sentence as its natural width, and the dialog obeys (measured:
         2667 pixels wide). Capping the natural width is what makes the text wrap —
         and it does so in every language, which no hand-placed line break could do. *)
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
   let title = (s_ "ADD OR MODIFY A LAN BRIDGE") in
   let msg   = (s_ "\
A LAN bridge connects your virtual network to the REAL local network of this \
computer. The virtual machines attached to it are then on the SAME physical \
network as the host itself, with real addresses (static, or from the LAN's own \
DHCP server), the real DNS, the real gateway, and the other machines of the \
room as neighbours. It also enables team-work across computers: two Marionnet \
instances running on different real machines, each with a LAN bridge, form a \
single virtual network.\n\n\
Marionnet builds that bridge ITSELF, when the component starts: it puts the \
network card of this computer into a bridge and moves the host address and \
default route onto it, then gives everything back when the component stops. \
Nothing has to be prepared beforehand. Two things follow from touching the \
host's own card, and both matter:\n\n\
- the connection of THIS COMPUTER is interrupted for a fraction of a second \
each time the bridge is built or taken down, and Marionnet asks for your \
password, once, in order to be allowed to do it;\n\
- a Wi-Fi card CANNOT be used this way (an access point refuses several \
machines behind one association): on a laptop connected over Wi-Fi, use a NAT \
bridge instead.\n\n\
There is one such bridge per computer, shared: several Marionnet instances, and \
several LAN bridge components, use the same one, and it is given back when the \
last of them has finished with it.\n\n\
LAN bridge, NAT bridge or gateway? Use a LAN BRIDGE when the virtual machines \
must appear directly on the real network of this computer, or to link \
Marionnet instances running on different machines. Use a NAT BRIDGE to reach \
the Internet without touching this computer's configuration at all — it is also \
the only one that works over Wi-Fi. Use a WORLD GATEWAY for a self-contained \
NAT router that needs no privilege whatsoever.\n\n\
Advanced use: if the variable MARIONNET_BRIDGE (in marionnet.conf or on the \
command line) names a bridge, Marionnet builds nothing and simply attaches to \
that one — the behaviour of Marionnet before it learned to build bridges by \
itself, for hosts where an administrator prepared one.")
   in Simple_dialogs.help title msg ;;

end

(*-----*)
  WHERE
(*-----*)

module Eval_forest_child = struct

 (* The subtree is still called `world_bridge': what a .mar says about this
    component has not changed, and must not (episode 7b). *)
 let try_to_add_lan_bridge (network:User_level.network) ((root,children):Xforest.tree) =
  try
   (match root with
    | ("world_bridge", attrs)
    | ("gateway" (* retro-compatibility *), attrs) ->
    	let name  = List.assoc "name"  attrs in
        Log.printf1 "Importing LAN bridge \"%s\"...\n" name;
        let x = new User_level_lan_bridge.lan_bridge ~network ~name () in
	x#from_tree ("world_bridge", attrs) children  ;
        Log.printf1 "LAN bridge \"%s\" successfully imported.\n" name;
        true
   | _ ->
        false
   )
  with _ -> false

end (* module Eval_forest_child *)


(*-----*)
  WHERE
(*-----*)


module User_level_lan_bridge = struct

class lan_bridge =

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
   ((new Simulation_level_lan_bridge.lan_bridge
        ~parent:self
        ~working_directory:(network#project_working_directory)
        ~unexpected_death_callback:self#destroy_because_of_unexpected_death
        ()) :> User_level.node Simulation_level.device)

end (* class lan_bridge *)

end (* module User_level_lan_bridge *)

(*-----*)
  WHERE
(*-----*)

module Simulation_level_lan_bridge = struct

(** The mechanism itself -- the tap, the two-port hub, the internal cable and their
    life cycle -- is the one shared with the NAT bridge (see [Bridge_common]). What
    this component adds is which host bridge its tap joins: the one Marionnet builds
    on the host's card, or the one an administrator prepared. *)
class ['parent] lan_bridge =
  fun (* ~id *)
      ~(parent:'parent)
      ~working_directory
      ~unexpected_death_callback
      () ->
  (* Whether THIS component is the reason the automatic bridge was built. Only a
     component that asked for it may give it back: `mnlan0' is shared, and a `down'
     nobody asked for could take down the bridge of another Marionnet instance. *)
  let asked_for_the_automatic_bridge = ref false in
  (* --- *)
  (* Called at start-up time, and possibly twice for a single gesture (the simulated
     object is built, then started) -- hence a memoised elevation (see Privileges)
     and an `ensure' that hands back the bridge built the first time. *)
  let resolve_bridge_name () : string =
    match Global_options.explicit_world_bridge_name with
    | Some bridge_name ->
        (* Somebody configured MARIONNET_BRIDGE: an administrator did the work, we
           keep honouring it and touch nothing on this host -- the behaviour of
           this component before it learned to build its own bridge. *)
        let () = Log.printf1 "lan_bridge: attaching to the configured host bridge %s (MARIONNET_BRIDGE)\n" bridge_name in
        bridge_name
    | None ->
        (* The scoped sudoers block of the LAN bridge is granted by the user, not by
           the administrator (docs/modernisation-world-bridge.md § 1 bis.3), and this
           is the moment it is needed. Privileges asks for the password and installs
           it; it also tells the user itself when it fails, exactly once per session,
           so here we only leave a trace in the log and carry on. *)
        let () =
          match Privileges.ensure_lanbridge () with
          | Ok () -> ()
          | Error message -> Log.printf1 "lan_bridge: no administrator rights for the LAN bridge: %s\n" message
        in
        (match Lan_bridge_host.ensure () with
         | Ok info ->
             let () = asked_for_the_automatic_bridge := true in
             let () =
               Log.printf2 "lan_bridge: using the host bridge %s (network card: %s)\n"
                 info.Lan_bridge_host.bridge
                 (match info.Lan_bridge_host.interface with Some i -> i | None -> "none")
             in
             info.Lan_bridge_host.bridge
         | Error e ->
             (* Not a new way of failing: we fall back on the configured name, so the
                component behaves exactly as it did before this work-stream -- it will
                not find its bridge, and will say so. The reason is always logged, and
                E_WIRELESS is the one users will meet: a Wi-Fi card cannot be enslaved,
                which is precisely what the NAT bridge is for. *)
             let () =
               Log.printf2
                 "lan_bridge: the LAN bridge is unavailable (%s); falling back on the configured bridge %s\n"
                 (Lan_bridge_host.string_of_error e) Global_options.ethernet_world_bridge_name
             in
             Global_options.ethernet_world_bridge_name)
  in
  (* --- *)
  (* Called once the tap has been destroyed: the host gets its card back as soon as
     nobody needs it any more -- and not one moment before, the bridge being shared. *)
  let after_terminate () : unit =
    if !asked_for_the_automatic_bridge then
      let () = asked_for_the_automatic_bridge := false in
      match Lan_bridge_host.release () with
      | Ok () -> ()
      | Error e -> Log.printf1 "lan_bridge: %s\n" (Lan_bridge_host.string_of_error e)
  in
  (* --- *)
object(_self)
  inherit ['parent] Bridge_common.Simulation_level_bridge.bridge_device
      ~parent
      ~device_type:"world_bridge"
      ~resolve_bridge_name
      ~after_terminate
      ~socket_name_prefix:"world_bridge_hub-socket-"
      ~working_directory
      ~unexpected_death_callback
      ()
end

end (* module Simulation_level_lan_bridge *)

(** Just for testing: *)
let test = Dialog_add_or_update.make
