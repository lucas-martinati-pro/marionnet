(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008, 2009  Luca Saiu
   Copyright (C) 2009, 2010, 2012  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2009, 2010, 2012  Université Paris 13
   Copyright (C) 2026  Jean-Vincent Loddo

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

(* The DATA of a treeview: a row, its items, and their JSON codec. Nothing here knows
   about Gtk+, which is the whole point of the module existing: [Treeview] itself is a
   widget, hence part of the GUI executable, hence out of reach of the (tests) stanza -
   while what a project file contains is exactly what must be tested without a display.
   [Treeview] keeps referring to these two modules under their historical names:

     module Row_item = Treeview_row.Row_item
     module Row      = Treeview_row.Row

   so no caller had to change when they moved here (work-stream
   `migration-marshal-to-text', episode 3). *)

(* --- *)
module ListExtra  = Ocamlbricks.ListExtra
module Forest     = Ocamlbricks.Forest
module Json_bricks = Ocamlbricks.Json_bricks
(* --- *)

module Row_item = struct

  type t =
  | String of string
  | CheckBox of bool
  | Icon of string;; (* Ugly, but this avoids that OCaml bitches about
			parametric polymorphism and classes *)

  (* For debugging: *)
  let sprint = function
  | String s   -> Printf.sprintf "String \"%s\"" s
  | CheckBox b -> Printf.sprintf "CheckBox %b" b
  | Icon s     -> Printf.sprintf "Icon \"%s\"" s

  let failwith x = failwith ("Treeview.Row_item."^x)
  let failwithf frmt t = failwith (Printf.sprintf frmt (sprint t))

  let extract_String = function
  | String s -> s
  | t -> failwithf "Row_item.extract_String: expected a Row_item.String, but found %s" t;;

  let extract_CheckBox = function
  | CheckBox b -> b
  | t -> failwithf "Row_item.extract_CheckBox: expected a Row_item.CheckBox, but found %s" t;;

  let extract_Icon = function
  | Icon s -> s
  | t -> failwithf "Row_item.extract_Icon: expected a Row_item.Icon, but found %s" t;;

  let return_String x   = String x
  let return_CheckBox x = CheckBox x
  let return_Icon x     = Icon x

  module type Projection_injection =
    sig
      val constr_name : string
      type a
      val extract : t -> a
      val return  : a -> t
    end

  module String_prj_inj : (Projection_injection with type a = string) =
    struct
      let constr_name="String"
      type a = string let extract = extract_String let return = return_String
    end

  module CheckBox_prj_inj : (Projection_injection with type a = bool) =
    struct
      let constr_name="CheckBox"
      type a = bool let extract = extract_CheckBox let return = return_CheckBox
    end

  module Icon_prj_inj : (Projection_injection with type a = string) =
    struct
      let constr_name="Icon"
      type a = string let extract = extract_Icon let return = return_Icon
    end

  (** Return a written representation of the given item, suitable for debugging,
      which also includes the constructor: *)
  let to_pretty_string = function
  | String s   -> Printf.sprintf "#string<%s>" s
  | CheckBox b -> Printf.sprintf "#checkbox<%b>" b
  | Icon s     -> Printf.sprintf "#icon<%s>" s

end (* module Row_item *)

(** A row is simply a list of non-conflicting pairs (field, row_item). We
    implement it in this way to make it easy to marshal, and realatively easy
    to manipulate at runtime. Of course by using lists instead of tuples we're
    avoiding potentially helpful type checks here, but here flexibility is more
    important *)
module Row = struct

  (* A row is in practice a record (non-ordered tuple with projections): *)
  type t = (field * Row_item.t) list
   and field = string

  (* Methods for generic fields:  *)

  let get_field ~field t : Row_item.t =
    ListExtra.Assoc.find field t

  let set_field ~field ~(value:Row_item.t) t : t =
    ListExtra.Assoc.set t field value

  let field_exists ~field t : bool =
    ListExtra.Assoc.mem field t

  let failwith x = failwith ("Treeview.Row."^x)

  let field_not_found ~caller ~field =
    failwith (Printf.sprintf "%s: row field `%s' not found" caller field)

  module Make_field_accessors (Prj_inj : Row_item.Projection_injection)
  : sig
      val set : field:string -> value:Prj_inj.a -> t -> t
      val get : ?caller:string -> field:string -> t -> Prj_inj.a
      val eq  : ?fallback:bool -> ?caller:string -> field:string -> value:Prj_inj.a -> t -> bool
    end
  = struct

    let unexpected_item ~caller ~field =
      failwith
        (Printf.sprintf "%s: row field `%s' is not a Row_item.%s"
           caller field Prj_inj.constr_name)

    let set ~field ~value t =
      set_field t ~field ~value:(Prj_inj.return value)

    let get
      ?(caller=(Printf.sprintf "%s_field.get" Prj_inj.constr_name)) ~field t =
      try
        let v = get_field ~field t in
        (try Prj_inj.extract v with _ -> unexpected_item ~caller ~field)
      with
        | Not_found -> field_not_found ~caller ~field

    let eq
      ?fallback
      ?(caller=(Printf.sprintf "%s_field.eq" Prj_inj.constr_name))
      ~field ~value t
      =
      let code () = ((get ~caller ~field t) = value) in
      match fallback with
      | None -> code ()
      | Some b -> try code () with _ -> b (* usually b=false *)

  end (* functor Row.Make_field_accessors *)

  module Icon_field     = Make_field_accessors(Row_item.Icon_prj_inj)
  module String_field   = Make_field_accessors(Row_item.String_prj_inj)
  module CheckBox_field = Make_field_accessors(Row_item.CheckBox_prj_inj)

  (* Specific methods for the string field "Name": *)
  let eq_name ?fallback value = String_field.eq ?fallback ~caller:"eq_name" ~field:"Name" ~value
  let get_name         = String_field.get ~caller:"get_name" ~field:"Name"
  let set_name value t = String_field.set ~field:"Name" ~value t

  (* Specific methods for the string field "_id": *)
  let eq_id ?fallback value = String_field.eq ?fallback ~caller:"eq_id" ~field:"_id" ~value
  let get_id         = String_field.get ~caller:"get_id" ~field:"_id"
  let set_id value t = String_field.set ~field:"_id" ~value t

 (** Print a written representation of the given row, suitable for debugging;
    the printed string also includes the constructor: *)
  let to_pretty_string row =
    let buffer = Buffer.create 100 in
    let print_string x = Buffer.add_string buffer x in
    let rec loop row =
      match row with
      | [] -> ()
      | (name, value) :: rest -> begin
	  print_string (Printf.sprintf "%s=%s " name (Row_item.to_pretty_string value));
	  loop rest;
      end in
    print_string "{ ";
    loop row;
    print_string "}";
    let result = Buffer.contents buffer in
    result

  let pretty_print ~channel row =
    Printf.kfprintf flush channel "%s\n" (to_pretty_string row)

end (* module Row *)


(* *************************** *
    JSON codec (project v3)
 * *************************** *)

(** A textual, self-describing serialization of what a treeview saves, replacing the
    [Marshal] dump of [states/states-forest], [states/ifconfig], [states/defects] and
    [states/texts] (work-stream `migration-marshal-to-text', see
    docs/migration-marshal-to-text.md, section 4.2). What is saved is not the forest
    alone but the pair [(next_identifier, forest)] — the counter of fresh row identifiers
    travels with the rows it numbered. The shape is:

{v
{ "format": "marionnet/treeview", "version": 3,
  "next_identifier": 42,
  "rows": [ { "fields": [ [ "Name", { "kind": "string",   "value": "m1" } ],
                          [ "Type", { "kind": "icon",     "value": "machine" } ],
                          [ "Up",   { "kind": "checkbox", "value": true } ] ],
              "children": [] } ] }
v}

    Two shapes are deliberate here:

    - a field is a [name, value] {b pair in an array}, never a member of a JSON object,
      for the same reason as the attributes of an xforest: the OCaml type is an
      association list, and turning it into an object would silently reorder it and drop
      the duplicate keys a hand-repaired file may well carry;

    - an item is [{"kind": ..., "value": ...}] rather than the [{"String": ...}] which
      would mirror the OCaml constructors: the discriminant is then readable, and
      interrogable with [jq], without knowing the names of three constructors of a module
      nobody outside Marionnet has read.

    Strings are byte-safe (see {!Ocamlbricks.Json_bricks.json_of_string}): a field name
    and a string or icon value may be a [{"b64": ...}] object instead of a JSON string.
    Rows do carry arbitrary bytes — a comment typed in a guest, a filename in a forgotten
    locale. *)

module Json = struct

let json_format  = "marionnet/treeview" ;;
let json_version = 3 ;;

(* Named, as in [Xforest]: the plumbing is shared with the other v3 codecs. *)
let fail          = Json_bricks.fail ;;
let kind_of_json  = Json_bricks.kind_of ;;
let json_of_string = Json_bricks.json_of_string ;;
let string_of_json = Json_bricks.string_of_json ;;
let member_of      = Json_bricks.member_of ;;

let json_of_item : Row_item.t -> Yojson.Safe.t = function
  | Row_item.String s   ->
      `Assoc [ ("kind", `String "string");   ("value", (json_of_string s)) ]
  | Row_item.CheckBox b ->
      `Assoc [ ("kind", `String "checkbox"); ("value", `Bool b) ]
  | Row_item.Icon s     ->
      `Assoc [ ("kind", `String "icon");     ("value", (json_of_string s)) ]
;;

let item_of_json : Yojson.Safe.t -> Row_item.t = function
  | `Assoc fields ->
      let member = member_of ~where:"a field value" fields in
      let value = member "value" in
      (match member "kind" with
       | `String "string"   -> Row_item.String (string_of_json ~what:"a string value" value)
       | `String "icon"     -> Row_item.Icon   (string_of_json ~what:"an icon value" value)
       | `String "checkbox" ->
           (match value with
            | `Bool b -> Row_item.CheckBox b
            | j -> fail "a checkbox value should be a boolean, found %s" (kind_of_json j))
       (* Named, not guessed: an unknown kind is a file this binary does not understand,
          not a string to fall back on. *)
       | `String k -> fail "unknown field kind \"%s\" (expecting string, checkbox or icon)" k
       | j -> fail "\"kind\" should be a string, found %s" (kind_of_json j))
  | j -> fail "expected a field value as an object, found %s" (kind_of_json j)
;;

let json_of_field ((name, item) : Row.field * Row_item.t) : Yojson.Safe.t =
  `List [ (json_of_string name); (json_of_item item) ]
;;

let field_of_json : Yojson.Safe.t -> (Row.field * Row_item.t) = function
  | `List [name; item] ->
      ((string_of_json ~what:"a field name" name), (item_of_json item))
  | j -> fail "expected a field as a [name, value] pair, found %s" (kind_of_json j)
;;

(* As in [Xforest], both members of a row are required: an absent "children" read as no
   children would be a silent approximation, and the states of a machine are children. *)
let rec json_of_forest (forest : Row.t Forest.t) : Yojson.Safe.t =
  `List (List.map json_of_tree (Forest.to_treelist forest))

and json_of_tree ((row, children) : Row.t * Row.t Forest.t) : Yojson.Safe.t =
  `Assoc [ ("fields",   `List (List.map json_of_field row));
           ("children", (json_of_forest children)) ]
;;

let rec forest_of_json : Yojson.Safe.t -> Row.t Forest.t = function
  | `List trees -> Forest.of_treelist (List.map tree_of_json trees)
  | j -> fail "expected an array of rows, found %s" (kind_of_json j)

and tree_of_json : Yojson.Safe.t -> (Row.t * Row.t Forest.t) = function
  | `Assoc members ->
      let member = member_of ~where:"a row" members in
      (* Sequential on purpose: the first problem reported is the first one in reading
         order, which is what someone repairing a file by hand expects: *)
      let row      = fields_of_json (member "fields") in
      let children = forest_of_json (member "children") in
      (row, children)
  | j -> fail "expected a row as an object, found %s" (kind_of_json j)

and fields_of_json : Yojson.Safe.t -> Row.t = function
  | `List fields -> List.map field_of_json fields
  | j -> fail "expected \"fields\" as an array, found %s" (kind_of_json j)
;;

(** Encode a treeview content as a JSON text, newline-terminated. *)
let to_JSON_string ((next_identifier, forest) : int * Row.t Forest.t) : string =
  Json_bricks.to_text ~format:json_format ~version:json_version
    [ ("next_identifier", `Int next_identifier);
      ("rows",            (json_of_forest forest)) ]
;;

(** Decode a treeview content from a JSON text. Every failure - ill-formed JSON,
    unexpected format or version, missing member, unknown field kind, undecodable
    base64 - is reported as [Error message]. *)
let of_JSON_string (text:string) : ((int * Row.t Forest.t), string) result =
  Json_bricks.of_text ~format:json_format ~version:json_version
    ~decode:(fun member ->
      let next_identifier =
        match member "next_identifier" with
        | `Int i -> i
        | j -> fail "\"next_identifier\" should be an integer, found %s" (kind_of_json j)
      in
      (next_identifier, (forest_of_json (member "rows"))))
    text
;;

(** Write a treeview content into a file. As with the [Marshal] path it replaces, an I/O
    failure is raised, not returned: a project that cannot be saved must be reported as
    such. *)
let to_JSON_file (content : int * Row.t Forest.t) (filename:string) : unit =
  Json_bricks.write_file ~filename (to_JSON_string content)
;;

(** Read a treeview content from a file. Unlike its writing counterpart, I/O failures are
    returned as [Error message]: an unreadable project file is an ordinary case here,
    dealt with by the caller together with the decoding failures. *)
let of_JSON_file (filename:string) : ((int * Row.t Forest.t), string) result =
  match Json_bricks.read_file filename with
  | Error msg -> Error msg
  | Ok text ->
      (match of_JSON_string text with
       | Ok content -> Ok content
       | Error msg  -> Error (Printf.sprintf "%s: %s" filename msg))
;;

end (* module Json *)
