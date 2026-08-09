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

(* Tests for the JSON codecs of what a treeview saves - the rows ([bin/treeview_row.ml],
   section 4.2) and the counters of `ifconfig' ([bin/treeview_counters.ml], section 4.3) -,
   episode 3 of the `migration-marshal-to-text' work-stream. Run them with:

     dune test

   The same two invariants as for the xforest codec of episode 2 (see test/xforest_json.ml):

     1. what goes in comes out, including the *order* of the fields of a row and their
        duplicate keys, and including the [next_identifier] which travels with the rows;

     2. the emitted text is valid UTF-8 - checked with the independent validator of
        test/utf_8_reference.ml, never with the predicate the codec itself uses. Rows do
        carry arbitrary bytes: a comment typed in a guest, a filename in a locale nobody
        remembers.

   And one which belongs to this episode: a decoding failure must be REPORTED. The path
   these codecs are written for swallows exceptions - [Treeview_ifconfig#load_counters] is
   wrapped in a [try ... with _ -> ()] - so a broken codec would show up as a project
   silently reopened with its fresh-address counters back to 1, handing out addresses
   already in use. The failures are therefore tested one by one, and the messages are
   checked to *name* what went wrong.

   These tests are pure: no file other than a temporary one, no network, no GUI - which is
   the whole reason [Row]/[Row_item] and these codecs live in the library `marionnet_base'
   rather than in the Gtk+ module [Treeview]. *)

module Forest = Ocamlbricks.Forest

module Row      = Treeview_row.Row
module Row_item = Treeview_row.Row_item
module Json     = Treeview_row.Json

(* --- Minimal test harness (same as the other test programs: no test framework here) --- *)

let failures = ref 0

let check ~name (condition : bool) (details : string) =
  if condition
    then Printf.printf "OK    %s\n%!" name
    else (incr failures; Printf.printf "FAIL  %s -- %s\n%!" name details)

let contains ~substring text =
  let n = String.length substring and m = String.length text in
  let rec loop i = (i + n <= m) && ((String.sub text i n = substring) || loop (i+1)) in
  loop 0

let is_valid_utf_8 = Utf_8_reference.is_valid

(* --- Helpers --- *)

type content = int * Row.t Forest.t   (* what a treeview saves: (next_identifier, rows) *)

let row_forest (rows : Row.t list) : Row.t Forest.t =
  Forest.of_treelist (List.map (fun row -> (row, Forest.empty)) rows)

let string_field name value = (name, Row_item.String value)
let icon_field   name value = (name, Row_item.Icon value)
let check_field  name value = (name, Row_item.CheckBox value)

(* A row as the treeviews of Marionnet really shape one: *)
let a_machine_row name =
  [ string_field "Name" name;
    icon_field   "Type" "machine";
    string_field "MAC address" "02:04:06:08:0a:0c";
    check_field  "Up" true ]

(* The two invariants, checked together on a given content: *)
let round_trip ~name (content : content) =
  let text = Json.to_JSON_string content in
  let () =
    check ~name:(name ^ " / output is valid UTF-8") (is_valid_utf_8 text)
      "the emitted text carries raw bytes, so it is not valid JSON for any other tool"
  in
  match Json.of_JSON_string text with
  | Error msg -> check ~name:(name ^ " / round-trip") false ("decoding failed: " ^ msg)
  | Ok content' ->
      check ~name:(name ^ " / round-trip") (content' = content)
        (Printf.sprintf "the decoded content differs from the original one; text was:\n%s" text)

let expect_error ~name ~substring (result : ('a, string) result) =
  match result with
  | Ok _ -> check ~name false "decoding succeeded, while it was expected to fail"
  | Error msg ->
      check ~name (contains ~substring msg)
        (Printf.sprintf "the message does not mention %S: %S" substring msg)

(* A well-formed treeview text, to be corrupted member by member below: *)
let wrap ?(format="marionnet/treeview") ?(version=3) ?(next_identifier="7") rows =
  Printf.sprintf
    "{\"format\": %S, \"version\": %d, \"next_identifier\": %s, \"rows\": [%s]}"
    format version next_identifier rows

(* -------------------------------------------------------------------------- *)
(* The instrument first                                                       *)
(* -------------------------------------------------------------------------- *)

(* A test whose own instrument is wrong proves nothing, and this instrument is precisely
   what makes the others discriminant (see the header): so it gets checked first. *)
let test_the_validator_itself () =
  let () =
    List.iter
      (fun s -> check ~name:(Printf.sprintf "validator accepts %S" s) (is_valid_utf_8 s) "")
      Utf_8_reference.valid_samples
  in
  List.iter
    (fun s -> check ~name:(Printf.sprintf "validator rejects %S" s) (not (is_valid_utf_8 s)) "")
    Utf_8_reference.invalid_samples

(* -------------------------------------------------------------------------- *)
(* Rows: round-trips                                                          *)
(* -------------------------------------------------------------------------- *)

let test_empty_treeview () =
  (* The treeview `texts' (documents) is empty in every project of the corpus: *)
  round_trip ~name:"empty treeview" (1, Forest.empty)

let test_the_three_kinds () =
  round_trip ~name:"the three kinds of item"
    (42, row_forest [ [ string_field "Name" "m1";
                        icon_field   "Type" "machine";
                        check_field  "Up" true;
                        check_field  "Down" false ] ])

let test_empty_row_and_empty_strings () =
  (* A row with no field, an empty field name, an empty value: all legal here. *)
  round_trip ~name:"empty row and empty strings"
    (0, row_forest [ []; [string_field "" ""]; [icon_field "Type" ""] ])

let test_next_identifier () =
  let content = (123456789, row_forest [a_machine_row "m1"]) in
  let () = round_trip ~name:"a large next_identifier" content in
  let text = Json.to_JSON_string content in
  check ~name:"next_identifier is a JSON number of its own"
    (contains ~substring:"\"next_identifier\": 123456789" text)
    (Printf.sprintf "not found in:\n%s" text)

let test_utf_8_values () =
  (* Accents, quotes, newlines, tabs, backslashes: all of them travel as ordinary JSON
     strings - the base64 fallback must NOT kick in here, or the format would stop being
     readable exactly where readability matters (a comment is written by a human): *)
  let value = "TP r\xc3\xa9seaux \"salle B\" \xe2\x82\xac\nligne 2\tfin\\" in
  let content = (2, row_forest [ [string_field "Comment" value] ]) in
  let () = round_trip ~name:"UTF-8, quotes, newlines" content in
  let text = Json.to_JSON_string content in
  check ~name:"UTF-8 values stay readable (no base64)"
    (not (contains ~substring:"b64" text))
    (Printf.sprintf "the base64 fallback was used for a perfectly valid UTF-8 value:\n%s" text)

let test_raw_bytes_in_a_value () =
  let value = "\x84\x95\xa6\xbd\x00\x08\xff\xfe comment" in
  let content = (2, row_forest [ [string_field "Comment" value] ]) in
  let () = round_trip ~name:"raw bytes in a string value" content in
  let text = Json.to_JSON_string content in
  check ~name:"raw bytes trigger the base64 fallback" (contains ~substring:"b64" text)
    (Printf.sprintf "raw bytes were written as a JSON string:\n%s" text)

let test_raw_bytes_in_a_field_name_and_in_an_icon () =
  (* Not expected in practice, but a hole there would produce an invalid file just the
     same - and the column headers of a treeview are translated strings: *)
  round_trip ~name:"raw bytes in a field name and in an icon"
    (3, row_forest [ [ ("Nom\xff", Row_item.String "m1");
                       icon_field "Type\x80" "machine\xfe" ] ])

let test_overlong_encoding_and_surrogate () =
  (* C0 80 (overlong NUL) and ED A0 80 (U+D800): forbidden by UTF-8, accepted by many
     naive validators, hence the stdlib decoder as the reference: *)
  let content = (4, row_forest [ [string_field "x" "\xc0\x80"; string_field "y" "\xed\xa0\x80"] ]) in
  let () = round_trip ~name:"overlong encoding and lone surrogate" content in
  let text = Json.to_JSON_string content in
  check ~name:"an overlong encoding and a surrogate are treated as raw bytes"
    (contains ~substring:"b64" text)
    (Printf.sprintf "one of them was accepted as valid UTF-8:\n%s" text)

let test_field_order_and_duplicates () =
  (* A row is an association list, not a map: a JSON object would silently reorder it and
     drop the second "x". The order is what the columns of the widget are read against. *)
  let row =
    [ string_field "Name" "m1"; icon_field "Type" "machine";
      string_field "x" "1"; string_field "x" "2" ]
  in
  let content = (5, row_forest [row]) in
  let () = round_trip ~name:"field order and duplicates" content in
  match Json.of_JSON_string (Json.to_JSON_string content) with
  | Error msg -> check ~name:"fields are read back in order" false msg
  | Ok (_, forest') ->
      let (row', _) = Forest.to_tree forest' in
      check ~name:"fields are read back in order, duplicates included" (row' = row)
        (Printf.sprintf "got { %s }"
           (String.concat "; "
              (List.map (fun (k,v) -> Printf.sprintf "%S=%s" k (Row_item.to_pretty_string v)) row')))

let test_deep_forest () =
  (* The shape of the treeview `states-forest': a machine, and under it the states of its
     disk, one of which has a state of its own. Three levels, several roots. *)
  let state name = ((a_machine_row name), Forest.empty) in
  let m1 =
    ( (a_machine_row "m1"),
      Forest.of_treelist
        [ ((a_machine_row "m1 state 1"), (Forest.of_treelist [state "m1 state 1.1"]));
          (state "m1 state 2") ] )
  in
  round_trip ~name:"deep forest with several roots"
    (6, Forest.of_treelist [m1; (state "m2"); (state "m3")])

let test_file_round_trip () =
  let content =
    (7, row_forest [ [ string_field "Name" "caf\xc3\xa9";
                       string_field "Comment" "\x84\x95\xa6\xbd\x01";
                       check_field "Up" false ] ])
  in
  let filename = Filename.temp_file "marionnet-test-treeview-" ".json" in
  let () = Json.to_JSON_file content filename in
  let () =
    match Json.of_JSON_file filename with
    | Error msg  -> check ~name:"file round-trip" false msg
    | Ok content' -> check ~name:"file round-trip" (content' = content) "the decoded content differs"
  in
  (* The text on disk ends with a newline, so that a project file behaves under diff and
     under the usual line-oriented tools: *)
  let () =
    let ic = open_in_bin filename in
    let text = really_input_string ic (in_channel_length ic) in
    let () = close_in ic in
    check ~name:"the file ends with a newline"
      ((String.length text > 0) && (text.[String.length text - 1] = '\n'))
      (Printf.sprintf "last bytes: %S"
         (String.sub text (max 0 (String.length text - 8)) (min 8 (String.length text))))
  in
  try Sys.remove filename with _ -> ()

(* -------------------------------------------------------------------------- *)
(* Rows: failures must be reported, never guessed away                        *)
(* -------------------------------------------------------------------------- *)

let test_ill_formed_json () =
  expect_error ~name:"ill-formed JSON is rejected" ~substring:"well-formed"
    (Json.of_JSON_string "{ \"format\": ")

let test_wrong_toplevel () =
  expect_error ~name:"a toplevel array is rejected" ~substring:"expected an object"
    (Json.of_JSON_string "[]")

let test_another_format () =
  (* The reason every one of these files carries a "format": the four treeviews, the two
     xforests and the counters are seven files in one archive, and a mixed-up name must be
     said out loud rather than decoded into nonsense - which is exactly what
     [Marshal.from_file] would do. *)
  expect_error ~name:"an xforest text is not accepted here" ~substring:"unexpected format"
    (Json.of_JSON_string
       "{\"format\": \"marionnet/xforest\", \"version\": 3, \"roots\": []}")

let test_future_version () =
  expect_error ~name:"a future version is rejected by name" ~substring:"unsupported version 4"
    (Json.of_JSON_string (wrap ~version:4 ""))

let test_missing_next_identifier () =
  expect_error ~name:"a missing next_identifier is reported"
    ~substring:"missing member \"next_identifier\""
    (Json.of_JSON_string
       "{\"format\": \"marionnet/treeview\", \"version\": 3, \"rows\": []}")

let test_next_identifier_as_a_string () =
  expect_error ~name:"a next_identifier written as a string is rejected"
    ~substring:"\"next_identifier\" should be an integer"
    (Json.of_JSON_string (wrap ~next_identifier:"\"7\"" ""))

let test_missing_children () =
  expect_error ~name:"a missing \"children\" is reported" ~substring:"missing member \"children\""
    (Json.of_JSON_string (wrap "{\"fields\": []}"))

let test_missing_fields () =
  expect_error ~name:"a missing \"fields\" is reported" ~substring:"missing member \"fields\""
    (Json.of_JSON_string (wrap "{\"children\": []}"))

let test_fields_as_an_object () =
  (* The mistake a well-meaning hand-editor would make: *)
  expect_error ~name:"\"fields\" as an object is rejected"
    ~substring:"expected \"fields\" as an array"
    (Json.of_JSON_string (wrap "{\"fields\": {\"Name\": \"m1\"}, \"children\": []}"))

let test_bad_field_shape () =
  expect_error ~name:"a field of three elements is rejected" ~substring:"[name, value] pair"
    (Json.of_JSON_string
       (wrap "{\"fields\": [[\"Name\", {\"kind\": \"string\", \"value\": \"m1\"}, 1]], \
                \"children\": []}"))

let test_unknown_kind () =
  (* Nothing is guessed: an unknown kind is a file this binary does not understand, and it
     is named as such. Falling back on a string would put a value of the wrong type in a
     column of the widget, which is how the defect B6 of the automate work-stream looked. *)
  expect_error ~name:"an unknown item kind is rejected by name"
    ~substring:"unknown field kind \"colour\""
    (Json.of_JSON_string
       (wrap "{\"fields\": [[\"Name\", {\"kind\": \"colour\", \"value\": \"red\"}]], \
                \"children\": []}"))

let test_missing_value () =
  expect_error ~name:"a missing \"value\" is reported" ~substring:"missing member \"value\""
    (Json.of_JSON_string
       (wrap "{\"fields\": [[\"Up\", {\"kind\": \"checkbox\"}]], \"children\": []}"))

let test_checkbox_not_a_boolean () =
  expect_error ~name:"a checkbox whose value is a string is rejected"
    ~substring:"a checkbox value should be a boolean"
    (Json.of_JSON_string
       (wrap "{\"fields\": [[\"Up\", {\"kind\": \"checkbox\", \"value\": \"true\"}]], \
                \"children\": []}"))

let test_string_kind_with_a_boolean_value () =
  expect_error ~name:"a string item whose value is a boolean is rejected"
    ~substring:"a string value: expected a string"
    (Json.of_JSON_string
       (wrap "{\"fields\": [[\"Name\", {\"kind\": \"string\", \"value\": true}]], \
                \"children\": []}"))

let test_invalid_base64 () =
  expect_error ~name:"invalid base64 content is reported" ~substring:"invalid base64"
    (Json.of_JSON_string
       (wrap "{\"fields\": [[\"Name\", {\"kind\": \"string\", \"value\": {\"b64\": \"!!!\"}}]], \
                \"children\": []}"))

let test_missing_file () =
  expect_error ~name:"a missing file is reported as an error value" ~substring:"No such file"
    (Json.of_JSON_file "/nonexistent/marionnet/ifconfig.json")

(* -------------------------------------------------------------------------- *)
(* The counters of `ifconfig'                                                 *)
(* -------------------------------------------------------------------------- *)

let counters_round_trip ~name (counters : Treeview_counters.t) =
  let text = Treeview_counters.to_JSON_string counters in
  let () =
    check ~name:(name ^ " / output is valid UTF-8") (is_valid_utf_8 text)
      "the emitted text is not valid UTF-8"
  in
  match Treeview_counters.of_JSON_string text with
  | Error msg -> check ~name:(name ^ " / round-trip") false ("decoding failed: " ^ msg)
  | Ok counters' ->
      check ~name:(name ^ " / round-trip") (counters' = counters)
        (Printf.sprintf "the decoded counters differ; text was:\n%s" text)

let test_counters () =
  let () = counters_round_trip ~name:"counters, initial state" (0, 1, Int64.one) in
  let () = counters_round_trip ~name:"counters, a used project" (12345678, 42, 4711L) in
  (* An Int64 is exactly what a JSON number cannot carry: beyond 2^53 a reader using IEEE
     754 doubles - which is every JSON reader as far as the format is concerned - loses
     the low bits. Hence the string, and hence these two values at the bounds: *)
  let () = counters_round_trip ~name:"counters, Int64.max_int" (1, 1, Int64.max_int) in
  counters_round_trip ~name:"counters, a negative Int64" (1, 1, Int64.minus_one)

let test_counters_ipv6_travels_as_a_string () =
  let text = Treeview_counters.to_JSON_string (7, 8, 9223372036854775807L) in
  let () =
    check ~name:"the IPv6 counter is written as a JSON string"
      (contains ~substring:"\"next_ipv6_address_as_int\": \"9223372036854775807\"" text)
      (Printf.sprintf "not found in:\n%s" text)
  in
  (* ...and only as a string: reading a JSON number too would make a reread depend on
     which of the two forms a writer happened to choose. *)
  expect_error ~name:"the IPv6 counter written as a number is rejected"
    ~substring:"should be a string holding a 64 bit integer"
    (Treeview_counters.of_JSON_string
       "{\"format\": \"marionnet/ifconfig-counters\", \"version\": 3, \
         \"obsolete_mac_address_as_int\": 1, \"next_ipv4_address_as_int\": 1, \
         \"next_ipv6_address_as_int\": 1}")

let test_counters_failures () =
  let () =
    expect_error ~name:"an unparsable 64 bit integer is reported" ~substring:"not a 64 bit integer"
      (Treeview_counters.of_JSON_string
         "{\"format\": \"marionnet/ifconfig-counters\", \"version\": 3, \
           \"obsolete_mac_address_as_int\": 1, \"next_ipv4_address_as_int\": 1, \
           \"next_ipv6_address_as_int\": \"twelve\"}")
  in
  let () =
    expect_error ~name:"a missing counter is reported"
      ~substring:"missing member \"next_ipv4_address_as_int\""
      (Treeview_counters.of_JSON_string
         "{\"format\": \"marionnet/ifconfig-counters\", \"version\": 3, \
           \"obsolete_mac_address_as_int\": 1, \"next_ipv6_address_as_int\": \"1\"}")
  in
  let () =
    (* The counters file sits next to the rows file, and both are read on the same path: *)
    expect_error ~name:"a treeview text is not accepted as counters" ~substring:"unexpected format"
      (Treeview_counters.of_JSON_string (wrap ""))
  in
  let () =
    expect_error ~name:"a future version of the counters is rejected by name"
      ~substring:"unsupported version 4"
      (Treeview_counters.of_JSON_string
         "{\"format\": \"marionnet/ifconfig-counters\", \"version\": 4}")
  in
  expect_error ~name:"a missing counters file is reported as an error value"
    ~substring:"No such file"
    (Treeview_counters.of_JSON_file "/nonexistent/marionnet/ifconfig-counters.json")

let test_counters_file_round_trip () =
  let counters = (12345678, 17, 1234567890123456789L) in
  let filename = Filename.temp_file "marionnet-test-counters-" ".json" in
  let () = Treeview_counters.to_JSON_file counters filename in
  let () =
    match Treeview_counters.of_JSON_file filename with
    | Error msg    -> check ~name:"counters file round-trip" false msg
    | Ok counters' ->
        check ~name:"counters file round-trip" (counters' = counters) "the decoded counters differ"
  in
  try Sys.remove filename with _ -> ()

(* -------------------------------------------------------------------------- *)

let () =
  let () =
    Printf.printf
      "Testing the JSON codecs of a treeview and of its counters (episode 3)\n%!"
  in
  let () = test_the_validator_itself () in
  let () = test_empty_treeview () in
  let () = test_the_three_kinds () in
  let () = test_empty_row_and_empty_strings () in
  let () = test_next_identifier () in
  let () = test_utf_8_values () in
  let () = test_raw_bytes_in_a_value () in
  let () = test_raw_bytes_in_a_field_name_and_in_an_icon () in
  let () = test_overlong_encoding_and_surrogate () in
  let () = test_field_order_and_duplicates () in
  let () = test_deep_forest () in
  let () = test_file_round_trip () in
  let () = test_ill_formed_json () in
  let () = test_wrong_toplevel () in
  let () = test_another_format () in
  let () = test_future_version () in
  let () = test_missing_next_identifier () in
  let () = test_next_identifier_as_a_string () in
  let () = test_missing_children () in
  let () = test_missing_fields () in
  let () = test_fields_as_an_object () in
  let () = test_bad_field_shape () in
  let () = test_unknown_kind () in
  let () = test_missing_value () in
  let () = test_checkbox_not_a_boolean () in
  let () = test_string_kind_with_a_boolean_value () in
  let () = test_invalid_base64 () in
  let () = test_missing_file () in
  let () = test_counters () in
  let () = test_counters_ipv6_travels_as_a_string () in
  let () = test_counters_failures () in
  let () = test_counters_file_round_trip () in
  let () = Printf.printf "%d failure(s)\n%!" !failures in
  exit (if !failures = 0 then 0 else 1)
