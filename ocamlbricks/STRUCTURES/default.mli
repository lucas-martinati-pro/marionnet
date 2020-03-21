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

(** Manage global defaults for your optional parameters. If the field mutex is [true] the access
    is synchronized by a mutex (thread safe). {b Example}:
{[
module Default_foo = Default.Make(struct type t = foo_type let create () = .. let mutex = false end)
let my_function ?foo .. =
 let foo = Default_foo.extract_or_get_default foo in
 ...
]}
*)

module Make :
  functor (Value : sig  type t  val create : unit -> t  val mutex : bool  end) ->
    sig
      type t = Value.t
      val get : unit -> t
      val set : t -> unit
      val extract_or_get_default : t option -> t
    end
