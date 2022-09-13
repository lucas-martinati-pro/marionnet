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

(* ------------------------------------------ *)
(*            Multi-level locks               *)
(* ------------------------------------------ *)

(* ------------------------ *)
(*        ADD_GUARDS        *)
(*    (General pattern)     *)
(* ------------------------ *)

(* The word "basic" stands here for "raw but multi-level": *)

module Guard :
  sig
    (* None stands for false, Some (action) for true (with action as continuation): *)
    type t = unit -> action option
     and action = unit -> unit
     and ts = t array
    (* --- *)
    type 'a g = 'a -> action option
     and 'a gs = ('a g) array
  end

module type BASIC_METHODS =
   sig
     type t
     (* --- *)
     val lock     : t -> unit
     val try_lock : t -> bool
     (* --- *)
     module BASIC_Critical : sig
       val wait   : ?level:int -> t -> unit (* needed to implement `lock' with guards *)
       val unlock : t -> unit               (* needed to implement `try_lock' with guards *)
     end
   end (* BASIC_METHODS *)

module type GUARDED_METHODS =
   sig
     type t
     (* --- *)
     val lock     : ?level:int -> ?guards:Guard.ts -> t -> unit
     val try_lock : ?level:int -> ?guards:Guard.ts -> t -> bool
     (* --- *)
     module GUARDED_Critical : sig
      val require : ?level:int -> guards:Guard.ts -> t -> unit
     end
     (* --- *)
   end (* GUARDED_METHODS *)

(* BASIC_METHODS -> GUARDED_METHODS *)
module ADD_GUARDS : functor (Basic: BASIC_METHODS) -> GUARDED_METHODS with type t = Basic.t

(* ------------------------ *)
(*      LEVELS & core       *)
(* ------------------------ *)

type level = int (* >= 0 *)

module type LEVELS = sig
  val levels : int
  (* The "lowest" level is used as default for the optional
     parameter ?level for all tools defined below: *)
  val lowest : level
end

(* ------------------------ *)
(*            RAW           *)
(* ------------------------ *)

(* A condition variable per level: *)
type core = { m: Mutex.t;  wr: waiting_room;  wrt: subscribers; }
  (* --- *)
  (* Set of condition variables on which the thread will `wait': *)
  and waiting_room = (Condition.t array)
  (* --- *)
  (* A weak hashset based on physical equality: *)
  and subscribers  = (waiting_room Hashset.t) Lazy.t

(* --- *)
type waiting_rooms = waiting_room list


module type RAW =
   sig
     type t (* may be `core' or not *)
     val create    : unit -> t
     val levels    : int
     val lowest    : int
     (* --- *)
     val mutex        : t -> Mutex.t
     val waiting_room : t -> waiting_room
     (* --- *)
     val lock      : t -> unit
     val try_lock  : t -> bool
     (* --- *)
     module RAW_Critical : sig
       val wait      : ?level:int -> t -> unit
       val subscribe : t -> waiting_room -> unit
       val broadcast : ?highland:unit -> ?levels:int list (*[]*) -> t -> unit
       val unlock    : ?broadcast_levels:int list (* <= lowland *) -> t -> unit
     end
     (* --- *)
   end (* RAW *)

(* RAW implementation: *)
module Raw : functor (Levels: LEVELS) -> RAW with type t = core


(* ------------------------ *)
(*         GUARDED          *)
(* ------------------------ *)

module type GUARDED =
   sig
     type t
     val create    : unit -> t
     val levels    : int
     val lowest    : level
     (* --- *)
     val mutex        : t -> Mutex.t
     val waiting_room : t -> waiting_room
     (* --- *)
     val compare : t -> t -> int (* compare mutexes *)
     (* --- *)
     val lock      : ?level:int -> ?guards:Guard.ts -> t -> unit
     val try_lock  : ?level:int -> ?guards:Guard.ts -> t -> bool
     (* --- *)
     module Critical : sig
       val require   : ?level:int -> guards:Guard.ts -> t -> unit
       val subscribe : t -> waiting_room -> unit
       val broadcast : ?highland:unit -> ?levels:int list (*[]*) -> t -> unit
       val unlock    : ?broadcast_levels:int list (* <= lowland *) -> t -> unit
     end
     (* --- *)
   end (* GUARDED *)

(* GUARDED implementation: *)
module Guarded : functor (Levels: LEVELS) -> GUARDED with type t = core

(* Make a GUARDED from another Raw and/or Basic: *)
module GUARDED_of_RAW : functor (Raw: RAW) -> GUARDED with type t = Raw.t

(* ------------------------ *)
(*       DISCIPLINED        *)
(* ------------------------ *)

module type DISCIPLINED_METHODS =
   sig
     type t
     val with_lock     : ?level:int -> ?guards:('a Guard.gs) -> ?broadcast_levels:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     val with_try_lock : ?level:int -> ?guards:('a Guard.gs) -> ?broadcast_levels:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
   end

(* DISCIPLINED = GUARDED + DISCIPLINED_METHODS *)
module type DISCIPLINED =
   sig
     include GUARDED
     include DISCIPLINED_METHODS with type t := t
   end

module ADD_DISCIPLINE : functor (Guarded: GUARDED) -> DISCIPLINED_METHODS with type t := Guarded.t (* remove DISCIPLINED_METHODS.t *)
(* --- *)
module DISCIPLINED_of_RAW : functor (Raw: RAW) -> DISCIPLINED with type t = Raw.t

(* ------------------------ *)
(*        PROTOCOL          *)
(* ------------------------ *)

(* Core critical methods: *)
type brdcast_method = ?levels:int list -> unit -> unit

module type PROTOCOL =
   sig
     type data
     val create : unit -> data
     (* --- *)
     val levels    : int           (* cardinality of the domain of levels, which may be strictly greater than #[lowest,highest] *)
     (* Managed levels, which cardinality is (highest - lowest + 1) *)
     val highest   : level         (* highest  managed level *)
     val lowest    : level         (* lowest   managed level *)
     val index_of  : level -> int  (* index of managed level, i.e. level ⊢> max {lowest, min {highest, level}} - lowest *)
     (* --- *)
     val acquire_guards_per_class : ((level * data) Guard.gs) array (* length = number of classes (distinct really managed levels) *)
     val acquire_guards : ?level:int -> data -> Guard.ts
     (* --- *)
     val release_code   : brdcast_method -> ?level:int -> data -> unit
   end (* PROTOCOL *)

type ('a,'b) data_couple = { p1: 'a; p0: 'b }

module COMPOSE_PROTOCOL : functor (P1: PROTOCOL) -> functor (P0: PROTOCOL) -> PROTOCOL with type data = (P1.data, P0.data) data_couple

(* ------------------------ *)
(*      READERS-WRITERS     *)
(* ------------------------ *)

(* A PROTOCOL implementation: *)
module Readers_writer : functor (Levels: LEVELS) -> PROTOCOL

(* Special composition for READERS_WRITERS
   ---
   Levels equals or greater than the highest level (i.e. at least the writer level of P1,
   which is already a "maintainer") must be composed in a special way. Actually, when a
   maintainer would acquire the resource, it must subscribe itself (actions n°1) as
   "waiting writer" at every level. Hence, unconditioned actions n°1 must be grouped and
   executed before other guards.
   *)
module COMPOSE_READERS_WRITERS : functor (P1: PROTOCOL) -> functor (P2: PROTOCOL) -> PROTOCOL

(* ------------------------ *)
(*      PROTOCOLARY         *)
(* ------------------------ *)

module type PROTOCOLARY =
   sig
     include GUARDED
     (* --- *)
     val id : t -> int  (* just an identifier (progressive) *)
     (* --- *)
     val new_waiting_room : unit -> waiting_room
     val subscribe   : t -> waiting_rooms -> unit
     (* --- *)
     val acquire     : ?level:int -> ?guard:(unit -> bool) -> ?waiting_room:waiting_room -> t -> unit
     val try_acquire : ?level:int -> ?guard:(unit -> bool) -> t -> bool
     (* --- *)
     module Protected : sig
       (* wait and require using the owned mutex but with a different waiting_room: *)
       val wait    :  level:int -> ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> waiting_room -> t -> unit
       val require :  level:int -> ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> guard:(unit -> bool) -> waiting_room -> t -> unit
       (* --- *)
       val wait_choosy :
         release_level:int -> wait_level:int -> ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> waiting_room -> t -> unit
       (* --- *)
       val require_choosy :
         release_level:int -> wait_level:int ->
         ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> guard:(unit -> bool) -> waiting_room -> t -> unit
       (* --- *)
       val release : ?level:int -> ?notify:int list (*[]*) -> ?subscribe:waiting_rooms -> t -> unit
     end
     (* --- *)
   end (* PROTOCOLARY *)

(* PROTOCOLARY maker: *)
module NEST_PROTOCOL : functor (Core: GUARDED) -> functor (Protocol: PROTOCOL) -> PROTOCOLARY


(* ------------------------ *)
(*        COMPLETION        *)
(* ------------------------ *)

module type COMPLETE =
   sig
     include PROTOCOLARY
     (* --- *)
     (* --- unlock∘f∘lock *)
     val with_lock        : ?level:int -> ?guards:('a Guard.gs) -> ?broadcast_levels:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     val with_try_lock    : ?level:int -> ?guards:('a Guard.gs) -> ?broadcast_levels:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     (* --- *)
     (* --- release∘f∘acquire *)
     val with_acquire     : ?level:int -> ?guard:('a -> bool) -> ?waiting_room:waiting_room -> ?notify:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     val with_try_acquire : ?level:int -> ?guard:('a -> bool) -> ?notify:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     (* --- *)
     val with_acquire_choosy  :
        ?in_level:int (* lowest *)   ->  ?in_guard:('a -> bool) ->  ?in_waiting_room:waiting_room ->
       ?out_level:int (* in_level *) -> ?out_guard:('a -> bool) -> ?out_waiting_room:waiting_room ->
       ?notify:int list -> (* performed releasing the first time, before waiting for an out_guard, if any *)
       (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     (* --- *)
   end (* COMPLETE *)


module COMPLETION : functor (Protocolary: PROTOCOLARY) -> COMPLETE with type t = Protocolary.t

(* ------------------------ *)
(*       READY-TO-USE       *)
(* ------------------------ *)

(* Single level, simplest locks with 1 condition variable: *)
module Single_level : DISCIPLINED

(* Two levels, readers-writer locks based on 2-levels critical locks: *)
module RW_levels : COMPLETE

(* Three levels, readers-writer-maintainer locks based on 3-levels critical locks: *)
module RWM_levels : COMPLETE


(* ------------------------ *)
(*    COMPLETE commented    *)
(* ------------------------ *)

(* This is the complete signature of a module implementing "locks"
   with different "levels" of use, so different levels of "users".
   ---
   For instance, levels may correspond to "reader", "writer", "maintainer", etc.
   The difference is in the signalling and reception of events: you must wait for a signal
   as member of a *specific* group (not necessarily your own group), but you can broadcast
   to a single group, several groups, or all groups of "users" (i.e. all threads).
   --- *)
module type COMPLETE_commented = (* COMPLETE *)
   sig
     (* --- *)
     (* ========================== CREATION ========================== *)
     type t
     val create : unit -> t
     (* --- *)
     (* The number of condition variables, i.e. the level of priority
        ("reader", "writer", "maintainer", etc). As for arrays, if the levels
        are N, the "users" are indexes in {0..(N-1)}. So, if levels = 1, the
        set of indexes (user classes) is the singleton {0}. *)
     val levels : int
     val lowest : level     (* lowest level (0 in most cases) *)
     (* --- *)
     val mutex        : t -> Mutex.t
     val waiting_room : t -> waiting_room
     (* --- *)
     (* Compare identifiers => compare the age, i.e. the date of creation: *)
     val compare : t -> t -> int
     (* --- *)
     (* ====================== LOW LEVEL METHODS ====================== *)
     (* --- *)
     (* For the following tools, in the singular ?level always stands for "wait level",
        while in the plural ?levels stands for "broadcast levels". *)
     val lock : ?level:int (* 0 *) -> ?guards:(Guard.ts) -> t -> unit
     (* --- *)
     (* Try to lock but only in the absence of conflict with a thread of the *same* level.
        Note also that level 0 threads (readers) have no conflicts with other level 0 threads: *)
     val try_lock : ?level:int -> ?guards:(Guard.ts) -> t -> bool
     (* --- *)
     (* To be used in critical sections (i.e. when the involved mutex has been locked by the thread): *)
     module Critical : sig
       val require   : ?level:int (* 0 *) -> guards:Guard.ts -> t -> unit (* ≅ if guard then () else (unlock; lock ~guard) *)
       val subscribe : t -> waiting_room -> unit
       val broadcast : ?highland:unit -> ?levels:int list (*[]*) -> t -> unit
       (* --- *)
       (* ?broadcast_levels are of "lowland" because here the "lock" method is really a lock method applied on mutex: *)
       val unlock : ?broadcast_levels:int list (* <= lowland *) -> t -> unit
     end
     (* --- *)
     (* ============== (recommended) HIGH LEVEL METHODS  ============== *)
     (* --- *)
     val id : t -> int  (* just an identifier (progressive) *)
     (* --- *)
     val new_waiting_room : unit -> waiting_room
     val subscribe : t -> waiting_rooms -> unit
     (* --- *)
     (* The argument ~waiting_room, if provided, is used only if ~guard is provided too: *)
     val acquire     : ?level:int -> ?guard:(unit -> bool) -> ?waiting_room:waiting_room -> t -> unit
     val try_acquire : ?level:int -> ?guard:(unit -> bool) -> t -> bool
     (* --- *)
     module Protected : sig
       (* wait and require using the owned mutex but with a different waiting_room: *)
       val wait    :  level:int -> ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> waiting_room -> t -> unit
       val require :  level:int -> ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> guard:(unit -> bool) -> waiting_room -> t -> unit
       (* --- *)
       val wait_choosy :
         release_level:int -> wait_level:int -> ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> waiting_room -> t -> unit
       (* --- *)
       val require_choosy :
         release_level:int -> wait_level:int ->
         ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> guard:(unit -> bool) -> waiting_room -> t -> unit
       (* --- *)
       (* The parameters `notify' ans `subscribe' are related to "highland": *)
       val release : ?level:int -> ?notify:int list (*[]*) -> ?subscribe:waiting_rooms -> t -> unit
     end
     (* --- *)
     (* Multi-level locks are completed by some high-level tools, for a disciplined access.
        For all tools, the broadcast is performed <=> the function succeed (no exceptions).
        Methods `with_lock' and `with_try_lock' execute the function in the "critical section", i.e.
        when the internal mutex is really locked. Conversely `with_acquire' and `with_try_acquire' execute
        the function in the "protected section", i.e. when the ressource is owned, by the thread, with the
        specified level of ownership (reader, writer, etc). The mutex is locked by these methods only to enter
        and to exit from the protected section.
        *)
     (* --- *)
     (* Broadcasts are for the critical "lowland" where threads may be stucked in: *)
     val with_lock        : ?level:int -> ?guards:('a Guard.gs) -> ?broadcast_levels:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     val with_try_lock    : ?level:int -> ?guards:('a Guard.gs) -> ?broadcast_levels:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     (* --- *)
     (* Broadcasts are for the critical "highland" where threads may be stucked in: *)
     val with_acquire     : ?level:int -> ?guard:('a -> bool) -> ?waiting_room:waiting_room -> ?notify:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     val with_try_acquire : ?level:int -> ?guard:('a -> bool) -> ?notify:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     (* --- *)
     val with_acquire_choosy  :
        ?in_level:int (* lowest *)   ->  ?in_guard:('a -> bool) ->  ?in_waiting_room:waiting_room ->
       ?out_level:int (* in_level *) -> ?out_guard:('a -> bool) -> ?out_waiting_room:waiting_room ->
       ?notify:int list ->
       (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     (* --- *)
   end (* module COMPLETE *)


(* ------------------------ *)
(*        EXAMPLES          *)
(* ------------------------ *)

(* Examples of usage (how to re-create the ready-to-use modules described above):

open Lock_club

(* Single level: *)
module Single_level : DISCIPLINED
  = struct
      module  M0 = Guarded (struct let levels = 1 let lowest = 0 end)
      include M0
      include ADD_DISCIPLINE (M0)
    end

module RW_levels : COMPLETE
  = struct
      module  L0 = struct let levels = 2 let lowest = 0 end
      module  M0 = Guarded (L0)
      module  M1 = NEST_PROTOCOL (M0) (Readers_writer (L0))
      include M1
      include COMPLETION (M1)
    end

module RWM_levels : COMPLETE
  = struct
      module  L1 = struct let levels = 3 let lowest = 1 end
      module  L0 = struct let levels = 3 let lowest = 0 end
      module  P1 = Readers_writer (L1)
      module  P0 = Readers_writer (L0)
   (* module  P2 = COMPOSE_PROTOCOL (P1) (P0) *)
      module  P2 = COMPOSE_READERS_WRITERS (P1) (P0) (* more accurated *)
      (* --- *)
      module  M0 = Guarded (L0)
      module  M1 = NEST_PROTOCOL (M0) (P2)
      include COMPLETION (M1)
    end

*)

(* ------------------------ *)
(*  The "collector" channel *)
(* ------------------------ *)
(*
module Log = Ocamlbricks_log

(* Unsatisfactory definition using "lowland" waiting rooms: *)
module Collector = struct

  module Lock = Lock_club.RWM_levels

  type 'a t = Lock.t * ('a list) Res.t

  let make () = (Lock.create (), Res.return [])

  let reader = 0
  let writer = 1
  let maintainer = 2

  let flush (t:'a t) : 'a list =
    Lock.with_acquire
      ~level:(writer)
      ~guard:(fun r -> (Res.get r) <> [])
   (* ~notify:[writer; reader]  (* ATOMATICALLY DONE AT LOWLAND *)   *)
       t (fun res ->
            let () = Log.printf "Collector.flush: WORKING IN PROTECTED SECTION\n" in
            Res.apply_rw res (fun xs -> [], fun _ -> xs)
            )
       |> Either.get_right

  let add (x:'a) (t:'a t) : unit =
    Lock.with_acquire
      ~level:(maintainer)
   (* ~notify:[writer; reader]  (* ATOMATICALLY DONE AT LOWLAND *)   *)
       t (fun res ->
            let () = Log.printf "Collector.add: WORKING IN PROTECTED SECTION\n" in
            Res.apply_rw res (fun xs -> x::xs, fun _ -> ())
            )
       |> Either.get_right

  let taste ?guard (t:'a t) : 'a list =
    Lock.with_acquire
      ~level:(reader)
      ?guard
       t (fun res ->
            let () = Log.printf "Collector.taste: WORKING IN PROTECTED SECTION\n" in
            Res.apply_ro res (fun xs -> xs)
            )
       |> Either.get_right

end (* Collector *)

let c = Collector.make () ;;
(* val c : Collector.Lock.t * '_a list Res.t = (<abstr>, <abstr>) *)

Collector.taste c ;;
(* - : '_a list = [] *)

let g = Future.make (fun () -> Collector.taste ~guard:(fun r -> (Res.get r) <> []) c) () ;;
(* val g : '_a list Future.t = <abstr>
[2591869.1]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2591869.1]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2591869.1]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2591869.1]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
*)

Future.taste g ;;
(* - : string list option = None *)

let f = Future.make (fun () -> Collector.flush c) () ;;
(* val f : '_a list Future.t = <abstr>
[2591869.2]: Lock.Readers_writer: acquire_guards: L1-READER AT L1 ACQUIRED (action n°1)
[2591869.2]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2591869.2]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2591869.2]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
[2591869.2]: Lock.Readers_writer: release_code:   L1-READER AT L1 => RELEASED
[2591869.1]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2591869.1]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2591869.1]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2591869.1]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
*)

(* => the future `g' (i.e. 2591869.1) has been woken up by `f' (i.e. 2591869.2) needlessly because
   `f' is an L0 writer that broadcasts all writers and readers unlocking the mutex.
   This broadcast acts on the "lowland", i.e. on the waiting room directly associated to the mutex.
   So, we change the definition: *)

module Log = Ocamlbricks_log

(* Good definition, using an "highland" waiting room: *)
module Collector = struct

  module Lock = Lock_club.RWM_levels

  (* We attach an "highland" waiting room (snd projection): *)
  type 'a t = (Lock.t * ('a list) Res.t) * Lock_club.waiting_room

  let make () =
    let lock = Lock.create () in
    let wr = Lock_club.make_waiting_room ~levels:3 in
    let () = Lock.subscribe lock wr in
    ((lock, Res.return []), wr)

  let reader = 0
  let writer = 1
  let maintainer = 2

  let flush (t:'a t) : 'a list =
    Lock.with_acquire
      ~level:(writer)
      ~guard:(fun r -> (Res.get r) <> [])
      ~waiting_room:(snd t)
      ~notify:[writer; reader]  (* AT HIGHLAND *)
      (fst t)
      (fun res ->
         let () = Log.printf "Collector.flush: WORKING IN PROTECTED SECTION\n" in
         Res.apply_rw res (fun xs -> [], fun _ -> xs)
         )
       |> Either.get_right

  let add (x:'a) (t:'a t) : unit =
    Lock.with_acquire
      ~level:(maintainer)
      ~notify:[writer; reader]  (* AT HIGHLAND *)
      (fst t)
      (fun res ->
         let () = Log.printf "Collector.add: WORKING IN PROTECTED SECTION\n" in
         Res.apply_rw res (fun xs -> x::xs, fun _ -> ())
         )
       |> Either.get_right

  let taste ?guard (t:'a t) : 'a list =
    Lock.with_acquire
      ~level:(reader)
      ?guard
      ~waiting_room:(snd t) (* used only when ?guard will be provided *)
      (fst t)
      (fun res ->
         let () = Log.printf "Collector.taste: WORKING IN PROTECTED SECTION\n" in
         Res.apply_ro res (fun xs -> xs)
         )
       |> Either.get_right

end (* Collector *)

let c = Collector.make () ;;
(* val c : (Collector.Lock.t * '_a list Res.t) * Lock_club.waiting_room = ((<abstr>, <abstr>), [|<abstr>; <abstr>; <abstr>|]) *)

Collector.taste c ;;
(* - : '_a list = [] *)

let g = Future.make (fun () -> Collector.taste ~guard:(fun r -> (Res.get r) <> []) c) () ;;
(* val g : '_a list Future.t = <abstr>
[2596652.1]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2596652.1]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2596652.1]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2596652.1]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
*)

Future.taste g ;;
(* - : '_a list option = None *)

let f = Future.make (fun () -> Collector.flush c) () ;;
(* val f : '_a list Future.t = <abstr>
[2596652.2]: Lock.Readers_writer: acquire_guards: L1-READER AT L1 ACQUIRED (action n°1)
[2596652.2]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2596652.2]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2596652.2]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
[2596652.2]: Lock.Readers_writer: release_code:   L1-READER AT L1 => RELEASED
*)

(* It's fine: `g' has not been woken up by `f', even if `f' broadcasted all writers and readers
   unlocking the mutex. But `g' was waiting on the "highland" waiting room, not on the "lowland"
   one. So, `f' will broadcast this highland waiting room only when it will really change the
   structure, and this will be possible only when its guard will be true. And currently is not
   the case. *)

Future.taste f ;;
(* - : '_a list option = None *)

let action () = List.iter (fun x -> Thread.create (fun () -> Collector.add x c) () |> ignore) ["ciao"; "hello"; "bye"] ;;
(* val action : unit -> unit = <fun> *)

action () ;;
(* - : unit = ()
[2596652.4]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L1 DECLARED myself as waiting writer (action n°1)
[2596652.4]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2596652.4]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L1 ACQUIRED (action n°2)
[2596652.4]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L0 ACQUIRED (action n°2)
[2596652.4]: Collector.add: WORKING IN PROTECTED SECTION
[2596652.3]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L1 DECLARED myself as waiting writer (action n°1)
[2596652.3]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2596652.5]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L1 DECLARED myself as waiting writer (action n°1)
[2596652.5]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2596652.4]: Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels 1, 0
[2596652.4]: Lock.Readers_writer: release_code:   L2-WRITER AT L0 => RELEASED
[2596652.4]: Lock.Readers_writer: release_code:   L2-WRITER AT L1 => RELEASED
[2596652.3]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L1 ACQUIRED (action n°2)
[2596652.3]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L0 ACQUIRED (action n°2)
[2596652.3]: Collector.add: WORKING IN PROTECTED SECTION
[2596652.3]: Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels 1, 0
[2596652.3]: Lock.Readers_writer: release_code:   L2-WRITER AT L0 => RELEASED
[2596652.3]: Lock.Readers_writer: release_code:   L2-WRITER AT L1 => RELEASED
[2596652.5]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L1 ACQUIRED (action n°2)
[2596652.5]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L0 ACQUIRED (action n°2)
[2596652.5]: Collector.add: WORKING IN PROTECTED SECTION
[2596652.5]: Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels 1, 0
[2596652.5]: Lock.Readers_writer: release_code:   L2-WRITER AT L0 => RELEASED
[2596652.5]: Lock.Readers_writer: release_code:   L2-WRITER AT L1 => RELEASED
[2596652.2]: Lock.Readers_writer: acquire_guards: L1-READER AT L1 ACQUIRED (action n°1)
[2596652.2]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2596652.2]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2596652.2]: Collector.flush: WORKING IN PROTECTED SECTION
[2596652.1]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2596652.2]: Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels 1, 0
[2596652.2]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
[2596652.2]: Lock.Readers_writer: release_code:   L1-READER AT L1 => RELEASED
[2596652.1]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2596652.1]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2596652.1]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
*)

(* Note that `f' (2596652.2), which is a "writer", i.e. an "L1"-thread, can acquire the resource
   only when all prioritary threads ("maintainers", i.e. "L2"-threads) have released the structure. *)

Future.taste f ;;
(* - : string list option = Some ["bye"; "ciao"; "hello"] *)

Future.taste g ;;
(* - : string list option = None *)

Collector.add "quit" c ;;
(* - : unit = ()
[2596652.0]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L1 DECLARED myself as waiting writer (action n°1)
[2596652.0]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2596652.0]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L1 ACQUIRED (action n°2)
[2596652.0]: Lock.Readers_writer: acquire_guards: L2-WRITER AT L0 ACQUIRED (action n°2)
[2596652.0]: Collector.add: WORKING IN PROTECTED SECTION
[2596652.0]: Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels 1, 0
[2596652.0]: Lock.Readers_writer: release_code:   L2-WRITER AT L0 => RELEASED
[2596652.0]: Lock.Readers_writer: release_code:   L2-WRITER AT L1 => RELEASED
[2596652.1]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2596652.1]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2596652.1]: Collector.taste: WORKING IN PROTECTED SECTION
[2596652.1]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2596652.1]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
*)

Future.taste g ;;
(* - : string list option = Some ["quit"] *)

*)

(* ------------------------ *)
(*   Synchronous channels   *)
(* ------------------------ *)
(*

module Log = Ocamlbricks_log

module Synchronous = struct

  module Lock = Lock_club.RW_levels

  (* The channel may be empty or it may contain a message: *)
  type 'a t = (Lock.t * ('a option) Res.t) * Lock_club.waiting_room

  let make () =
    let lock = Lock.create () in
    let wr = Lock_club.make_waiting_room ~levels:2 in
    let () = Lock.subscribe lock wr in
    ((lock, Res.return None), wr)

  let reader = 0
  let writer = 1

  let receive (t:'a t) : 'a =
    Lock.with_acquire
      ~level:(writer)
      ~guard:(fun r -> (Res.get r) <> None)
      ~waiting_room:(snd t)
      ~notify:[writer; reader]
      (* --- *)
      (fst t)
      (fun res ->
         let () = Log.printf "Synchronous.receive: WORKING IN PROTECTED SECTION\n" in
         Res.apply_rw res (fun b -> None, fun _none -> Option.extract ~failwith_msg:"receive" ?fallback:None b)
         )
       |> Either.get_right


  let send_async (t:'a t) (msg:'a) : unit =
    Lock.with_acquire
      ~level:(writer)
      ~guard:(fun r -> (Res.get r) = None)
      ~notify:[writer; reader]
      (* --- *)
      (fst t)
      (fun res ->
         let () = Log.printf "Synchronous.send_async: WORKING IN PROTECTED SECTION\n" in
         Res.apply_rw res (fun _none -> Some msg, fun _ -> ())
         )
       |> Either.get_right

  let send (t:'a t) (msg:'a) : unit =
    Lock.with_acquire_choosy
      ~in_level:(writer)
      ~in_guard:(fun r -> (Res.get r) = None)
      ~in_waiting_room:(snd t)
      (* --- *)
      ~notify:[writer; reader]
      (* --- *)
      ~out_level:(reader)
      ~out_guard:(fun r -> (Res.get r) = None)
      (* --- *)
      (fst t)
      (fun res ->
         let () = Log.printf "Synchronous.send: WORKING IN PROTECTED SECTION\n" in
         Res.apply_rw res (fun _none -> Some msg, fun _ -> ())
         )
       |> Either.get_right

  let taste ?guard (t:'a t) : 'a option =
    Lock.with_acquire
      ~level:(reader)
      ?guard
      ~waiting_room:(snd t) (* used only when ?guard will be provided *)
      (fst t)
      (fun res ->
         let () = Log.printf "Synchronous.taste: WORKING IN PROTECTED SECTION\n" in
         Res.apply_ro res (fun b -> b)
         )
       |> Either.get_right

end (* Synchronous *)

(*
module Synchronous :
  sig
    module Lock = Lock_club.RW_levels
    type 'a t = (Lock.t * 'a option Res.t) * Lock_club.waiting_room
    val make : unit -> (Lock.t * 'a option Res.t) * Lock_club.waiting_room
    val reader : int
    val writer : int
    val receive : 'a t -> 'a
    val send_async : 'a t -> 'a -> unit
    val send : 'a t -> 'a -> unit
    val taste : ?guard:('a option Res.t -> bool) -> 'a t -> 'a option
  end
*)

let ch = Synchronous.make () ;;

(* Not synchronous for now: *)
let f = Future.make (fun () -> Synchronous.send_async ch "Hi, how are you?"; Misc.pr "future f: Success.\n") () ;;
(* ---
val f : unit Future.t = <abstr>
[2817358.4]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2817358.4]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2817358.4]: Synchronous.send_async: WORKING IN PROTECTED SECTION
[2817358.4]: Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels 1, 0
[2817358.4]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
future f: Success.
*)

let msg = Synchronous.taste ch ;;
(* ---
[2817358.0]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2817358.0]: Synchronous.taste: WORKING IN PROTECTED SECTION
[2817358.0]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
val msg : string option = Some "Hi, how are you?"
*)

