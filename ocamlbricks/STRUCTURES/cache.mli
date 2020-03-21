(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2010 Jean-Vincent Loddo

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

(** Build a cached version of a function working on a non-persistent structure.
    The structure must be equipped with a revision number: this integer
    is used to decide when the function has to be recalculated
    or when the value stored in the cache may be taken as the result of the
    function. {b Example}:

{[
(* The module implementing the data structure has to manage a revision number,
   as for instance Cloakroom: *)

# let t = Cloakroom.create () ;;
val t : '_a Cloakroom.t = <abstr>

# let to_list = Cache.optimize ~revision:Cloakroom.revision Cloakroom.to_list t ;;
val to_list : '_a list Cache.thunk = <fun>

# to_list () ;;
  : '_a list = []

# Cloakroom.add t "foo" ;;
  : Cloakroom.id = 1

# Cloakroom.add t "bar" ;;
  : Cloakroom.id = 2

# Cloakroom.revision t;;
  : int = 2

# to_list () ;;
  : string list = ["foo"; "bar"]
]}
*)

val optimize : revision:('t -> int) -> ('t -> 'a) -> 't -> unit -> 'a
