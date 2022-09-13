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

(** Compositional channels. *)

let standby  y f x = try f x with _ -> y   (* Misc.standby *)

(* --- *)
IFDEF DOCUMENTATION_OR_DEBUGGING THEN
  module Log = Ocamlbricks_log
  DEFINE DEBUGGING(x)=x
ELSE
  DEFINE DEBUGGING(x)=()
ENDIF

(* --- *)
module Club = Lock_clubs.RWM_levels
module Club_set = Set.Make (struct  type t = Club.t  let compare = Club.compare  end)
(* --- *)
type waiting_room = Lock_clubs.waiting_room
type 'a review   = ('a option, exn) result
type 'a reviewer = 'a -> 'a -> 'a review

(* Used below to store the map resid -> commits_no *)
module Int_map = Map.Make (struct type t = int  let compare = compare end)
type resid_commits_snapshot = int Int_map.t

(* ------------------------------ *)
(* Control of exposed resistances *)
(* ------------------------------ *)

type status  = (bool * bool lazy_t)
 and control = commits_no * status (* should be called "detailed status" *)
 and commits_no = int

(* We suppose here that the compared structures (old and new value) are PERSISTENT (not mutable).
   In this hypothesis, if they are (==) or (=) there is no need to notify anyone for changes,
   because there are no changes.
   ---
   Note that the equality test (eq) must be protected, because it could raise exceptions caused
   for instance by functional or lazy values (Invalid_argument "compare: functional value").
   *)
let status_implies_notification ((eqq, eq): status) : bool =
  let no_changes = (eqq) || (try (Lazy.force eq) with _ -> false (* as a precaution *)) in
  not no_changes (* i.e. there are changes *)

(* ------------------------------ *)
(*     Generic "book" functor     *)
(* ------------------------------ *)

(* For testing/debugging: *)
module type BOOK = sig
  val stats_alive    : unit -> Hashtbl.statistics
  val clean          : unit -> unit
  val alarm          : Gc.alarm lazy_t
  val get_orphan_ids : ?clean:unit -> unit -> int list
end

