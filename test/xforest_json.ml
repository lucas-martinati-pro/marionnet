(* This file is part of Marionnet

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

(* Round-trip tests for the JSON codec of [lib/STRUCTURES/xforest.ml], episode 2 of the
   `migration-marshal-to-text' work-stream (see docs/migration-marshal-to-text.md,
   section 4.1). Run them with:

     dune test

   Two invariants are checked here, and the second one is the reason the codec is not
   simply `Yojson.Safe.to_string':

     1. what goes in comes out, byte for byte, including the *order* of the attributes
        and their duplicate keys - the OCaml type is an association list, not a map;

     2. the text produced is always valid UTF-8, hence a candidate for being valid JSON.
        Yojson writes raw bytes verbatim and rereads them faithfully, so a codec without
        the base64 fallback would pass invariant 1 while emitting files that no other
        tool - jq, python, a JSON linter - can read. Invariant 2 is what actually fails
        without the fallback, which makes these tests discriminant.

   These tests are pure: no file other than a temporary one, no network, no GUI. *)

module Xforest = Ocamlbricks.Xforest
module Forest  = Ocamlbricks.Forest

(* --- Minimal test harness (same as test/marionnet.ml: no test framework here) --- *)

let failures = ref 0

let check ~name (condition : bool) (details : string) =
  if condition
    then Printf.printf "OK    %s\n%!" name
    else (incr failures; Printf.printf "FAIL  %s -- %s\n%!" name details)

(* --- Helpers --- *)

let leaf tag attrs : Xforest.t = Forest.of_tree ((tag, attrs), Forest.empty)

let tree (node : Xforest.node) (children : Xforest.t) : Xforest.tree = (node, children)

let contains ~substring text =
  let n = String.length substring and m = String.length text in
  let rec loop i = (i + n <= m) && ((String.sub text i n = substring) || loop (i+1)) in
  loop 0

(* A UTF-8 validator written here on purpose, rather than the one the codec uses to
   decide whether a string needs the base64 fallback: checking the output of a codec with
   the very predicate that drives it would be circular - a wrong predicate would make
   both the codec and its test wrong, in agreement. This one decodes by hand, and rejects
   what a naive check usually accepts: overlong encodings, surrogates (U+D800..U+DFFF)
   and anything beyond U+10FFFF. *)
let is_valid_utf_8 (s : string) : bool =
  let n = String.length s in
  let byte i = Char.code s.[i] in
  let continuation i = (i < n) && ((byte i) land 0xC0 = 0x80) in
  let rec loop i =
    if i >= n then true else
    let b = byte i in
    if b < 0x80 then loop (i+1)
    else if b land 0xE0 = 0xC0 then
      (continuation (i+1)) &&
      (let cp = ((b land 0x1F) lsl 6) lor ((byte (i+1)) land 0x3F) in
       (cp >= 0x80) && (loop (i+2)))
    else if b land 0xF0 = 0xE0 then
      (continuation (i+1)) && (continuation (i+2)) &&
      (let cp = ((b land 0x0F) lsl 12) lor (((byte (i+1)) land 0x3F) lsl 6)
                lor ((byte (i+2)) land 0x3F) in
       (cp >= 0x800) && (not ((cp >= 0xD800) && (cp <= 0xDFFF))) && (loop (i+3)))
    else if b land 0xF8 = 0xF0 then
      (continuation (i+1)) && (continuation (i+2)) && (continuation (i+3)) &&
      (let cp = ((b land 0x07) lsl 18) lor (((byte (i+1)) land 0x3F) lsl 12)
                lor (((byte (i+2)) land 0x3F) lsl 6) lor ((byte (i+3)) land 0x3F) in
       (cp >= 0x10000) && (cp <= 0x10FFFF) && (loop (i+4)))
    else false
  in
  loop 0

(* The two invariants above, checked together on a given forest: *)
let round_trip ~name (forest : Xforest.t) =
  let text = Xforest.to_JSON_string forest in
  let () =
    check ~name:(name ^ " / output is valid UTF-8") (is_valid_utf_8 text)
      "the emitted text carries raw bytes, so it is not valid JSON for any other tool"
  in
  match Xforest.of_JSON_string text with
  | Error msg -> check ~name:(name ^ " / round-trip") false ("decoding failed: " ^ msg)
  | Ok forest' ->
      check ~name:(name ^ " / round-trip") (forest' = forest)
        (Printf.sprintf "the decoded forest differs from the original one; text was:\n%s" text)

let expect_error ~name ~substring (result : (Xforest.t, string) result) =
  match result with
  | Ok _ -> check ~name false "decoding succeeded, while it was expected to fail"
  | Error msg ->
      check ~name (contains ~substring msg)
        (Printf.sprintf "the message does not mention %S: %S" substring msg)

(* -------------------------------------------------------------------------- *)
(* Round-trips                                                                 *)
(* -------------------------------------------------------------------------- *)

(* A test whose own instrument is wrong proves nothing, and this instrument is precisely
   what makes the others discriminant (see the header): so it gets checked first. *)
let test_the_validator_itself () =
  let valid   = [""; "abc"; "caf\xc3\xa9"; "\xe2\x82\xac"; "\xf0\x9f\x98\x80"; "\x00\x7f"] in
  let invalid = [ "\x80";                 (* a lone continuation byte              *)
                  "\xc3";                 (* truncated two-byte sequence           *)
                  "\xe2\x82";             (* truncated three-byte sequence         *)
                  "\xc0\x80";             (* overlong encoding of NUL              *)
                  "\xe0\x80\x80";         (* overlong encoding again               *)
                  "\xed\xa0\x80";         (* U+D800, a surrogate                   *)
                  "\xf5\x80\x80\x80";     (* beyond U+10FFFF                       *)
                  "\xff"; "\xfe" ]
  in
  let () =
    List.iter
      (fun s -> check ~name:(Printf.sprintf "validator accepts %S" s) (is_valid_utf_8 s) "")
      valid
  in
  List.iter
    (fun s -> check ~name:(Printf.sprintf "validator rejects %S" s) (not (is_valid_utf_8 s)) "")
    invalid

let test_empty_forest () =
  round_trip ~name:"empty forest" Forest.empty

let test_plain_values () =
  round_trip ~name:"plain values"
    (leaf "machine" [("name", "m1"); ("memory", "48"); ("distrib", "trixie")])

let test_empty_strings () =
  (* An empty tag, an empty attribute name and an empty value are all legal here: *)
  round_trip ~name:"empty strings" (leaf "" [("", ""); ("name", "")])

let test_no_attribute () =
  round_trip ~name:"no attribute at all" (leaf "network" [])

let test_utf_8_values () =
  (* Accents, quotes, newlines, tabs, backslashes: all of them travel as ordinary JSON
     strings - the base64 fallback must NOT kick in here, or the format would stop being
     readable exactly where readability matters: *)
  let value = "eth0 \"cafe\" caf\xc3\xa9 \xe2\x82\xac\nline2\tend\\" in
  let forest = leaf "machine" [("comment", value)] in
  let () = round_trip ~name:"UTF-8, quotes, newlines" forest in
  let text = Xforest.to_JSON_string forest in
  check ~name:"UTF-8 values stay readable (no base64)"
    (not (contains ~substring:"b64" text))
    (Printf.sprintf "the base64 fallback was used for a perfectly valid UTF-8 value:\n%s" text)

let test_raw_bytes_in_value () =
  (* The real case behind the fallback: the six attributes still marshalled inside the
     forest (rc_config, the four Quagga fields of a router) start with the Marshal magic
     number 0x8495A6BD, which is not valid UTF-8: *)
  let value = "\x84\x95\xa6\xbd\x00\x08\xff\xfe rc_config" in
  let forest = leaf "machine" [("rc_config", value)] in
  let () = round_trip ~name:"raw bytes in a value" forest in
  let text = Xforest.to_JSON_string forest in
  check ~name:"raw bytes trigger the base64 fallback" (contains ~substring:"b64" text)
    (Printf.sprintf "raw bytes were written as a JSON string:\n%s" text)

let test_raw_bytes_in_name_and_tag () =
  (* Not expected in practice, but the codec must not have a hole there either: an
     invalid tag or attribute name would produce an invalid file just the same. *)
  round_trip ~name:"raw bytes in a tag and in an attribute name"
    (leaf "tag\xff" [("name\x80", "value")])

let test_overlong_encoding () =
  (* C0 80 is the overlong encoding of NUL: forbidden by UTF-8, accepted by many naive
     validators. The stdlib decoder rejects it, so it must go through base64: *)
  let forest = leaf "machine" [("x", "\xc0\x80")] in
  let () = round_trip ~name:"overlong UTF-8 encoding" forest in
  let text = Xforest.to_JSON_string forest in
  check ~name:"an overlong encoding is treated as raw bytes" (contains ~substring:"b64" text)
    (Printf.sprintf "C0 80 was accepted as valid UTF-8:\n%s" text)

let test_lone_surrogate () =
  (* ED A0 80 encodes U+D800, a surrogate: also forbidden, also often accepted: *)
  let forest = leaf "machine" [("x", "\xed\xa0\x80")] in
  let () = round_trip ~name:"lone surrogate" forest in
  let text = Xforest.to_JSON_string forest in
  check ~name:"a surrogate is treated as raw bytes" (contains ~substring:"b64" text)
    (Printf.sprintf "ED A0 80 was accepted as valid UTF-8:\n%s" text)

let test_attribute_order_and_duplicates () =
  (* THE reason attributes are a JSON array of pairs and not a JSON object: writing
     `distrib' realigns `kernel' (episode 4f of the pilotage-par-script work-stream), so
     two orders do not give the same result; and a JSON object would silently drop the
     second `x'. *)
  let attrs = [("distrib", "trixie"); ("kernel", "6.12"); ("x", "1"); ("x", "2")] in
  let forest = leaf "machine" attrs in
  let () = round_trip ~name:"attribute order and duplicates" forest in
  match Xforest.of_JSON_string (Xforest.to_JSON_string forest) with
  | Error msg -> check ~name:"attributes are read back in order" false msg
  | Ok forest' ->
      let ((_, attrs'), _) = Forest.to_tree forest' in
      check ~name:"attributes are read back in order, duplicates included"
        (attrs' = attrs)
        (Printf.sprintf "got [%s]"
           (String.concat "; " (List.map (fun (k,v) -> Printf.sprintf "%S,%S" k v) attrs')))

let test_deep_forest () =
  let m1 = tree ("machine", [("name","m1")]) Forest.empty in
  let m2 = tree ("machine", [("name","m2")]) (Forest.of_treelist [m1]) in
  let sw = tree ("switch",  [("name","s1"); ("port_no","8")]) (Forest.of_treelist [m2; m1]) in
  let net = tree ("network", [("name","projet1")]) (Forest.of_treelist [sw; m1]) in
  round_trip ~name:"deep forest with several roots"
    (Forest.of_treelist [net; (tree ("cable", [("name","c1")]) Forest.empty)])

let test_file_round_trip () =
  let forest =
    Forest.of_treelist
      [ tree ("network", [("name", "caf\xc3\xa9"); ("rc_config", "\x84\x95\xa6\xbd\x01")])
          (Forest.of_treelist [tree ("machine", [("name","m1")]) Forest.empty]) ]
  in
  let filename = Filename.temp_file "marionnet-test-xforest-" ".json" in
  let () = Xforest.to_JSON_file forest filename in
  let () =
    match Xforest.of_JSON_file filename with
    | Error msg -> check ~name:"file round-trip" false msg
    | Ok forest' -> check ~name:"file round-trip" (forest' = forest) "the decoded forest differs"
  in
  (* The text on disk ends with a newline, so that a project file behaves under diff and
     under the usual line-oriented tools: *)
  let () =
    let ic = open_in_bin filename in
    let text = really_input_string ic (in_channel_length ic) in
    let () = close_in ic in
    check ~name:"the file ends with a newline"
      ((String.length text > 0) && (text.[String.length text - 1] = '\n'))
      (Printf.sprintf "last bytes: %S" (String.sub text (max 0 (String.length text - 8)) (min 8 (String.length text))))
  in
  try Sys.remove filename with _ -> ()

(* -------------------------------------------------------------------------- *)
(* Failures: they must be reported, never guessed away                         *)
(* -------------------------------------------------------------------------- *)

let test_ill_formed_json () =
  expect_error ~name:"ill-formed JSON is rejected" ~substring:"well-formed"
    (Xforest.of_JSON_string "{ \"format\": ")

let test_wrong_toplevel () =
  expect_error ~name:"a toplevel array is rejected" ~substring:"expected an object"
    (Xforest.of_JSON_string "[]")

let test_unknown_format () =
  expect_error ~name:"an unknown format is rejected" ~substring:"unexpected format"
    (Xforest.of_JSON_string
       "{\"format\": \"marionnet/treeview\", \"version\": 3, \"roots\": []}")

let test_future_version () =
  (* The point of a self-describing format: a v4 file must be *named* as such, not
     dereferenced at random the way Marshal.from_file would: *)
  expect_error ~name:"a future version is rejected by name" ~substring:"unsupported version 4"
    (Xforest.of_JSON_string
       "{\"format\": \"marionnet/xforest\", \"version\": 4, \"roots\": []}")

let test_missing_member () =
  expect_error ~name:"a missing \"children\" is reported" ~substring:"missing member \"children\""
    (Xforest.of_JSON_string
       "{\"format\": \"marionnet/xforest\", \"version\": 3, \
         \"roots\": [{\"tag\": \"network\", \"attrs\": []}]}")

let test_attrs_as_an_object () =
  (* The mistake a well-meaning hand-editor would make: *)
  expect_error ~name:"\"attrs\" as an object is rejected" ~substring:"expected \"attrs\" as an array"
    (Xforest.of_JSON_string
       "{\"format\": \"marionnet/xforest\", \"version\": 3, \
         \"roots\": [{\"tag\": \"network\", \"attrs\": {\"name\": \"x\"}, \"children\": []}]}")

let test_bad_attribute_shape () =
  expect_error ~name:"an attribute of three elements is rejected" ~substring:"[name, value] pair"
    (Xforest.of_JSON_string
       "{\"format\": \"marionnet/xforest\", \"version\": 3, \
         \"roots\": [{\"tag\": \"t\", \"attrs\": [[\"a\",\"b\",\"c\"]], \"children\": []}]}")

let test_invalid_base64 () =
  expect_error ~name:"invalid base64 content is reported" ~substring:"invalid base64"
    (Xforest.of_JSON_string
       "{\"format\": \"marionnet/xforest\", \"version\": 3, \
         \"roots\": [{\"tag\": \"t\", \"attrs\": [[\"a\", {\"b64\": \"!!!\"}]], \"children\": []}]}")

let test_missing_file () =
  (* An unreadable file is an ordinary case, dealt with as a value, not as an exception: *)
  expect_error ~name:"a missing file is reported as an error value" ~substring:"No such file"
    (Xforest.of_JSON_file "/nonexistent/marionnet/xforest.json")

(* -------------------------------------------------------------------------- *)

let () =
  let () = Printf.printf "Testing the JSON codec of Ocamlbricks.Xforest (episode 2)\n%!" in
  let () = test_the_validator_itself () in
  let () = test_empty_forest () in
  let () = test_plain_values () in
  let () = test_empty_strings () in
  let () = test_no_attribute () in
  let () = test_utf_8_values () in
  let () = test_raw_bytes_in_value () in
  let () = test_raw_bytes_in_name_and_tag () in
  let () = test_overlong_encoding () in
  let () = test_lone_surrogate () in
  let () = test_attribute_order_and_duplicates () in
  let () = test_deep_forest () in
  let () = test_file_round_trip () in
  let () = test_ill_formed_json () in
  let () = test_wrong_toplevel () in
  let () = test_unknown_format () in
  let () = test_future_version () in
  let () = test_missing_member () in
  let () = test_attrs_as_an_object () in
  let () = test_bad_attribute_shape () in
  let () = test_invalid_base64 () in
  let () = test_missing_file () in
  let () = Printf.printf "%d failure(s)\n%!" !failures in
  exit (if !failures = 0 then 0 else 1)
