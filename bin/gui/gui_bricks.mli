(* This file is part of Marionnet
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

type form = < (* object *)
  add              : GObj.widget -> unit;
  add_with_tooltip : ?just_for_label:unit -> string -> GObj.widget -> unit;
  add_section      : ?fg:string -> ?size:string -> ?no_line:unit -> string -> unit;
  set_sensitive    : label_text:string -> bool -> unit;
  coerce           : GObj.widget;
  table            : GPack.table;
  >

val make_form_with_labels :
  ?section_no:int ->
  ?row_spacings:int ->
  ?col_spacings:int ->
  ?packing:(GObj.widget -> unit) ->
  string list -> form

val wrap_with_label :
  ?tooltip:string ->
  ?packing:(GObj.widget -> unit) ->
  ?labelpos:[< `EAST | `NORTH | `SOUTH | `WEST > `NORTH ] ->
  string ->
  (< coerce : GObj.widget; .. > as 'a) -> 'a

val entry_with_label :
  ?tooltip:string ->
  ?packing:(GObj.widget -> unit) ->
  ?max_length:int ->
  ?entry_text:string ->
  ?labelpos:[< `EAST | `NORTH | `SOUTH | `WEST > `NORTH ] ->
  string -> GEdit.entry

val spin_byte :
  ?tooltip:string ->
  ?label:string ->
  ?labelpos:[< `EAST | `NORTH | `SOUTH | `WEST > `NORTH ] ->
  ?lower:int ->
  ?upper:int ->
  ?step_incr:int ->
  ?packing:(GObj.widget -> unit) ->
  int -> GEdit.spin_button

val spin_ipv4_address :
  ?tooltip:string ->
  ?byte_tooltips: string array ->
  ?label:string ->
  ?labelpos:[< `EAST | `NORTH | `SOUTH | `WEST > `NORTH ] ->
  ?packing:(GObj.widget -> unit) ->
  int -> int -> int -> int ->
  GEdit.spin_button * GEdit.spin_button * GEdit.spin_button * GEdit.spin_button

val spin_ipv4_address_with_cidr_netmask :
  ?tooltip:string ->
  ?byte_tooltips: string array ->
  ?label:string ->
  ?labelpos:[< `EAST | `NORTH | `SOUTH | `WEST > `NORTH ] ->
  ?packing:(GObj.widget -> unit) ->
  int -> int -> int -> int -> int ->
  GEdit.spin_button * GEdit.spin_button * GEdit.spin_button * GEdit.spin_button * GEdit.spin_button

val activable_entry :
  ?packing:(GObj.widget -> unit) ->
  ?homogeneous:bool ->
  ?active:bool ->
  ?text:string ->
  ?red_text_condition:(string -> bool) ->
  unit -> < active : bool;  content : string;  hbox : GPack.box;  check_button : GButton.toggle_button;  entry : GEdit.entry >

val make_tooltips_for_container :
  < connect : < destroy : callback:('a -> unit) -> 'b; .. >; .. > ->
  GObj.widget ->
  string -> unit

module Ok_callback : sig
 val check_name : string -> string -> (string->bool) -> 'a -> 'a option
end

module Dialog_run : sig

  val ok_or_cancel :
    [ `CANCEL | `DELETE_EVENT | `HELP | `OK ] GWindow.dialog ->
    get_widget_data:(unit -> 'a) ->
    ok_callback:('a -> 'b option) ->
    ?help_callback:(unit -> unit) ->
    unit -> 'b option

  val yes_or_cancel :
    [ `CANCEL | `DELETE_EVENT | `HELP | `YES ] GWindow.dialog ->
    ?help_callback:(unit -> unit) ->
    context:'a ->
    unit -> 'a option

  val yes_no_or_cancel :
    [ `CANCEL | `DELETE_EVENT | `HELP | `NO | `YES ] GWindow.dialog ->
    ?help_callback:(unit -> unit) ->
    context:'a ->
    unit -> ('a * bool) option

end (* Dialog_run *)

module Dialog : sig

  val yes_or_cancel_question :
    ?title:string ->
    ?help_callback:(unit -> unit) ->
    ?image_filename:string ->
    ?markup:string ->
    ?text:string ->
    context:'a ->
    unit -> 'a option

  val yes_no_or_cancel_question :
    ?title:string ->
    ?help_callback:(unit -> unit) ->
    ?image_filename:string ->
    ?markup:string ->
    ?text:string ->
    context:'a ->
    unit -> ('a * bool) option

end (* Dialog *)


val set_marionnet_icon : [> ] GWindow.dialog -> unit
(*   < set_icon : GdkPixbuf.pixbuf option -> 'a; .. > -> 'a = <fun> *)

type packing_function = GObj.widget -> unit

val make_combo_boxes_of_vm_installations:
  ?on_distrib_change:(string -> unit) ->
  ?on_variant_change:(string -> unit) ->
  ?on_kernel_change:(string -> unit) ->
  ?distribution:string ->
  ?variant:string ->
  ?kernel:string ->
  ?updating:unit ->
  packing:(packing_function * packing_function * packing_function) ->
  Disk.virtual_machine_installations
  ->
  Ocamlbricks.Widget.ComboTextTree.comboTextTree


module Dialog_add_or_update : sig

 val make_window_image_name_and_label :
   title:string ->
   image_file:string ->
   image_tooltip : string ->
   name:string ->
   name_tooltip : string ->
   ?label:string ->
   ?label_tooltip : string ->
   unit ->
     [ `CANCEL | `DELETE_EVENT | `HELP | `OK ] GWindow.dialog *
     GMisc.image *
     GEdit.entry *
     GEdit.entry

end

module Reactive_widget :
  sig

    type abstract_combo_box_text = (item list) * (active_index option)
     and item = string
     and active_index = int (* 0..(n-1) *)
     and node = item
     and port = item

    class combo_box_text :
      strings:string list ->
      ?active:int ->
      ?width:int ->
      ?height:int ->
      ?packing:(GObj.widget -> unit) ->
      unit ->
      object
        method cortex  : (abstract_combo_box_text) Ocamlbricks.Cortex.t
        method activate_first : unit
        method get     : string option
        method destroy : unit -> unit
      end

    type 'a power4 = 'a * 'a * 'a * 'a

    class cable_input_widget :
      ?n0:string -> ?p0:string -> ?n1:string -> ?p1:string ->
      ?width:int ->
      ?height:int ->
      ?packing_n0:(GObj.widget -> unit) ->
      ?packing_p0:(GObj.widget -> unit) ->
      ?packing_n1:(GObj.widget -> unit) ->
      ?packing_p1:(GObj.widget -> unit) ->
      free_node_port_list:(string * string) list ->
      unit ->
      object
        method destroy : unit
        method get_widget_data : (string option * string option) * (string option * string option)
        (* Just for debugging: *)
        method get_cortex_group : (abstract_combo_box_text) power4 Ocamlbricks.Cortex.t
        method get_combo_boxes  : (combo_box_text) power4
      end

    val guess_humanly_speaking_enpoints :
      ?n0:string -> ?p0:string -> ?n1:string -> ?p1:string ->
      (node * port) list ->
      (node option * port option) * (node option * port option)

end (* Reactive_widget *)

val button_image :
  (*?window:GWindow.window ->*)
  ?callback:(unit->unit) ->
  ?label:string ->
  ?label_position:[ `BOTTOM | `LEFT | `RIGHT | `TOP ] ->
  ?tooltip:string ->
  packing:(GObj.widget -> unit) ->
  ?stock:GtkStock.id ->
  ?stock_size:[ `BUTTON | `DIALOG | `DND | `INVALID | `LARGE_TOOLBAR | `MENU | `SMALL_TOOLBAR ] ->
  ?file:string ->
  unit -> GButton.button


val button_image_popuping_a_menu :
  (*?window:GWindow.window ->*)
  ?renewer:(GMenu.menu -> unit) ->
  ?label:string ->
  ?label_position:[ `BOTTOM | `LEFT | `RIGHT | `TOP ] ->
  ?tooltip:string ->
  packing:(GObj.widget -> unit) ->
  ?stock:GtkStock.id ->
  ?stock_size:[ `BUTTON | `DIALOG | `DND | `INVALID | `LARGE_TOOLBAR | `MENU | `SMALL_TOOLBAR ] ->
  ?file:string ->
  unit -> (GMenu.menu * GButton.button * GPack.box)


val make_check_items_renewer_v1 :
  get_label_active_callback_list:(unit -> (string * bool * (bool -> unit)) list) ->
  unit -> (GMenu.menu -> unit)

val make_check_items_renewer_v2 :
  get_label_active_list:(unit -> (string * bool) list) ->
  callback:(string -> bool -> unit) ->
  unit -> (GMenu.menu -> unit)

(* Example of usage:
 make_rc_config_widget
   ~packing:(form#add_with_tooltip (s_ "Check to activate a startup configuration" ))
   ~active:(fst rc_config)
   ~content:(snd rc_config)
   ~device_name:(old_name)
   ~language:("bash")
   ()
*)
val make_rc_config_widget :
  ?height:int -> ?width:int -> (* window paremeters *)
  ?filter_names:Talking.EDialog.filter_name list ->
  (* --- *)
  parent: GWindow.window_skel -> (* don't worry if the parent is a dialog: you can always perform (dialog :> GWindow.window_skel) *)
  packing:(GObj.widget -> unit) ->
  active: bool ->
  content:string ->
  device_name:string ->
  language:string ->
  unit -> (* object *) < active:bool; content:string;  set_sensitive:bool->unit > (* end *)

val make_check_button_with_related_alternatives :
  packing:(GObj.widget -> unit) ->
  active: bool ->
  ?active_alternative:int -> (* 0 *)
  ?use_markup:bool -> (* false *)
  alternatives:string list ->
  unit -> (* object *) < active:bool; selected_alternative:string option;  set_sensitive:bool->unit > (* end *)

(* Example of usage::
let notebook =
  let b1 = GButton.button ~label:"b1" () in
  let b2 = GButton.button ~label:"b2" () in
  make_notebook_of_assoc_list ~packing [("aaa", b1#coerce); ("bbb", b2#coerce)] ;;
*)
val make_notebook_of_assoc_list :
  (*?homogeneous_tabs:bool ->*)
  packing:(GObj.widget -> unit) ->
  (string * GObj.widget) list -> GPack.notebook

val make_notebook_of_assoc_array_with_check_buttons :
  ?tooltip:string -> (* s_ "Check to activate" *)
  (*?homogeneous_tabs:bool ->*)
  packing:(GObj.widget -> unit) ->
  (string * bool * GObj.widget) array -> GButton.toggle_button array


(* ---
Replace:
  let packing = toolbar#add in ...
with:
  let packing = Gui_bricks.make_toolbar_packing_function (toolbar) in ...
*)
val make_toolbar_packing_function : ?homogeneous:bool -> ?expand:bool -> ?show:bool -> GButton.toolbar -> packing_function

(* --- *)
val test : unit -> char option
