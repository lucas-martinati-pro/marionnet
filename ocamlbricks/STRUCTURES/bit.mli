(* This file is part of our reusable OCaml BRICKS library
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

(** Some utilities about bits. Notice that these functions are not implemented
    aiming to the best efficiency. They are thinked for small problems related
    to mask of bits (unix permissions, IP,...). *)

val bits_as_booleans_of_int : ?length:int -> int -> bool list
val int_of_bits_as_booleans : bool list -> int

val bits_as_integers_of_int : ?length:int -> int -> int list
val int_of_bits_as_integers : int list -> int
