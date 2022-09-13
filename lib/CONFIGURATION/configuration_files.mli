(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2008  Luca Saiu
   Copyright (C) 2012  Jean-Vincent Loddo
   Copyright (C) 2008 2012  Université Paris 13

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

(** Simple implementation of application-wise configuration files, implemented as shell scripts.
    Configuration files are looked for (by default) in "standard" places like /etc,
    the user's home directory and the shell environment.
    There is a priority:
    - System-wise files in /etc
    - User's files in ~
    - The shell environment at application startup time.
*)

(** {b Examples}:
{[
let t = Configuration_files.make ~file_names:["/etc/os-release"] ~variables:["NAME";"VERSION";"ID"] () ;;
val t : Configuration_files.t = <abstr>

let name = Configuration_files.get_string_variable "NAME" t ;;
val name : string option = Some "Ubuntu"

let version = Configuration_files.extract_string_variable_or ~default:"none" "VERSION" t ;;
val version : string = "12.04.1 LTS, Precise Pangolin"

let version = Configuration_files.extract_string_list_variable_or ~default:[] "VERSION" t ;;
val version : string list = ["12.04.1"; "LTS,"; "Precise"; "Pangolin"]

let version = Configuration_files.Logging.extract_string_list_variable_or ~default:[] "VERSION" t ;;
[18821.0]: Searching for variable VERSION:
[18821.0]:  - found value "12.04.1 LTS, Precise Pangolin"
val version : string list = ["12.04.1"; "LTS,"; "Precise"; "Pangolin"]

let foobar = Configuration_files.Logging.extract_string_list_variable_or ~default:[] "FOOBAR" t ;;
Exception: Invalid_argument "Configuration_files: Unexpected variable name `FOOBAR'".

let foobar = Configuration_files.Logging.extract_string_list_variable_or ~ignore_undeclared:() ~default:[] "FOOBAR" t ;;
[18407.0]: Searching for variable FOOBAR:                                                                                                            [18407.0]: Warning: FOOBAR not declared.                                                                                                             [18407.0]:  - using default ""
val foobar : string list = []
]}
*)

(** The abstract data type representing a configuration, make by reading file(s). *)
type t

type varname = string

val make :
  ?software_name:string ->
  ?file_names:string list ->
  variables:varname list ->
  ?dont_read_environment:unit ->
  unit -> t

(** The type of functions looking in the structure for a variable and
    returning an optional result: *)
type 'a get_variable =
  ?k:('a -> 'a option) ->            (** An optional continuation (called with Option.bind) *)
  ?ignore_undeclared:unit ->         (** Do not fail when undeclared *)
  ?unsuitable_value:('a -> bool) ->  (** Filter unsuitable values *)
  varname ->                         (** The name of the variable *)
  t -> 'a option

(** The type of functions looking in the structure for a variable and
    returning the value found or a default: *)
type 'a extract_variable_or =
  ?k:('a -> 'a) ->                   (** An optional continuation *)
  ?ignore_undeclared:unit ->         (** Do not fail when undeclared *)
  ?unsuitable_value:('a -> bool) ->  (** Filter unsuitable values *)
  default:'a ->                      (** The default value, if the variable is undeclared or its value unsuitable *)
  varname ->                         (** The name of the variable *)
  t -> 'a

val get_bool_variable               : bool   get_variable
val get_float_variable              : float  get_variable
val get_int_variable                : int    get_variable
val get_string_variable             : string get_variable
val get_string_list_variable        : (string list) get_variable

val extract_bool_variable_or        : bool   extract_variable_or
val extract_float_variable_or       : float  extract_variable_or
val extract_int_variable_or         : int    extract_variable_or
val extract_string_variable_or      : string extract_variable_or
val extract_string_list_variable_or : (string list) extract_variable_or

(* With source: *)
type source = [ `Filename of string | `Environment ] 
(* --- *)
module With_source : sig
  val get_bool_variable               : (bool * source) get_variable
  val get_float_variable              : (float * source) get_variable
  val get_int_variable                : (int * source) get_variable
  val get_string_variable             : (string * source) get_variable
  val get_string_list_variable        : ((string list) * source) get_variable
end


(** Versions with logging features: *)
module Logging : sig

  (** The type of (logged) functions looking in the structure for a variable and returning an optional result: *)
  type 'a get_variable =
    ?k:('a -> 'a option) ->                             (** An optional continuation (called with Option.bind) *)
    ?log_printf:(string -> unit) Log_builder.printf ->  (** An optional Log.printf *)
    ?ignore_undeclared:unit ->                          (** Do not fail, just warning if `log_printf' is provided *)
    ?unsuitable_value:('a -> bool) ->                   (** Filter unsuitable values *)
    varname ->                                          (** The name of the variable *)
    t -> 'a option

  (** The type of (logged) functions looking in the structure for a variable and returning the value found or a default: *)
  type 'a extract_variable_or =
    ?k:('a -> 'a) ->                                    (** An optional continuation *)
    ?log_printf:(string -> unit) Log_builder.printf ->  (** An optional Log.printf *)
    ?ignore_undeclared:unit ->                          (** Do not fail, just warning if `log_printf' is provided *)
    ?unsuitable_value:('a -> bool) ->                   (** Filter unsuitable values *)
    default:'a ->                                       (** The default value, if the variable is undeclared or its value unsuitable *)
    varname ->                                          (** The name of the variable *)
    t -> 'a

  val get_bool_variable               : bool   get_variable
  val get_float_variable              : float  get_variable
  val get_int_variable                : int    get_variable
  val get_string_variable             : string get_variable
  val get_string_list_variable        : (string list) get_variable

  val extract_bool_variable_or        : bool   extract_variable_or
  val extract_float_variable_or       : float  extract_variable_or
  val extract_int_variable_or         : int    extract_variable_or
  val extract_string_variable_or      : string extract_variable_or
  val extract_string_list_variable_or : (string list) extract_variable_or

end (* Logging *)

