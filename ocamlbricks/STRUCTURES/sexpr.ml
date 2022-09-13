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

(* --- *)
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
    val return  : 'a -> 'a t                    (* atom   *)
    val product : 'a t -> 'b t -> ('a * 'b) t   (* cons   *)
    val fst     : ('a * 'b) t -> 'a t           (* car    *)
    val snd     : ('a * 'b) t -> 'b t           (* cdr    *)
    val split   : ('a * 'b) t -> 'a t * 'b t    (* decons *)
    val combine : 'a t -> 'b t -> ('a * 'b) t   (* cons   *)
    val unzip   : ('a * 'b) t -> ('a t * 'b t)  (* decons *)
    val zip     : ('a t * 'b t) -> ('a * 'b) t  (* cons (uncurried) *)
  end

(* --- *)

(* "s-expression" or "nested-list" or "nested-2D-point" or binary-"tree"-structured-data : *)
type _ t =
| Atom : 'a -> 'a t                   (* single *)
| Cons : 'a t * 'b t -> ('a * 'b) t   (* couple *)

(* Constructors:
      (1) "atom", but may be also called "singleton" or "return" or "make" or "create"
      (2) "cons", but may be also called "couple" or "product" or "combine"
      *)

let atom : type a. a -> a t = function x -> Atom(x)
let cons : type a b. a t -> b t -> (a*b) t = function x -> function y -> Cons(x,y)

(* Destructors:
      (1) "car",    but may be also called "fst" or "prj1" or "𝜋₁"
      (2) "cdr",    but may be also called "snd" or "prj2" or "𝜋₂"
      (3) "decons", but may be also called "split"
      *)

let car : type a b. (a*b) t -> a t = function Cons(x,y) -> x | Atom xy -> Atom(fst xy)
let cdr : type a b. (a*b) t -> b t = function Cons(x,y) -> y | Atom xy -> Atom(snd xy)

let decons : type a b. (a*b) t -> a t * b t = function
| Cons(x,y) -> (x,y)
| Atom(xy)  -> let (x,y) = xy in (Atom x, Atom y)

(* Make the Ocaml tuple represented by the S-expression: *)
let rec extract : type a. a t -> a = function
| Cons(x,y) -> (extract x, extract y)
| Atom(x)  -> x

let compare_extracted : 'a. ('a -> 'a -> int) -> ('a t -> 'a t -> int) = fun (compare) -> fun t1 t2 ->
 compare (extract t1) (extract t2)

let compare : ('a t -> 'a t -> int) = fun t1 t2 ->
 (*Pervasives.*)compare (extract t1) (extract t2)

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

module COMPLETE_UNZIPPABLE (U:UNZIPPABLE) = struct

  include U

  let fst = match fst with Some f -> f | None -> (* continue: *)
    fun xy -> let (x,y) = unzip xy in x

  let snd = match snd with Some f -> f | None -> (* continue: *)
    fun xy -> let (x,y) = unzip xy in y

end (* COMPLETE_UNZIPPABLE *)

module type FORGET_AND_NEST_METHODS =
   sig
    type 'a t

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
= struct
(* --- *)
module U = COMPLETE_UNZIPPABLE (U)
(* --- *)
type (_) t = Atom : 'a U.t -> 'a t | Cons : ('a t * 'b t) -> ('a * 'b) t

let atom : type a. a U.t -> a t = fun x -> Atom(x)
let cons : type a b. a t -> b t -> (a*b) t = fun x -> fun y -> Cons(x, y)

let car : type a b. (a*b) t -> a t = function Cons(x,y) -> x | Atom xy -> Atom(U.fst xy)
let cdr : type a b. (a*b) t -> b t = function Cons(x,y) -> y | Atom xy -> Atom(U.snd xy)

let decons : type a b. (a*b) t -> (a t * b t) = function
| Cons(x, y) -> (x,y)
| Atom(xy)  -> let (x,y) = U.unzip xy in (Atom x, Atom y)

let is_atom : type a. a t -> bool = function
| Atom(_) -> true
| Cons(_, _) -> false

let is_cons : type a. a t -> bool = function
| Atom(_) -> false
| Cons(_, _) -> true

let map_L : type a0 a1 b. (a0 t -> a1 t) -> (a0 * b) t -> (a1 * b) t = function f -> function
| Cons(x, y) -> Cons(f x, y)
| Atom(xy) -> let (x,y) = U.unzip xy in Cons(f (Atom x), Atom y)

