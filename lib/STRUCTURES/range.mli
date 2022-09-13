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

type 'a t
 (* --- *)
 and index = int
 and card = int

(* Include the case when the range is a sequence of couples ('i * 'a): *)
val empty : 'a t

(* As for arrays, make a constant range: *)
val make  : card -> 'a -> 'a t
val makei : card -> 'a -> (index * 'a) t  (* only indexes are variable *)

(* As for arrays, make a index dependent range: *)
val init  : card -> (index -> 'a) -> 'a t
val initi : card -> (index -> 'a) -> (index * 'a) t  (* add the integer index *)
val inits : card -> 's -> ('s -> index -> 's * 'a) -> ('s * 'a) t
val initl : card -> 's -> ('s -> index -> 's * 'a) -> 'a t  (* equivalent to (map fst) ∘ inits *)

(* Include the case when the list is an associative list: *)
val of_list  : 'a list -> 'a t
val of_listi : 'a list -> (index * 'a) t (* add the integer index of the element *)

(* Include the case when the array is an associative list (i.e. when it contains couples ('i * 'a)): *)
val of_array  : 'a array -> 'a t
val of_arrayi : 'a array -> (index * 'a) t (* add the integer index of the element *)
val of_separated_arrays : 'i array -> 'a array -> ('i * 'a) t

val of_array2D  : 'a array array -> 'a t
val of_array3D  : 'a array array array -> 'a t
val of_array4D  : 'a array array array array -> 'a t
val of_array5D  : 'a array array array array array -> 'a t

(* With the location (integer indexes) of each element: *)
val of_array2Di : 'a array array -> ((index * index) * 'a) t
val of_array3Di : 'a array array array -> ((index * index * index) * 'a) t
val of_array4Di : 'a array array array array -> ((index * index * index * index) * 'a) t
val of_array5Di : 'a array array array array array -> ((index * index * index * index * index) * 'a) t

val of_string  : string -> char t
val of_stringi : string -> (index * char) t (* add the integer index of the element *)

IFDEF OCAML4_07_OR_LATER THEN
val of_seq  : 'a Seq.t -> 'a t
val of_seqi : 'a Seq.t -> (index * 'a) t
val of_hashtbl : ('i,'a) Hashtbl.t -> ('i * 'a) t
ENDIF

val singleton : 'a -> 'a t
val cons      : 'a -> 'a t -> 'a t
val of_lazy   : 'a lazy_t -> 'a t
val lazy_cons : 'a lazy_t -> 'a t -> 'a t

