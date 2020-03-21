(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009  Jean-Vincent Loddo

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

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

type 'a thread_status =
| Completed of 'a
| Exception of exn

(** The abstract type of a future. *)
type 'a future = (('a thread_status) Egg.t) * Thread.t

(** Alias. *)
type 'a t = 'a future

(** Create a future applying an argument to a function. The result of the function may be got later with [touch] or [taste]. *)
let future (f:'a -> 'b) (x:'a) : 'b t =
 let egg = Egg.create () in
 let wrap x =
   let y = (try Completed (f x)
            with e -> Exception e)
   in Egg.release egg y
 in
 let thd = Thread.create wrap x in
 (egg,thd)

(** {b Wait} until the result is ready. Re-raise [exn] if the future has been interrupted by the exception [exn]. *)
let touch (egg,thd) =
 match Egg.wait egg with
| Completed y -> y
| Exception e -> raise e

(** Check if the result is ready (non-blocking): [None] means {e not ready}, while [Some y] means {e ready with value} [y].
Re-raise [exn] if the future has been interrupted by the exception [exn]. *)
let taste (egg,thd) : 'a option = match Egg.taste egg with
 | None   -> None
 | Some v ->
    (match v with
    | Completed y -> Some y
    | Exception e -> raise e
    )

let thread_of (egg,thd) = thd
