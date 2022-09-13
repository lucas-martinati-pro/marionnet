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

(** Combinatoric selections of n elements to k places,
    ordered or unordered, with or without repetitions.
    Elements are represented by indexes, i.e. by integers
    from 0 to (n-1). *)

type n = int      (* number of elements *)
 and k = int      (* number of places *)
 and index = int  (* 0..(n-1) *)

val count : ?unordered:unit -> ?repetitions:unit -> n * k -> int
val make  : ?unordered:unit -> ?repetitions:unit -> n * k -> index list array

(* -----------------------------------
     End of relevant interface!
     The rest below are just aliases
     and implementation details:
   ----------------------------------- *)

(* Trivial `make' instances: *)

(* Selections.permutations 3 ;;
   - : index list array = [|[0; 1; 2]; [0; 2; 1]; [1; 0; 2]; [1; 2; 0]; [2; 0; 1]; [2; 1; 0]|]  *)
val permutations : n -> (index list) array     (* make ?unordered:None ?repetitions:None (n,n) *)

(* Selections.combinations (4,2) ;;
   - : index list array = [|[0; 1]; [0; 2]; [0; 3]; [1; 2]; [1; 3]; [2; 3]|] *)
val combinations : n * k -> (index list) array (* make ~unordered:()   ?repetitions:None (n,k) *)

(* Not completely trivial `make' instance:
   Selections.subsets 3 ;;
   - : int list array = [|[]; [0]; [1]; [2]; [0; 1]; [0; 2]; [1; 2]; [0; 1; 2]|] *)
val subsets : n -> (index list) array

(* Unordered bi-partitions.
   Note that, by definition, a partition doesn't contain the empty set.

   Selections.bipartitions 4 ;;
   - : (int list * int list) array =
   [| ([0], [1; 2; 3]);  ([1], [0; 2; 3]);  ([2], [0; 1; 3]);  ([3], [0; 1; 2]);
      ([0; 1], [2; 3]);  ([0; 2], [1; 3]);  ([0; 3], [1; 2])|] *)
val bipartitions : n -> (index list * index list) array

(* Unordered bi-partitions with singletons (on the left side).
   Selections.singletons_bipartitions 4 ;;
   - : (index list * index list) array = [|([0], [1; 2; 3]); ([1], [0; 2; 3]); ([2], [0; 1; 3]); ([3], [0; 1; 2])|] *)
val singletons_bipartitions : n -> (index list * index list) array

(* Unordered bi-partitions of the same length.
   Selections.half_partitions 2 ;;
   - : (index list * index list) array = [| ([0], [1]) |]

   Selections.half_partitions 6 ;;
   - : (index list * index list) array =
   [| ([0; 1; 2], [3; 4; 5]);  ([0; 1; 3], [2; 4; 5]);  ([0; 1; 4], [2; 3; 5]);  ([0; 1; 5], [2; 3; 4]);  ([0; 2; 3], [1; 4; 5]);
      ([0; 2; 4], [1; 3; 5]);  ([0; 2; 5], [1; 3; 4]);  ([0; 3; 4], [1; 2; 5]);  ([0; 3; 5], [1; 2; 4]);  ([0; 4; 5], [1; 2; 3])|] *)
val half_partitions : n (* even *) -> (index list * index list) array

(* Trivial `count' instances: *)

(* count ?unordered:None ?repetitions:None (n,n) *)
val factorial : n -> int

(* count ?unordered:None ?repetitions:None (n,k) *)
val factorial_ratio : n * k -> int   (* n!/k! (n>=k) *)

(* count ?unordered:None ~repetitions:() (n,k) *)
val int_power : n -> k -> int  (* int_power 2 10 = 1024 *)

(* count ~unordered:() ?repetitions:None (n,k) *)
val binomial : n * k -> int

(* Stirling number of the second kind,
   i.e. the number of ways to partition a set of n objects into k non-empty subsets,
   denoted by S(n,k) or {ⁿₖ} *)
val stirling2k : n  * k -> int

(* Equals to stirling2k(n,2) but calculated more efficiently with the formula: (2^(n-1) - 1): *)
val count_bipartitions : n -> int

(* binomial(n, n/2) / 2 *)
val count_half_partitions : n (* even *) -> int

(* ---- *)

module type Details =
  sig
    val count : n * k -> int
    val make  : n * k -> index list array
    (* --- *)
    (* Memoization details: *)
    val max_array_size : int
    val skip           : ?max_array_size:int (* bytes *) -> n * k -> bool
    val ht             : (n * k, index list array) Hashtbl.t
    val hashtbl_size   : unit -> [`bytes of int] * [`Kb of int] * [`Mb of int]
    val hashtbl_fill   : unit -> unit
    val hashtbl_reset  : unit -> unit
  end

