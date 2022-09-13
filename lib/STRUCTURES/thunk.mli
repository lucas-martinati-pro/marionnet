(* This file is part of ocamlbricks
   Copyright (C) 2012 Jean-Vincent Loddo

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

(** Utilities about thunks, i.e. functions from [unit] to ['a]. *)

type 'a t = unit -> 'a

val linearize : 'a t -> 'a t
val protect   : fallback:(unit -> 'a) -> 'a t -> 'a t

(** Alias for linearize: *)
val one_shot  : 'a t -> 'a t

val apply     : 'a t -> 'a
val of_lazy   : 'a lazy_t -> 'a t
val to_lazy   : 'a t -> 'a lazy_t

type id = int
type linear = bool

(** First thunk providing a suitable result: *)
val first_success : ('a -> bool) -> 'a t list -> 'a option

(** As first_success, but each thunk may directly fails (None): *)
val first_attempt : ('a -> bool) -> ('a option) t list -> 'a option

(** A queue of 'a thunks. Linear (one-shot) thunks are automatically
   removed after each call of apply. Note that the first parameter
   of the folder is the accumulator (current state). *)
class ['a] fifo_container :
  (* Default for methods having these parameters: *)
  ?fallback:'a t ->
  unit ->
  object
  method register_thunk : ?fallback:'a t -> ?one_shot:unit -> 'a t -> id
  method register_lazy  : ?fallback:'a t -> 'a Lazy.t -> id
  method remove         : id -> unit
  method get            : id -> 'a t
  method revno          : int
  method apply          : 'b. ?folder:('b -> 'a -> 'b) -> 'b -> 'b
  (* The application is delayed but it will act on the current (not the future) 
   list of thunks. Note also that the one-shot thunks are immediately removed. *)
  method delayed_apply  : 'b. ?folder:('b -> 'a -> 'b) -> 'b -> 'b Lazy.t
  method as_queue       : ('a t * linear) Container.Queue_with_identifiers.t
end

(** A stack of 'a thunks. Linear (one-shot) thunks are automatically
   removed after each call of apply. Note that the first parameter
   of the folder is the accumulator (current state). *)
class ['a] lifo_container :
  (* Default for methods having these parameters: *)
  ?fallback:'a t ->
  unit ->
  object
  method register_thunk : ?fallback:'a t -> ?one_shot:unit -> 'a t -> id
  method register_lazy  : ?fallback:'a t -> 'a Lazy.t -> id
  method remove         : id -> unit
  method get            : id -> 'a t
  method revno          : int
  method apply          : 'b. ?folder:('b -> 'a -> 'b) -> 'b -> 'b
  (* The application is delayed but it will act on the current (not the future) 
   list of thunks. Note also that the one-shot thunks are immediately removed. *)
  method delayed_apply  : 'b. ?folder:('b -> 'a -> 'b) -> 'b -> 'b Lazy.t
  method as_stack       : ('a t * linear) Container.Stack_with_identifiers.t
end

class fifo_unit_protected_container :
  unit ->
  object
  method register_thunk : ?unprotect:unit -> ?one_shot:unit -> unit t -> id
  method register_lazy  : ?unprotect:unit -> unit Lazy.t -> id
  method remove         : id -> unit
  method get            : id -> unit t
  method revno          : int
  method apply          : unit -> unit
  method as_queue       : (unit t * linear) Container.Queue_with_identifiers.t
end

(** Useful to make a {e local} object-oriented mrproper structure.
    A typical use is to connect the method [apply] to the destruction of
    a temporary structure, as for instance a widget.

    {b Example}:
{[  let window = GWindow.window () in
  let mrproper = new Thunk.lifo_unit_protected_container () in
  ..
  mrproper#register_lazy (lazy ...);
  mrproper#register_lazy (lazy ...);
  ..
  let _ = window#connect#destroy ~callback:mrproper#apply in
  ..
]}*)
class lifo_unit_protected_container :
  unit ->
  object
  method register_thunk : ?unprotect:unit -> ?one_shot:unit -> unit t -> id
  method register_lazy  : ?unprotect:unit -> unit Lazy.t -> id
  method remove         : id -> unit
  method get            : id -> unit t
  method revno          : int
  method apply          : unit -> unit
  method as_stack       : (unit t * linear) Container.Stack_with_identifiers.t
end

IFDEF DOCUMENTATION_OR_DEBUGGING THEN
module Test : sig
  val go : unit -> unit
end
ENDIF
