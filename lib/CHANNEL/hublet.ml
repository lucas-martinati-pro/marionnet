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

(** Named, 1-to-N, synchronous/asynchronous, 1-size value-passing channels.
    The purpose of this structure is to allow multicast communications.
    *)

(* The channel may be empty or it may contain a message
   together with the number of acknowledgements, i.e. the
   number of threads that have been already received this message: *)
type 'a t = (('a * ack_nb) option) Channel.t
 and ack_nb = int

let create () = Channel.create None

(* An extract of channel.mli:
   ---
   val access :
     ?level:int -> ?ephemeral:unit -> ?enter:('a -> bool) -> ?notify:int list -> ?update:('a -> 'a) -> ?leave:('a -> bool) ->
     'a t -> ('a -> 'a -> 'b) -> 'b
   ---
*)

let receive (t:'a t) : 'a =
  Channel.access
    ~level:(Channel.maintainer)  (* receivers are prioritary w.r.t senders *)
    ~enter:(fun x -> x <> None)  (* we receive only when there's something to get *)
    ~update:(function Some (msg, ack_nb) -> Some (msg, ack_nb + 1) | None -> assert false)
    (t)
    (* --- *)
    (fun x0 -> function
     | Some (msg, ack_nb) -> msg
     | None -> assert false
     )

(* We can send a message only if the place is empty (None) or the previous message has been received (ack_nb>0): *)
let could_we_send_a_message : ('a * ack_nb) option -> bool =
  function
  | Some (msg, ack_nb) when ack_nb = 0 -> false
  | _ -> true

(* --- *)

(* Asynchronous version: *)
let send ?force (t:'a t) : 'a -> unit =
  let level, enter = match force with
  | None    -> Channel.writer, Some could_we_send_a_message
  | Some () -> Channel.maintainer, None
  (* --- *)
  in
  (* Channel.set is a simplified form of Channel.access: *)
  fun (msg: 'a) ->
    Channel.set ~level ?enter (t) (Some (msg, 0)) (* ack_nb is reset to 0 *)

(* Synchronous version: we leave the procedure when someone has received
   the message sent. In other words, exactly when we could send a new message,
   if we wanted to: *)
let send_sync ?force (t:'a t) : 'a -> unit =
  let level, enter = match force with
  | None    -> Channel.writer, Some could_we_send_a_message
  | Some () -> Channel.maintainer, None
  (* --- *)
  in
  (* Channel.set is a simplified form of Channel.access: *)
  fun (msg: 'a) ->
    Channel.set ~level ?enter ~leave:(could_we_send_a_message) (t) (Some (msg, 0)) (* ack_nb is reset to 0 *)

(* Group the two functions: *)
let send ?sync =
  match sync with None -> send | Some () -> send_sync

(* --- *)

(* Similar to send, but the buffer is simply emptied.
   Also, the update is called with an higher priority i.e. as "maintainer". *)
let reset (t:'a t) : unit =
   Channel.set ~level:(Channel.maintainer) (t) None

(* Synchronous version: wait for the reception of the last sent message, then remove it: *)
let reset_sync (t:'a t) : unit =
   Channel.set ~level:(Channel.maintainer) ~enter:(could_we_send_a_message) (t) None

(* Group the two functions: *)
let reset ?sync =
  match sync with None -> reset | Some () -> reset_sync

(* --- *)

(* Channel.get is executed as "reader": *)
let taste (t:'a t) : ('a * ack_nb) option =
    Channel.find t ((<>)None) |> Option.join

(* Object-oriented interface: *)
type 'a obj = <
  receive : 'a;
  send    : ?sync:unit -> ?force:unit -> 'a -> unit;
  taste   : ('a * ack_nb) option;
  reset   : unit;
  hermit  : 'a t
  >

let objectify (t:'a t) : 'a obj =
  object
    method send ?sync ?force msg = send t ?sync ?force msg
    method receive = receive t
    method taste = taste t
    method reset = reset t
    method hermit = t
  end

let new_channel () = objectify (create ())

