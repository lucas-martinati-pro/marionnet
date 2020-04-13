(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009 2020  Jean-Vincent Loddo
   Copyright (C) 2009 2020  Université Sorbonne Paris Nord

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

(** Synchronization structure for functional/concurrent (threads) programming model.
    This structure allows an asynchronous kind of function application.

    Differently from the default [Thread], the result of the application is not lost but accessible with the primitives [touch] and [taste].
    The same holds for exceptions and their associated values: if an exception interrupts the computation, it will be re-raised
    in any thread touching or tasting the future. This behaviour makes the primitive
    [future] preferrable with respect to the standard [Thread.create] {e even} for threads providing a non interesting
    result, i.e. a result of type [unit].
    The function `fork' provide a similar tool based on a real fork, i.e. a child process, of the main process. *)

type 'a future
type 'a t = 'a future

(* ------------------------------- *)
(*      Thread-based "future"      *)
(* ------------------------------- *)

(* The underlying thread may be got with `to_thread': *)
val thread : ('a -> 'b) -> 'a -> 'b future

(* Aliases and flipped version: *)
val make   : ('a -> 'b) -> 'a -> 'b future
val make'  : 'a -> ('a -> 'b) -> 'b future

(* ------------------------------- *)
(*       Fork-based "future"       *)
(* ------------------------------- *)

type pid = int

(* This call starts two new branches of computation, which are (1) a fork of
   the main process and (2) a thread waiting for the fork termination. When
   the fork terminates, it transmits its (serialized with closures) result
   to the thread by a pipe, and the latter deliver something "touchable" to
   the main process. By default, a call to Gc.compact() is performed before
   forking. *)
val fork : ?no_compact:unit -> ('a -> 'b) -> 'a -> 'b future * pid

(* ------------------------------- *)
(*       General constructor       *)
(*    (by default thread-based,    *)
(*     ignoring pid with ~fork)   *)
(* ------------------------------- *)

val future :
  ?fork:unit ->
  ?no_compact:unit -> (* meaningfull only when ~fork is set *)
  ('a -> 'b) -> 'a -> 'b future

(* ------------------------------- *)
(*  "Touch" or "taste" the result  *)
(* ------------------------------- *)

val touch : 'a future -> 'a
val taste : 'a future -> 'a option (* None means "not ready" *)

(* Reveal exceptions including them in the result (instead of re-raising them
   when "touching" or "tasting"). The advantage of using this module is to be
   able to compose computations with the monadic operators of the Either type. *)
module Reveal : sig
  val touch : 'a future -> (exn, 'a) Either.t
  val taste : 'a future -> (exn, 'a) Either.t option
end

(* Correctly terminated (without exceptions) *)
val ready : 'a future -> bool

(* Terminated, correctly or not (by exception).
   terminated t = ((Reveal.taste t) <> None) *)
val terminated : 'a future -> bool

(* ------------------------------- *)
(*     Monadic/Comonadic stuff     *)
(* ------------------------------- *)

val bind   : ?fork:unit -> 'a future -> ('a -> 'b future) -> 'b future
val return : 'a -> 'a future

