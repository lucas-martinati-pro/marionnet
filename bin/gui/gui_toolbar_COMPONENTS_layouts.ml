(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2009, 2010  Jean-Vincent Loddo
   Copyright (C) 2009, 2010  Université Paris 13

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

(* --- *)
module StackExtra = Ocamlbricks.StackExtra
(* --- *)
open Gettext

(** Layouts for component-related menus. See the file gui_machine.ml for an example of application. *)

(** Function which appends entries to a toolbar *)
module Toolbar = struct

(* A presentation choice belongs to the palette, independently of the project.
   Keep the actual text widgets so toggling never rebuilds component menus. *)
let palettes = ref []

let set_labels_visible toolbar visible =
  List.iter (fun (owner, widgets) ->
    if owner = Gobject.get_oid toolbar#as_widget then
      List.iter (fun widget ->
        if visible then widget#misc#show () else widget#misc#hide ()) widgets
  ) !palettes

  (* Note that ~label:"" is very important in the call of GMenu.image_menu_item. Actually, it is a workaround
      of something that resemble to a bug in lablgtk: if not present, another external function is internally
      called by this function and the result is a menu entry with an horizontal line in background... *)
(*  let append_image_menu_OLD_TO_BE_REMOVED (toolbar:GButton.toolbar) filename tooltip =
    let slot    = GButton.tool_item ~packing:toolbar#insert () in
    let menubar = GMenu.menu_bar ~border_width:0 ~width:0 ~height:56 (* 60 *) ~packing:(slot#add) () in
    let image   = GMisc.image ~xalign:0.5 ~yalign:0.5 ~xpad:0 ~ypad:0 ~file:(Initialization.Path.images^filename) () in
    let result  = GMenu.image_menu_item ~label:"" ~image ~packing:menubar#add () in
    let set_tooltip w text = (GData.tooltips ())#set_tip w ~text in
    result#image#misc#show ();
    set_tooltip slot#coerce tooltip;
    result*)

(* NEW version (v0, unused), lablgtk3 compatible: *)
let append_image_menu_v0 (toolbar:GButton.toolbar) filename tooltip =
  let slot    = GButton.tool_item ~packing:toolbar#insert () in
  let box     = GPack.hbox ~border_width:2 ~packing:(slot#add) ~show:true () in
  let image   = GMisc.image ~xalign:0.5 ~yalign:0.5 ~xpad:0 ~ypad:0 ~file:(Filename.concat Initialization.Path.images filename) ~packing:(box#pack) () in
  let menubar = GMenu.menu_bar ~border_width:0 ~width:0 ~height:56 (* 60 *) ~packing:(box#pack) () in
  let result  = GMenu.menu_item ~label:"+" ~packing:menubar#add () in
  let () = image#misc#show () in
  let () = GtkBase.Widget.Tooltip.set_text slot#as_widget tooltip in
  result

(* NEW version, lablgtk3 compatible: *)
let append_image_menu (toolbar:GButton.toolbar) filename tooltip =
  let slot = GButton.tool_item ~packing:toolbar#insert () in
  let menubar = GMenu.menu_bar ~border_width:0 ~packing:slot#add () in
  let result = GMenu.menu_item ~show:true ~packing:menubar#add () in
  let row = GPack.hbox ~spacing:8 ~border_width:3 ~show:true ~packing:result#add () in
  let file = Filename.concat Initialization.Path.images filename in
  let pixbuf = GdkPixbuf.from_file_at_size file ~width:32 ~height:32 in
  let _image = GMisc.image ~pixbuf ~width:32 ~height:32 ~show:true
    ~packing:(row#pack ~expand:false) () in
  let label = match filename with
    | "ico.machine.palette.png" -> s_ "Machine"
    | "ico.hub.palette.png" -> s_ "workspace.palette.hub"
    | "ico.switch.palette.png" -> s_ "workspace.palette.switch"
    | "ico.router.palette.png" -> s_ "Router"
    | "ico.cloud.palette.png" -> s_ "workspace.palette.cloud"
    | "ico.world.palette.png" -> s_ "workspace.palette.world"
    | "ico.cable.direct.palette.png" -> s_ "workspace.palette.cable"
    | "ico.cable.crossed.palette.png" -> s_ "workspace.palette.crossover"
    | _ -> tooltip
  in
  let text = GMisc.label ~text:label ~xalign:0. ~show:false
    ~packing:(row#pack ~expand:true) () in
  let arrow = GMisc.label ~text:"▸" ~show:false ~packing:(row#pack ~expand:false) () in
  text#coerce#set_no_show_all true;
  arrow#coerce#set_no_show_all true;
  palettes := (Gobject.get_oid toolbar#as_widget, [text#coerce; arrow#coerce]) :: !palettes;
  GtkBase.Widget.Tooltip.set_text slot#as_widget tooltip;
  (try
    let provider = GObj.css_provider () in
    provider#load_from_data "menubar { background: transparent; box-shadow: none; border: none; } menuitem { border-radius: 6px; }";
    menubar#misc#style_context#add_provider provider 600;
    result#misc#style_context#add_provider provider 600
  with _ -> ());
  result

end (* module Toolbar *)

module type Toolbar_entry =
 sig
  val imagefile : string
  val tooltip   : string
  val packing   : [ `toolbar of GButton.toolbar | `menu_parent of Menu_factory.menu_parent ]
 end

module type State = sig val st:State.globalState end

module Layout_for_network_component
 (State         : sig val st:State.globalState end)
 (Toolbar_entry : Toolbar_entry)
 (Add           : Menu_factory.Entry_callbacks)
 (Properties    : Menu_factory.Entry_with_children_callbacks)
 (Remove        : Menu_factory.Entry_with_children_callbacks)
 = struct

  let menu_parent =
    match Toolbar_entry.packing with
    | `toolbar toolbar ->
         let image_menu_item = Toolbar.append_image_menu (toolbar) (Toolbar_entry.imagefile) (Toolbar_entry.tooltip) in
         Menu_factory.Menuitem (image_menu_item :> GMenu.menu_item_skel)
    | `menu_parent p -> p

  module F = Menu_factory.Make (struct
    let parent = menu_parent
    let window = State.st#mainwin#window_MARIONNET
  end)

 module Add' = struct
   include Add
   let text  = (s_ "Add")
   let stock = `ADD
   end

 module Properties' = struct
   include Properties
   let text  = (s_ "Modify")
   let stock = `PROPERTIES
   end

 module Remove' = struct
   include Remove
   let text  = (s_ "Remove")
   let stock= `REMOVE
   end

 module Created_Add        = Menu_factory.Make_entry               (Add')        (F)
 module Created_Properties = Menu_factory.Make_entry_with_children (Properties') (F)
 module Created_Remove     = Menu_factory.Make_entry_with_children (Remove')     (F)

end


module Layout_for_network_node
 (State         : sig val st:State.globalState end)
 (Toolbar_entry : Toolbar_entry)
 (Add        : Menu_factory.Entry_callbacks)
 (Properties : Menu_factory.Entry_with_children_callbacks)
 (Remove     : Menu_factory.Entry_with_children_callbacks)
 (Startup    : Menu_factory.Entry_with_children_callbacks)
 (Stop       : Menu_factory.Entry_with_children_callbacks)
 (Suspend    : Menu_factory.Entry_with_children_callbacks)
 (Resume     : Menu_factory.Entry_with_children_callbacks)
 = struct

 module Startup' = struct
   include Startup
   let text  = (s_ "Start")
   let stock = `EXECUTE
   end

 module Stop' = struct
   include Stop
   let text  = (s_ "Stop")
   let stock = `MEDIA_STOP
   end

 module Suspend' = struct
   include Suspend
   let text  = (s_ "Suspend")
   let stock = `MEDIA_PAUSE
   end

 module Resume' = struct
   include Resume
   let text  = (s_ "Resume")
   let stock = `MEDIA_PLAY
   end

 module Created_entries_for_network_component = Layout_for_network_component (State) (Toolbar_entry) (Add) (Properties) (Remove)
 module F = Created_entries_for_network_component.F
 let () = F.add_separator ()
 module Created_Startup = Menu_factory.Make_entry_with_children (Startup') (F)
 module Created_Stop    = Menu_factory.Make_entry_with_children (Stop')    (F)
 let () = F.add_separator ()
 module Created_Suspend = Menu_factory.Make_entry_with_children (Suspend') (F)
 module Created_Resume  = Menu_factory.Make_entry_with_children (Resume')  (F)

end

module Lifecycle
 (State : State)
 (Dev : sig val devkind : User_level.devkind val kind_name : unit -> string end)
 = struct

  let st = State.st

  module Remove = struct
    type t = string
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_destroy ~devkind:Dev.devkind ()
    let dialog name () =
      Gui_bricks.Dialog.yes_or_cancel_question
        ~title:(s_ "Remove")
        ~markup:(Printf.sprintf (f_ "Are you sure that you want to remove %s\nand all the cables connected to this %s?") name (Dev.kind_name ()))
        ~context:name
        ()
    let reaction name =
      let d = (st#network#get_node_by_name name) in
      let action () = d#destroy in
      st#network_change action ()
  end

  module Startup = struct
    type t = string
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_startup ~devkind:Dev.devkind ()
    let dialog     = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#startup
  end

  module Stop = struct
    type t = string
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_gracefully_shutdown ~devkind:Dev.devkind ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#gracefully_shutdown
  end

  module Suspend = struct
    type t = string
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_suspend ~devkind:Dev.devkind ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#suspend
  end

  module Resume = struct
    type t = string
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_resume ~devkind:Dev.devkind ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#resume
  end

end

module Layout_for_network_node_with_state
 (State             : sig val st:State.globalState end)
 (Toolbar_entry     : Toolbar_entry)
 (Add               : Menu_factory.Entry_callbacks)
 (Properties        : Menu_factory.Entry_with_children_callbacks)
 (Remove            : Menu_factory.Entry_with_children_callbacks)
 (Startup           : Menu_factory.Entry_with_children_callbacks)
 (Stop              : Menu_factory.Entry_with_children_callbacks)
 (Suspend           : Menu_factory.Entry_with_children_callbacks)
 (Resume            : Menu_factory.Entry_with_children_callbacks)
 (Ungracefully_stop : Menu_factory.Entry_with_children_callbacks)
 = struct

 module Ungracefully_stop' = struct
   include Ungracefully_stop
   let text  = (s_ "Power-off")
   let stock = `DISCONNECT
   end

 module Created_entries_for_network_node = Layout_for_network_node (State) (Toolbar_entry) (Add) (Properties) (Remove) (Startup) (Stop) (Suspend) (Resume)
 module F = Created_entries_for_network_node.F
 let () = F.add_separator ()
 module Created_Ungracefully_stop = Menu_factory.Make_entry_with_children (Ungracefully_stop') (F)

end


module Layout_for_network_edge
 (State             : sig val st:State.globalState end)
 (Toolbar_entry     : Toolbar_entry)
 (Add        : Menu_factory.Entry_callbacks)
 (Properties : Menu_factory.Entry_with_children_callbacks)
 (Remove     : Menu_factory.Entry_with_children_callbacks)
 (Disconnect : Menu_factory.Entry_with_children_callbacks)
 (Reconnect  : Menu_factory.Entry_with_children_callbacks)
 = struct

 module Disconnect' = struct
   include Disconnect
   let text  = (s_ "Disconnect")
   let stock = `DISCONNECT
   end

 module Reconnect' = struct
   include Reconnect
   let text  = (s_ "Re-connect")
   let stock = `CONNECT
   end

 module Created_entries_for_network_component = Layout_for_network_component (State) (Toolbar_entry) (Add) (Properties) (Remove)
 module F = Created_entries_for_network_component.F
 let () = F.add_separator ()
 module Created_Disconnect = Menu_factory.Make_entry_with_children (Disconnect') (F)
 module Created_Reconnect  = Menu_factory.Make_entry_with_children (Reconnect') (F)

 (* Cable sensitiveness *)
 module Created_Add = Created_entries_for_network_component.Created_Add
 let () = StackExtra.push (Created_Add.item#coerce) (State.st#sensitive_cable_menu_entries)

end
