(* This file is part of ocamlbricks
   Copyright (C) 2012  Jean-Vincent Loddo

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

(** High-level impure but cool API for the standard module [Arg]. *)

(** List of available registering functions with their codomain:

{[val register_usage_msg : string -> unit
val register_h_option_as_help : unit -> unit

val register_unit_option      : .. -> unit option ref
val register_bool_option      : .. -> bool option ref
val register_string_option    : .. -> string option ref
val register_filename_option  : .. -> string option ref
val register_directory_option : .. -> string option ref
val register_enum_option      : .. -> string option ref
val register_int_option       : .. -> int option ref
val register_float_option     : .. -> float option ref

val register_string_optional_argument : .. -> string option ref
val register_string_argument          : .. -> string ref
val register_string_list0_argument    : .. -> string list ref
val register_string_list1_argument    : .. -> string list ref

val register_bool_optional_argument   : .. -> ?default:bool option -> bool option ref
val register_bool_argument            : .. -> bool ref
val register_bool_list0_argument      : .. -> bool list ref
val register_bool_list1_argument      : .. -> bool list ref

val register_int_optional_argument    : .. -> int option ref
val register_int_argument             : .. -> int ref
val register_int_list0_argument       : .. -> int list ref
val register_int_list1_argument       : .. -> int list ref

val register_float_optional_argument  : .. -> float option ref
val register_float_argument           : .. -> float ref
val register_float_list0_argument     : .. -> float list ref
val register_float_list1_argument     : .. -> ?error_msg:error_msg -> float list ref

val register_filename_optional_argument : .. -> string option ref
val register_filename_argument          : .. -> string ref
val register_filename_list0_argument    : .. -> string list ref
val register_filename_list1_argument    : .. -> string list ref
]}

{b Example}:

{[(* Registering usage: *)
let () = Argv.register_usage_msg "Usage: myprogram [OPTIONS] LENGTH [FLAGS..] POWERS[POWERS..] FILE[FILES..]\nOptions:" ;;

(* Registering options: *)
let option_x : unit option ref = Argv.register_unit_option "x" ~doc:"very useful option -x" () ;;
let option_y : unit option ref = Argv.register_unit_option "y" () ;;
let option_z : bool option ref = Argv.register_bool_option "z" () ;;
let option_s = Argv.register_string_option "s" ~tests:[(((<>)"none"), "not none please for the option `-s'")] () ;;
let option_t = Argv.register_enum_option "t" ~admissible_args:["BLACK"; "WHITE"] ~doc:"very useful option -t" () ;;
let option_f = Argv.register_filename_option "f" ~w:() ~r:() ~b:() ~doc:"very useful option -f" () ;;
let option_d = Argv.register_directory_option "d" ~w:() ~doc:"very useful option -d" () ;;
let () = Argv.register_h_option_as_help () ;;

(* Registering arguments: *)
let length = Argv.register_float_argument () ;;
let flags  = Argv.register_bool_list0_argument () ;;
let powers = Argv.register_int_list1_argument () ;;
let files  = Argv.register_filename_list1_argument ~r:() ~f:() () ;;

let main =
  begin
    (* Parse the command line (Sys.argv). The program will exit if something goes wrong parsing the command line: *)
    Argv.parse ();
    (* At this point all involved references have been updated: *)
    let () =
      if !option_x = Some () then begin
        Printf.printf "Not so useful option. Exiting ;-)\n";
        exit 0;
      end
    in
    ...

  end
;;
]}

Now, for instance, at command line:

{[$ myprogram -x -y -z trued -s none 3.14 42 /etc/a[ln]*
myprogram: wrong argument `trued'; option `-z' expects a boolean.
Usage: myprogram [OPTIONS] LENGTH FLAGS.. POWERS[POWERS..] FILE[FILES..]
Options:
  -x        very useful option -x
  -y        undocumented
  -z BOOL   undocumented
  -s STRING undocumented
  -t {BLACK|WHITE}
            very useful option -t
  -f FILE   very useful option -f
  -d DIR    very useful option d
  -h        Display this list of options
  -help     Display this list of options
  --help    Display this list of options

(* end of example *)
]}
*)

type error_msg = string

val register_usage_msg : string -> unit

val tuning :
  ?no_error_location_parsing_arguments:unit ->
  ?no_usage_on_error_parsing_arguments:unit ->
  unit -> unit

(** {2 Options without argument} *)

val register_unit_option :
  string -> ?aliases:string list ->
  ?doc:string -> ?default:unit option -> ?toggle:unit ->
  unit -> unit option ref

(** {2 Options with argument} *)

val register_bool_option :
  string -> ?aliases:string list ->
  ?arg_name_in_help:string ->
  ?doc:string -> ?default:bool option ->
  unit -> bool option ref

val register_string_option :
  string -> ?aliases:string list ->
  ?tests:((string -> bool) * error_msg) list ->
  ?arg_name_in_help:string ->
  ?doc:string -> ?default:string option ->
  unit -> string option ref

val register_filename_option :
  string -> ?aliases:string list ->
  ?r:unit -> ?w:unit -> ?x:unit ->
  ?follow:unit -> ?f:unit -> ?d:unit -> ?c:unit -> ?b:unit -> ?h:unit -> ?p:unit -> ?socket:unit ->
  ?error_msg:string ->
  ?tests:((string -> bool) * error_msg) list ->
  ?arg_name_in_help:string ->
  ?doc:string -> ?default:string option ->
  unit -> string option ref

val register_directory_option :
  string -> ?aliases:string list ->
  ?r:unit -> ?w:unit -> ?x:unit ->
  ?error_msg:string ->
  ?tests:((string -> bool) * error_msg) list ->
  ?arg_name_in_help:string ->
  ?doc:string -> ?default:string option ->
  unit -> string option ref

val register_enum_option :
  string -> ?aliases:string list ->
  admissible_args:string list ->
  ?doc:string -> ?default:string option ->
  unit -> string option ref

val register_int_option :
  string -> ?aliases:string list ->
  ?tests:((int -> bool) * error_msg) list ->
  ?arg_name_in_help:string ->
  ?doc:string -> ?default:int option ->
  unit -> int option ref

val register_float_option :
  string -> ?aliases:string list ->
  ?tests:((float -> bool) * error_msg) list ->
  ?arg_name_in_help:string ->
  ?doc:string -> ?default:float option ->
  unit -> float option ref

val register_h_option_as_help : unit -> unit

(** {2 String arguments } *)

val register_string_optional_argument :
  ?tests:((string -> bool) * error_msg) list ->
  ?default:string option ->
  unit -> string option ref

val register_string_argument :
  ?tests:((string -> bool) * error_msg) list ->
  ?error_msg:error_msg ->
  unit -> string ref

val register_string_list0_argument :
  ?tests:((string -> bool) * error_msg) list ->
  unit -> string list ref

val register_string_list1_argument :
  ?tests:((string -> bool) * error_msg) list ->
  ?error_msg:error_msg ->
  unit -> string list ref

(** {2 Bool arguments } *)

val register_bool_optional_argument :
  ?default:bool option ->
  unit -> bool option ref

val register_bool_argument       :
  ?error_msg:error_msg ->
  unit -> bool ref

val register_bool_list0_argument :
  unit -> bool list ref

val register_bool_list1_argument :
  ?error_msg:error_msg ->
  unit -> bool list ref

(** {2 Int arguments } *)

val register_int_optional_argument :
  ?tests:((int -> bool) * error_msg) list ->
  ?default:int option ->
  unit -> int option ref

val register_int_argument :
  ?tests:((int -> bool) * error_msg) list ->
  ?error_msg:error_msg ->
  unit -> int ref

val register_int_list0_argument :
  ?tests:((int -> bool) * error_msg) list ->
  unit -> int list ref

val register_int_list1_argument :
  ?tests:((int -> bool) * error_msg) list ->
  ?error_msg:error_msg ->
  unit -> int list ref

(** {2 Float arguments } *)

val register_float_optional_argument :
  ?tests:((float -> bool) * error_msg) list ->
  ?default:float option ->
  unit -> float option ref

val register_float_argument :
  ?tests:((float -> bool) * error_msg) list ->
  ?error_msg:error_msg ->
  unit -> float ref

val register_float_list0_argument :
  ?tests:((float -> bool) * error_msg) list ->
  unit -> float list ref

val register_float_list1_argument :
  ?tests:((float -> bool) * error_msg) list ->
  ?error_msg:error_msg -> unit -> float list ref

(** {2 Filename arguments } *)

val register_filename_optional_argument :
  ?r:unit -> ?w:unit -> ?x:unit ->
  ?follow:unit -> ?f:unit -> ?d:unit -> ?c:unit -> ?b:unit -> ?h:unit -> ?p:unit -> ?socket:unit ->
  ?error_msg:string ->
  ?tests:((string -> bool) * error_msg) list ->
  ?default:string option ->
  unit -> string option ref

val register_filename_argument :
  ?r:unit -> ?w:unit -> ?x:unit ->
  ?follow:unit -> ?f:unit -> ?d:unit -> ?c:unit -> ?b:unit -> ?h:unit -> ?p:unit -> ?socket:unit ->
  ?error_msg:string ->
  ?tests:((string -> bool) * error_msg) list ->
  unit -> string ref

val register_filename_list0_argument :
  ?r:unit -> ?w:unit -> ?x:unit ->
  ?follow:unit -> ?f:unit -> ?d:unit -> ?c:unit -> ?b:unit -> ?h:unit -> ?p:unit -> ?socket:unit ->
  ?error_msg:string ->
  ?tests:((string -> bool) * error_msg) list ->
  unit -> string list ref

val register_filename_list1_argument :
  ?r:unit -> ?w:unit -> ?x:unit ->
  ?follow:unit -> ?f:unit -> ?d:unit -> ?c:unit -> ?b:unit -> ?h:unit -> ?p:unit -> ?socket:unit ->
  ?error_msg:string ->
  ?tests:((string -> bool) * error_msg) list ->
  unit -> string list ref

(** {2 Parsing functions } *)

val parse_argv : string array -> unit
val parse : ?exit_with_errno:int -> unit -> unit

