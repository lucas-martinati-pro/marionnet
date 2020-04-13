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
val protect : ('a -> unit) -> 'a -> unit

(* Print immediately a message on stderr. For debugging purposes: *)
val pr : ('a, out_channel, unit, unit) format4 -> 'a

(* Note that ~finally is itself protected by exceptions and its result is ignored. *)
val try_finalize : finally:('a -> (exn, 'b) Either.t -> 'ignored) -> ('a -> 'b) -> 'a -> 'b
