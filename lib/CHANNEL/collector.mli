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

val create : unit -> 'a t
(* --- *)
val flush : 'a t -> 'a list
val add   : 'a t -> 'a -> unit
(* --- *)
val taste : 'a t -> ('a list) option (* disjunctive-meaning: ∃ *)

(* --------------------
     Some basic tests
   --------------------

let c = Collector.create () ;;
(* val c : '_a Collector.t *)

List.iter (fun x -> Future.make (fun () -> Collector.add c x) () |> ignore) [10; 16; 23; 51] ;;
(* - : unit = () *)

Collector.taste c ;;
(* - : int list option = Some [16; 23; 51; 10] *)

Collector.flush c ;;
(* - : int list = [16; 23; 51; 10] *)

Collector.taste c ;;
(* - : int list option = None *)

List.iter (fun x -> Future.make (fun () -> if x=30 then ignore (Collector.flush c) else Collector.add c x) () |> ignore) [10; 20; 30; 40; 50; 60; 70] ;;
(* - : unit = () *)

(* Note that even if the flusher starts among the first threads (is the third), it waits until all maintainers put their message: *)
Collector.taste c ;;
(* - : int list option = None *)

(* --------------------
       d = c + c'
   -------------------- *)

let c' = Collector.create () ;;
(* val c' : '_a Collector.t *)

let d = Channel.plus c c' ;;
(* val d : int list Channel.t *)

Collector.taste d ;;
(* - : int list option = None *)

Collector.add c' 11 ;;
(* - : unit = () *)

Collector.taste d ;;
(* - : int list option = Some [11] *)

Collector.add c' 12 ;;
(* - : unit = () *)

Collector.taste d ;;
(* - : int list option = Some [12; 11] *)

Collector.add c 111 ;;
(* - : unit = () *)

Collector.taste d ;;
(* - : int list option = Some [111] *)

Collector.flush d ;;
(* - : int list = [12; 11] *)

Collector.flush d ;;
(* - : int list = [111] *)

*)