let msg = Synchronous.receive ch ;;
(* ---
[2817358.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2817358.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2817358.0]: Synchronous.receive: WORKING IN PROTECTED SECTION
[2817358.0]: Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels 1, 0
[2817358.0]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
val msg : string = "Hi, how are you?"
*)

let msg = Synchronous.taste ch ;;
(* ---
[2817358.0]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2817358.0]: Synchronous.taste: WORKING IN PROTECTED SECTION
[2817358.0]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
val msg : string option = None
*)

(* ===> Synchronous now: <=== *)
let f = Future.make (fun () -> Synchronous.send ch "Hi, are you listening right now?"; Misc.pr "future f: Success.\n") () ;;
(* ---
val f : unit Future.t = <abstr>
[2817358.6]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2817358.6]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2817358.6]: Synchronous.send: WORKING IN PROTECTED SECTION
[2817358.6]: Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels 1, 0
[2817358.6]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
*)

let msg = Synchronous.taste ch ;;
(* ---
[2817358.0]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2817358.0]: Synchronous.taste: WORKING IN PROTECTED SECTION
[2817358.0]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
val msg : string option = Some "Hi, are you listening right now?"
*)

let msg = Synchronous.receive ch ;;
(* ---
[2817358.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2817358.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2817358.0]: Synchronous.receive: WORKING IN PROTECTED SECTION
[2817358.0]: Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels 1, 0
[2817358.0]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
val msg : string = "Hi, are you listening right now?"
[2817358.6]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2817358.6]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
future f: Success. (* <=== !!! *)
*)

