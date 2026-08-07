(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008  Luca Saiu
   Copyright (C) 2009, 2010  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2009, 2010  Université Paris 13

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
module Log = Marionnet_log
module Forest = Ocamlbricks.Forest
module Stateful_modules = Ocamlbricks.Stateful_modules

open Gettext;;
module Row_item = Treeview.Row_item ;;
module Row = Treeview.Row ;;

(** The direction in which data flow in a single port; this is the 'resolution'
    of each defect, for each port: *)
type port_direction =
    InToOut | OutToIn;;

let string_of_port_direction d =
  match d with
    InToOut -> "outward"
  | OutToIn -> "inward";;

type column_header = string

(** The direction in which data flow in a single port; this is the 'resolution'
    of each defect, for each port: *)
type cable_direction =
  LeftToRight | RightToLeft;;

let string_of_cable_direction d =
  match d with
    LeftToRight -> "rightward"
  | RightToLeft -> "leftward";;

class t =
fun ~packing
    ~method_directory
    ~method_filename
    ~after_user_edit_callback
    () ->
object(self)
  inherit
    Treeview.treeview_with_a_primary_key_Name_column
      ~packing ~method_directory ~method_filename
      ~highlight_color:"Light Coral"
      ~hide_reserved_fields:true
      ()
  (* as super *)

  val loss_header = "Loss %"
  method get_row_loss = self#get_String_field (loss_header)
  method set_row_loss = self#set_String_field (loss_header)

  val duplication_header = "Duplication %"
  method get_row_duplication = self#get_String_field (duplication_header)
  method set_row_duplication = self#set_String_field (duplication_header)

  val flipped_bits_header = "Flipped bits %"
  method get_row_flipped_bits = self#get_String_field (flipped_bits_header)
  method set_row_flipped_bits = self#set_String_field (flipped_bits_header)

  val minimum_delay_header = "Minimum delay (ms)"
  method get_row_minimum_delay = self#get_String_field (minimum_delay_header)
  method set_row_minimum_delay = self#set_String_field (minimum_delay_header)

  val maximum_delay_header = "Maximum delay (ms)"
  method get_row_maximum_delay = self#get_String_field (maximum_delay_header)
  method set_row_maximum_delay = self#set_String_field (maximum_delay_header)

  val type_header = "Type"
  method get_row_type = self#get_Icon_field (type_header)
  method set_row_type = self#set_Icon_field (type_header)

  val uneditable_header = "_uneditable"
  method get_row_uneditable = self#get_CheckBox_field (uneditable_header)

  method non_defective_defaults =
    [ loss_header,          Row_item.String "0";
      duplication_header,   Row_item.String "0";
      flipped_bits_header,  Row_item.String "0";
      minimum_delay_header, Row_item.String "0";
      maximum_delay_header, Row_item.String "0"; ]

  method defective_defaults =
    [ loss_header,          Row_item.String "5";
      duplication_header,   Row_item.String "5";
      flipped_bits_header,  Row_item.String "0.01";
      minimum_delay_header, Row_item.String "50";
      maximum_delay_header, Row_item.String "100"; ]

  (* --- B6 (episode 6, work-stream "marionnet-automate-composants") ---
     Deducing the validity of an entry from a homonymous row is what let a component silently
     inherit the truncated entry of a previous one: add_my_defects recreated nothing, and
     get_cable_data then settled the matter with an `assert', which killed the startup of a
     component the user had not even touched. The three methods below decide validity on the
     *shape* of the entry, and repair it by completing what is missing — never by destroying and
     recreating the whole entry, which would silently throw away the defects the user had set on
     the surviving rows. *)

  (** Add, under the given parent, every (type, name) direction row that is missing. Returns the
      number of rows added, so that the caller can tell a sound entry from a repaired one. *)
  method private complete_direction_rows ~parent_row_id ~(expected : (string * string) list) : int =
    let present = List.map self#get_row_type (self#children_of parent_row_id) in
    List.fold_left
      (fun added (direction_type, direction_name) ->
         if List.mem direction_type present then added else begin
           ignore
             (self#add_row
                ~parent_row_id
                (List.append
                   [ name_header, Row_item.String direction_name;
                     type_header, Row_item.Icon direction_type ]
                   self#non_defective_defaults));
           added + 1
           end)
      0
      expected

  (* Report what a repair did, or why it could not be attempted. Factored out because both
     ensure_* methods below must stay total: a component must be created even when its defects
     entry resists repair — a defective entry is a defect of this treeview, not a reason to
     refuse the component. *)
  method private report_repair ~name ~repair =
    try
      let added = repair () in
      if added > 0 then
        Log.printf2 ~force:true
          "Treeview_defects: WARNING: the entry of \"%s\" was incomplete (it was very likely inherited from a previous component); %d missing row(s) added\n"
          name added
    with e ->
      Log.printf2 ~force:true
        "Treeview_defects: WARNING: the entry of \"%s\" could not be checked nor repaired (%s)\n"
        name (Printexc.to_string e)

  (** Make sure a usable entry exists for that cable: create it when there is none, complete it
      when it lost one of its two direction rows. *)
  method ensure_cable_entry ~cable_name ~cable_type ~left_name ~right_name () =
    if not (self#unique_row_exists_with_binding ~field:name_header ~value:cable_name) then
      self#add_cable ~cable_name ~cable_type ~left_name ~right_name ()
    else begin
      Log.printf1 "The cable %s has already defects defined...\n" cable_name;
      self#report_repair ~name:cable_name ~repair:(fun () ->
        self#complete_direction_rows
          ~parent_row_id:(self#unique_row_id_of_name cable_name)
          ~expected:[ ("leftward", left_name); ("rightward", right_name) ])
      end

  (** Make sure a usable entry exists for that device: create it when there is none; otherwise
      realign the number of ports (update_port_no leaves the existing ones untouched) and complete
      the ports that lost a direction row. *)
  method ensure_device_entry ~device_name ~device_type ~port_no ~port_prefix ~user_port_offset () =
    if not (self#unique_row_exists_with_binding ~field:name_header ~value:device_name) then
      self#add_device ~device_name ~device_type ~port_no ~port_prefix ~user_port_offset ()
    else begin
      Log.printf2 "The %s %s has already defects defined...\n" device_type device_name;
      self#report_repair ~name:device_name ~repair:(fun () ->
        let () = self#update_port_no ~device_name ~port_no ~port_prefix ~user_port_offset () in
        List.fold_left
          (fun added port_row_id ->
             added +
             self#complete_direction_rows
               ~parent_row_id:port_row_id
               ~expected:[ ("inward", "inward"); ("outward", "outward") ])
          0
          (self#children_of (self#unique_row_id_of_name device_name)))
      end

  method add_device
    ?(defective_by_default=false)
    ~device_name
    ~device_type
    ~port_no
    ~port_prefix
    ~user_port_offset
    ()
    =
    Log.printf5
      "Making a defect treeview entry for %s \"%s\" with %d ports (prefix %s, user port offset %d).\n"
      device_type device_name port_no port_prefix user_port_offset;
    let row_id =
      self#add_row
        [ name_header,       Row_item.String device_name;
          type_header,       Row_item.Icon device_type;
          uneditable_header, Row_item.CheckBox true; ] in
    self#update_port_no ~defective_by_default ~device_name ~port_no ~port_prefix ~user_port_offset ();
    self#collapse_row row_id;


  method add_cable ~cable_name ~cable_type ~left_name ~right_name () =
    let cable_type =
      match cable_type with
      | "direct"     -> "straight-cable"
      | "crossover"  -> "crossover-cable"
      | "nullmodem"  -> assert false
      | _ -> assert false in
    let cable_row_id =
      self#add_row
        [ name_header,       Row_item.String cable_name;
          type_header,       Row_item.Icon cable_type;
          uneditable_header, Row_item.CheckBox true; ] in
    ignore
      (self#add_row
         ~parent_row_id:cable_row_id
         (List.append
            [name_header, Row_item.String left_name;
             type_header, Row_item.Icon "leftward"]
            self#non_defective_defaults));
    ignore
      (self#add_row
         ~parent_row_id:cable_row_id
         (List.append
            [name_header, Row_item.String right_name;
             type_header, Row_item.Icon "rightward"]
            self#non_defective_defaults));
    self#collapse_row cable_row_id;

  (* Used importing hub/switch/.. for backward compatibility: *)
  method change_port_user_offset ~device_name ~user_port_offset =
    let offset = user_port_offset in
    let update name =
      try  Scanf.sscanf name "eth%i"  (fun i -> Printf.sprintf "eth%d"  (i+offset)) with _ ->
      try  Scanf.sscanf name "port%i" (fun i -> Printf.sprintf "port%d" (i+offset)) with _ ->
      name
    in
    let device_row_id = self#unique_row_id_of_name device_name in
    let port_row_ids = Forest.children_nodes device_row_id !id_forest in
    List.iter (self#update_row_name update) port_row_ids

  method private add_port
    ?(defective_by_default=false)
    ~device_name
    ~port_prefix
    ~user_port_offset
    =
    let defaults =
      if defective_by_default
        then self#defective_defaults
        else self#non_defective_defaults
    in
    let device_row_id = self#unique_row_id_of_name device_name in
    let current_port_no = self#children_no_of ~parent_name:device_name in
    let current_user_port_index = current_port_no + user_port_offset in
    let port_type =
      match self#get_row_type (device_row_id) with
      | "machine" (*| "world_bridge"*) -> "machine-port"
      | "gateway" (* retro-compatibility *) -> "machine-port"
      | _ -> "other-device-port" in
    let port_row_id =
      self#add_row
        ~parent_row_id:device_row_id
        [ name_header, Row_item.String (Printf.sprintf "%s%i" port_prefix current_user_port_index);
          type_header, Row_item.Icon port_type;
          uneditable_header, Row_item.CheckBox true; ] in
    let _inward_row_id =
      (self#add_row
         ~parent_row_id:port_row_id
         (List.append
            [name_header, Row_item.String "inward";
             type_header, Row_item.Icon "inward"]
            self#non_defective_defaults)) in
    let outward_row_id =
      (self#add_row
         ~parent_row_id:port_row_id
         (List.append
            [name_header, Row_item.String "outward";
             type_header, Row_item.Icon "outward"]
            defaults)) in
    if defective_by_default then begin
      (* In a single direction suffice: *)
      self#show_that_it_is_defective outward_row_id;
    end


  method update_port_no
    ?(defective_by_default=false)
    ~device_name
    ~port_no
    ~port_prefix
    ~user_port_offset
    ()
    =
    let add_child_of device_name =
        self#add_port ~defective_by_default ~device_name ~port_prefix ~user_port_offset
    in
    self#update_children_no ~add_child_of ~parent_name:device_name port_no

  method get_port_data device_name port_name port_direction =
    let port_row = self#get_complete_row_of_child ~parent_name:device_name ~child_name:port_name in
    let port_id = self#id_of_complete_row port_row in
    let port_direction_ids = self#children_of port_id in
    let port_direction_str = string_of_port_direction (port_direction) in
    List.find
      (fun row -> Row.Icon_field.eq ~field:type_header ~value:port_direction_str row)
      (List.map self#get_row port_direction_ids)

  method get_cable_data cable_name cable_direction =
    let cable_row_id = self#unique_row_id_of_name cable_name in
    let cable_direction_ids = self#children_of cable_row_id in
    let cable_direction_str = string_of_cable_direction (cable_direction) in
    let filtered_cable_directions =
      List.filter
        (fun row -> Row.Icon_field.eq ~field:type_header ~value:cable_direction_str row)
        (List.map self#get_row cable_direction_ids) in
    let found = List.length filtered_cable_directions in
    (* B6 (episode 6): a named failure instead of `assert', whose "Assertion failed" said nothing
       of what was wrong. Since ensure_cable_entry completes the missing rows when the component
       is created, `found = 0' should no longer be reachable here; `found > 1' still is, as
       duplicate rows are reported but never removed — deleting a row the user may have set
       defects on is not a decision this method can take on its own. *)
    if found <> 1 then
      failwith
        (Printf.sprintf
           "Treeview_defects#get_cable_data: the entry of the cable \"%s\" has %d row(s) for the direction \"%s\" instead of exactly one"
           cable_name found cable_direction_str);
    List.hd filtered_cable_directions

  method rename_cable_endpoints cable_name left_endpoint_name right_endpoint_name =
    let cable_row_id = self#unique_row_id_of_name cable_name in
    let cable_direction_ids = self#children_of cable_row_id in
    (* B6 (episode 6): same reasoning as in get_cable_data above. *)
    if (List.length cable_direction_ids) <> 2 then
      failwith
        (Printf.sprintf
           "Treeview_defects#rename_cable_endpoints: the entry of the cable \"%s\" has %d direction row(s) instead of exactly two"
           cable_name (List.length cable_direction_ids));
    let directions = List.map self#get_complete_row cable_direction_ids in
    let leftward_direction  =
      List.find (fun row -> Row.Icon_field.eq ~field:type_header ~value:"leftward" row)  directions
    in
    let rightward_direction =
      List.find (fun row -> Row.Icon_field.eq ~field:type_header ~value:"rightward" row)  directions
    in
    self#set_row_name (Row.get_id leftward_direction)  (left_endpoint_name);
    self#set_row_name (Row.get_id rightward_direction) (right_endpoint_name);

  (** Return a single port attribute as an item: *)
  method get_port_attribute device_name port_name port_direction field =
    let row = self#get_port_data (device_name) (port_name) (port_direction) in
    float_of_string (Row.String_field.get ~field row)

  method get_port_attribute_of
    ~device_name
    ~port_prefix
    ~port_index
    ~user_port_offset
    ~port_direction
    ~column_header
    ()
    =
    let user_port_index = port_index + user_port_offset in
    let port_name = Printf.sprintf "%s%i" port_prefix user_port_index in
    self#get_port_attribute device_name port_name port_direction column_header

  (** Return a single cable attribute as an item: *)
  method get_cable_attribute cable_name cable_direction field =
    let row = self#get_cable_data (cable_name) (cable_direction) in
    float_of_string (Row.String_field.get ~field row)

  method private is_empty_or_a_number_between s minimum maximum =
    s = "" ||
    (try
      Scanf.sscanf s "%f" (fun x -> x >= minimum && x <= maximum)
    with _ -> false)

  method private is_a_valid_percentage s =
    self#is_empty_or_a_number_between s 0.0 100.0

  method private is_a_valid_non_100_percentage s =
    self#is_empty_or_a_number_between s 0.0 99.0

  method private is_a_valid_delay s =
    self#is_empty_or_a_number_between s 0.0 100000.0

  method private show_that_it_is_defective row_id =
    self#highlight_row row_id

  method private show_that_it_is_not_defective row_id =
    self#unhighlight_row row_id

  (** Return true iff there exists at least a defect in the given row.
      If given, use the given values for minimum and maximum delay instead
      of the ones found in the row: *)
  method private is_defective ?minimum_delay ?maximum_delay row_id =
    let row =
      List.filter
        (fun (header, _) ->
          let c = String.get header ((String.length header) - 1) in
          ((c = ')' || c = '%') && (* we're interested in percentages and times *)
          (match minimum_delay with
            None -> true
          | Some _ -> not (header = minimum_delay_header)) &&
          (match maximum_delay with
            None -> true
          | Some _ -> not (header = maximum_delay_header))))
        (self#get_row row_id) in
    let values =
      List.map
        (fun (_, i) -> let s = Row_item.extract_String i in try float_of_string s with _ -> 0.0)
        row in
    let values =
      match maximum_delay with None -> values | Some x -> x :: values in
    let values =
      match minimum_delay with None -> values | Some x -> x :: values in
    List.exists
      (fun x -> x > 0.0)
      values

  method private show_defectiveness ?minimum_delay ?maximum_delay row_id =
    if self#is_defective ?minimum_delay ?maximum_delay row_id then
      self#show_that_it_is_defective row_id
    else
      self#show_that_it_is_not_defective row_id

  (* --- Episode 5c, work-stream "marionnet-pilotage-par-script" ---
     Everything the GTK cell-edited path does *after* a defects cell has been committed, and that
     [#set_row_field] does not do: realign the sister bound when the two delays cross, refresh the
     highlighting of the row, and say when a flipped-bits percentage is unusually high. It is
     extracted here on the very shape of [#constraints_verdict] (episode 5b): the method *does* the
     writes and *returns* what is to be reported, showing nothing — the GUI turns the verdict into
     a dialog, the control server into a JSON field. One source of truth, two messages.

     Precondition, the same one the GTK path satisfies (Treeview.editable_string_column#on_edit):
     the edited cell has ALREADY been written when this is called; [new_content] is its value.

     Returns: (the realigned column and its new value) option × (warning title and body) option,
     both members being translated strings, hence never to be printed with %S (episode 5b). *)
  method edit_side_effects
    ~(row_id : string) ~(header : column_header) ~(new_content : string)
    : (column_header * string) option * (string * string) option
    =
    (* An empty cell means zero here, as [is_defective] already reads it (float_of_string fails and
       the value counts as 0.0). Reading it as an exception instead is what made the GUI drop the
       whole update — including the device restart — whenever a delay cell was cleared. *)
    let float_or_zero s = if s = "" then 0.0 else try float_of_string s with _ -> 0.0 in
    if header = minimum_delay_header then
      let minimum_delay = float_or_zero new_content in
      let maximum_delay = float_or_zero (self#get_row_maximum_delay row_id) in
      let adjusted =
        if minimum_delay > maximum_delay then
          let value = string_of_float minimum_delay in
          let () = self#set_row_maximum_delay row_id value in
          Some (maximum_delay_header, value)
        else None
      in
      let () =
        self#show_defectiveness ~maximum_delay:(max minimum_delay maximum_delay) row_id
      in
      (adjusted, None)
    else if header = maximum_delay_header then
      let maximum_delay = float_or_zero new_content in
      let minimum_delay = float_or_zero (self#get_row_minimum_delay row_id) in
      let adjusted =
        if minimum_delay > maximum_delay then
          let value = string_of_float maximum_delay in
          let () = self#set_row_minimum_delay row_id value in
          Some (minimum_delay_header, value)
        else None
      in
      let () =
        self#show_defectiveness ~minimum_delay:(min minimum_delay maximum_delay) row_id
      in
      (adjusted, None)
    else
      let () = self#show_defectiveness row_id in
      let warning =
        if header = flipped_bits_header && (float_or_zero new_content) > 1.0 then
          Some ((s_ "This value may be too high"),
                (s_ "Please consider that a flipped bits percentage greater than 1% implies *many* transmission errors.\n\nAnyway you are free to experiment with any percentage."))
        else None
      in
      (None, warning)

  (** grandparent for devices, parent for cables: *)
  method private relevant_device_name_for_row_id row_id =
    try  self#get_row_grandparent_name row_id
    with _ -> self#get_row_parent_name row_id

  initializer
    let _ =
      self#add_checkbox_column
        ~header:uneditable_header
        ~hidden:true
        ~default:(fun () -> Row_item.CheckBox false)
        () in
    let _ =
      self#add_icon_column
        ~header:type_header
        ~shown_header:(s_ "Type")
        ~strings_and_pixbufs:[
	    "machine", Initialization.Path.images^"treeview-icons/machine.xpm";
	    "hub",     Initialization.Path.images^"treeview-icons/hub.xpm";
	    "switch",  Initialization.Path.images^"treeview-icons/switch.xpm";
	    "router",  Initialization.Path.images^"treeview-icons/router.xpm";
	    "cloud",   Initialization.Path.images^"treeview-icons/cloud.xpm";
	    "world_bridge",  Initialization.Path.images^"treeview-icons/world.xpm";
	    "gateway" (* retro-compatibility: *),  Initialization.Path.images^"treeview-icons/world.xpm";
	    "straight-cable",    Initialization.Path.images^"treeview-icons/cable-grey.xpm";
	    "crossover-cable",   Initialization.Path.images^"treeview-icons/cable-blue.xpm";
	    "machine-port",      Initialization.Path.images^"treeview-icons/network-card.xpm";
	    "other-device-port", Initialization.Path.images^"treeview-icons/port.xpm";

	    "rightward", Initialization.Path.images^"treeview-icons/left-to-right.xpm";
	    "leftward",  Initialization.Path.images^"treeview-icons/right-to-left.xpm";
	    "outward",   Initialization.Path.images^"treeview-icons/in-to-out.xpm";
	    "inward",    Initialization.Path.images^"treeview-icons/out-to-in.xpm";
            ]
        () in
    let loss =
      self#add_editable_string_column
        ~header:loss_header
        ~shown_header:(s_ "Loss %")
        ~default:(fun () -> Row_item.String "")
        ~constraint_predicate:(fun i -> let i = Row_item.extract_String i in self#is_a_valid_percentage i)
        () in
    let duplication =
      self#add_editable_string_column
        ~header:duplication_header
        ~shown_header:(s_ "Duplication %")
        ~default:(fun () -> Row_item.String "")
        ~constraint_predicate:(fun i -> let i = Row_item.extract_String i in self#is_a_valid_non_100_percentage i)
        () in
    let flipped_bits =
      self#add_editable_string_column
        ~header:flipped_bits_header
        ~shown_header:(s_ "Flipped bits %")
        ~default:(fun () -> Row_item.String "")
        ~constraint_predicate:(fun i -> let i = Row_item.extract_String i in self#is_a_valid_percentage i)
        () in
    let minimum_delay =
      self#add_editable_string_column
        ~header:minimum_delay_header
        ~shown_header:(s_ "Minimum delay (ms)")
        ~default:(fun () -> Row_item.String "")
        ~constraint_predicate:(fun i -> let i = Row_item.extract_String i in self#is_a_valid_delay i)
        () in
    let maximum_delay =
      self#add_editable_string_column
        ~header:maximum_delay_header
        ~shown_header:(s_ "Maximum delay (ms)")
        ~default:(fun () -> Row_item.String "")
        ~constraint_predicate:(fun i -> let i = Row_item.extract_String i in self#is_a_valid_delay i)
        () in
    (* The five editable columns share one commit path (episode 5c): what each of them used to do
       inline now lives in [#edit_side_effects], which the control server calls too. Here the
       verdict becomes a dialog; there, a JSON field. *)
    List.iter
      (fun column ->
         column#set_after_edit_commit_callback
           (fun row_id _old_content new_content ->
              match
                self#edit_side_effects ~row_id ~header:(column#header) ~new_content
              with
              | _, Some (title, message) -> Simple_dialogs.warning title message ()
              | _, None -> ()))
      [ loss; duplication; flipped_bits; minimum_delay; maximum_delay ];

  self#add_row_constraint
    ~name:(s_ "you should choose a direction to define this parameter")
    (fun row ->
      let uneditable = Row.CheckBox_field.get ~field:uneditable_header row in
      (not uneditable) ||
      (List.for_all (fun (name, value) ->
                       name = name_header ||
                       name = type_header ||
                       name = uneditable_header ||
                       self#is_column_reserved name ||
                       value = Row_item.String "")
                    row));

    self#set_after_update_callback
      (fun row_id ->
        after_user_edit_callback (self#relevant_device_name_for_row_id row_id));

    (* Make internal data structures: no more columns can be added now: *)
    self#create_store_and_view;

    (* Setup the contextual menu: *)
    self#set_contextual_menu_title "Defects operations";
end;;

class treeview = t
module The_unique_treeview = Stateful_modules.Variable (struct
  type t = treeview
  let name = Some "treeview_defects"
  end)
let extract = The_unique_treeview.extract

let make ~(window:GWindow.window) ~(hbox:GPack.box) ~after_user_edit_callback ~method_directory ~method_filename () =
  let result = new t ~packing:(hbox#add) ~method_directory ~method_filename ~after_user_edit_callback () in
  let _toolbar = Treeview.add_expand_and_collapse_button ~window ~hbox (result:>Treeview.t) in
  The_unique_treeview.set result;
  result
;;
