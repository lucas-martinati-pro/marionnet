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

(** Put objects of any type in a cage. With this encapsulation, any access,
    i.e. any call of a method of the inner object, is sequentialized.  *)

(* The core is simply of type (int * 'a) where the first component represent
   the revision number (revno), incremented for every access: *)
type 'a t = (int * 'a) Channel.t

(* --- *)
val create : 'a -> 'a t

(* --- *)
val revno : 'a t -> int (* after creation is 0 *)

(* ---
   Synchronous calls:
   --- *)

(* Classic (synchronous) calls, with an optional entering guard: *)

val apply   : 'a t -> ?enter:('a -> bool) -> ('a -> 'b) -> (exn, 'b) Either.t
val apply2  : 'a t -> 'b -> ?enter:('a -> 'b -> bool) -> ('a -> 'b -> 'c) -> (exn, 'c) Either.t
val apply3  : 'a t -> 'b -> 'c -> ?enter:('a -> 'b -> 'c -> bool) -> ('a -> 'b -> 'c -> 'd) -> (exn, 'd) Either.t
(* --- *)
val apply_extract  : 'a t -> ?enter:('a -> bool) -> ('a -> 'b) -> 'b
val apply2_extract : 'a t -> 'b -> ?enter:('a -> 'b -> bool) -> ('a -> 'b -> 'c) -> 'c
val apply3_extract : 'a t -> 'b -> 'c -> ?enter:('a -> 'b -> 'c -> bool) -> ('a -> 'b -> 'c -> 'd) -> 'd

(* ---
   Asynchronous calls:
   --- *)

(* These procedures are asynchronous.
   The caller doesn't wait for the result (in unit, not really interesting);
   it just gives the "order" of applying the function to another thread then
   returns immediately to its own activity.
   If an exception occurs, it is ignored: *)

val delegate  : 'a t -> ?enter:('a -> bool) -> ('a -> unit) -> unit
val delegate2 : 'a t -> 'b -> ?enter:('a -> 'b -> bool) -> ('a -> 'b -> unit) -> unit
val delegate3 : 'a t -> 'b -> 'c -> ?enter:('a -> 'b -> 'c -> bool) -> ('a -> 'b -> 'c -> unit) -> unit

(* Asynchronous call with retreivable result: *)
val future  : 'a t -> ?enter:('a -> bool) -> ('a -> 'b) -> ((exn, 'b) Either.t) Future.t
val future2 : 'a t -> 'b -> ?enter:('a -> 'b -> bool) -> ('a -> 'b -> 'c) -> ((exn, 'c) Either.t) Future.t
val future3 : 'a t -> 'b -> 'c -> ?enter:('a -> 'b -> 'c -> bool) -> ('a -> 'b -> 'c -> 'd) -> ((exn, 'd) Either.t) Future.t

(* ---
   Object-oriented interface:
   --- *)

type 'a obj = <
  apply         : 'b. ?enter:('a -> bool) -> ('a -> 'b) -> (exn, 'b) Either.t;
  apply_extract : 'b. ?enter:('a -> bool) -> ('a -> 'b) -> 'b;
  delegate      : ?enter:('a -> bool) -> ('a -> unit) -> unit;
  future        : 'b. ?enter:('a -> bool) -> ('a -> 'b) -> ((exn, 'b) Either.t) Future.t;
  (* --- *)
  revno  :  int;
  hermit : 'a t;
  >

(* --- *)
val objectify : 'a t -> 'a obj

(* Create a new cage and immediately put it in a object shell: *)
val new_obj : 'a -> 'a obj

(* --------------------
     Some basic tests
   --------------------


*)