(* Pattern for clean tools, with facilities for debugging: *)
let make_clean_tool ~the_global_book ~module_name () =
  fun () ->
    Lock_clubs.Single_level.with_lock (the_global_book) (fun wt ->
      let _n0 = DEBUGGING(wt#stats.Hashtbl.num_bindings) in
      let () = wt#clean in
      let _n1 = DEBUGGING(wt#stats.Hashtbl.num_bindings) in
      let () = DEBUGGING(Log.printf2 ~v:2 "%s: weak hash table CLEANED (removed %d elements)\n" (module_name) (_n0 - _n1)) in
      ()
      ) |> Either.extract_or_raise


(* The book made by this functor is a weak hash table based on an identifier function. This will be absolutely relevant
   for the book of Conjunction.t because  *)
module Book_of_functor (M: sig  type 'a t  val identifier: 'a t -> int  val name: string  end)
: sig
    val register : 'a M.t -> unit
    (* --- For testing/debugging: *)
    val stats_alive : unit -> Hashtbl.statistics
    val clean       : unit -> unit
    val alarm       : Gc.alarm lazy_t
    (* --- *)
    val get_orphan_ids : ?clean:unit -> unit -> int list
  end

= struct

  (* Used as a reference: *)
  let consistency : unit lazy_t = lazy (true |> ignore)
  (*--- *)
  (* We suppose that all types 'a t are blocks: *)
  let check_consistency (t: 'a M.t) : unit =
    let () = (assert (Obj.is_block (Obj.repr t))) in
    let () = DEBUGGING(Log.printf1 ~v:2 "%s: BOOK CONSISTENCY CHECKED\n" (M.name)) in
    Lazy.force consistency

  (* Single level, simplest locks with 1 condition variable (unused here): *)
  module Lock = Lock_clubs.Single_level

  type book = Lock.t * (fake M.t, int) Table.t
   and fake = int

  let the_global_book : book =
    let lock = Lock.create () in
    let wt : (fake M.t, int) Table.t = Table.make ~weak:() (* ephemerons *) ~equality:(==) ~identifier:(M.identifier) () in
    (lock, wt)

  (* Create another book to store used identifiers: *)
  let id_book = Hashset.make ()

  (* val clean: unit -> unit *)
  let clean = make_clean_tool ~the_global_book ~module_name:(M.name) ()

  (* Gc.create_alarm : (unit -> unit) -> alarm *)
  let alarm = lazy (Gc.create_alarm (clean))

  (* For testing/debugging: val stats_alive: unit -> Hashtbl.statistics *)
  let stats_alive () = Lock.with_lock (the_global_book) (fun wt -> wt#stats_alive) |> Either.extract_or_raise

  let add (t: fake M.t) (t_id) : unit =
    Lock.with_lock (the_global_book) (fun wt -> wt#add (t) (t_id)) |> Either.extract_or_raise

  let register (t: 'a M.t) : unit =
    let t_id = M.identifier t in
    let () = DEBUGGING(Log.printf3 ~v:2 "%s: REGISTERING structure #%d (GC-alarm=%b)\n" (M.name) (t_id) (Lazy.is_val alarm)) in
    (* Activate the GC alarm (once, registering the first time): *)
    let _ = Lazy.force alarm in
    let () = (if not (Lazy.is_val consistency) then check_consistency t) in
    let () = Hashset.add (id_book) (t_id) in
    add (Obj.magic t) (t_id)

  let get_orphan_ids ?clean () : int list  =
    Lock.with_lock (the_global_book) (fun wt ->
      let cited_ids : int list      = Hashset.to_list ~unstable:() (* speed-up *) (id_book) in
      let alive_ids : int Hashset.t = Hashset.of_list (List.map (snd) (wt#to_assoc_list)) in
      let result = List.filter (fun id -> not (Hashset.mem alive_ids id)) (cited_ids) in
      let () = (if clean = Some () then List.iter (Hashset.remove id_book) result) in
      result
      ) |> Either.extract_or_raise

end (* Book_of_functor *)

(* ------------------------------ *)
(*             Book               *)
(*   club-chain ⊢> waiting-rooms  *)
(* ------------------------------ *)

(* This module contains the global structure, shared by all threads, which implements the 1-1 dynamic bijection between
   club-chains (lists) and waiting-rooms. Conflicts acceeding this structure may occur only when objects are created
   (i.e. rarely). *)
module Club_chain_book :
  sig
    type t = Club.t list
    type found = bool
    (* --- *)
    val find_or_bind : club_list:Club.t list -> (t * waiting_room) * found
    val bind         : singleton:t -> waiting_room:waiting_room -> unit
    (* --- For testing/debugging: *)
    val clean: unit -> unit
    val stats_alive: unit -> Hashtbl.statistics
    val alarm : Gc.alarm lazy_t
  end
= struct

  (* Single level, simplest locks with 1 condition variable (unused here): *)
  module Book_lock = Lock_clubs.Single_level

  type book = Book_lock.t * data
    and data = (t Extreme_sharing.identity) * (t, waiting_room) Table.t
    and t = Club.t list

  (* The global (shared by all threads) protected register for club-chains and waiting-rooms: *)
  let the_global_book : book =
    let lock = Book_lock.create () in
    let club_chain_id = Extreme_sharing.make_weakly_memoized_identity () (* ephemerons *) in
    let table : (t, waiting_room) Table.t = Table.make ~weak:() (* ephemerons *) ~equality:(==) () in
    let data = (club_chain_id, table) in
    (lock, data)

  (* val clean: unit -> unit *)
  (* let clean = make_clean_tool ~the_global_book ~module_name:("Channel.Club_chain_book") () *)
  let clean () =
    Book_lock.with_lock (the_global_book) (fun (id, wt) ->
      let _n0 = wt#stats.Hashtbl.num_bindings in
      let () = wt#clean in
      let _n1 = wt#stats.Hashtbl.num_bindings in
      let () = DEBUGGING(Log.printf1 ~v:2 "Channel.Club_chain_book: weak hash table CLEANED (removed %d elements)\n" (_n0 - _n1)) in
      ()
      ) |> Either.extract_or_raise

  (* Gc.create_alarm : (unit -> unit) -> alarm *)
  let alarm = lazy (Gc.create_alarm (clean))

  (* For testing/debugging: val stats_alive: unit -> Hashtbl.statistics *)
  let stats_alive () = Book_lock.with_lock (the_global_book) (fun (id, wt) -> wt#stats_alive) |> Either.extract_or_raise

  type found = bool

  let find_or_bind ~club_list : (t * waiting_room) * found =
    (* Important point here: clubs (locks) are ordered by date of creation (age): *)
    let club_chain_v0 = List.sort_uniq (**) (Club.compare) (**) (club_list) in
    (* --- *)
    Book_lock.with_lock (the_global_book) (fun data ->
      (* --- *)
      let (id, wt)     = data in
      let club_chain   = id (club_chain_v0) in
      let found        = (club_chain == club_chain_v0) in
      let waiting_room = wt#find_or_bind (club_chain) (lazy (Club.new_waiting_room ())) in
      (* --- *)
      ((club_chain, waiting_room), found)
      (* --- *)
      ) |> Either.extract_or_raise

  (* Used to create new channels: *)
  let bind ~singleton ~waiting_room : unit =
    let () = assert ((List.length singleton) = 1) in
    (* Activate the GC alarm (once, registering the first time): *)
    let _ = Lazy.force alarm in
    (* --- *)
    let club_chain_v0 = singleton in
    (* --- *)
    Book_lock.with_lock (the_global_book) (fun data ->
      (* --- *)
      let (id, wt)   = data in
      let club_chain = id (club_chain_v0) in
      let () = assert (club_chain == club_chain_v0) in
      let () = assert (not (wt#mem (club_chain))) in
      let () = wt#replace (club_chain) (waiting_room) in
      ()
      ) |> Either.extract_or_raise

end (* Club_chain_book *)

(* ------------------------------ *)
(*             Book               *)
(*  club ⊢> unstable-conjunction  *)
(* ------------------------------ *)

(* Book of unstable conjunctions indexed by clubs (club -> unstable-conjunction): *)
module Club2UC_book :
  sig
    type uc = { cc: Club_chain_book.t; resid: int; get_commits_no: (unit->int); force_commit: (unit->control); }
    (* --- *)
    val make : Club_chain_book.t -> int -> (unit->int) -> (unit->control) -> uc
    val add  : uc -> unit
    val find : Club.t -> uc list
    (* --- Signature could be reduced to: *)
    val register : Club_chain_book.t -> 'a Res.Exposed.t -> unit
    val remove_resids : int list -> unit
    (* --- For testing/debugging: *)
    val clean: unit -> unit
    val stats_alive: unit -> Hashtbl.statistics
    val alarm : Gc.alarm lazy_t
  end
= struct

  type uc = { cc: Club_chain_book.t; resid: int; get_commits_no: (unit->int); force_commit: (unit->control); }

  (* val make : Club_chain_book.t -> int -> (unit -> unit) -> unit *)
  let make (cc) (resid) (get_commits_no) (force_commit) = { cc; resid; get_commits_no; force_commit; }

  (* Single level, simplest locks with 1 condition variable (unused here): *)
  module Book_lock = Lock_clubs.Single_level

  type book = Book_lock.t * data
    and data = (Club.t, uc) Table.t

  (* The global (shared by all threads) protected register for club-chains and waiting-rooms: *)
  let the_global_book : book =
    let lock = Book_lock.create () in
    (* It's very dangerous here to use an address-based hashing, because clubs are nested into several kind
       of structures (lists, chains, channels). Hence, to avoid problems, we will use an hash function based
       on the identifier Club.id:  *)
    let wt : (Club.t, uc) Table.t = Table.make ~weak:() (* ephemerons *) ~identifier:(Club.id) () in
    (lock, wt)

  (* val clean: unit -> unit *)
  let clean = make_clean_tool ~the_global_book ~module_name:("Channel.Club2UC_book") ()

  (* For testing/debugging: val stats_alive: unit -> Hashtbl.statistics *)
  let stats_alive () = Book_lock.with_lock (the_global_book) (fun wt -> wt#stats_alive) |> Either.extract_or_raise

  (* Gc.create_alarm : (unit -> unit) -> alarm *)
  let alarm = lazy (Gc.create_alarm (clean))

  (* --- *)

  (* Are added in the weak table all links from a club of the conjunction to the whole (unstable) conjunction: *)
  let add (uc) : unit =
    (* --- *)
    Book_lock.with_lock (the_global_book) (fun wt ->
      let () = DEBUGGING(Log.printf4 ~v:3 "Channel.Club2UC_book.add: BEFORE ADDING (#clubs=%d, #wt=%d, chain #%d, uc #%d)\n"
        (List.length uc.cc) (wt#stats.Hashtbl.num_bindings) (Misc.get_magic_identifier uc.cc) (Misc.get_magic_identifier uc))
      in
      List.iter (fun club ->
        let () = DEBUGGING(Log.printf4 ~v:3 "Channel.Club2UC_book.add: ABOUT TO ADD BINDING club #%d (hash: %d) -> chain #%d (ic #%d)\n"
          (Club.id club) (Hashtbl.hash club) (Misc.get_magic_identifier uc.cc) (Misc.get_magic_identifier uc))
        in
        wt#add (club) (uc)
        ) (uc.cc)
      ) |> Either.extract_or_raise

  (* Will be used to remove orphaned binding (club -> collected conjunction): *)
  let remove_resids (resids : int list) : unit =
    let resids = Hashset.of_list (resids) in
    (* --- *)
    Book_lock.with_lock (the_global_book) (fun wt ->
      wt#filter_map_inplace (fun club uc -> if Hashset.mem (resids) (uc.resid) then None else Some uc)
      ) |> Either.extract_or_raise

  let find (club) : uc list =
    (* --- *)
    Book_lock.with_lock (the_global_book) (fun wt ->
      let () = DEBUGGING(Log.printf3 ~v:2 "Channel.Club2UC_book.find: about to find unstable resistances involved by club #%d (#wt=%d, member=%b)\n"
        (Club.id club) (wt#stats.Hashtbl.num_bindings) (wt#mem club))
      in
      wt#find_all (club)
      ) |> Either.extract_or_raise

  (* --- Signature could be reduced to: *)
  let register (cc: Club_chain_book.t) (res: 'a Res.Exposed.t) =
    let resid = (Res.Exposed.id res) in
    let () = DEBUGGING(Log.printf3 ~v:2 "Channel.Club2UC_book: REGISTERING committer for resistance #%d (#clubs=%d, GC-alarm=%b)\n"
      (resid) (List.length cc) (Lazy.is_val alarm)) in
    let uc = make (cc) (resid) (fun () -> Res.Exposed.commits_no res) (fun () -> Res.Exposed.commit_or_warning res) in
    (* Activate the GC alarm (once, registering the first time): *)
    let _ = Lazy.force alarm in
    add uc

  (* let compare uc1 uc2 = Misc.magic_physical_compare (ic1.force_commit) (ic2.force_commit) *)

end (* Club2UC_book *)

(* ------------------------------ *)
(*          Stabilize             *)
(*    an (additive) directory     *)
(*    of unstable conjunctions    *)
(* ------------------------------ *)

module Stabilize : sig
     (* --- *)
     (* In this module a "file" is an unstable conjunction: *)
     type file = Club2UC_book.uc
     (* --- *)
     type ('a, 'x) t =
        Dir of
           (file array) *                (* unprefixed vars, i.e. freely available resources or "files" *)
          ((Club.t * ('a,'x) t) array)   (* prefixed ordered choices (or "subdirectories") *)
     (* --- *)
     val files     : ('a,'x) t -> file array
     val subdirs   : ('a,'x) t -> (Club.t * ('a,'x) t) array
     (* --- *)
     val stairs_lengths : ('a,'x) t -> int array
     (* --- *)
     val of_unstable_conjunctions : Club2UC_book.uc list -> (Club.t, file) t
     val of_club : Club.t -> (Club.t, file) t
     val take_decision : resid:int -> Club_chain_book.t -> unit
     (* --- *)
  end
 = struct

  type file = Club2UC_book.uc

  include Directory_tree.MAKE_additive
    (struct type 'a t = Club.t let compare = Club.compare end)
    (struct type 'a t = file   let compare = Misc.magic_physical_compare end)

  (* Each file (leaf) contains the whole path that leads to it, in the correct order.
    So, the complete (linear) directory may be rebuilt straight-forward: *)
  let rebuild (uc: Club2UC_book.uc) : (Club.t, file) t =
    let open Club2UC_book in
    let club_chain = uc.cc in
    let rec loop = function
    | c::[] -> return c (uc)
    | c::cc -> prepend c (loop cc)
    | [] -> assert false
    in
    loop (club_chain)

  let of_unstable_conjunctions (ucs: Club2UC_book.uc list) =
    let paths = List.map (rebuild) (ucs) in
    list_sum paths

  let of_club (c: Club.t) =
    let ucs = Club2UC_book.find c in
    of_unstable_conjunctions (ucs)

  (* Structural (deep) equality cannot be used here because unstable conjunctions are of different types.
     In a strictly typed language as OCaml the only way to take a snapshot of values of arbitrary types
     could be though Obj.magic. *)
  let implies_notification (rcm: resid_commits_snapshot) (uc: Club2UC_book.uc) =
    (* Note that `force_commit' is Res.Exposed.commit_or_warning, which get the value of
       `commits_no' before to commit the resistance: *)
    let (cn, (eqq, _eq)): control = uc.Club2UC_book.force_commit () in
    if eqq = false then true (* notify *) else (* continue with eqq: *)
    let cn_before_visit = Int_map.find (uc.Club2UC_book.resid) (rcm) in
    (cn > cn_before_visit) (* <=> notify *)

  let stabilizer (rcm: resid_commits_snapshot) (t: (Club.t, file) t) : unit =
    (* --- *)
    let rec visit ((Dir (fs, cts)): (Club.t, file) t) : bool (* <=> implies notification (releasing) *) =
      let n = Array.length fs in
      (* --- *)
      let result : bool =
        if n=0 then (false) else (* continue with n>0: *)
        if n=1 then implies_notification (rcm) fs.(0) else (* n>1 *)
        (* Do commits saving the information about notifications: *)
        Array.fold_left (fun s f -> implies_notification (rcm) (f) || s) (false) (fs)
      in
      (* --- *)
      let visit_subdir (c,t) : bool =
        let () = Club.acquire ~level:0 (* as reader *) c in
        (* Go in depth, and return here knowing if notification are required: *)
        let result : bool = visit t in
        (* --- *)
        let notify = if result then
            let () = DEBUGGING(Log.printf ~v:2 "Channel.Stabilize.stabilizer: ABOUT TO RELEASE BROADCASTING ALL LEVELS\n") in
            Some [2;1;0]
          else
            None
        in
        let () = Club.Protected.release ~level:0 ?notify c in
        result
      in
      (* Go now in depth, if needed: *)
      (* --- *)
      let d = Array.length cts in (* number of directories *)
      if d=0 then (result) else   (* continue with d>0: *)
      (* --- *)
      if d=1 then visit_subdir cts.(0) || result else (* continue with d>1: *)
      (* --- *)
      Array.fold_left (fun s ct -> visit_subdir ct || s) (result) (cts)
    (* --- *)
    (* end of visit() *)
    in
    (* --- *)
    let () = DEBUGGING(Log.printf ~v:2 "Channel.Stabilize.stabilizer: ABOUT TO START THE VISIT\n") in
    visit t |> (fun result ->
      let () = DEBUGGING(Log.printf1 ~v:2 "Channel.Stabilize.stabilizer: RESULT OF THE VISIT (something changed and notifications sent): %b\n" result) in
      ignore result
      )

  (* Decide there is at least one super-structure of the resistance (acquired with the club-chain) that needs to be stabilized.
     This tool is called in a protected section of the provided club-chain, so all super-structures are locked at least for writers.
     For this reason, we are able to get the current number of commits of any involved unstable super-structure: *)
  let take_decision ~resid (club_chain) =
    let ucs = List.map (Club2UC_book.find) (club_chain) |> List.flatten |> List.filter (fun uc -> uc.Club2UC_book.resid <> resid) in
    if ucs = [] then
      let () = DEBUGGING(Log.printf1 ~v:2 "Channel.Stabilize.take_decision: NEEDLESS for resistance #%d\n" (resid)) in
      (* nothing to do *)
      ()
    else (* continue: *)
    (* --- *)
    let rcm : resid_commits_snapshot (* int Int_map.t *) =
      let rcs = List.map (fun uc -> uc.Club2UC_book.resid, uc.Club2UC_book.get_commits_no ()) ucs in
      List.fold_left (fun m (r,c) -> Int_map.add r c m) (Int_map.empty) (rcs)
    in
    let t = of_unstable_conjunctions ucs in
    (* --- *)
    let () = DEBUGGING(Log.printf2 ~v:2 "Channel.Stabilize.take_decision: ABOUT TO LAUNCH A STABILIZER for %d unstable conjunction(s) involved by res. #%d\n"
      (Int_map.cardinal rcm) (resid))
    in
    Thread.create (stabilizer rcm) (t) |> ignore

end (* Stabilize *)

(* ------------------------ *)
(*       Conjunction        *)
(*   (atoms of genealogy)   *)
(* ------------------------ *)

(* A conjunction is a triple (club-chain, waiting-room, resistance): the club-chain represents
   the "protection" (the set of locks) for the resistance, while the waiting-room simply allows
   a thread to wait for an event about the conjunction. A conjunction is said "unstable" if its
   resistance has a reviewer, i.e. an associated reviewing process that may change the state of
   its components as soon as a thread will attempt an access, even in read-only mode. *)
module Conjunction (*: Directory_tree.ZIPPED_FUNCTOR *) = struct

  type 'a t = { cc: Club_chain_book.t;  wr: waiting_room; res: 'a Res.Exposed.t; }

  module Book = Book_of_functor (struct
    type 'a c = 'a t (* alias *)
    type 'a t = 'a c  let identifier t = Res.Exposed.id t.res  let name = "Channel.Conjunction"
    end)

  (* Gc.create_alarm : (unit -> unit) -> alarm *)
  let alarm = lazy (Gc.create_alarm (fun () ->
    let orphan_resids = Book.get_orphan_ids ~clean:() () in (* orphaned resistance ids *)
    let () = DEBUGGING(Log.printf1 ~v:2 "Channel.Conjunction: ABOUT TO REMOVE BINDINGS (club, orphaned-unstable-conjunctions) (#orphans: %d)\n"
      (List.length orphan_resids))
    in
    Club2UC_book.remove_resids (orphan_resids)
    ))

  (* val get : 'a t -> 'a *)
  let get t = Res.Exposed.get (t.res)

  (* val aim : 'a t -> ('a -> 'a) -> 'a * ('a review * status) *)
  let aim t f = Res.Exposed.aim (t.res) f

  let map ?equality (f: 'a -> 'b) (t: 'a t) : 'b t =
    { t with res = Res.Exposed.map ?equality f t.res }

  (* Create a resistance and bind it to a fresh couple of related club and waiting room: *)
  let return ?reviewer (v:'a) : 'a t =
    let c  = Club.create () in
    let cc = c::[] in (* c ⊢> {c} *)
    (* Create an "highland" waiting room: *)
    let wr = Club.new_waiting_room () in
    (* Club_chain_book.bind because the singleton is new, created just now: *)
    let () = Club_chain_book.bind ~singleton:(cc) ~waiting_room:(wr) in
    let () = Club.subscribe (c) [wr] in
    let res = Res.Exposed.return ?reviewer v in
    (* --- *)
    (* A fresh resistance cannot be unstable, so the following line can be commented: *)
    (* let () = if not (Res.Exposed.stable res) then Club2UC_book.register (cc) (res) in *)
    (* --- *)
    (* Define the GC-alarm at the first channel creation: *)
    let _ = Lazy.force alarm in
    (* --- *)
    let result = {cc; wr; res} in
    let () = Book.register (result) in
    result

  let product ?reviewer t1 t2 =
    (* --- *)
    let cs = (List.append t1.cc t2.cc) in (* two "chains" appended become a list, not a chain *)
    (* --- *)
    (* Sort, remove duplicates, remove duplicates from the mutex list unique
       and, possibly, reuse a previously associated waiting-room, if any: *)
    let (cc, wr), found =
      Club_chain_book.find_or_bind ~club_list:(cs)
    in
    (* --- *)
    let res = Res.Exposed.product ?reviewer (t1.res) (t2.res) in
    (* --- *)
    let result = { cc; wr; res } in
    (* If the waiting-room was found, there's nothing to do (subscriptions have been already done).
       Otherwise, we have to subscribe wr to all components (in a critical section of the whole
       group and with the high level of priority): *)
    let () = if found then () else
      (* Subscriptions are performed in critical section for each club. The order is not relevant
         because this action may be done locking each mutex separately, with no need to lock
         the whole group at the same time: *)
      List.iter (fun club -> Club.subscribe club [wr]) (cc)
    in
    (* --- *)
    let () = if not (Res.Exposed.stable res) then Club2UC_book.register (cc) (res) in
    let () = Book.register (result) in
    (* --- *)
    result

  (* NOTE: the following operations, doing projections (split, fst_prj, snd_prj), inherit the
           club-chain of their parents as is. So, they will be used only when we can't do better,
           i.e. when we will not be able to retrieve their genealogical history (product factors). *)

  (* Note that the club-chain is inherited from parent: *)
  let split ?fst_reviewer ?snd_reviewer t =
    let res1, res2 = Res.Exposed.split ?fst_reviewer ?snd_reviewer t.res in
    (* --- *)
    (* Same club and waiting room for both components: *)
    let t1 = { t with res = res1 } in
    let t2 = { t with res = res2 } in
    (* --- *)
    let () = if not (Res.Exposed.stable res1) then Club2UC_book.register (t.cc) (res1) in
    let () = if not (Res.Exposed.stable res2) then Club2UC_book.register (t.cc) (res2) in
    let () = Book.register (t1) in
    let () = Book.register (t2) in
    (* --- *)
    (t1, t2)

  (* Note that the club-chain is inherited from parent: *)
  let fst_prj ?reviewer t =
    let res1 = Res.Exposed.fst_prj ?reviewer t.res in
    (* --- *)
    let () = if not (Res.Exposed.stable res1) then Club2UC_book.register (t.cc) (res1) in
    let result = { t with res = res1 } in
    let () = Book.register (result) in
    (* --- *)
    result

  (* Note that the club-chain is inherited from parent: *)
  let snd_prj ?reviewer t =
    let res2 = Res.Exposed.snd_prj ?reviewer t.res in
    (* --- *)
    let () = if not (Res.Exposed.stable res2) then Club2UC_book.register (t.cc) (res2) in
    let result = { t with res = res2 } in
    let () = Book.register (result) in
    (* --- *)
    result

  (* val cover : 'a t -> ('a -> 'a -> 'a review) -> 'a t
     Note that the club-chain is inherited from parent: *)
  let cover t reviewer =
    (* --- *)
    let res' = Res.Exposed.cover t.res reviewer in
    let () = Club2UC_book.register (t.cc) (res') in
    let result = { t with res = res' } in
    let () = Book.register (result) in
    (* --- *)
    result

  (* --- *)

  (* compare = oldest resistance (by object identifiers) *)
  let compare (t1 : 'a t) (t2: 'a t) =
    Res.Exposed.compare (t1.res) (t2.res)

end (* Conjunction *)

(* ---------------------------- *)
(*   FTC_conjunction or FTCC    *)
(*           (files)            *)
(* ---------------------------- *)

(* "FTC_conjunction" stands for (F)amily (T)ree (C)losed conjunction (abreviated in "FTCC").
   Morally, it's a conjunction that preserves the history of its proper building,
   i.e. the genealogy of free products which have generated the information stored
   at the root level, where we have something of type:

   type 'a t = { cc: Club_chain_book.t;  wr: waiting_room; res: 'a Res.Exposed.t; }

   and we can access to "free" components, if any, by `fst_prj' and `snd_prj'.
*)
module FTC_conjunction = struct

  (* Genealogy of "free" products (i.e. products without a reviewer or,
     intuitively, without a global resistance). *)
  module Genealogy = Sexpr.GENEALOGY_OF_ZIPPED (
    struct
      type 'a t = 'a Conjunction.t
      let return v = Conjunction.return ?reviewer:None v
      let zip (x,y) = Conjunction.product ?reviewer:None x y
      (* The following operations will be used when we can't do better,
         i.e. when we can't retrieve the genealogical history (product factors): *)
      let unzip xy = Conjunction.split ?fst_reviewer:None ?snd_reviewer:None xy
      let fst = Some (fun xy -> Conjunction.fst_prj ?reviewer:None xy)
      let snd = Some (fun xy -> Conjunction.snd_prj ?reviewer:None xy)
    end)

  (* S-expression of free products, i.e. a conjunction with its genealogy: *)
  type 'a t = 'a Genealogy.t

  let return ?reviewer (v:'a) : 'a t =
    Genealogy.atom (Conjunction.return ?reviewer v)

  (* The three components of the structure: *)
  let club_chain   t = (Genealogy.root t).Conjunction.cc
  let waiting_room t = (Genealogy.root t).Conjunction.wr
  let resistance   t = (Genealogy.root t).Conjunction.res

  (* For debugging/testing: *)
  let string_of_club_chain t =
    String.concat " " (List.map (Printf.sprintf "#%d") (List.map (Club.id) (club_chain t)))

  (* val get : 'a t -> 'a *)
  let get t = Conjunction.get (Genealogy.root t)

  (* val aim : 'a t -> ('a -> 'a) -> 'a * ('a review * status) *)
  let aim t f = Conjunction.aim (Genealogy.root t) f

  let product ?reviewer (x : 'a t) (y : 'b t) : ('a * 'b) t =
    match reviewer with
    | None -> (* free => node *)
        Genealogy.product x y  (* cons ∘ Z.zip ∘ (root, root) *)
    (* --- *)
    | Some reviewer -> (* non-free => atom *)
        Genealogy.atom (Conjunction.product ~reviewer (Genealogy.root x) (Genealogy.root y))

  let cover (x:'a t) (reviewer) : 'a t =
    Genealogy.atom (Conjunction.cover (Genealogy.root x) reviewer)

  (* Weakly memoize with physical equality: *)
  let map (*?equality*) (f:'a -> 'b) (x:'a t) : 'b t =
    Genealogy.atom (Conjunction.map ~equality:(==) f (Genealogy.root x))

  (* Renamed later in `fst' as usual: *)
  let fst_prj ?reviewer (xy : ('a * 'b) t) : 'a t =
    match reviewer with
    | None -> (* free => car (fst) *)
        Genealogy.car xy
    (* --- *)
    | Some reviewer -> (* non-free => atom *)
        Genealogy.atom (Conjunction.cover (Genealogy.car xy |> Genealogy.root) reviewer)

  (* Renamed later in `snd' as usual: *)
  let snd_prj ?reviewer (xy : ('a * 'b) t) : 'b t =
    match reviewer with
    | None -> (* free => cdr (snd) *)
        Genealogy.cdr xy
    (* --- *)
    | Some reviewer -> (* non-free => atom *)
        Genealogy.atom (Conjunction.cover (Genealogy.cdr xy |> Genealogy.root) reviewer)

  (* split tries to reuse ancestors calling `fst_prj' and `snd_prj':  *)
  let split ?fst_reviewer ?snd_reviewer (xy : ('a * 'b) t) : ('a t) * ('b t) =
    let x = fst_prj ?reviewer:fst_reviewer xy in
    let y = snd_prj ?reviewer:snd_reviewer xy in
    (x, y)

  let unzip xy = split ?fst_reviewer:None ?snd_reviewer:None xy
  let zip (x,y) = product ?reviewer:None x y

  let fst xy = fst_prj ?reviewer:None xy
  let snd xy = snd_prj ?reviewer:None xy

  let compare x y = Conjunction.compare (Genealogy.root x) (Genealogy.root y)
end (* FTC_conjunction *)

(* Alias: *)
module FTCC = FTC_conjunction

(* ---------------------------------- *)
(*             FTCC_dir               *)
(*  (tree structured FTTC's choices)  *)
(* ---------------------------------- *)

module FTCC_dir : sig
     (* --- *)
     type ('a, 'x) t =
        Dir of
           ('x FTCC.t array) *           (* unprefixed vars, i.e. freely available resources or "files" *)
          ((Club.t * ('a,'x) t) array)   (* prefixed ordered choices (or "subdirectories") *)
     (* --- *)
     val return    : Club.t -> 'x FTCC.t -> ('a,'x) t
     val prepend   : Club.t -> ('a,'x) t -> ('a,'x) t
     (* --- First level: *)
     val files     : ('a,'x) t -> 'x FTCC.t array
     val subdirs   : ('a,'x) t -> (Club.t * ('a,'x) t) array
     (* --- *)
     val all_files : ('a,'x) t -> ('x FTCC.t) array
     val all_stairs: ('a,'x) t -> (Club.t) array
     (* --- *)
     val stairs_lengths : ('a,'x) t -> int array
     (* --- *)
     val map_files         : ('x FTCC.t -> 'y FTCC.t) -> ('a,'x) t -> ('a,'y) t
     val map_file_contents : ('x -> 'y) -> ('a,'x) t -> ('a,'y) t
     (* --- *)
     val zero      : ('a,'x) t
     val plus      : ('a,'x) t -> ('a,'x) t -> ('a,'x) t
     val array_sum : ('a,'x) t array -> ('a,'x) t
     val list_sum  : ('a,'x) t list  -> ('a,'x) t
     val choose    : ('a,'x) t -> ('x FTCC.t) option
     (* --- *)
     val times      : ?file_zip  :('x FTCC.t * 'y FTCC.t -> ('x * 'y) FTCC.t) -> ('a,'x) t -> ('a,'y) t -> ('a, 'x * 'y) t
     val split      : ?file_unzip:(('x * 'y) FTCC.t -> 'x FTCC.t * 'y FTCC.t) -> ('a, 'x * 'y) t -> ('a,'x) t * ('a,'y) t
     val fst        : ?file_fst  :(('x * 'y) FTCC.t -> 'x FTCC.t) -> ('a, 'x * 'y) t -> ('a, 'x) t
     val snd        : ?file_snd  :(('x * 'y) FTCC.t -> 'y FTCC.t) -> ('a, 'x * 'y) t -> ('a, 'y) t
  end
 =
  Directory_tree.MAKE
    (struct type 'a t = Club.t let compare = Club.compare end)
    (FTCC)

(* ---------------------------- *)
(*         Constructors         *)
(* ---------------------------- *)

(* Directories of S-expressions of free products
   of triples (club-chain, waiting-room, resistance): *)
type 'a t = (Club.t, 'a) FTCC_dir.t

let create ?reviewer (v:'a) : 'a t =
  let ftcc = FTCC.return ?reviewer v in
  let club = List.hd (FTCC.club_chain ftcc) in (* club_chain is a singleton *)
  FTCC_dir.return (club) (ftcc)

let cover (t:'a t) (reviewer) : 'a t =
  FTCC_dir.map_files (fun w -> FTCC.cover w reviewer) t

let map = FTCC_dir.map_file_contents

let lengths = FTCC_dir.stairs_lengths

(* Each file (leaf) contains the whole path that leads to it, in the correct order.
   So, the complete (linear) directory may be rebuilt straight-forward: *)
let rebuild (w:'a FTCC.t) : 'a t =
  let club_chain = FTCC.club_chain w in
  let rec loop = function
  | c::[] -> FTCC_dir.return c w
  | c::cc -> FTCC_dir.prepend c (loop cc)
  | [] -> assert false
  in
  loop (club_chain)

(* Split optimized through the hystory of products.
---
It should be noted that, in order to obtain the optimization, the function `FTCC_dir.split' must be *avoided*.
Indeed, it makes a perfect copy (map) of the directory structure, whereas some directories only concern the
first projection, or only the second. Taking advantage of the fact that the files contain the paths that lead
to them (what a useful redundancy!), we will make an extraction of all the involved files, then the separation,
then the reconstruction of the directories really necessary for each projection.
---
The more natural, but not optimal, definition would have been as follows:
---
let (*naive_*)split ?fst_reviewer ?snd_reviewer (t :('a * 'b) t) : ('a t) * ('b t) =
  let file_unzip =
    match fst_reviewer, snd_reviewer with
    | None, None                           -> None
    | None, Some snd_reviewer              -> Some (fun xy -> FTCC.split ~snd_reviewer xy)
    | Some fst_reviewer, None              -> Some (fun xy -> FTCC.split ~fst_reviewer xy)
    | Some fst_reviewer, Some snd_reviewer -> Some (fun xy -> FTCC.split ~fst_reviewer ~snd_reviewer xy)
  in
  FTCC_dir.split ?file_unzip t
--- *)
let split ?fst_reviewer ?snd_reviewer (t :('a * 'b) t) : ('a t) * ('b t) =
  (* --- *)
  let files = FTCC_dir.all_files t in
  (* --- *)
  (* Here `FTCC.split' may find in its genealogy its original factors,
     each one with the list of its related and strictly necessary locks: *)
  let files1, files2 = Array.map (FTCC.split ?fst_reviewer ?snd_reviewer) files |> ArrayExtra.split in
  (* --- *)
  let paths1 = Array.map (rebuild) files1 in
  let paths2 = Array.map (rebuild) files2 in
  (* --- *)
  let t1 = FTCC_dir.array_sum paths1 in
  let t2 = FTCC_dir.array_sum paths2 in
  (* --- *)
  (t1, t2)

(* First projection optimized through the hystory of products and the rebuilding process
   as explained for `split'.
---
The more natural, but not optimal, definition would have been as follows,
where `FTCC_dir.fst' suffers from the same problem as explained for `FTCC_dir.split':
---
let (*naive_*)fst_prj ?reviewer (t :('a * 'b) t) : ('a t) =
  let file_fst = Option.map (fun reviewer -> fun xy -> FTCC.fst_prj ~reviewer xy) reviewer in
  FTCC_dir.fst ?file_fst t
--- *)
let fst_prj ?reviewer (t :('a * 'b) t) : ('a t) =
  (* --- *)
  let files = FTCC_dir.all_files t in
  (* --- *)
  (* Here `FTCC.fst_prj' may find in its genealogy the original first projection: *)
  let files1 = Array.map (FTCC.fst_prj ?reviewer) files in
  let paths1 = Array.map (rebuild) files1 in
  let t1 = FTCC_dir.array_sum paths1 in
  t1

(* Second projection optimized through the hystory of products and the rebuilding process
   as explained for `split'.
---
The more natural, but not optimal, definition would have been as follows,
where `FTCC_dir.snd' suffers from the same problem as explained for `FTCC_dir.split':
---
let (*naive_*)snd_prj ?reviewer (t :('a * 'b) t) : ('b t) =
  let file_snd = Option.map (fun reviewer -> fun xy -> FTCC.snd_prj ~reviewer xy) reviewer in
  FTCC_dir.snd ?file_snd t
--- *)
let snd_prj ?reviewer (t :('a * 'b) t) : ('b t) =
  (* --- *)
  let files = FTCC_dir.all_files t in
  (* --- *)
  (* Here `FTCC.snd_prj' may find in its genealogy the original second projection: *)
  let files2 = Array.map (FTCC.snd_prj ?reviewer) files in
  let paths2 = Array.map (rebuild) files2 in
  let t2 = FTCC_dir.array_sum paths2 in
  t2

(* --- *)
let product ?reviewer (x : 'a t) (y : 'b t) : ('a * 'b) t =
  let file_zip = Option.map (fun reviewer -> fun (x,y) -> FTCC.product ~reviewer x y) reviewer in
  FTCC_dir.times ?file_zip x y

let zero = FTCC_dir.zero
let plus = FTCC_dir.plus
let array_sum = FTCC_dir.array_sum
let list_sum = FTCC_dir.list_sum

(* `times' is `product' without the option ?reviewer *)
let times x y = FTCC_dir.times ?file_zip:None x y

(* Aliases have no optional parameters: *)
let unzip xy = split ?fst_reviewer:None ?snd_reviewer:None xy
let zip (x,y) = product ?reviewer:None x y

(* ------------------------ *)
(*        Collector         *)
(* ------------------------ *)

(* A simple structure (1-club-channel) used later as support
   to implement the general procedure `acquire_with_guard': *)
module Collector = struct

  module Club = Lock_clubs.RWM_levels (* 3 levels *)

  (* We attach an "highland" waiting room (snd projection): *)
  type 'a t = (Club.t * ('a list) Res.t) * Lock_clubs.waiting_room

  let make () =
    let lock = Club.create () in
    let wr = Club.new_waiting_room () in
    let () = Club.subscribe lock [wr] in
    ((lock, Res.return []), wr)

  let reader = 0
  let writer = 1
  let maintainer = 2

  let flush (t:'a t) : 'a list =
    let () = DEBUGGING(Log.printf1 ~v:3 "Channel.Collector.flush: ABOUT TO WAIT FOR SOMETHING IN COLLECTOR (CLUB #%d, as writer)\n" (t|>fst|>fst|>Club.id)) in
    Club.with_acquire
      ~level:(writer)
      ~guard:(fun r -> (Res.get r) <> [])
      ~waiting_room:(snd t)
      ~notify:[writer; reader]  (* AT HIGHLAND *)
      (fst t)
      (fun res ->
         let () = DEBUGGING(Log.printf ~v:3 "Channel.Collector.flush: ABOUT TO FLUSH COLLECTOR\n") in
         Res.apply_rw res (fun xs -> [], fun _ -> xs)
         )
       |> Either.extract_or_raise

  let add (x:'a) (t:'a t) : unit =
    Club.with_acquire
      ~level:(maintainer)
      ~notify:[writer; reader]  (* AT HIGHLAND *)
      (fst t)
      (fun res ->
         let () = DEBUGGING(Log.printf ~v:3 "Channel.Collector.add: ABOUT TO ADD INTO COLLECTOR\n") in
         Res.apply_rw res (fun xs -> x::xs, fun _ -> ())
         )
       |> Either.extract_or_raise

  let taste ?guard (t:'a t) : 'a list =
    Club.with_acquire
      ~level:(reader)
      ?guard
      ~waiting_room:(snd t) (* used only when ?guard will be provided *)
      (fst t)
      (fun res ->
         let () = DEBUGGING(Log.printf ~v:3 "Channel.Collector.taste: ABOUT TO TASTE COLLECTOR\n") in
         Res.apply_ro res (fun xs -> xs)
         )
       |> Either.extract_or_raise

end (* Collector *)

(* ------------------------ *)
(*        Countdown         *)
(* ------------------------ *)

module Countdown :
  sig
    module Lock = Lock_clubs.Single_level
    type t = Lock.t * int ref
    val make : int -> t
    (* --- *)
    val decr      : t -> unit
    val wait_zero : t -> unit
  end
  = struct

  module Lock = Lock_clubs.Single_level

  type t = Lock.t * (int ref)

  let make n =
    let lock = Lock.create () in
    (lock, ref n)

  let reader = 0
  let writer = 1

  let decr (t:t) : unit =
    Lock.with_lock ~level:(writer) t (fun r ->
         let () = DEBUGGING(Log.printf ~v:3 "Channel.Countdown.decr: ABOUT TO DECREMENT\n") in
         decr r;
         (* Here an exemple of non trivial broadcast policy: 1 (writer) =/> {1,0}: *)
         if !r <= 0 then Lock.Critical.broadcast ~levels:[0] (fst t) else ()
         )
       |> Either.extract_or_raise

  let wait_zero (t:t) : unit =
    Lock.with_lock ~level:(reader) t
      ~guards:[| (fun r -> if !r <= 0 then Some (fun () -> ()) else None) |]
      (fun r -> DEBUGGING(Log.printf ~v:3 "Channel.Countdown.wait_zero: REACHED ZERO\n"))
       |> Either.extract_or_raise

end (* Countdown *)

(* ------------------------ *)
(*         Acquire          *)
(* ------------------------ *)

(* Without a guard we have simply to choose an available conjunctions of locks
   then acquire it in the good order.
   ---
   NOTE: this implies that any method without guard is non-deterministic!
   ---
   *)
let acquire_no_guard ?level t =
  match FTCC_dir.choose t with
  | None -> invalid_arg "Channel: acquire: empty channel (zero) cannot be acquired"
  | Some ftcc ->
      let club_chain = FTCC.club_chain (ftcc) in
      let () = List.iter (Club.acquire ?level) (club_chain) in
      let v = lazy (Res.Exposed.get ((FTCC.Genealogy.root ftcc).Conjunction.res)) in
      (ftcc, v)

(* --- Launch a guardian: *)
let guardian ~ftcc ~collector ~mutex ~countdown ~waiting_room () : unit =
  let () = DEBUGGING(Log.printf ~v:3 "Channel: ABOUT TO CREATE A GUARDIAN\n") in
  (* --- *)
  Thread.create (fun () ->
    Mutex.lock mutex;
    Countdown.decr countdown;               (* meanwhile, the main thread waits for the counter to become 0 *)
    (* --- *)
    let () = DEBUGGING(Log.printf ~v:3 "Channel: guardian: ABOUT TO BEGIN A PASSIVE WAITING\n") in
    Condition.wait waiting_room.(0) mutex;  (* wait on "highland" level 0 (i.e. as reader) *)
    let () = DEBUGGING(Log.printf ~v:3 "Channel: guardian: WOKEN UP FROM PASSIVE WAITING\n") in
    (* --- *)
    Collector.add (ftcc) collector;         (* put the ftcc into collector *)
    Mutex.unlock mutex;
    ) () |> ignore

(* Some micro-optimizations:
   (1) FTCC.get is developped
   (2) we store the resistance's value that verify the guard: *)
let wguard (buffer:'a option ref) (guard: 'a -> bool) (ftcc: 'a FTCC.t) =
  try
    let x = (Res.Exposed.get ((FTCC.Genealogy.root ftcc).Conjunction.res)) (* FTCC.get ftcc *) in
    let y : bool = standby false guard x in
    let () = (if y then buffer := Some x) in
    y
  with e ->
    let () =
      DEBUGGING(Log.printf2 "Channel.acquire: exception raised: %s => guard cannot be tested for club chain %s => supposed false\n"
        (Printexc.to_string e) (FTCC.string_of_club_chain ftcc))
    in
    false

let acquire_with_guard ~(guard: 'a -> bool) ?level (t) : ('a FTCC.t) * ('a lazy_t) (* the acquired structure among several choices *) =
  (* Lazy values will be forced by the same thread, if needed, so it will be safe: *)
  let collector = lazy (Collector.make ()) in
  let v = ref None in
  let wguard = wguard v guard in (* instanciate *)
  (* --- *)
  let rec visit_starting_guardians t =
    (* --- *)
    let rec loop ((FTCC_dir.Dir (ws, cts)): 'a t) : ('a FTCC.t) option * (waiting_room list) =
      let n = Array.length ws in
      (* --- *)
      let result : ('a FTCC.t) option =
        if n=0 then None else (* continue with n>0: *)
        if n=1 then
          let w = ws.(0) in
          if wguard w then (Some w) else None
        else (* n>1 *)
          (ArrayExtra.find_opt ~round_from_random:() (wguard) ws)
      in
      if (result <> None) (* found *) then (result, []) else (* continue looking into subdirectories: *)
      (* --- *)
      let ctguard (created_wrs) (c,t) : ('a FTCC.t) option * (waiting_room list) =
        let () = Club.acquire ?level c in
        (* Go in depth, collecting waiting rooms that will be subscribed to `c': *)
        let result, next_wrs_to_join_c = loop t in
        (* --- *)
        let created_wrs (* to wake-up guardians *) =
          match result with
          | None ->
              let wrs = List.append (next_wrs_to_join_c) (created_wrs) in
              (* --- *)
              let failed_ftcc = FTCC_dir.files t in
              let k = Array.length (failed_ftcc) in
              if k = 0 then (Club.Protected.release ?level c; wrs) else (* launch guardians: *) begin
                (* --- *)
                let countdown = Countdown.make k in
                let collector = Lazy.force collector in
                (* The mutex and waiting room for new guardians: *)
                let mutex = Club.mutex c in
                let wr = Club.new_waiting_room () in (* <= should be of single level (for readers only) *)
                (* --- *)
                (* Launch guardians: *)
                let () = Array.iter (fun ftcc -> guardian ~ftcc ~collector ~mutex ~countdown ~waiting_room:(wr) ()) (failed_ftcc) in
                (* --- *)
                let () = Countdown.wait_zero (countdown) in
                (* The release procedure suppose a lock-unlock action which is fundamental to synchronize
                   the main thread with the guardians. Actually, at this point the `countdown' is zero, so
                   we are sure that all guardians are waiting on `mutex'. Hence, no event about the club c
                   may be loss and we can release it. Note that we suppose here that "highland" broadcasts
                   are only performed in protected sections. *)
                let () = Club.Protected.release ?level ~subscribe:(wr::next_wrs_to_join_c) c in
                (* --- *)
                (wr :: wrs) (* one more if k>0 *)
              end
          | success -> [] (* guardians are useless and they will wake-up by the main thread *)
        in
        (result, created_wrs)
      in
      (* --- *)
      let d = Array.length cts in (* number of directories *)
      if d=0 then (None, []) else (* continue with d>0: *)
      (* --- *)
      let created_wrs = [] in
      if d=1 then ctguard (created_wrs) cts.(0) else (* continue with d>1: *)
      (* --- *)
      (* val find_folding  : ?round_from_random:unit -> 's -> 'a array -> ('s -> 'a -> 'b option * 's) -> 'b option * 's *)
      ArrayExtra.find_folding ~round_from_random:() (created_wrs) (cts) (ctguard)
      (* --- *)
    in (* loop *)
    (* --- *)
    let result, created_wrs = loop t in
    (* --- *)
    match result with
    | Some ftcc -> (ftcc, created_wrs) (* success, with this acquired ftcc *)
    | None ->
        (* Prepare the next attempt, i.e. the next visit, on a subtree of the initial directory: *)
        let collector = Lazy.force collector in
        (* Wait and get all the ftcc involved by an event (broadcasted): *)
        (* --- *)
        let ftcc_list = Collector.flush collector in
        (* --- *)
        let paths = List.map (rebuild) (ftcc_list) in
        let t' = FTCC_dir.list_sum paths in
        (* Note that the collector is shared by all recursive calls as the following: *)
        let ftcc, created_wrs' = visit_starting_guardians t' in
        (ftcc, List.append created_wrs' created_wrs)
  (* --- *)
  (* end of visit_starting_guardians() *)
  in
  (* --- *)
  let ftcc, created_waiting_rooms =
    visit_starting_guardians t
  in
  (* --- *)
  (* Wake-up all living guardians: *)
  let () = List.iter (fun wr -> Condition.broadcast wr.(0)) (created_waiting_rooms) in
  (* --- *)
  let v : 'a lazy_t = lazy (match !v with Some x -> x | None -> assert false) in
  (* --- *)
  (ftcc, v)


(* val acquire ?guard: 'a -> bool -> ?level:int -> 'a t -> 'a FTCC.t (* the acquired structure among several choices *) *)
let acquire ?guard =
  match guard with
  | None -> acquire_no_guard
  | Some guard -> acquire_with_guard ~guard

(* ------------------------ *)
(*         release          *)
(* ------------------------ *)

(* val release : ?level:int -> ?notify:int list (*[]*) -> 'a FTCC.t -> unit *)
(* We suppose that the level of releasing will be the same used to acquire the resource: *)
let release ?level ?notify (ftcc: 'a FTCC.t) =
  (* Release (broadcasting) all clubs in the *same* order of acquirement (first acquired, first released): *)
  List.iter (Club.Protected.release ?level ?notify) (FTCC.club_chain ftcc)

(* ------------------------ *)
(*           wait           *)
(* ------------------------ *)

(* Private method: *)
let list_destruct = function
| x::xs -> (x,xs)
| [] -> assert false

(* Wait procedure to be called in protected section.
   Something happens for the conjunction if something happens somewhere into. *)
let wait ~release_level ~wait_level ?notify (ftcc: 'a FTCC.t) = begin
  let clubs = FTCC.club_chain ftcc in
  let clubs_head, clubs_tail = list_destruct (clubs) in
  let clubs_wr = FTCC.waiting_room ftcc in
  (* --- *)
  (* Release (broadcasting) the tail of clubs (in the same, not the reversed, order of acquirement).
     This choice gives a kind of priority to bigger structures which have a bigger scope of influence. *)
  let critical_hook (head_mutex) =
    () |> Thread.create (fun () ->
      (* The following locking-unlocking is fundamental to synchronize the main thread with the others.
         When the resources will be released (by this child) the main thread will be already in a
         waiting position. In this way, it will not lose any event produced by other threads: *)
      Mutex.lock   (head_mutex);
      Mutex.unlock (head_mutex);
      List.iter (Club.Protected.release ~level:(release_level) ?notify) (clubs_tail)
      ) |> ignore
  in
  (* --- *)
  (* Wait using the waiting room associated to the conjunction (club_chain), at the good place (level)
     and using the *lowest* mutex. No need to create a child with a critical hook if there are no
     resources to release other than the head itself (i.e. if the conjunction is a singleton): *)
  let () = match clubs_tail = [] with
    | true  -> Club.Protected.wait_choosy ~release_level ~wait_level ?notify ?critical_hook:None (clubs_wr) (clubs_head)
    | false -> Club.Protected.wait_choosy ~release_level ~wait_level ?notify ~critical_hook      (clubs_wr) (clubs_head)
    in
  (* --- Go back to have all components be acquired: *)
  List.iter (Club.acquire ~level:(wait_level) ?guard:None) (clubs_tail)
  end

(* ------------------------ *)
(*         require          *)
(* ------------------------ *)

(* The usual pattern with two notable differences:
   (1) parameter ?notify, if any, are used only once, for waiting the first time
   (2) the release_level is used the first time, after we continue with wait_level *)
let require ~release_level ~wait_level ?notify ~guard (ftcc: 'a FTCC.t) : bool * 'a =
  let buffer = ref None in
  let wguard () = wguard buffer guard ftcc in (* instanciate *)
  (* --- *)
  if wguard () then (true, (match !buffer with Some x -> x | None -> assert false)) (* fine, return immediately *)
  else (* continue: *)
  let () = (*self.*)wait ~release_level ~wait_level ?notify (ftcc) in
  (* --- *)
  while not (wguard ()) do
    (*self.*)wait ~release_level:(wait_level) ~wait_level ?notify:None (ftcc)
  done;
  (* Indicate that the guard wasn't immediately true: *)
  (false, (match !buffer with Some x -> x | None -> assert false))

(* ------------------------ *)
(*      with_acquire        *)
(* ------------------------ *)

(* Notifications are set by default according to the level of access: *)
let notify_defaults = [| (* 0 ⊢> *)[]; (* 1 ⊢> *)[1;0]; (* 2 ⊢> *)[2;1;0] |]

(* ------------------------ *)
(*         Access           *)
(*  (meticulous and easy )  *)
(* ------------------------ *)

(* The field v2 is mutable in order to provide to the user the possibility to control
   the changes occurred after the optional guard `leave'. Indeed, if the user is interested
   by details, it can simply program the body of the `access' method (of type 'a FTCC.t -> 'a details -> 'a -> 'a -> 'b)
   including the details into the result of type 'b. *)
type 'a details = { v0: 'a; v1: 'a; mutable v2: 'a option; review: 'a review; status: status; }
let unchanged : status = (true, lazy true)
let no_review = Ok None

(* General and meticulous access to the channel. Execute a function (method) in protected section: *)
module Meticulous = struct

  (* Note that 1 is the minimum level for a writer, so: update => level>=1  *)
  let access ?(level=1) ?ephemeral ?enter ?notify ?update ?leave t (f:'a FTCC.t -> 'a details -> 'a -> 'a -> 'b) : (exn, 'b) Either.t =
    let level = if update = None then level else (if level = 0 then 1 else level) in (* update => level>=1 *)
    let notify = match notify with None -> Some notify_defaults.(level) | notify -> notify in
    (* --- *)
    let ftcc, v0 = acquire ?guard:(enter) ~level t in
    let () = DEBUGGING(Log.printf1 ~v:2 "Channel.access: entering the protected section with for club chain %s\n" (FTCC.string_of_club_chain ftcc)) in
    let res : 'a Res.Exposed.t lazy_t = lazy ((FTCC.Genealogy.root ftcc).Conjunction.res) in
    (* --- *)
    let ev0 = Either.force v0 in
    (* --- *)
    match ev0 with
    | Either.Left e ->
        (* release and return: *)
        let () = release ~level (ftcc) in
        Either.Left e
    (* --- *)
    | Either.Right v0 -> (* continue: *)
    (* --- *)
    let (v1, (review, status)) =
      let do_nothing = (v0, (no_review, unchanged)) in
      match update with
      | Some update -> (try Res.Exposed.aim (Lazy.force res) (update) with _ -> do_nothing)
      | None        -> (do_nothing)
    in
    (* --- *)
    let details = {v0; v1; v2=None; review; status} in
    (* --- *)
    let ey = Either.protect (f ftcc details v0) v1 in
    (* --- *)
    (* Stabilizations and notifications are performed only for writers and maintainers.
       The following behaviour tries to be efficient: in case of a persistent structure
       (by default), if the internal resistance has not really changed we do nothing.
       The same (micro-)optimization cannot be applied to ephemeral (not persistent) structure,
       because for this kind of structures we cannot easily detect changes provoked by the `update'
       function (the 3th and 4th arguments of the body are the same object).
       *)
    let notify = if status_implies_notification (status) || (ephemeral<>None && level>0) then
        let res = (Lazy.force res) in
        let resid = (Res.Exposed.id res) in
        let () = DEBUGGING(Log.printf1 ~v:2 "Channel.access: about to decide stabilization for super structures of resistance #%d\n" (Res.Exposed.id res)) in
        let () = Stabilize.take_decision ~resid (FTCC.club_chain ftcc) in
        notify
      else
        let () = DEBUGGING(Log.printf ~v:2 "Channel.access: stabilizations and notifications are not required\n") in
        None
    in
    (* --- *)
    (* Notifications (broadcasts), if any, are performed now, once entered the critical section: *)
    let () =
      match leave with
      | None ->
          release ~level ?notify (ftcc)
      (* --- *)
      | Some leave ->
          let ok, v2 = require ~release_level:(level) ~wait_level:0 (* reader *) ?notify ~guard:(leave) (ftcc) in
          let notify = if ok then notify else None in
          let () = release ~level ?notify (ftcc) in
          let () = details.v2 <- Some v2 in
          ()
  in
  ey

end (* Meticulous *)

(* ---
   Two minor but pleasant changes:
   (1) the body ignores the first two arguments (FTTC.t and details), and
   (2) the exception, if any, is re-raised (outside the protected section)
       instead of to be stored in the result of type Either.t
   ---
   val access : ?level:int -> ?ephemeral:unit -> ?enter:('a->bool) -> ?notify:int list -> ?update:('a->'a) -> ?leave:('a->bool) -> ('a->'a->'b) -> 'a t -> 'b
   *)
let access ?level ?ephemeral ?enter ?notify ?update ?leave t f =
  Meticulous.access ?level ?ephemeral  ?enter ?notify ?update ?leave t (fun _ _ -> f) |> Either.extract_or_raise

(* Read-only specialization of `access', without update (and without ?level (reader) and ?notify (nobody)):
   val access_ro : ?enter:('a -> bool) -> ?leave:('a -> bool) -> 'a t -> ('a -> 'b) -> 'b *)
let access_ro ?enter ?leave t f =
  Meticulous.access ?enter ?leave t (fun _ _ _ -> f) |> Either.extract_or_raise

(* ------------------------ *)
(*           get            *)
(* ------------------------ *)

(* Slightly more efficient but equivalent to:
     ---
     access ~level:0 ?enter ?leave t (fun _ _ _ v1 -> v1) |> Either.extract_or_raise
     ---
     *)
let get ?enter ?leave t =
  let level = 0 (* reader *) in
  let ftcc, v0 = acquire ?guard:(enter) ~level t in
  (* --- *)
  let ev0 = Either.force v0 in
  (* --- *)
  match ev0 with
  | Either.Left e ->
      (* release and raise again the exception: *)
      let () = release ~level (ftcc) in
      raise e
  (* --- *)
  | Either.Right v0 -> (* continue: *)
  (* --- *)
  let () =
    match leave with
    | None -> release ~level (ftcc)
    (* --- *)
    | Some leave ->
        let _ok, _v2 = require ~release_level:(level) ~wait_level:0 (* reader *) ~guard:(leave) (ftcc) in
        release ~level (ftcc)
 in
 v0

(* ------------------------ *)
(*           aim            *)
(* ------------------------ *)

(* val aim : ?level:int (* 1 (writer) *) -> ?enter:('a -> bool) -> ?notify:int list -> ?leave:('a -> bool) -> 'a t -> ('a -> 'a) -> 'a * ('a details)
   Note that 1 is the minimum level for a writer: *)
let aim ?level ?enter ?notify ?leave t update (*: 'a*) =
  Meticulous.access ?level ?enter ?notify ~update ?leave t (fun _ d v0 v1 -> v1,d) |> Either.extract_or_raise

(* val set : ?level:int (* 1 (writer) *) -> ?enter:('a -> bool) -> ?notify:int list -> ?leave:('a -> bool) -> 'a t -> 'a -> unit
   Anachronistic and illusory ;-) *)
let set ?level ?enter ?notify ?leave t x =
  aim ?level ?enter ?notify ?leave t (fun _ -> x) |> ignore

(* --- Simplified versions of `aim' (all are protected except aim_extract): *)

(* val aim_succeed : 'a t -> ('a update) -> bool *)
let aim_succeed ?level ?enter ?notify ?leave t f =
  aim ?level ?enter ?notify ?leave t f |> (fun (_, d) -> Res.Review.to_bool d.review)

(* val aim_human : 'a t -> ('a update) -> 'a Review.h *)
let aim_human ?level ?enter ?notify ?leave t f =
  aim ?level ?enter ?notify ?leave t f |> (fun (_, d) -> Res.Review.human_readable d.review)

(* val aim_option : 'a t -> ('a update) -> 'a option *)
let aim_option ?level ?enter ?notify ?leave t f =
  aim ?level ?enter ?notify ?leave t f |> (fun (v2, details) ->
    (* let open Res.Review in *)
    match details.review with Error _ -> None (* v0 *) | _ -> Some v2
    )

(* ---------------------------- *)
(*      Method application      *)
(* ---------------------------- *)

(* Facilities: *)
let reader = 0
let writer = 1
let maintainer = 2

(* ---------------------------- *)
(*      Method construction     *)
(* ---------------------------- *)

module Method = struct

  type ('a,'b,'c) meth =
    { level     : int option;
      ephemeral : unit option;
      enter     : ('a -> bool) option;
      notify    : (int list) option;
      update    : ('a -> 'a) option;
      leave     : ('a -> bool) option;
      body      : ('a -> 'a -> 'b -> 'c);
      }

  (* val define :
       ?level:int (* 1 *) -> ?ephemeral:unit -> ?enter:('a->bool) -> ?notify:int list -> ?update:('a->'a) -> ?leave:('a->bool) -> ('a->'b->'c) -> ('a,'b,'c) meth *)
  let define ?level ?ephemeral ?enter ?notify ?update ?leave (body) = {level; ephemeral; enter; notify; update; leave; body; }

  (* val apply  : ('a,'b,'c) meth -> 'a t -> 'b -> 'c *)
  let apply {level; ephemeral; enter; notify; update; leave; body; } t b = access ?level ?ephemeral ?enter ?notify ?update ?leave t (fun v0 v1 -> body v0 v1 b)

  (* val product : ('a1,'b1,'c1) meth -> ('a2,'b2,'c2) meth -> ('a1*'a2, 'b1*'b2, 'c1*'c2) meth *)
  let product (m1: ('a1,'b1,'c1) meth) (m2: ('a2,'b2,'c2) meth) : ('a1*'a2, 'b1*'b2, 'c1*'c2) meth =
    (* --- *)
    let level     = Option.map_binop (max) (m1.level) (m2.level) in
    let ephemeral = Option.map_binop (max) (m1.ephemeral) (m2.ephemeral) in
    (* --- *)
    let combine_guards = function
    | None, None    -> None
    | None, Some g2 -> Some (fun (_,a2) -> g2 a2)
    | Some g1, None -> Some (fun (a1,_) -> g1 a1)
    | Some g1, Some g2 -> Some (fun (a1,a2) -> g1 a1 && g2 a2) (* lazy boolean conjunction *)
    in
    (* --- *)
    let combine_updates = function
    | None, None    -> None
    | None, Some g2 -> Some (fun (a1,a2) -> (a1, g2 a2))
    | Some g1, None -> Some (fun (a1,a2) -> (g1 a1, a2))
    | Some g1, Some g2 -> Some (fun (a1,a2) -> (g1 a1, g2 a2))
    in
    (* --- *)
    let enter = combine_guards (m1.enter, m2.enter) in
    (* --- *)
    let notify = (* union of broadcast levels: *)
     let f = fun xs ys -> List.sort_uniq (fun x y -> compare y x) (List.append xs ys) in
     Option.map_binop (f) (m1.notify) (m2.notify)
    in
    (* --- *)
    let update = combine_updates (m1.update, m2.update) in
    (* --- *)
    let leave = combine_guards (m1.leave, m2.leave) in
    (* --- *)
    let body (a1,a2) (a1',a2') (b1,b2) =
      let c1 = m1.body a1 a1' b1 in
      let c2 = m2.body a2 a2' b2 in
      (c1,c2)
    in
    (* --- *)
    {level; ephemeral; enter; notify; update; leave; body; }

end

(* ------------------------ *)
(*         Folding          *)
(* ------------------------ *)

(* Access as reader, without guards, to the several components of the disjunction (i.e. to the several files of the directory): *)
(* val fold : 'a t -> 's -> ('s -> 'a lazy_t -> 's) -> 's *)
let fold (t) (s0) (f:'s -> 'a lazy_t -> 's) : 's =
  (* --- *)
  (* The accumalating function is automatically protected:
     if an exception is raised, the function behaves as the identity. *)
  let apply_f s w = try f s (lazy (FTCC.get w)) with _ -> s in
  (* --- *)
  let rec loop ((FTCC_dir.Dir (ws, cts)): 'a t) (s0) : 's =
    let n = Array.length ws in
    (* --- *)
    let s1 : 's =
      if n=0 then s0 else (* continue with n>0: *)
      if n=1 then (apply_f s0 ws.(0))
      else (* n>1 *)
        (Array.fold_left (apply_f) s0 ws)
    in
    (* Now continue looking into subdirectories: *)
    (* --- *)
    let pushdir (s1) (c,t) : 's =
      let () = Club.acquire ~level:(reader) c in
      (* Go in depth: *)
      let s2 = loop t s1 in
      (* Return: *)
      let () = Club.Protected.release ~level:(reader) c in
      s2
    in
    (* --- *)
    let d = Array.length cts in (* number of directories *)
    if d=0 then s1 else (* continue with d>0: *)
    (* --- *)
    if d=1 then pushdir s1 cts.(0) else (* continue with d>1: *)
    (* --- *)
    (Array.fold_left pushdir s1 cts)
    (* --- *)
  in (* loop *)
  (* --- *)
  loop t s0

(* Instances of fold: *)

(* val exists :  'a t -> ('a -> bool) -> bool *)
let exists t p = fold t (false) (fun s x -> s || p (Lazy.force x))

(* val for_all : 'a t -> ('a -> bool) -> -> bool *)
let for_all t p = fold t (true) (fun s x -> s && p (Lazy.force x))

(* val find : 'a t -> ('a -> bool) -> 'a option *)
let find t p = fold t (None) (fun s x ->
  if s <> None then s else (* continue: *)
  let x = (Lazy.force x) in
  if p x then Some x else None
  )

(* ------------------------ *)
(*         Folding          *)
(*     during ownership     *)
(* ------------------------ *)

(* The same visit but dealing with an already acquired conjunction: *)
let fold_with_acquired_clubs ?(level=reader) (club_set: Club_set.t) (t) (s0) (f:'s -> 'a lazy_t -> 's) : 's =
  (* --- *)
  (* The accumalating function is automatically protected:
     if an exception is raised, the function behaves as the identity. *)
  let apply_f s w = try f s (lazy (FTCC.get w)) with _ -> s in
  (* --- *)
  let rec loop ((FTCC_dir.Dir (ws, cts)): 'a t) (s0) : 's =
    let n = Array.length ws in
    (* --- *)
    let s1 : 's =
      if n=0 then s0 else (* continue with n>0: *)
      if n=1 then (apply_f s0 ws.(0))
      else (* n>1 *)
        (Array.fold_left (apply_f) s0 ws)
    in
    (* Now continue looking into subdirectories: *)
    (* --- *)
    let pushdir (s1) (c,t) : 's =
      if Club_set.mem (c) (club_set) then (* Go in depth: *) (loop t s1) else
      (* The same but with acquire/release: *)
      (* --- *)
      let () = Club.acquire ~level c in
      (* Go in depth: *)
      let s2 = loop t s1 in
      (* Return: *)
      let () = Club.Protected.release ~level c in
      s2
    in
    (* --- *)
    let d = Array.length cts in (* number of directories *)
    if d=0 then s1 else (* continue with d>0: *)
    (* --- *)
    if d=1 then pushdir s1 cts.(0) else (* continue with d>1: *)
    (* --- *)
    (Array.fold_left pushdir s1 cts)
    (* --- *)
  in (* loop *)
  (* --- *)
  loop t s0

(* ---------------------------- *)
(*    Non-determinism control   *)
(* ---------------------------- *)

module Control = struct

  (* All tools here return the following result, which can be:
     (1) an exception, or
     (2) the value 'b returned by the applied function, combined with the actually acquired channel in case of disjunction.
     Applying these tools to disjunctions (many "files" stored in the "directory"), we are able to acquire again exactly the
     same structure acquired the first time, and continue the work on it. *)
  type ('a,'b) result = (exn, 'b * ('a t lazy_t)) Either.t

  let access ?level ?ephemeral ?enter ?notify ?update ?leave t f =
    Meticulous.access ?level ?ephemeral ?enter ?notify ?update ?leave t (fun ftcc _details x0 x1 ->
      let y1 = (f x0 x1) in
      let y2 = lazy (rebuild ftcc) in
      (y1, y2)
      )

  let access_with_fold ?level ?ephemeral ?enter ?notify ?update ?leave t (s0: 's) (acc:'s -> 'a lazy_t -> 's) (f:'a -> 'a -> 's -> 'b) : ('a,'b) result =
    (* --- *)
    Meticulous.access ?level ?ephemeral ?enter ?notify ?update ?leave t (fun ftcc _details x0 x1 ->
      let club_set = Club_set.of_list (FTCC.club_chain ftcc) in
      (* The folding is performed as reader: *)
      let s1 = fold_with_acquired_clubs (**) ~level:(reader) (**) (club_set) (t) (s0) (acc) in
      (* Apply now the function: *)
      (f x0 x1 s1, lazy (rebuild ftcc))
      )

  let access_with_test_for_all ?level ?ephemeral ?enter ?notify ?update ?leave t (p: 'a -> bool) (f:'a -> 'a -> bool -> 'b) =
    access_with_fold ?level ?ephemeral ?enter ?notify ?update ?leave t (true) (fun s x -> s && p (Lazy.force x)) f

  let access_with_test_exists ?level ?ephemeral ?enter ?notify ?update ?leave t (p: 'a -> bool) (f:'a -> 'a -> bool -> 'b) =
    access_with_fold ?level ?ephemeral ?enter ?notify ?update ?leave t (false) (fun s x -> s || p (Lazy.force x)) f

  let access_with_find ?level ?ephemeral ?enter ?notify ?update ?leave t (p: 'a -> bool) (f:'a -> 'a -> 'a option -> 'b) =
    access_with_fold ?level ?ephemeral ?enter ?notify ?leave t (None) (fun s x ->
      if s <> None then s else (* continue: *)
      let x = (Lazy.force x) in
      if p x then Some x else None
      )
      (f)

end (* Control *)

(* ---------------------------- *)
(*       Debugging/testing      *)
(* ---------------------------- *)

(* val print_active_bindings : unit -> unit *)
let print_active_bindings () =
  let cjs = (Conjunction.Book.stats_alive ()).Hashtbl.num_bindings in
  let ccs = (Club_chain_book.stats_alive ()).Hashtbl.num_bindings in
  let cus = (Club2UC_book.stats_alive ()).Hashtbl.num_bindings in
  Misc.pr "Conjunctions: %d  Club-chains: %d  Club-related-to-unstable-conj: %d\n" cjs ccs cus


module Help = struct

let access () = Misc.pr
"---
val Meticulous.access :
  ?level:int ->                    (* 1 *)
  ?ephemeral:unit ->               (* None, by default structures are considered as persistent *)
  ?enter:('a -> bool) ->           (* None *)
  ?notify:int list ->              (* according to the level: 0 ⊢> [], 1 ⊢> [1;0], 2 ⊢> [2;1;0] *)
  ?update:('a -> 'a) ->            (* None *)
  ?leave:('a -> bool) ->           (* None *)
  'a t ->                          (* the channel *)
  (* The third and forth arguments of the body are the previous and current encapsulated value: *)
  ('a FTCC.t -> 'a details -> 'a -> 'a -> 'b) -> (exn, 'b) Either.t

where:

type 'a details = { v0:'a;  v1:'a;  mutable v2:'a;  review:'a review;  status:status; }
 and 'a review  = ('a option, exn) result  (* Error(exn) | Ok(None) | Ok(Some v) *)
 and  status    = (bool * bool lazy_t)     (* v2==v0, lazy (v2=v0) *)
---
General and meticulous access to the channel (dealing with resistances and acquired conjunctions).
The goal is to execute a function (method) in a protected section, i.e. exclusively.
---
Given the initial encapsulated value v0:'a of the channel, the optional argument `update', if any,
is used to update v0 into v1, according to a possible internal resistance. After this step,
the body takes (1) the acquired conjunction (among a possible disjunction), (2) the details of the
resistance process, and (3) the current up-to-date value v1:'a and starts a computation to provide
the result in 'b.
About exceptions:
  - if an exception is raised during the update, it is silently ignored (but appears in the details),
    and we continue with the body applied to v1=v0
  - if an exception is raised during the body execution, it is reported in the result
    of type (exn, 'b) Either.t
---
Note about the mutability of details.v2: the field v2 is mutable in order to
provide to the user the possibility to control the changes occurred after the
optional guard `leave'. Indeed, if the user is interested by details, it can
simply program the body ('a FTCC.t -> 'a details -> 'a -> 'a -> 'b)
including the details into the result of type 'b.

---
Simplified method:
---
val access :
  ?level:int ->
  ?ephemeral:unit ->
  ?enter:('a -> bool) ->
  ?notify:int list ->
  ?update:('a -> 'a) ->
  ?leave:('a -> bool) ->
  'a t -> ('a -> 'a -> 'b) -> 'b
---
There are two minor but pleasant changes:
(1) the body ignores the first two arguments (FTTC.t and details), and
(2) the exception, if any, is re-raised (outside the protected section)
    instead of to be stored in the result of type Either.t
"
;;


let review () = Misc.pr
"---
type 'a review  = ('a option, exn) result
---
A review is more than the boolean result of the indicator function of a set.
It express, of course, the boolean case \"accepted\"/\"rejected\", but, when the
value is accepted, it may express the revision that has been applied to the
value to render it acceptable. Hence, review belongs one of three cases:
---
  Error (exn)  =>  false, i.e. \"rejected\" with comments in exn
  Ok None      =>  true, \"accepted\" as is
  Ok Some v    =>  true, accepted but \"revised\" to v
---
"
;;

end (* Help *)

(* ---------------------------- *)
(* Integer protected resistance *)
(* ---------------------------- *)

let incr t = aim t (fun v -> v+1) |> (fun (_, details) -> Res.Review.to_bool details.review)
let decr t = aim t (fun v -> v-1) |> (fun (_, details) -> Res.Review.to_bool details.review)

(* ---------------------------- *)
(*          Toolkit             *)
(* ---------------------------- *)

(** Just for fun: opening this module you redefine the standard [ref], [!] and [:=]
    in order to operate on this kind of structure instead of standard references. *)
module Toolkit = struct

  let ref ?reviewer v = create ?reviewer v
  let (!) t = get t
  let (:=) t v = set t v

  let incr t = aim t (fun v -> v+1) |> ignore
  let decr t = aim t (fun v -> v-1) |> ignore

  let ppi t = aim t (fun v -> v+1) |> (fun (v1, details) -> v1)          (* ++i *)
  let ipp t = aim t (fun v -> v+1) |> (fun (v1, details) -> details.v0)  (* i++ *)

  let mmi t = aim t (fun v -> v-1) |> (fun (v1, details) -> v1)          (* --i *)
  let imm t = aim t (fun v -> v-1) |> (fun (v1, details) -> details.v0)  (* i-- *)

end

(* ------------------------ *)
(*     Last definitions     *)
(* ------------------------ *)

(* To be moved at the end of the file: *)
let fst xy = fst_prj ?reviewer:None xy
let snd xy = snd_prj ?reviewer:None xy
