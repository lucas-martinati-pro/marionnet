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

(** Thread-safe deferred computations as algebraic channels. *)

type 'a t = ('a core) Channel.t
 and 'a core

(* Constructors: *)

val create    : (unit -> 'a) -> 'a t
val from_fun  : (unit -> 'a) -> 'a t (* alias for `make' *)

(* Methods:
   See: https://caml.inria.fr/pub/docs/manual-ocaml/libref/Lazy.html *)

(* Note that, applied to disjunctions, the methods `force' and `force_opt'
   are by default non-deterministic, which means that the choice of the internal
   structure that will be forced in unpredictable. However, the option ?reuse allows
   the user to determine and reuse the same forced component, if any.
   Note that the usage of ?reuse gives something better than the code fragment:

     (if Lazynel.is_unforced t then Lazynel.force t else Lazynel.wait t)

   because with ~reuse:() the structure is accessed once, while with this
   fragment is accessed twice and, worst, the unicity of the component that will
   be forced cannot be guaranteed (which is the case with ~reuse:()).
   --- *)
val force     : ?reuse:unit -> 'a t -> 'a         (* raises again the exception, if any *)
val force_opt : ?reuse:unit -> 'a t -> 'a option  (* notifies the exception, if any, with None *)
(* --- *)

val is_val      : 'a t -> bool     (* disjunctive-meaning: ∃ *)
val is_forced   : 'a t -> bool     (* disjunctive-meaning: ∃ *)
val is_unforced : 'a t -> bool     (* disjunctive-meaning: ∀ *)

(* Concurrency-related tools: *)

(* Wait until someone, other than the current thread, forces the value: *)
val wait     : 'a t -> 'a          (* raise again the exception, if any *)
val wait_opt : 'a t -> 'a option   (* notify the exception, if any, with None *)

(* Get the status of the channel (None stands for unforced). In case of disjunction,
   the meaning is the maximal status (with the natural order unforced <= forced):
   *)
val taste : 'a t -> ((exn, 'a) Either.t) option (* disjunctive-meaning: max *)


