(* This file is part of ocamlbricks
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

(** The plumbing shared by the JSON codecs of a Marionnet project file. See the interface
    for what each function promises; the comments here are about how it is done. *)

(* Raised while decoding, caught back in [of_text]: *)
exception Malformed of string ;;
let fail fmt = Printf.ksprintf (fun msg -> raise (Malformed msg)) fmt ;;

let kind_of = function
  | `String _ -> "a string"  | `Int _   -> "an integer" | `Float _ -> "a float"
  | `Bool _   -> "a boolean" | `Null    -> "null"
  | `List _   -> "an array"  | `Assoc _ -> "an object"
  | _         -> "an unexpected value"
;;

(* A string is written as a JSON string when, and only when, it is valid UTF-8. The stdlib
   decoder is taken as the reference, since it also rejects overlong encodings and
   surrogates - which a hand-written check usually forgets: *)
let is_valid_utf_8 (s:string) : bool =
  let n = String.length s in
  let rec loop i =
    (i >= n) ||
    (let d = String.get_utf_8_uchar s i in
     (Uchar.utf_decode_is_valid d) && (loop (i + Uchar.utf_decode_length d)))
  in
  loop 0
;;

let json_of_string (s:string) : Yojson.Safe.t =
  if is_valid_utf_8 s
    then `String s
    else `Assoc [("b64", `String (Base64.encode_string s))]
;;

let string_of_json ~(what:string) : Yojson.Safe.t -> string = function
  | `String s -> s
  | `Assoc [("b64", `String b)] ->
      (match Base64.decode b with
       | Ok s -> s
       | Error (`Msg m) -> fail "%s: invalid base64 content (%s)" what m)
  | j -> fail "%s: expected a string or a {\"b64\": ...} object, found %s" what (kind_of j)
;;

let member_of ~(where:string) (fields : (string * Yojson.Safe.t) list) (key:string) =
  try List.assoc key fields with
  | Not_found -> fail "missing member \"%s\" in %s" key where
;;

let to_text ~(format:string) ~(version:int) (members : (string * Yojson.Safe.t) list) =
  let json = `Assoc (("format", `String format) :: ("version", `Int version) :: members) in
  (* [~std:true] rules out the yojson-specific extensions: what is written here must be
     ordinary JSON, readable by jq, python or a linter. *)
  (Yojson.Safe.pretty_to_string ~std:true json) ^ "\n"
;;

let of_text ~(format:string) ~(version:int) ~(decode:(string -> Yojson.Safe.t) -> 'a) (text:string) =
  try
    match Yojson.Safe.from_string text with
    | `Assoc fields ->
        let member = member_of ~where:"the toplevel object" fields in
        let () =
          match member "format" with
          | `String f when (f = format) -> ()
          | `String f -> fail "unexpected format \"%s\" (expecting \"%s\")" f format
          | j -> fail "\"format\" should be a string, found %s" (kind_of j)
        in
        let () =
          match member "version" with
          | `Int v when (v = version) -> ()
          | `Int v -> fail "unsupported version %d (this binary understands %d)" v version
          | j -> fail "\"version\" should be an integer, found %s" (kind_of j)
        in
        Ok (decode member)
    | j -> fail "expected an object, found %s" (kind_of j)
  with
  | Malformed msg         -> Error msg
  | Yojson.Json_error msg -> Error (Printf.sprintf "not a well-formed JSON text: %s" msg)
;;

let write_file ~(filename:string) (text:string) : unit =
  let channel = open_out filename in
  Fun.protect ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel text)
;;

let read_file (filename:string) : (string, string) result =
  try
    let channel = open_in_bin filename in
    Ok (Fun.protect ~finally:(fun () -> close_in_noerr channel)
          (fun () -> really_input_string channel (in_channel_length channel)))
  with
  | Sys_error msg -> Error msg
  | End_of_file   -> Error (Printf.sprintf "%s: unexpected end of file" filename)
;;
