(* This file is part of ocamlbricks
   Copyright (C) 2013, 2014, 2015, 2016, 2017  Jean-Vincent Loddo

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

(* ------------------------------------- *
          Very low-level access
 * ------------------------------------- *)

module Basic :
   sig
     (* --- *)
     type b = Mutex.t * Condition.t
     (* --- *)
     val create    : unit -> b
     val try_lock  : ?guard:(b -> bool) -> b -> bool
     val lock      : ?guard:(b -> bool) -> ?timeout:float -> b -> unit
     val wait      : b -> unit
     val signal    : b -> unit
     val broadcast : b -> unit
     val unlock    : b -> unit
     (* --- *)
     val merge_and_sort_basic_lists : (b list) list -> b list
     val compare   : b -> b -> int
   end

(* Conjunction: a sorted array of basic locks: *)
module Conjunction :
  sig
    (* --- *)
    type c = b array
     and b = Basic.b
    (* --- *)
    val create    : unit -> c
    val product   : c list -> c
    val unity     : c (* empty*)
    val append    : c -> c -> c (* a binary product without reordering *)
    val try_lock  : ?guard:(c -> bool) -> c -> bool
    val lock      : ?guard:(c -> bool) -> ?timeout:float -> c -> unit
    val unlock    : c -> unit
    val wait      : c -> b option  (* the result is the basic where something has happen, if any *)
    val broadcast : c -> unit
    (* --- *)
    val compare   : c -> c -> int
    module Set    : Set.S with type elt = c
  end

(* ------------------------------------- *
       Low-level access
 * ------------------------------------- *)

(* The module in a nutshell: *)
type b = Basic.b              (* Basic locks                         : b = (mutex, condition) *)
 and c = Conjunction.c        (* Ordered conjunctions of basic locks : c = b1 ⋅ b2 ⋅ ⋅⋅⋅ ⋅ bk *)
 and d = Conjunction.c array  (* Disjunction of conjunctions         : d = c1 + c2 + ... + cn *)

(* Alias that helps to clarify the signature of try_lock: *)
type 'a maybe = 'a option

exception Timeout

(* The result of try_lock should be interpreted in this way:
   None => false, Some(None) => true but the disjunction is empty (zero), Some(Some(c)) => true with the involved conjunction c. *)
val try_lock  : ?guard:(c -> bool) -> d -> c option maybe

(* The result of lock() is None iff the disjunction is empty *)
val lock      : ?guard:(c -> bool) -> ?timeout:float -> d -> c option

val wait      : c -> b option  (* the result is the basic where something has happen, if any *)
val broadcast : c -> unit (* alert *)

val unlock    : c -> unit


(* ------------------------------------- *
           High-level access
 * ------------------------------------- *)

(* A lock, in the more general sense, is a disjunction: *)
type t = d

val create  : unit -> t

val sum     : t list -> t  (* general n-ary sum of locks *)
val product : t list -> t  (* general n-ary product of locks *)

val zero  : t (* identity element of the sum:     0 = {} *)
val unity : t (* identity element of the product: 1 = {{}} *)

val empty : t (* alias for zero *)

val of_conjunction_list  : Conjunction.c list  -> d
val of_conjunction_array : Conjunction.c array -> d

(* Should we alert other threads waiting on this structure? In other terms, should we perform a broadcast? *)
type alert = bool

(* A "trailer" is an optional thunk executed out of the critical section, that is to say after unlocking the structure. *)
type trailer = (unit -> unit) option

(* High-level blocking access.
   The second result of the action (c -> 'a * alert) indicates if a broadcast must be performed
   on the locked conjunction, before unlocking.
   Both the function `guard' and the action (c -> 'a * alert) take a conjunction as argument.
   The idea is that, with this information (used as a dictionary key), all these functions could
   recover other related informations. *)
val access : ?verbose:unit -> ?guard:(c -> bool) -> ?timeout:float -> t -> (c -> 'a * alert * trailer) -> 'a

(* High-level non-blocking access. *)
val try_access : ?verbose:unit -> ?guard:(c -> bool) -> t -> (c -> 'a * alert * trailer) -> 'a option
