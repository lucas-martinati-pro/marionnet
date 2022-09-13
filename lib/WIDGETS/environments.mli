(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Jean-Vincent Loddo, Luca Saiu

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

(** Abstract results of a GUI dialog. *)

class ['a, 'b] env :
  unit ->
  object
    val table : ('a, 'b) Hashmap.t
    method add : 'a * 'b -> unit
    method add_list : ('a * 'b) list -> unit
    method get : 'a -> 'b
    method to_list : ('a * 'b) list
    method updated_by : ('a,'b) env -> unit
  end
val make : ('a * 'b) list -> ('a, 'b) env

exception Undefined_identifier of string

class ['a] string_env :
  unit ->
  object
    val table : (string, 'a) Hashmap.t
    method add : string * 'a -> unit
    method add_list : (string * 'a) list -> unit
    method get : string -> 'a
    method to_list : (string * 'a) list
    method to_string : ('a -> string) -> string
    method updated_by : (string,'a) env -> unit
  end

val make_string_env : (string * 'a) list -> 'a string_env
val string_env_updated_by: 'a string_env -> 'a string_env -> 'a string_env
