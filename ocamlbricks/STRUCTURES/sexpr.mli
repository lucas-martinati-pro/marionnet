(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2020  Jean-Vincent Loddo
   Copyright (C) 2020  Université Sorbonne Paris Nord

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

(** S-expressions defined to be isomorphic to OCaml tuples but closed w.r.t. products. *)

(* "s-expression" or "nested-list" or "nested-2D-point" or binary-"tree"-structured-data : *)
type _ t = Atom : 'a -> 'a t | Cons : 'a t * 'b t -> ('a * 'b) t

val atom   : 'a -> 'a t
val cons   : 'a t -> 'b t -> ('a * 'b) t
val car    : ('a * 'b) t -> 'a t            (* fst ∘ decons *)
val cdr    : ('a * 'b) t -> 'b t            (* snd ∘ decons *)
val decons : ('a * 'b) t -> 'a t * 'b t

(* Aliases: *)
val return  : 'a -> 'a t                    (* atom   *)
val product : 'a t -> 'b t -> ('a * 'b) t   (* cons   *)
val fst     : ('a * 'b) t -> 'a t           (* car    *)
val snd     : ('a * 'b) t -> 'b t           (* cdr    *)
val split   : ('a * 'b) t -> 'a t * 'b t    (* decons *)
val combine : 'a t -> 'b t -> ('a * 'b) t   (* cons   *)
val unzip   : ('a * 'b) t -> ('a t * 'b t)  (* decons *)
val zip     : ('a t * 'b t) -> ('a * 'b) t  (* cons (uncurried) *)

(* An S-expression, as defined, in never empty, so: *)
val extract : 'a t -> 'a

(* compare_extracted (compare) = compare ∘ (extract ⨯ extract) *)
val compare_extracted : ('a -> 'a -> int) -> ('a t -> 'a t -> int)

(* compare = compare_extracted (Pervasives.compare) *)
val compare : ('a t -> 'a t -> int)
(*
let x = Sexpr.atom 10 ;;
let y = Sexpr.atom 'A' ;;

(compare) (Sexpr.product x y) (Sexpr.atom (10,'A')) ;;
- : int = 1

(Sexpr.compare) (Sexpr.product x y) (Sexpr.atom (10,'A')) ;;
- : int = 0
*)

(* ---------------------------- *)
(*       Some signatures        *)
(* ---------------------------- *)

module type ALIASES =
   sig
    type 'a t
    (* --- *)
    val product : 'a t -> 'b t -> ('a * 'b) t           (* cons   *)
    val fst     : ('a * 'b) t -> 'a t                   (* car    *)
    val snd     : ('a * 'b) t -> 'b t                   (* cdr    *)
    (* --- *)
    val split   : ('a * 'b) t -> ('a t * 'b t)          (* decons *)
    val combine : 'a t -> 'b t -> ('a * 'b) t           (* cons *)
    (* --- *)
    val unzip   : ('a * 'b) t -> ('a t * 'b t)          (* decons *)
    val zip     : ('a t * 'b t) -> ('a * 'b) t          (* (uncurried) cons *)
    (* --- *)
  end

module type FORGET_AND_NEST_METHODS =
   sig
    type 'a t
    (* --- *)
    val forget_R  : ('a * 'b) t -> 'a t                 (* car *)
    val forget_L  : ('a * 'b) t -> 'b t                 (* cdr *)
    (* --- *)
    val forget_LL : (('a * 'b) * 'c) t -> ('b * 'c) t   (* map_L ∘ forget_L *)
    val forget_LR : (('a * 'b) * 'c) t -> ('a * 'c) t   (* map_L ∘ forget_R *)
    val forget_RL : ('a * ('b * 'c)) t -> ('a * 'c) t   (* map_R ∘ forget_L *)
    val forget_RR : ('a * ('b * 'c)) t -> ('a * 'b) t   (* map_R ∘ forget_R *)
    (* --- *)
    val nest_L    : 'a t -> 'b t -> ('a * 'b) t         (* cons *)
    val nest_R    : 'b t -> 'a t -> ('a * 'b) t         (* cons ∘ flip *)
    (* --- *)
    val nest_LL   : 'a t -> ('b * 'c) t -> (('a * 'b) * 'c) t  (* map_L (nest_L) *)
    val nest_LR   : 'b t -> ('a * 'c) t -> (('a * 'b) * 'c) t  (* map_L (nest_R) *)
    val nest_RL   : 'b t -> ('a * 'c) t -> ('a * ('b * 'c)) t  (* map_R (nest_L) *)
    val nest_RR   : 'c t -> ('a * 'b) t -> ('a * ('b * 'c)) t  (* map_R (nest_R) *)
    (* --- *)
  end

(* The type of this module: *)
module type SEXPR =
  sig
    type _ t = Atom : 'a -> 'a t | Cons : 'a t * 'b t -> ('a * 'b) t
    val atom   : 'a -> 'a t
    val cons   : 'a t -> 'b t -> ('a * 'b) t
    val car    : ('a * 'b) t -> 'a t
    val cdr    : ('a * 'b) t -> 'b t
    val decons : ('a * 'b) t -> 'a t * 'b t
    (* aliases: *)
    val return  : 'a -> 'a t                            (* atom *)
    include ALIASES with type 'a t := 'a t
  end

(* ---------------------------- *)
(*  LIFT AN unzip-ABLE FUNCTOR  *)
(* ---------------------------- *)

module type UNZIPPABLE =
   sig
     type 'a t
     (* --- *)
     val unzip : ('a * 'b) t -> 'a t * 'b t
     (* --- *)
     (* Projections are optional (may be trivially derived from unzip) but may
        be provided if there are more efficient versions (this may happen when
        unzip is itself built from projections): *)
     val fst   : (('a * 'b) t -> 'a t) option
     val snd   : (('a * 'b) t -> 'b t) option
     (* --- *)
   end (* UNZIPPABLE *)

(* Using the provided type's projections we can go down (unzip) more than... the depth of the tree! *)
module OF_UNZIPPABLE (U : UNZIPPABLE)
 : sig
    type (_) t = Atom : 'a U.t -> 'a t | Cons : ('a t * 'b t) -> ('a * 'b) t
    (* --- *)
    val atom   : 'a U.t -> 'a t
    val cons   : 'a t -> 'b t -> ('a * 'b) t
    (* --- *)
    val is_atom : 'a t -> bool
    val is_cons : 'a t -> bool
    (* --- *)
    val decons : ('a * 'b) t -> ('a t * 'b t)
    val car    : ('a * 'b) t -> 'a t                    (* fst ∘ decons *)
    val cdr    : ('a * 'b) t -> 'b t                    (* snd ∘ decons *)
    (* --- *)
    include ALIASES with type 'a t := 'a t
    (* --- *)
    val map_L : ('a0 t -> 'a1 t) -> ('a0 * 'b) t -> ('a1 * 'b) t
    val map_R : ('b0 t -> 'b1 t) -> ('a * 'b0) t -> ('a * 'b1) t
    (* --- *)
    include FORGET_AND_NEST_METHODS with type 'a t := 'a t
    (* --- *)
  end

(* ---------------------------- *)
(*  Memoize a "zipped" FUNCTOR  *)
(* ---------------------------- *)

(* Zippable and unzippable (bijection)
   Source: Handbook of algebra Vol.3 HAZEWINKEL, ELSEVIER 2003 *)
module type ZIPPED =
   sig
     type 'a t
     (* --- *)
     val zip   : ('a t * 'b t) -> ('a * 'b) t
     val unzip : ('a * 'b) t -> 'a t * 'b t
     (* --- *)
     val fst   : (('a * 'b) t -> 'a t) option
     val snd   : (('a * 'b) t -> 'b t) option
     (* --- *)
   end (* ZIPPED *)


(* Genealogy of products (zip applications).
   Using the provided type's projections we can go down more than... the depth of the tree! *)
module GENEALOGY_OF_ZIPPED (Z : ZIPPED)
: sig
    type (_) t = Atom : 'a Z.t -> 'a t | Cons : ('a * 'b) Z.t * ('a t * 'b t) -> ('a * 'b) t
    (* --- *)
    val atom   : 'a Z.t -> 'a t
    val cons   : ('a * 'b) Z.t -> 'a t -> 'b t -> ('a * 'b) t
    (* --- *)
    val root    : 'a t -> 'a Z.t
    val is_atom : 'a t -> bool
    val is_cons : 'a t -> bool
    (* --- *)
    val car    : ('a * 'b) t -> 'a t
    val cdr    : ('a * 'b) t -> 'b t
    val decons : ('a * 'b) t -> ('a * 'b) Z.t * ('a t * 'b t)
    (* --- *)
    (* Aliases (less trivial than usual): *)
    val product  : 'a t -> 'b t -> ('a * 'b) t      (* cons ∘ Z.zip ∘ (root, root) *)
    val fst      : ('a * 'b) t -> 'a t              (* car              *)
    val snd      : ('a * 'b) t -> 'b t              (* cdr              *)
    val split    : ('a * 'b) t -> ('a t * 'b t)     (* snd ∘ decons     *)
    val combine  : 'a t -> 'b t -> ('a * 'b) t      (* product          *)
    val unzip    : ('a * 'b) t -> ('a t * 'b t)     (* snd ∘ decons     *)
    val zip      : ('a t * 'b t) -> ('a * 'b) t     (* (uncurried) product *)

   (* If the node is a cons, reuse the projections stored at children level to build the new products: *)
    val map_L     : ('a0 Z.t -> 'a1 Z.t) -> ('a0 t -> 'a1 t) -> ('a0 * 'b) t -> ('a1 * 'b) t
    val map_R     : ('b0 Z.t -> 'b1 Z.t) -> ('b0 t -> 'b1 t) -> ('a * 'b0) t -> ('a * 'b1) t
    (* --- *)
    include FORGET_AND_NEST_METHODS with type 'a t := 'a t
    (* --- *)
  end


(* ---------------------------- *)
(*  Memoize a zippable FUNCTOR  *)
(* ---------------------------- *)

(* Without projections we cannot go down more than the depth of the tree: *)
module GENEALOGY_OF_FUNCTOR (F:sig  type 'a t  val zip: ('a t * 'b t) -> ('a * 'b) t  end)
 : sig
    type (_) t = Atom : 'a F.t -> 'a t | Cons : ('a * 'b) F.t * ('a t * 'b t) -> ('a * 'b) t
    (* --- *)
    val atom   : 'a F.t -> 'a t
    val cons   : ('a * 'b) F.t -> 'a t -> 'b t -> ('a * 'b) t
    (* --- *)
    val root   : 'a t -> 'a F.t
    (* --- *)
    val car    : ('a * 'b) t -> 'a t
    val cdr    : ('a * 'b) t -> 'b t
    val decons : ('a * 'b) t -> ('a * 'b) F.t * ('a t * 'b t)
    (* --- *)
    (* aliases: *)
    val product : 'a t -> 'b t -> ('a * 'b) t                          (* cons ∘ F.zip ∘ (root, root) *)
    val fst     : ('a * 'b) t -> 'a t                                  (* car    *)
    val snd     : ('a * 'b) t -> 'b t                                  (* cdr    *)
    val split   : ('a * 'b) t -> ('a t * 'b t)                         (* snd ∘ decons *)
    val combine : 'a t -> 'b t -> ('a * 'b) t                          (* product*)
    val unzip   : ('a * 'b) t -> ('a t * 'b t)                         (* snd ∘ decons *)
    val zip     : ('a t * 'b t) -> ('a * 'b) t                         (* (uncurried) product *)
  end

(* ---------------------------- *)
(*   Memoize a zippable TYPE    *)
(* ---------------------------- *)

(* Simplest case. As for `GENEALOGY_OF_FUNCTOR', we cannot go down more than the depth of the tree: *)
module GENEALOGY_OF_TYPE (V:sig  type t  val zip: t * t -> t  end)
 : sig
    type _ t = Atom : V.t -> V.t t | Cons : (V.t) * ('a t * 'b t) -> ('a * 'b) t
    (* --- *)
    val atom   : V.t -> V.t t
    val cons   : V.t -> 'a t -> 'b t -> ('a * 'b) t
    (* --- *)
    val root   : 'a t -> V.t
    (* --- *)
    val car    : ('a * 'b) t -> 'a t
    val cdr    : ('a * 'b) t -> 'b t
    val decons : ('a * 'b) t -> V.t * ('a t * 'b t)
    (* --- *)
    (* aliases: *)
    val return  : V.t -> V.t t                            (* atom   *)
    val product : 'a t -> 'b t -> ('a * 'b) t             (* cons ∘ V.zip ∘ (root, root) *)
    val fst     : ('a * 'b) t -> 'a t                     (* car    *)
    val snd     : ('a * 'b) t -> 'b t                     (* cdr    *)
    val split   : ('a * 'b) t -> ('a t * 'b t)            (* snd ∘ decons *)
    val combine : 'a t -> 'b t -> ('a * 'b) t             (* product*)
    val unzip   : ('a * 'b) t -> ('a t * 'b t)            (* snd ∘ decons *)
    val zip     : ('a t * 'b t) -> ('a * 'b) t            (* (uncurried) product *)
  end


(* ---------------------------- *)
(*          Examples            *)
(* ---------------------------- *)

(*
open Sexpr;;

let x = atom 5 ;;
(* val x : int t = Atom 5 *)

let y = atom 7 ;;
(* val y : int t = Atom 7 *)

let z = cons x y ;;
(* val z : (int * int) t = Cons (Atom 5, Atom 7) *)

car z ;;
(* - : int t = Atom 5 *)

cdr z ;;
(* - : int t = Atom 7 *)

(* ---
   Ok, now we change the products and we "memoize" them
   (we will able to restore components with `fst' (car) and `snd' (cdr)):
   --- *)

module M = Sexpr.GENEALOGY_OF_TYPE(struct type t = int  let zip (x,y) = x*y end) ;;
module M :
  sig
    type _ t = Atom : int -> int t | Cons : int * ('a t * 'b t) -> ('a * 'b) t
    val atom : int -> int t
    val cons : int -> 'a t -> 'b t -> ('a * 'b) t
    val root : 'a t -> int
    val car : ('a * 'b) t -> 'a t
    val cdr : ('a * 'b) t -> 'b t
    val decons : ('a * 'b) t -> int * ('a t * 'b t)
    val product : 'a t -> 'b t -> ('a * 'b) t
    val fst : ('a * 'b) t -> 'a t
    val snd : ('a * 'b) t -> 'b t
    val split : ('a * 'b) t -> 'a t * 'b t
    val combine : 'a t -> 'b t -> ('a * 'b) t
    val unzip : ('a * 'b) t -> 'a t * 'b t
    val zip : 'a t * 'b t -> ('a * 'b) t
  end

let x = M.atom 5 ;;
(* val x : int M.t = M.Atom 5 *)

let y = M.atom 7 ;;
(* val y : int M.t = M.Atom 7 *)

let z = M.product x y ;;
(* val z : (int * int) t = Cons (35, (Atom 5, Atom 7)) *)

let z' = M.product x y ;;
(* val z' : (int * int) M.t = M.Cons (35, (M.Atom 5, M.Atom 7)) *)

z=z', z==z';;
(* - : bool * bool = (true, false) *)

M.root z ;;
(* - : int = 35 *)

(M.fst z) = (M.fst z'), (M.fst z) == (M.fst z');;
(* - : bool * bool = (true, true) *)

let w = M.product z z ;;
(* val w : ((int * int) * (int * int)) M.t =
     M.Cons (1225, (M.Cons (35, (M.Atom 5, M.Atom 7)), M.Cons (35, (M.Atom 5, M.Atom 7)))) *)

(M.fst w) = (M.snd w), (M.fst w) == (M.snd w);;
(* - : bool * bool = (true, true) *)

M.decons w ;;
(* - : int * ((int * int) M.t * (int * int) M.t) =
    (1225, (M.Cons (35, (M.Atom 5, M.Atom 7)), M.Cons (35, (M.Atom 5, M.Atom 7)))) *)

M.decons z ;;
(* - : int * (int M.t * int M.t) = (35, (M.Atom 5, M.Atom 7)) *)

M.decons x ;; (* Type error: *)
Error: This expression has type int M.t but an expression was expected of type ('a * 'b) M.t
       Type int is not compatible with type 'a * 'b
*)
