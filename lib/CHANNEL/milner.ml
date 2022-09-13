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

(** Named, 1-to-1, synchronous/asynchronous, 1-size value-passing channels.
    Being first-class citizen, they allow the communication of channels (like in pi-calculus).
    ---
    Strictly speaking,

      (1) Milner's channels as initially defined in CCS are not value-passing
          (here they would be of type unit), and

      (2) both in CCS and pi-calculus, the `send' method is supposed to be executed in the synchronous mode,
          while in this module `send' is executed by default in the asynchronous mode. Hence, to force the
          synchronous mode we have to precise the option ~sync:().
    ---
    Milner's theoretical models were initially synchronous in order to have a basic definition of program
    equivalence (bisimilarity), but were later extended (by Milner and others) to cover the asynchronous
    case.
    *)

(* The channel may be empty or it may contain a message: *)
type 'a t = ('a option) Channel.t

let create ?reviewer () = Channel.create ?reviewer (None)

(* An extract of channel.mli:
   ---
   val access :
     ?level:int -> ?ephemeral:unit -> ?enter:('a -> bool) -> ?notify:int list -> ?update:('a -> 'a) -> ?leave:('a -> bool) ->
     'a t -> ('a -> 'a -> 'b) -> 'b
   ---
*)

let receive (t:'a t) : 'a =
  Channel.access
    ~level:(Channel.writer)
    ~enter:(fun x -> x <> None)  (* we receive only when there's something to get *)
    ~update:(fun x -> None)      (* the buffer is emptied *)
    (t)
    (* --- *)
    (fun x0 x1 -> match x0 with  (* now x1 is None *)
     | Some msg -> msg
     | None -> assert false
     )

(* Asynchronous. (Could be also defined with Channel.set). *)
let send (t:'a t) (msg:'a) : unit =
  Channel.access
    ~level:(Channel.writer)
    ~enter: (fun x -> x = None)  (* we send only when the place is empty *)
    ~update:(fun x -> Some msg)  (* the buffer is filled *)
    (t)
    (* --- *)
    (fun x0 x1 -> ())            (* nothing else to do *)

(* Synchronous send (Milner's model): *)
let send_sync (t:'a t) (msg:'a) : unit =
  Channel.access
    ~level:(Channel.writer)
    ~enter: (fun x -> x = None)  (* we send only when the place is empty *)
    ~update:(fun x -> Some msg)  (* the buffer is filled *)
    ~leave: (fun x -> x = None)  (* we leave the procedure when someone has received the message *)
    (t)
    (* --- *)
    (fun x0 x1 -> ())            (* nothing else to do *)

(* Group the two functions: *)
let send ?sync =
  match sync with
  | None -> send
  | Some () -> send_sync

(* val taste : 'a t -> 'a option
   ---
   Note that this function could be defined simply as (Channel.get t) but, in this way,
   the result will be non-deterministic in the case of a disjunction. *)
let taste (t:'a t) : 'a option =
 (* Channel.fold (t) (None) (fun s lcore -> if s <> None then s else Lazy.force lcore) *)
    Channel.find t ((<>)None) |> Option.join

(* ---
   Object-oriented interface:
   --- *)

type 'a obj = < receive : 'a; send : 'a -> unit; taste : 'a option; hermit:'a t >

let objectify (t:'a t) : 'a obj =
  object
    method send = send t
    method receive = receive t
    method taste = taste t
    method hermit = t
  end

let new_channel () = objectify (create ())

