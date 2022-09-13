(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2019 2020  Jean-Vincent Loddo
   Copyright (C) 2019 2020  Université Sorbonne Paris Nord

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

(** Polymorphic {e unbounded}, not persistent (imperative) sets.
    An encapsulated [('a, int * multiplicity) Hashtbl.t] is used
    for quickly answering to the membership question.  *)

type 'a t

(* --- *)
type multiplicity = int

(* ---
  In the following tools, the parameter ?identifier:('a -> int) implies:
  (1) hash ≜ (Hashtbl.hash ∘ identifier), and
  (2) equality x y ≜ (identifier x)=(identifier y)
  --- *)
val make     : ?weak:unit (* ephemerons *) -> ?identifier:('a -> int) -> ?equality:('a->'a->bool) (* = *) -> ?size:int (* 0 *) ->    unit -> 'a t
val of_list  : ?weak:unit (* ephemerons *) -> ?identifier:('a -> int) -> ?equality:('a->'a->bool) (* = *) -> ?size:int (* 0 *) -> 'a list -> 'a t
val of_array : ?weak:unit (* ephemerons *) -> ?identifier:('a -> int) -> ?equality:('a->'a->bool) (* = *) -> ?size:int (* 0 *) -> 'a array -> 'a t
(* --- *)
val mem          : 'a t -> 'a -> bool
val multiplicity : 'a t -> 'a -> int
val add          : ?quantity:int (* 1 *) -> 'a t -> 'a -> unit
val remove       : ?quantity:int (* 1 *) -> 'a t -> 'a -> unit
(*(* --- *)
val of_list    : 'a list -> 'a t
val of_array   : 'a array -> 'a t*)
(* --- *)
(* The following functions are stable with respect to the order of insertion
   in the multiset (stability). Use ~unstable:() to speed up the answer,
   when the stability is not relevant: *)
val to_list    : ?unstable:unit -> 'a t -> ('a * multiplicity) list
val to_array   : ?unstable:unit -> 'a t -> ('a * multiplicity) array
(* --- *)
val to_hashtbl : 'a t -> ('a, int * multiplicity) Hashtbl.t

