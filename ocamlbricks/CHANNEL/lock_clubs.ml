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


(* Protect an application from any kind of exception with an emergency result in standby: *)
(* val standby :  'b -> ('a -> 'b) -> 'a -> 'b *)
let standby  y f x = try f x with _ -> y   (* Misc.standby *)
let ignore_exn f x = try f x with _ -> ()  (* Misc.protect *)
module Log = Ocamlbricks_log
(* --- *)
IFDEF DOCUMENTATION_OR_DEBUGGING THEN
  DEFINE DEBUGGING(x)=x
ELSE
  DEFINE DEBUGGING(x)=()
ENDIF

module Tools = struct

 let array_of_reversed_known_length_list len =
    function
    | []    -> [||]
    | x::xs ->
        let a = Array.make len x in
        (* --- *)
        let rec loop i = function
        | []    -> a
        | x::xs -> (a.(i) <- x); loop (i-1) xs
        in
        loop (len-2) xs

end (* Tools *)

(* ------------------------ *)
(*          BASIC           *)
(*        ADD_GUARDS        *)
(*    (General pattern)     *)
(* ------------------------ *)

(* The word "basic" stands here for "raw but multi-level": *)

module Guard :
  sig
    type t = unit -> action option
     and action = unit -> unit
     and ts = t array
     and actions = action array
    (* --- *)
    (* The action or "continuation" is executed only if the guard is satisfied: *)
    val test_and_run : t -> unit -> bool
    (* --- *)
    val test_all : ts -> bool * actions
    val exec_all : actions -> unit
   (* --- *)
    type 'a g = 'a -> action option
     and 'a gs = ('a g) array
    val thunkify : 'a gs -> 'a -> ts
  end
= struct

 type t = (unit -> action option)
  and action = (unit -> unit)
  and ts = t array
  and actions = action array

 type 'a g = 'a -> action option
  and 'a gs = ('a g) array

 let thunkify gs x : ts =
   Array.map (fun g -> fun () -> g x) gs

 (* val test_and_run : t -> unit -> bool *)
 let test_and_run f () : bool =
   try
     (match f () with
     | None -> false
     | Some action -> (action ()); true
     )
   with _ -> false

 let test_all ts : bool * actions =
   let n = Array.length ts in
   (* --- *)
   let rec loop acc i =
     if i>=n then (true, Tools.array_of_reversed_known_length_list n acc) else
     match ts.(i) () with
     | None -> (false, [||])
     | Some action -> loop (action::acc) (i+1)
   (* --- *)
   in loop [] 0

 let exec_all : actions -> unit =
   Array.iter (fun a -> a ())

end (* Guard *)

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
module ADD_GUARDS (Basic: BASIC_METHODS) : GUARDED_METHODS with type t = Basic.t
= struct

  (* Inherit all but lock, try_lock and unlock: *)
  (* include Basic => Multiple definition of the module name Critical *)
  type t = Basic.t

  (* To be used in critical sections (i.e. when the mutex has been locked by the thread): *)
  module GUARDED_Critical = struct (* inherit *) include Basic.BASIC_Critical
    (* --- *)
    (* val require : ?level:int -> guards:((unit -> action option) array) -> t -> unit *)
    let require ?level ~guards t =
      let n = Array.length guards in
      for i = 0 to (n-1) do
        while not (Guard.test_and_run guards.(i) ()) do
          (*Basic.BASIC_Critical.*)wait ?level t
        done
      done

  end (* GUARDED_Critical *)

  (* The guard is evaluated once the mutex is locked. If the guard is false, we wait until something happen
     to relock and revaluate the guard. We return from this procedure only when the mutex is locked and
     the guard is true: *)
  let lock ?level ?guards : t -> unit =
    match guards with
    | None       -> (Basic.lock)
    | Some guards -> (fun t -> Basic.lock t; (*self.*)GUARDED_Critical.require ?level ~guards t)

  (* ?level is ignored but it is added to fit the signature GUARDED_METHODS, even if it will be useful only with protocolary modules. *)
  let try_lock ?level ?guards =
    match guards with
    | None -> (Basic.try_lock)
    (* --- *)
    | Some guards ->
        (fun t ->
            if not (Basic.try_lock t) then false else (* continue with the mutex locked: *)
            let (all_ok, actions) = Guard.test_all guards in
            if (all_ok)
              then
                (* Fine, the mutex is locked and the guard is true. We have just to perform the guard related actions.
                   Success: *)
                let () = Guard.exec_all (actions) in
                true
              else begin
                (* The guard is false, so unlock the mutex and fail. *)
                Basic.BASIC_Critical.unlock t;
                false
                end)

end (* ADD_GUARDS *)

(* ------------------------ *)
(*      LEVELS & core       *)
(* ------------------------ *)

type level = int (* >= 0 *)

