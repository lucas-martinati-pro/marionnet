(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2020  Jean-Vincent Loddo
   Copyright (C) 2020  Université Sorbonne Paris Nord

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

(** Thread-safe deferred computations. *)

type 'a t

(* Constructors: *)

val make      : (unit -> 'a) -> 'a t
val from_fun  : (unit -> 'a) -> 'a t (* alias for `make' *)

(* Methods:
   See: https://caml.inria.fr/pub/docs/manual-ocaml/libref/Lazy.html *)

val force     : 'a t -> 'a
val force_opt : 'a t -> 'a option (* catch exceptions *)
val taste     : 'a t -> ((exn, 'a) Either.t) option
(* --- *)
val is_val    : 'a t -> bool
val is_forced : 'a t -> bool

(* No way to implement:
   val wait : 'a t -> 'a
   => see module Lazynel (implemented with channels)
*)

