(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007  Jean-Vincent Loddo
   Copyright (C) 2008  Luca Saiu
   Copyright (C) 2007, 2008  Université Paris 13

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


(** A forest concretization very close to XML. The type of nodes is
    [string * (string * string list)] where the first element is the
    tag and the second is the list of attributes, i.e. bindings in the
    form (key,value) where both key and value are strings. *)

(* --- *)
(* module Log = Marionnet_log *)
module Log = Ocamlbricks_log
(* module Forest = Ocamlbricks.Forest *)
type tag = string ;;

type attribute  = (string * string) ;;
type attributes = attribute list ;;

type node   = tag * attributes ;;

(** The forest concretization and its aliases. *)

type forest = node Forest.t ;;
type t      = forest ;;
type tree   = node * forest ;; (* the root and its children *)


(* *************************** *
        Class interpreter
 * *************************** *)

(** An Xforest interpreter is an object able to update itself
    reading an Xforest and, conversely, able to encode itself
    into an Xforest *)
class virtual interpreter () = object (self)

 (** Interpret a tree. The tag is ignored here. *)
 method from_tree ((tag,attrs):node) (children:forest) =
  begin
   (* Interpret attributes *)
   Log.printf1 "About to interpret *attributes* with tag \"%s\"\n" tag;
   List.iter self#eval_forest_attribute attrs;

   (* Interpret children *)
   Log.printf1 "About to interpret *children* with tag \"%s\"\n" tag;
   let l = Forest.to_treelist children in
   List.iter (self#eval_forest_child) l
  end

 (** The default interpretation of an attribute is ignore. *)
 method eval_forest_attribute : (attribute -> unit) =
   fun attr -> ()

 (** The default interpretation of a child is ignore. *)
 method eval_forest_child : (tree -> unit) =
  fun tree -> ()

 (** Encode self into an xtree. Typically this method calls
     recursively the same method of its children in order to construct
      its representation as forest. *)
 method virtual to_tree : tree

 (** May be redefined. Otherwise, by default, is simply a call to the method constructing
     the tree which is transformed in a forest (singleton). *)
 method to_forest : forest =
   Forest.of_tree self#to_tree

end;; (* class interpreter *)


(** print_forest specialization for xforest *)
let print_xforest ?level ~channel forest =
 let string_of_attr (name,value) = (name^"="^"\""^value^"\"") in
 let fold_strings = function
  | []   -> ""
  | [x]  -> x
  | x::r -> List.fold_left (fun a b -> a ^ " " ^ b) x r  in
 let string_of_attrs attrs = fold_strings (List.map string_of_attr attrs) in
 let string_of_node (tag,attrs) = ("<" ^ tag ^ "[" ^ (string_of_attrs attrs) ^ "]>") in
 Forest.print_forest ?level ~string_of_node ~channel forest
;;

(** Facilities for encoding/decoding fields in an object which are not strings. *)

let encode x = Marshal.to_string   x [Marshal.No_sharing] ;;
let decode y = Marshal.from_string y 0 ;;


(* *************************** *
    JSON codec (project v3)
 * *************************** *)

(** A textual, self-describing serialization of an xforest, replacing the [Marshal] dumps
    of [netmodel/network.xml] and [netmodel/dotoptions.marshal] (Marionnet work-stream
    `migration-marshal-to-text', see docs/migration-marshal-to-text.md, section 4.1).
    The shape is:

{v
{ "format": "marionnet/xforest", "version": 3,
  "roots": [ { "tag": "network",
               "attrs": [ [ "name", "projet1" ] ],
               "children": [] } ] }
v}

    Attributes are an ordered {b list of pairs}, never a JSON object. The OCaml type is
    [(string * string) list], where the order is meaningful (attributes are interpreted
    sequentially by [#eval_forest_attribute]) and duplicate keys are possible: both
    properties would be silently destroyed by a JSON object.

    Any string (a tag, an attribute name or an attribute value) which is not valid UTF-8
    is written as [{"b64": "..."}] instead of a JSON string. That fallback is not a
    precaution against losing data: yojson happens to write raw bytes verbatim and to
    reread them faithfully. It is the only way to emit a text which is valid JSON {e at
    all}, which is the whole point of the migration - a project any other tool can read.
    A [\uXXXX] escape would {b not} do: it denotes a code point, not a byte, so writing
    0x8F that way and rereading it yields U+008F, that is two bytes once in UTF-8. *)

let json_format  = "marionnet/xforest" ;;
let json_version = 3 ;;

(* The byte-safe representation of a string (the base64 fallback and the trap it avoids),
   the reporting of a malformed text and the {"format", "version", ...} envelope are the
   same for every v3 file of a project - here, but also for the forest of treeview rows
   and for the counters of the treeview `ifconfig', both in Marionnet's bin/. They are
   therefore stated once, in [Json_bricks], and only named here: *)
let fail          = Json_bricks.fail ;;
let kind_of_json  = Json_bricks.kind_of ;;
let json_of_string = Json_bricks.json_of_string ;;
let string_of_json = Json_bricks.string_of_json ;;
let member_of      = Json_bricks.member_of ;;

let json_of_attribute ((name, value) : attribute) : Yojson.Safe.t =
  `List [ (json_of_string name); (json_of_string value) ]
;;

let attribute_of_json : Yojson.Safe.t -> attribute = function
  | `List [name; value] ->
      ((string_of_json ~what:"attribute name"  name),
       (string_of_json ~what:"attribute value" value))
  | j -> fail "expected an attribute as a [name, value] pair, found %s" (kind_of_json j)
;;

let rec json_of_forest (forest:forest) : Yojson.Safe.t =
  `List (List.map json_of_tree (Forest.to_treelist forest))

and json_of_tree (((tag, attrs), children) : tree) : Yojson.Safe.t =
  `Assoc [ ("tag",      (json_of_string tag));
           ("attrs",    `List (List.map json_of_attribute attrs));
           ("children", (json_of_forest children)) ]
;;

(* Note that the three members of a tree are all required ([member_of] fails on a missing
   one): rebuilding an absent "children" as an empty forest, say, would reintroduce
   exactly the kind of silent approximation this format was introduced to remove. *)
let rec forest_of_json : Yojson.Safe.t -> forest = function
  | `List trees -> Forest.of_treelist (List.map tree_of_json trees)
  | j -> fail "expected an array of trees, found %s" (kind_of_json j)

and tree_of_json : Yojson.Safe.t -> tree = function
  | `Assoc fields ->
      let member = member_of ~where:"a tree" fields in
      (* Sequential on purpose: the first problem reported is the first one in reading
         order, which is what someone repairing a file by hand expects: *)
      let tag      = string_of_json ~what:"tag" (member "tag") in
      let attrs    = attributes_of_json (member "attrs") in
      let children = forest_of_json (member "children") in
      ((tag, attrs), children)
  | j -> fail "expected a tree as an object, found %s" (kind_of_json j)

and attributes_of_json : Yojson.Safe.t -> attributes = function
  | `List attrs -> List.map attribute_of_json attrs
  | j -> fail "expected \"attrs\" as an array, found %s" (kind_of_json j)
;;

(** Encode a forest as a JSON text, newline-terminated. *)
let to_JSON_string (forest:forest) : string =
  Json_bricks.to_text ~format:json_format ~version:json_version
    [ ("roots", (json_of_forest forest)) ]
;;

(** Decode a forest from a JSON text. Every failure - ill-formed JSON, unexpected format
    or version, missing member, undecodable base64 - is reported as [Error message]. *)
let of_JSON_string (text:string) : (forest, string) result =
  Json_bricks.of_text ~format:json_format ~version:json_version
    ~decode:(fun member -> forest_of_json (member "roots"))
    text
;;

(** Write a forest into a file. As with the [Marshal] path it replaces, an I/O failure is
    raised, not returned: a project that cannot be saved must be reported as such. *)
let to_JSON_file (forest:forest) (filename:string) : unit =
  Json_bricks.write_file ~filename (to_JSON_string forest)
;;

(** Read a forest from a file. Unlike its writing counterpart, I/O failures are returned
    as [Error message]: an unreadable project file is an ordinary case here, dealt with
    by the caller together with the decoding failures. *)
let of_JSON_file (filename:string) : (forest, string) result =
  match Json_bricks.read_file filename with
  | Error msg -> Error msg
  | Ok text ->
      (match of_JSON_string text with
       | Ok forest -> Ok forest
       | Error msg -> Error (Printf.sprintf "%s: %s" filename msg))
;;

(** EXAMPLE 1 *)

(* In a class, just add method like:

method to_tree =
 Forest.leaf ("cable",[("name","xxx");("label","xxx")]);;

method eval_forest_attribute : (string * string) -> unit = function
 | ("name",name) -> self#set_name name
 | ("kind",kind) -> self#set_kind kind
 | _ -> () *)

(** EXAMPLE 2 *)

(*method to_tree =
 let name = Forest.tree ("name",[]) (Forest.leaf ("xxx",[]))
 let kind = Forest.tree ("kind",[]) (Forest.leaf ("yyy",[]))
 in Forest.node ("cable",[]) (Forest.of_treelist [name; kind])

(** EXAMPLE 2 *)
method eval_forest_child (root,children) = match root with
 | ("name", attrs) ->
     let name = new name () in (* nel new senza argomenti l'essenza della backward-compatibility *)
     name#from_tree x;       (* chiamata ricorsiva al from_forest *)
     self#set_name = name;     (* oppure potrei accumulare... *)
 ...
 | _ -> ()
 *)


