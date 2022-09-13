(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009  Jean-Vincent Loddo

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

(** Thread safe, efficient concatenation of string queues. *)

type t

IFNDEF OCAML4_02_OR_LATER THEN
type bytes = string
ENDIF

val create : ?block_size:int -> unit -> t

(** {2 Writers' tools} *)

(** The queue is released by default for all operations. The user could request
    the non-releasing setting the optional parameter [~release] to [false]. *)

val append_from_descr : ?release:bool -> t -> Unix.file_descr -> unit

val from_descr   : ?release:bool -> ?block_size:int -> Unix.file_descr -> t
val from_file    : ?release:bool -> ?block_size:int -> string          -> t
val from_channel : ?release:bool -> ?block_size:int -> in_channel      -> t

(** {2 Readers' tools} *)

type blit_function = bytes -> int -> bytes -> int -> int -> unit
val concat : ?blit:blit_function -> t -> string

(** {2 Thread_unsafe versions} *)

module Thread_unsafe :
 sig
  val append_from_descr : ?release:bool -> t -> Unix.file_descr -> unit
  val concat            : ?blit:blit_function -> t -> string
 end
