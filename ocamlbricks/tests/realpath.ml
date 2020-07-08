(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2020  Jean-Vincent Loddo
   Copyright (C) 2020  Université Sorbonne Paris Nord

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


(* The binary code of this source will be generated with
   the following setting in Makefile.local:
   ---
   NATIVE_PROGRAMS += realpath.native
   ---
   The generated file should be "_build/tests/realpath.native"
*)

(* --------------------------------------- *)
(*              Parse argv                 *)
(* --------------------------------------- *)

let () = Argv.register_usage_msg (Printf.sprintf "Usage: %s FILE" (Filename.basename Sys.argv.(0)))
let () = Argv.register_h_option_as_help ()
(* --- *)
let file  = Argv.register_string_argument ()
(* --- *)
let () = Argv.tuning ~no_error_location_parsing_arguments:() ~no_usage_on_error_parsing_arguments:() ()
let () = Argv.parse ()

(* --------------------------------------- *)
(*                 Main                    *)
(* --------------------------------------- *)

match UnixExtra.realpath_exists !file with
| None -> exit 2
| Some x -> Printf.printf "%s\n" x

(* --------------------------------------- *)
(*            Test with Bash               *)
(* --------------------------------------- *)
(*
function g1 { find /etc | while read z; do [[ -e "$z" ]]  &&   realpath "$z"; done > /tmp/etc.1; }
function g2 { find /etc | while read z; do _build/tests/realpath.native "$z"; done > /tmp/etc.2; }
g1; g2;
diff /tmp/etc.1 /tmp/etc.2 && echo "SAME RESULT"
SAME RESULT
*)


