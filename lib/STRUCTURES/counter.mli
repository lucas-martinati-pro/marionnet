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

(** Generate unique identifiers. The defined structure includes a stack allowing
    to recycle identifiers (using functions [open_parenthesis] and [close_parenthesis]). *)

type t
val create : ?initial_value:int -> unit -> t

val fresh             : t -> unit -> int

val open_parenthesis  : t -> unit
val close_parenthesis : t -> unit

(** {b Example}:
{[
# let c = Counter.create () ;;
val c : Counter.t = <abstr>

# Counter.fresh c () ;;
  : int = 1

# Counter.fresh c () ;;
  : int = 2

# Counter.open_parenthesis c ;;
  : unit = ()

# Counter.fresh c () ;;
  : int = 3

# Counter.fresh c () ;;
  : int = 4

# Counter.close_parenthesis c ;;
  : unit = ()

# Counter.fresh c () ;;
  : int = 3
]}
*)

(** {2 Simplified generators} *)

type 'a generator = unit -> 'a
val make_int_generator    : unit   -> int generator
val make_string_generator : ?prefix:string -> ?suffix:string -> unit -> string generator

(** {2 More sophisticated Object-oriented interface} *)

class c :
  ?initial_value:int ->
  unit ->
  object
    method close_parenthesis : unit
    method fresh : unit -> int
    method open_parenthesis : unit
    method reset : unit
    method set_next_fresh_value_to : int -> unit
    method get_next_fresh_value : int
  end
