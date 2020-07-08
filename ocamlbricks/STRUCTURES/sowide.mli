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

(** (So)rted arrays (wi)thout (d)uplicat(e)s.
    Used as of polymorphic sets, this structure offer an efficient procedure for splitting
    the array into two parts corresponding to the lower-bounds and the upper-bounds of a
    pivot value. *)

(* Similar to Set.OrderedType but for functors, i.e. parametric types: *)
module type ORDERED_FUNCTOR =
  sig
   type 'a t
   val compare : 'a t -> 'a t -> int
  end

(* Output signature: *)
module type SOWIDE =
  sig
    type 'a t
     and 'a ts = 'a t array
    (* --- *)
     and a = index
     and b = index
     and found = index
     and index = int
    (* --- *)
    val compare : 'a t -> 'a t -> int
    (* --- *)
    val make            : 'a t array -> 'a ts
    val merge           : 'a t array -> 'a t array -> 'a ts
    (* --- *)
    val mem             : ?a:index -> ?b:index -> 'a t -> 'a ts -> bool
    val find_opt        : ?a:index -> ?b:index -> 'a ts -> 'a t -> found option
    val locate          : ?a:index -> ?b:index -> 'a ts -> 'a t -> (a * b, found) Either.t
    val locate_pedantic : ?a:index -> ?b:index -> 'a ts -> 'a t -> (((a, b) Either.t, a * b) Either.t, found) Either.t
    val locate_or_split : ?a:index -> ?b:index -> 'a ts -> 'a t -> ('a ts * 'a ts, found) Either.t
    (* --- *)
    val substract : 'a ts -> 'a ts -> 'a ts

    (* Modulo a projection of elements (we suppose the array being ordered with this same projection): *)
    module With_projection : sig
      val make            : ('a -> 'b t) -> 'a array -> 'a array
      val merge           : ('a -> 'b t) -> 'a array -> 'a array -> 'a array
      val mem             : ?a:index -> ?b:index -> ('a -> 'b t) -> 'b t -> 'a array -> bool
      val find_opt        : ?a:index -> ?b:index -> ('a -> 'b t) -> 'a array -> 'b t -> found option
      val locate          : ?a:index -> ?b:index -> ('a -> 'b t) -> 'a array -> 'b t -> ((a * b), found) Either.t
      val locate_pedantic : ?a:index -> ?b:index -> ('a -> 'b t) -> 'a array -> 'b t -> (((a, b) Either.t, a * b) Either.t, found) Either.t
      val locate_or_split : ?a:index -> ?b:index -> ('a -> 'b t) -> 'a array -> 'b t -> ('a array * 'a array, found) Either.t
    end (* With_projection *)
  end

(* Make (So)rted arrays (wi)thout (d)uplicat(e)s *)
module MAKE (Type : ORDERED_FUNCTOR) : SOWIDE with type 'a t = 'a Type.t

(* Standard cases with structural and physical compare: *)
module With_structural_compare : SOWIDE with type 'a t = 'a  (* = Sowide.MAKE (struct type 'a t = 'a let compare = compare end) *)
module With_physical_compare   : SOWIDE with type 'a t = 'a  (* = Sowide.MAKE (struct type 'a t = 'a let compare = Misc.magic_physical_compare end) *)

(* With a simple type (not a functor), we can apply an hash-consing technique to make something more efficient: *)
module Type_with_structural_compare (M: sig type t end) : SOWIDE with type 'a t = M.t

(* Examples:

module M = Sowide.MAKE (struct type 'a t = int let compare = compare end) ;;

M.locate [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (50) ;;
(* - : (int * int, int) Either.t = Either.Right 5 *)

M.locate [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (500) ;;
(* - : (int * int, int) Either.t = Either.Left (8, 9) *)

M.locate [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (5000) ;;
(* - : (int * int, int) Either.t = Either.Left (9, 9) *)

M.locate_or_split [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (5000) ;;
(* - : (int array * int array, int) Either.t = Either.Left ([|0; 10; 20; 30; 40; 50; 60; 70; 100; 1000|], [||]) *)

M.locate_or_split [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (500) ;;
(* - : (int array * int array, int) Either.t = Either.Left ([|0; 10; 20; 30; 40; 50; 60; 70; 100|], [|1000|]) *)

M.locate_or_split [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (50) ;;
(* - : (int array * int array, int) Either.t = Either.Right 5 *)

M.locate_or_split [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (51) ;;
(* - : (int array * int array, int) Either.t = Either.Left ([|0; 10; 20; 30; 40; 50|], [|60; 70; 100; 1000|]) *)

(* --- *)

let l = [50] in Sowide.With_structural_compare.locate [| [0]; [10]; [20]; [30]; [40]; [50]; [60]; [70]; [100]; [1000] |] (l) ;;
(* - : (int * int, int) Either.t = Either.Right 5 *)

let l = [50] in Sowide.With_physical_compare.locate [| [0]; [10]; [20]; [30]; [40]; [50]; [60]; [70]; [100]; [1000] |] (l) ;;
(* - : (int * int, int) Either.t = Either.Left (0, 0) *)

let l = [50] in let module S = Sowide.With_structural_compare in
  S.find_opt (S.make [| [0]; [10]; [20]; [30]; [40]; l; [60]; [70]; [100]; [1000] |]) ([50]) ;;
(* - : int option = Some 5 *)

let l = [50] in let module S = Sowide.With_structural_compare in
  S.find_opt (S.make [| [0]; [10]; [20]; [30]; [40]; l; [60]; [70]; [100]; [1000] |]) (l) ;;
(* - : int option = Some 5 *)

let l = [50] in let module S = Sowide.With_physical_compare in
  S.find_opt (S.make [| [0]; [10]; [20]; [30]; [40]; l; [60]; [70]; [100]; [1000] |]) ([50]) ;;
(* - : int option = None *)

let l = [50] in let module S = Sowide.With_physical_compare in
  S.find_opt (S.make [| [0]; [10]; [20]; [30]; [40]; l; [60]; [70]; [100]; [1000] |]) (l) ;;
(* - : int option = Some 0 *)

(* Note that `l' is found at index 0 because importing the array with the new order (S.make),
   we cause a re-ordering based on physical identifiers: *)
let l = [50] in let module S = Sowide.With_physical_compare in
  (S.make [| [0]; [10]; [20]; [30]; [40]; l; [60]; [70]; [100]; [1000] |]) ;;
(* - : int list array = [|[50]; [1000]; [100]; [70]; [60]; [40]; [30]; [20]; [10]; [0]|] *)

let l = [50] in let module S = Sowide.With_physical_compare in
  S.find_opt (S.make [| [0]; [10]; l; [30]; [40]; l; [60]; [70]; l; [1000] |]) (l) ;;
(* - : int option = Some 0 *)

let l = [50] in let module S = Sowide.With_physical_compare in
  (S.make [| [0]; [10]; l; [30]; [40]; l; [60]; [70]; l; [1000] |]) ;;
(* - : int list array = [|[50]; [1000]; [70]; [60]; [40]; [30]; [10]; [0]|] *)

let l = [50] in let module S = Sowide.With_physical_compare in
  (S.make [| l; l; l; [30]; l; l; l; l; l; |]) ;;
(* - : int list array = [|[50]; [30]|] *)

*)
