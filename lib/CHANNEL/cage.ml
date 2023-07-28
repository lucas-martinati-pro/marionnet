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
(* val create : 'a -> 'a t *)
let create x = Channel.create (0,x)

(* --- *)
module EitherExtra = struct
  let protect f x = try Either.Right (f x) with e -> Either.Left e
  let extract_or_raise = function Either.Right y -> y | Either.Left e  -> raise e
end

(* An extract of channel.mli:
   ---
   val access :
     ?level:int -> ?ephemeral:unit -> ?enter:('a -> bool) -> ?notify:int list -> ?update:('a -> 'a) -> ?leave:('a -> bool) ->
     'a t -> ('a -> 'a -> 'b) -> 'b
   ---
   (* Read-only specialization of `access', without update (and without ?level (reader) and ?notify (nobody)): *)
   val access_ro : ?enter:('a -> bool) -> ?leave:('a -> bool) -> 'a t -> ('a -> 'b) -> 'b
   ---
*)

(* val revno : 'a t -> int (* after creation is 0 *) *)
let revno (t:'a t) : int =
  Channel.access_ro (t) fst

(* ---
   Synchronous calls:
   --- *)

(* Classic (synchronous) calls, with an optional entering guard: *)

(* val apply : 'a t -> ?enter:('a -> bool) -> ('a -> 'b) -> (exn, 'b) Either.t *)
let apply (t:'a t) ?enter f =
  Channel.access
    ~level:(Channel.writer)
    ?enter:(Option.map (fun g -> fun (_,x) -> g x) enter)
    (* The revno is updated; the hermit remains the same object (of course): *)
    ~update:(fun (i,x) -> (i+1, x))
    (t)
    (* --- *)
    (fun (_,x0) _ -> EitherExtra.protect f x0)

(* val apply2  : 'a t -> 'b -> ?enter:('a -> 'b -> bool) -> ('a -> 'b -> 'c) -> (exn, 'c) Either.t *)
let apply2 (t:'a t) y ?enter f =
  apply t ?enter:(Option.map (fun g -> fun x -> g x y) enter) (fun x -> f x y)

(* val apply3  : 'a t -> 'b -> 'c -> ?enter:('a -> 'b -> 'c -> bool) -> ('a -> 'b -> 'c -> 'd) -> (exn, 'd) Either.t *)
let apply3 (t:'a t) y z ?enter f =
  apply t ?enter:(Option.map (fun g -> fun x -> g x y z) enter) (fun x -> f x y z)

(* val apply_extract  : 'a t -> ?enter:('a -> bool) -> ('a -> 'b) -> 'b *)
let apply_extract (t:'a t) ?enter f = apply t ?enter f |> EitherExtra.extract_or_raise
(* --- *)
(* val apply2_extract : 'a t -> 'b -> ?enter:('a -> 'b -> bool) -> ('a -> 'b -> 'c) -> 'c *)
let apply2_extract (t:'a t) y ?enter f = apply2 t y ?enter f |> EitherExtra.extract_or_raise
(* --- *)
(* val apply3_extract : 'a t -> 'b -> 'c -> ?enter:('a -> 'b -> 'c -> bool) -> ('a -> 'b -> 'c -> 'd) -> 'd *)
let apply3_extract (t:'a t) y z ?enter f = apply3 t y z ?enter f |> EitherExtra.extract_or_raise

(* ---
   Asynchronous calls:
   --- *)

(* These procedures are asynchronous.
   The caller doesn't wait for the result (in unit, not really interesting);
   it just gives the "order" of applying the function to another thread then
   returns immediately to its own activity.
   If an exception occurs, it is ignored: *)

(* val delegate  : 'a t -> ?enter:('a -> bool) -> ('a -> unit) -> unit *)
let delegate (t:'a t) ?enter f : unit =
  Thread.create (apply t ?enter) f |> ignore

(* val delegate2 : 'a t -> 'b -> ?enter:('a -> 'b -> bool) -> ('a -> 'b -> unit) -> unit *)
let delegate2 (t:'a t) y ?enter f : unit =
  Thread.create (apply2 t y ?enter) f |> ignore

(* val delegate3 : 'a t -> 'b -> 'c -> ?enter:('a -> 'b -> 'c -> bool) -> ('a -> 'b -> 'c -> unit) -> unit *)
let delegate3 (t:'a t) y z ?enter f : unit =
  Thread.create (apply3 t y z ?enter) f |> ignore

(* Asynchronous call with retreivable result: *)

(* val future  : 'a t -> ?enter:('a -> bool) -> ('a -> 'b) -> ((exn, 'b) Either.t) Future.t *)
let future t ?enter f : ((exn, 'b) Either.t) Future.t =
  Future.thread (apply t ?enter) f

(* val future2 : 'a t -> 'b -> ?enter:('a -> 'b -> bool) -> ('a -> 'b -> 'c) -> ((exn, 'c) Either.t) Future.t *)
let future2 t y ?enter f : ((exn, 'b) Either.t) Future.t =
  Future.thread (apply2 t y ?enter) f

(* val future3 : 'a t -> 'b -> 'c -> ?enter:('a -> 'b -> 'c -> bool) -> ('a -> 'b -> 'c -> 'd) -> ((exn, 'd) Either.t) Future.t *)
let future3 t y z ?enter f : ((exn, 'b) Either.t) Future.t =
  Future.thread (apply3 t y z ?enter) f

(* ---
   Object-oriented interface:
   --- *)

(* --- *)
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
let objectify (t:'a t) : 'a obj =
  object
    method apply         : 'b. ?enter:('a -> bool) -> ('a -> 'b) -> (exn, 'b) Either.t = apply t
    method apply_extract : 'b. ?enter:('a -> bool) -> ('a -> 'b) -> 'b = apply_extract t
    method delegate      : ?enter:('a -> bool) -> ('a -> unit) -> unit = delegate t
    method future        : 'b. ?enter:('a -> bool) -> ('a -> 'b) -> ((exn, 'b) Either.t) Future.t = future t
    method hermit = t
    method revno  = revno t
  end

(* --- *)
let new_obj x = objectify (create x)


