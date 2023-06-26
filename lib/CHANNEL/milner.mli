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
    case which appears as more interesting in practice.
    *)

(* The core is simply of type ('a option): *)
type 'a t = ('a option) Channel.t

(* --- *)
(* type 'a reviewer = ('a option -> 'a option -> 'a option Res.review) *)
(* --- *)
val create : ?reviewer:('a option) Res.reviewer -> unit -> 'a t
(* --- *)
val send    : ?sync:unit -> 'a t -> 'a -> unit
val receive : 'a t -> 'a
val taste   : 'a t -> 'a option

(* Object oriented interface: *)

type 'a obj = < receive : 'a; send : 'a -> unit; taste : 'a option; hermit:'a t >
val objectify : 'a t -> 'a obj

(* Create a new channel and immediately put it in a object shell: *)
val new_channel : unit -> 'a obj

(* --------------------
     Some basic tests
   --------------------

let m = Milner.create () ;;
(* val m : '_a option Channel.t *)

Milner.send m "hello";;
(* - : unit = () *)

Milner.receive m ;;
(* - : string = "hello" *)

(* Asynchronous: *)
Milner.send m "bonjour";;

let f = Future.make (fun () -> let msg = Milner.receive m in Misc.pr "future f: received: %s\n" msg) () ;;
(*
val f : unit Future.t = <abstr>
future f: received: bonjour
*)

(* Now, receive() (by f on m) starts before send() (on m): *)
let f = Future.make (fun () -> let msg = Milner.receive m in Misc.pr "future f: received: %s\n" msg) () ;;
(* val f : unit Future.t = <abstr> *)

Milner.send m "ciao";;
(*
- : unit = ()
future f: received: ciao
*)

(* ---
   With a reviewer (capitalize the message!):
   --- *)

let m = Milner.create
  ~reviewer:(fun _x0 -> function (Some s1) -> let s1' = String.capitalize_ascii s1 in if s1' = s1 then Res.accepted () else Res.revised (Some s1') | None -> Res.accepted ())
  () ;;
(* val m : string Milner.t *)

Milner.send m "hello" ;;
(* - : unit = () *)

Milner.receive m ;;
(* - : string = "Hello" *)

Milner.taste m ;;
(* - : string option = None *)

(* --------------------
       m = m1 + m2
   -------------------- *)

let m1 = Milner.create () ;;
(* val m1 : '_a option Channel.t *)

let m2 = Milner.create () ;;
(* val m2 : '_a option Channel.t *)

let m = Channel.plus m1 m2 ;;
(* val m : '_a option Channel.t *)

Milner.send m1 "hello sent through m1";;
(* - : unit = () *)

Milner.taste m1 ;;
(* - : string option = Some "hello sent through m1" *)

Milner.taste m2 ;;
(* - : string option = None *)

Milner.taste m ;;
(* - : string option = Some "hello sent through m1" *)

Milner.receive m ;;
(* - : string = "hello sent through m1" *)

Milner.taste m ;;
(* - : string option = None *)

(* ---
   At this point, the channel m (which is m1+m2) is empty
   --- *)

(* Launch a thread that waits on m (which is m1+m2): *)
let f = Future.make (fun () -> let msg = Milner.receive m in Misc.pr "future f: received: %s\n" msg) () ;;
(* val f : unit Future.t *)

Milner.send m1 "hello sent through m1";;
(* - : unit = ()
future f: received: hello sent through m1
*)

(* --- *)

(* Again, launch a new thread that waits on m (which is m1+m2): *)
let f = Future.make (fun () -> let msg = Milner.receive m in Misc.pr "future f: received: %s\n" msg) () ;;
(* val f : unit Future.t = <abstr> *)

Milner.send m2 "hello sent through m2";;
(* - : unit = ()
future f: received: hello sent through m2
*)

(* Now send() and receive() work on sum m = m1+m2: *)
Milner.send m "hello sent through m (m1+m2)";;
(* - : unit = () *)

let f = Future.make (fun () -> let msg = Milner.receive m in Misc.pr "future f: received: %s\n" msg) () ;;
(* future f: received: hello sent through m (m1+m2) *)

(* Now, almost the same, but receive() (by f on m) is launched before send() (on m): *)
let f = Future.make (fun () -> let msg = Milner.receive m in Misc.pr "future f: received: %s\n" msg) () ;;
(* val f : unit Future.t  *)

Milner.send m "hello sent through m (m1+m2)";;
(* - : unit = ()
future f: received: hello sent through m (m1+m2)
*)

(* --------------------
       pi-calculus
   -------------------- *)

let pi = Milner.create () ;;

(* --- A thread receives a channel then RECEIVES something through this channel --- *)

let f = Future.make (fun () -> let ch = Milner.receive pi in let msg = Milner.receive ch in Misc.pr "future f: received: '%s' through a received channel\n" msg) () ;;
(* val f : unit Future.t = <abstr> *)

Milner.send pi m ;; (* where m = m1+m2 *)
(* - : unit = () *)

Milner.send m2 "hello sent through m2";;
(* - : unit = ()
future f: received: 'hello sent through m2' through a received channel
*)

(* --- A thread receives a channel then SENDS something through this channel in synchronous mode: --- *)

let f = Future.make (fun () -> let ch = Milner.receive pi in Milner.send ~sync:() ch "future f: used a received channel to send this message") () ;;
(* val f : unit Future.t = <abstr> *)

Milner.send pi m ;;
(* - : unit = () *)

Milner.receive m ;;
- : string = "future f: used a received channel to send this message"

(* --------------------
         Triad
   -------------------- *)

let c1 = Milner.create () ;;
let c2 = Milner.create () ;;
let c = Channel.product c1 c2 ;;

Milner.send c1 42 ;;
Milner.send c2 "hello" ;;
Channel.get c ;;
(* - : int option * string option = (Some 42, Some "hello") *)

(* Create a mapping ("view") *)
let m = Channel.map (fun (x,y) -> Option.combine x y) c ;;

Milner.taste m ;;
(* - : (int * string) option = Some (42, "hello") *)

Milner.receive m ;;
(* - : int * string = (42, "hello") *)

(* The "view" is read-only: *)
Milner.receive m ;;
(* - : int * string = (42, "hello") *)

(* --- *)

let msg2 = Milner.receive c2 ;;
(* val msg2 : string = "hello" *)

let c12 = Milner.create () ;;

let triad = Channel.product ~reviewer:(fun ((x0,y0),z0) ((x1,y1),z1) ->
  if (z1=None) && (x1<>None) && (y1<>None) then Res.revised ((None,None), Option.combine x1 y1) else Res.accepted ()) c c12 ;;
(* val triad : ((int option * string option) * (int * string) option) Channel.t *)

(* The triad is not a Milner's channel, so we cannot call Milner's method: *)
Channel.get triad ;;
(* - : (int option * string option) * (int * string) option = ((Some 42, None), None) *)

Milner.send c2 "ciao" ;;
(* - : unit = () *)

Channel.get triad ;;
(* - : (int option * string option) * (int * string) option = ((None, None), Some (42, "ciao")) *)

let f1 = Future.make (fun () -> let (msg1,msg2) = Milner.receive c12 in Misc.pr "future f1: received: (%d,\"%s\")\n" msg1 msg2) () ;;
(* val f1 : unit Future.t *)

let f2 = Future.make (fun () -> let (msg1,msg2) = Milner.receive c12 in Misc.pr "future f2: received: (%d,\"%s\")\n" msg1 msg2) () ;;
(* val f2 : unit Future.t *)

Channel.get triad ;;
(* - : (int option * string option) * (int * string) option = ((None, None), None) *)

Milner.send c1 50 ;;

Channel.get triad ;;
(* - : (int option * string option) * (int * string) option = ((Some 50, None), None) *)

Milner.send c2 "Actions speak louder than words" ;;
(*
- : unit = ()
future f2: result of receive: (50,"Actions speak louder than words") *)

Channel.get triad ;;
(* - : (int option * string option) * (int * string) option = ((None, None), None) *)

Milner.send c1 55 ;;
(* - : unit = () *)

Milner.send c2 "The more things change, the more they stay the same" ;;
(* - : unit = ()
future f1: result of receive: (55,"The more things change, the more they stay the same") *)

*)
