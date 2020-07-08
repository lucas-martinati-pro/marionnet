(* This file is part of ocamlbricks
   Copyright (C) 2013  Jean-Vincent Loddo

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


(** Generic and compositional data structure for safe threads interactions.
    Cortex stands for (CO)mpositional (R)eactive au(T)omata in mutual (EX)clusion. *)

type 'a t

val return :
  ?equality:('a -> 'a -> bool) ->
  ?on_proposal:('a -> 'a -> 'a) ->
  ?on_commit:('a -> 'a -> unit) ->
  'a -> 'a t

val of_object :
  ?equality:('a -> 'a -> bool) ->
  ?on_proposal:('a -> 'a -> 'a) ->
  ?on_commit:('a -> 'a -> unit) ->
  < get : 'a; set : 'a -> unit > -> 'a t

val on_proposal_append : 'a t -> ('a -> 'a -> 'a) -> Thunk.id
val on_proposal_remove : 'a t -> Thunk.id -> unit
val on_proposal_clear  : 'a t -> unit

val on_commit_append : 'a t -> ('a -> 'a -> unit) -> Thunk.id
val on_commit_remove : 'a t -> Thunk.id -> unit
val on_commit_clear  : 'a t -> unit

(** Generic method call: *)
val eval :
  ?guard:('a -> bool) ->
  ('a -> 'b -> 'a * ('a -> 'c)) ->
  'b ->
  'a t -> 'c * bool

(** Facilities (specific and common `eval' instances): *)
val get     : ?guard:('a -> bool) -> 'a t -> 'a
val set     : ?guard:('a -> bool) -> 'a t -> 'a -> unit
val propose : ?guard:('a -> bool) -> 'a t -> 'a -> 'a * bool
val move    : ?guard:('a -> bool) -> 'a t -> ('a -> 'a) -> 'a * bool
val apply   : ?guard:('a -> bool) -> 'a t -> ('a -> 'b) -> 'b
val apply2  : ?guard:('a -> bool) -> 'a t -> ('a -> 'b -> 'c) -> 'b -> 'c

module Async : sig
  val set  : ?guard:('a -> bool) -> 'a t -> 'a -> unit
  val move : ?guard:('a -> bool) -> 'a t -> ('a -> 'a) -> unit
end

type ('a,'b) either = ('a,'b) Either.t

type 'a scalar_or_cortex = ('a, ('a t)) either
val scalar : 'a   -> 'a scalar_or_cortex
val cortex : 'a t -> 'a scalar_or_cortex

(* -------------------------------------------
                 Connections
   ------------------------------------------- *)

val connection :
  ?on_proposal:('b -> 'b -> 'b) ->
  ?on_commit:('b -> 'b -> unit) ->
  ?private_fellow:unit ->
  ('a -> 'b) ->
  ('b -> 'a) ->
  'a t -> 'b t

val view :
  ?equality:('b -> 'b -> bool) ->
  ?on_proposal:('b -> 'b -> 'b) ->
  ?on_commit:('b -> 'b -> unit) ->
  ?private_fellow:unit ->
  ('a -> 'b) ->
  'a t -> 'b t

(* A wrapper is a connection with the identity functions: *)
val wrapper :
  ?on_proposal:('a -> 'a -> 'a) ->
  ?on_commit:('a -> 'a -> unit) ->
  ?private_fellow:unit ->
  'a t -> 'a t

(* -------------------------------------------
         Canonical products (tuples)
   ------------------------------------------- *)

val group_pair :
  ?on_proposal:('a * 'b -> 'a * 'b -> 'a * 'b) ->
  ?on_commit:('a * 'b -> 'a * 'b -> unit) ->
  'a t ->
  'b t -> ('a * 'b) t

val group_with_scalar :
  ?on_proposal:('a * 'b -> 'a * 'b -> 'a * 'b) ->
  ?on_commit:('a * 'b -> 'a * 'b -> unit) ->
  ('a scalar_or_cortex) ->
  ('b scalar_or_cortex) -> ('a *'b) t

val group_triple :
  ?on_proposal:('a * 'b * 'c -> 'a * 'b * 'c -> 'a * 'b * 'c) ->
  ?on_commit:('a * 'b * 'c -> 'a * 'b * 'c -> unit) ->
  'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t

val group_quadruple :
  ?on_proposal:('a * 'b * 'c * 'd -> 'a * 'b * 'c * 'd -> 'a * 'b * 'c * 'd) ->
  ?on_commit:('a * 'b * 'c * 'd -> 'a * 'b * 'c * 'd -> unit) ->
  'a t -> 'b t -> 'c t -> 'd t -> ('a * 'b * 'c * 'd) t

val group_quintuple :
  ?on_proposal:('a * 'b * 'c * 'd * 'e -> 'a * 'b * 'c * 'd * 'e -> 'a * 'b * 'c * 'd * 'e) ->
  ?on_commit:('a * 'b * 'c * 'd * 'e -> 'a * 'b * 'c * 'd * 'e -> unit) ->
  'a t -> 'b t -> 'c t -> 'd t -> 'e t -> ('a * 'b * 'c * 'd * 'e) t

val group_array :
  ?on_proposal:('a array -> 'a array -> 'a array) ->
  ?on_commit:('a array -> 'a array -> unit) ->
  ('a t) array -> ('a array) t

val defuse : 'a t -> unit

(* -------------------------------------------
     Canonical sums (arrays, option, either)
   ------------------------------------------- *)

val sum_array :
  ?on_proposal:(int * 'a -> int  * 'a -> int * 'a) ->
  ?on_commit:(int * 'a -> int  * 'a -> unit) ->
  'a t array -> (int * 'a) t

module Either :
  sig
    val iLeft :
      ?on_proposal:(('a,'b) either -> ('a,'b) either -> ('a,'b) either) ->
      ?on_commit:(('a,'b) either -> ('a,'b) either -> unit) ->
      ?right:('b t) ->
      'a scalar_or_cortex -> (('a,'b) either) t

    val iRight :
      ?on_proposal:(('a,'b) either -> ('a,'b) either -> ('a,'b) either) ->
      ?on_commit:(('a,'b) either -> ('a,'b) either -> unit) ->
      ?left:('a t) ->
      'b scalar_or_cortex -> (('a,'b) either) t
  end

module Option :
  sig
    val iNone :
      ?on_proposal:('a option -> 'a option -> 'a option) ->
      ?on_commit:('a option -> 'a option -> unit) ->
      'a t -> ('a option) t

    val iSome :
      ?on_proposal:('a option -> 'a option -> 'a option) ->
      ?on_commit:('a option -> 'a option -> unit) ->
      'a t -> ('a option) t
  end


(* -------------------------------------------
                General products
   ------------------------------------------- *)

module Product_pair :
 functor
  (Prod : sig
     type ('a,'b) t
     val prjA : ('a,'b) t -> 'a
     val prjB : ('a,'b) t -> 'b
     val make : 'a -> 'b -> ('a,'b) t
   end)
   -> sig
        (* This is the only function with an interface allowing
           the user to specify a scalar. In the other functors
           we will be able to compose only cortex. *)
	val make :
	  ?on_proposal:(('a,'b) Prod.t -> ('a,'b) Prod.t -> ('a,'b) Prod.t) ->
	  ?on_commit:(('a,'b) Prod.t -> ('a,'b) Prod.t -> unit) ->
	  ('a scalar_or_cortex) ->
	  ('b scalar_or_cortex) -> (('a,'b) Prod.t) t
      end

module Product_triple :
 functor
  (Prod : sig
     type ('a,'b,'c) t
     val prjA : ('a,'b,'c) t -> 'a
     val prjB : ('a,'b,'c) t -> 'b
     val prjC : ('a,'b,'c) t -> 'c
     val make : 'a -> 'b -> 'c -> ('a,'b,'c) t
   end)
   -> sig
	val product_triple :
	  ?on_proposal:(('a,'b,'c) Prod.t -> ('a,'b,'c) Prod.t -> ('a,'b,'c) Prod.t) ->
	  ?on_commit:(('a,'b,'c) Prod.t -> ('a,'b,'c) Prod.t -> unit) ->
	  'a t -> 'b t -> 'c t -> (('a,'b,'c) Prod.t) t
      end

module Product_quadruple :
 functor
  (Prod : sig
     type ('a,'b,'c,'d) t
     val prjA : ('a,'b,'c,'d) t -> 'a
     val prjB : ('a,'b,'c,'d) t -> 'b
     val prjC : ('a,'b,'c,'d) t -> 'c
     val prjD : ('a,'b,'c,'d) t -> 'd
     val make : 'a -> 'b -> 'c -> 'd -> ('a,'b,'c,'d) t
   end)
   -> sig
	val product_quadruple :
	  ?on_proposal:(('a,'b,'c,'d) Prod.t -> ('a,'b,'c,'d) Prod.t -> ('a,'b,'c,'d) Prod.t) ->
	  ?on_commit:(('a,'b,'c,'d) Prod.t -> ('a,'b,'c,'d) Prod.t -> unit) ->
	  'a t -> 'b t -> 'c t -> 'd t -> (('a,'b,'c,'d) Prod.t) t
      end

module Product_quintuple :
 functor
  (Prod : sig
     type ('a,'b,'c,'d,'e) t
     val prjA : ('a,'b,'c,'d,'e) t -> 'a
     val prjB : ('a,'b,'c,'d,'e) t -> 'b
     val prjC : ('a,'b,'c,'d,'e) t -> 'c
     val prjD : ('a,'b,'c,'d,'e) t -> 'd
     val prjE : ('a,'b,'c,'d,'e) t -> 'e
     val make : 'a -> 'b -> 'c -> 'd -> 'e -> ('a,'b,'c,'d,'e) t
   end)
   -> sig
	val product_quintuple :
	  ?on_proposal:(('a,'b,'c,'d,'e) Prod.t -> ('a,'b,'c,'d,'e) Prod.t -> ('a,'b,'c,'d,'e) Prod.t) ->
	  ?on_commit:(('a,'b,'c,'d,'e) Prod.t -> ('a,'b,'c,'d,'e) Prod.t -> unit) ->
	  'a t -> 'b t -> 'c t -> 'd t -> 'e t -> (('a,'b,'c,'d,'e) Prod.t) t
      end

(* -------------------------------------------
                General sums
   ------------------------------------------- *)

module Sum_pair :
 functor
  (Sum : sig
     type ('a,'b) t
     val injA : 'a -> ('a,'b) t
     val injB : 'b -> ('a,'b) t
     val case : ('a,'b) t -> ('a -> 'y) -> ('b -> 'y) -> 'y
   end)
   -> sig
	val injA :
	  ?on_proposal:(('a,'b) Sum.t -> ('a,'b) Sum.t -> ('a,'b) Sum.t) ->
	  ?on_commit:(('a,'b) Sum.t -> ('a,'b) Sum.t -> unit) ->
	  ?b:('b t) ->
	  'a scalar_or_cortex -> (('a,'b) Sum.t) t

	val injB :
	  ?on_proposal:(('a,'b) Sum.t -> ('a,'b) Sum.t -> ('a,'b) Sum.t) ->
	  ?on_commit:(('a,'b) Sum.t -> ('a,'b) Sum.t -> unit) ->
	  ?a:('a t) ->
	  'b scalar_or_cortex -> (('a,'b) Sum.t) t
      end

module Sum_triple :
 functor
  (Sum : sig
     type ('a,'b,'c) t
     val injA   : 'a -> ('a,'b,'c) t
     val injB   : 'b -> ('a,'b,'c) t
     val injC   : 'c -> ('a,'b,'c) t
     val case   : ('a,'b,'c) t -> ('a -> 'y) -> ('b -> 'y) -> ('c -> 'y) -> 'y
   end)
   -> sig
	val injA :
	  ?on_proposal:(('a,'b,'c) Sum.t -> ('a,'b,'c) Sum.t -> ('a,'b,'c) Sum.t) ->
	  ?on_commit:(('a,'b,'c) Sum.t -> ('a,'b,'c) Sum.t -> unit) ->
	  ?b:('b t) ->
	  ?c:('c t) ->
	  'a scalar_or_cortex -> (('a,'b,'c) Sum.t) t

	val injB :
	  ?on_proposal:(('a,'b,'c) Sum.t -> ('a,'b,'c) Sum.t -> ('a,'b,'c) Sum.t) ->
	  ?on_commit:(('a,'b,'c) Sum.t -> ('a,'b,'c) Sum.t -> unit) ->
	  ?a:('a t) ->
	  ?c:('c t) ->
	  'b scalar_or_cortex -> (('a,'b,'c) Sum.t) t

	val injC :
	  ?on_proposal:(('a,'b,'c) Sum.t -> ('a,'b,'c) Sum.t -> ('a,'b,'c) Sum.t) ->
	  ?on_commit:(('a,'b,'c) Sum.t -> ('a,'b,'c) Sum.t -> unit) ->
	  ?a:('a t) ->
	  ?b:('b t) ->
	  'c scalar_or_cortex -> (('a,'b,'c) Sum.t) t
      end

module Sum_quadruple :
 functor
  (Sum : sig
     type ('a,'b,'c,'d) t
     val injA   : 'a -> ('a,'b,'c,'d) t
     val injB   : 'b -> ('a,'b,'c,'d) t
     val injC   : 'c -> ('a,'b,'c,'d) t
     val injD   : 'd -> ('a,'b,'c,'d) t
     val case   :
       ('a,'b,'c,'d) t ->
       ('a -> 'y) -> ('b -> 'y) -> ('c -> 'y) -> ('d -> 'y) -> 'y
   end)
   -> sig
	val injA :
	  ?on_proposal:(('a,'b,'c,'d) Sum.t -> ('a,'b,'c,'d) Sum.t -> ('a,'b,'c,'d) Sum.t) ->
	  ?on_commit:(('a,'b,'c,'d) Sum.t -> ('a,'b,'c,'d) Sum.t -> unit)  ->
	  ?b:('b t) ->
	  ?c:('c t) ->
	  ?d:('d t) ->
	  'a scalar_or_cortex -> (('a,'b,'c,'d) Sum.t) t

	val injB :
	  ?on_proposal:(('a,'b,'c,'d) Sum.t -> ('a,'b,'c,'d) Sum.t -> ('a,'b,'c,'d) Sum.t) ->
	  ?on_commit:(('a,'b,'c,'d) Sum.t -> ('a,'b,'c,'d) Sum.t -> unit)  ->
	  ?a:('a t) ->
	  ?c:('c t) ->
	  ?d:('d t) ->
	  'b scalar_or_cortex -> (('a,'b,'c,'d) Sum.t) t

	val injC :
	  ?on_proposal:(('a,'b,'c,'d) Sum.t -> ('a,'b,'c,'d) Sum.t -> ('a,'b,'c,'d) Sum.t) ->
	  ?on_commit:(('a,'b,'c,'d) Sum.t -> ('a,'b,'c,'d) Sum.t -> unit)  ->
	  ?a:('a t) ->
	  ?b:('b t) ->
	  ?d:('d t) ->
	  'c scalar_or_cortex -> (('a,'b,'c,'d) Sum.t) t

	val injD :
	  ?on_proposal:(('a,'b,'c,'d) Sum.t -> ('a,'b,'c,'d) Sum.t -> ('a,'b,'c,'d) Sum.t) ->
	  ?on_commit:(('a,'b,'c,'d) Sum.t -> ('a,'b,'c,'d) Sum.t -> unit)  ->
	  ?a:('a t) ->
	  ?b:('b t) ->
	  ?c:('c t) ->
	  'd scalar_or_cortex -> (('a,'b,'c,'d) Sum.t) t
      end

module Sum_quintuple :
 functor
  (Sum : sig
     type ('a,'b,'c,'d,'e) t
     val injA   : 'a -> ('a,'b,'c,'d,'e) t
     val injB   : 'b -> ('a,'b,'c,'d,'e) t
     val injC   : 'c -> ('a,'b,'c,'d,'e) t
     val injD   : 'd -> ('a,'b,'c,'d,'e) t
     val injE   : 'e -> ('a,'b,'c,'d,'e) t
     val case   :
       ('a,'b,'c,'d,'e) t ->
       ('a -> 'y) -> ('b -> 'y) -> ('c -> 'y) -> ('d -> 'y) -> ('e -> 'y) -> 'y
   end)
   -> sig
	val injA :
	  ?on_proposal:(('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t) ->
	  ?on_commit:(('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t -> unit) ->
	  ?b:('b t) ->
	  ?c:('c t) ->
	  ?d:('d t) ->
	  ?e:('e t) ->
	  'a scalar_or_cortex -> (('a,'b,'c,'d,'e) Sum.t) t

	val injB :
	  ?on_proposal:(('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t) ->
	  ?on_commit:(('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t -> unit) ->
	  ?a:('a t) ->
	  ?c:('c t) ->
	  ?d:('d t) ->
	  ?e:('e t) ->
	  'b scalar_or_cortex -> (('a,'b,'c,'d,'e) Sum.t) t

	val injC :
	  ?on_proposal:(('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t) ->
	  ?on_commit:(('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t -> unit) ->
	  ?a:('a t) ->
	  ?b:('b t) ->
	  ?d:('d t) ->
	  ?e:('e t) ->
	  'c scalar_or_cortex -> (('a,'b,'c,'d,'e) Sum.t) t

	val injD :
	  ?on_proposal:(('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t) ->
	  ?on_commit:(('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t -> unit) ->
	  ?a:('a t) ->
	  ?b:('b t) ->
	  ?c:('c t) ->
	  ?e:('e t) ->
	  'd scalar_or_cortex -> (('a,'b,'c,'d,'e) Sum.t) t

	val injE :
	  ?on_proposal:(('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t) ->
	  ?on_commit:(('a,'b,'c,'d,'e) Sum.t -> ('a,'b,'c,'d,'e) Sum.t -> unit) ->
	  ?a:('a t) ->
	  ?b:('b t) ->
	  ?c:('c t) ->
	  ?d:('d t) ->
	  'e scalar_or_cortex -> (('a,'b,'c,'d,'e) Sum.t) t
      end



(* -------------------------------------------
             Basic OO interfaces
   ------------------------------------------- *)

module Object : sig

  class type ['a] public_interface = object
    method cortex_t : 'a t
    method eval     : 'b 'c. ?guard:('a -> bool) -> ('a -> 'b -> 'a * ('a -> 'c)) -> 'b -> 'c * bool
    method get      : ?guard:('a -> bool) -> unit -> 'a
    method set      : ?guard:('a -> bool) -> 'a -> unit
    method propose  : ?guard:('a -> bool) -> 'a -> 'a * bool
    method move     : ?guard:('a -> bool) -> ('a -> 'a) -> 'a * bool
    method async    : <
      set  : ?guard:('a -> bool) -> 'a -> unit;
      move : ?guard:('a -> bool) -> ('a -> 'a) -> unit;
      >
  end

  class type ['a] private_interface = object
    method private cortex_t : 'a t
    method private eval     : 'b 'c. ?guard:('a -> bool) -> ('a -> 'b -> 'a * ('a -> 'c)) -> 'b -> 'c * bool
    method private get      : ?guard:('a -> bool) -> unit -> 'a
    method private set      : ?guard:('a -> bool) -> 'a -> unit
    method private propose  : ?guard:('a -> bool) -> 'a -> 'a * bool
    method private move     : ?guard:('a -> bool) -> ('a -> 'a) -> 'a * bool
    method private async    : <
      set  : ?guard:('a -> bool) -> 'a -> unit;
      move : ?guard:('a -> bool) -> ('a -> 'a) -> unit;
      >
  end

  class ['a] with_public_interface  : 'a t -> ['a] public_interface
  class ['a] with_private_interface : 'a t -> ['a] private_interface

  val with_public_interface  : 'a t -> 'a public_interface
  val with_private_interface : 'a t -> 'a private_interface

end (* Object *)

(* Group-then-close strategy (instead of close-then-group) *)
module Open : sig
  type 'a opn

  val return :
    ?equality:('a -> 'a -> bool) ->
    ?on_proposal:('a -> 'a -> 'a) ->
    ?on_commit:('a -> 'a -> unit) ->
    'a -> ('a t) opn

  val close : 'a opn -> 'a

  val group_pair :
    ?on_proposal:('a * 'b -> 'a * 'b -> 'a * 'b) ->
    ?on_commit:('a * 'b -> 'a * 'b -> unit) ->
    'a t opn -> 'b t opn ->
    ('a t * 'b t * ('a * 'b) t) opn

  val group_triple :
    ?on_proposal:('a * 'b * 'c -> 'a * 'b * 'c -> 'a * 'b * 'c) ->
    ?on_commit:('a * 'b * 'c -> 'a * 'b * 'c -> unit) ->
    'a t opn -> 'b t opn -> 'c t opn ->
    ('a t * 'b t * 'c t * ('a * 'b * 'c) t) opn

  val group_quadruple :
    ?on_proposal:('a * 'b * 'c * 'd -> 'a * 'b * 'c * 'd -> 'a * 'b * 'c * 'd) ->
    ?on_commit:('a * 'b * 'c * 'd -> 'a * 'b * 'c * 'd -> unit) ->
    'a t opn -> 'b t opn -> 'c t opn -> 'd t opn ->
    ('a t * 'b t * 'c t * 'd t * ('a * 'b * 'c * 'd) t) opn

  val group_quintuple :
    ?on_proposal:('a * 'b * 'c * 'd * 'e -> 'a * 'b * 'c * 'd * 'e -> 'a * 'b * 'c * 'd * 'e) ->
    ?on_commit:('a * 'b * 'c * 'd * 'e -> 'a * 'b * 'c * 'd * 'e -> unit) ->
    'a t opn -> 'b t opn -> 'c t opn -> 'd t opn -> 'e t opn ->
    ('a t * 'b t * 'c t * 'd t * 'e t * ('a * 'b * 'c * 'd * 'e) t) opn

  val group_array :
    ?on_proposal:('a array -> 'a array -> 'a array) ->
    ?on_commit:('a array -> 'a array -> unit) ->
    'a t opn array -> ('a t array * 'a array t) opn

  val lifes :
    ?on_proposal:(('a option * 'a t) -> ('a option * 'a t) -> ('a option * 'a t)) ->
    ?on_commit:(('a option * 'a t) -> ('a option * 'a t) -> unit) ->
    creator:(?previous:'a -> unit -> 'a t opn) ->
    terminal:('a -> bool) ->
    unit -> ('a option * 'a t) t opn

  val sum_array :
    ?on_proposal:(int * 'a -> int  * 'a -> int * 'a) ->
    ?on_commit:(int * 'a -> int  * 'a -> unit) ->
    'a t opn array -> ('a t array * (int * 'a) t) opn

  module Product_pair :
  functor
    (Prod : sig
      type ('a,'b) t
      val prjA : ('a,'b) t -> 'a
      val prjB : ('a,'b) t -> 'b
      val make : 'a -> 'b -> ('a,'b) t
    end)
    -> sig
	  val product_pair :
	    ?on_proposal:(('a,'b) Prod.t -> ('a,'b) Prod.t -> ('a,'b) Prod.t) ->
	    ?on_commit:(('a,'b) Prod.t -> ('a,'b) Prod.t -> unit) ->
	    'a t opn -> 'b t opn ->
	    ('a t * 'b t * (('a,'b) Prod.t) t) opn
	end

end (* module Open *)

type 'a u = 'a t Open.opn

(* -------------------------------------------
               Leashed pointers
   ------------------------------------------- *)

val lifes :
  ?on_proposal:(('a option * 'a t) -> ('a option * 'a t) -> ('a option * 'a t)) ->
  ?on_commit:(('a option * 'a t) -> ('a option * 'a t) -> unit) ->
  creator:(?previous:'a -> unit -> 'a u) ->
  terminal:('a -> bool) ->
  unit -> ('a option * 'a t) t


(* -------------------------------------------
                  Examples
   ------------------------------------------- *)

IFDEF DOCUMENTATION_OR_DEBUGGING THEN
module Make_Examples : functor (Void:sig end) -> sig
module Example1 : sig
  val x : int t
  val y : int t
  val z : (int * int) t
  val w : (int, int) either t
  module Triad : sig  type ('a, 'b, 'c) t = Apollo of 'a | Athena of 'b | Zeus of 'c  end
  val t : (int, int, string) Triad.t t
  end
module Example2 : sig
  val x : (int option * int t) t
  val y : int t
  val z : int t
  val look : ('a * 'b t) t -> 'b
  val member : ('a * 'b t) t -> 'b t
  end
end (* functor Make_Examples() *)
ENDIF
