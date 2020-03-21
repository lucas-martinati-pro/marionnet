(* This file is part of ocamlbricks
   Copyright (C) 2013  Jean-Vincent Loddo

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

(** Additional features for the standard module [Queue]. *)

val filter      : ('a -> bool) -> 'a Queue.t -> unit
val filter_copy : ('a -> bool) -> 'a Queue.t -> 'a Queue.t
val map         : ('a -> 'a) -> 'a Queue.t -> unit
val map_copy    : ('a -> 'b) -> 'a Queue.t -> 'b Queue.t
val rev         : 'a Queue.t -> unit
val rev_copy    : 'a Queue.t -> 'a Queue.t

(* The push against discipline (the inserted element will be the first out): *)
val copush : 'a Queue.t -> 'a -> unit

(* Note that, because of the FIFO discipline, we have the equation:
   to_list (of_list xs) = List.rev xs *)
val to_list     : 'a Queue.t -> 'a list
val of_list     : 'a list -> 'a Queue.t
