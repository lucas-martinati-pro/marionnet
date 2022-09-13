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

(** Single-writer/multi-readers {e egg} synchronization structure. Eggs are very close to {b futures}: someone in the system
    (the {e writer}) has to perform a job for itself and/or for others (the {e readers}). In this sense,
    readers wait until the writer "make the egg". The egg is ready when it is released by the writer. When this happen,
    the writer broadcast all pending readers. Future readers will get the egg immediately without waiting.

    There's just a little {b difference between eggs and futures}: the role writer/reader of an agent is not known
    a priori, but could be defined dynamically. More specifically, the boolean and {b non-blocking} function
    [acquire_release_power] allows a potential writer to acquire the power to perform the job. If it succeed
    the agent become a writer, otherwise it should become a reader waiting for the egg produced by someone else.
    The typical scheme (where t is an egg) is:

{[let result =
  if Egg.acquire_release_power t
   then
     (* I'm the writer *)
     let result = (* perform the job *) in
     (Egg.release t);
     result
   else
     (* I'm a reader *)
     Egg.wait t
]}

If you know a priori the writer, you dont need to call the function [acquire_release_power]. In other terms,
you are using eggs as futures.
*)

type 'a t

val create     : unit -> 'a t
val acquire_release_power : 'a t -> bool
val wait       : 'a t -> 'a
val taste      : 'a t -> 'a option
val release    : 'a t -> 'a -> unit
