(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2010-2023  Jean-Vincent Loddo
   Copyright (C) 2010-2023  Université Paris 13

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
module Option = Ocamlbricks.Option
module Egg = Ocamlbricks.Egg
module Thunk = Ocamlbricks.Thunk

(* Ex: `id "sh" our `mime "text/x-ocaml" *)
type language_identification = [ `id of string | `mime_type of string ] ;;

(* Our `language_manager' is an object encapsulating a `GSourceView2.source_language_manager'
   with a convenient interface: *)
let language_manager () =
  let m = GSourceView3.source_language_manager ~default:false in
  object (self)

    (* For debugging: *)
    method print_list =
      let i = ref 0 in
      List.iter
	(fun id -> incr i;
	  match m#language id with
	    Some lang ->
	      let name = lang#name in
	      let section = lang#section in
	      Printf.kfprintf flush stdout "%2d: %-20s %-30s (section: %s)\n" !i id name section
	    | None -> ())
	m#language_ids

    method get_language_by_id id =
      (m#language id)

    method get_language_by_mime_type mime_type =
      (m#guess_language ~content_type:mime_type ())

    method get_language (li:language_identification) =
      match li with
      | `id x        -> self#get_language_by_id x
      | `mime_type x -> self#get_language_by_mime_type x

    method add_path ?(append:unit option) path =
      let current_list = m#search_path in
      let new_list =
	if append=None
	  then path::current_list
	  else List.append current_list [path]
      in
      m#set_search_path new_list

   initializer
     (* The file `vde_switch.lang' will be installed in the marionnet's home: *)
     self#add_path (Initialization.Path.marionnet_home)

end (* object language_manager *)

(* Redefined now as a lazy value: *)
let language_manager = lazy (language_manager ())

let window
  ?(language:language_identification option)
  ?(font_name="Monospace 11")
  ?auto_indent
  ?(right_margin_position=80)
  ?(content="")
  ?modal
  ?(height=500)
  ?(width=660)
  ?(draw_spaces=[`SPACE; `NEWLINE])
  ?close_means_cancel
  (* not as window (in order to be drawn on top of another dialog). This information carry out the window_skel parent: *)
  ?(create_as_dialog : GWindow.window_skel option)
  ?(position=`CENTER)
  ~title
  ~(result:(string option) Egg.t)
  ()
  =
  let modal = Option.to_bool modal in
  let (win, vbox, win_connect_destroy) =
    match create_as_dialog with
    | None ->
        let win = GWindow.window ~modal ~title ~position ~height ~width () in
        let () = win#set_destroy_with_parent true in
        ((win :> GWindow.window_skel), GPack.vbox ~packing:win#add (), win#connect#destroy)
    | Some parent ->
        let win = GWindow.dialog ~parent ~destroy_with_parent:true ~modal ~title ~position ~height ~width () in
        ((win :> GWindow.window_skel), win#vbox, win#connect#destroy)
  in
  (* --- *)
  let scrolled_win = GBin.scrolled_window
      ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC
      ~packing:vbox#add (* ~height ~width *)
      ()
  in
  (* --- *)
  let set_expand x = begin
    x#coerce#set_expand  true;
    x#coerce#set_hexpand true;
    x#coerce#set_vexpand true;
    end
  in
  let () = set_expand (vbox) in
  let () = set_expand (scrolled_win) in
  (* --- *)
  (*  val GSourceView3.source_view :
        ?source_buffer:source_buffer ->
        ?draw_spaces:SourceView3Enums.source_draw_spaces_flags list ->
        ?auto_indent:bool ->
        ?highlight_current_line:bool ->
        ?indent_on_tab:bool ->
        ?indent_width:int ->
        ?insert_spaces_instead_of_tabs:bool ->
        ?right_margin_position:int ->
        ?show_line_marks:bool ->
        ?show_line_numbers:bool ->
        ?show_right_margin:bool ->
        ?smart_home_end:SourceView3Enums.source_smart_home_end_type ->
        ?tab_width:int ->
        ?editable:bool ->
        ?cursor_visible:bool ->
        ?justification:GtkEnums.justification ->
        ?wrap_mode:GtkEnums.wrap_mode ->
        ?accepts_tab:bool ->
        ?border_width:int ->
        ?width:int ->
        ?height:int ->
        ?packing:(GObj.widget -> unit) ->
        ?show:bool ->
        unit -> source_view *)
  let source_view =
    GSourceView3.source_view
      ~auto_indent:(Option.to_bool auto_indent)
      ~insert_spaces_instead_of_tabs:true
      ~tab_width:2
      ~show_line_numbers:true
      ~right_margin_position
      ~show_right_margin:true
      ~packing:(scrolled_win#add)
      ~highlight_current_line:true
      (* ~height ~width *)
      ()
  in
  let hbox = GPack.hbox ~packing:vbox#add ~homogeneous:true () in
  vbox#set_child_packing ~expand:false ~fill:false hbox#coerce;
  let button_cancel = GButton.button ~stock:`CANCEL ~packing:hbox#add () in
  let button_ok = GButton.button ~stock:`OK ~packing:hbox#add () in
  List.iter (fun w -> hbox#set_child_packing ~expand:false ~fill:false w#coerce) [button_cancel; button_ok];
  let language_manager = Lazy.force language_manager in
  let lang = Option.bind language (language_manager#get_language) in
  (* let () = Option.iter (fun l -> Printf.kfprintf flush stderr "gui_source_editing: lang=%s\n" l#name) lang in *)
  (* --- *)
  (* lablgtk3 doesn't accept this:
       win#set_allow_shrink true;
     *)
  (* --- *)
  source_view#misc#modify_font_by_name font_name;
  source_view#source_buffer#set_highlight_matching_brackets true;
  source_view#source_buffer#set_language lang;
  source_view#source_buffer#set_highlight_syntax true;
  source_view#set_smart_home_end `AFTER;
  source_view#set_draw_spaces draw_spaces;
  source_view#source_buffer#begin_not_undoable_action ();
  source_view#source_buffer#set_text content;
  source_view#source_buffer#end_not_undoable_action ();
  let get_text () = Some (source_view#source_buffer#get_text ()) in
  (* Callbacks. Note that the egg is released before destroying the window,
     because this action provoke the execution of the close_callback, that
     may release another result. Callbacks are linearized in order to prevent
     to call them twice (callback -> win#destroy -> callback). *)
  let cancel_callback =
    Thunk.linearize (fun () -> Egg.release result None; win#destroy ())
  in
  let ok_callback =
    Thunk.linearize (fun () -> Egg.release result (get_text ()); win#destroy ())
  in
  let close_callback =
    if close_means_cancel=None then ok_callback else cancel_callback
  in
  ignore (button_cancel#connect#clicked ~callback:cancel_callback);
  ignore (button_ok#connect#clicked ~callback:ok_callback);
  ignore (win_connect_destroy close_callback);
  (* --- *)
  win#misc#grab_focus ();
  win#show ();
;;
