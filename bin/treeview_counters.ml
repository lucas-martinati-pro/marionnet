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

(** The JSON codec of the counters of the treeview `ifconfig' — the eighth and smallest of
    the files a project keeps in [Marshal] form ([states/ifconfig-counters]); work-stream
    `migration-marshal-to-text', see docs/migration-marshal-to-text.md, section 4.3.

    The triple is the one [Treeview_ifconfig] marshals and demarshals, in that very order:

{v
{ "format": "marionnet/ifconfig-counters", "version": 3,
  "obsolete_mac_address_as_int": 12345678,
  "next_ipv4_address_as_int": 1,
  "next_ipv6_address_as_int": "1" }
v}

    Two remarks the schema alone does not carry:

    - [next_ipv6_address_as_int] is an [Int64.t], and it travels {b as a string}: JSON has
      no portable 64 bit integer (its numbers are IEEE 754 doubles as far as any other
      reader is concerned, hence exact only up to 2^53). It is written in one form and
      read in one form only, a string: accepting a JSON number as well would make a
      reread depend on which of the two a writer happened to choose;

    - the first field is [_OBSOLETE_mac_address_as_int] on the OCaml side, kept because it
      is already written "for forward compatibility" and this work-stream is not the place
      to remove a field from a file older binaries may read. Note that it is drawn {e at
      random} at every save ([Treeview_ifconfig#save]), which is why the bench of episode 1
      expects those four bytes, and only those, to change from one save to the next.

    ⚠️ The loading path this codec is meant for is wrapped in a [try ... with _ -> ()]
    ([Treeview_ifconfig#load_counters]): a conversion failing there would be {b silent},
    and a project would go on with fresh-address counters reset to 1 - handing out
    addresses already in use. Hence the unit tests, and hence a bench which checks the
    counters {e explicitly} rather than trusting a load which raises nothing. *)

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

(** Encode the counters as a JSON text, newline-terminated. *)
let to_JSON_string ((obsolete_mac, next_ipv4, next_ipv6) : t) : string =
  Json_bricks.to_text ~format:json_format ~version:json_version
    [ ("obsolete_mac_address_as_int", `Int obsolete_mac);
      ("next_ipv4_address_as_int",    `Int next_ipv4);
      ("next_ipv6_address_as_int",    `String (Int64.to_string next_ipv6)) ]
;;

(** Decode the counters from a JSON text. Every failure - ill-formed JSON, unexpected
    format or version, missing member, unparsable 64 bit integer - is reported as
    [Error message]. *)
let of_JSON_string (text:string) : (t, string) result =
  Json_bricks.of_text ~format:json_format ~version:json_version
    ~decode:(fun member ->
      ((int_member   ~name:"obsolete_mac_address_as_int" member),
       (int_member   ~name:"next_ipv4_address_as_int"    member),
       (int64_member ~name:"next_ipv6_address_as_int"    member)))
    text
;;

(** Write the counters into a file. As with the [Marshal] path it replaces, an I/O failure
    is raised, not returned. *)
let to_JSON_file (counters : t) (filename:string) : unit =
  Json_bricks.write_file ~filename (to_JSON_string counters)
;;

(** Read the counters from a file. I/O failures are returned as [Error message], together
    with the decoding failures. *)
let of_JSON_file (filename:string) : (t, string) result =
  match Json_bricks.read_file filename with
  | Error msg -> Error msg
  | Ok text ->
      (match of_JSON_string text with
       | Ok counters -> Ok counters
       | Error msg   -> Error (Printf.sprintf "%s: %s" filename msg))
;;