module type LEVELS = sig
  val levels:int
  (* The "lowest" level is used as default for the optional
     parameter ?level for all tools defined below: *)
  val lowest : level
end

(* A condition variable per level: *)
type core = { m: Mutex.t; wr: waiting_room; wrt: subscribers; }
 (* Set of condition variables on which the thread will `wait': *)
 and waiting_room = (Condition.t array)
 (* A weak hashset based on physical equality: *)
 and subscribers  = (waiting_room Hashset.t) Lazy.t

(* --- *)
type waiting_rooms = waiting_room list


(* ------------------------ *)
(*            RAW           *)
(* ------------------------ *)

module type RAW =
   sig
     type t
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
       val wait      : ?level:int (*0*) -> t -> unit
       val subscribe : t -> waiting_room -> unit
       val broadcast : ?highland:unit -> ?levels:int list (*[]*) -> t -> unit
       val unlock    : ?broadcast_levels:int list (* <= lowland *) -> t -> unit
     end
     (* --- *)
   end (* RAW *)

(* RAW implementation: *)
(* module Raw : functor (Levels: LEVELS) -> RAW *)
module Raw (Levels: LEVELS) : RAW with type t = core
= struct

  let () = if not (Levels.levels >= 1 && Levels.lowest >= 0 && Levels.lowest < Levels.levels) then
    invalid_arg (Printf.sprintf "Lock: bad levels' specifications")

  include Levels

  (* A mutex and a condition variable per level: *)
  type t = core

  let mutex t = t.m
  let waiting_room t = t.wr

  (* Defined as named function to exploit the `Lazy.from_fun' related optimization
     ("slightly more efficient" announced in the Lazy module manual): *)
  let create_subscribers_table () =
    Hashset.make ~weak:() (* ephemerons *) ~equality:(==) ~size:0 ()

  (* The table of subscribers is really created when the first subscriber signs in: *)
  let create () : t =
    let waiting_room = (Array.init levels (fun _ -> Condition.create ())) in
    let subscribers  = Lazy.from_fun (create_subscribers_table) in
    { m = Mutex.create ();  wr = waiting_room;  wrt = subscribers; }

  let lock     t = Mutex.lock t.m
  let try_lock t = Mutex.try_lock t.m

  (* To be used in critical sections (i.e. when the mutex has been locked by the current thread): *)
  module RAW_Critical = struct

    (* Critical method. Elementary but fundamental tool wrapping
       Condition.wait to implement passive waiting at the good level: *)
    let wait ?(level=lowest) t =
      Condition.wait t.wr.(level) t.m

    (* Critical method. Subscription is definitive (but will be released
       automatically when the waiting room will be collected by the GC).
       val subscribe : t -> waiting_room -> unit *)
    let subscribe t (waiting_room) =
      let wrt = (Lazy.force t.wrt) in
      Hashset.add (wrt) (waiting_room)

    (* Accessory. Broadcast a single waiting room. Silently accepts incorrect leveles: *)
    let broadcast_waiting_room (levels: int list) (wr: waiting_room) =
      List.iter (fun level -> ignore_exn Condition.broadcast wr.(level)) (levels)

    (* Critical method.
       val broadcast : ?highland:unit -> ?levels:int list (*[]*) -> t -> unit
       ---
       Broadcast all condition variables specified by ?levels.
       For subscribers (highland), broadcasts are performed from the smaller
       structures to the bigger ones, because:
         smaller => older   (=> high-priority structure)
         bigger  => younger (=> low-priority  structure)
         *)
    let broadcast ?highland ?(levels=[]) t =
      if levels = [] then () (* nothing to do *) else (* continue: *)
      match highland with
      (* --- *)
      | None ->    (* Broadcast my own waiting room (lowland): *)
          broadcast_waiting_room (levels) (t.wr)
      (* --- *)
      | Some () -> (* Broadcast now all subscribers (highland), if any: *)
          let () = DEBUGGING(Log.printf1 ~v:2 "Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels %s\n"
            (String.concat ", " (List.map string_of_int levels)))
          in
          (* Note here that Hashset.to_list returns elements in their original order of insertion ("stability").
             This implies that an implicit priority is given to smaller (because older) subscribers: *)
          let waiting_rooms = Hashset.to_list ?unstable:None (Lazy.force t.wrt) in
          (* For all subscribers, broadcast all required levels: *)
          List.iter (broadcast_waiting_room levels) (waiting_rooms)

    (* --- *)
    (* Redefine unlock in order to add the broadcast related option.
       val unlock : ?broadcast_levels:int list -> t -> unit *)
    let unlock ?broadcast_levels t =
      let () = match broadcast_levels with
      | None -> ()
      | Some levels -> (*self.*)broadcast ?highland:None ~levels t
      in
      Mutex.unlock t.m

   end (* Critical *)

