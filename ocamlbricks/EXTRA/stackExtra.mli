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

(** Replacement for the standard module [Stack]. The difference with the standard [Stack]
    is the function [to_list] that transforms the stack in a list in O(1). *)

type 'a t
exception Empty
val create   : unit -> 'a t
val clear    : 'a t -> unit
val copy     : 'a t -> 'a t
val push     : 'a -> 'a t -> unit
val pop      : 'a t -> 'a
val top      : 'a t -> 'a
val is_empty : 'a t -> bool
val length   : 'a t -> int

val iter     : ('a -> unit) -> 'a t -> unit
val filter   : ('a -> bool) -> 'a t -> unit
val map      : ('a -> 'a) -> 'a t -> unit
val fold     : ('b -> 'a -> 'b) -> 'b -> 'a t -> 'b
val rev      : 'a t -> unit
val rev_copy : 'a t -> 'a t

(* Note that, because of the LIFO discipline, we have the equation:
   to_list (of_list xs) = xs *)
val to_list  : 'a t -> 'a list
val of_list  : 'a list -> 'a t

(* The push against nature (the appended element will be the last out): *)
val copush   : 'a t -> 'a -> unit
