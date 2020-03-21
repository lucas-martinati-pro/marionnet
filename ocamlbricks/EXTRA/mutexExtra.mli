(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009, 2011  Jean-Vincent Loddo
   Copyright (C) 2011  Université Paris 13

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

(** Additional features for the standard module [Mutex].

{b Example}:
{[(* Extend the standard Mutex: *)
module Mutex = MutexExtra.Extend (Mutex);;

(* Use the function with_mutex: *)
Mutex.with_mutex mutex (fun () -> ...);;

(* Idem for recursive mutexes: *)
module Recursive_mutex = MutexExtra.Extend (MutexExtra.Recursive_mutex) ;;

(* Or equivalently, you can use a predefined functor application as shortcut: *)
module Recursive_mutex = MutexExtra.Recursive ;;
]}
*)

module type Mutex_signature =
  sig
    type t
    val create   : unit -> t
    val lock     : t -> unit
    val unlock   : t -> unit
    val try_lock : t -> bool
  end

module type Basic_signature =
  sig
    include Mutex_signature
    val wait : Condition.t -> t -> unit
  end

module type Extended_signature =
  sig
    include Basic_signature

    val status   : t -> bool

    val with_mutex       : ?verbose:unit -> t -> (unit -> 'a) -> 'a
    val apply_with_mutex : ?verbose:unit -> t -> ('a -> 'b) -> 'a -> 'b

    val with_mutex_and_guard :
      ?perform_in_critical_section_before_sleeping:(unit -> unit) ->
      condition:Condition.t ->
      guard:(unit->bool) ->
      t ->
      (unit->'a) -> 'a

    val apply_with_mutex_and_guard :
      ?perform_in_critical_section_before_sleeping:(unit -> unit) ->
      condition:Condition.t ->
      guard:(unit->bool) ->
      t ->
      ('a -> 'b) -> 'a -> 'b

    val signal_with_mutex    : condition:Condition.t -> t -> unit
    val broadcast_with_mutex : condition:Condition.t -> t -> unit
  end


module Extend : functor (M:Basic_signature) -> Extended_signature

module EMutex : Extended_signature with type t = Mutex.t  (* Extended standard mutexes *)
module RMutex : Extended_signature                        (* Extended recursive mutexes *)

(* Just a more explicit alias for EMutex: *)
module Extended_Mutex : Extended_signature with type t = Mutex.t

(* Just a more explicit alias for RMutex: *)
module Recursive : Extended_signature

module Just_give_me_an_apply_with_mutex : functor (M:sig end) ->
  sig
    val apply_with_mutex : ('a -> 'b) -> 'a -> 'b
  end

