(* This file is part of ocamlbricks
   Copyright (C) 2017  Jean-Vincent Loddo

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

(* The principal type of this module is a disjunction of locked values: *)
type 'a t = 'a d
  (* --- *)
  and 'a d = ('a c) array
  and 'a c = Lock.c * 'a
  and 'a locked = ('a c) option (* the actual locked value, if any (i.e. iff the disjunction is not empty) *)

(* Constructors: *)

(* The preferable way to make locked values is to convert a fresh values constructor into a locked values one.
   This method prevent the user to access values without locking them. *)
val constructor : ('a -> 'b) -> 'a -> 'b d

val return   : 'a -> 'a d  (* make a structure protected by a basic lock (mutex) *)
val make     : 'a -> 'a d  (* alias for return *)
(* --- *)
val empty    : 'a d        (* alias for zero  *)
val fictive  : 'a -> 'a d  (* alias for unity *)

(* Algebraic operations (sum and product): *)

val zero     : 'a d        (* identity element of the sum (the empty set of conjunctions) *)
val unity    : 'a -> 'a d  (* make a not really protected structure (i.e. protected by the empty set of conjunctions...) *)

(* Homogeneous variadic sum: *)
val sum      : ('a d) list -> 'a d

(* Homogeneous variadic product: *)
val product  : ('a d) list -> ('a list) d

(* Eterogeneous n-ary products: *)
val product2 : ('a d) -> ('b d) -> ('a * 'b) d
val product3 : ('a d) -> ('b d) -> ('c d) -> ('a * 'b * 'c) d
val product4 : ('a d) -> ('b d) -> ('c d) -> ('d d) -> ('a * 'b * 'c * 'd) d
val product5 : ('a d) -> ('b d) -> ('c d) -> ('d d) -> ('e d) -> ('a * 'b * 'c * 'd * 'e) d

(* Homogeneous compositional variadic product: *)
val cproduct  : ('a d) list -> ('a list -> 'alist) -> ('alist) d

(* Eterogeneous compositional n-ary products: *)
val cproduct2 : ('a d) -> ('b d) -> ('a -> 'b -> 'ab) -> ('ab) d
val cproduct3 : ('a d) -> ('b d) -> ('c d) -> ('a -> 'b -> 'c -> 'abc) -> ('abc) d
val cproduct4 : ('a d) -> ('b d) -> ('c d) -> ('d d) -> ('a -> 'b -> 'c -> 'd -> 'abcd) -> ('abcd) d
val cproduct5 : ('a d) -> ('b d) -> ('c d) -> ('d d) -> ('e d) -> ('a -> 'b -> 'c -> 'd -> 'e -> 'abcde) -> ('abcde) d

(* High level access: *)

(* Should we alert other threads waiting on this structure? In other terms, should we perform a broadcast? *)
type alert = bool

(* A "trailer" is an optional thunk executed out of the critical section, that is to say after unlocking the structure. *)
type trailer = (unit -> unit) option

(* High-level blocking access.
   An action of type ('a -> 'b * alert) is performed on the locked structure of type 'a, which is usually mutable
   (for instance a reference or an object). So, this action may change implicitely the internal state of its
   argument (of type 'a) to produce an output (of type 'b). If this happens, the action notify that a broadcast
   must be performed through the second (boolean) part of its result (alert).
   ---
   The trailer is not necessary but very practical because the action usually decides all the next steps:
   (1) which is the provided result (2) is an alert required? (3) are some final actions required (out of
   critical section)? *)
val access : ?verbose:unit -> ?guard:('a -> bool) -> ?timeout:float -> 'a t -> ('a -> 'b * alert * trailer) -> 'b

(* High-level non-blocking access: *)
val try_access : ?verbose:unit -> ?guard:('a -> bool) -> 'a t -> ('a -> 'b * alert * trailer) -> 'b option

(* Simplified interfaces for access and try_access: *)
val easy_access     : 'a t -> ('a -> 'b) -> 'b
val easy_try_access : 'a t -> ('a -> 'b) -> 'b option

(* Low level access: *)

val try_lock  : ?guard:('a -> bool) -> 'a d -> ('a locked) option
val lock      : ?guard:('a -> bool) -> ?timeout:float -> 'a d -> 'a locked
val wait      : 'a locked -> Lock.b option  (* the result is the basic lock where something has happen, if any *)
val broadcast : 'a locked -> unit           (* alert the involved conjunction *)
val unlock    : 'a locked -> unit           (* unlock the involved conjunction *)

val involved_locks : 'a locked -> Lock.b array
