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

(** A container where elements may be left and succesively removed using their associated ticket.
    Any type of elements are allowed, even functions. These elements are considered equivalent in
    the same way as the standard module [Hashtbl] consider keys equivalent.
    Adding and removing elements are O(log n), itering and folding (by id) are linear O(n)
    as for simple lists. Furthermore, elements are found in O(log n) comparing integer keys. *)

type 'a t
type id = int
type revision = int

val create : ?size:int -> unit -> 'a t

val add    : 'a t -> 'a -> id
val remove : 'a t -> id -> bool
val mem    : 'a t -> id -> bool
val length : 'a t -> int
val revision : 'a t -> int
val iter : (id -> 'a -> unit ) -> 'a t -> unit
val fold : (id -> 'a -> 'b -> 'b) -> 'a t -> 'b -> 'b
val to_list : 'a t -> 'a list
val to_assoc_list : 'a t -> (id * 'a) list
val of_list : 'a list -> 'a t * (id list)

module Cached : sig

  val to_list       : 'a t -> unit -> 'a list
  val to_assoc_list : 'a t -> unit -> (id * 'a) list

end

module Hetero : sig
 type t
 type id = int
 type revision = int
 val create : ?size:int -> unit -> t
 val add    : t -> 'a -> id
 val find   : t -> id -> 'a
 val remove : t -> id -> bool
 val mem    : t -> id -> bool
 val length : t -> int
end
