(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008, 2009  Luca Saiu
   Copyright (C) 2009, 2010, 2012  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2009, 2010, 2012  Université Paris 13

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

(* To do: this could be moved to WIDGET/ *)

(* Several comments below refer to "B6": it is the identifier, in the audit of the work-stream
   "marionnet-automate-composants" (docs/refonte-automate-composants.md), of the defect that
   made this treeview drift from the network model — reading a column of the Gtk+ model gave
   back, now and then, a value whose first word had been overwritten, so a row that was present
   was reported as missing. The lesson is written in the code where it applies: identities and
   values are read from the internal forest, never from the widget. *)

(* --- *)
module Log = Marionnet_log
module ListExtra = Ocamlbricks.ListExtra
module Counter = Ocamlbricks.Counter
module Forest = Ocamlbricks.Forest
module Oomarshal = Ocamlbricks.Oomarshal
module Option = Ocamlbricks.Option
module SetExtra = Ocamlbricks.SetExtra
(* --- *)

open Gettext

(* The data of a treeview - a row and its items - lives in [Treeview_row], a module of the
   library `marionnet_base' which knows nothing about Gtk+, so that the JSON codec of what
   a treeview saves can be unit-tested without a display (work-stream
   `migration-marshal-to-text', episode 3). Their historical names are kept here, which is
   why no caller of [Treeview.Row] / [Treeview.Row_item] had to change: *)
module Row_item = Treeview_row.Row_item
module Row      = Treeview_row.Row


module Backward_compatibility = struct

 open Forest_backward_compatibility

 type row        = (string * row_item) list
  and row_item   = String of string | CheckBox of bool | Icon of string
  and row_forest = row forest

 let import_row_item = function
 | String   s -> Row_item.String s
 | CheckBox b -> Row_item.CheckBox b
 | Icon s     -> Row_item.Icon s

 let import_row = List.map (function (field, row_item) -> (field, import_row_item row_item))

 let import_row_forest f =
  Forest.map (import_row) (forest_conversion f)

 (* Main module's function: *)
 let load_from_old_file (file_name) : (int * Row.t Forest.t) =
   let m = new Oomarshal.marshaller in
   (* Loading forest in the old format: *)
   let (next_identifier : int), (complete_forest : row_forest) =
      m#from_file (file_name)
   in
   (* Conversion to the new format: *)
   let complete_forest = import_row_forest (complete_forest) in
   (* --- *)
   (next_identifier, complete_forest)

end (* Backward_compatibility *)

(* type row_id = int;; *)
type row_id = string;;

module Defaults = struct
 let highlight_foreground_color = "Black";;
 let highlight_color = "Bisque";;
end;;

type column_type =
  | StringColumnType
  | CheckBoxColumnType
  | IconColumnType;;

class virtual column =
let last_used_id = ref 0 in
fun ~(hidden:bool)
    ~(reserved:bool)
    ?(default:(unit -> Row_item.t) option)
    ~(header:string)
    ?(shown_header=header)
    ?constraint_predicate:(constraint_predicate = (fun (_ : Row_item.t) -> true))
    () ->
let () = last_used_id := !last_used_id + 1 in
let _ =
  if reserved then
    match default with
      Some _ -> ()
    | None   -> failwith ("The column "^ header ^" is reserved but has no default")
  else ()
in
object(self)
  val id = !last_used_id
  method id = id

  method header = header
  method shown_header = shown_header
  method hidden = hidden
  method is_reserved =reserved
  (* Whether a human may type into this column: only [editable_string_column] overrides it, and
     it is exactly the column class whose renderer carries `EDITABLE true. Without this predicate
     the distinction is lost the moment a column is added, since #add_column coerces it to
     [column] (l.1078) — and a caller wanting the writable vocabulary (control_server.ml,
     ifconfig-set) would have to hard-code a list of headers, which is what publishing #columns
     was meant to avoid. *)
  method is_editable = false
  method has_default =
    match default with
      Some _ -> true
    | None -> false
  method default =
    match default with
      Some default -> default
    | None -> failwith (self#header ^ " has no default value, hence it must be specified")
  method virtual can_contain : Row_item.t -> bool
  method virtual gtree_column : 'a . 'a GTree.column
  method virtual append_to_view : GTree.view -> unit
  method virtual get : string -> Row_item.t
  method virtual set : ?initialize:bool -> ?row_iter:Gtk.tree_iter -> ?ignore_constraints:bool -> string -> Row_item.t -> unit

  val gtree_view_column = ref None

  method set_gtree_view_column (the_gtree_view_column : GTree.view_column) =
    gtree_view_column := Some the_gtree_view_column

  method gtree_view_column =
    match !gtree_view_column with
      None ->
        failwith "set_gtree_view_column has not been called"
    | Some the_gtree_view_column ->
        the_gtree_view_column
end;;

type constraint_name = string ;;
type column_header = string ;;

exception RowConstraintViolated    of constraint_name ;;
exception ColumnConstraintViolated of column_header ;;

class string_column = fun
    ~(treeview:treeview)
    ?hidden:(hidden=false)
    ?reserved:(reserved=false)
    ?default
    ?italic:(italic=false)
    ?bold:(bold=false)
    ~(header:string)
    ?(shown_header)
    ?constraint_predicate:(constraint_predicate = (fun (_ : Row_item.t) -> true))
    () ->
  object(self)

  inherit column ~hidden ~reserved ?default ~header ?shown_header ~constraint_predicate () (* as super *)

  method can_contain x =
    constraint_predicate x
  val gtree_column : ('a GTree.column) =
    (treeview#gtree_column_list :> GTree.column_list)#add Gobject.Data.string
  method gtree_column (* Ugly kludge which I need to overcome countervariance restrictions *) =
    Obj.magic gtree_column

  method append_to_view (view : GTree.view) =
    let column = (self :> column) in
    let renderer =
      GTree.cell_renderer_text
        [ `EDITABLE false;
          `FOREGROUND treeview#get_highlight_foreground_color;
          `STYLE (if italic then `ITALIC else `NORMAL);
          `WEIGHT (if bold then `BOLD else `NORMAL); ]
    in
    let highlight_column = (treeview#get_column "_highlight" :> column) in
    let highlight_color_column = (treeview#get_column "_highlight-color" :> column) in
    let col = GTree.view_column
        ~title:self#shown_header
        ~renderer:(renderer, [ "text", column#gtree_column;
                               "foreground_set", (highlight_column#gtree_column);
                               "cell_background_set", (highlight_column#gtree_column);
                               "cell_background", (highlight_color_column#gtree_column); ])
        () in
    let _ = view#append_column col in
    col#set_resizable true;
    self#set_gtree_view_column col

  (* B6 (episode 14): read from the internal forest, not from the widget — see the long comment
     in icon_column#append_to_view. Cheaper too: a hashtable lookup instead of resolving a path
     and crossing the GValue conversion. *)
  method get row_id =
    Row_item.String
      (Row.String_field.get
         ~caller:"Treeview.string_column#get" ~field:self#header
         (treeview#get_complete_row row_id))

  method set ?(initialize=false) ?row_iter ?(ignore_constraints=false) row_id item =
    (if not (self#header = "_id") then
       (if not initialize then begin
          let current_row =
            treeview#get_complete_row row_id in
          let new_row = Row.set_field ~field:self#header ~value:item current_row in
            (if not ignore_constraints then
               treeview#check_constraints new_row);
            (* Ok, if we arrived here then no constraint is violated by the update. *)
            treeview#set_row row_id new_row;
        end));
    let tree_iter =
      match row_iter with
        | None -> treeview#id_to_iter row_id
        | Some row_iter -> row_iter in
    let store = (treeview#store :> GTree.tree_store) in
    match item with
      Row_item.String s ->
        store#set
          ~row:tree_iter
          ~column:self#gtree_column
          s
    | _ ->
        failwith (Printf.sprintf "set: wrong datum type for string column %s" self#header)
end

and (*class *) editable_string_column =
fun ~(treeview:treeview)
    ?hidden:(hidden=false)
    ?reserved:(reserved=false)
    ?default
    ~(header:string)
    ?(shown_header)
    ?constraint_predicate:(constraint_predicate = (fun (_ : Row_item.t) -> true))
    ?italic:(italic=false)
    ?bold:(bold=false)
    () -> object(self)
  inherit string_column ~hidden ~reserved ?default ~treeview ~header ?shown_header
                        ~constraint_predicate ~italic ~bold () (* as super *)

  method! can_contain x =
    constraint_predicate x

  method! is_editable = true

  method! append_to_view (view : GTree.view) =
    let column = (self :> column) in
    let highlight_column = treeview#get_column "_highlight" in
    let highlight_color_column = treeview#get_column "_highlight-color" in
    let renderer =
      GTree.cell_renderer_text
        [ `EDITABLE true;
          `FOREGROUND treeview#get_highlight_foreground_color;
          `STYLE (if italic then `ITALIC else `NORMAL);
          `WEIGHT (if bold then `BOLD else `NORMAL); ]
    in
    let col = GTree.view_column
        ~title:self#shown_header
        ~renderer:(renderer, [ "text", column#gtree_column;
                               "foreground_set", (highlight_column#gtree_column);
                               "cell_background_set", (highlight_column#gtree_column);
                               "cell_background", (highlight_color_column#gtree_column); ])
        ()
    in
    let _ = view#append_column col in
    ignore(renderer#connect#edited ~callback:(fun path new_content -> self#on_edit path new_content));
    col#set_resizable true;
    self#set_gtree_view_column col

  val before_edit_commit_callback = ref (fun _ _ _ -> ())
  val after_edit_commit_callback = ref (fun _ _ _ -> ())

  method private on_edit path new_content =
    let id = treeview#path_to_id path in
    let old_content =
      match self#get id with
        Row_item.String s -> s
      | _ -> assert false in
    (try
      (!before_edit_commit_callback) id old_content new_content;
      self#set id (Row_item.String new_content);
      (!after_edit_commit_callback) id old_content new_content;
      treeview#run_after_update_callback id;
    with e -> begin
      Log.printf1
        "Treeview.editable_string_column#on_edit: a callback raised an exception (%s), or a constraint was violated.\n"
        (Printexc.to_string e);
      flush_all ();
    end);

  (** Bind a callback to be called just before an edit is committed to data structures.
      The callback parameters are the row id, the old and the new content. If the callback
      throws an exception then no modification is committed, and the after_edit_commit
      callback is not called. *)
  method set_before_edit_commit_callback (callback : string -> string -> string -> unit) =
    before_edit_commit_callback := callback

  (** Bind a callback to be called just *after* an edit is committed to data structures.
      The callback parameters are the row id, the old and the new content. *)
  method set_after_edit_commit_callback (callback : string -> string -> string -> unit) =
    after_edit_commit_callback := callback
end

and (*class *) checkbox_column =
fun ~(treeview:treeview)
    ?hidden:(hidden=false)
    ?reserved:(reserved=false)
    ?default
    ~(header:string)
    ?(shown_header)
    ?constraint_predicate:(constraint_predicate = (fun (_ : Row_item.t) -> true))
    () -> object(self)
  inherit column ~hidden ~reserved ?default ~header ?shown_header
                 ~constraint_predicate () (* as super *)

  method append_to_view (view : GTree.view) =
    let highlight_column = treeview#get_column "_highlight" in
    let highlight_color_column = treeview#get_column "_highlight-color" in
    let renderer = GTree.cell_renderer_toggle [ `ACTIVATABLE true; `RADIO false; ] in
    let col = GTree.view_column
        ~title:self#shown_header
        ~renderer:(renderer, [ "active", self#gtree_column;
                               "cell_background_set", (highlight_column#gtree_column);
                               "cell_background", (highlight_color_column#gtree_column); ])
        ()
    in
    let _ = renderer#connect#toggled ~callback:(fun path -> self#on_toggle path) in
    let _ = view#append_column col in
    col#set_resizable true;
    self#set_gtree_view_column col

  (* B6 (episode 14): read from the internal forest, not from the widget. *)
  method get row_id =
    Row_item.CheckBox
      (Row.CheckBox_field.get
         ~caller:"Treeview.checkbox_column#get" ~field:self#header
         (treeview#get_complete_row row_id))

  method set ?(initialize=false) ?row_iter ?(ignore_constraints=false) row_id (item : Row_item.t) =
    (if not initialize then begin
       let current_row = treeview#get_complete_row row_id in
       let new_row = Row.set_field ~field:self#header ~value:item current_row in
         (if not ignore_constraints then
            treeview#check_constraints new_row);
         (* Ok, if we arrived here then no constraint is violated by the update. *)
         treeview#set_row row_id new_row;
    end);
    let tree_iter =
      match row_iter with
        | None -> treeview#id_to_iter row_id
        | Some row_iter -> row_iter in
    let store = (treeview#store :> GTree.tree_store) in
    match item with
      Row_item.CheckBox value ->
        store#set
          ~row:tree_iter
          ~column:self#gtree_column
          value
    | _ ->
        failwith (Printf.sprintf "set: wrong datum type for checkbox column %s" self#header)

  method can_contain x =
    constraint_predicate x
  val gtree_column =
    (treeview#gtree_column_list :> GTree.column_list)#add Gobject.Data.boolean
  method gtree_column (* Ugly kludge which I need to overcome countervariance restrictions *) =
    Obj.magic gtree_column

  val before_toggle_commit_callback = ref (fun _ _ _ -> ())
  val after_toggle_commit_callback = ref (fun _ _ _ -> ())

  method on_toggle path =
    let id = treeview#path_to_id path in
    let old_content =
      match self#get id with
        Row_item.CheckBox value -> value
      | _ -> assert false in
    let new_content = not old_content in
    (try
      (!before_toggle_commit_callback) id old_content new_content;
      self#set id (Row_item.CheckBox new_content);
      (!after_toggle_commit_callback) id old_content new_content;
      treeview#run_after_update_callback id;
    with _ -> begin
      Log.printf "Treeview.checkbox_column#on_toggle: a callback raised an exception, or a constraint was violated.\n";
    end);

  (** Bind a callback to be called just before an toggle is committed to data structures.
      The callback parameters are the row id, the old and the new value. If the callback
      throws an exception then no modification is committed, and the after_toggle_commit
      callback is not called. *)
  method set_before_toggle_commit_callback (callback : row_id -> bool -> bool -> unit) =
    before_toggle_commit_callback := callback

  (** Bind a callback to be called just *after* an toggle is committed to data structures.
      The callback parameters are the row id, the old and the new value. *)
  method set_after_toggle_commit_callback (callback : row_id -> bool -> bool -> unit) =
    after_toggle_commit_callback := callback

  method append_after_toggle_commit_callback (callback : row_id -> bool -> bool -> unit) =
    let current = !after_toggle_commit_callback in
    after_toggle_commit_callback := (fun r b0 b1 -> (current r b0 b1); callback r b0 b1)

end

and (*class *) icon_column =
fun ~(treeview:treeview)
    ?hidden:(hidden=false)
    ?reserved:(reserved=false)
    ?default
    ~(header:string)
    ?(shown_header)
    ~(strings_and_pixbufs:(string * (* To do: gdkpixbuf *) string) list)
    () ->
let strings_and_pixbufs =
  List.map
    (fun (name, pixbuf_pathname) ->
      name, (GdkPixbuf.from_file pixbuf_pathname))
    strings_and_pixbufs in
object(self)
  inherit column ~hidden ~reserved ?default ~header ?shown_header () (* as super *)

  method private lookup predicate =
    let singleton = List.filter predicate strings_and_pixbufs in
    if not ((List.length singleton) = 1) then begin
      Log.printf1 "Treeview.icon_column#lookup: ERROR: icon name lookup failed: found %i results instead of 1\n" (List.length singleton);
      List.iter
        (fun (name, pixbuf) ->
          Log.printf2
            "(predicate is %s for %s)\n"
            (if predicate (name, pixbuf) then "true" else "false")
            name)
        strings_and_pixbufs;
      failwith "Icon lookup failed"
    end else
      List.hd singleton

  method private lookup_by_string string =
    self#lookup (fun (string_, _) -> string_ = string)

  method private lookup_by_pixbuf pixbuf =
    self#lookup (fun (_, pixbuf_) -> pixbuf_ = pixbuf)

  method can_contain x =
    (* If lookup_by_string doesn't fail then x is safe: *)
    match x with
      (Row_item.Icon icon) ->
        (try
          ignore (self#lookup_by_string icon);
          true;
        with _ ->
          false)
    | _ ->
        false

  val gtree_column =
    (treeview#gtree_column_list :> GTree.column_list)#add Gobject.Data.string

  method gtree_column (* Ugly kludge which I need to overcome countervariance restrictions *) =
    Obj.magic gtree_column

  (* B6 (episode 6): a transparent pixbuf of the size of the known icons, shown when a value
     matches no icon. Leaving `PIXBUF unset in that case would not leave the cell empty: Gtk
     reuses the same renderer for every cell, so the cell would silently inherit the icon of the
     previously rendered row. *)
  val blank_pixbuf = lazy
    (let width, height =
       match strings_and_pixbufs with
       | (_, pixbuf) :: _ -> (GdkPixbuf.get_width pixbuf), (GdkPixbuf.get_height pixbuf)
       | []               -> 16, 16
     in
     let pixbuf = GdkPixbuf.create ~width ~height ~has_alpha:true () in
     let () = GdkPixbuf.fill pixbuf 0l in (* fully transparent *)
     pixbuf)

  method append_to_view (view : GTree.view) =
    let highlight_column = treeview#get_column "_highlight" in
    let highlight_color_column = treeview#get_column "_highlight-color" in
    (* B6 (episode 6): a cell_data_func is called by Gtk's C code and replayed at every redraw, so
       raising from here escapes through a C stack — that is the origin of the
       "CRITICAL: gtk_tree_cell_data_func ... Icon lookup failed" of journal 56. A rendering
       function must be total: an unknown value is now logged and drawn blank, instead of killing
       the redraw of the whole treeview. *)
    (* B6 (episode 14): and the icon name is no longer read from the widget at all. Reading a
       string column of the Gtk model is not reliable in this stack: the returned string has the
       right length and a correct tail, but its first word is overwritten by a heap address
       (0x56A90F… in one run, 0x5DD0D3… in the next: constant within a run, so an address, and
       glibc's brk range rather than OCaml's). The internal forest is the source of truth, exactly
       as for identities since episodes 5 and 6 — this was the last read of a *value* from the
       widget on a hot path. Only the *structure* is still asked of the model: the path of the row.
       Measured, not guessed: 21 and 43 occurrences in the two runs of episode 14, and the
       hypothesis of a garbage collection artefact was refuted there (a 256 MB minor heap, i.e.
       almost no minor collection, did not lower the count). *)
    let icon_name_of_iter (model : GTree.model) iter =
      match treeview#path_to_id_opt (model#get_path iter) with
      | None    -> failwith "the internal forest has no row at this path"
      | Some id ->
          Row.Icon_field.get
            ~caller:"Treeview.icon_column: cell renderer" ~field:self#header
            (treeview#get_complete_row id)
    in
    let icon_cell_data_function =
      (fun renderer (model:GTree.model) iter ->
        let pixbuf =
          try
            let (_, pixbuf) = self#lookup_by_string (icon_name_of_iter model iter) in
            pixbuf
          with e ->
            let () =
              Log.printf2 ~force:true
                "Treeview.icon_column#append_to_view: WARNING: column \"%s\": no icon for this row (%s); drawing an empty cell\n"
                self#header (Printexc.to_string e)
            in
            Lazy.force blank_pixbuf
        in
        renderer#set_properties [ `PIXBUF pixbuf; `MODE `ACTIVATABLE ]) in
    let icon_renderer =
      GTree.cell_renderer_pixbuf [ (* `CELL_BACKGROUND highlight_background_color; *) ] in

(*  ~callback:(fun path new_content -> self#on_edit path new_content) *)
    let col = GTree.view_column
        ~title:self#shown_header
        ~renderer:(icon_renderer, [ "cell_background_set", (highlight_column#gtree_column);
                                    "cell_background", (highlight_color_column#gtree_column);])
        () in
    col#set_cell_data_func icon_renderer (icon_cell_data_function icon_renderer);
    ignore (view#append_column col);
    col#set_resizable true;
    self#set_gtree_view_column col

  (* B6 (episode 14): read from the internal forest, not from the widget. *)
  method get row_id =
    Row_item.Icon
      (Row.Icon_field.get
         ~caller:"Treeview.icon_column#get" ~field:self#header
         (treeview#get_complete_row row_id))

  method set ?(initialize=false) ?row_iter ?(ignore_constraints=false) row_id (item : Row_item.t) =
    (if not initialize then begin
       let current_row = treeview#get_complete_row row_id in
       let new_row = Row.set_field ~field:self#header ~value:item current_row  in
         (if not ignore_constraints then
            treeview#check_constraints new_row);
         (* Ok, if we arrived here then no constraint is violated by the update. *)
         treeview#set_row row_id new_row;
    end);
    let tree_iter =
      match row_iter with
        | None -> treeview#id_to_iter row_id
        | Some row_iter -> row_iter in
    let store = (treeview#store :> GTree.tree_store) in
    match item with
      Row_item.Icon name ->
        store#set
          ~row:tree_iter
          ~column:self#gtree_column
          name
    | _ ->
        failwith (Printf.sprintf "set: wrong datum type for icon column %s" self#header)
end

and (* class *) treeview = fun
  ?(hide_reserved_fields=true)
  ?(highlight_foreground_color=Defaults.highlight_foreground_color)
  ?(highlight_color=Defaults.highlight_color)
  ~packing
  ~method_directory
  ~method_filename
  () ->
let gtree_column_list = new GTree.column_list in
let vbox =
  GPack.box `VERTICAL ~homogeneous:false ~packing ~spacing:0 () in
let hbox =
  GPack.box
    `HORIZONTAL
    ~homogeneous:false
    ~packing:(vbox#pack ~expand:true ~padding:0)
    ~spacing:0
    ()
in
(* The most important widget here: *)
let view =
  GTree.view
    ~packing:(hbox#pack ~expand:true ~padding:0)
    ~reorderable:false (* Drag 'n drop for lines would be very cool, but here we need *)
                       (* to keep our internal forest data structure consistent with the UI *)
    ~enable_search:false
    ~headers_visible:true
    ~headers_clickable:true
    ~rules_hint:true
    ()
in
let _ =
  GRange.scrollbar
    `VERTICAL
    ~adjustment:view#vadjustment
    ~packing:(hbox#pack ~expand:false ~padding:0)
    () in
let _ =
  GRange.scrollbar
    `HORIZONTAL
    ~adjustment:view#hadjustment
    ~packing:(vbox#pack ~expand:false ~padding:0)
    () in
let counter = new Counter.c ~initial_value:0 () in
object(self)

  (* To allow a low-level access: *)
  method view = view

  method gtree_column_list : GTree.column_list = gtree_column_list
  method counter = counter

  val mutable highlight_foreground_color = highlight_foreground_color
  method get_highlight_foreground_color = highlight_foreground_color
  method set_highlight_foreground_color x = highlight_foreground_color <- x

  val mutable highlight_color = highlight_color
  method get_highlight_color = highlight_color
  method set_highlight_color x = highlight_color <- x

  val tree_store = ref None

  val id_forest =
    ref Forest.empty

  val get_column =
    Hashtbl.create 100

  method get_column header =
    try
      ((Hashtbl.find get_column header) :> column)
    with e -> begin
      Log.printf2 "Treeview.treeview#get_column: failed in looking for column \"%s\" (%s)\n" header (Printexc.to_string e);
      raise e; (* re-raise *)
    end

  (* Special case: any treeview will contain this column (initialized here, see later): *)
  val mutable the_highlight_checkbox_column : checkbox_column option = None
  (* --- *)
  method set_highlight_checkbox_column (checkbox_column) : unit =
    the_highlight_checkbox_column <- Some checkbox_column
  (* --- *)
  method get_highlight_checkbox_column : checkbox_column =
    Option.extract (the_highlight_checkbox_column)
  (* --- *)

  (* Useful to filter information loaded from uncompatible files: *)
  method column_headers =
    Hashtbl.fold (fun k _ ks -> k::ks) (get_column) []

  method is_column_reserved header =
    let column = self#get_column header in
    column#is_reserved

  val id_to_row =
    Hashtbl.create 1000

  val columns : column list ref =
    ref []

  val id_column : column option ref =
    ref None

  val after_update_callback = ref (fun _ -> ())

  method set_after_update_callback f =
    after_update_callback := f

  method run_after_update_callback row_id =
    !after_update_callback row_id

  val row_constraints = ref []
  method add_row_constraint
      ?name:(name="<unnamed row constraing>")
      row_constraint =
    row_constraints := (name, row_constraint) :: !row_constraints

  val expanded_row_ids : (string, unit) Hashtbl.t = Hashtbl.create 1000;

  method private row_constraints = !row_constraints

  (* The verdict alone, with no dialog and no exception: the caller decides how to report it.
     Extracted at episode 5b of [marionnet-pilotage-par-script] because the control server must
     refuse an ifconfig write with a JSON answer, not with a window — while running exactly the
     checks the GUI runs, rather than a validation of its own. One source of truth, two messages
     (same shape as User_level.check_new_name at episode 4d-2c). *)
  method constraints_verdict complete_row : [ `Row of constraint_name | `Column of column_header ] option =
    let violated_row_constraint =
      List.find_opt
        (fun (_name, row_constraint) -> not (row_constraint complete_row))
        self#row_constraints
    in
    match violated_row_constraint with
    | Some (name, _) -> Some (`Row name)
    | None ->
        (match
           List.find_opt
             (fun (header, value) -> not ((self#get_column header)#can_contain value))
             complete_row
         with
         | Some (header, _) -> Some (`Column header)
         | None             -> None)

  method check_constraints complete_row =
    match self#constraints_verdict complete_row with
    | None -> ()
    | Some (`Row name) ->
        Simple_dialogs.error
          "Invalid value: row constraint violated"
          (Printf.sprintf
             "The value you have chosen for a treeview element violates the row constraint \"%s\"."
             name)
          ();
        raise (RowConstraintViolated name)
    | Some (`Column header) ->
        Simple_dialogs.error
          "Invalid column value"
          (Printf.sprintf
             "The value you have chosen for an element of the column \"%s\" is invalid."
             header)
          ();
        raise (ColumnConstraintViolated header)

  method columns =
    !columns

  val double_click_on_row_callback  = ref (fun (id:string) -> ())
  val simple_click_on_row_callback  = ref (fun (id:string) -> ())
  val collapse_row_callback         = ref (fun (id:string) -> ())
  val expand_row_callback           = ref (fun (id:string) -> ())
  val on_cursor_changed_callback    = ref (fun () -> ())
  val on_selection_changed_callback = ref (fun () -> ())

  method set_double_click_on_row_callback (callback) =
    double_click_on_row_callback := callback

  method set_simple_click_on_row_callback (callback) =
    simple_click_on_row_callback := callback

  method set_collapse_row_callback (callback) =
    collapse_row_callback := callback

  method set_expand_row_callback (callback) =
    expand_row_callback := callback

  method set_on_cursor_changed_callback (callback) =
    on_cursor_changed_callback := callback

  method append_on_cursor_changed_callback (callback) =
    let current = !on_cursor_changed_callback in
    on_cursor_changed_callback := (fun () -> current (); callback ())

  method set_on_selection_changed_callback (callback) =
    on_selection_changed_callback := callback

  method append_on_selection_changed_callback (callback) =
    let current = !on_selection_changed_callback in
    on_selection_changed_callback := (fun () -> current (); callback ())

  (** This returns the just-created column *)
  method private add_column (column : column) : unit =
    columns := !columns @ [ column ];
    Hashtbl.add get_column column#header column

  method private on_cursor_changed () =
    Log.printf ~v:2 "Treeview: cursor changed\n";
    !on_cursor_changed_callback ()

  method private on_selection_changed () =
    Log.printf ~v:2 "Treeview: selection changed\n";
    !on_selection_changed_callback ()

  method private on_row_activation path column =
    let id : string = self#path_to_id path in
    !double_click_on_row_callback id

  method private on_row_collapse iter _ =
    let id = self#iter_to_id iter in
    Hashtbl.remove expanded_row_ids id;
    !collapse_row_callback id

  method private on_row_expand iter _ =
    let id = self#iter_to_id iter in
    Hashtbl.add expanded_row_ids id ();
    !expand_row_callback id

  method unselect =
    view#selection#unselect_all ()

  method select_row row_id =
    view#selection#select_path (self#id_to_path row_id)

  method selected_row_id : string option =
    match view#selection#get_selected_rows with
      [] -> None
    | path :: [] -> (Some (self#path_to_id path))
    | _ -> assert false

  method selected_row =
    match self#selected_row_id with
      None -> None
    | Some id -> Some (self#get_row id)

  val menu_items = ref []

  val contextual_menu_title = ref "Treeview commands"

  method set_contextual_menu_title title =
    contextual_menu_title := title

  method add_menu_item label predicate callback =
    menu_items := !menu_items @ [ Some(label, predicate, callback) ]

  method add_separator_menu_item =
    menu_items := !menu_items @ [ None ]

  (* Also update the selection to be just the pointed row, if any: *)
  method private selected_row_id_of_event (event) : string option =
    let x = int_of_float (GdkEvent.Button.x event) in
    let y = int_of_float (GdkEvent.Button.y event) in
    let selected_row_id =
      (match view#get_path_at_pos ~x ~y with
        Some (path, _, _, _) ->
          let id = self#path_to_id path in
          self#select_row id;
          Some id
      | None ->
          self#unselect;
          None)
    in
    selected_row_id

  method private show_contextual_menu (event) =
    let selected_row_id = self#selected_row_id_of_event (event) in
    Log.printf ~v:2 "Treeview: showing the contextual menu\n";
    let menu = GMenu.menu () in
    List.iter
      (fun menu_item ->
         match menu_item with
           Some(label, predicate, callback) ->
             if predicate selected_row_id then
               let menu_item = GMenu.menu_item ~label ~packing:menu#append () in
             ignore (menu_item#connect#activate
                       ~callback:(fun () -> callback selected_row_id))
         | None ->
           ignore (GMenu.separator_item ~packing:menu#append ()))
      !menu_items;
    menu#popup ~button:(GdkEvent.Button.button event) ~time:(GdkEvent.Button.time event)

  method private button_press_callback (event) =
    let selected_row_id = self#selected_row_id_of_event (event) in
    Log.printf ~v:2 "Treeview: button press callback\n";
    Option.iter (!simple_click_on_row_callback) selected_row_id;
    ()

  method create_store_and_view =
    let the_tree_store = GTree.tree_store gtree_column_list in
    tree_store := Some the_tree_store;
    List.iter
      (fun column ->
        if not column#hidden then
          column#append_to_view view)
      self#columns;
    (* --- *)
    ignore (view#connect#row_activated     ~callback:self#on_row_activation);
    ignore (view#connect#row_collapsed     ~callback:self#on_row_collapse);
    ignore (view#connect#row_expanded      ~callback:self#on_row_expand);
    ignore (view#connect#cursor_changed    ~callback:self#on_cursor_changed);
    ignore (view#selection#connect#changed ~callback:self#on_selection_changed);
    (* --- *)
    ignore (view#event#connect#button_press
      ~callback:(fun event ->
                    (* We handled the event only in the cases 3 (`TWO_BUTTON_PRESS): *)
                    let code = GdkEvent.Button.button event in
                    let () = Log.printf1 ~v:2 "Treeview: GdkEvent.Button.button event = %d\n" code in
                    match code with
                    | 3 -> (self#show_contextual_menu  event; true)
                    | 1 -> (self#button_press_callback event; false) (* `BUTTON_PRESS treated but not handled *)
                    | _ -> false (* we didn't handle the event *))
                    );
    (* --- *)
    view#set_model (Some the_tree_store#coerce)

  method store =
    match !tree_store with
      None ->
        failwith "called store before create_store_and_view"
    | (Some the_tree_store) ->
        the_tree_store

  (* The treeview's working directory and filename are provided by constructor: *)
  method filename  : string = method_filename  ()
  method directory : string = method_directory ()

  (* A short name telling the four treeviews apart in the log — their row identifiers overlap,
     which would otherwise make the traces ambiguous. `filename' raises when no project is
     active, hence the guard. *)
  method treeview_nickname : string =
    try Filename.basename (self#filename) with _ -> "?"

  method add_string_column
    ~header ?shown_header
    ?(italic=false) ?(bold=false)
    ?(hidden=false) ?(reserved=false) ?default
    ?constraint_predicate
    () =
    let string_column =
      new string_column
        ~italic ~bold
        ~treeview:(self :> treeview) ~hidden ~reserved ?default ~header
        ?shown_header
        ?constraint_predicate
        ()
    in
    let () = self#add_column (string_column :> column) in
    string_column

  method add_editable_string_column
    ~header ?shown_header
    ?(italic=false) ?(bold=false)
    ?(hidden=false) ?(reserved=false) ?default
    ?constraint_predicate
    () =
    let editable_string_column =
      new editable_string_column
        ~italic ~bold
        ~hidden ~reserved ?default ~treeview:(self :> treeview)
        ~header ?shown_header ?constraint_predicate
        ()
    in
    let () = self#add_column (editable_string_column :> column) in
    editable_string_column

  method add_checkbox_column
    ~header ?shown_header
    ?(hidden=false) ?(reserved=false) ?default
    ?constraint_predicate
    () =
    let checkbox_column =
      new checkbox_column
        ~treeview:(self :> treeview) ~header ?shown_header ~hidden
        ~reserved ?default ?constraint_predicate
       ()
    in
    let () = self#add_column (checkbox_column :> column) in
    checkbox_column

  method add_icon_column
    ~header ?shown_header
    ?(hidden=false) ?(reserved=false) ?default
    ~strings_and_pixbufs
    () =
    let icon_column =
      new icon_column
        ~treeview:(self :> treeview) ~header ?shown_header ~hidden
        ~reserved ?default ~strings_and_pixbufs
      ()
    in
    let () = self#add_column (icon_column :> column) in
    icon_column

  (* Add non-specified columns with default values.
     If any constraint is violated raise an exception *)
  method private add_unspecified_columns ?ignore_constraints row =
    let unspecified_columns =
      List.filter
        (fun column -> not (Row.field_exists ~field:column#header row))
        self#columns in
    let unspecified_alist =
      List.map
        (* this fails if there's no default: it's intended: *)
        (fun column -> column#header, (column#default ()))
        unspecified_columns
    in
    let complete_row = unspecified_alist @ row in
    (if ignore_constraints = Some () then
      self#check_constraints complete_row);
    complete_row

  method id_of_complete_row row = Row.get_id row

  method private forest_to_id_forest =
    Forest.map (self#id_of_complete_row)

  method private forest_to_id_row_list ?add_unspecified_columns (forest : Row.t Forest.t)
  : (string * Row.t) list
  =
  let mill =
    match add_unspecified_columns with
    | None    ->
       fun row ->
         let id = self#id_of_complete_row row in
         (id,row)
    | Some () ->
       fun row ->
         let id = self#id_of_complete_row row in
         let row = self#add_unspecified_columns ~ignore_constraints:() row in
         (id,row)
  in
  Forest.to_list (Forest.map (mill) forest)

  method private forest_to_id_forest_and_line_list ?add_unspecified_columns forest =
    (self#forest_to_id_forest forest),
    (self#forest_to_id_row_list ?add_unspecified_columns forest)

  method private private_add_complete_row_with_no_checking ?parent_row_id (row: Row.t) =
    (* Add defaults for unspecified fields: *)
    let row =
      self#add_unspecified_columns ~ignore_constraints:() row
    in
    (* Be sure that we set the _id as the *first* column, so that we can make searches by
       id even when setting all the other columns [To do: this may not be needed
       anymore. --L.]: *)
    let row_id = self#id_of_complete_row row in
    let row = Row.set_id row_id row in
    let store = self#store in
    let parent_iter_option =
      match parent_row_id with
        None -> None
      | (Some parent_row_id) -> Some(self#id_to_iter parent_row_id) in
    (* Update our internal structures holding the forest data: *)
    id_forest :=
      Forest.add_tree_to_forest
        (fun some_id ->
           match parent_row_id with
             None -> false
           | Some parent_row_id -> some_id = parent_row_id)
        row_id Forest.empty
        !id_forest;
    (* Update the hash table, adding the complete row: *)
    Hashtbl.add id_to_row row_id row;
    let new_row_iter = store#append ?parent:parent_iter_option () in
    (* Set all fields (note that the row is complete, hence there's no need to
       worry about unspecified columns now): *)
    List.iter
      (fun (column_header, datum) ->
        try
          let column = self#get_column column_header in
          (if column_header = "_id" then begin
            store#set ~row:new_row_iter ~column:column#gtree_column row_id;
           end else begin
            column#set
              row_id
              ~ignore_constraints:true
              datum;
           end);
        with e -> begin
          Log.printf2 "  - WARNING: unknown column %s (%s)\n" column_header (Printexc.to_string e);
        end)
      row;

  (* Episode 13 of the work-stream "marionnet-automate-composants": this method, `set_complete_forest'
     and the three highlighting methods below mutate the Gtk+ tree model exactly as `remove_row',
     `remove_subtree' and `clear' do, hence they MUST run in the GTK main thread, for the reason
     detailed at length near `remove_row' (the master lock taken twice by the same thread). They were
     left out of episode 9 because it had not been established whether `store#append'/`store#set'
     emit a signal towards a connected OCaml callback *within* the call — the icon renderer's
     cell_data_func being the candidate. That measurement is undecidable in the direction that
     matters: were the callback invoked synchronously from a secondary thread, the process would
     freeze inside the trampoline before logging anything. Since the project's invariant already
     requires every GTK call to start from the main thread, since the deletions have been wrapped
     since episode 9, and since apply_extract applies on the spot when the caller already is the main
     thread, these methods are wrapped rather than measured. The wrapping sits on the private
     methods, so that every entry point — add_row, set_forest, load, set_row, set_row_field,
     set_{String,Icon,CheckBox}_field, update_String_field — is covered without touching a single
     caller. *)
  method private add_complete_row_with_no_checking ?parent_row_id (row: Row.t) =
    GMain_actor.apply_extract
      (fun () -> self#private_add_complete_row_with_no_checking ?parent_row_id row) ()

  method add_row ?parent_row_id (row:Row.t) =
    (* Check that no reserved fields are specified: *)
    List.iter
      (fun (column_header, _) ->
         if (self#get_column column_header)#is_reserved then
           failwith "add_row: reserved columns can not be directly specified")
      row;
    (* Add non-specified fields with default values: *)
    let row = self#add_unspecified_columns row in
    self#add_complete_row_with_no_checking ?parent_row_id row;
    (* Get the row id: *)
    let row_id = self#id_of_complete_row row in
    (* A just-added row should be collapsed by default *)
    self#collapse_row row_id;
    (* Return the row id. This is important for the caller: *)
    row_id

  (** Return the current id forest: *)
  method get_id_forest =
    !id_forest

  (** Return a row forest (not the internally-used id forest), containing the
      non-reserved fields *)
  method get_forest =
    Forest.map
      (fun row_id ->
         self#get_row row_id)
      !id_forest;

  (** Return a row forest (not the internally-used id forest), containing all
      the fields *)
  method get_complete_forest =
    Forest.map
      (fun row_id ->
         self#get_complete_row row_id)
      !id_forest;

  (** Completely clear the state, and set it to the given forest. *)
  method set_forest (forest : Row.t Forest.t) =
    self#set_complete_forest
      (Forest.map
        (fun row -> self#add_unspecified_columns row)
        forest)

  (** Completely clear the state, and set it to the given complete forest. *)
  method private set_complete_forest (new_forest : Row.t Forest.t) =
    (* Episode 13: same reason as `add_complete_row_with_no_checking' above. Note that the nested
       `self#clear' is itself wrapped: apply_extract applies on the spot once we are the main
       thread, so the nesting costs nothing and cannot deadlock. *)
    GMain_actor.apply_extract (fun () -> self#private_set_complete_forest new_forest) ()

  method private private_set_complete_forest (new_forest : Row.t Forest.t) =
    (* Clear our structures and Gtk structures: *)
    self#clear;
    (* Compute our new structures: *)
    let new_id_forest, new_row_list =
      self#forest_to_id_forest_and_line_list ~add_unspecified_columns:() new_forest
    in
    (* Set the new id forest: *)
    id_forest := new_id_forest;
    (* Fill the hash table with our new rows: *)
    List.iter
      (fun (row_id, row) ->
        Hashtbl.add id_to_row row_id row)
      new_row_list;
    (* Fill Gtk structures, so that the interface shows our new forest: *)
    let store = self#store in
    Forest.iter
      (fun row_id parent ->
        (* Find the correct Gtk place "where to attach" the new line: *)
        let parent_iter_option =
          (match parent with
             None ->
               None
           | (Some parent_row_id) ->
               Some(self#id_to_iter parent_row_id)) in
        let new_row_iter = store#append ?parent:parent_iter_option () in
        (* Set all fields in the row with id row_id (note that the row is complete, hence
           there's no need to worry about unspecified columns now): *)
        let row = Hashtbl.find id_to_row row_id in
        let id_column = self#get_column "_id" in
        store#set ~row:new_row_iter ~column:id_column#gtree_column row_id;
        List.iter
          (fun (column_header, datum) ->
            try
              let column = self#get_column column_header in
              (if not (column_header = "_id") then
                 column#set row_id ~initialize:true ~row_iter:new_row_iter ~ignore_constraints:true datum);
            with e -> begin
              Log.printf2
                "Treeview.treeview#set_complete_forest: WARNING: error (I guess the problem is an unknown column) %s (%s)\n"
                column_header
                (Printexc.to_string e);
            end)
          row;)
      new_id_forest;

  (** Return true iff the given row is currently expanded *)
  method is_row_expanded row_id =
    Hashtbl.mem expanded_row_ids row_id

  (** Return the list of ids of all currently expanded rows *)
  method private expanded_row_ids =
    List.filter
      (fun row_id -> self#is_row_expanded row_id)
      (Forest.to_list !id_forest)

  (** Expand exactly the rows with the ids in row_id_list, and collapse
      everything else *)
  method set_expanded_row_ids expanded_row_id_list =
    self#collapse_everything;
    List.iter
      (fun row_id -> self#expand_row row_id)
      expanded_row_id_list

  val next_identifier_and_content_forest_marshaler =
    new Oomarshal.marshaller;

  (* For debugging: *)
  method print =
    let string_of_node node =
      let buffer = Buffer.create 100 in
      let print_string x = Buffer.add_string buffer x in
      print_string "[ ";
      List.iter
	(fun (s, row_item) ->
	  print_string (Printf.sprintf "%s: " s);
	  match row_item with
	  | Row_item.String s ->
	      print_string (Printf.sprintf "%s; " s)
	  | Row_item.CheckBox b ->
	      print_string
		(Printf.sprintf "%s; " (if b then "T" else "F"))
	  | Row_item.Icon i ->
	      print_string (Printf.sprintf "icon:%s; " i))
	node;
      print_string "]\n";
      let result = Buffer.contents buffer in
      result
    in (* end of string_of_node *)
    let forest = self#get_complete_forest in
    let next_identifier = (self#counter#get_next_fresh_value) in
    Printf.kfprintf flush stderr "Next identifier: %i\n" next_identifier;
    Forest.print_forest ~string_of_node ~channel:stderr forest

  method save ?(with_forest_treatment=fun x->x) () =
    let file_name = self#filename in
    Log.printf1 "Treeview.treeview#save: saving into %s\n" file_name;
    let forest = with_forest_treatment (self#get_complete_forest) in
    next_identifier_and_content_forest_marshaler#to_file
      (self#counter#get_next_fresh_value, forest)
      file_name;

  method load ?(file_name=self#filename) ~(project_version : [ `v0 | `v1 | `v2 ]) () =
    let () = Log.printf1 "Treeview.treeview#load: about to load the treeview from file %s\n" file_name in
    self#detach_view_in
      (fun () ->
        let () = Log.printf1 "Treeview.treeview#load: Preparing to load a treeview content from file %s\n" file_name in
        let () = self#clear in
        try
          let (next_identifier, complete_forest) =
            match project_version with
            | `v2 | `v1 -> next_identifier_and_content_forest_marshaler#from_file (file_name)
            | `v0       -> Backward_compatibility.load_from_old_file (file_name)
          in
          let () = self#counter#set_next_fresh_value_to next_identifier in
          (* Remove incompatible bindings if necessary: *)
          let complete_forest =
            let admissible_fields = SetExtra.String_set.of_list (self#column_headers) in
            Forest.map
              (List.filter (fun (field,_) -> SetExtra.String_set.mem field admissible_fields))
              complete_forest
          in
          let () = self#set_complete_forest complete_forest in
          let () = Log.printf1 "Treeview.treeview#load: Ok, treeview content successfully loaded from: %s\n" file_name in
          let () =
            (* Under -d only (Debug_level is built by `of_bool' and caps at 1,
               initialization.ml:148-155): dumping the forest as it comes from the file is the
               only way to tell a forest already damaged on disk from one damaged in session. *)
            if (Global_options.Debug_level.get ()) >= 1 then begin
            Log.printf1 "Treeview.treeview#load: freshly loaded forest of %s:\n" file_name;
            Forest.print_forest ~string_of_node:Row.to_pretty_string ~channel:stderr (complete_forest)
            end
          in
          ()
        with e -> begin
          Log.printf2 "Treeview.treeview#load: Loading the treeview %s: failed (%s); I'm setting an empty forest, in the hope that nothing serious will happen\n\n" file_name (Printexc.to_string e);
        end);
    (* This must be executed with the view attached, as it operates on the GUI: *)
    self#collapse_everything;

  (** Also return reserved fields: *)
  method get_complete_row row_id =
    Hashtbl.find id_to_row row_id

  method remove_reserved_fields row =
    List.filter
      (fun (header, _) -> not (self#get_column header)#is_reserved)
      row

  (** Hide reserved fields: *)
  method get_row row_id =
    self#remove_reserved_fields (self#get_complete_row row_id)

  method get_row_field row_id field =
    Row.get_field (self#get_complete_row row_id) ~field

  method unique_row_exists_with_binding ~(field:string) ~(value:string) =
   let predicate row : bool = (Row.String_field.eq ~fallback:false ~field ~value row) in
   self#is_there_a_unique_row_such_that (predicate)

  (** This needs to be public (it would be 'friend' in C++), but please don't directly
      call it. It's meant for use by the subclasses of 'column. *)
  method set_row (row_id : string) row =
    Hashtbl.add id_to_row row_id row

  method set_row_field (row_id : string) field new_item =
    let complete_forest = self#get_complete_forest in
    let updated_complete_forest =
      Forest.search_and_replace
        (fun row -> (self#id_of_complete_row row) = row_id)
        (fun row -> Row.set_field ~field ~value:new_item row)
        complete_forest
    in
    self#set_complete_forest updated_complete_forest

  method get_String_field field (row_id:string) =
    Row_item.extract_String (self#get_row_field row_id field)

  method set_String_field field (row_id:string) x =
    self#set_row_field row_id field (Row_item.String x)

  method update_String_field field (update:string->string) (row_id:string) =
    let v = self#get_String_field field row_id in
    self#set_String_field field row_id (update v)

  method get_Icon_field field (row_id:string) =
    Row_item.extract_Icon (self#get_row_field row_id field)

  method set_Icon_field field (row_id:string) x =
    self#set_row_field row_id field (Row_item.Icon x)

  method get_CheckBox_field field (row_id:string) =
    Row_item.extract_CheckBox (self#get_row_field row_id field)

  method set_CheckBox_field field (row_id:string) x =
    self#set_row_field row_id field (Row_item.CheckBox x)

  method private private_remove_row (row_id : string) =
    (* Removing the row from the Gtk+ tree model is a little involved.
       We have to first build an updated version of our internal data
       structures, then completely clear the state, and re-build it
       from our updated version.
       This greatly simplifies the GUI part, which is less comfortable
       to work with than our internal data structures. *)
     (* Beware: Forest.filter "cuts bad nodes and lifts their orphans up" (forest.ml:150), so
        this method does NOT remove a subtree — the children of row_id survive, promoted one
        level up. Hence this line: the victim, and the children it is about to orphan. *)
     let () =
       let name = try Row.get_name (self#get_complete_row row_id) with e -> Printexc.to_string e in
       let orphans = try self#children_of row_id with _ -> [] in
       Log.printf4
         "[%s] Treeview#remove_row: removing row %s (\"%s\"); %d child row(s) will be lifted up\n"
         self#treeview_nickname row_id name (List.length orphans)
     in
     (* Ok, save the updated state we want to restore later: *)
     let updated_id_forest =
       Forest.filter
         (fun an_id -> not (an_id = row_id))
         !id_forest in
     let updated_content_forest =
       Forest.map (fun id -> self#get_complete_row id) updated_id_forest in
     let _updated_expanded_row_ids_as_list =
       List.fold_left
         (fun list an_id ->
            if Hashtbl.mem expanded_row_ids an_id then
              an_id :: list
            else
              list)
         []
         (Forest.to_list updated_id_forest) in
     (* Clear the full state, which of course includes the GUI: *)
     self#private_clear;
     (* Restore the state we have set apart before: *)
     Forest.iter
       (fun row parent_tree ->
         let parent_row_id =
           match parent_tree with
           | None -> None
           | Some node-> Some (self#id_of_complete_row node)
         in
         self#add_complete_row_with_no_checking ?parent_row_id row)
       updated_content_forest;

  (* The three methods below mutate the Gtk+ tree model, hence they MUST run in the GTK main
     thread — like every other GUI call of this program (see the project's CLAUDE.md). Calling
     them from another thread deadlocks the whole runtime, and does so silently: `store#remove'
     makes Gtk+ emit a signal (row deletion moves the cursor and the selection), lablgtk then
     re-enters OCaml through its `marshal' trampoline (ml_gobject.c), which starts by taking the
     runtime's master lock — a lock the calling thread already holds, and which is not reentrant.
     The thread thus waits for itself forever, the master lock is never released, and every other
     OCaml thread piles up behind it: the whole process freezes with no exception and no CPU
     activity. Measured with gdb on a frozen process (journals 16, 18 and 19 of the work-stream
     "marionnet-automate-composants"): the closing thread sat in st_masterlock_acquire under
     gtk_tree_store_remove, called from `network#reset' (state.ml) through `destroy_my_history'.
     GMain_actor.apply_extract is used, not `delegate': the latter drops the exception raised by
     the delegated code (it ignores the returned Either), which would silently resurrect the
     "succeeded task that actually raised" bug fixed in episode 5. apply_extract re-raises in the
     calling thread, so these methods keep exactly the semantics they had when called directly —
     `remove_subtree_by_name' below still sees the failure it logs. Note also that apply_extract
     applies the function on the spot when the caller already is the GTK main thread, so the usual
     paths (menu callbacks) pay nothing for this protection. *)
  method remove_row (row_id : string) =
    GMain_actor.apply_extract (fun () -> self#private_remove_row row_id) ()

  method private private_remove_subtree (row_id : string) =
    let row_iter = self#id_to_iter row_id in
    (* First find out which rows we have to remove: *)
    let ids_of_the_rows_to_be_removed =
      row_id :: (Forest.descendant_nodes row_id !id_forest) in
    (* Who is removed, and with which descendants. Beware: id_to_iter above may have raised
       already, in which case nothing at all is removed and this line is not printed. *)
    let () =
      let describe id = try Row.get_name (self#get_complete_row id) with _ -> "?" in
      Log.printf4
        "[%s] Treeview#remove_subtree: removing row %s (\"%s\") together with [%s]\n"
        self#treeview_nickname row_id (describe row_id)
        (String.concat "; "
           (List.map (fun id -> Printf.sprintf "%s:\"%s\"" id (describe id))
              (List.tl ids_of_the_rows_to_be_removed)))
    in
    (* Ok, now update id_forest, id_to_row and expanded_row_ids: *)
    List.iter
      (fun row_id ->
         id_forest :=
           Forest.filter
             (fun a_row_id ->
                not (row_id = a_row_id))
             !id_forest)
      ids_of_the_rows_to_be_removed;
    List.iter
      (fun row_id ->
         Hashtbl.remove id_to_row row_id;
         Hashtbl.remove expanded_row_ids row_id)
      ids_of_the_rows_to_be_removed;
    (* Finally remove the row, together with its subtrees, from the Gtk+ tree model: *)
    ignore (self#store#remove row_iter);

  method remove_subtree (row_id : string) =
    GMain_actor.apply_extract (fun () -> self#private_remove_subtree row_id) ()

  method private private_clear =
    id_forest := Forest.empty;
    Hashtbl.clear id_to_row;
    Hashtbl.clear expanded_row_ids;
    self#store#clear ();

  method clear =
    GMain_actor.apply_extract (fun () -> self#private_clear) ()

  (* B6 (work-stream "marionnet-automate-composants", episode 6): the identifier of a row is no
     longer read from the "_id" column of the widget. This read was the last one left deciding an
     identity, and it is precisely the kind of read that was measured returning "@" where the very
     next traversal read "0" (episode 5, journals 53-55). Only the *structure* of the model is
     queried now — the path of the row — while the identifier itself comes from the internal
     forest, which is the source of truth. *)
  method iter_to_id (iter:Gtk.tree_iter) : string =
    self#path_to_id (self#iter_to_path iter)

  method iter_to_path iter =
    self#store#get_path iter

  method path_to_iter path =
    self#store#get_iter path

  (* B6 (work-stream "marionnet-automate-composants"): position of a row in the internal forest,
     as the list of sibling indices leading to it — i.e. exactly the indices of the Gtk tree path
     of that row. This is legitimate because both structures are grown together and in the same
     order: Forest.add_tree_to_forest appends the new tree at the END of its parent's children
     (forest.ml:331-338, via `concat'), just like store#append does, and set_complete_forest
     fills the store by a pre-order walk of the forest, so ancestors and preceding siblings are
     always already in place when a path is computed. *)
  method private id_to_path_indices (id:string) : (int list) option =
    let rec search_forest ~prefix forest =
      let rec search_trees ~index = function
        | [] -> None
        | (root, children) :: rest ->
            let here = prefix @ [index] in
            if root = id then Some here else
            (match search_forest ~prefix:here children with
             | (Some _) as found -> found
             | None -> search_trees ~index:(index + 1) rest)
      in
      search_trees ~index:0 (Forest.to_treelist forest)
    in
    search_forest ~prefix:[] (self#get_id_forest)

  (* B6 (episode 6): the converse of id_to_path_indices, and legitimate for the same reason (both
     structures are grown together and in the same order). Answers None when the indices lead
     nowhere in the internal forest, which can only mean a real divergence with the store. *)
  method private path_indices_to_id (indices : int list) : string option =
    let rec descend forest = function
      | [] -> None
      | index :: rest ->
          (match List.nth_opt (Forest.to_treelist forest) index with
           | None -> None
           | Some (root, children) ->
               if rest = [] then Some root else descend children rest)
    in
    descend (self#get_id_forest) indices

  (* B6 (episode 5): the identifier is resolved through the internal forest — the source of truth — instead
     of scanning the Gtk model row by row and comparing the "_id" column of each one. The former
     implementation was defeated by unreliable reads of that column: a traversal could read "@"
     where the very next one read "0" (journals 53-55), so a perfectly present row was reported
     as missing, the startup task raised, and the component silently stayed off. As a bonus, the
     widget is no longer walked at every single column write. *)
  method id_to_iter (id:string) =
    match self#id_to_path_indices id with
    | None ->
        failwith ("id_to_iter: id " ^ ((* string_of_int *) id) ^ " not found")
    | Some indices ->
        let path = GTree.Path.create indices in
        (try self#store#get_iter path with e ->
           failwith
             (Printf.sprintf "id_to_iter: id %s is at path %s in the forest of %s, but the store has no such row (%s)"
                id (GTree.Path.to_string path) self#treeview_nickname (Printexc.to_string e)))

  (* B6 (episode 6): failing here is deliberate, and it is the same choice as in id_to_iter — an
     identifier that cannot be resolved must not be replaced by a plausible-looking wrong one,
     because two of the callers (the end of an edition, the toggle of a checkbox) *write* through
     it. Note the asymmetry with the icon renderer below, which must stay total: this method is
     called from occasional event callbacks, not from a cell_data_func replayed at every redraw. *)
  (* B6 (episode 14): the total variant, for the one caller that must never raise — the icon
     renderer, replayed at every redraw from Gtk's C stack. *)
  method path_to_id_opt path : string option =
    self#path_indices_to_id (Array.to_list (GTree.Path.get_indices path))

  method path_to_id path : string =
    match self#path_to_id_opt path with
    | Some id -> id
    | None ->
        failwith
          (Printf.sprintf
             "path_to_id: the store of %s has a row at path %s, but the internal forest has none"
             self#treeview_nickname (GTree.Path.to_string path))

  method id_to_path (id:string) =
    self#iter_to_path (self#id_to_iter id)

  (* B6 (episode 6): for_all_rows, iter_on_forest and iter_on_tree used to live here. They walked
     the widget with a destructively modified iterator, and their only caller was the former
     id_to_iter, dropped at episode 5 — they are dead code since then. They are removed rather
     than kept, because every measured phantom read came from that walk, never from a fresh
     iterator obtained by store#get_iter of a path. Anything needing to traverse the rows should
     use the internal forest (get_id_forest, get_row_list). *)

  (* Same discipline, and for the same reason, as remove_row/remove_subtree/clear above: these four
     mutate the widget from whatever thread calls them, and `row-expanded'/`row-collapsed' ARE
     connected (see the initializer: on_row_expand/on_row_collapse), so Gtk+ re-enters OCaml
     synchronously inside the call — deadlocking the runtime when the caller is not the GTK main
     thread. The callers concerned are not hypothetical: `add_substate_of'
     (treeview_history.ml, one collapse per COW state) runs in a task runner task, reached from
     create_cow_file_name_and_thunk_to_get_the_source (user_level.ml) every time a machine or a
     router starts; add_row below collapses the row it has just created; treeview_defects and
     treeview_ifconfig collapse on component creation. What has kept this from freezing so far is
     that Gtk+ only emits when the state actually CHANGES: collapsing an already-collapsed row —
     the common case — emits nothing. A deployed tree is enough to lose the process, which is
     precisely how the closing freeze behaved before being caught. *)
  method expand_row id =
    GMain_actor.apply_extract (fun () -> view#expand_row (self#id_to_path id)) ()

  method expand_everything =
    GMain_actor.apply_extract (fun () -> view#expand_all ()) ()

  method collapse_everything =
    GMain_actor.apply_extract (fun () -> view#collapse_all ()) ()

  method collapse_row id =
    GMain_actor.apply_extract (fun () -> view#collapse_row (self#id_to_path id)) ()

  method is_row_highlighted row_id =
    match self#get_row_field row_id "_highlight" with
      Row_item.CheckBox b -> b
  | _ -> assert false

  (* Episode 13: these three reach `store#set' through `column#set', outside the two methods wrapped
     above, and they are called from the task runner (treeview_history.ml, when a machine starts).
     Same wrapping, same reason. *)
  method highlight_row row_id =
    let highlight_color_column = self#get_column "_highlight" in
    GMain_actor.apply_extract
      (fun () -> highlight_color_column#set (row_id) (Row_item.CheckBox true)) ()

  method unhighlight_row row_id =
    let highlight_color_column = self#get_column "_highlight" in
    GMain_actor.apply_extract
      (fun () -> highlight_color_column#set (row_id) (Row_item.CheckBox false)) ()

  method set_row_highlight_color color row_id =
    let highlight_color_column = self#get_column "_highlight-color" in
    GMain_actor.apply_extract
      (fun () -> highlight_color_column#set (row_id) (Row_item.String color)) ()

  method get_row_list =
    Forest.to_list self#get_complete_forest

  (* Return a list of row_ids such that the complete rows they identify enjoy the
     given property *)
  method row_ids_such_that predicate =
    let row_list = List.filter predicate self#get_row_list in
    List.map self#id_of_complete_row row_list

  method unique_root_row_id_such_that predicate =
    let roots = Forest.roots_of self#get_complete_forest in
    match (List.filter predicate roots) with
    | [row] -> self#id_of_complete_row row
    | rows ->
       failwith (Printf.sprintf "unique_root_row_id_such_that: there were %i results instead of 1"
                   (List.length rows))

  method rows_such_that predicate =
    List.map self#get_row (self#row_ids_such_that predicate)

  method unique_row_such_that predicate =
    self#get_row (self#unique_row_id_such_that predicate)

  method complete_rows_such_that predicate =
    List.map self#get_complete_row (self#row_ids_such_that predicate)

  method unique_complete_row_such_that predicate =
    self#get_complete_row (self#unique_row_id_such_that predicate)

  (** Return the row_id of the only row satisfying the given predicate. Fail if more
      than one such row exist: *)
  method unique_row_id_such_that predicate =
    let row_ids = self#row_ids_such_that predicate in
    match row_ids with
      row_id :: [] -> row_id
    | _ -> failwith (Printf.sprintf
                       "unique_row_id_such_that: there were %i results instead of 1"
                       (List.length row_ids))


  method private is_there_a_unique_row_such_that (predicate : Row.t -> bool) : bool =
    try
      ignore (self#unique_row_id_such_that predicate); true
    with _ -> false

  (** Return an option containing the the row_id of the parent row, if any. *)
  method parent_of row_id =
   Forest.parent_of row_id !id_forest

  method children_of row_id =
    Forest.children_nodes row_id !id_forest

  method children_no row_id =
    let row_ids = self#children_of row_id in
    List.length row_ids

  method set_column_visibility header visibility =
    (self#get_column header)#gtree_view_column#set_visible visibility

  val is_view_detached =
    ref false

  (** See detach_view_in: *)
  method is_view_detached =
    !is_view_detached

  (** Temporarily detach the view while executing the thunk, so that updates don't show up in
      the GUI. Using this improves performance when adding/removing a lot of rows. Any exception
      raised by the thunk is correctly propagated after re-attaching the view. *)
  method private private_detach_view_in (thunk : unit -> unit) =
    let () = Log.printf "Treeview.treeview#detach_view_in: about to detach the view\n" in
    let model : GTree.model = self#store#coerce in
    view#set_model None;
    (try
      is_view_detached := true;
      thunk ();
      is_view_detached := false;
      view#set_model (Some model);
    with e -> begin
      let () = Log.printf "Treeview.treeview#detach_view_in: something goes wrong\n" in
      is_view_detached := false;
      view#set_model (Some model);
      raise e;
      end)

  (* Public interface. apply_extract, not `delegate': the latter drops the Either and would make
     the `raise e' of private_detach_view_in above dead code — the thunk's failure would be
     silently swallowed, which is exactly the "task that succeeded although it raised" bug of
     episode 5. Fixed at episode 15, together with the three callers in state.ml which used to
     swallow it a second time. *)
  method detach_view_in (thunk : unit -> unit) =
    GMain_actor.apply_extract (fun () -> self#private_detach_view_in thunk) ()

  initializer
    (* Add hidden reserved columns: *)
    let _ =
      self#add_string_column
        ~header:"_id"
        ~reserved:true
        ~default:(fun () -> Row_item.String (string_of_int (self#counter#fresh ())))
        ~hidden:hide_reserved_fields
        () in
    let _ =
      self#add_editable_string_column
        ~header:"_highlight-color"
        ~reserved:true
        ~default:(fun () -> Row_item.String self#get_highlight_color)
        ~hidden:hide_reserved_fields
        () in
    let ckboxcol =
      self#add_checkbox_column
        ~header:"_highlight"
        ~reserved:true
        ~default:(fun () -> Row_item.CheckBox false)
        ~hidden:hide_reserved_fields
        () in
    let () =
       self#set_highlight_checkbox_column (ckboxcol)
    in
    ();

    self#add_menu_item
      (s_ "Expand all")
      (fun _ -> true)
      (fun selected_rowid_if_any ->
        self#expand_everything);

    self#add_menu_item
      (s_ "Collapse all")
      (fun _ -> true)
      (fun selected_rowid_if_any ->
        self#collapse_everything);

    self#add_separator_menu_item;
end;;

(* Convenient alias: *)
class t = treeview

class virtual treeview_with_a_Name_column = fun
  ?hide_reserved_fields
  ?highlight_foreground_color
  ?highlight_color
  ~packing
  ~method_directory
  ~method_filename
  () ->
 object(self)
  inherit t ?hide_reserved_fields ?highlight_foreground_color ?highlight_color ~packing ~method_directory ~method_filename ()

  val name_header = "Name"
  method get_row_name    = self#get_String_field    (name_header)
  method set_row_name    = self#set_String_field    (name_header)
  method update_row_name = self#update_String_field (name_header)

  method rename old_name new_name =
    let row_ids = self#row_ids_of_name old_name in
    List.iter (fun row_id -> self#set_row_name row_id new_name) row_ids

  method unique_root_row_id_of_name name = self#unique_root_row_id_such_that (Row.eq_name name)
  method row_ids_of_name name            = self#row_ids_such_that (Row.eq_name name)
  method rows_of_name name               = self#rows_such_that    (Row.eq_name name)

  method get_row_parent_name row_id =
    let parent_row_id = Option.extract (self#parent_of row_id) in
    self#get_row_name (parent_row_id)

  method get_row_grandparent_name row_id =
    let parent_row_id = Option.extract (self#parent_of row_id) in
    let grandparent_row_id = Option.extract (self#parent_of parent_row_id) in
    self#get_row_name (grandparent_row_id)

  method get_name_list =
    let forest = self#get_complete_forest in
    let forest_of_names = Forest.map (Row.get_name) forest in
    ListExtra.remove_duplicates (Forest.to_list forest_of_names)

  initializer
    let _ =
      self#add_string_column
        ~header:name_header
        ~shown_header:(s_ "Name")
        ()
     in ()

 end (* treeview_with_a_Name_column *)

(* Name is here a primary key: *)
class virtual treeview_with_a_primary_key_Name_column
  ?hide_reserved_fields
  ?highlight_foreground_color
  ?highlight_color
  ~packing
  ~method_directory
  ~method_filename
  () =
  object(self)
  inherit
    treeview_with_a_Name_column
      ?hide_reserved_fields ?highlight_foreground_color ?highlight_color
      ~packing ~method_directory ~method_filename ()

  method unique_row_id_of_name name = self#unique_row_id_such_that  (Row.eq_name name)
  method unique_row_of_name name    = self#unique_row_such_that     (Row.eq_name name)

  method children_no_of ~parent_name =
    let row_id = self#unique_row_id_of_name parent_name in
    self#children_no row_id

  (** Do nothing if there is no such name. *)
  method remove_subtree_by_name name =
    try
      let row_id = self#unique_row_id_of_name name in
      self#remove_subtree row_id;
    with e ->
      (* The exception stays swallowed — the contract of this method is to do nothing when
         there is no such name — but a destruction silently skipped here is the very first
         mechanism of B6, hence it must at least leave a trace. *)
      Log.printf2 ~force:true
        "Treeview#remove_subtree_by_name: \"%s\": destruction SKIPPED (%s)\n"
        name (Printexc.to_string e)

  method update_children_no ~(add_child_of:string -> unit) ~parent_name new_children_no =
    let row_id = self#unique_row_id_of_name parent_name in
    let row_ids = self#children_of row_id in
    let old_children_no = List.length row_ids in
    let delta = new_children_no - old_children_no in
    if delta >= 0 then
      for _i = old_children_no + 1 to new_children_no do
        add_child_of parent_name
      done
    else begin
      let reversed_row_ids = List.rev row_ids in
      List.iter self#remove_row (ListExtra.head ~n:(-(delta)) reversed_row_ids);
    end;

  method get_complete_row_of_child ~parent_name ~child_name =
    let row_id = self#unique_row_id_of_name parent_name in
    let row_ids = self#children_of row_id in
    let filtered_data =
      List.filter
        (Row.eq_name child_name)
        (List.map self#get_complete_row row_ids)
    in
    assert((List.length filtered_data) = 1);
    List.hd filtered_data

  method get_row_of_child ~parent_name ~child_name =
    self#remove_reserved_fields (self#get_complete_row_of_child ~parent_name ~child_name)

 end

(* Add the two buttons "Expand all" and "Collapse all" at right side of the treeview. *)
let add_expand_and_collapse_button ~(window:GWindow.window) ~(hbox:GPack.box) (treeview:t) : GButton.toolbar =
  let toolbar =
    let packing w = hbox#pack ~expand:false w in
    GButton.toolbar ~orientation:`VERTICAL ~packing ()
  in
  (*let packing = toolbar#add in*)
  let packing = Gui_bricks.make_toolbar_packing_function (toolbar) in
  (* --- *)
  let b1 = Gui_bricks.button_image (*~window*) ~packing ~file:"ico.action.zoom.in.png" () in
  let b2 = Gui_bricks.button_image (*~window*) ~packing ~file:"ico.action.zoom.out.png" () in
  let () =
    (* !!!VERIFY TRANSITION (lablgtk2->lablgtk3): *)
    (* (* (* let set = (GData.tooltips ())#set_tip in *) *) *)
    (* val GtkBase.Widget.Tooltip.set_text : [> `widget ] Gtk.obj -> string -> unit *)
    let set widget ~text = GtkBase.Widget.Tooltip.set_text widget text in
    set b1#as_widget ~text:(s_ "Expand all");
    set b2#as_widget ~text:(s_ "Collapse all")
  in
  let () =
    let set (b:GButton.button) callback = ignore (b#connect#clicked ~callback) in
    set b1 (fun () -> treeview#expand_everything);
    set b2 (fun () -> treeview#collapse_everything)
  in
  toolbar
