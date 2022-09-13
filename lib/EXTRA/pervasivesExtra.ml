(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Luca Saiu

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

(* Authors:
 * - Luca Saiu: initial version
 * - Jean-Vincent Loddo: functors for printers
 *)

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

IFNDEF OCAML4_02_OR_LATER THEN
module Bytes = struct  include String  let to_string x = x  let of_string x = x  end
type bytes = string
ENDIF

type filename = string
type length = int

(** Round the float. By default the number of decimals is set to 3. *)
let round ?(decimals=3) =
  let k = 10. ** (float_of_int decimals) in
  fun x-> (floor (x *. k +. 0.5)) /. k

(** Multiply by [100.] then round. For instance, [percentage ~decimals:1 0.896531] returns [89.7]. *)
let percentage ?(decimals=0) x =
  round ~decimals (x *. 100.)

(** Convert the two integers into floats, divide them, multiply by [100.] and finally round.
    For instance, [percentage_fraction ~decimals:2 711 1013] returns [70.19]. *)
let percentage_fraction ?decimals x y =
  percentage ?decimals ((float_of_int x) /. (float_of_int y))

(** For-based folder using float numbers. *)
let for_float ?backward ~min ~max ~step f acc =
  let tollerance = step /. 2. in
  match backward with
  | None ->
      let max = max +. tollerance in
      let rec loop acc x =
	if x > max then acc else loop (f acc x) (x+.step)
      in
      loop acc min
  | Some () ->
      let min = min -. tollerance in
      let rec loop acc x =
	if x < min then acc else loop (f acc x) (x-.step)
      in
      loop acc min


let for_float ?break ?backward ~min ~max ~step f acc =
  let tollerance = step /. 2. in
  match backward, break with
  | None, None ->
      let max = max +. tollerance in
      let rec loop acc x =
	if x > max then acc else loop (f acc x) (x+.step)
      in
      loop acc min
  | None, Some break ->
      let max = max +. tollerance in
      let rec loop acc x =
	if x > max || (break acc x) then acc else loop (f acc x) (x+.step)
      in
      loop acc min
  | Some (), None ->
      let min = min -. tollerance in
      let rec loop acc x =
	if x < min then acc else loop (f acc x) (x-.step)
      in
      loop acc min
  | Some (), Some break ->
      let min = min -. tollerance in
      let rec loop acc x =
	if x < min || (break acc x) then acc else loop (f acc x) (x-.step)
      in
      loop acc min


(** For-based folder using int numbers. *)
let for_int ?break ?backward ?(step=1) ~min ~max f acc =
  match backward, break with
  | None, None ->
      let rec loop acc x =
	if x > max then acc else loop (f acc x) (x+step)
      in
      loop acc min
  | None, Some break ->
      let rec loop acc x =
	if x > max || (break acc x) then acc else loop (f acc x) (x+step)
      in
      loop acc min
  | Some (), None ->
      let rec loop acc x =
	if x < min then acc else loop (f acc x) (x-step)
      in
      loop acc min
  | Some (), Some break ->
      let rec loop acc x =
	if x < min || (break acc x) then acc else loop (f acc x) (x-step)
      in
      loop acc min


let get_first_line_of_file filename =
  try
    let ch = open_in filename in
    let line = input_line ch in
    let () = close_in ch in
    Some line
  with _ -> None


let get_first_lines_of_file filename n =
  try
    let ch = open_in filename in
    let rec loop k acc =
      if k=0 then List.rev acc else
      try
        let line = input_line ch in
        loop (k-1) (line::acc)
      with _ -> List.rev acc
    in
    let result = loop n [] in
    let () = close_in ch in
    result
  with _ -> []

let get_first_chars_of_file filename n =
  try
    let ch = open_in filename in
    let rec loop k acc =
      if k=0 then List.rev acc else
      try
        let line = input_char ch in
        loop (k-1) (line::acc)
      with _ -> List.rev acc
    in
    let result = loop n [] in
    let () = close_in ch in
    result
  with _ -> []


let with_open_in ~filename mtdh =
  let in_channel = open_in filename in
  let length = in_channel_length (in_channel) in
  let result = mtdh in_channel length in
  close_in in_channel;
  result

let with_open_in_bin ~filename mtdh =
  let in_channel = open_in_bin filename in
  let length = in_channel_length (in_channel) in
  let result = mtdh in_channel length in
  close_in in_channel;
  result

let with_open_out ?(perm=0o644) ~filename mtdh =
  let file_exists = Sys.file_exists filename in
  let out_channel = open_out filename in
  let result = mtdh out_channel in
  close_out out_channel;
  if not file_exists then Unix.chmod filename perm else ();
  result

let with_open_out_bin ?(perm=0o644) ~filename mtdh =
  let file_exists = Sys.file_exists filename in
  let out_channel = open_out_gen [Open_wronly; Open_creat; Open_trunc; Open_binary] 0 filename in
  let result = mtdh out_channel in
  close_out out_channel;
  if not file_exists then Unix.chmod filename perm else ();
  result

let get_file_content ~filename =
  with_open_in_bin ~filename
    (fun in_channel length ->
       let s = Bytes.create length in
       really_input in_channel s 0 length;
       Bytes.to_string s)

let put_file_content ?perm ~filename content =
  with_open_out_bin ?perm ~filename
    (fun out_channel -> output_string out_channel content)