end (* Raw functor *)

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
       (* ?broadcast_levels are of "lowland" because here the "lock" method is really a lock on mutex: *)
       val unlock    : ?broadcast_levels:int list (* <= lowland *) -> t -> unit
     end
     (* --- *)
   end (* GUARDED *)

(* Raw -> Guarded *)
module GUARDED_of_RAW (Raw: RAW) : GUARDED with type t = Raw.t
= struct

  (* Inherit all but lock, try_lock and unlock: *)
  let create   = Raw.create
  let levels   = Raw.levels
  let lowest   = Raw.lowest
  (* --- *)
  let mutex        = Raw.mutex
  let waiting_room = Raw.waiting_room

  module BASIC_methods = struct
     type t = Raw.t
     let lock     = Raw.lock
     let try_lock = Raw.try_lock
     (* --- *)
     module BASIC_Critical = struct
       let wait = Raw.RAW_Critical.wait
       let unlock t = Raw.RAW_Critical.unlock (* ?broadcast_levels *) t
     end
  end (* BASIC_METHODS *)

 (* BASIC_METHODS -> GUARDED_METHODS *)
  include ADD_GUARDS (BASIC_methods)

  (* To be used in critical sections (i.e. when the mutex has been locked by the thread): *)
  module Critical = struct
    (* inherit *) include Raw.RAW_Critical
    (* inherit *) include GUARDED_Critical
  end (* Critical *)

  (* --- *)
  (* val compare : t -> t -> int (* compare mutexes *) *)
  let compare t1 t2 = compare (Raw.mutex t1) (Raw.mutex t2)

end (* GUARDED_of_RAW *)


(* GUARDED implementation: *)
(* module Guarded : functor (Levels: LEVELS) -> GUARDED *)
module Guarded (Levels: LEVELS) : GUARDED with type t = core
= struct
  (* --- *)
  include GUARDED_of_RAW(Raw(Levels))
  (* --- *)
end (* Guarded *)

(* ------------------------ *)
(*       DISCIPLINED        *)
(* ------------------------ *)

module type DISCIPLINED_METHODS =
   sig
     type t
     (* --- *)
     val with_lock     : ?level:int -> ?guards:('a Guard.gs) -> ?broadcast_levels:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     val with_try_lock : ?level:int -> ?guards:('a Guard.gs) -> ?broadcast_levels:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
   end

module type DISCIPLINED =
   sig
     include GUARDED
     include DISCIPLINED_METHODS with type t := t
   end

