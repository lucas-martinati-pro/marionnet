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

(** Thread-safe weak memoization, with or without projections
    (for uncurried functions with several arguments). *)

val weakly_memoize :
  ?identifier:('a -> int) ->
  ?equality:('a -> 'a -> bool) ->
  ?size:int ->
  ?prj:('a -> 'c) ->
  ('a -> 'b) -> 'a -> 'b


(* ---------------------------- *)
(*          Examples            *)
(* ---------------------------- *)

(*
Ocamlbricks_log.enable ~level:2 () ;;

let f x = Thread.delay (Random.float 3.); let y = (Array.init 1000 (fun i -> i+x)) in let () = (Array.sort compare y) in y ;;
(* val f : int -> int array = <fun> *)

let f' = TS_memo.weakly_memoize f ;;
(* val f' : int -> int array = <fun> *)

f' 5 ;;
(*
[3751555.0]: TS_memo.get_or_compute_image: about start computation
[3751555.0]: TS_memo.get_or_compute_image: image calculated
- : int array =
[|5; 6; 7; 8; 9; 10; 11; 12; 13; 14; 15; 16; 17; 18; 19; 20; 21; 22; 23; 24; ...|]
*)

f' 5 ;;
(*
[3751555.0]: TS_memo.get_or_compute_image: image found => finished
- : int array =
[|5; 6; 7; 8; 9; 10; 11; 12; 13; 14; 15; 16; 17; 18; 19; 20; 21; 22; 23; 24; ...|]
*)

Ocamlbricks_log.enable ~level:1 () ;;

let make_100_threads_per_value_working_on_range x0 x1 =
  Array.init (x1-x0+1) (fun j ->
    Array.init 100 (fun i -> Future.make (fun () -> f' (x0+j)) ())
    ) ;;
(* val make_threads_working_on : int -> int -> int array Future.t array array *)

let ys = Array.map (Array.map Future.touch) (make_100_threads_per_value_working_on_range 13 29) ;;

Channel.print_active_bindings () ;;
(* Conjunctions: 17  Club-chains: 17  Club-related-to-unstable-conj: 0 *) (* 17 = 29-13+1 *)

Gc.full_major () ;;
(* - : unit = () *)

Channel.print_active_bindings () ;;
(* Conjunctions: 0  Club-chains: 0  Club-related-to-unstable-conj: 0 *)

(* A second time: *)
let ys = Array.map (Array.map Future.touch) (make_100_threads_per_value_working_on_range 13 29) ;;
(*
[3751555.4392]: TS_memo.get_or_compute_image: image found => finished
[3751555.4396]: TS_memo.get_or_compute_image: image found => finished
(* 1700 (= 17*100) similar lines  *)
[3751555.4721]: TS_memo.get_or_compute_image: image found => finished
val ys : int array array array =
  [|[|[|13; 14; 15; 16; 17; 18; 19; 20; 21; 22; 23; 24; 25; 26; 27; 28; 29; 30; ...|];
*)

Channel.print_active_bindings () ;;
(* Conjunctions: 0  Club-chains: 0  Club-related-to-unstable-conj: 0 *)

*)
