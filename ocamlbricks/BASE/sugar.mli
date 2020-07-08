(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Jean-Vincent Loddo

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

(** Basic shortcuts and syntactic sugar. *)

val ( ||> ) : ('a -> 'b) -> ('b -> 'c) -> 'a -> 'c
val identity : 'a -> 'a
val id : 'a -> 'a
val ( @@ ) : ('a -> 'b) -> ('c -> 'd) -> 'a * 'c -> 'b * 'd
val curry : ('a * 'b -> 'c) -> 'a -> 'b -> 'c
val uncurry : ('a -> 'b -> 'c) -> 'a * 'b -> 'c
val ( |=> ) : 'a option -> 'a -> 'a
val nothing : unit -> unit
val skip : unit
type identifier = int
type 'a filter = 'a -> 'a
