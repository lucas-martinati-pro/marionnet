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

(** Additional features for (and instances of) the standard module [Map]. *)

module type S =
    sig
      include Map.S

      (* Extra functions: *)

      val search      :  key -> 'a t -> 'a option
      val filter      : (key -> 'a -> bool) -> 'a t -> 'a t
      val filter_map  : (key -> 'a -> bool) -> ('a -> 'b) -> 'a t -> 'b t
      val filter_mapi : (key -> 'a -> bool) -> (key -> 'a -> 'b) -> 'a t -> 'b t
      val product     : 'a t -> 'b t -> ('a * 'b) t
      val of_list     : ?acc:'a t -> (key * 'a) list -> 'a t
      val to_list     : ?acc:(key * 'a) list -> ?reverse:bool -> 'a t -> (key * 'a) list
      val domain      : ?reverse:bool -> 'a t -> key list
      val codomain    : ?reverse:bool -> 'a t -> 'a list
      val restrict    : 'a t -> key list -> 'a t
      val substract   : 'a t -> key list -> 'a t
    end

module Extend : functor (Map : Map.S) -> S with type key = Map.key
module Make   : functor (Ord : Map.OrderedType) -> S with type key = Ord.t

(** {2 Pre-built mappings} *)

module String_map : S with type key = string
module Int_map    : S with type key = int

(** {2 Not persistent (imperative) versions} *)

module Destructive : sig

  (* TODO: add wrappers for the functions introduced in OCaml 3.12: *)
  module type S =
    sig
      type key
      type 'a t
      val create    : unit -> 'a t
      val is_empty  : 'a t -> bool
      val add       : key -> 'a -> 'a t -> unit
      val find      : key -> 'a t -> 'a
      val remove    : key -> 'a t -> unit
      val mem       : key -> 'a t -> bool
      val iter      : (key -> 'a -> unit) -> 'a t -> unit
      val map       : ('a -> 'a) -> 'a t -> unit
      val mapi      : (key -> 'a -> 'a) -> 'a t -> unit
      val fold      : (key -> 'a -> 'b -> 'b) -> 'a t -> 'b -> 'b
      val compare   : ('a -> 'a -> int) -> 'a t -> 'a t -> int
      val equal     : ('a -> 'a -> bool) -> 'a t -> 'a t -> bool

      (* Extra functions: *)

      val search      : key -> 'a t -> 'a option
      val copy        : 'a t -> 'a t
      val filter      : (key -> 'a -> bool) -> 'a t -> unit
      val filter_map  : (key -> 'a -> bool) -> ('a -> 'a) -> 'a t -> unit
      val filter_mapi : (key -> 'a -> bool) -> (key -> 'a -> 'a) -> 'a t -> unit
      val of_list     : ?acc:'a t -> (key * 'a) list -> 'a t
      val to_list     : ?acc:(key * 'a) list -> ?reverse:bool -> 'a t -> (key * 'a) list
      val domain      : ?reverse:bool -> 'a t -> key list
      val codomain    : ?reverse:bool -> 'a t -> 'a list
      val restrict    : 'a t -> key list -> unit
      val substract   : 'a t -> key list -> unit

    end

  module Make : functor (Ord : Map.OrderedType) -> S with type key = Ord.t

  (* Destructive versions: *)

  module String_map : S with type key = string
  module Int_map    : S with type key = int

end (* Destructive *)