let map_R : type b0 b1 a. (b0 t -> b1 t) -> (a * b0) t -> (a * b1) t = function f -> function
| Cons(x, y) -> Cons(x, f y)
| Atom(xy) -> let (x,y) = U.unzip xy in Cons(Atom x, f (Atom y))

let  forget_L = cdr
let  forget_R = car
let  forget_LL : 'a 'b 'c.(('a * 'b) * 'c) t -> ('b * 'c) t = fun x -> map_L (forget_L) x
let  forget_LR : 'a 'b 'c.(('a * 'b) * 'c) t -> ('a * 'c) t = fun x -> map_L (forget_R) x
let  forget_RL : 'a 'b 'c.('a * ('b * 'c)) t -> ('a * 'c) t = fun x -> map_R (forget_L) x
let  forget_RR : 'a 'b 'c.('a * ('b * 'c)) t -> ('a * 'b) t = fun x -> map_R (forget_R) x

let forget_LLR : ((('a * 'b) * 'c) * 'd) t -> (('a * 'c) * 'd) t = map_L (forget_LR)
(* and so on ... *)

let nest_L : 'a 'b. 'a t -> 'b t -> ('a * 'b) t = cons
let nest_R : 'a 'b. 'a t -> 'b t -> ('b * 'a) t = fun x y -> cons y x

let nest_LL : 'a 'b 'c. 'a t -> ('b * 'c) t -> (('a * 'b) * 'c) t = fun x y -> map_L (nest_L x) y
let nest_LR : 'a 'b 'c. 'b t -> ('a * 'c) t -> (('a * 'b) * 'c) t = fun x y -> map_L (nest_R x) y

let nest_RL : 'a 'b 'c. 'b t -> ('a * 'c) t -> ('a * ('b * 'c)) t = fun x y -> map_R (nest_L x) y
let nest_RR : 'a 'b 'c. 'c t -> ('a * 'b) t -> ('a * ('b * 'c)) t = fun x y -> map_R (nest_R x) y

let nest_LLR : 'a 'b 'c 'd. 'b t -> (('a * 'c) * 'd) t -> ((('a * 'b) * 'c) * 'd) t = fun x y -> map_L (nest_LR x) y
(* and so on ... *)

(* aliases: *)
let product = cons
let fst = car
let snd = cdr
let split = decons
let combine = cons
let unzip = decons
let zip (x,y) = cons x y (* (uncurried) cons *)

end (* OF_UNZIPPABLE *)


(* ---------------------------- *)
(*  Memoize a "zipped" FUNCTOR  *)
(* ---------------------------- *)

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

module COMPLETE_ZIPPED (Z:ZIPPED) = struct
  include COMPLETE_UNZIPPABLE(Z)
  let zip = Z.zip
end (* COMPLETE_ZIPPED *)


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
    include ALIASES with type 'a t := 'a t
    (* --- *)
   (* If the node is a cons, reuse the projections stored at children level to build the new products: *)
    val map_L     : ('a0 Z.t -> 'a1 Z.t) -> ('a0 t -> 'a1 t) -> ('a0 * 'b) t -> ('a1 * 'b) t
    val map_R     : ('b0 Z.t -> 'b1 Z.t) -> ('b0 t -> 'b1 t) -> ('a * 'b0) t -> ('a * 'b1) t
    (* --- *)
    include FORGET_AND_NEST_METHODS with type 'a t := 'a t
    (* --- *)
  end
= struct
(* --- *)
module Z = COMPLETE_ZIPPED (Z)
(* --- *)
type (_) t = Atom : 'a Z.t -> 'a t | Cons : ('a * 'b) Z.t * ('a t * 'b t) -> ('a * 'b) t

let atom : type a. a Z.t -> a t = fun x -> Atom(x)
let cons : type a b. (a*b) Z.t -> a t -> b t -> (a*b) t = fun xy -> fun x -> fun y -> Cons(xy, (x, y))

let car : type a b. (a*b) t -> a t = function Cons(xy, (x,y)) -> x | Atom xy -> Atom(Z.fst xy)
let cdr : type a b. (a*b) t -> b t = function Cons(xy, (x,y)) -> y | Atom xy -> Atom(Z.snd xy)

let decons : type a b. (a*b) t -> (a*b) Z.t * (a t * b t) = function
| Cons(xy, (x, y)) -> (xy, (x,y))
| Atom(xy)  -> let (x,y) = (Z.fst xy, Z.snd xy) in (xy, (Atom x, Atom y))

let root : type a. a t -> a Z.t = function
| Atom(x) -> x
| Cons(xy, _) -> xy

let is_atom : type a. a t -> bool = function
| Atom(_) -> true
| Cons(_, _) -> false

let is_cons : type a. a t -> bool = function
| Atom(_) -> false
| Cons(_, _) -> true

let mmap_L : ('a0 Z.t -> 'a1 Z.t) -> ('a0 * 'b) Z.t -> ('a1 * 'b) Z.t = fun fm -> fun xy ->
  let (mx, my) = Z.unzip xy in
  Z.zip (fm mx, my)

let mmap_R : ('b0 Z.t -> 'b1 Z.t) -> ('a * 'b0) Z.t -> ('a * 'b1) Z.t = fun fm -> fun xy ->
  let (mx, my) = Z.unzip xy in
  Z.zip (mx, fm my)

(* Reuse projections (by calling `root') stored at children level: *)
let map_L : type a0 a1 b. (a0 Z.t -> a1 Z.t) -> (a0 t -> a1 t) -> (a0 * b) t -> (a1 * b) t = fun fm -> fun ft -> function
| Cons(xy, (x, y)) -> let (mx, my) = (root x, root y)     in Cons(Z.zip (fm mx, my), (ft x, y))
| Atom(xy)         -> let (mx, my) = (Z.fst xy, Z.snd xy) in Cons(Z.zip (fm mx, my), (ft (Atom mx), Atom my))

(* Reuse projections (by calling `root') stored at children level: *)
let map_R : type b0 b1 a. (b0 Z.t -> b1 Z.t) -> (b0 t -> b1 t) -> (a * b0) t -> (a * b1) t = fun fm -> fun ft -> function
| Cons(xy, (x, y)) -> let (mx, my) = (root x, root y)     in Cons(Z.zip (mx, fm my), (x, ft y))
| Atom(xy)         -> let (mx, my) = (Z.fst xy, Z.snd xy) in Cons(Z.zip (mx, fm my), (Atom mx, ft (Atom my)))

let  forget_L = cdr
let  forget_R = car
let mforget_L = Z.snd
let mforget_R = Z.fst

let mforget_LL : (('a * 'b) * 'c) Z.t -> ('b * 'c) Z.t = mmap_L (mforget_L)
let mforget_LR : (('a * 'b) * 'c) Z.t -> ('a * 'c) Z.t = mmap_L (mforget_R)
let mforget_RL : ('a * ('b * 'c)) Z.t -> ('a * 'c) Z.t = mmap_R (mforget_L)
let mforget_RR : ('a * ('b * 'c)) Z.t -> ('a * 'b) Z.t = mmap_R (mforget_R)

let  forget_LL : 'a 'b 'c.(('a * 'b) * 'c) t -> ('b * 'c) t = fun x -> map_L (mforget_L) (forget_L) x
let  forget_LR : 'a 'b 'c.(('a * 'b) * 'c) t -> ('a * 'c) t = fun x -> map_L (mforget_R) (forget_R) x
let  forget_RL : 'a 'b 'c.('a * ('b * 'c)) t -> ('a * 'c) t = fun x -> map_R (mforget_L) (forget_L) x
let  forget_RR : 'a 'b 'c.('a * ('b * 'c)) t -> ('a * 'b) t = fun x -> map_R (mforget_R) (forget_R) x

let forget_LLR : ((('a * 'b) * 'c) * 'd) t -> (('a * 'c) * 'd) t = map_L (mforget_LR) (forget_LR)
(* and so on ... *)

let mnest_L : 'a Z.t -> 'b Z.t -> ('a * 'b) Z.t = fun mx my -> Z.zip (mx, my) (* curried zip *)
let mnest_R : 'a Z.t -> 'b Z.t -> ('b * 'a) Z.t = fun mx my -> Z.zip (my, mx) (* curried flipped zip *)

let mnest_LL : 'a 'b 'c. 'a Z.t -> ('b * 'c) Z.t -> (('a * 'b) * 'c) Z.t = fun mx my -> mmap_L (mnest_L mx) my
let mnest_LR : 'a 'b 'c. 'b Z.t -> ('a * 'c) Z.t -> (('a * 'b) * 'c) Z.t = fun mx my -> mmap_L (mnest_R mx) my
let mnest_RL : 'a 'b 'c. 'b Z.t -> ('a * 'c) Z.t -> ('a * ('b * 'c)) Z.t = fun mx my -> mmap_R (mnest_L mx) my
let mnest_RR : 'a 'b 'c. 'c Z.t -> ('a * 'b) Z.t -> ('a * ('b * 'c)) Z.t = fun mx my -> mmap_R (mnest_R mx) my

let nest_L : 'a 'b. 'a t -> 'b t -> ('a * 'b) t =
  fun x y ->
    (* Get stored values: *)
    let (mx, my) = (root x, root y) in
    cons (Z.zip (mx,my)) x y

(* nest_R = Flip.flip nest_L *)
let nest_R : 'a 'b. 'a t -> 'b t -> ('b * 'a) t =
  fun x y ->
    (* Get stored values: *)
    let (mx, my) = (root x, root y) in
    cons (Z.zip (my,mx)) y x

let nest_LL : 'a 'b 'c. 'a t -> ('b * 'c) t -> (('a * 'b) * 'c) t = fun x y -> map_L (mnest_L (root x)) (nest_L x) y
let nest_LR : 'a 'b 'c. 'b t -> ('a * 'c) t -> (('a * 'b) * 'c) t = fun x y -> map_L (mnest_R (root x)) (nest_R x) y

let nest_RL : 'a 'b 'c. 'b t -> ('a * 'c) t -> ('a * ('b * 'c)) t = fun x y -> map_R (mnest_L (root x)) (nest_L x) y
let nest_RR : 'a 'b 'c. 'c t -> ('a * 'b) t -> ('a * ('b * 'c)) t = fun x y -> map_R (mnest_R (root x)) (nest_R x) y

let nest_LLR : 'a 'b 'c 'd. 'b t -> (('a * 'c) * 'd) t -> ((('a * 'b) * 'c) * 'd) t = fun x y -> map_L (mnest_LR (root x)) (nest_LR x) y
(* and so on ... *)

(* aliases: *)
let product x y = cons (Z.zip (root x, root y)) x y
let fst = car
let snd = cdr
let split zxy = let (z, xy) = decons zxy in xy
let combine = product
let unzip = split
let zip (x,y) = product x y (* (uncurried) product *)

end (* GENEALOGY_OF_ZIPPED *)


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
= struct
(* --- *)
type (_) t = Atom : 'a F.t -> 'a t | Cons : ('a * 'b) F.t * ('a t * 'b t) -> ('a * 'b) t

let atom : type a. a F.t -> a t = fun x -> Atom(x)
let cons : type a b. (a*b) F.t -> a t -> b t -> (a*b) t = fun xy -> fun x -> fun y -> Cons(xy, (x, y))

let car : type a b. (a*b) t -> a t = function Cons(xy, (x,y)) -> x | Atom xy -> assert false
let cdr : type a b. (a*b) t -> b t = function Cons(xy, (x,y)) -> y | Atom xy -> assert false

let decons : type a b. (a*b) t -> (a*b) F.t * (a t * b t) = function
| Cons(xy, (x, y)) -> (xy, (x,y))
| Atom(xy)  -> assert false

let root : type a. a t -> a F.t = function
| Atom(x) -> x
| Cons(xy, _) -> xy

(* aliases: *)
let product x y = cons (F.zip (root x, root y)) x y
let fst = car
let snd = cdr
let split zxy = let (z, xy) = decons zxy in xy
let combine = product
let unzip = split
let zip (x,y) = product x y (* (uncurried) product *)

end (* GENEALOGY_OF_FUNCTOR *)


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
= struct
(* --- *)
type _ t = Atom : V.t -> V.t t | Cons : (V.t) * ('a t * 'b t) -> ('a * 'b) t

let atom : V.t -> V.t t = fun x -> Atom(x)
let cons : type a b. V.t -> a t -> b t -> (a*b) t = fun xy -> fun x -> fun y -> Cons(xy, (x, y))

let car : type a b. (a*b) t -> a t = function Cons(xy, (x,y)) -> x | Atom xy -> assert false
let cdr : type a b. (a*b) t -> b t = function Cons(xy, (x,y)) -> y | Atom xy -> assert false

let decons : type a b. (a*b) t -> V.t * (a t * b t) = function
| Cons(xy, (x, y)) -> (xy, (x,y))
| Atom(xy)  -> assert false

let root : type a. a t -> V.t = function
| Atom(x) -> x
| Cons(xy, _) -> xy

(* aliases: *)
let return = atom
let product x y = cons (V.zip (root x, root y)) x y
let fst = car
let snd = cdr
let split zxy = let (z, xy) = decons zxy in xy
let combine = product
let unzip = split
let zip (x,y) = product x y (* (uncurried) product *)
end (* GENEALOGY_OF_TYPE *)


(* Global aliases (this module): *)
let return = atom
let product = cons
let fst = car
let snd = cdr
let split = decons
let combine = cons
let unzip = decons
let zip (x,y) = cons x y (* (uncurried) cons *)
