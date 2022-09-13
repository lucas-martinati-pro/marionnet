(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Jean-Vincent Loddo
   Copyright (C) 2008  Luca Saiu (wrote the methods remove_key_value_or_fail
                                  and remove_key_value)

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

(** Polymorphic {e unbounded} {b multi} maps (environments). *)

type ('a, 'b) t

val make           : ?size:int -> unit -> ('a, 'b) t
val lookup_or_fail : ('a, 'b) t -> 'a -> 'b list
val lookup         : ('a, 'b) t -> 'a -> 'b list
val mem            : ('a, 'b) t -> 'a -> 'b -> bool
val memq           : ('a, 'b) t -> 'a -> 'b -> bool
val bound          : ('a, 'b) t -> 'a -> bool
val add            : ('a, 'b) t -> 'a -> 'b -> unit
val add_list       : ('a, 'b) t -> ('a * 'b) list -> unit
val replace        : ('a, 'b) t -> 'a -> 'b -> unit
val remove         : ('a, 'b) t -> ?all:bool -> 'a -> unit
val update         : ?replace:bool -> ('a, 'b) t -> ('a, 'b) t -> unit
val to_list        : ('a, 'b) t -> ('a * 'b) list
val of_list        : ?size:int -> ('a * 'b) list -> ('a, 'b) t

(** {2 Object-oriented interface} *)

class ['a, 'b] hashmultimap :
  ?size:int ->
  unit ->
  object
    method add : 'a -> 'b -> unit
    method add_list : ('a * 'b) list -> unit
    method bound : 'a -> bool
    method get : ('a, 'b) Hashtbl.t
    method lookup : 'a -> 'b list
    method lookup_or_fail : 'a -> 'b list
    method mem : 'a -> 'b -> bool
    method memq : 'a -> 'b -> bool
    method remove : ?all:bool -> 'a -> unit
    method remove_key_value : 'a -> 'b -> unit
    method remove_key_value_or_fail : 'a -> 'b -> unit
    method replace : 'a -> 'b -> unit
    method to_list : ('a * 'b) list
  end
