(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009  Jean-Vincent Loddo

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

(** Operations on type ['a option]. *)

type 'a t = 'a option

(** Extract the encapsulated value. If the argument is [None], the optional [?fallback] is called.
    By default [fallback] is set to [fun ()->failwith "Option.extract"].*)
val extract : ?failwith_msg:string -> ?fallback:(unit -> 'a) -> 'a option -> 'a
val extract_or : 'a option -> 'a -> 'a
val extract_or_force : 'a option -> 'a Lazy.t -> 'a
val extract_from_list : ?acc:'a list -> 'a option list -> 'a list
val extract_map_or : 'a option -> ('a -> 'b) -> 'b -> 'b

(* (update ~latter:x1 x0) returns x1 if it is defined (Some), else returns x0 *)
val update : ?latter:'a -> 'a option -> 'a option

val map    : ('a -> 'b) -> 'a option -> 'b option
val bind   : 'a option -> ('a -> 'b option) -> 'b option
val return : 'a -> 'a option
val map2   : ('a -> 'b -> 'c) -> 'a option -> 'b option -> 'c option
val bind2  : 'a option -> 'b option -> ('a -> 'b -> 'c option) -> 'c option
val join   : 'a option option -> 'a option

val map_binop  : ('a -> 'a -> 'a) -> 'a option -> 'a option -> 'a option

val iter  : ('a -> unit) -> 'a option -> unit
val iter2 : ('a -> 'b -> unit) -> 'a option -> 'b option -> unit

val filter : ('a -> bool) -> 'a option -> 'a option

val apply_or_catch : ?fallback:(exn -> 'a -> unit) -> ('a -> 'b) -> 'a -> 'b option
(* apply_or_catch simplified: *)
val protect  : ('a -> 'b) -> ('a -> 'b option)
val protect2 : ('a -> 'b -> 'c) -> ('a -> 'b -> 'c option)
val protect3 : ('a -> 'b -> 'c -> 'd) -> ('a -> 'b -> 'c -> 'd option)

(* Note that ~finally is itself protected by exceptions and its result is ignored. *)
val try_finalize : finally:('a -> (exn, 'b) Either.t -> 'ignored) -> ('a -> 'b) -> 'a -> 'b option

(* Find the first result that succeed (not None): *)
val find    : 'a list -> ('a -> 'b option) -> 'b option
val exists  : 'a list -> ('a -> 'b option) -> bool (* exists  xs f = ((find xs f) <> None) *)
val for_all : 'a list -> ('a -> 'b option) -> bool (* for_all xs f = not (exists xs (fun x -> not (f x))) *)

val of_bool : bool -> unit option
val to_bool : 'a option -> bool

val to_list   : 'a option -> 'a list

val split    : ('a * 'b) option -> 'a option * 'b option
val split3   : ('a * 'b * 'c) option -> 'a option * 'b option * 'c option
val split4   : ('a * 'b * 'c * 'd) option -> 'a option * 'b option * 'c option * 'd option
val split5   : ('a * 'b * 'c * 'd * 'e) option -> 'a option * 'b option * 'c option * 'd option * 'e option

val combine  : 'a option -> 'b option -> ('a * 'b) option
val combine3 : 'a option -> 'b option -> 'c option -> ('a * 'b * 'c) option
val combine4 : 'a option -> 'b option -> 'c option -> 'd option -> ('a * 'b * 'c * 'd) option
val combine5 : 'a option -> 'b option -> 'c option -> 'd option -> 'e option -> ('a * 'b * 'c * 'd * 'e) option

(* Printing *)

val  printf   : ?none:string -> ?frame:(string -> string, unit, string) format -> ('a -> string, unit, string) format -> 'a option -> unit
val eprintf   : ?none:string -> ?frame:(string -> string, unit, string) format -> ('a -> string, unit, string) format -> 'a option -> unit
val sprintf   : ?none:string -> ?frame:(string -> string, unit, string) format -> ('a -> string, unit, string) format -> 'a option -> string
val to_string : ?none:string -> ?frame:(string -> string, unit, string) format -> ?a:('a -> string) -> 'a option -> string
