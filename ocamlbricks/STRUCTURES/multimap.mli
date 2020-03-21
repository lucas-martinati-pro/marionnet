(* This file is part of ocamlbricks
   Copyright (C) 2012  Jean-Vincent Loddo

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

(** Additional features for (and instances of) the standard module [Map]. *)

(* TODO: add wrappers for the functions introduced in OCaml 3.12: *)
module type S =
   sig
      type key
      type elt
      type elt_set

      type t
      val empty         : t
      val is_empty      : t -> bool
      val add           : key -> elt -> t -> t
      val find          : key -> t -> elt_set
      val find_list     : ?sort:unit -> key -> t -> elt list
      val remove_key    : key -> t -> t
      val remove        : key -> elt -> t -> t
      val mem_key       : key -> t -> bool
      val mem           : key -> elt -> t -> bool
      val iter_key      : (key -> elt_set -> unit) -> t -> unit
      val iter          : (key -> elt -> unit) -> t -> unit
      val fold_key      : (key -> elt_set -> 'b -> 'b) -> t -> 'b -> 'b
      val fold          : (key -> elt -> 'b -> 'b) -> t -> 'b -> 'b
      val compare       : t -> t -> int
      val equal         : t -> t -> bool

      (* Extra functions: *)

      val filter_key    : (key -> elt_set -> bool) -> t -> t
      val filter        : (key -> elt -> bool) -> t -> t
      val of_list       : ?acc:t -> (key * elt) list -> t
      val to_list       : ?acc:(key * elt) list -> ?sort:unit -> t -> (key * elt) list
      val domain        : ?sort:unit -> t -> key list
      val codomain      : ?sorted_by_key:unit -> t -> elt list
      val restrict      : t -> key list -> t
      val diff          : t -> t -> t
      val inter         : t -> t -> t
      val union         : t -> t -> t
   end


module Make :
  functor (Ord_key : Map.OrderedType) ->
  functor (Ord_elt : Map.OrderedType) -> S with
      type key = Ord_key.t and
      type elt = Ord_elt.t and
      type elt_set = SetExtra.Make(Ord_elt).t

IFDEF DOCUMENTATION_OR_DEBUGGING THEN
module Examples : sig

  (* I'm forced to export the module Ord_elt to express the type String2int.elt_set
     (by the expression SetExtra.Make(Ord_elt).t) *)
  module Ord_elt : Map.OrderedType with type t = int
  module String2int : S
    with
      type key = string and
      type elt = int and
      type elt_set = SetExtra.Make(Ord_elt).t

  val t  : String2int.t
  val t' : String2int.t

  val diff  : String2int.t
  val inter : String2int.t
  val union : String2int.t

  val list_of_t     : (string * int) list
  val list_of_t'    : (string * int) list
  val list_of_diff  : (string * int) list
  val list_of_inter : (string * int) list
  val list_of_union : (string * int) list

end
ENDIF


