(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009 Jean-Vincent Loddo

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

(** Additional features for the standard module [Pervasives]. *)

type filename = string
type length = int

val round      : ?decimals:int (* 3 *) -> float -> float

val percentage          : ?decimals:int (* 0 *) -> float -> float
val percentage_fraction : ?decimals:int (* 0 *) -> int -> int -> float

val for_float : ?break:('a -> float -> bool) -> ?backward:unit -> min:float -> max:float -> step:float -> ('a -> float -> 'a) -> 'a -> 'a
val for_int   : ?break:('a -> int -> bool)   -> ?backward:unit -> ?step:int -> min:int -> max:int -> ('a -> int -> 'a) -> 'a -> 'a

(** The result on empty or non-existent files is None. *)
val get_first_line_of_file  : string -> string option

(** The result on empty or non-existent files is the empty list. *)
val get_first_lines_of_file : filename -> int -> string list

(** The result on empty or non-existent files is the empty list. *)
val get_first_chars_of_file : filename -> int -> char list

val with_open_in      : filename:string -> (in_channel -> length -> 'a) -> 'a
val with_open_in_bin  : filename:string -> (in_channel -> length -> 'a) -> 'a

val with_open_out     : ?perm:int -> filename:string -> (out_channel -> 'a) -> 'a
val with_open_out_bin : ?perm:int -> filename:string -> (out_channel -> 'a) -> 'a

val get_file_content  : filename:string -> string
val put_file_content  : ?perm:int -> filename:string -> string -> unit
