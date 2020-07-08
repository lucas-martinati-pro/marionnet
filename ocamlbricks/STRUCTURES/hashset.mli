(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2018 2020  Jean-Vincent Loddo
   Copyright (C) 2018 2020  Université Sorbonne Paris Nord

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

(** Polymorphic, {e unbounded}, not persistent (imperative) sets.
    An encapsulated [('a, int) Hashtbl.t] is used for quickly answering
    to the membership question.  *)

(* --- *)
type 'a t

(* ---
  In the following tools, the parameter ?identifier:('a -> int) implies:
  (1) hash ≜ (Hashtbl.hash ∘ identifier), and
  (2) equality x y ≜ (identifier x)=(identifier y)
  --- *)
val make     : ?weak:unit (* ephemerons *) -> ?identifier:('a -> int) -> ?equality:('a->'a->bool) (* = *) -> ?size:int (* 0 *) ->    unit  -> 'a t
val of_list  : ?weak:unit (* ephemerons *) -> ?identifier:('a -> int) -> ?equality:('a->'a->bool) (* = *) -> ?size:int (* 0 *) -> 'a list  -> 'a t
val of_array : ?weak:unit (* ephemerons *) -> ?identifier:('a -> int) -> ?equality:('a->'a->bool) (* = *) -> ?size:int (* 0 *) -> 'a array -> 'a t
(* --- *)
val mem        : 'a t -> 'a -> bool
val add        : 'a t -> 'a -> unit
val remove     : 'a t -> 'a -> unit

(** Variant: add a member to the hashset, if necessary, and get its integer
    identifier in the table (useful for weak tables based on the physical
    equality, to obtain a bijection between identifiers and memory adresses): *)
val add'       : 'a t -> 'a -> int

(* Based on add', provides a *transitive* (weak) polymorphic `compare' function.
   Of course, once applied, the result will be of type: '_a -> '_a -> int *)
val make_physical_compare : ?size:int -> unit -> ('a -> 'a -> int)
(* --- *)
(* The following functions are stable with respect to the order of insertion
   in the set ("stability"). Use ~unstable:() to speed up the answer,
   when the stability is not relevant: *)
val to_list    : ?unstable:unit -> 'a t -> 'a list
val to_array   : ?unstable:unit -> 'a t -> 'a array
(* --- *)
(* Stable functions (i.e. elements that compare equal are kept in their original order): *)
val list_uniq  : 'a list  -> 'a list (* stable! *)
val array_uniq : 'a array -> 'a array
val uniq       : 'a list  -> 'a list (* alias for list_uniq *)
(* --- *)
val to_hashtbl : 'a t -> ('a, int) Hashtbl.t
