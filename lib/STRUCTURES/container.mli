(* This file is part of ocamlbricks
   Copyright (C) 2013  Jean-Vincent Loddo

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


(** The signature of an imperative stack or queue *)
module type T =
  sig
    type 'a t
    val create   : unit -> 'a t
    val clear    : 'a t -> unit
    val copy     : 'a t -> 'a t
    val push     : 'a -> 'a t -> unit
    val pop      : 'a t -> 'a
    val top      : 'a t -> 'a
    val is_empty : 'a t -> bool
    val length   : 'a t -> int
    val iter     : ('a -> unit) -> 'a t -> unit
    val filter   : ('a -> bool) -> 'a t -> unit
    val map      : ('a -> 'a) -> 'a t -> unit
    val fold     : ('b -> 'a -> 'b) -> 'b -> 'a t -> 'b
    val rev      : 'a t -> unit
    val rev_copy : 'a t -> 'a t

    val to_list  : 'a t -> 'a list
    val of_list  : 'a list -> 'a t

    (** The push method in the opposite discipline: if the container is LIFO
        the co-pushing method is FIFO and vice-versa. For instance, in a
        stack implemented by a list, the co-pushing method is the `append'
        operation:
          push   x xs = x::xs
          copush xs x = xs@[x]

        In other words, the co-pushing method is the composition:
          reverse; push; reverse *)
    val copush   : 'a t -> 'a -> unit
  end

module type T_with_identifiers =
  sig
    type id = int
    type 'a t

    (* Functions with the same name but abstracting from identifiers: *)

    val create   : unit -> 'a t
    val clear    : 'a t -> unit
    val copy     : 'a t -> 'a t
    val pop      : 'a t -> 'a
    val top      : 'a t -> 'a
    val is_empty : 'a t -> bool
    val length   : 'a t -> int
    val iter     : ('a -> unit) -> 'a t -> unit
    val filter   : ('a -> bool) -> 'a t -> unit
    val map      : ('a -> 'a) -> 'a t -> unit
    val fold     : ('b -> 'a -> 'b) -> 'b -> 'a t -> 'b
    val rev      : 'a t -> unit
    val rev_copy : 'a t -> 'a t

    val to_list  : 'a t -> 'a list
    val of_list  : 'a list -> 'a t

    (* There are two differences with the T signature about shared names:
       both `push' and `copush' return the `id' generated for insertion: *)

    val push   : 'a -> 'a t -> id
    val copush : 'a t -> 'a -> id

   (* Identical functions but changing name ("i" suffix or "assoc_"): *)

    val pushi    : (id * 'a) -> 'a t -> unit
    val copushi  : 'a t -> (id * 'a) -> unit
    val popi     : 'a t -> id * 'a
    val topi     : 'a t -> id * 'a
    val iteri    : (id * 'a -> unit) -> 'a t -> unit
    val filteri  : (id * 'a -> bool) -> 'a t -> unit
    val mapi     : (id * 'a -> id * 'a) -> 'a t -> unit
    val foldi    : ('b -> id * 'a -> 'b) -> 'b -> 'a t -> 'b
    val to_assoc_list  : 'a t -> (id * 'a) list
    val of_assoc_list  : (id * 'a) list -> 'a t

    (* The real purpose of having identifiers: *)

    (* get_by_id may raise [Not_found] *)
    val get_by_id    : id -> 'a t -> 'a

    (* Does nothing if the id doesn't exist: *)
    val remove_by_id : id -> 'a t -> unit

    (* The inner generator of fresh identifiers: *)
    val fresh : unit -> int

    (* The inner generator of fresh identifiers *as module*
       (useful to have something ready to be provided to a functor).
       (Note that fresh = Option.extract Fresh.fresh) *)
    module Fresh : sig val fresh : (unit -> int) option end
  end

module Add_identifiers :
  (* Fresh is morally an optional functor argument: *)
  functor (Fresh : sig val fresh : (unit -> int) option end) ->
  functor (Container: T) -> T_with_identifiers


module Stack_with_identifiers : T_with_identifiers
module Queue_with_identifiers : T_with_identifiers