let msg = Synchronous.taste ch ;;
(* ---
[2817358.0]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2817358.0]: Synchronous.taste: WORKING IN PROTECTED SECTION
[2817358.0]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
val msg : string option = None
*)

(* ------------------------ *)
(*        Countdown         *)
(* ------------------------ *)

module Countdown :
  sig
    module Lock = Lock_club.Single_level
    type t = Lock.t * int ref
    val make : int -> t
    (* --- *)
    val decr      : t -> unit
    val wait_zero : t -> unit
  end
  = struct

  module Lock = Lock_club.Single_level

  type t = Lock.t * (int ref)

  let make n =
    let lock = Lock.create () in
    (lock, ref n)

  let reader = 0
  let writer = 1

  let decr (t:t) : unit =
    Lock.with_lock ~level:(writer) t (fun r ->
         let () = Log.printf "Countdown.decr: WORKING IN CRITICAL SECTION\n" in
         decr r;
         if !r <= 0 then Lock.Critical.broadcast ~levels:[0] (fst t) else ()
         )
       |> Either.get_right

  let wait_zero (t:t) : unit =
    Lock.with_lock ~level:(reader) t
      ~guards:[| (fun r -> if !r <= 0 then Some (fun () -> ()) else None) |]
      (fun r -> Log.printf "Countdown.wait_zero: WORKING IN CRITICAL SECTION\n")
       |> Either.get_right

