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


(* Protect an action from any kind of exception: *)
val protect  : ('a -> unit) -> 'a -> unit
val protect2 : ('a -> 'b -> unit) -> ('a -> 'b -> unit)
val protect3 : ('a -> 'b -> 'c -> unit) -> ('a -> 'b -> 'c -> unit)

(* Apply a function and detect if it returns an ordinary result without raising any exception: *)
val succeed  : ('a -> 'b) -> 'a -> bool
val succeed2 : ('a -> 'b -> 'c) -> 'a -> 'b -> bool

(* Print immediately a message on stderr. For debugging purposes: *)
val pr : ('a, out_channel, unit, unit) format4 -> 'a

(* Note that ~finally is itself protected by exceptions and its result is ignored.
   If the applied function raises an exception, this exception is re-raised after finalization: *)
val try_finalize  : finally:('a -> (exn, 'b) Either.t -> 'ignored) -> ('a -> 'b) -> 'a -> 'b
val try_finalize2 : finally:('a -> 'b -> (exn, 'c) Either.t -> 'ignored) -> ('a -> 'b -> 'c) -> 'a -> 'b -> 'c

(* Get the unique identifier of a Caml value representation.
   Thread safe (read-only method): *)
val get_magic_identifier : 'a -> int

(* Print informations about the Caml value representation:
Misc.print_repr_info [21; 42] ;;
is_block: true
tag: 0
size: 2
magic: 70160594236104
*)
val print_repr_info : 'a -> unit

(* Both polymorphic and physical, really magic.
   Not Thread safe (because get_magic_identifier is called twice).
   (magic_physical_compare x y) = 0   <=>   (x==y) || (get_magic_identifier x) = (get_magic_identifier y) *)
val magic_physical_compare : 'a -> 'a -> int

(* Trace calls of a function (entering/exiting).
   Example of usage:
   ---
   let mytool = Misc.follow "mytool" mytool ;;
   ---
*)
val follow  : string -> ('a -> 'b) -> 'a -> 'b
val follow2 : string -> ('a -> 'b -> 'c) -> 'a -> 'b -> 'c

(* Thread safe integers generator: *)
val fresh_id : unit -> int