(* module ADD_DISCIPLINE : functor (Guarded: GUARDED) -> DISCIPLINED *)
module ADD_DISCIPLINE (Guarded: GUARDED) : DISCIPLINED_METHODS with type t := Guarded.t (* t not exported to avoid duplicated definitions *)
= struct

  (*include Guarded*)
  type t = Guarded.t

  (* val with_lock : ?level:int -> ?guards:('a Guard.gs) -> ?broadcast_levels:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t *)
  (* The broadcast is performed <=> the function succeed: *)
  let with_lock ?level ?guards ?broadcast_levels ((t:t),x) f =
    let guards = Option.map (fun gs -> Guard.thunkify gs x) guards in
    let () = Guarded.lock ?level ?guards t in
    (* --- *)
    let ey = Either.protect f x in
    (* --- *)
    let _broadcast : unit =
      if Either.is_right ey then
        ignore_exn (Guarded.Critical.broadcast ?highland:None ?levels:(broadcast_levels)) t
    in
    (* --- *)
    let () = Guarded.Critical.unlock t in
    ey

  (* val with_try_lock : ?level:int -> ?guards:('a Guard.gs) -> ?broadcast_levels:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t *)
  (* The broadcast is performed <=> the function succeed: *)
  let with_try_lock ?level ?guards ?broadcast_levels (t,x) f =
    let guards = Option.map (fun gs -> Guard.thunkify gs x) guards in
    let success = Guarded.try_lock ?level ?guards t in
    if not success then Either.Left (Failure "try_lock") else (* continue: *)
    (* --- *)
    let ey = Either.protect f x in
    (* --- *)
    let _broadcast : unit =
      if Either.is_right ey then
      ignore_exn (Guarded.Critical.broadcast ?highland:None ?levels:(broadcast_levels)) t
    in
    (* --- *)
    let () = Guarded.Critical.unlock t in
    ey


end (* ADD_DISCIPLINE *)

(* module DISCIPLINED_of_RAW : functor (Raw: RAW) -> DISCIPLINED with type t = Raw.t *)
module DISCIPLINED_of_RAW (Raw: RAW) : DISCIPLINED with type t = Raw.t
= struct
  module M0 = GUARDED_of_RAW (Raw)
  include M0
  include ADD_DISCIPLINE (M0)
end

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
     val release_code : brdcast_method -> ?level:int -> data -> unit
   end (* PROTOCOL *)

type ('a,'b) data_couple = { p1: 'a; p0: 'b }

module COMPOSE_PROTOCOL (P1: PROTOCOL) (P0: PROTOCOL) : PROTOCOL with type data = (P1.data, P0.data) data_couple = struct
  type data = (P1.data, P0.data) data_couple
  let create () = { p1 = P1.create (); p0 = P0.create () }
  (* --- *)

  let release_code  (brdcast_method) ?level data = begin
    P0.release_code (brdcast_method) ?level data.p0;
    P1.release_code (brdcast_method) ?level data.p1; (* P1 last *)
    end

  let levels =
    let () = assert (P1.levels = P0.levels) in
    P1.levels

  let lowest  = min P0.lowest  P1.lowest
  let highest = max P0.highest P1.highest

  let index_of    (level) = max (lowest) (min highest level) - lowest

  (* length = number of levels *)
  let acquire_guards_per_class =
    Array.init (levels) (fun i ->
      let level = lowest + i in
      let i1 = P1.index_of (level) in
      let i0 = P0.index_of (level) in
      let p1gs = Array.map (fun g (level, data) -> g (level, data.p1)) P1.acquire_guards_per_class.(i1) in
      let p0gs = Array.map (fun g (level, data) -> g (level, data.p0)) P0.acquire_guards_per_class.(i0) in
      Array.append (p1gs) (p0gs))

  (* Ottimizzare: *)
  let acquire_guards ?(level=lowest) data =
    let i = index_of (level) in
    Array.map (fun g -> fun () -> g (level, data)) acquire_guards_per_class.(i)

  (* Equivalent (more intuitive) definition: *)
  (* let acquire_guards ?level data =
       let gs1 = P1.acquire_guards ?level data.p1 in
       let gs2 = P0.acquire_guards ?level data.p0 in
       Array.append gs1 gs2                           (* P1 first *) *)

end (**)

(* ------------------------ *)
(*      READERS-WRITERS     *)
(* ------------------------ *)

(* A PROTOCOL implementation: *)
module Readers_writer (Levels: LEVELS) : PROTOCOL = struct

  type data = {
    mutable active_readers   : int;
    mutable no_active_writer : bool;
    mutable waiting_writers  : int;
    }

  let create () =
    { active_readers=0; no_active_writer=true; waiting_writers=0; }

  (* Check condition on levels: *)
  let () = if not (Levels.levels >= 2) then
    invalid_arg (Printf.sprintf "Lock.Readers_writer: required at least 2 levels")

  (* --- *)
  let levels  = Levels.levels
  let lowest  = Levels.lowest
  let highest = lowest + 1
  let index_of (level) = max (lowest) (min highest level) - lowest
  (* --- *)
  let writer_level = highest (* lowest + 1 *)
  let reader_level = lowest
  (* --- *)

  (* Reader (at this level), BEFORE an access *)
  let acquire_guards_READER : (level * data) Guard.gs =
    let action1 (level, data) =
      (* In critical section: *)
      if (data.no_active_writer && data.waiting_writers = 0) then Some (fun () ->
        let () = DEBUGGING(Log.printf2 ~v:2 "Lock.Readers_writer: acquire_guards: L%d-READER AT L%d ACQUIRED (action n°1)\n" level Levels.lowest) in
        (data.active_readers <- data.active_readers + 1)
        )
      else None
    in
    [| action1 |]


  (* Writer (at this level), BEFORE an access *)
  let acquire_guards_WRITER : (level * data) Guard.gs =
    let action1 (level, data) = Some (fun () -> (* Some => true, i.e. do it anyway *)
      let () = DEBUGGING(Log.printf2 ~v:2 "Lock.Readers_writer: acquire_guards: L%d-WRITER AT L%d DECLARED myself as waiting writer (action n°1)\n" level Levels.lowest) in
      data.waiting_writers <- data.waiting_writers + 1
      )
    in
    (* --- *)
    let action2 (level, data) =
      if (data.no_active_writer && data.active_readers = 0) then Some (fun () ->
        let () = DEBUGGING(Log.printf2 ~v:2 "Lock.Readers_writer: acquire_guards: L%d-WRITER AT L%d ACQUIRED (action n°2)\n" level Levels.lowest) in
        (data.waiting_writers  <- data.waiting_writers - 1);
        (data.no_active_writer <- false)
        )
      else None
    in
    (* VERIFICARE CHE LA require SIA FATTA ALLO STESSO LIVELLO level (che è pure opzionale!!!!) *)
    [| action1; action2 |]

  (* val acquire_guards_per_class : ((level * data) Guard.gs) array (* length = number of classes (distinct really managed levels) *) *)
  let acquire_guards_per_class =
    [| acquire_guards_READER; acquire_guards_WRITER |]

  (* Ottimizzare: *)
  let acquire_guards ?(level=lowest) data =
    let i = index_of (level) in
    Array.map (fun g -> fun () -> g (level, data)) acquire_guards_per_class.(i)

  (* val release_code : brdcast_method -> ?level:int -> data -> unit *)
  let release_code (lowland_broadcast) ?(level=reader_level) (data) : unit =
    match level with
    (* --- *)
    | _ when level >= writer_level -> (* writer, AFTER an access *)
       begin (* of critical section: *)
         (data.no_active_writer <- true);
         (**) lowland_broadcast (**) ?levels:(Some [writer_level; reader_level]) (); (* "lowland" *)
         DEBUGGING(Log.printf2 ~v:2 "Lock.Readers_writer: release_code:   L%d-WRITER AT L%d => RELEASED\n" level Levels.lowest);
       end
    (* --- *)
    | _ when level <= reader_level -> (* reader, AFTER an access *)
       begin (* of critical section: *)
         (data.active_readers <- data.active_readers - 1);
         (if (data.waiting_writers > 0) && (data.active_readers = 0) then (**) lowland_broadcast (**) ?levels:(Some [writer_level]) ());
         DEBUGGING(Log.printf2 ~v:2 "Lock.Readers_writer: release_code:   L%d-READER AT L%d => RELEASED\n" level Levels.lowest);
       end
    (* --- *)
    | _ -> assert false


end (* Readers_writer functor *)

(* Special composition for READERS_WRITERS.
   ---
   Levels equals or greater than the highest level (i.e. at least the writer level of P1,
   which is already a "maintainer") must be composed in a special way. Actually, when a
   maintainer would acquire the resource, it must subscribe itself (actions n°1) as
   "waiting writer" at every level. Hence, unconditioned actions n°1 must be grouped and
   executed before other guards.
   *)
module COMPOSE_READERS_WRITERS (P1: PROTOCOL) (P0: PROTOCOL) : PROTOCOL = struct

  include COMPOSE_PROTOCOL (P1) (P0)

  (* split_in_the_middle 4 [| 1;2;3;4 |] ;;
     - : int array * int array = ([|1; 2|], [|3; 4|]) *)
  let split_in_the_middle n xs =
    let half = (n/2) in
    let left_part  = Array.sub xs 0 half in
    let right_part = Array.sub xs half (half) in
    (left_part, right_part)

  (* length = number of levels *)
  let acquire_guards_per_class =
    Array.init (levels) (fun i ->
      let level = lowest + i in
      let i1 = P1.index_of (level) in
      let i0 = P0.index_of (level) in
      let gs1 = Array.map (fun g (level, data) -> g (level, data.p1)) P1.acquire_guards_per_class.(i1) in
      let gs0 = Array.map (fun g (level, data) -> g (level, data.p0)) P0.acquire_guards_per_class.(i0) in
      (* --- *)
      let () = DEBUGGING(Log.printf ~v:2 "Lock.Readers_writer: about to compose readers-writers guards\n") in
      match (level >= P1.highest) (* at least a "maintainer" *) with
      (* --- *)
      | true ->
          let n1 = Array.length gs1 in
          let n0 = Array.length gs0 in
          (* Both n1 and n2 are even: *)
          let () = assert ((n1 mod 2 = 0) && (n0 mod 2 = 0)) in
          let gs1L, gs1R = split_in_the_middle (n1) (gs1) in
          let gs0L, gs0R = split_in_the_middle (n0) (gs0) in
          Array.concat [gs1L; gs0L; (* <= actions n°1 grouped *) gs1R; gs0R (* <= actions n°2 grouped *)]
      (* --- *)
      (* As a normal composition (reader_level for both): *)
      | false -> Array.append gs1 gs0    (* P1 first *)
      )

  (* Ottimizzare: *)
  let acquire_guards ?(level=lowest) data =
    let i = index_of (level) in
    Array.map (fun g -> fun () -> g (level, data)) acquire_guards_per_class.(i)

end (* COMPOSE_READERS_WRITERS *)

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
       val wait    :  level:int -> ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> waiting_room -> t -> unit
       val require :  level:int -> ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> guard:(unit -> bool) -> waiting_room -> t -> unit
       (* --- *)
       val wait_choosy :
         release_level:int -> wait_level:int -> ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> waiting_room -> t -> unit
       (* --- *)
       val require_choosy :
         release_level:int -> wait_level:int -> ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> guard:(unit -> bool) -> waiting_room -> t -> unit
       (* --- *)
       val release : ?level:int -> ?notify:int list (*[]*) -> ?subscribe:waiting_rooms -> t -> unit
     end
     (* --- *)
   end (* PROTOCOLARY *)

(* PROTOCOLARY maker: *)
module NEST_PROTOCOL (Core: GUARDED) (Protocol: PROTOCOL) : PROTOCOLARY = struct

  (* Attach the protocol data to the lock: *)
  type t = { core:Core.t; data:Protocol.data; id:int }

  let thread_safe_fresh_id : unit -> int =
    fun () -> Oo.id (object end)

  let create () : t =
    let core = Core.create () in
    let data = Protocol.create () in
    let id = thread_safe_fresh_id () in (* progressive identifier *)
    {core; data; id}

  let levels = Core.levels
  let lowest = Core.lowest
  let id t = t.id
  (* --- *)
  let mutex        t = Core.mutex (t.core)
  let waiting_room t = Core.waiting_room (t.core)
  (* --- *)
  (* val compare : t -> t -> int *)
  (* Compare identifiers => compare the age, i.e. the date of creation: *)
  let compare t1 t2 = compare (t1.id) (t2.id)
  (* --- *)

  (* type brdcast_method = ?levels:int list -> unit -> unit
     Note: "lowland" broadcasts for protocols that enrich the core: *)
  let brdcast_method (core) =
    fun ?levels () -> Core.Critical.broadcast ?highland:None ?levels (core)

  (* val lock : ?level:int -> ?guards:Guard.ts -> t -> unit *)
  let lock ?level ?guards t =
    let nested_guards = Protocol.acquire_guards ?level (t.data) in
    let guards = match guards with None -> nested_guards | Some guards -> Array.append (nested_guards) (guards) in
    (* --- *)
    Core.lock ?level ~guards (t.core)

  (* val try_lock  : ?level:int -> ?guard:Guard.ts -> t -> bool *)
  let try_lock ?level ?guards t =
    let nested_guards = Protocol.acquire_guards ?level (t.data) in
    let guards = match guards with None -> nested_guards | Some guards -> Array.append (nested_guards) (guards) in
    (* --- *)
    Core.try_lock ?level ~guards (t.core)

  let unlock ?broadcast_levels t =
    let () = Core.Critical.unlock ?broadcast_levels (t.core) in
    ()

  (* acquire = core.lock; protocol.acquire_code; core.unlock
     When protocols are nested, intermediary acquire methods are simply ignored: *)
  let acquire_no_guard ?level t =
    let () = (*self.*)lock ?level ?guards:None t in  (* no more guards than protocolary *)
    let () = Core.Critical.unlock (t.core) in        (* self.unlock ?broadcast_levels:None *)
    let () = DEBUGGING(Log.printf2 "Lock: ACQUIRED CLUB #%d at level %d\n" t.id (Option.extract_or level 0)) in
    ()

  let try_acquire_no_guard ?level t =
    let success = (*self.*)try_lock ?level ?guards:None t in  (* no more guards than protocolary *)
    let () = if success then Core.Critical.unlock (t.core)  in  (* self.unlock ?broadcast_levels:None *)
    success

  (* val new_waiting_room : unit -> waiting_room *)
  let new_waiting_room () =
    (Array.init levels (fun _ -> Condition.create ()))

  (* val subscribe : t -> waiting_room -> unit *)
  let subscribe t (wrs: waiting_rooms) : unit = begin
    Core.lock ?guards:None (t.core);
    List.iter (Core.Critical.subscribe t.core) (wrs);
    Core.Critical.unlock (t.core);
    end

  module Protected = struct

    (* val release : ?level:int -> ?notify:int list (*[]*) -> t -> unit *)
    (* release  =  core.lock;  core.broadcast ~highland;  protocol.release_code;  core.unlock *)
    let release ?level ?notify ?subscribe t =
      (* --- *)
      let () = Core.lock ?guards:None (t.core) in (* not self.lock! *)
      (* --- *)
      (* Broadcast "highland" if asked: *)
      let () = match notify with None -> () | Some levels -> Core.Critical.broadcast ~highland:() ~levels (t.core) in
      (* --- *)
      (* Subscribe one or several "highland" related waiting rooms if asked: *)
      let () = Option.iter (List.iter (Core.Critical.subscribe t.core)) (subscribe)  in
      (* --- *)
      (* self.unlock may cause "lowland" broadcasts: *)
      let () = Protocol.release_code (brdcast_method t.core) ?level (t.data) in
      let () = Core.Critical.unlock ?broadcast_levels:None (t.core) in (* no lowland broadcast  *)
      let () = DEBUGGING(Log.printf2 "Lock: RELEASED CLUB #%d at level %d\n" t.id (Option.extract_or level 0)) in
      ()

    (* ---
       wait and require using the owned mutex but with a different waiting_room:
       ---
       val wait    :  level:int -> ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> waiting_room -> t -> unit
       val require :  level:int -> ?notify:int list (*[]*) -> ?critical_hook:(Mutex.t -> unit) -> guard:(unit -> bool) -> waiting_room -> t -> unit
       *)
    let wait ~level ?notify ?critical_hook (wr: waiting_room) t =
      (* --- *)
      let () = Core.lock ~level ?guards:None (t.core) in (* not self.lock! *)
      (* --- *)
      (* Broadcast "highland" if asked: *)
      let () = match notify with None -> () | Some levels -> Core.Critical.broadcast ~highland:() ~levels (t.core) in
      (* --- *)
      let () = Protocol.release_code (brdcast_method t.core) ~level (t.data) in
      (* --- *)
      let mutex = Core.mutex t.core in
      (* --- *)
      let () = match critical_hook with None -> () | Some code -> code (mutex) in
      (* --- *)
      let () = DEBUGGING(Log.printf2 "Lock: RELEASED CLUB #%d at level %d (WAITING FOR AN EVENT)\n" t.id level) in
      let () = Condition.wait wr.(level) (mutex) in
      let () = DEBUGGING(Log.printf2 "Lock: WOKEN UP by an event about CLUB #%d at level %d\n" t.id level) in
      (* --- *)
      let nested_guards = Protocol.acquire_guards ~level (t.data) in
      let () = Core.Critical.require ~level ~guards:(nested_guards) (t.core) in
      let () = Core.Critical.unlock (t.core) in
      ()

    (* The usual pattern with a notable difference: parameters ?notify and ?critical_hook,
       if any, are used only once, for waiting the first time: *)
    let require ~level ?notify ?critical_hook ~guard (waiting_room) t =
      (* --- *)
      if (standby false guard ()) then () (* fine, return immediately *) else (* continue: *)
      (* --- *)
      let () = (*self.*)wait ~level ?notify ?critical_hook (waiting_room) t in
      (* --- *)
      while not (standby false guard ()) do
        (*self.*)wait ~level (waiting_room) t
      done

    let wait_choosy ~release_level ~wait_level ?notify ?critical_hook (wr: waiting_room) t =
      (* --- *)
      let level = (release_level) in (* for the next steps, before waiting: *)
      (* --- *)
      let () = Core.lock ~level ?guards:None (t.core) in (* not self.lock! *)
      (* --- *)
      (* Broadcast "highland" if asked: *)
      let () = match notify with None -> () | Some levels -> Core.Critical.broadcast ~highland:() ~levels (t.core) in
      (* --- *)
      let () = Protocol.release_code (brdcast_method t.core) ~level (t.data) in
      (* --- *)
      let mutex = Core.mutex t.core in
      (* --- *)
      let () = match critical_hook with None -> () | Some code -> code (mutex) in
      (* --- *)
      let level = wait_level in (* for the rest of procedure: *)
      (* --- *)
      let () = Condition.wait wr.(level) (mutex) in
      (* --- *)
      let nested_guards = Protocol.acquire_guards ~level (t.data) in
      let () = Core.Critical.require ~level ~guards:(nested_guards) (t.core) in
      let () = Core.Critical.unlock (t.core) in
      ()

    (* The usual pattern with two notable differences:
       (1) parameters ?notify and ?critical_hook, if any, are used only once, for waiting the first time
       (2) the release_level is used the first time, after we continue with wait_level *)
    let require_choosy ~release_level ~wait_level ?notify ?critical_hook ~guard (waiting_room) t =
      if (standby false guard ()) then () (* fine, return immediately *)
      else (* continue: *)
      let () = (*self.*)wait_choosy ~release_level ~wait_level ?notify ?critical_hook (waiting_room) t in
      (* --- *)
      while not (standby false guard ()) do
        (*self.*)wait ~level:(wait_level) (waiting_room) t
      done


  end (* Protected *)

  module Critical = struct
    let require ?level ~guards t = Core.Critical.require ?level ~guards (t.core)
    let broadcast ?highland ?levels t = Core.Critical.broadcast ?highland ?levels (t.core)
    let subscribe t = Core.Critical.subscribe (t.core)
    (* New protocolary `unlock' defined above: *)
    let unlock = unlock
  end

  (* ------------------------ *)
  (*     Guarded methods      *)
  (* ------------------------ *)

  (* The argument waiting_room if used only to wait for the guard, not for locking: *)
  let acquire ?(level=Core.lowest) ?guard ?waiting_room : t -> unit =
    match guard with
    | None       -> (acquire_no_guard ~level)
    | Some guard ->
        (fun t ->
           (* Important point: if a guard is given without a specific waiting room,
              the "lowland" waiting room associated to the mutex will be used for waiting: *)
           let waiting_room = match waiting_room with Some wr -> wr | None -> Core.waiting_room (t.core) in
           acquire_no_guard ~level t;
          (*self.*)Protected.require ~level ?notify:None ?critical_hook:None ~guard (waiting_room) t)

  let try_acquire ?level ?guard =
    match guard with
    | None -> (try_acquire_no_guard ?level)
    (* --- *)
    | Some guard ->
        (fun t ->
            if not (try_acquire_no_guard ?level t) then false else (* continue with the mutex locked: *)
            if (standby false guard ())
              then
                (* Fine, the mutex is locked and the guard is true. Success: *)
                true
              else begin
                (* The guard is false, so unlock the mutex and fail: *)
                Core.Critical.unlock (t.core); (* self.unlock t *)
                false
                end)


end (* NEST_PROTOCOL *)


(* ------------------------ *)
(*        COMPLETION        *)
(* ------------------------ *)

module type COMPLETE =
   sig
     include PROTOCOLARY
     (* include DISCIPLINED_METHODS with type t := t *)
     (* --- *)
     val with_lock        : ?level:int -> ?guards:('a Guard.gs) -> ?broadcast_levels:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     val with_try_lock    : ?level:int -> ?guards:('a Guard.gs) -> ?broadcast_levels:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     (* --- *)
     val with_acquire     : ?level:int -> ?guard:('a -> bool) -> ?waiting_room:waiting_room -> ?notify:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     val with_try_acquire : ?level:int -> ?guard:('a -> bool) -> ?notify:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     (* --- *)
     val with_acquire_choosy  :
        ?in_level:int (* lowest *)   ->  ?in_guard:('a -> bool) ->  ?in_waiting_room:waiting_room ->
       ?out_level:int (* in_level *) -> ?out_guard:('a -> bool) -> ?out_waiting_room:waiting_room ->
       ?notify:int list ->
       (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t
     (* --- *)
   end (* COMPLETE *)


module COMPLETION (Protocolary: PROTOCOLARY) : COMPLETE with type t = Protocolary.t
= struct

  include Protocolary
  include ADD_DISCIPLINE (Protocolary)

  (* val with_acquire : ?level:int -> ?guard:('a -> bool) -> ?notify:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t *)
  (* The broadcast is performed <=> the function succeed: *)
  let with_acquire ?level ?guard ?waiting_room ?notify (t,x) f =
    let guard = Option.map (fun g -> fun () -> g x) guard in
    let () = Protocolary.acquire ?level ?guard ?waiting_room t in
    (* --- *)
    let ey = Either.protect f x in
    (* --- *)
    let notify =
      if Either.is_right ey then notify else None
    in
    (* --- *)
    (* Broadcasts, if any, are performed now, once entered the critical section: *)
    let () = Protocolary.Protected.release ?level ?notify t in
    ey

  let with_acquire_choosy ?(in_level=Protocolary.lowest) ?in_guard ?in_waiting_room ?(out_level=in_level) ?out_guard ?out_waiting_room ?notify (t,x) f =
    let in_guard = Option.map (fun g -> fun () -> g x) in_guard in
    let in_waiting_room = match in_waiting_room with Some wr -> wr | None -> Protocolary.waiting_room t in
    (* --- *)
    let () = Protocolary.acquire ~level:(in_level) ?guard:(in_guard) ~waiting_room:(in_waiting_room) t in
    (* --- *)
    let ey = Either.protect f x in
    (* --- *)
    let notify =
      if Either.is_right ey then notify else None
    in
    match out_guard with
    (* --- *)
    | None ->
        (* Broadcasts, if any, are performed now, once entered the critical section: *)
        let () = Protocolary.Protected.release ~level:(in_level) ?notify t in
        ey
    (* --- *)
    | Some g ->
        let out_guard () = g x in
        let out_waiting_room = match out_waiting_room with Some wr -> wr | None -> in_waiting_room in
        (* --- *)
        (* Broadcasts, if any, are performed now: *)
        let () = Protocolary.Protected.require_choosy
          ~release_level:(in_level)
          ~wait_level:(out_level)
          ?notify
          ~guard:(out_guard)
          (out_waiting_room)
          t
        in
        (* --- *)
        let () = Protocolary.Protected.release ~level:(out_level) ?notify:None t in
        ey


  (* val with_try_acquire : ?level:int -> ?guard:('a -> bool) -> ?notify:int list -> (t * 'a) -> ('a -> 'b) -> (exn, 'b) Either.t *)
  (* The broadcast is performed <=> the function succeed: *)
  let with_try_acquire ?level ?guard ?notify (t,x) f =
    let guard = Option.map (fun g -> fun () -> g x) guard in
    let success = Protocolary.try_acquire ?level ?guard t in
    if not success then Either.Left (Failure "try_acquire") else (* continue: *)
    (* --- *)
    let ey = Either.protect f x in
    (* --- *)
    let notify =
      if Either.is_right ey then notify else None
    in
    (* --- *)
    (* Broadcasts, if any, are performed now, once entered the critical section: *)
    let () = Protocolary.Protected.release ?level ?notify t in
    ey

end (* COMPLETION *)


(* ------------------------ *)
(*       READY-TO-USE       *)
(* ------------------------ *)

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


(* ------------------------ *)
(*    COMPLETE commented    *)
(* ------------------------ *)

module type COMPLETE_commented = COMPLETE