(* cobind is an instance and flipped version of `future': *)
val cobind : ?fork:unit -> 'a future -> ('a future -> 'b) -> 'b future

(* ------------------------------- *)
(*        Thread conversions       *)
(* ------------------------------- *)

val to_thread : 'a future -> Thread.t   (* get the inner thread *)
val of_thread : Thread.t -> unit future (* future (Thread.join) *)

(* ------------------------------- *)
(*      Thread/Fork control        *)
(* ------------------------------- *)

module Control : sig

  type t = pid * tid * protected_kill
   and tid = int (* current thread identifier *)
   and protected_kill = (unit -> unit)

  val make : ?pid:int -> ?kill:(unit -> unit) -> unit -> t

  (* Accessors: *)
  val get_pid : t -> pid
  val get_tid : t -> tid
  val get_protected_kill : t -> protected_kill

end (* Control *)

(* ------------------------------- *)
(*         map & map-reduce        *)
(*       programming patterns      *)
(* ------------------------------- *)

(* All are thread-based futures by default. If the ?fork option is set, it concerns internal
   computations, i.e. the "map" job, not the collection of results, i.e. the "reduce" job, which
   will be performed by a thread. *)
module List : sig
  (* List.map (future f) xs |> future (List.map touch) *)
  val map : ?fork:unit -> ('a -> 'b) -> 'a list -> ('b list) future
  (* --- *)
  (* map_reduce_list f op s0 xs  =  List.map (future f) xs |> future (List.fold_left (fun s b -> op s (touch b)) s0)  *)
  val map_reduce : ?fork:unit -> ('a -> 'b) -> ('s -> 'b -> 's) -> 's -> 'a list -> 's future
end

module Array : sig
  (* (map f xs)  =  List.map (future f) xs |> future (List.map touch) *)
  val map : ?fork:unit -> ('a -> 'b) -> 'a array -> ('b array) future
  (* --- *)
  (* (map_reduce f op s0 xs)  =  List.map (future f) xs |> future (List.fold_left (fun s b -> op s (touch b)) s0)  *)
  val map_reduce : ?fork:unit -> ('a -> 'b) -> ('s -> 'b -> 's) -> 's -> 'a array -> 's future
end


(* ------------------------------- *)
(*              Examples           *)
(* ------------------------------- *)

(*
let p = Future.List.map (fun x -> x+1) [10;20;30;40;50] ;;
val p : int list Future.t = <abstr>
Future.touch p ;;
- : int list = [11; 21; 31; 41; 51]

(* --- *)
# let p = Future.List.map_reduce (fun x -> Thread.sleep 1.; x*2) (fun s y -> s + y) 0 [10;20;30;40;50] ;;
val p : int Future.t = <abstr>
Future.touch p ;;
- : int = 300

# let p = Future.List.map_reduce (fun x -> Thread.delay 1.; x*2) (fun s y -> s + y) 0 [10;20;30;40;50] in UnixExtra.perf Future.touch p ;;
- : int * float = (300, 1.00126099586486816)

# let p = Future.List.map_reduce (fun x -> Thread.delay 5.; x*2) (fun s y -> s + y) 0 [10;20;30;40;50] in UnixExtra.perf Future.touch p ;;
- : int * float = (300, 5.00531792640686)

# let p () = List.map (fun x -> Thread.delay 5.; x*2) [10;20;30;40;50] |> List.fold_left (fun s y -> s + y) 0 in UnixExtra.perf p () ;;
- : int * float = (300, 25.0190880298614502)


# let f1 () =  Future.thread (fun x -> exp (sqrt ((sin x) *. (log x)))) 3.1415 |> Future.touch ;;
val f1 : unit -> float = <fun>

# let f2 () =  Future.fork (fun x -> exp (sqrt ((sin x) *. (log x)))) 3.1415 |> fst |> Future.touch ;;
val f2 : unit -> float = <fun>

# UnixExtra.perf f1 () ;;
- : float * float = (1.01035178555553795, 0.000257015228271484375)

# UnixExtra.perf f2 () ;;
- : float * float = (1.01035178555553795, 0.0551271438598632812)

# let f x = exp (sqrt ((sin x) *. (log x))) ;;
# let f1 () =  Future.List.map          f [3.14; 1.27; 2.54; 1.76; 1.89; 2.01 ] |> Future.touch ;;
# let f2 () =  Future.List.map ~fork:() f [3.14; 1.27; 2.54; 1.76; 1.89; 2.01 ] |> Future.touch ;;

UnixExtra.perf f1 () ;;
- : float list * float =
([1.04361326913588592; 1.61251013225855733; 2.06749154455590167; 2.10672473507443; 2.17590545777322442; 2.21423229208373185],
  0.000674009323120117188)

utop # UnixExtra.perf f2 () ;;
- : float list * float =
([1.04361326913588592; 1.61251013225855733; 2.06749154455590167; 2.10672473507443; 2.17590545777322442; 2.21423229208373185],
  0.0613539218902587891)

See tests/test_future.ml for a revenge of "forking futures".
*)
