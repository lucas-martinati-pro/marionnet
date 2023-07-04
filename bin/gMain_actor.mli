(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2023  Jean-Vincent Loddo
   Copyright (C) 2023  Université Sorbonne Paris Nord

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

(* Transform the GTK main thread in a actor (https://en.wikipedia.org/wiki/Actor_model)
   --
   All these tools should be called by a "client" thread other than the GTK main thread (gtk_main).
   However, the GTK main thread may call these tools: in this case, they became the standard
   function application (just protected from exceptions). Using the function Thread.id we prevent
   the GTK main thread to remain stucked in a deadlock (waiting for a message from itself).
   ---
   Examples:
     let () = GMain_actor.delegate window#destroy ()
     ---
     let y = GMain_actor.apply (fun x -> x*2) (21) in
     Log.printf1 "Created thread: testing a call to the GTK main thread: result is %d\n" (Either.find_right y |> Option.extract);
   ---
   *)

(* Classic (synchronous) call: *)
val apply   : ?prio:int -> ('a -> 'b) -> 'a -> (exn, 'b) Either.t
val apply2  : ?prio:int -> ('a -> 'b -> 'c) -> 'a -> 'b -> (exn, 'c) Either.t
val apply3  : ?prio:int -> ('a -> 'b -> 'c -> 'd) -> 'a -> 'b -> 'c -> (exn, 'd) Either.t
(* --- *)
val apply_extract  : ?prio:int -> ('a -> 'b) -> 'a -> 'b
val apply2_extract : ?prio:int -> ('a -> 'b -> 'c) -> 'a -> 'b -> 'c
val apply3_extract : ?prio:int -> ('a -> 'b -> 'c -> 'd) -> 'a -> 'b -> 'c -> 'd

(* These procedures may be asynchronous setting ~async:(). In this case
   the caller doesn't wait for the result; it just gives the "order" of
   applying the function to `gtk_main' then returns immediately to its own activity: *)
val delegate  : ?async:unit -> ?prio:int -> ('a -> unit) -> 'a -> unit
val delegate2 : ?async:unit -> ?prio:int -> ('a -> 'b -> unit) -> 'a -> 'b -> unit
val delegate3 : ?async:unit -> ?prio:int -> ('a -> 'b -> 'c -> unit) -> 'a -> 'b -> 'c -> unit

(* Asynchronous call with retreivable result: *)
val future  : ?prio:int -> ('a -> 'b) -> 'a -> ((exn, 'b) Either.t) Ocamlbricks.Future.t
val future2 : ?prio:int -> ('a -> 'b -> 'c) -> 'a -> 'b -> ((exn, 'c) Either.t) Ocamlbricks.Future.t
val future3 : ?prio:int -> ('a -> 'b -> 'c -> 'd) -> 'a -> 'b -> 'c -> ((exn, 'd) Either.t) Ocamlbricks.Future.t

(* --- Low-level control: *)
val am_I_the_GTK_main_thread : unit -> bool

