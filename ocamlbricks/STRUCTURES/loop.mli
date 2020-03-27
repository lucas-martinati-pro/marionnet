(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2018  Jean-Vincent Loddo

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

(** Loops as data structures, easier to nest than classic "fold" functions.

    There are some advantages to use this module:

      - the signature of all defined loops is unique (far to be the case with "fold" functions)
      - because the signature is unique, we can compose them in the style of imperative programming
        language, writing the body at the end of construction
      - the programming style remains functional (as for "fold" function), but we can use also them
        in an imperative style using unit as type for variables representing the state.
      - loops may have a "break" condition
      - when it make sense, loops have a "backward" option to change direction
      - loops (of the same type) may also be nested dynamically, i.e. with a parametric depth.
      *)

(** Notation for type variables:

   - 's represents the type of "states"  (which are updated and returned by the loop)
   - 'i represents the type of "indexes" (often the natural numbers, but the domain may be more general)
   - 'a represents the type of "values"  (given each time with indexes to the body of loop, in order to update the state)
   - 'r represents the type of "ranges"  (i.e. the structures used to generate the sequence of values)

   Basic (b), unidirectional (u), and general (g) loops ('b','u','g' of course!).
   A "general" loop may be used as a "unidirectional" one, that may be used as a "basic" one.
   *)

type ('s,'i,'a) loop  = init:'s -> ('s,'i,'a) body -> 's
 and ('s,'i,'a) body  = ('s -> 'i -> 'a -> 's)
 and ('s,'i,'a) break = ('s -> 'i -> 'a -> bool)

type ('r,'s,'i,'a) r  = range:'r -> ('s,'i,'a) loop                  (* "ranger"  : simple interface, no options, just the range (r) *)
type ('r,'s,'i,'a) u  = ?break:('s,'i,'a) break -> ('r,'s,'i,'a) r   (* "unidir"  : with option ?break, but unidirectional (u) *)
type ('r,'s,'i,'a) g  = ?backward:unit -> ('r,'s,'i,'a) u            (* "general" : general case (g), with options ?backward and ?break *)

(* ------------------------------------------------ *
    Typical loops with natural numbers as indexes,
       in their convivial interface (type `g')
 * ------------------------------------------------ *)

(** A "range" is a triple (start, stop, step).
    The semantics of a range (a,b,s), where s<>0, is :
      - the set {a+ks | k∊ℕ, a+ks < b } if a<=b and s>0, or
      - the set {a+ks | k∊ℕ, a+ks > b } if a>b  and s<0.
    Note that the second limit (b) is never included in the set.
    ---
    The semantics of a char range (a,b) is slightly different because the right limit is
    included in this case. Formally, the represented set is { chr(code(a)+k) | k∊ℕ, code(a)+k <= code(b) }.
    *)
type int_range   = ( start *  stop *  step)
 and float_range = (fstart * fstop * fstep)
 and char_range  = (cstart * cstop)
 and start       = int
 and stop        = int
 and step        = int
 and fstart      = float
 and fstop       = float
 and fstep       = float
 and cstart      = char
 and cstop       = char
 and index       = int

(*
type ('r,'s,'i,'a) g = ?backward:unit -> ?break:('s -> 'i -> 'a -> bool) -> range:'r -> init:'s -> ('s -> 'i -> 'a -> 's) -> 's

val for_int_range   : (int_range  , 's, index,   int) g
val for_float_range : (float_range, 's, index, float) g
val for_char_range  : (char_range , 's, index,  char) g
val for_array       : ('a array   , 's, index,    'a) g
val for_list        : ('a list    , 's, index,    'a) g
val for_string      : (string     , 's, index,  char) g
*)

val for_int_range   : ?backward:unit -> ?break:('s -> index -> int   -> bool) -> range:( start *  stop *  step) -> init:'s -> ('s -> index -> int   -> 's) -> 's
val for_float_range : ?backward:unit -> ?break:('s -> index -> float -> bool) -> range:(fstart * fstop * fstep) -> init:'s -> ('s -> index -> float -> 's) -> 's
val for_char_range  : ?backward:unit -> ?break:('s -> index -> char  -> bool) -> range:(cstart * cstop)         -> init:'s -> ('s -> index -> char  -> 's) -> 's

val for_array       : ?backward:unit -> ?break:('s -> index -> 'a   -> bool) -> range:'a array -> init:'s -> ('s -> index -> 'a -> 's) -> 's
val for_list        : ?backward:unit -> ?break:('s -> index -> 'a   -> bool) -> range:'a list  -> init:'s -> ('s -> index -> 'a -> 's) -> 's
val for_string      : ?backward:unit -> ?break:('s -> index -> char -> bool) -> range:string   -> init:'s -> ('s -> index -> char -> 's) -> 's

(* ------------------------------------------------ *
             Array related bounded loops
 * ------------------------------------------------ *)

(* Generalized, flipped and/or folding version of standard loops about arrays: *)
module Array : sig
  (* Alias for function `for_array', that is a generalized and flipped version of standard Array.fold_{left,right}. *)
  val fold : ?backward:unit -> ?break:('s -> index -> 'a -> bool) -> range:'a array -> init:'s -> ('s -> index -> 'a -> 's) -> 's
  (* --- *)
  val map  : range:'a array -> (index -> 'a -> 'b) -> 'b array  (* just a flipped version of the standard function Array.mapi *)
  val iter : range:'a array -> (index -> 'a -> unit) -> unit    (* just a flipped version of the standard function Array.iteri *)
  (* --- *)
  val init_folding : range:int      -> init:'s -> ('s -> index -> 'a * 's) -> 'a array
  val  map_folding : range:'a array -> init:'s -> ('s -> index -> 'a -> 'b * 's) -> 'b array
  val iter_folding : range:'a array -> init:'s -> ('s -> index -> 'a -> 's) -> unit

  (* -------------------- *
        Combinatorics
   * -------------------- *)

  type k = int

  val selections :
    ?verbose:unit ->      (* announce the number of expected loops on stderr, before to perform them *)
    (* --- *)
    ?unordered:unit ->    (* combinations (the array in the body may be viewed as a set (or multiset if repetitions are enable) ) *)
    ?repetitions:unit ->  (* with repetitions *)
    (* --- *)
    ?backward:unit ->
    ?break:('s -> index array -> 'a array -> bool) ->
    (* --- *)
    range:'a array * k -> (* n is the length of the array *)
    (* --- *)
    init:'s -> ('s -> index array -> 'a array -> 's) -> 's

end

(* ------------------------------------------------ *
             List related bounded loops
 * ------------------------------------------------ *)

(* Generalized, flipped and/or folding version of standard loops about lists: *)
module List : sig
  (* Alias for function `for_list', that is a generalized and flipped version of standard List.fold_{left,right}. *)
  val fold : ?backward:unit -> ?break:('s -> index -> 'a -> bool) -> range:'a list  -> init:'s -> ('s -> index -> 'a -> 's) -> 's
  (* --- *)
  val map  : range:'a list -> (index -> 'a -> 'b) -> 'b list (* flipped version of standard List.mapi *)
  val iter : range:'a list -> (index -> 'a -> unit) -> unit  (* flipped version of standard List.iteri *)
  (* --- *)
  val init_folding : range:int     -> init:'s -> ('s -> index -> 'a * 's) -> 'a list
  val iter_folding : range:'a list -> init:'s -> ('s -> index -> 'a -> 's) -> unit
  val  map_folding : range:'a list -> init:'s -> ('s -> index -> 'a -> 'b * 's) -> 'b list
end

(* ------------------------------------------------ *
                Unbounded loops
 * ------------------------------------------------ *)

type unbounded_int_range = (start * step)

val while_do : ?range:(start * step) (* (0,1) *) -> init:'s -> break:('s -> index -> int -> bool) -> ('s -> index -> int -> 's) -> 's
val do_while : ?range:(start * step) (* (0,1) *) -> init:'s -> break:('s -> index -> int -> bool) -> ('s -> index -> int -> 's) -> 's

(* Examples :

Loop.while_do ~range:(1,1) ~init:() ~break:(fun () j i -> true) (fun s j i -> Printf.printf "Iteration n°%02d (index %d)\n" i j) ;;
- : unit = ()

Loop.do_while ~range:(1,1) ~init:() ~break:(fun () j i -> true) (fun s j i -> Printf.printf "Iteration n°%02d (index %d)\n" i j) ;;
Iteration n°01 (index 0)
- : unit = ()

Loop.while_do ~range:(10,2) ~init:() ~break:(fun () j i -> i>16) (fun s j i -> Printf.printf "Iteration n°%02d (index %d)\n" i j) ;;
Iteration n°10 (index 0)                                                                                                                                                                                           Iteration n°12 (index 1)                                                                                                                                                                                           Iteration n°14 (index 2)
Iteration n°16 (index 3)

let xs = Loop.while_do ~range:(1,1) ~init:[] ~break:(fun _ j i -> i>10) (fun s j i -> (i*i)::s) ;;
val xs : int list = [100; 81; 64; 49; 36; 25; 16; 9; 4; 1]

*)

(* ------------------------------------------------ *
            Structure-based bounded loops
 * ------------------------------------------------ *)

(** With the following constructors, the natural end happens when the ~range function raises an exception.
    However, an additional break condition may be provided as usual. Both loops are unidirectional. *)
val for_sequence : ((index -> 'a) , 's, index, 'a) u
val for_thunk    : ((unit  -> 'a) , 's, index, 'a) u

type ('s,'a,'ta) fold1 = ('s -> 'a -> 's) -> 's -> 'ta -> 's
type ('s,'a,'b,'tab) fold2 = ('s -> 'a -> 'b -> 's) -> 's -> 'tab -> 's

val unidir_of_functor   : ('s * index, 'a, 'ta) fold1 -> ('ta,  's, index, 'a) u
val unidir_of_bifunctor : ('s * index, 'a, 'b, 'tab) fold2 -> ('tab, 's, index, 'a * 'b) u

(* Example of functor's fold conversion:
   let for_queue ?break = Loop.unidir_of_functor (Queue.fold) ?break ;; *)
val for_queue : ('a Queue.t, 's, int, 'a) u

(* Example of functor's fold conversion (requires OCaml >= 4.03):
   let for_stack ?break = Loop.unidir_of_functor (Stack.fold) ?break ;; *)
IFDEF OCAML4_03_OR_LATER THEN
val for_stack : ?break:('a -> index -> 'b -> bool) -> range:'b Stack.t -> init:'a -> ('a -> index -> 'b -> 'a) -> 'a
ENDIF

(* Example of functor's fold conversion (requires OCaml >= 4.07):
   let for_seq ?break = Loop.unidir_of_functor (Seq.fold_left) ?break ;; *)
IFDEF OCAML4_07_OR_LATER THEN
val for_seq : ('a Seq.t, 's, int, 'a) u
ENDIF

(* Example of bifunctor's fold conversion:
   let for_hashtbl ?break = Loop.unidir_of_bifunctor (fun f s t -> Hashtbl.fold (fun x y s -> f s x y) t s) ?break ;; *)
val for_hashtbl : (('k, 'a) Hashtbl.t, 's, int, 'k * 'a) u

(* Usage:
     module M = Map.Make (Ordered_type) ;;
     include Loop.Make_for_map (M) ;;
     val for_map : ('a M.t, 's, int, M.key * 'a) Loop.u *)
module Make_for_map : functor (M : Map.S) -> sig
  (* Example of bifunctor's fold conversion:
     let for_map ?break = Loop.unidir_of_bifunctor (fun f s t -> M.fold (fun x y s -> f s x y) t s) ?break ;; *)
  val for_map : ('a M.t, 's, index, M.key * 'a) u
end


(** Examples:

# List.rev (Loop.for_int_range ~range:(0,15,3) ~init:[] (fun s j x -> (j,x)::s)) ;;
- : (int * int) list = [(0, 0); (1, 3); (2, 6); (3, 9); (4, 12)]

# List.rev (Loop.for_char_range ~backward:() ~range:('a','f') ~init:[] (fun s j x -> (j,x)::s)) ;;
- : (int * char) list = [(0, 'f'); (1, 'e'); (2, 'd'); (3, 'c'); (4, 'b'); (5, 'a')]

# Loop.for_list ~range:['0';'1';'2'] ~init:[] (fun s j x -> x::s) ;;
- : char list = ['2'; '1'; '0']

# List.rev (Loop.for_sequence ~range:(fun i -> if i<10 then i*i else assert false) ~init:[] (fun s j x -> (j,x)::s)) ;;
- : (int * int) list = [(0, 0); (1, 1); (2, 4); (3, 9); (4, 16); (5, 25); (6, 36); (7, 49); (8, 64); (9, 81)]

# List.rev (Loop.for_thunk ~range:(let i = ref (-1) in fun () -> incr i; if !i<10 then (!i) * (!i) else assert false) ~init:[] (fun s j x -> (j,x)::s)) ;;
- : (int * int) list = [(0, 0); (1, 1); (2, 4); (3, 9); (4, 16); (5, 25); (6, 36); (7, 49); (8, 64); (9, 81)]

Manually nested (depth 2):
---
List.rev (Loop.for_int_range ~range:(3,0,-1) ~init:[] (fun s j1 x ->
  Loop.for_string ~range:"hello" ~init:s (fun s j2 c ->
    (x,c)::s
    ))) ;;
- : (int * char) list =
[(3, 'h'); (3, 'e'); (3, 'l'); (3, 'l'); (3, 'o');
 (2, 'h'); (2, 'e'); (2, 'l'); (2, 'l'); (2, 'o');
 (1, 'h'); (1, 'e'); (1, 'l'); (1, 'l'); (1, 'o')]


Manually nested (depth 3):
---

let ht =
  let y = Hashtbl.create 51 in
  (Hashtbl.add y "hello" "salut";  Hashtbl.add y "dog" "chien";  Hashtbl.add y "house" "maison"); y ;;

Loop.for_hashtbl ~range:ht ~init:() (fun s j (en,fr) ->
  Loop.for_string ~range:(en) ~init:() (fun s i c1 ->
    Loop.for_string ~range:(fr) ~init:() (fun s i c2 ->
      if c1<>c2 then Printf.printf "%c%c " c1 c2
    )))
;;
hs ha hl hu ht es ea el eu et ls la lu lt ls la lu lt os oa ol ou ot dc dh di de dn oc oh oi oe on gc gh
gi ge gn hm ha hi hs ho hn om oa oi os on um ua ui us uo un sm sa si so sn em ea ei es eo en - : unit = ()

(* --- *)
Loops as list constructors:

let xys =
  Loop.for_hashtbl ~range:ht ~init:[] (fun s j (en,fr) ->
    Loop.for_string ~range:(en) ~init:s (fun s i c1 ->
      Loop.for_string ~range:(fr) ~init:s (fun s i c2 ->
        if c1<>c2 then ((c1,c2)::s) else s
      )))
;;
val xys : (char * char) list =
  [('e', 'n'); ('e', 'o'); ('e', 's'); ('e', 'i'); ('e', 'a'); ('e', 'm');
   ('s', 'n'); ('s', 'o'); ('s', 'i'); ('s', 'a'); ('s', 'm'); ('u', 'n');
   ('u', 'o'); ('u', 's'); ('u', 'i'); ('u', 'a'); ('u', 'm'); ('o', 'n');
   ...
   ('e', 's'); ('h', 't'); ('h', 'u'); ('h', 'l'); ('h', 'a'); ('h', 's')]

*)

(* --------------------------------------------------- *
    Loops as data structure with the `nest' operation
 * --------------------------------------------------- *)

module Nest_s_array : sig
  val nest_r : ('r,'s,'i,'a) r -> ('r array, 's, 'i array, 'a array) u (* Note that `r' becames 'u' here *)
  val nest_u : ('r,'s,'i,'a) u -> ('r array, 's, 'i array, 'a array) u
  val nest_g : ('r,'s,'i,'a) g -> ('r array, 's, 'i array, 'a array) g

  (* ---  Just `nest_g' applied to traditional general loops:  --- *)
  val for_int_ranges   : (  int_range array, 's, index array,   int array) g
  val for_float_ranges : (float_range array, 's, index array, float array) g
  val for_char_ranges  : ( char_range array, 's, index array,  char array) g
  val for_arrays       : ( ('a array) array, 's, index array,    'a array) g
  val for_lists        : ( ('a  list) array, 's, index array,    'a array) g
  val for_strings      : (     string array, 's, index array,  char array) g
end

module Nest_s_list : sig
  val nest_r : ('r,'s,'i,'a) r -> ('r list, 's, 'i array, 'a array) u (* Note that `r' becames 'u' here *)
  val nest_u : ('r,'s,'i,'a) u -> ('r list, 's, 'i array, 'a array) u
  val nest_g : ('r,'s,'i,'a) g -> ('r list, 's, 'i array, 'a array) g

  (* ---  Just `nest_g' applied to traditional general loops:  --- *)
  val for_int_ranges   : (  int_range list, 's, index array,   int array) g
  val for_float_ranges : (float_range list, 's, index array, float array) g
  val for_char_ranges  : ( char_range list, 's, index array,  char array) g
  val for_arrays       : ( ('a array) list, 's, index array,    'a array) g
  val for_lists        : ( ('a  list) list, 's, index array,    'a array) g
  val for_strings      : (     string list, 's, index array,  char array) g
end

(* This module builds n-ary-cartesian products of a provided `range'.
   The parameter `depth' is the power (n) of the n-ary-cartesian product. *)
module Nest_s_depth : sig
  val nest_r : depth:int -> ('r,'s,'i,'a) r -> ('r, 's, 'i array, 'a array) u (* Note that `r' becames 'u' here *)
  val nest_u : depth:int -> ('r,'s,'i,'a) u -> ('r, 's, 'i array, 'a array) u
  val nest_g : depth:int -> ('r,'s,'i,'a) g -> ('r, 's, 'i array, 'a array) g

  (* ---  Just `nest_g' applied to traditional general loops:  --- *)
  val for_int_ranges   : depth:int -> (  int_range, 's, index array,   int array) g
  val for_float_ranges : depth:int -> (float_range, 's, index array, float array) g
  val for_char_ranges  : depth:int -> ( char_range, 's, index array,  char array) g
  val for_arrays       : depth:int -> (   'a array, 's, index array,    'a array) g
  val for_lists        : depth:int -> (   'a  list, 's, index array,    'a array) g
  val for_strings      : depth:int -> (     string, 's, index array,  char array) g
end

(* Example:
let unix_modalities =
  Loop.Nest_depth.for_int_ranges ~depth:3 ~range:(0,8,1) ~init:[] (fun s j x -> x::s) ;;

val unix_modalities : int array list =
  [[|7; 7; 7|]; [|7; 7; 6|]; [|7; 7; 5|]; [|7; 7; 4|]; [|7; 7; 3|];
   [|7; 7; 2|]; [|7; 7; 1|]; [|7; 7; 0|]; [|7; 6; 7|]; [|7; 6; 6|];
   [|7; 6; 5|]; [|7; 6; 4|]; [|7; 6; 3|]; [|7; 6; 2|]; [|7; 6; 1|];
   [|7; 6; 0|]; [|7; 5; 7|]; [|7; 5; 6|]; [|7; 5; 5|]; [|7; 5; 4|];
   [|7; 5; 3|]; [|7; 5; 2|]; [|7; 5; 1|]; [|7; 5; 0|]; [|7; 4; 7|];
   [|7; 4; 6|]; [|7; 4; 5|]; [|7; 4; 4|]; [|7; 4; 3|]; [|7; 4; ...|]; ...]
*)


(* Implementation details: *)
module Implementation : sig

  (* A domain is just a triple where the two first components ('backward and 'break) are optional. *)
  (* type ('backward,'break,'range) domain = ('backward option) * ('break option) * 'range *)
  type ('w,'b,'r) domain = ('w option) * ('b option) * 'r

  (* General form of a loop: *)
  (* type ('backward, 'break, 'range, 'state, 'index, 'items) t = ('backward, 'break, 'range) domain -> ('state, 'index, 'items) loop *)
  type ('w, 'b, 'r, 's, 'i, 'a) t = ('w, 'b, 'r) domain -> ('s, 'i, 'a) loop

    (* Directives for the depth-most level ('d) and for all intermediary levels ('l): *)
  type ('d,'l) nested_options = ('d option) * ('l option array) option

  (* A `nested_t' is a particular case of `t':*)
  type ('w,'b,'r,'s,'i,'a) nested_t =
    (('w,'w) nested_options, (('s, 'i array, 'a array) break, 'b) nested_options, 'r, 's, 'i array, 'a array) t

  (* General "nest" operation, managing depth-most and intermediary settings (backward/break): *)
  (* --- *)
  val nest_t_sequence : depth:int -> ('w,'b,'r,'s,'i,'a) t -> ('w,'b, int->'r ,'s,'i,'a) nested_t
  val nest_t_power    : depth:int -> ('w,'b,'r,'s,'i,'a) t -> ('w,'b,      'r ,'s,'i,'a) nested_t
  val nest_t_list     :              ('w,'b,'r,'s,'i,'a) t -> ('w,'b, 'r list ,'s,'i,'a) nested_t
  val nest_t_array    :              ('w,'b,'r,'s,'i,'a) t -> ('w,'b, 'r array,'s,'i,'a) nested_t

  (* -------------------------
        Simplified versions
     ------------------------- *)

  (* There is a single (depth-most) backward option, of type 1 (boolean argument),
     and there is a single (depth-most) break condition:
     # ---
     type ('range, 'state, 'index, 'items) s = (unit, ('state, 'index, 'items) break, 'range) domain -> ('state, 'index, 'items) loop
     # ---
     Note that the general type `g' is equivalent to the abstract one `s' but is not directly nestable.
     However, `g' is probably easier to understand than `s'. *)
  type ('r,'s,'i,'a) s = (unit, ('s, 'i, 'a) break, 'r) domain -> ('s, 'i, 'a) loop

  (* Instances of the "nest" operation obtained renouncing to intermediary backward or break settings, just using the depth-most ones: *)
  (* --- *)
  val nest_s_sequence : depth:int -> ('r,'s,'i,'a) s -> (int->'r, 's, 'i array, 'a array) s
  val nest_s_power    : depth:int -> ('r,'s,'i,'a) s -> (     'r, 's, 'i array, 'a array) s
  val nest_s_list     :              ('r,'s,'i,'a) s -> ('r list, 's, 'i array, 'a array) s
  val nest_s_array    :              ('r, 's, 'i, 'a) s -> ('r array, 's, 'i array, 'a array) s

  (* Conversions : *)

  val s_of_ranger  : ('r,'s,'i,'a) r -> ('r,'s,'i,'a) s  (* the result will ignore both options `backward' and `break' *)
  val s_of_unidir  : ('r,'s,'i,'a) u -> ('r,'s,'i,'a) s  (* the result will ignore the option `backward' *)
  val s_of_general : ('r,'s,'i,'a) g -> ('r,'s,'i,'a) s

  val s_to_ranger  : ('r,'s,'i,'a) s -> ('r,'s,'i,'a) r
  val s_to_unidir  : ('r,'s,'i,'a) s -> ('r,'s,'i,'a) u
  val s_to_general : ('r,'s,'i,'a) s -> ('r,'s,'i,'a) g

end (* Implementation *)
