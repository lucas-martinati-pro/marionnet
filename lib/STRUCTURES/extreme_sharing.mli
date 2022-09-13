(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2019  Jean-Vincent Loddo

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

(** Render the structural equality and the physical one equivalent.
    The main tool of this module, aka `make_weakly_memoized_identity',
    applied to all working values of a type, render the structural
    equality and the physical one equivalent:

    for all x,y. (x==y) <=> (x=y)

    Example:

    let id = Extreme_sharing.make_id ();;
    (* val id : '_a -> '_a = <fun> *)

    let x = Array.init 13 (fun i -> i*i) |> id ;;
    (* val x : int array = [|0; 1; 4; 9; 16; 25; 36; 49; 64; 81; 100; 121; 144|] *)

    let y = Array.init 13 (fun i -> i*i) |> id ;;
    (* val y : int array = [|0; 1; 4; 9; 16; 25; 36; 49; 64; 81; 100; 121; 144|] *)

    x==y;;
    (* - : bool = true *)
    ---
    This be useful to minimize the number of copies of structurally
    equivalent structures in memory. Actually, given a function f:('a -> 'b),
    we can always compose this function with a (weakly) memoized version of
    the identity idᴬ:('a -> 'a) and/or idᴮ:('b -> 'b). Hence, in three obvious
    ways:
          (1)  λx.f (idᴬ x)         "attach"
          (2)  λx.idᴮ (f x)         "co-attach"
          (3)  λx.idᴮ (f (idᴬ x))   "bi-attach"

    Behind the identity functions there are weak hash tables (based on ephemerons).
    They provides a sort of canonical representation of working values of their type
    The "first occurred" value will represent, with its address, all equivalent values
    in the sense of the structural equality (=).
    *)

type 'a identity = ('a -> 'a)

(* Make a weak hash table to detect and filter 'a copies: *)
val make_weakly_memoized_identity : ?size:int (* 0 *) -> unit -> ('a -> 'a)

(* Shorthand for `make_weakly_memoized_identity' making a weak hash table of
   initial size 0: *)
val make_id : unit -> 'a identity

(* ------------------------------------ *)
(*        Attach the mechanism of       *)
(*    sharing addresses to a fonction   *)
(* ------------------------------------ *)

(* Note: in the following tools, the optional argument ?id is provided calling
   `make_id' by default, because this behaviour is satisfactory in almost all cases.
   However, it is also interesting to share the same id function, aka the same weak
   hash table, among several functions taking and/or producing the same type of values. *)

val attach         : ?id:('a -> 'a) -> ('a -> 'b) -> 'a -> 'b                      (* f ⊢> f∘idᴬ *)
val co_attach      : ?id:('b -> 'b) -> ('a -> 'b) -> 'a -> 'b                      (* f ⊢> idᴮ∘f *)
val bi_attach_endo : ?id:('a -> 'a) -> ('a -> 'a) -> 'a -> 'a                      (* f ⊢> idᴬ∘f∘idᴬ *)
val bi_attach      : ?idA:('a -> 'a) -> ?idB:('b -> 'b) -> ('a -> 'b) -> 'a -> 'b  (* f ⊢> idᴮ∘f∘idᴬ *)

(* ------------------------------------ *)
(*         Modular memoization          *)
(*      based on physical addresses     *)
(* ------------------------------------ *)

(* Note that all the following memoization are based on physical equivalence.
   This is because, in a sense, idᴬ functions "transform" (=) into (==).
   ---
   Notation:
     (.)': f ⊢> (f)' represent the internal operator memoizing a function
                     using the physical equivalence (==)
   --- *)

(* This 2nd order tool generates 2 weak hash tables per function, the first for
   sharing (idᴬ) and the second for memoization. So, a call to the memoized
   function resulting from this tool always causes 2 calls to Hashtbl.find.
   (that's the price we pay for saving memory).
   Briefly, this tools implements:  f ⊢> (f)' ∘ idᴬ
   *)
val memoize : ?id:('a -> 'a) -> ('a -> 'b) -> 'a -> 'b

(* Like `memoize' but for the codomain. This may be specially useful if the working
   inputs are already filtered by an idᴬ function.
   Briefly, this tools implements:  f ⊢> (idᴮ ∘ f)'  *)
val co_memoize : ?id:'b identity -> ('a -> 'b) -> ('a -> 'b)

(* This 2nd order tool generates 3 weak hash tables. Two for sharing (idᴬ and idᴮ) and the
   third for memoization. Note that, calling `bi_memoize' with an argument f, the internal
   memoized function (with `==') is not f' *but* (idB ∘ f)'. In this way, both elements of
   any couple (x,y) stored in the internal weak hash table are canonical.
   Briefly, the tool implements f ⊢> (idB ∘ f)' ∘ idA .
   *)
val bi_memoize : ?idA:('a -> 'a) -> ?idB:('b -> 'b) -> ('a -> 'b) -> 'a -> 'b

(* Simply an instance of `bi_memoize' but with exactly the *same* filter idᴬ
   used for both domain and codomain.
   Briefly, the tool implements idᴬ ⊢> f ⊢> (idᴬ ∘ f)' ∘ idᴬ
*)
val bi_memoize_endo : ?id:('a -> 'a) -> ('a -> 'a) -> 'a -> 'a

(* All the tools above are implemented with this function based on ephemerons
   (see the standard module Ephemeron.K1): *)
val weakly_memoize : ?trace_faults:unit -> ?equality:('a -> 'a -> bool) (* (=) *) -> ?size:int (* 0 *) -> ('a -> 'b) -> 'a -> 'b

(* Variant with a projection function that prevent collection of 'a arguments. This may be useful to memoize functions with
   several arguments. Because these functions must be uncurried before to be memoized, their arguments are probably built
   only to call the function, then unused and collected.
   Example:

    (* val tool : string -> string list -> string *)
    let tool = String.concat

    (* val memoised_tool : string -> string list -> string *)
    let memoised_tool =
      let uncurried (sep, xs) = tool sep xs in
      let equality (sep1, xs1) (sep2, xs2) = (sep1 = sep2) && (xs1 == xs2) in
      let memo = Extreme_sharing.weakly_memoize_with_prj ~trace_faults:() ~equality ~prj:(snd) (uncurried) in
      fun sep xs -> memo (sep, xs)

    let r = memoised_tool ":" ["/bin"; "/usr/bin"; "/usr/local/bin"] ;;
    (* Extreme_sharing: weakly_memoize_with_prj: FAULT *)
    (* val r : string = "/bin:/usr/bin:/usr/local/bin" *)

    let dirs = ["/bin";"/usr/bin";"/usr/local/bin"] ;;

    let r = memoised_tool ":" dirs ;;
    (* Extreme_sharing: weakly_memoize_with_prj: FAULT *)
    (* val r : string = "/bin:/usr/bin:/usr/local/bin" *)

    let r = memoised_tool ":" dirs ;;
    (* val r : string = "/bin:/usr/bin:/usr/local/bin" *)
   *)
val weakly_memoize_with_prj : ?trace_faults:unit -> ?equality:('a -> 'a -> bool) (* (=) *) -> ?size:int (* 0 *) -> prj:('a -> 'c) -> ('a -> 'b) -> 'a -> 'b


(* ------------------------------------ *)
(*        Facilities for arrays'        *)
(*    destructors and/or constructors   *)
(* ------------------------------------ *)

(* Easy interface for arrays. *)
module Array : sig

  (* Make a weak hash table to detect internal copies in the array: *)
  val id : ?elt:('a->'a) -> unit -> ('a array) -> ('a array)

  (* Just `Array.id' cited above composed with the corresponding function: *)

  val    attach : ?elt:('a->'a) -> ('a array -> 'b) -> ('a array -> 'b)
  val co_attach : ?elt:('b->'b) -> ('a -> 'b array) -> ('a -> 'b array)
  val bi_attach : ?eltA:('a->'a) -> ?eltB:('b->'b) -> ('a array -> 'b array) -> ('a array -> 'b array)

end

(* ------------------------------------ *)
(*        Facilities for lists'         *)
(*    destructors and/or constructors   *)
(* ------------------------------------ *)

(* Easy interface for lists.
   The option ~sublists:() is really extreme! *)
module List : sig

  (* Make a weak hash table to detect copies in a list: *)
  val id : ?sublists:unit -> ?elt:'a identity -> unit -> ('a list) identity

  (* Just `List.id' cited above composed with the corresponding function: *)

  val    attach : ?sublists:unit -> ?elt:('a->'a) -> ('a list -> 'b) -> ('a list -> 'b)
  val co_attach : ?sublists:unit -> ?elt:('b->'b) -> ('a -> 'b list) -> ('a -> 'b list)
  val bi_attach : ?sublists:unit -> ?eltA:('a->'a) -> ?eltB:('b->'b) -> ('a list -> 'b list) -> ('a list -> 'b list)

end

(* General functorized interface. The module Array defined above may be viewed as an instance
   of this functor applied to the standard module Array. Instead, the module List defined above
   is more than a simple application of this functor because of the recursive nature of the list
   exploited to enhance sharing. *)
module Through : functor (M : sig  type 'a t  val map : ('a -> 'b) -> 'a t -> 'b t  end) ->
  sig
    type 'a t = 'a M.t

    val id : ?elt:'a identity -> unit -> 'a t identity

    (* Just `Through.id' cited above composed with the corresponding function: *)

    val    attach : ?elt:('a->'a) -> ('a t -> 'b) -> ('a t -> 'b)
    val co_attach : ?elt:('b->'b) -> ('a -> 'b t) -> ('a -> 'b t)
    val bi_attach : ?eltA:('a->'a) -> ?eltB:('b->'b) -> ('a t -> 'b t) -> ('a t -> 'b t)

  end

(*
-------------------------------------------------
                    Example
-------------------------------------------------

let size_of x =
    let b = Bytes.length (Marshal.to_bytes x [Marshal.Closures]) in
    (`bytes b, `Kb (b/1024), `Mb (b/(1048576)))

(* val f : int -> (int list) array
   # f 4 ;;
   - : int list array = [|[0]; [1; 0]; [2; 1; 0]; [3; 2; 1; 0]|] *)
let f x = Loop.Array.init_folding ~range:x ~init:[] (fun s j -> j::s, j::s)  ;;

let f1 = Extreme_sharing.Array.co_attach f ;;
let f2 = Extreme_sharing.Array.co_attach ~elt:(Extreme_sharing.List.id ~sublists:() ()) f ;;

let fm,  ht  = Memo.memoize_and_get_table f ;;
let f1m, ht1 = Memo.memoize_and_get_table f1 ;;
let f2m, ht2 = Memo.memoize_and_get_table f2 ;;

let make_a_structure_with g = [| g 10; g 11; g 12; g 13; g 14; g 15; g 16; g 15; g 14; g 13; g 12; g 11; g 10 |] ;;

(make_a_structure_with f) = (make_a_structure_with f1)  &&
(make_a_structure_with f) = (make_a_structure_with f2)  &&
(make_a_structure_with f) = (make_a_structure_with fm)  &&
(make_a_structure_with f) = (make_a_structure_with f1m) &&
(make_a_structure_with f) = (make_a_structure_with f2m) ;;
(* - : bool = true *)

size_of (make_a_structure_with f) ;;
size_of (make_a_structure_with f1) ;;
size_of (make_a_structure_with f2) ;;
(* (`bytes 1034, `Kb 1, `Mb 0) *)
(* (`bytes 614,  `Kb 0, `Mb 0) *)
(* (`bytes 453,  `Kb 0, `Mb 0) *)

size_of (make_a_structure_with fm) ;;
size_of (make_a_structure_with f1m) ;;
size_of (make_a_structure_with f2m) ;;
(* (`bytes 590, `Kb 0, `Mb 0) *)
(* (`bytes 446, `Kb 0, `Mb 0) *)
(* (`bytes 285, `Kb 0, `Mb 0) *)

size_of ht;;
size_of ht1;;
size_of ht2;;
(* (`bytes 854, `Kb 0, `Mb 0) *)
(* (`bytes 710, `Kb 0, `Mb 0) *)
(* (`bytes 549, `Kb 0, `Mb 0) *)

(* ====== Slimming an hash table ====== *)

let id = Extreme_sharing.Array.id ~elt:(Extreme_sharing.List.id ~sublists:() ()) () ;;
(* val id : '_a list array Extreme_sharing.identity *)

let slim ht = Hashtbl.iter (fun x y -> Hashtbl.replace ht x (id y)) ht ;;
(* val slim : ('a, int list array) Hashtbl.t -> unit *)

*)