(* For testing/debugging. The thunk contains an internal state and
   may be applied repetitively to generate the values of the sequence.
   At the end of sequence the thunk will raise `Out_of_range'. *)
exception Out_of_range
val to_thunk : 'a t -> (unit -> 'a)

module Int : sig
    type  start = int  and  stop = int  and  step = int
    (* --- *)
    val forward   : ?verbose:unit -> ?step:int -> start:int -> stop:int -> unit -> int t
    val forwardi  : ?verbose:unit -> ?step:int -> start:int -> stop:int -> unit -> (index * int) t
    (* --- *)
    val backward  : ?verbose:unit -> ?step:int -> start:int -> stop:int -> unit -> int t
    val backwardi : ?verbose:unit -> ?step:int -> start:int -> stop:int -> unit -> (index * int) t
    (* --- *)
    (* (step≥0) => "forward"  loop (broken when value ≥ stop)
       (step<0) => "backward" loop (broken when value ≤ stop) *)
    val make  : ?verbose:unit -> (start * stop * step) -> int t
    val makei : ?verbose:unit -> (start * stop * step) -> (index * int) t
end (* Int *)

(* Type shared by modules Rational and Float: *)
type fraction = int * int

(* A little but useful module to generate float sequences by mean of fractions: *)
module Fraction : sig
  val of_float : ?decimals:int -> float -> fraction
  val to_float : fraction -> float
  val of_int   : int -> fraction
  (* --- *)
  val gcd : int -> int -> int

  val addition : fraction -> fraction -> fraction

  (* Lift the negative sign to numerator, if any *)
  val lift_sign : fraction -> fraction

  val is_not_negative : fraction -> bool

  (* Unify to the same_denominator *)
  val unify :  fraction -> fraction -> fraction * fraction

  val compare : fraction -> fraction -> int
end


module Rational : sig
    type start = fraction  and stop = fraction  and  step = fraction
    (* ---  By default step is (1, abs (snd start)) *)
    val forward   : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> fraction t
    val forwardi  : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> (index * fraction) t
    (* --- *)
    (* ---  By default step is (-1, abs (snd start)) *)
    val backward  : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> fraction t
    val backwardi : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> (index * fraction) t
    (* --- *)
    (* (step≥0) => "forward"  loop (broken when value ≥ stop)
       (step<0) => "backward" loop (broken when value ≤ stop) *)
    val make  : ?verbose:unit -> (start * stop * step) -> fraction t
    val makei : ?verbose:unit -> (start * stop * step) -> (index * fraction) t
    (* --- *)
end (* Rational *)

(* Just a mapping of Rational tools: *)
module Float : sig
    type start = fraction  and stop = fraction  and  step = fraction
    (* --- *)
    val forward   : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> float t
    val forwardi  : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> (index * float) t
    (* --- *)
    val backward  : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> float t
    val backwardi : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> (index * float) t
    (* --- *)
    (* (step≥0) => "forward"  loop (broken when value ≥ stop)
       (step<0) => "backward" loop (broken when value ≤ stop) *)
    val make  : ?verbose:unit -> (start * stop * step) -> float t
    val makei : ?verbose:unit -> (start * stop * step) -> (index * float) t
end (* Float *)

(* Just a mapping of Int tools: *)
module Char : sig
    type start = char  and stop = char  and  step = int
    (* --- *)
    (* (step≥0) => "forward"  loop (broken when value ≥ stop)
       (step<0) => "backward" loop (broken when value ≤ stop) *)
    val make  : ?verbose:unit -> (start * stop * step) -> char t
    val makei : ?verbose:unit -> (start * stop * step) -> (index * char) t
end (* Char *)

val map  : ('a -> 'b) -> 'a t -> 'b t
val mapi : ('i -> 'a -> 'b) -> ('i * 'a) t -> 'b t

val map2  : ('a -> 'b -> 'c) -> 'a t -> 'b t -> 'c t
val map2i : ('i * 'j -> 'a * 'b -> 'c) -> ('i * 'a) t -> ('j * 'b) t -> 'c t

val reindex : 'a t -> (index * 'a) t
val unindex : ('i * 'a) t -> 'a t (* map snd *)

val filter  : ('a -> bool) -> 'a t -> 'a t
val filteri : ('i -> 'a -> bool) -> ('i * 'a) t -> ('i * 'a) t

val skip  : ('a -> bool) -> 'a t -> 'a t
val skipi : ('i -> 'a -> bool) -> ('i * 'a) t -> ('i * 'a) t

(* The sequence terminates immediately when an element verify the predicate.
   This last element is removed as the rest of the sequence.
   Example:
     Range.to_list (Range.cut (fun c -> c>'B') (Range.of_list ['A'; 'B'; 'C'; 'D'])) ;;
     (* - : char list = ['A'; 'B'] *)
   *)
val cut  : ('a -> bool) -> 'a t -> 'a t
val cuti : ('i -> 'a -> bool) -> ('i * 'a) t -> ('i * 'a) t

(* The sequence terminates when an element verify the predicate but,
   not as `cut', this element is the last element in the resulting
   sequence, while the rest is cut.
   Example:
     Range.to_list (Range.break (fun c -> c>'B') (Range.of_list ['A'; 'B'; 'C'; 'D'])) ;;
     (* - : char list = ['A'; 'B'; 'C'] *)
   *)
