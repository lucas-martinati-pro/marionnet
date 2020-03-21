(* This file is part of ocamlbricks
   Copyright (C) 2013  Jean-Vincent Loddo

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


(** Common recurrent cortex instances (process, service,..). *)

module Process : sig

  type program = string
  type arguments = string list
  type pid = int
  type birthtime = float (* since 00:00:00 GMT, Jan. 1, 1970, in seconds *)
  type age  = float (* duration, in seconds *)
  type exit_code = int
  type signal_name = string
  type mrproper = unit -> unit

  type options
  type tuning = unit -> options
  val make_options :
    ?enrich:options ->
    ?stdin:Endpoint.Source.t ->
    ?stdout:Endpoint.Sink.t ->
    ?stderr:Endpoint.Sink.t ->
    ?pseudo:string ->
    unit -> options

  module State : sig

    type running_state = Running | Suspended

    type t =
      | Planned    of tuning * program * arguments
      | Started    of program * birthtime * pid * mrproper * running_state
      | Terminated of program * age * pid * (signal_name, exit_code) Either.t

    val equality : t -> t -> bool

    val is_planned       : t -> bool
    val is_started       : t -> bool
    val is_suspended     : t -> bool
    val is_running       : t -> bool
    val is_terminated    : t -> bool
    val is_terminated_and_has_been_really_executed : t -> bool
    val is_terminated_aged_at_least : seconds:float -> t -> bool
    val birthtime : t -> float option
    val age : t -> float option

  end (* Process.State *)

  type t = State.t Cortex.t
  type u = State.t Cortex.u (* open cortex *)

  val plan :
    ?tuning:(unit -> options) ->
    program -> arguments -> t

  module Open :
    sig
      val plan :
	?tuning:(unit -> options) ->
	program -> arguments -> u
    end

  val start     : t -> State.t * bool
  val suspend   : ?nohang:unit -> t -> State.t * bool
  val resume    : ?nohang:unit -> t -> State.t * bool
  val terminate : ?nohang:unit -> t -> State.t * bool

  class c :
    ?tuning:(unit -> options) ->
    program ->
    arguments ->
    object
      inherit [State.t] Cortex.Object.with_private_interface
      method start     : unit -> State.t * bool
      method suspend   : ?nohang:unit -> unit -> State.t * bool
      method resume    : ?nohang:unit -> unit -> State.t * bool
      method terminate : ?nohang:unit -> unit -> State.t * bool
    end

end

module Service : sig

  type t = (Process.State.t option * Process.t) Cortex.t

  val plan :
    ?tuning:Process.tuning ->
    Process.program -> Process.arguments -> t

  val start                    : t -> Process.State.t * bool
  val previous_status          : t -> Process.State.t option
  val previous_really_executed : t -> bool
  val previous_age             : t -> float option
  val previous_aged_at_least   : seconds:float -> t -> bool
  val status                   : t -> Process.State.t
  val suspend                  : t -> Process.State.t * bool
  val resume                   : ?nohang:unit -> t -> Process.State.t * bool
  val stop                     : ?nohang:unit -> t -> Process.State.t * bool
  val restart                  : t -> Process.State.t * bool

  class c :
    ?tuning:Process.tuning ->
    Process.program ->
    Process.arguments ->
    object
      inherit
        [Process.State.t option * Process.t]
           Cortex.Object.with_private_interface
      method start                    : unit -> Process.State.t * bool
      method previous_status          : unit -> Process.State.t option
      method previous_really_executed : unit -> bool
      method previous_age             : unit -> float option
      method previous_aged_at_least   : seconds:float -> bool
      method status                   : unit -> Process.State.t
      method suspend                  : unit -> Process.State.t * bool
      method resume                   : ?nohang:unit -> unit -> Process.State.t * bool
      method stop                     : ?nohang:unit -> unit -> Process.State.t * bool
      method restart                  : unit -> Process.State.t * bool
    end

end

(* 1-position communication channels: *)
module Channel : sig

  (* The channel may be empty or it may contain a message for someone *)
  type 'a t = ('a option) Cortex.t

  val return :
    ?equality:('a -> 'a -> bool) ->
    ?on_proposal:('a option -> 'a option -> 'a option) ->
    ?on_commit:('a option -> 'a option -> unit) ->
    ?init:'a ->
    unit -> 'a t

  val receive  : 'a t -> 'a
  val send     : 'a t -> 'a -> bool (* success/failure of sending *)

end (* Channel *)

module Clock : sig
  type t = int Cortex.t
  val make : ?init:int -> ?limit:int -> ?delay:float -> unit -> t
end

