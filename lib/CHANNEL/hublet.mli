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
   number of threads that have been already received this message:
   *)
type 'a t = (('a * ack_nb) option) Channel.t
 and ack_nb = int

val create  : unit -> 'a t
(* --- *)
val send    : ?sync:unit -> ?force:unit -> 'a t -> 'a -> unit
val receive : 'a t -> 'a
val taste   : 'a t ->  ('a * ack_nb) option
(* --- *)
(* Set the channel value to `None'. With ~sync wait for the last message has been received: *)
val reset   : ?sync:unit -> 'a t -> unit

(* Object oriented interface: *)
type 'a obj = <
  receive : 'a;
  send    : ?sync:unit -> ?force:unit -> 'a -> unit;
  taste   : ('a * ack_nb) option;
  reset   : unit;
  hermit  : 'a t
  >
(* --- *)
val objectify : 'a t -> 'a obj

(* Create a new channel and immediately put it in a object shell: *)
val new_channel : unit -> 'a obj

(* --------------------
     Some basic tests
   --------------------

(* I use again the name `m', not standing for (M)ilner.t, but for (m)ulticast. *)

let m = Hublet.create () ;;
(* val m : '_a Hublet.t *)

Hublet.send m "hello";;
(* - : unit = () *)

Future.make (fun () -> Hublet.send m "greetings from future") () ;;
(* - : unit Future.t = <abstr> *)

Hublet.send ~force:() m "hello world";

Hublet.receive m ;;
(* - : string = "hello world" *)
Hublet.receive m ;;
(* - : string = "greetings from future" *)
Hublet.receive m ;;
(* - : string = "greetings from future" *)

Hublet.send m "bye";;
(* - : unit = () *)

Hublet.receive m ;;
(* - : string = "bye" *)
Hublet.receive m ;;
(* - : string = "bye" *)

let make_receiver (name) =
  Future.make (fun () -> let msg = Hublet.receive m in Misc.pr "future %s: received: '%s'\n" name msg) () ;;

(* Reset m: *)
Hublet.reset m;; (* equivalent to: Channel.set m None ;; *)
Hublet.taste m;;
(* - : (string * int) option = None *)

let f1 = make_receiver "f1" ;;
let f2 = make_receiver "f2" ;;
let f3 = make_receiver "f3" ;;

let m = Hublet.objectify m ;;
(* val m : string Hublet.obj = <obj> *)

m#send "Hope there are several receivers" ;;
(* - : unit = ()
future f1: received: 'Hope there are several receivers'
future f2: received: 'Hope there are several receivers'
future f3: received: 'Hope there are several receivers'
*)

(* --------------------
     Like pi-calculus
    but with multicast
   -------------------- *)

let m1 = Hublet.create () ;;
let m2 = Hublet.create () ;;
let m  = Channel.plus m1 m2 ;;
let pi = Hublet.create () ;;

(* --- A thread receives a channel then RECEIVES something through this channel --- *)

let make_receiver (name) =
  Future.make (fun () -> let ch = Hublet.receive pi in let msg = Hublet.receive ch in Misc.pr "future %s: received: '%s' through a received channel\n" name msg) () ;;
(* val make_receiver : string -> unit Future.t = <fun> *)

Hublet.send pi m ;; (* where m = m1+m2 *)
(* - : unit = () *)

Hublet.taste pi ;;
(* - : (string Hublet.t * int) option *)

let f1, f2, f3 = make_receiver "f1", make_receiver "f2", make_receiver "f3" ;;

Hublet.send m1 "hello sent through m1";;
Hublet.send m2 "world sent through m2";;
(*
- : unit = ()
future f3: received: 'hello sent through m1' through a received channel
future f1: received: 'hello sent through m1' through a received channel
future f2: received: 'hello sent through m1' through a received channel
- : unit = ()
*)

(* NOTE that m is always available on channel pi, because pi is a multicast
   channel (hublet), not a unicast (Milner's) channel.
   So relaunching the threads, m will be taken from pi, then a
   receive operation on the sum (m1+m2) will be executed.
   Note also that some thread will receive from m1, other from m2 because
   the choice between "paths" m1 and m2 is randomized in the "directory" m
   (see channel.ml).
   *)

let f1, f2, f3 = make_receiver "f1", make_receiver "f2", make_receiver "f3" ;;
(*
future f3: received: 'hello sent through m1' through a received channel
future f2: received: 'hello sent through m1' through a received channel
future f1: received: 'world sent through m2' through a received channel
*)

let f1, f2, f3 = make_receiver "f1", make_receiver "f2", make_receiver "f3" ;;
(*
future f3: received: 'world sent through m2' through a received channel
future f2: received: 'hello sent through m1' through a received channel
future f1: received: 'hello sent through m1' through a received channel
*)

let f1, f2, f3 = make_receiver "f1", make_receiver "f2", make_receiver "f3" ;;
(*
future f3: received: 'world sent through m2' through a received channel
future f2: received: 'world sent through m2' through a received channel
future f1: received: 'world sent through m2' through a received channel
*)

(* --- Removing a choice for threads: --- *)

let m2 = Hublet.objectify m2 ;;
(* val m2 : string Hublet.obj = <obj> *)
m2#reset ;;
(* - : unit = () *)

let f1, f2, f3 = make_receiver "f1", make_receiver "f2", make_receiver "f3" ;;
(*
future f3: received: 'hello sent through m1' through a received channel
future f1: received: 'hello sent through m1' through a received channel
future f2: received: 'hello sent through m1' through a received channel *)

let f1, f2, f3 = make_receiver "f1", make_receiver "f2", make_receiver "f3" ;;
(*
future f3: received: 'hello sent through m1' through a received channel
future f1: received: 'hello sent through m1' through a received channel
future f2: received: 'hello sent through m1' through a received channel *)

(* --- Sending with choices: --- *)

let m  = Hublet.objectify m ;;
let m1 = Hublet.objectify m1 ;;

m#send "This is the last example. Bye." ;;
(* - : unit = () *)

let f1, f2, f3 = make_receiver "f1", make_receiver "f2", make_receiver "f3" ;;
(*
future f3: received: 'This is the last example. Bye.' through a received channel
future f1: received: 'This is the last example. Bye.' through a received channel
future f2: received: 'This is the last example. Bye.' through a received channel *)

(* Because m#send has be done on m1, while m2 contains None (previous reset): *)

m1#taste ;;
(* - : (string * int) option = Some ("This is the last example. Bye.", 9) *)
m2#taste ;;
(* - : (string * int) option = None *)

(* Note that hublets, in a sense, are not completely closed w.r.t. the Channel.sum.
   Actually, the method `taste' is now randomized: *)

m#taste ;;
(* - : (string * int) option = None *) (* selected m2 *)

m#taste ;;
(* - : (string * int) option = None *) (* again m2 *)

m#taste ;;
(* - : (string * int) option = Some ("This is the last example. Bye.", 9) *)  (* now choosed m1! *)

(* Now, if we send twice through m, the second time there will be no choice: *)

m#send "This is the last example (really). Bye." ;;
m#send "This is the last example (really, I promise). Bye." ;;

let f1, f2, f3 = make_receiver "f1", make_receiver "f2", make_receiver "f3" ;;
(*
future f3: received: 'This is the last example (really). Bye.' through a received channel
future f1: received: 'This is the last example (really, I promise). Bye.' through a received channel
future f2: received: 'This is the last example (really). Bye.' through a received channel *)

*)