val break  : ('a -> bool) -> 'a t -> 'a t
val breaki : ('i -> 'a -> bool) -> ('i * 'a) t -> ('i * 'a) t

val uniq       : 'a t -> 'a t
val uniqi      : ('i * 'a) t -> ('i * 'a) t (* ignoring indexes *)
val uniq_image : ('a ->'b) -> 'a t -> 'a t

val append : 'a t -> 'a t -> 'a t

(* Even sequences of different length may be combined. In this case,
   the result has the length of the shortest argument. *)
val combine  : 'a t -> 'b t -> ('a * 'b) t
val combinei : ('i * 'a) t -> ('j * 'b) t -> (('i * 'j) * ('a * 'b)) t

(* Combine as long as possible (alap).
   The result has the length of the longest sequence (instead of the shortest as with `combine').
   Example:
     let r1  = Range.of_list ['A'; 'B'; 'C'; 'D'] ;;
     let r2  = Range.of_list [ 3.14; 2.71 ]  ;;
     let r12 = Range.combine_alap r1 r2 ;;
     Range.to_list r12 ;;
     (* - : (char option * float option) list =
        [(Some 'A', Some 3.14); (Some 'B', Some 2.71); (Some 'C', None); (Some 'D', None)] *)
*)
val combine_alap  : 'a t -> 'b t -> ('a option * 'b option) t
val combine_alapi : ('i * 'a) t -> ('j * 'b) t -> (('i option * 'j option) * ('a option * 'b option)) t

val fst  : ('a * 'b) t -> 'a t
val snd  : ('a * 'b) t -> 'b t

val fsti : (('i * 'j) * ('a * 'b)) t -> ('i * 'a) t
val sndi : (('i * 'j) * ('a * 'b)) t -> ('j * 'b) t

val split  : ('a * 'b) t -> ('a t) * ('b t)
val spliti : (('i * 'j) * ('a * 'b)) t -> ('i * 'a) t * ('j * 'b) t

val twist  : ('a * 'b) t -> ('b * 'a) t
val twisti : (('i * 'j) * ('a * 'b)) t -> (('j * 'i) * ('b * 'a)) t

(* ------------------------------------------------
           Monadic operators (bind)
   ------------------------------------------------ *)

val return : 'a -> 'a t (* aka singleton *)
val bind   : 'a t -> ('a -> 'b t) -> 'b t
val bindi  : ('i * 'a) t -> ('i -> 'a -> 'b t) -> 'b t
val join   : 'a t t -> 'a t

(* ------------------------------------------------
     Nested bind (managing or ignoring indexes):
   ------------------------------------------------ *)

  (* Examples:

  let r1 = Range.of_list ['A'; 'B'; 'C'] ;;
  let r2 = Range.of_list [3.14; 2.71] ;;
  val r1 : char Range.t
  val r2 : float Range.t

  Range.to_list (Range.product r1 r2) ;;         (* product *)
  - : (char * float) list =
  [('A', 3.14); ('A', 2.71); ('B', 3.14); ('B', 2.71); ('C', 3.14); ('C', 2.71)]

  let r1 = Range.of_listi ['A'; 'B'; 'C'] ;;
  let r2 = Range.of_listi [3.14; 2.71] ;;
  val r1 : (int * char) Range.t
  val r2 : (int * float) Range.t

  Range.to_list (Range.product r1 r2) ;;         (* product *)
  - : ((int * char) * (int * float)) list =
  [((0, 'A'), (0, 3.14)); ((0, 'A'), (1, 2.71));
   ((1, 'B'), (0, 3.14)); ((1, 'B'), (1, 2.71));
   ((2, 'C'), (0, 3.14)); ((2, 'C'), (1, 2.71))]

  Range.to_list (Range.producti r1 r2) ;;        (* producti *)
  - : ((int * int) * (char * float)) list =
  [((0, 0), ('A', 3.14)); ((0, 1), ('A', 2.71));
   ((1, 0), ('B', 3.14)); ((1, 1), ('B', 2.71));
   ((2, 0), ('C', 3.14)); ((2, 1), ('C', 2.71))]

  *)

val product      : 'a t -> 'b t -> ('a * 'b) t
val dep_product  : 'a t -> ('a -> 'b t) -> ('a * 'b) t

val producti     : ('i * 'a) t -> ('j * 'b) t -> (('i * 'j) * ('a * 'b)) t
val dep_producti : ('i * 'a) t -> ('i -> 'a -> ('j * 'b) t) -> (('i * 'j) * ('a * 'b)) t

val power        : 'a t -> int -> ('a list) t
val poweri       : ('i * 'a) t -> int -> (('i list) * ('a list)) t

(* ------------------------------------------------
         Ranges of selections (Combinatorics)
   ------------------------------------------------ *)

  (* Optimized selections of k elements from a array (of n).
     Note however that a (unoptimized) variant already exists:
     (power (Range.of_array xs) k) = (Range.Selections.make ~repetitions:() ?unordered:None ~k xs) *)

  (* With or without (unbounded) repetitions, ordered or not (4 cases per function => 8 variants): *)

val of_selections  : ?repetitions:unit -> ?unordered:unit -> k:int -> 'a array -> ('a list) t
val of_selectionsi : ?repetitions:unit -> ?unordered:unit -> k:int -> ('i * 'a) array -> ('i list * 'a list) t

  (* With bounded repetitions, ordered or not (2 cases per function => 4 variants).
     Bounded variants are not optimized.
     Examples:

      Range.to_list (Range.of_bounded_selections ~k:2 [|('A',3); ('B',2); ('C',1)|]);;
      (* - : char list list = [['A'; 'A']; ['A'; 'B']; ['A'; 'C']; ['B'; 'A']; ['B'; 'B']; ['B'; 'C']; ['C'; 'A']; ['C'; 'B']] *)

      Range.to_list (Range.of_bounded_selections ~k:3 [|('A',3); ('B',2); ('C',1)|]);;
      (* - : char list list =
      [['A'; 'A'; 'A']; ['A'; 'A'; 'B']; ['A'; 'A'; 'C']; ['A'; 'B'; 'A']; ['A'; 'B'; 'B']; ['A'; 'B'; 'C']; ['A'; 'C'; 'A']; ['A'; 'C'; 'B'];
       ['B'; 'A'; 'A']; ['B'; 'A'; 'B']; ['B'; 'A'; 'C']; ['B'; 'B'; 'A']; ['B'; 'B'; 'C']; ['B'; 'C'; 'A']; ['B'; 'C'; 'B'];
       ['C'; 'A'; 'A']; ['C'; 'A'; 'B']; ['C'; 'B'; 'A']; ['C'; 'B'; 'B']] *)

      let y1 = Range.to_list (Range.of_bounded_selections ~k:3 [|('A',1); ('B',1); ('C',1); ('D',1); ('E',1) |]);;
      let y2 = Range.to_list (Range.of_selections ~k:3 [|'A'; 'B'; 'C'; 'D'; 'E'|]);;
      y1 = y2 ;;
      (* - : bool = true *)
      *)

type quantity = int

val of_bounded_selections  : ?unordered:unit -> k:int -> ('a * quantity) array -> ('a list) t
val of_bounded_selectionsi : ?unordered:unit -> k:int -> (('i * 'a) * quantity) array -> ('i list * 'a list) t

(* Alias for Range.of_selections ?unordered:None ?repetitions:None ~k:(Array.length xs) xs
   ---
   Range.to_list (Range.of_permutations [|'A'; 'B'; 'C'|]) ;;
   - : char list list = [['A'; 'B'; 'C']; ['A'; 'C'; 'B']; ['B'; 'A'; 'C']; ['B'; 'C'; 'A']; ['C'; 'A'; 'B']; ['C'; 'B'; 'A']] *)
val of_permutations : 'a array -> ('a list) t

(* Alias for Range.of_selections ~unordered:() ?repetitions:None ~k xs
   ---
   Range.to_list (Range.of_combinations 2 [|'A'; 'B'; 'C'|]) ;;
   - : char list list = [['A'; 'B']; ['A'; 'C']; ['B'; 'C']] *)
val of_combinations : k:int -> 'a array -> ('a list) t
val of_ksubsets     : k:int -> 'a array -> ('a list) t (* alias for combinations *)

(* A little more than an alias: the concatenation of ksubsets for k=1..(Array.length xs)
   ---
   Range.to_list (Range.of_subsets [|'A'; 'B'; 'C'|]) ;;
   - : char list list = [[]; ['A']; ['B']; ['C']; ['A'; 'B']; ['A'; 'C']; ['B'; 'C']; ['A'; 'B'; 'C']] *)
val of_subsets : 'a array -> ('a list) t

(* With locations:
   let ixs = Range.to_array (Range.of_listi ['A'; 'B'; 'C']) ;; (* [|(0, 'A'); (1, 'B'); (2, 'C')|] *)
   Range.to_list (Range.of_subsetsi ixs) ;;
   - : (int list * char list) list =
      [([],[]); ([0],['A']); ([1],['B']); ([2],['C']); ([0;1],['A';'B']); ([0;2],['A';'C']); ([1;2],['B';'C']); ([0;1;2],['A';'B';'C'])] *)
val of_permutationsi : ('i * 'a) array -> ('i list * 'a list) t
val of_combinationsi : k:int -> ('i * 'a) array -> ('i list * 'a list) t
val of_ksubsetsi     : k:int -> ('i * 'a) array -> ('i list * 'a list) t (* alias for of_combinationsi *)
val of_subsetsi      : ('i * 'a) array -> ('i list * 'a list) t

(* ------------------------------------------------
                 Trailing states
      (transform sequences without evaluation)
   ------------------------------------------------ *)

(* Nestable loops, specially `layer' (aka `foreach').
   ---
   This tools are interesting when some inner loops are based on state-dependent ranges.
   On the contrary, if all involved ranges are state-independent, the functions `product'
   or `dep_product' between ranges should be sufficient to do the same job.
   In other words, this module is a toolkit to create state-dependent products of ranges,
   and, at the same time, to make a fold scheme (like Array.fold or List.fold) lazy.
   ---
   Note also that the result of `layer' and `core' is of type ('s * 'b) t, which is exactly
   the type of sequenced values with "locations" ('i * 'a) t. The state 's associated
   to the main result 'b may be interpreted as a "cause" or an "origin" of this value,
   more than a "location".
   ---
   Example:
     Compute something with an unordered product of ranges (make pairs, not couples),
     avoiding pair's repetitions
     => the state s register the set of already generated pairs:

    let t =
      let r1 = Range.of_list ['A'; 'B'; 'C'] in
      let r2 = Range.of_list ['A'; 'B'; 'D'] in
      (* --- *)
      Range.Nest.layer ~range:r1 ~init:[] ~body:(fun s c1 ->
        (********** Note: r2' depend on s, which is modified in the inner and last (i.e. core) loop: **********)
        let r2' = Range.skip (fun c2 -> (List.mem (c1,c2) s) || (List.mem (c2,c1) s)) r2 in
        Range.Nest.core ~range:r2' ~init:s ~body:(fun s c2 ->
          let () = Printf.printf "Really working on (%c,%c)\n" c1 c2 in
          (c1,c2)::s, ((Char.escaped c1)^(Char.escaped c2))
          ))
    ;;

    let r = (Range.snd t) ;;
    (* val r : bytes Range.t *)

    (* Force lazy computation: *)
    Range.to_list r ;;
    (*  Really working on (A,A)
        Really working on (A,B)
        Really working on (A,D)
        Really working on (B,B)
        Really working on (B,D)
        Really working on (C,A)
        Really working on (C,B)
        Really working on (C,D)
        - : bytes list = ["AA"; "AB"; "AD"; "BB"; "BD"; "CA"; "CB"; "CD"] *)

    (* --- *)

    (* Initializing structures as lists or arrays (with Nest.init): *)
    let fibo =
      (Range.Nest.init ~range:(Range.Int.make (0,10,1)) ~init:(0,1) ~body:(fun (s0,s1) x -> let s=s0+s1 in (s1,s),s))
        |> (Range.append (Range.of_list [0;1])) |> Range.to_array ;;
    (* val fibo : int array = [|0; 1; 1; 2; 3; 5; 8; 13; 21; 34; 55; 89|] *)

    (* --- *)

    (* Mapping structures as lists or arrays (with Nest.trail or Nest.core): *)
    let cumulated_sums xs =
      (Range.Nest.trail ~range:(Range.of_array xs) ~init:0 ~body:(fun s x -> s+x))
        |> Range.to_array ~length:(Array.length xs) ;;

    (* val cumulated_sums : int array -> int array *)

    cumulated_sums [|0; 1; 1; 2; 3; 5; 8; 13; 21; 34; 55; 89|] ;;
    (* - : int array = [|0; 1; 2; 4; 7; 12; 20; 33; 54; 88; 143; 232|] *)

    let juxtapose_cumulated_sums xs =
      (Range.Nest.core ~range:(Range.of_array xs) ~init:0 ~body:(fun s x -> (s+x),x))
        |> Range.twist |> Range.to_array ~length:(Array.length xs) ;;

    (* val juxtapose_cumulated_sums : int array -> (int * int) array *)

    juxtapose_cumulated_sums [|0; 1; 1; 2; 3; 5; 8; 13; 21; 34; 55; 89|] ;;
    (* [|(0, 0); (1, 1); (1, 2); (2, 4); (3, 7); (5, 12); (8, 20); (13, 33);  (21, 54); (34, 88); (55, 143); (89, 232)|] *)
*)
module Nest : sig

  val layer  : range:'a t -> init:'s -> body:('s -> 'a -> ('s * 'b) t) -> ('s * 'b) t  (* foreach *)
  val core   : range:'a t -> init:'s -> body:('s -> 'a ->  's * 'b)    -> ('s * 'b) t
  val init   : range:'a t -> init:'s -> body:('s -> 'a ->  's * 'b)    -> 'b t         (* snd∘core *)
  val trail  : range:'a t -> init:'s -> body:('s -> 'a ->  's)         -> 's t

  val layeri : range:('i * 'a) t -> init:'s -> body:('s -> 'i -> 'a -> ('s * 'b) t) -> ('s * 'b) t  (* foreachi *)
  val corei  : range:('i * 'a) t -> init:'s -> body:('s -> 'i -> 'a ->  's * 'b)    -> ('s * 'b) t
  val initi  : range:('i * 'a) t -> init:'s -> body:('s -> 'i -> 'a ->  's * 'b)    -> 'b t         (* snd∘corei *)
  val traili : range:('i * 'a) t -> init:'s -> body:('s -> 'i -> 'a ->  's)         -> 's t

  IFDEF DOCUMENTATION_OR_DEBUGGING THEN
  (* layer (i.e. foreach) has the same type but is not stateT_bind (foreach_v2): *)
  val stateT_bind : range:'a t -> init:'s -> body:('s -> 'a -> ('s * 'b) t) -> ('s * 'b) t (* foreach_v2 *)
  ENDIF

