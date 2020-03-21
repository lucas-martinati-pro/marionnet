(* This file is part of ocamlbricks
   Copyright (C) 2013, 2014, 2015, 2016, 2017  Jean-Vincent Loddo

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


(** A simple module for active waiting ("spinning" or "busy-waiting").
    This is the only possibility when a value is not locked by a mutex or
    when is locked by a mutex unrelated to a condition variable. *)

(** Type aliases: *)
type time = seconds
 and delay = seconds
 and seconds = float

exception Timeout

(* ========================================================
                    Simplified interface
   ======================================================== *)

type 'a thunk = unit -> 'a

(** Wait until a condition (guard) becames true, applying a function "delay" to sleep between two tests.
    The backoff function used to build the delay function is linear by default.
    A couple of thunks for unlocking/relocking may be provided to be executed before and after sleeping.
    The result is the value returned by the last relocking call, or it is the provided one if the
    relocking was never been called.
    Note that the type 'a became simply "unit" if the locking (relock) function doesn't return
    a meaningfull information, which is the common case.
    May raise Timeout if ?timeout is provided. *)
val wait_until :
  ?backoff:[`linear|`exponential|`binary_exponential] -> ?max_delay:time -> ?slot:time -> unit -> (* constructor *)
  ?unlock_relock:(unit thunk * 'a thunk) ->
  ?timeout_exn:exn -> (* exception to be raised in case of timeout (by default is Spinning.Timeout) *)
  ?timeout:seconds ->
  guard:(unit->bool) -> 'a -> 'a  (* usually unit->unit *)

(** As the previous function with two differences:
    (1) the argument ~timeout is mandatory, and
    (2) when the timeout occurs, it doesn't raise the exception Timeout (just returns None). *)
val wait_impatiently :
  ?backoff:[`linear|`exponential|`binary_exponential] -> ?max_delay:time -> ?slot:time -> unit -> (* constructor *)
  ?unlock_relock:(unit thunk * 'a thunk) ->
  ?timeout_exn:exn ->
  timeout:seconds ->
  guard:(unit->bool) -> 'a -> 'a option (* usually unit->(unit option) *)


(* ========================================================
                   Full detailed interface
   ======================================================== *)


(** A backoff_function takes the number of observed collisions c and returns the range r from which
    to extract a random number k (in the interval [0..r]). This factor, multiplied to the "slot_time" d,
    determines the time (d*k) to sleep (i.e. the "delay") before a new evaluation of a condition.
    ---
    Exemples of backoff functions:
    Linear (c->c), Binary exponential (c->2^c), Truncated binary exponential (c->2^(min c max_collisions),.. *)
module Backoff : sig
  (* --- *)
  type f = collisions -> delay_range
  (* --- *)
   and collisions  = float
   and delay_range = time
  (* --- *)
  (* Common cases: *)
  val linear             : f   (* fun c->c *)
  val exponential        : f   (* exp *)
  val binary_exponential : f   (* fun c->2.**c *)
  (* --- *)
  (* Used by Ethernet CSMA/CD:
     we define a maximum number of collisions (max{x}) instead of a max range (~max_delay, i.e. max{f(x)}): *)
  val truncated_binary_exponential : ?max_collisions:int -> f   (* fun c->2.**(min c max_collisions) *)
  (* --- *)
end (* Backoff *)


(** Default for functions taking these optional arguments. *)
module Default : sig
  (* --- *)
  val backoff : Backoff.f (* Backoff.linear *)
  val slot    : time      (* 0.1 seconds *)
  (* --- *)
end


(* Random generators, built from common backoff functions: *)
module Random : sig
  (* --- *)
  type g = unit -> delay
  (* --- *)
  val make : ?max_delay:time -> ?slot:time -> ?backoff:Backoff.f -> unit -> g
  (* --- *)
  (* Common cases: *)
  val linear                       : ?max_delay:time     -> ?slot:time -> unit -> g
  val exponential                  : ?max_delay:time     -> ?slot:time -> unit -> g
  val binary_exponential           : ?max_delay:time     -> ?slot:time -> unit -> g
  val truncated_binary_exponential : ?max_collisions:int -> ?slot:time -> unit -> g  (* Ethernet CSMA/CD *)
  (* --- *)
end (* Random *)


   (** A "delay" is a function that sleeps (applying Thread.sleep) during a random time
    in an evolving range (possibly limited by ~max_delay) *)
module Delay : sig
  (* --- *)
  type p = unit -> unit (* procedure *)
  (* --- *)
  val make : ?max_delay:time -> ?slot:time -> Backoff.f -> p
  (* --- *)
  (* Common cases: *)
  val linear                       : ?max_delay:time     -> ?slot:time -> unit -> p
  val exponential                  : ?max_delay:time     -> ?slot:time -> unit -> p
  val binary_exponential           : ?max_delay:time     -> ?slot:time -> unit -> p
  val truncated_binary_exponential : ?max_collisions:int -> ?slot:time -> unit -> p  (* Ethernet CSMA/CD *)
  (* --- *)
end (* Delay *)


(** A "wait_until" is a kind of function that waits until a condition becames true,
    applying a function "delay" to sleep between two tests. A couple of thunks
    for unlocking/relocking may be provided to be executed before and after sleeping.
    The result of a function is the value returned by the last relocking call, or it's
    the provided one (identity) if the relocking has never been called. *)
module Wait_until : sig
  (* --- *)
  (* ?timeout_exn is the exception to be raised in case of timeout (by default is Spinning.Timeout) *)
  (* 'lock will be simply "unit" if the locking (relock) function doesn't return a meaningfull information: *)
  type 'lock f =
    ?unlock_relock:(unit thunk * 'lock thunk) -> ?timeout_exn:exn -> ?timeout:seconds -> guard:(unit->bool) -> 'lock -> 'lock
  (* --- *)
   and 'a thunk = unit -> 'a
  (* --- *)
  val make : ?max_delay:time -> ?slot:time -> Backoff.f -> 'lock f
  (* --- *)
  val linear                       : ?max_delay:time     -> ?slot:time -> unit -> 'lock f
  val exponential                  : ?max_delay:time     -> ?slot:time -> unit -> 'lock f
  val binary_exponential           : ?max_delay:time     -> ?slot:time -> unit -> 'lock f
  val truncated_binary_exponential : ?max_collisions:int -> ?slot:time -> unit -> 'lock f  (* Ethernet CSMA/CD *)
  (* --- *)
end (* Wait_until *)
