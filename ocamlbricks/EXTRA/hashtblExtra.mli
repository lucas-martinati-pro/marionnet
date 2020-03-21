(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009 Jean-Vincent Loddo

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

(** Additional features for the standard module [Hashtbl]. *)

type ('a, 'b) t = ('a, 'b) Hashtbl.t

val remove_all : ('a, 'b) t -> 'a -> unit
val search        : ('a, 'b) t -> 'a  -> 'b option
val to_assoc_list : ('a, 'b) t -> ('a * 'b) list
val of_assoc_list : ?random:bool -> ?size:int -> ('a * 'b) list -> ('a,'b) t

IFDEF OCAML4_OR_LATER THEN
val map           : ('b -> 'c) -> ('a, 'b) t -> ('a, 'c) t
val mapk          : ('a -> 'b -> 'c) -> ('a, 'b) t -> ('a, 'c) t
val map2          : ('b -> 'c -> 'd) -> ('a, 'b) t -> ('a, 'c) t -> ('a, 'd) t
val map2k         : ('a -> 'b -> 'c -> 'd) -> ('a, 'b) t -> ('a, 'c) t -> ('a, 'd) t
ENDIF

module Make :
  functor (H : Hashtbl.HashedType) ->
    sig
      type key = H.t
      type 'a t = 'a Hashtbl.Make(H).t
      val create : int -> 'a t
      val clear : 'a t -> unit
      val copy : 'a t -> 'a t
      val add : 'a t -> key -> 'a -> unit
      val remove : 'a t -> key -> unit
      val find : 'a t -> key -> 'a
      val find_all : 'a t -> key -> 'a list
      val replace : 'a t -> key -> 'a -> unit
      val mem : 'a t -> key -> bool
      val iter : (key -> 'a -> unit) -> 'a t -> unit
      val fold : (key -> 'a -> 'b -> 'b) -> 'a t -> 'b -> 'b
      val length : 'a t -> int
      (* extra: *)
      val remove_all : 'a t -> key -> unit
      val search     : 'a t -> key -> 'a option
      val to_assoc_list : 'a t -> (key * 'a) list
      val of_assoc_list : ?size:int -> (key * 'a) list -> 'a t
      (* --- *)
      IFDEF OCAML4_OR_LATER THEN
      val map   : ('a -> 'b) -> 'a t -> 'b t
      val mapk  : (key -> 'a -> 'b) -> 'a t -> 'b t
      val map2  : ('a -> 'b -> 'c) -> 'a t -> 'b t -> 'c t
      val map2k : (key -> 'a -> 'b -> 'c) -> 'a t -> 'b t -> 'c t
      ENDIF      
end
