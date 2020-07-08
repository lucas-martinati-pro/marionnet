(* This file is part of ocamlbricks
   Copyright (C) 2011 2012 2013  Jean-Vincent Loddo

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

IFNDEF OCAML4_02_OR_LATER THEN
type bytes = string
ENDIF

(** Similar to [Thread.create] with two differences:

    (1) you may create a killable thread (but only a limited number of threads
        of your application may be killable at the same time, i.e. 31)

    (2) you are able to call [ThreadExtra.at_exit] in the function ('a -> 'b)
        that will be executed in the created thread.

    Note that there are only 31 (from signal 34 to 64, hence 64-34+1=31) possible threads per process that
    may run simultaneously with the capability of being killed. For this reason, when the option ~killable
    is set up, the call is blocking until a "signal slot" became available for the thread that will be created.
    *)
val create : ?killable:unit -> ('a -> 'b) -> 'a -> Thread.t
val future : ?killable:unit -> ('a -> 'b) -> 'a -> 'b Future.t

(* Similar to Unix.read but with a way to exit waiting. The "exit_door" should be a read
   descriptor fd0 resulting from a [let fd0, fd1 = Unix.pipe ()]. With this trick, the
   read mechanism can be broken (by a Failure exception) simply providing ~exit_door:fd0
   and closing the write descriptor fd1 when desired. *)
val read_with_exit_door :
  ?timeout:float -> (* (-1.) i.e. no timeout by default *)
  exit_door:Unix.file_descr (* read descriptor of Unix.pipe *) ->
  Unix.file_descr -> bytes (* buffer *) -> int (* offset *) -> int (* len *) -> int

(* See `read_with_exit_door': *)
val recv_with_exit_door :
  ?timeout:float -> (* (-1.) i.e. no timeout by default *)
  exit_door:Unix.file_descr (* read descriptor of Unix.pipe *) ->
  Unix.file_descr -> bytes (* buffer *) -> int (* offset *) -> int (* len *) -> int

(** Create a thread that waits for a process termination. By default the process is killed if
    the application terminates (by default we suppose that the application is the father and
    the owner of this process). *)
val waitpid_thread :
  ?killable:unit ->
  ?before_waiting:(pid:int -> unit) ->
  ?after_waiting:(pid:int -> Unix.process_status -> unit) ->
  ?perform_when_suspended:(pid:int -> unit) ->
  ?perform_when_resumed:(pid:int -> unit) ->
  ?fallback:(pid:int -> exn -> unit) ->
  ?do_not_kill_child_at_exit:unit ->
  unit -> (pid:int -> Thread.t)

(** Apply [Unix.fork] immediately creating a thread that waits for the termination of this fork. *)
val fork_with_tutor :
  ?killable:unit ->
  ?before_waiting:(pid:int->unit) ->
  ?after_waiting:(pid:int -> Unix.process_status -> unit) ->
  ?perform_when_suspended:(pid:int -> unit) ->
  ?perform_when_resumed:(pid:int -> unit) ->
  ?fallback:(pid:int -> exn -> unit) ->
  ?do_not_kill_child_at_exit:unit ->
  ('a -> 'b) -> 'a -> unit Future.t

module Easy_API : sig

  type options

  val make_options :
    ?enrich:options ->
    ?killable:unit ->
    ?before_waiting:(pid:int->unit) ->
    ?after_waiting:(pid:int -> Unix.process_status -> unit) ->
    ?perform_when_suspended:(pid:int -> unit) ->
    ?perform_when_resumed:(pid:int -> unit) ->
    ?fallback:(pid:int -> exn -> unit) ->
    ?do_not_kill_child_at_exit:unit ->
    unit -> options

  val waitpid_thread :
    ?options:options ->
    unit -> (pid:int -> Thread.t)

  val fork_with_tutor :
    ?options:options ->
    ('a -> 'b) -> 'a -> unit Future.t

end (* Easy_API *)

val at_exit : (unit -> unit) -> unit

val kill      : Thread.t -> bool
val killall   : unit -> unit
val killable  : unit -> int list
val killer    : Thread.t -> unit -> unit

val set_killable_with_thunk : ?who:Thread.t -> (unit -> unit) -> unit

val id_kill   : int -> bool
val id_killer : int -> unit -> unit

val delayed_kill    : float -> Thread.t -> unit
val delayed_killall : float -> unit
val delayed_id_kill : float -> int -> unit

val delay : float -> unit
