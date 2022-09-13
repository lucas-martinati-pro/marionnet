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

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

module Make (Value:sig  type t  val create : unit -> t  val mutex : bool end) :
 sig
  type t = Value.t
  val get : unit -> t
  val set : t -> unit
  val extract_or_get_default : t option -> t
 end = struct

type t = Value.t

let default = ref None

module Unprotected = struct

 (** Set the current default. *)
 let set s = (default := Some s)

 (** Get the current default if exists; create, set and return it if doesn't exist. *)
 let get () = match !default with
 | Some s -> s
 | None ->
     let new_default = Value.create () in
     (default := Some new_default);
     new_default

 (** If the argument is [Some x] return [x]; if the argument is [None], return the result of [get ()]. *)
 let extract_or_get_default = function
 | Some s -> s
 | None -> get ()

end (* Unprotected *)

 let mutex = MutexExtra.Recursive.create ()

 let switch f = match Value.mutex with
  | true  -> MutexExtra.Recursive.apply_with_mutex mutex f
  | false -> f

 let set = switch Unprotected.set
 let get = switch Unprotected.get
 let extract_or_get_default = switch Unprotected.extract_or_get_default

end
