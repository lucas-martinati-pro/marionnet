(* This file is part of ocamlbricks
   Copyright (C) 2010 Jean-Vincent Loddo

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

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

IFNDEF OCAML4_04_OR_LATER THEN
let lowercase  = String.lowercase
let uppercase  = String.uppercase
let capitalize = String.capitalize
ELSE
let lowercase  = String.lowercase_ascii
let uppercase  = String.uppercase_ascii
let capitalize = String.capitalize_ascii
ENDIF

let make_dot_filter_by_format_and_description ~output_format_as_string ~description =
  let ext = output_format_as_string in
  let name = Printf.sprintf "%s (*.%s)" description ext in
  let patt1 = lowercase ext in
  let patt2 = uppercase ext in
  let patt3 = capitalize ext in
  let patterns = List.map (Printf.sprintf "*.%s") [patt1; patt2; patt3] in
  GFile.filter ~name ~patterns ()

let filter_of_format outfmt =
  let xyzw_list = Dot.working_output_formats ~no_file_inspection:() () in
  match ListExtra.search (fun (x,y,z,w) -> x=outfmt) xyzw_list with
  | None -> failwith "Dot_widget.filter_of_output_format"
  | Some (_, output_format_as_string, description, _) ->
      make_dot_filter_by_format_and_description
        ~output_format_as_string
        ~description

let filter_of_string ext =
  let outfmt = Dot.output_format_of_string ext in
  filter_of_format outfmt

let make_all_working_filters_assoc () =
  let xyzw_list = Dot.working_output_formats ~no_file_inspection:() () in
  List.map (fun (x,y,z,w) -> (x, make_dot_filter_by_format_and_description ~output_format_as_string:y ~description:z)) xyzw_list

let make_all_working_filters () =
  let xyzw_list = Dot.working_output_formats ~no_file_inspection:() () in
  List.map (fun (x,y,z,w) -> make_dot_filter_by_format_and_description ~output_format_as_string:y ~description:z) xyzw_list

let combo_of_working_output_formats
  ?(active:Dot.output_format option)
  ?add_tearoffs
  ?focus_on_click
  ?has_frame
  ?wrap_width
  ?width
  ?height
  ?packing
  ?show
  ()
  =
  let xs = Dot.working_output_formats ~no_file_inspection:() () in
  let xa = Array.of_list xs in
  let strings =
    List.map
      (fun (frm, str, des, fil) ->
         let x = StringExtra.make_wide str 10 in
         Printf.sprintf "<b><tt>%s</tt></b>%s" x des)
      xs
  in
  let active  = Option.bind active (fun act -> ListExtra.indexSuchThat (fun (frm,_,_,_) -> frm = act) xs) in
  let cb =
    GEdit.combo_box_text
      ~strings
      ~use_markup:true
      ?active
      ?add_tearoffs
      ?focus_on_click
      ?has_frame
      ?wrap_width
      ?width
      ?height
      ?packing
      ?show
      ()
  in
  let get_active_output_format () =
    let index = (fst cb)#active in
    let (x,_,_,_) = xa.(index) in x
  in
  ((fst cb), get_active_output_format)
