(* This file is part of ocamlbricks
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

class virtual destroy_methods :
  unit ->
  object
    method add_destroy_callback : unit Lazy.t -> unit
    method (*private*) destroy : unit
    method mrproper : Thunk.lifo_unit_protected_container
  end

module Gc_sync :
sig
  val finalizer : (int -> unit) -> oid:int -> finalizer_hook:'a -> unit
  val notify : int -> unit

  class ['a] t :
    ?destroy:(int -> unit) ->
    'a ->
    object
      method get : 'a
      method set : 'a -> unit
    end

  val ref : ?destroy:(int -> unit) -> 'a -> 'a t
end
