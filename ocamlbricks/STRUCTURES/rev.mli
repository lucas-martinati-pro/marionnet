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

(** Reversible references. The operation [open_parenthesis] set a backtracking point:
    all settings to reversible references could be reset by a simple call to [close_parenthesis].
    The user can nest parenthesis as he wishes. {b Example}:
{[# let x = create 42 ;;
val x : int t = {previous = []; current = 42}

# set x 43 ;;
  : unit = ()

# open_parenthesis () ;;
  : unit = ()

# set x 44 ;;
  : unit = ()

# set x 45 ;;
  : unit = ()

# get x;;
  : int = 45

# close_parenthesis () ;;
  : unit = ()

# get x;;
  : int = 43

# back_parenthesis () ;;
  : unit = ()

# get x;;
  : int = 42 ]} *)

type 'a t
val create : 'a -> 'a t

val open_parenthesis  : unit -> unit
val close_parenthesis : unit -> unit
val back_parenthesis  : unit -> unit

val get : 'a t -> 'a
val set : 'a t -> 'a -> unit

(** {2 Toolkit} *)

module Toolkit : sig
 val ref  : 'a   -> 'a t
 val (!)  : 'a t -> 'a
 val (:=) : 'a t -> 'a -> unit
end