end (* Countdown *)

let c = Countdown.make 5 ;;
(* val c : Countdown.Lock.t * int ref = (<abstr>, {contents = 5}) *)

let f = Future.make (fun () -> Countdown.wait_zero c) () ;;
(* val f : unit Future.t = <abstr> *)

Future.taste f ;;
(* - : unit option = None *)

Countdown.decr c ;;
(* [117833.0]: Countdown.decr: WORKING IN CRITICAL SECTION *)
Countdown.decr c ;;
(* [117833.0]: Countdown.decr: WORKING IN CRITICAL SECTION *)
Countdown.decr c ;;
(* [117833.0]: Countdown.decr: WORKING IN CRITICAL SECTION *)
Countdown.decr c ;;
(* [117833.0]: Countdown.decr: WORKING IN CRITICAL SECTION *)
Countdown.decr c ;;
(* [117833.0]: Countdown.decr: WORKING IN CRITICAL SECTION *)
(* [117833.1]: Countdown.wait_zero: WORKING IN CRITICAL SECTION *)

Future.taste f ;;
(* - : unit option = Some () *)

let f = Future.make (fun () -> Countdown.wait_zero c) () ;;
(* val f : unit Future.t = <abstr> *)
(* [117833.2]: Countdown.wait_zero: WORKING IN CRITICAL SECTION *)


*)
