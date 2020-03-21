(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2010  Jean-Vincent Loddo

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

(** Additional features for (and instances of) the standard module [Set]. *)

module type S =
  sig
    type elt
    type t
    val empty : t
    val is_empty : t -> bool
    val mem : elt -> t -> bool
    val add : elt -> t -> t
    val singleton : elt -> t
    val remove : elt -> t -> t
    val union : t -> t -> t
    val inter : t -> t -> t
    val diff : t -> t -> t
    val compare : t -> t -> int
    val equal : t -> t -> bool
    val subset : t -> t -> bool
    val iter : (elt -> unit) -> t -> unit
    val fold : (elt -> 'a -> 'a) -> t -> 'a -> 'a
    val for_all : (elt -> bool) -> t -> bool
    val exists : (elt -> bool) -> t -> bool
    val filter : (elt -> bool) -> t -> t
    val partition : (elt -> bool) -> t -> t * t
    val cardinal : t -> int
    val elements : t -> elt list
    val min_elt : t -> elt
    val max_elt : t -> elt
    val choose : t -> elt
    val split : elt -> t -> t * bool * t
    val copy : t -> t
    val of_list  : ?acc:t -> elt list -> t
    val of_lists : elt list list -> t
    val to_list  : ?acc:elt list -> ?reverse:bool -> t -> elt list
    val uniq : elt list -> elt list
  end

module Extend : functor (M : Set.S) -> S with type elt = M.elt and type t = M.t
module Make   : functor (Ord : Set.OrderedType) -> S with type elt = Ord.t

module String_set : S with type elt = string
module Int_set    : S with type elt = int

module Destructive : sig

  module type S =
    sig
      type elt
      type t
      val create : unit -> t
      val is_empty : t -> bool
      val mem : elt -> t -> bool
      val add : elt -> t -> unit
      val singleton : elt -> t
      val remove : elt -> t -> unit
      val union : t -> t -> unit
      val inter : t -> t -> unit
      val diff : t -> t -> unit
      val compare : t -> t -> int
      val equal : t -> t -> bool
      val subset : t -> t -> bool
      val iter : (elt -> unit) -> t -> unit
      val fold : (elt -> 'a -> 'a) -> t -> 'a -> 'a
      val for_all : (elt -> bool) -> t -> bool
      val exists : (elt -> bool) -> t -> bool
      val filter : (elt -> bool) -> t -> unit
      val partition : (elt -> bool) -> t -> t * t
      val cardinal : t -> int
      val elements : t -> elt list
      val min_elt : t -> elt
      val max_elt : t -> elt
      val choose : t -> elt
      val split : elt -> t -> t * bool * t
      val copy : t -> t
      val of_list : ?acc:t -> elt list -> t
      val to_list : ?acc:elt list -> ?reverse:bool -> t -> elt list
    end


  module Make : functor (Ord : Set.OrderedType) -> S with type elt = Ord.t
  module String_set : S with type elt = string
  module Int_set    : S with type elt = int

end (* Destructive *)