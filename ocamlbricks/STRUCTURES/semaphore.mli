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

type t
val create : ?mutex:Mutex.t -> ?condition:Condition.t -> ?init:int -> unit -> t

val p        : ?n:int -> t -> unit
val v        : ?n:int -> t -> unit
val p_nowait : ?n:int -> t -> bool

val with_semaphore : ?n:int -> t -> (unit -> 'a) -> 'a

module Array_and :
  functor (M : sig val dim : int end) ->
    sig

      val dim : int
      val create : ?mutex:Mutex.t -> ?condition:Condition.t -> ?init:int array -> unit -> t array

      val p        : ?n:int array -> t array -> unit
      val v        : ?n:int array -> t array -> unit
      val p_nowait : ?n:int array -> t array -> bool

      val with_semaphore : ?n:int array -> t array -> (unit -> 'a) -> 'a

    end

module Array_or :
  functor (M : sig val dim : int end) ->
    sig

      val dim : int
      val create : ?mutex:Mutex.t -> ?condition:Condition.t -> ?init:int array -> unit -> t array

      val p        : ?n:int array -> t array -> int * int
      val p_nowait : ?n:int array -> t array -> (int * int) option
      val v        : i:int -> n:int -> t array -> unit

      val with_semaphore : ?n:int array -> t array -> (i:int -> n:int -> 'a) -> 'a

    end
