(* This file is part of Marionnet, a virtual network laboratory
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

(* The JSON codec of the counters of the treeview `ifconfig'. The contract, the JSON
   schema and the reasons behind it are documented in treeview_counters.mli. *)

(* --- *)
module Json_bricks = Ocamlbricks.Json_bricks
(* --- *)

type t = int * int * Int64.t ;;  (* obsolete mac, next IPv4, next IPv6 *)

let json_format  = "marionnet/ifconfig-counters" ;;
let json_version = 3 ;;

(* Named, as in [Xforest] and [Treeview_row.Json]: the plumbing is shared. *)
let fail         = Json_bricks.fail ;;
let kind_of_json = Json_bricks.kind_of ;;

let int_member ~(name:string) (member : string -> Yojson.Safe.t) : int =
  match member name with
  | `Int i -> i
  | j -> fail "\"%s\" should be an integer, found %s" name (kind_of_json j)
;;

let int64_member ~(name:string) (member : string -> Yojson.Safe.t) : Int64.t =
  match member name with
  | `String s ->
      (match Int64.of_string_opt s with
       | Some i -> i
       | None   -> fail "\"%s\": \"%s\" is not a 64 bit integer" name s)
  | j -> fail "\"%s\" should be a string holding a 64 bit integer, found %s" name (kind_of_json j)
;;

let to_JSON_string ((obsolete_mac, next_ipv4, next_ipv6) : t) : string =
  Json_bricks.to_text ~format:json_format ~version:json_version
    [ ("obsolete_mac_address_as_int", `Int obsolete_mac);
      ("next_ipv4_address_as_int",    `Int next_ipv4);
      ("next_ipv6_address_as_int",    `String (Int64.to_string next_ipv6)) ]
;;

let of_JSON_string (text:string) : (t, string) result =
  Json_bricks.of_text ~format:json_format ~version:json_version
    ~decode:(fun member ->
      ((int_member   ~name:"obsolete_mac_address_as_int" member),
       (int_member   ~name:"next_ipv4_address_as_int"    member),
       (int64_member ~name:"next_ipv6_address_as_int"    member)))
    text
;;

let to_JSON_file (counters : t) (filename:string) : unit =
  Json_bricks.write_file ~filename (to_JSON_string counters)
;;

let of_JSON_file (filename:string) : (t, string) result =
  match Json_bricks.read_file filename with
  | Error msg -> Error msg
  | Ok text ->
      (match of_JSON_string text with
       | Ok counters -> Ok counters
       | Error msg   -> Error (Printf.sprintf "%s: %s" filename msg))
;;
