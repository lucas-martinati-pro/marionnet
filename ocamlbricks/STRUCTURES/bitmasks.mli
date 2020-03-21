(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2018 2019  Jean-Vincent Loddo

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


(** Efficient operations on sets of natural numbers (indexes) based on bitmasks.
    Elements of sets are indexes (int) from 0 to (n-1) where n is the cardinality.
    The equality test between two sets is specially efficient.
    This module is accessory for Loop.Range. *)

(* Each integer in the array represent the bitmask for dpi indexes.
   The array representing the set should be a little array of integers
   => efficient equality test (=) *)
type t = mask array
  (* --- *)
  and mask  = int
  and card  = int
  and dim   = int (* maximal cardinality *)
  and index = int (* 0..(dim-1) *)

(* The `dpi', i.e. the (d)imension (p)er (i)nteger is the most relevant constant in this module.
   It represent the maximal cardinality encoded by a single integer.
   For a 64 bit architecture the dpi is 62. *)
val dpi : dim

(* dim = length * dpi *)
val dim : t -> dim

val empty     : ?dim:int (* dpi *) -> unit -> t
val singleton : ?dim:int (* index+1 *) -> index -> t

val add    : index -> t -> t
val remove : index -> t -> t

val add_in_place    : index -> t -> unit
val remove_in_place : index -> t -> unit

(* Useful to implement multisets as stratified bitmasks (Bitmmask). Obsolete. *)
val add_checking_membership : index -> t -> t * bool

val mem : index -> t -> bool

val union : t -> t -> t
val inter : t -> t -> t

val of_list : ?dim:int -> index list -> t
val to_list : t -> index list

val is_empty : t -> bool
val subset : t -> t -> bool

(* None means "incomparable", (Some 0) means "equals", (Some (-1)) means "subset", (Some 1) means "superset" *)
val compare : t -> t -> int option
