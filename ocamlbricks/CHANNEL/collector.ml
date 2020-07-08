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

(** Collect messages from several sources asynchronously.
    Several "maintainers" put their message asynchronously and, from time to time,
    a (non prioritary) "writer" flush the container.
    *)

(* The core of the channel is simply a list: *)
type 'a t = ('a list) Channel.t

let create () = Channel.create []

let flush (t:'a t) : 'a list =
  Channel.access
    ~level:(Channel.writer)
    ~enter:((<>)[])          (* we can flush only when there's something in the list *)
    ~update:(fun xs -> [])   (* the buffer is emptied *)
    (t)
    (* --- *)
    (fun xs0 _xs1 -> xs0)    (* now _xs1 is the empty list *)

(* Any condition (guard) is needed to add a message: *)
let add (t:'a t) (msg:'a) : unit =
  Channel.access
    ~level:(Channel.maintainer)
    ~update:(fun xs -> msg::xs)  (* the message is added on top of the list ... *)
    (t)
    (* --- *)
    (fun _xs0 _xs1 -> ())        (* ... and there's nothing else to do *)

(* val taste : 'a t -> 'a option
   ---
   Note that this function could be defined simply as (Channel.get t) but, in this way,
   the result will be non-deterministic in the case of a disjunction. *)
let taste (t:'a t) : ('a list) option =
    Channel.find t ((<>)[])

