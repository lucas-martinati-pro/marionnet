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

(** Synchronization structure for functional/concurrent (threads) programming model.
    This structure allows an asynchronous kind of function application.

    Differently from the default [Thread], the result of the application is not lost but accessible with the primitives [touch] and [taste].
    The same holds for exceptions and their associated values: if an exception interrupts the computation, it will be re-raised
    in any thread touching or tasting the future. This behaviour makes the primitive
    [future] preferrable with respect to the standard [Thread.create] {e even} for threads providing a non interesting
    result, i.e. a result of type [unit]. *)

type 'a future
type 'a t = 'a future

val future : ('a -> 'b) -> 'a -> 'b future

(** {2 Result} *)

val touch : 'a future -> 'a
val taste : 'a future -> 'a option

val thread_of : 'a future -> Thread.t