module Power                  : Details  (*  ?unordered:None  ~repetitions:()    *)
module Linear_power           : Details  (*  ?unordered:None  ?repetitions:None  *)
module Unordered_power        : Details  (*  ~unordered:()    ~repetitions:()    *)
module Unordered_linear_power : Details  (*  ~unordered:()    ?repetitions:None  *)

(* val make_skip_function : count:(n * k -> int) -> max_array_size:int -> (n * k -> bool) *)


IFDEF DOCUMENTATION_OR_DEBUGGING THEN

  val test : unit -> unit

  val fill_all_ht : unit -> unit

  val stats_all_ht : unit ->
    [ `Power of Hashtbl.statistics ] *
    [ `Liner_power of Hashtbl.statistics ] *
    [ `Unordered_power of Hashtbl.statistics ] *
    [ `Unordered_linear_power of Hashtbl.statistics ]

  val size_of_all_ht : unit ->
    [ `Power of                  ([ `bytes of int ] * [ `Kb of int ] * [ `Mb of int ]) * [`max_array_size of int] ] *
    [ `Liner_power of            ([ `bytes of int ] * [ `Kb of int ] * [ `Mb of int ]) * [`max_array_size of int] ] *
    [ `Unordered_power of        ([ `bytes of int ] * [ `Kb of int ] * [ `Mb of int ]) * [`max_array_size of int] ] *
    [ `Unordered_linear_power of ([ `bytes of int ] * [ `Kb of int ] * [ `Mb of int ]) * [`max_array_size of int] ] *
    [ `TOTAL of                  ([ `bytes of int ] * [ `Kb of int ] * [ `Mb of int ]) ]

(* ---
# Selections.stats_all_ht () ;;
(`Power                  {Hashtbl.num_bindings = 0; num_buckets = 1024; max_bucket_length = 0; bucket_histogram = [|1024|]},
 `Liner_power            {Hashtbl.num_bindings = 0; num_buckets = 1024; max_bucket_length = 0; bucket_histogram = [|1024|]},
 `Unordered_power        {Hashtbl.num_bindings = 0; num_buckets = 1024; max_bucket_length = 0; bucket_histogram = [|1024|]},
 `Unordered_linear_power {Hashtbl.num_bindings = 0; num_buckets = 1024; max_bucket_length = 0; bucket_histogram = [|1024|]})

# Selections.size_of_all_ht () ;;
(`Power                  ((`bytes 1055, `Kb 1, `Mb 0), `max_array_size 4096),
 `Liner_power            ((`bytes 1055, `Kb 1, `Mb 0), `max_array_size 4096),
 `Unordered_power        ((`bytes 1055, `Kb 1, `Mb 0), `max_array_size 2048),
 `Unordered_linear_power ((`bytes 1055, `Kb 1, `Mb 0), `max_array_size 2048),
 `TOTAL                   (`bytes 4161, `Kb 4, `Mb 0))

# Selections.fill_all_ht () ;;

(`Power                  {Hashtbl.num_bindings = 572; num_buckets = 1024; max_bucket_length = 4; bucket_histogram = [|579; 341; 83; 19; 2|]},
 `Liner_power            {Hashtbl.num_bindings = 315; num_buckets = 1024; max_bucket_length = 3; bucket_histogram = [|750; 237; 33; 4|]},
 `Unordered_power        {Hashtbl.num_bindings = 633; num_buckets = 1024; max_bucket_length = 4; bucket_histogram = [|546; 351; 102; 22; 3|]},
 `Unordered_linear_power {Hashtbl.num_bindings = 633; num_buckets = 1024; max_bucket_length = 3; bucket_histogram = [|537; 363; 102; 22|]})

# Selections.size_of_all_ht () ;;
(`Power                  ((`bytes  226294, `Kb  220, `Mb 0), `max_array_size 4096),
 `Liner_power            ((`bytes  232583, `Kb  227, `Mb 0), `max_array_size 4096),
 `Unordered_power        ((`bytes  341185, `Kb  333, `Mb 0), `max_array_size 2048),
 `Unordered_linear_power ((`bytes  376477, `Kb  367, `Mb 0), `max_array_size 2048),
 `TOTAL                   (`bytes 1243707, `Kb 1214, `Mb 1))
--- *)


ENDIF