end (* Nest *)

(* Equivalent to Nest.layer and without labels (arguments are in the same order): *)
val foreach  : 'a  t -> 's -> ('s -> 'a -> ('s * 'b) t) -> ('s * 'b) t
val foreachi : ('i * 'a) t -> 's -> ('s -> 'i -> 'a -> ('s * 'b) t) -> ('s * 'b) t

IFDEF DOCUMENTATION_OR_DEBUGGING THEN
val foreach_v2 : 'a t -> 's -> ('s -> 'a -> ('s * 'b) t) -> ('s * 'b) t (* stateT_bind *)
ENDIF

(* ------------------------------------------------
                 Fold variants
         (sequences are really traversed)
   ------------------------------------------------ *)

(* Note that "do_while" means, as usual, that the body will be executed at least once (if the range has at least one element). *)
module Fold : sig

  val wholly        : range:'a t -> init:'s -> body:('s -> 'a -> 's) -> 's

  (* Exit when (break s a) <> None, otherwise exit with the result provided by the break predicate.   *)
  val gen_while_do  : break:('s -> 'a -> 's option) -> range:'a t -> init:'s -> body:('s -> 'a -> 's) -> 's
  val gen_do_while  : break:('s -> 'a -> 's option) -> range:'a t -> init:'s -> body:('s -> 'a -> 's) -> 's

  (* Usual simplified versions (the "break" predicate become a "remain" predicate and
     it doesn't change the last state before exiting):  *)

  val while_do      : ('s -> 'a -> bool) -> range:'a t -> init:'s -> body:('s -> 'a -> 's) -> 's
  val do_while      : ('s -> 'a -> bool) -> range:'a t -> init:'s -> body:('s -> 'a -> 's) -> 's

  (* --- *)

  val whollyi       : range:('i * 'a) t -> init:'s -> body:('s -> 'i -> 'a -> 's) -> 's

  val gen_while_doi : break:('s -> 'i -> 'a -> 's option) -> range:('i * 'a) t -> init:'s -> body:('s -> 'i -> 'a -> 's) -> 's
  val gen_do_whilei : break:('s -> 'i -> 'a -> 's option) -> range:('i * 'a) t -> init:'s -> body:('s -> 'i -> 'a -> 's) -> 's

  val while_doi     : ('s -> 'i -> 'a -> bool) -> range:('i * 'a) t -> init:'s -> body:('s -> 'i -> 'a -> 's) -> 's
  val do_whilei     : ('s -> 'i -> 'a -> bool) -> range:('i * 'a) t -> init:'s -> body:('s -> 'i -> 'a -> 's) -> 's

end (* Fold *)

(* Alias for Fold.wholly *)
val fold  : range:'a t -> init:'s -> body:('s -> 'a -> 's) -> 's

(* Alias for Fold.whollyi *)
val foldi : range:('i * 'a) t -> init:'s -> body:('s -> 'i -> 'a -> 's) -> 's

(* ------------------------------------------------
              Consumers/destructors
                (fold instances)
         (=> sequences are really traversed)
   ------------------------------------------------ *)

val length : 'a t -> int

val for_all : ('a -> bool) -> 'a t -> bool
val exists  : ('a -> bool) -> 'a t -> bool

val for_alli : ('i -> 'a -> bool) -> ('i * 'a) t -> bool
val existsi  : ('i -> 'a -> bool) -> ('i * 'a) t -> bool

(* The sequences are combined. In other words, the predicate
   is tested on the domain of couples resulting from the `combine' operator,
   domain which has the length of the shortest argument. *)
val for_all2 : ('a -> 'b -> bool) -> 'a t -> 'b t -> bool
val exists2  : ('a -> 'b -> bool) -> 'a t -> 'b t -> bool

val for_all2i : ('i * 'j -> 'a * 'b -> bool) -> ('i * 'a) t -> ('j * 'b) t -> bool
val exists2i  : ('i * 'j -> 'a * 'b -> bool) -> ('i * 'a) t -> ('j * 'b) t -> bool

val to_revlist  : 'a t -> 'a list
val to_list     : 'a t -> 'a list (* List.rev ∘ to_revlist *)

val to_revlisti : ('i * 'a) t -> 'a list (* ignoring indexes *)
val to_listi    : ('i * 'a) t -> 'a list (* ignoring indexes, doing (List.rev ∘ to_revlisti) *)

val to_array    : ?length:int -> 'a t -> 'a array
val to_arrayi   : ?length:int -> ('i * 'a) t -> 'a array (* ignoring indexes *)

val to_separated_arrays : ('i * 'a) t -> 'i array * 'a array

val to_string  : ?length:int -> char t -> string
val to_stringi : ?length:int -> ('i * char) t -> string (* ignoring indexes *)

val memoize  : 'a t -> 'a t         (* of_list ∘ to_list *)
val memoizei : ('i * 'a) t -> 'a t  (* of_list ∘ to_listi *)

val reverse  : 'a t -> 'a t         (* of_list ∘ to_revlist  (=> memoized) *)
val reversei : ('i * 'a) t -> 'a t  (* of_list ∘ to_revlisti (=> memoized) *)

val last        : init:'a -> 'a t -> 'a
val last_apply  : init:'a -> ('a -> 'b) -> 'a t -> 'b

val lasti       : init:('i * 'a) -> ('i * 'a) t -> ('i * 'a)
val last_applyi : init:('i * 'a) -> ('i -> 'a -> 'b) -> ('i * 'a) t -> ('b)


(* ------------------------------------------------
                    Details
   ------------------------------------------------ *)

(*(*(*(*(*(*(*(*(*

(* --- *)


module List :
  sig
    val forward  : ?verbose:unit -> 'a list -> (index, 'a) t
    val backward : ?verbose:unit -> ?reindex:unit -> 'a list -> (index, 'a) t
  end

module Array :
  sig
    val forward  : ?verbose:unit -> 'a array -> (index, 'a) t
    val backward : ?verbose:unit -> ?reindex:unit -> 'a array -> (index, 'a) t
  end*)*)*)*)*)*)*)*)*)
