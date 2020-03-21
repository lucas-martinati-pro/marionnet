(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2019 Jean-Vincent Loddo

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

(** Polymorphic {e unbounded} sets.
    An encapsulated [('a, unit) Hashtbl.t] is used for quickly answering
    to the membership question.  *)

type 'a t

(* --- *)
type multiplicity = int
val default_size : int
(* --- *)
val make         : ?size:int -> unit -> 'a t
val mem          : 'a t -> 'a -> bool
val multiplicity : 'a t -> 'a -> int
val add          : ?quantity:int (* 1 *) -> 'a t -> 'a -> unit
val remove       : ?quantity:int (* 1 *) -> 'a t -> 'a -> unit
(* --- *)
val of_list    : 'a list -> 'a t
val of_array   : 'a array -> 'a t
(* --- *)
(* The following functions are stable with respect to the order of insertion in the multiset: *)
val to_list    : 'a t -> ('a * multiplicity) list
val to_array   : 'a t -> ('a * multiplicity) array
(* --- *)
val extract_ht : 'a t -> ('a, int * multiplicity) Hashtbl.t
(* --- *)
(** Return a copy of the provided multiset (for a persistent usage): *)
val copy : 'a t -> 'a t

