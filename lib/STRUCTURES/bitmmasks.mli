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


(** Efficient operations on multisets of natural numbers (indexes) based on bitmasks.
    The equality test between two multisets is specially efficient. *)

(* Stratified bitmasks. The length of the array is the maximum multiplicity in the multiset. *)
type t = Bitmasks.t array
 and multiplicity = int
 and dim          = int (* maximal cardinality of the support set *)
 and index        = int

val empty     : ?dim:int -> unit -> t
val singleton : ?dim:int -> index -> t

val add : index -> t -> t  (* add a *single* occurrence of the index *)
val mem : index -> t -> bool
val mul : index -> t -> multiplicity

val remove : index -> t -> t (* DA TESTARE MEGLIO!!!!!!!!!*)

val of_list : ?dim:int -> index list -> t
val to_list : t -> index list

(* The multiset is defined by the index multiplicity: *)
val of_multiplicities : ?dim:int (* Array.length *) -> multiplicity array -> t

val is_empty : t -> bool
val subset  : t -> t -> bool (* set (support) inclusion *)
val submset : t -> t -> bool (* multiset inclusion *)

(* None means "incomparable", (Some 0) means "equals", (Some (-1)) means "submset", (Some 1) means "supermset" *)
val compare : t -> t -> int option

val dim : t -> dim (* dim = (length t.(0)) * Bitmasks.dpi *)
val support : t -> Bitmasks.t (* t.(0) *)

(* Examples:

Bitmmasks.of_list [] ;;
(* - : Bitmmasks.t = [|[|0|]|] *)

Bitmmasks.of_list [10;] ;;
(* - : Bitmmasks.t = [|[|1024|]|] *)

Bitmmasks.of_list [10; 10] ;;
(* - : Bitmmasks.t = [|[|1024|]; [|1024|]|]  *)

Bitmmasks.of_list [10; 10; 10; 0 ] ;;
(* - : Bitmmasks.t = [|[|1025|]; [|1024|]; [|1024|]|] *)

Bitmmasks.of_list' [10; 10; 10; 0; 1; 2; ] ;;
(* - : Bitmmasks.t = [|[|1031|]; [|1024|]; [|1024|]|] *)

let s = Bitmmasks.of_list [10; 20; 30; 10; 10; 20] ;;
(* val s : Bitmmasks.t = [|[|1074791424|]; [|1049600|]; [|1024|]|] *)

Bitmmasks.mem 10 s ;;
(* - : bool = true *)

Bitmmasks.mem 40 s ;;
(* - : bool = false *)

Bitmmasks.mul 10 s ;;
(* - : int = 3  *)

Bitmmasks.mul 20 s ;;
(* - : int = 2  *)

let s1 = Bitmmasks.add 20 s ;;
(* val s1 : Bitmmasks.t = [|[|1074791424|]; [|1049600|]; [|1049600|]|] *)

Bitmmasks.mul 20 s1 ;;
(* - : int = 3 *)

s1 = s ;;
(* - : bool = false *)

let s2 = Bitmmasks.remove 20 s1 ;;
(* val s2 : Bitmmasks.t = [|[|1074791424|]; [|1049600|]; [|1024|]|] *)

s2 = s ;;
(* - : bool = true   *)

Bitmmasks.to_list s ;;
(* - : int list = [10; 20; 30; 10; 20; 10] *)

Bitmmasks.to_list s1 ;;
(* - : int list = [10; 20; 30; 10; 20; 10; 20] *)

*)