(* --- Examples:

(* ------------------- *)
(*    Simple usage     *)
(* ------------------- *)

let f x () = Misc.pr "Executing f(%d) ...\n" x; Thread.delay (Random.float 3.); let y = (Array.init 1000 (fun i -> i+x)) in let () = (Array.sort compare y) in y ;;
(* val f : int -> unit -> int array *)

let y = Lazynel.create (f 5) ;;
(* val y : int array Lazynel.t *)

Lazynel.force y ;;
(*
Executing f(5) ...
- : int array =
[|5; 6; 7; 8; 9; 10; 11; 12; 13; 14; 15; 16; 17; 18; 19; 20; 21; 22; 23; 24; ...|]
*)

Lazynel.force y ;;
(*
- : int array =
[|5; 6; 7; 8; 9; 10; 11; 12; 13; 14; 15; 16; 17; 18; 19; 20; 21; 22; 23; 24; ...|]
*)

(* ------------------- *)
(*  Raising exception  *)
(* ------------------- *)

let y = Lazynel.create (fun () -> let y = f 42 () in (invalid_arg (string_of_int y.(3)))) ;;
Lazynel.force y ;;
(*
[70155.0]: Lazynel.force: about start computation
[70155.0]: Lazynel.force: value calculated
Exception: Invalid_argument "45".
*)

Lazynel.force y ;;
(*
Executing f(42) ...
Exception: Invalid_argument "45".
*)

Lazynel.taste y ;;
(* - : (exn, '_a) Either.t option = Some (Either.Left (Invalid_argument "45")) *)

Lazynel.is_val y ;;
(* - : bool = false *)

Lazynel.is_forced y ;;
(* - : bool = true *)

Lazynel.wait y ;;
(* Exception: Invalid_argument "45". *)

Lazynel.wait_opt y ;;
(* - : '_a option = None *)

(* ---
   Redefine y and start a thread that waits on lazy value without forcing it:
   --- *)

let y = Lazynel.create (fun () -> let y = f 51 () in (invalid_arg (string_of_int y.(3)))) ;;

let g = Future.make (fun () -> Lazynel.wait y) () ;;
(*
val g : '_a Future.t = <abstr>
[188834.1]: Lock: ACQUIRED CLUB #219 at level 0
[188834.1]: Lock: RELEASED CLUB #219 at level 0
[188834.1]: Lock: ACQUIRED CLUB #224 at level 1
[188834.1]: Lock: RELEASED CLUB #224 at level 1 (WAITING FOR AN EVENT)
*)

Lazynel.force y ;;
(*
[188834.0]: Lock: ACQUIRED CLUB #219 at level 1
Executing f(51) ...
[188834.0]: Lock: RELEASED CLUB #219 at level 1
Exception: Invalid_argument "54".
Raised at file "STRUCTURES/either.ml", line 88, characters 13-20
[188834.2]: Lock: ACQUIRED CLUB #224 at level 2 (* <= guardian (188834.2) *)
[188834.2]: Lock: RELEASED CLUB #224 at level 2
[188834.1]: Lock: RELEASED CLUB #224 at level 1
[188834.1]: Lock: ACQUIRED CLUB #219 at level 0
[188834.1]: Lock: RELEASED CLUB #219 at level 0
*)

Future.taste g ;;
(* Exception: Invalid_argument "54". *)

Future.touch g ;;
(* Exception: Invalid_argument "54". *)

(* ---------------------- *)
(*  Multiple competitors  *)
(* ---------------------- *)

module Log = Ocamlbricks_log ;;
Log.enable ~level:3 () ;;

let square x () = let () = Log.printf1 "Executing square(%d) - It'll take about five seconds...\n" x in let () = Thread.delay 5. in x*x ;;
let y = Lazynel.create (square 5) ;;

(* --- *)
begin
let _f1 = Future.make (fun () -> let r = Lazynel.wait  y in Log.printf1 "future f1: result of wait:  %d\n" r) () in
let _f2 = Future.make (fun () -> let r = Lazynel.force y in Log.printf1 "future f2: result of force: %d\n" r) () in
let _f3 = Future.make (fun () -> let r = Lazynel.force y in Log.printf1 "future f3: result of force: %d\n" r) () in
let r1 = Lazynel.is_val y in let () = Log.printf1 "Main thread: is_val: %b\n" r1 in
let r2 = Lazynel.wait   y in let () = Log.printf1 "Main thread: result of wait: %d\n" r2 in
let r3 = Lazynel.is_val y in let () = Log.printf1 "Main thread: is_val: %b\n" r3 in
()
end;;
(*
[337479.0]: Main thread: is_val: false
[337479.2]: Executing square(5) - It'll take about five seconds...
[337479.0]: Lock: RELEASED CLUB #210 at level 1 (WAITING FOR AN EVENT)
[337479.1]: Lock: RELEASED CLUB #204 at level 1 (WAITING FOR AN EVENT)
[337479.3]: Lock: RELEASED CLUB #213 at level 1 (WAITING FOR AN EVENT)
[337479.2]: future f2: result of force: 25
[337479.3]: Lock: WOKEN UP by an event about CLUB #213 at level 1
[337479.0]: Lock: WOKEN UP by an event about CLUB #210 at level 1
[337479.1]: Lock: WOKEN UP by an event about CLUB #204 at level 1
[337479.3]: future f3: result of force: 25
[337479.0]: Main thread: result of wait: 25
[337479.1]: future f1: result of wait:  25
[337479.0]: Main thread: is_val: true
- : unit = ()
*)

(* --- *)

Channel.print_active_bindings () ;;
(* Conjunctions: 1  Club-chains: 1  Club-related-to-unstable-conj: 0 *)

let y = "hello";;

Gc.full_major () ;;
(* - : unit = () *)

Channel.print_active_bindings () ;;
(* Conjunctions: 0  Club-chains: 0  Club-related-to-unstable-conj: 0 *)


(* ---------------------- *)
(*  Channel compositions  *)
(* ---------------------- *)

module Log = Ocamlbricks_log ;;

let square x () = let () = Log.printf1 "Executing square(%d) - It'll take about five seconds...\n" x in let () = Thread.delay 5. in x*x ;;
let y1 = Lazynel.create (square 5) ;;
let y2 = Lazynel.create (square 7) ;;
let y3 = Lazynel.create (square 9) ;;
let y = Channel.list_sum [y1; y2; y3] ;;

Lazynel.is_val y ;;
(* - : bool = false *)

let _f = Future.make (fun () -> let r = Lazynel.wait y in Log.printf1 "future f: result of wait: %d\n" r) () ;;
(*
[337479.8]: Lock: ACQUIRED CLUB #224 at level 0
[337479.8]: Lock: RELEASED CLUB #224 at level 0
[337479.8]: Lock: ACQUIRED CLUB #228 at level 0
[337479.8]: Lock: RELEASED CLUB #228 at level 0
[337479.8]: Lock: ACQUIRED CLUB #232 at level 0
[337479.8]: Lock: RELEASED CLUB #232 at level 0
[337479.8]: Lock: ACQUIRED CLUB #241 at level 1
[337479.8]: Lock: RELEASED CLUB #241 at level 1 (WAITING FOR AN EVENT)
*)

Lazynel.force y ;;
(*
[337479.0]: Executing square(7) - It'll take about five seconds...
[337479.8]: Lock: WOKEN UP by an event about CLUB #241 at level 1
[337479.8]: Lock: RELEASED CLUB #241 at level 1 (WAITING FOR AN EVENT)
- : int = 49
[337479.8]: Lock: WOKEN UP by an event about CLUB #241 at level 1
[337479.8]: future f: result of wait:  49
*)

Lazynel.is_val y ;;
(*
[337479.0]: Lock: ACQUIRED CLUB #224 at level 0
[337479.0]: Lock: RELEASED CLUB #224 at level 0
[337479.0]: Lock: ACQUIRED CLUB #228 at level 0
[337479.0]: Lock: RELEASED CLUB #228 at level 0
[337479.0]: Lock: ACQUIRED CLUB #232 at level 0
[337479.0]: Lock: RELEASED CLUB #232 at level 0
- : bool = true
*)

Lazynel.taste y ;;
(*
[468012.0]: Lock: ACQUIRED CLUB #199 at level 0
[468012.0]: Lock: RELEASED CLUB #199 at level 0
[468012.0]: Lock: ACQUIRED CLUB #203 at level 0
[468012.0]: Lock: RELEASED CLUB #203 at level 0
[468012.0]: Lock: ACQUIRED CLUB #207 at level 0
[468012.0]: Lock: RELEASED CLUB #207 at level 0
- : (exn, int) Either.t option = Some (Either.Right 25)
*)

(* Guarded methods, as well as fold-based, have a
   predictible behaviour: *)

Lazynel.wait y ;;
(*
[337479.0]: Lock: ACQUIRED CLUB #224 at level 0
[337479.0]: Lock: RELEASED CLUB #224 at level 0
- : int = 49
*)

Lazynel.wait y ;;
(*
[337479.0]: Lock: ACQUIRED CLUB #232 at level 0
[337479.0]: Lock: RELEASED CLUB #232 at level 0
[337479.0]: Lock: ACQUIRED CLUB #224 at level 0
[337479.0]: Lock: RELEASED CLUB #224 at level 0
- : int = 49
*)

Lazynel.wait y ;;
(*
[337479.0]: Lock: ACQUIRED CLUB #224 at level 0
[337479.0]: Lock: RELEASED CLUB #224 at level 0
- : int = 49
*)

Lazynel.wait y ;;
(*
[337479.0]: Lock: ACQUIRED CLUB #228 at level 0
[337479.0]: Lock: RELEASED CLUB #228 at level 0
[337479.0]: Lock: ACQUIRED CLUB #232 at level 0
[337479.0]: Lock: RELEASED CLUB #232 at level 0
[337479.0]: Lock: ACQUIRED CLUB #224 at level 0
[337479.0]: Lock: RELEASED CLUB #224 at level 0
- : int = 49
*)

Lazynel.force ~reuse:() y ;;
(* - : int = 81 *)

Lazynel.force ~reuse:() y ;;
(* - : int = 81 *)

(* If you don't set ~reuse, we have a non-deterministic access: *)
Lazynel.force y ;;
(* - : int = 25 *)

*)
