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


