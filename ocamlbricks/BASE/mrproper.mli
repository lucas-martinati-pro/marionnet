(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009 2012  Jean-Vincent Loddo

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

(** Register actions to perform exiting the program or destroying a
    temporary structure.

On the one hand, a definition as the following could be written at the beginning of a program:
{[ let exit = Mrproper.exit ;; ]}
and could be used for exiting the program.
On the other hand, anywhere in the program you could register some actions in order to leave
the program cleanly, as for instance:
{[ let filename = temp_file ~perm:0o755 ~suffix:".sh" () in
 let () = Mrproper.register_lazy (lazy (Unix.unlink filename)) in
 ...]}

Note that actions are internally registered in a {b stack} and are thus performed in the reversed order
with respect to the registration (insertion). *)

(** Push a thunk into the global stack of thunks. *)
val register_thunk : ?unprotect:unit -> ?one_shot:unit -> unit Thunk.t -> Thunk.id

(** Push a lazy action into the global stack of thunks.
    Lazy actions are forced to be one-shot: when unprotected, the
    thunk will not re-raise the same exception forcing the thunk execution twice. *)
val register_lazy  : ?unprotect:unit -> unit Lazy.t -> Thunk.id

(** Exit the program performing all registered actions in the global stack.*)
val exit  : int -> 'a

(** Perform the list (stack) of registered actions. *)
val apply : unit -> unit

(** Low level access to the inner global stack: *)
val as_stack : unit -> (unit Thunk.t * Thunk.linear) Container.Stack_with_identifiers.t
