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


module type Type = sig type t val name:string option end

module Variable :
  functor (Type : Type) ->
    sig
      type t = Type.t
      val get     : unit -> t option
      val extract : unit -> t
      val set     : t -> unit
      val unset   : unit -> unit
      val lazy_set: t Lazy.t -> unit
      val content : t Lazy.t option ref
    end

module Thread_shared_variable :
  functor (Type : Type) ->
    sig
      type t = Type.t
      val get     : unit -> t option
      val extract : unit -> t
      val set     : t -> unit
      val lazy_set: t Lazy.t -> unit
      val unset   : unit -> unit
      val apply_with_mutex : ('a -> 'b) -> 'a -> 'b
      val lock   : unit -> unit
      val unlock : unit -> unit
    end

module type Type_with_init =
  sig
    type t
    val name : string option
    val init : unit -> t
  end

module Process_private_thread_shared_variable :
  functor (Type : Type_with_init) ->
    sig
      type t = Type.t
      val get     : unit -> t option
      val extract : unit -> t
      val set     : t -> unit
      val lazy_set: t Lazy.t -> unit
      val unset   : unit -> unit
      val apply_with_mutex : ('a -> 'b) -> 'a -> 'b
      val lock   : unit -> unit
      val unlock : unit -> unit
    end

