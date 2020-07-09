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

IFNDEF OCAML4_03_OR_LATER THEN
type ('a, 'b) result = Ok of 'a | Error of 'b
ENDIF

module Club = Lock_clubs.RWM_levels
type waiting_room = Lock_clubs.waiting_room

(* ------------------------------ *)
(* Control of exposed resistances *)
(* ------------------------------ *)

type status  = (bool * bool lazy_t)
 and control = commits_no * status (* should be called "detailed status" *)
 and commits_no = int

(* ------------------------------ *)
(*  Generic signature of "books"  *)
(*    storing alive structures    *)
(* ------------------------------ *)

(* For testing/debugging: *)
module type BOOK = sig
  val stats_alive    : unit -> Hashtbl.statistics
  val clean          : unit -> unit
  val alarm          : Gc.alarm lazy_t
  val get_orphan_ids : ?clean:unit -> unit -> int list
end

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
    (* --- For testing/debugging: *)
    val stats_alive : unit -> Hashtbl.statistics
    val clean       : unit -> unit
    val alarm       : Gc.alarm lazy_t
  end

(* ------------------------------ *)
(*             Book               *)
(*  club ⊢> unstable-conjunction  *)
(* ------------------------------ *)

(* Book of unstable conjunctions indexed by clubs (club -> unstable-conjunction): *)
module Club2UC_book :
  sig
    type uc = { cc: Club_chain_book.t; resid: int; get_commits_no: (unit->int); force_commit: (unit->control); }
    (* --- For testing/debugging: *)
    val clean       : unit -> unit
    val stats_alive : unit -> Hashtbl.statistics
    val alarm       : Gc.alarm lazy_t
  end

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
     (* --- *)
     val stairs_lengths : ('a,'x) t -> int array
     (* --- *)
     val of_unstable_conjunctions : Club2UC_book.uc list -> (Club.t, file) t
     val of_club : Club.t -> (Club.t, file) t
     val take_decision : resid:int -> Club_chain_book.t -> unit
     (* --- *)
  end

(* ------------------------ *)
(*       Conjunction        *)
(*   (atoms of genealogy)   *)
(* ------------------------ *)

(* A conjunction is a triple (club-chain, waiting-room, resistance): the club-chain represents
   the "protection" (the set of locks) for the resistance, while the waiting-room simply allows
   a thread to wait for an event about the conjunction. A conjunction is said "unstable" if its
   resistance has a reviewer, i.e. an associated reviewing process that may change the state of
   its components as soon as a thread will attempt an access, even in read-only mode. *)
module Conjunction :
  sig
    type 'a t = { cc: Club_chain_book.t; wr: waiting_room; res: 'a Res.Exposed.t; }
    val get     : 'a t -> 'a
    val map     : ?equality:('a -> 'a -> bool) -> ('a -> 'b) -> 'a t -> 'b t
    val return  : ?reviewer:('a -> 'a -> 'a Res.review) -> 'a -> 'a t
    val product : ?reviewer:('a * 'b) Res.reviewer -> 'a t -> 'b t -> ('a * 'b) t
    val split   : ?fst_reviewer:'a Res.reviewer ->  ?snd_reviewer:'b Res.reviewer -> ('a * 'b) t -> 'a t * 'b t
    val fst_prj : ?reviewer:'a Res.reviewer -> ('a * 'b) t -> 'a t
    val snd_prj : ?reviewer:'a Res.reviewer -> ('b * 'a) t -> 'a t
    val cover   : 'a t -> ('a -> 'a -> 'a Res.review) -> 'a t
    val compare : 'a t -> 'a t -> int
    (* --- *)
    module Book : BOOK
  end

(* ---------------------------- *)
(*   FTC_conjunction or FTCC    *)
(*           (files)            *)
(* ---------------------------- *)

(* "FTC_conjunction" stands for (F)amily (T)ree (C)losed conjunction (abreviated in "FTCC").
   Morally, it's a conjunction that preserves the history of its proper building,
   i.e. the genealogy of free products which have generated the information stored
   at the root level. *)
module FTCC :
  sig

  (* The genealogy of conjunctions *)
  module Genealogy :
    sig
      type _ t =
        | Atom : 'a Conjunction.t -> 'a t
        | Cons : ('a * 'b) Conjunction.t * ('a t * 'b t) -> ('a * 'b) t
      (* --- *)
      val atom      : 'a Conjunction.t -> 'a t
      val cons      : ('a * 'b) Conjunction.t -> 'a t -> 'b t -> ('a * 'b) t
      val root      : 'a t -> 'a Conjunction.t
      val is_atom   : 'a t -> bool
      val is_cons   : 'a t -> bool
      val car       : ('a * 'b) t -> 'a t
      val cdr       : ('a * 'b) t -> 'b t
      val decons    : ('a * 'b) t -> ('a * 'b) Conjunction.t * ('a t * 'b t)
      (* --- *)
      val product   : 'a t -> 'b t -> ('a * 'b) t
      val fst       : ('a * 'b) t -> 'a t
      val snd       : ('a * 'b) t -> 'b t
      val split     : ('a * 'b) t -> 'a t * 'b t
      val combine   : 'a t -> 'b t -> ('a * 'b) t
      val unzip     : ('a * 'b) t -> 'a t * 'b t
      val zip       : 'a t * 'b t -> ('a * 'b) t
    end

    (* Main type: *)
    type 'a t = 'a Genealogy.t (* i.e. a conjunction with its genealogy *)
    (* --- *)
    val return       : ?reviewer:('a -> 'a -> 'a Res.review) -> 'a -> 'a t
    (* --- *)
    val club_chain   : 'a t -> Club_chain_book.t
    val waiting_room : 'a t -> waiting_room
    val resistance   : 'a t -> 'a Res.Exposed.t
    val get          : 'a t -> 'a
    (* --- *)
    val product      : ?reviewer:('a * 'b) Res.reviewer -> 'a t -> 'b t -> ('a * 'b) t
    val cover        : 'a t -> ('a -> 'a -> 'a Res.review) -> 'a t
    val map          : ('a -> 'b) -> 'a t -> 'b t
    val fst_prj      : ?reviewer:'a Res.reviewer -> ('a * 'b) t -> 'a t
    val snd_prj      : ?reviewer:'b Res.reviewer -> ('a * 'b) t -> 'b t
    val split        : ?fst_reviewer:'a Res.reviewer -> ?snd_reviewer:'b Res.reviewer -> ('a * 'b) t -> 'a t * 'b t
    val unzip        : ('a * 'b) t -> 'a t * 'b t
    val zip          : 'a t * 'b t -> ('a * 'b) t
    val fst          : ('a * 'b) t -> 'a t
    val snd          : ('a * 'b) t -> 'b t
    val compare      : 'a t -> 'a t -> int
  end

(* ---------------------------------- *)
(*             FTCC_dir               *)
(*  (tree structured FTTC's choices)  *)
(* ---------------------------------- *)

module FTCC_dir :
  sig
    type ('a, 'x) t = Dir of 'x FTCC.t array * (Club.t * ('a, 'x) t) array
    (* --- *)
    val return     : Club.t -> 'x FTCC.t -> ('a, 'x) t
    val prepend    : Club.t -> ('a, 'x) t -> ('a, 'x) t
    (* --- *)
    val files      : ('a, 'x) t -> 'x FTCC.t array
    val subdirs    : ('a, 'x) t -> (Club.t * ('a, 'x) t) array
    (* --- *)
    val all_files  : ('a, 'x) t -> 'x FTCC.t array
    val all_stairs : ('a, 'x) t -> Club.t array
    (* --- *)
    val stairs_lengths : ('a,'x) t -> int array
    (* --- *)
    val map_files  : ('x FTCC.t -> 'y FTCC.t) -> ('a, 'x) t -> ('a, 'y) t
    val map_file_contents : ('x -> 'y) -> ('a, 'x) t -> ('a, 'y) t
    (* --- *)
    val zero       : ('a, 'x) t
    val plus       : ('a, 'x) t -> ('a, 'x) t -> ('a, 'x) t
    val array_sum  : ('a, 'x) t array -> ('a, 'x) t
    val list_sum   : ('a, 'x) t list -> ('a, 'x) t
    val choose     : ('a,'x) t -> ('x FTCC.t) option
    (* --- *)
    val times      : ?file_zip  :('x FTCC.t * 'y FTCC.t -> ('x * 'y) FTCC.t) -> ('a,'x) t -> ('a,'y) t -> ('a, 'x * 'y) t
    val split      : ?file_unzip:(('x * 'y) FTCC.t -> 'x FTCC.t * 'y FTCC.t) -> ('a, 'x * 'y) t -> ('a,'x) t * ('a,'y) t
    val fst        : ?file_fst  :(('x * 'y) FTCC.t -> 'x FTCC.t) -> ('a, 'x * 'y) t -> ('a, 'x) t
    val snd        : ?file_snd  :(('x * 'y) FTCC.t -> 'y FTCC.t) -> ('a, 'x * 'y) t -> ('a, 'y) t
  end

(* -------------------------- *)
(*         Channel            *)
(* -------------------------- *)

type 'a review   = ('a option, exn) result
type 'a reviewer = 'a -> 'a -> 'a review

(* type 'a t = Dir of 'a FTCC.t array * (Club.t * 'a t) array *)
type 'a t = (Club.t, 'a) FTCC_dir.t

val create    : ?reviewer:('a -> 'a -> 'a review) -> 'a -> 'a t
val cover     : 'a t -> ('a -> 'a -> 'a review) -> 'a t
(* --- *)
val map       : ('a -> 'b) -> 'a t -> 'b t
val rebuild   : 'a FTCC.t -> 'a t
(* --- *)
val split     : ?fst_reviewer:'a reviewer -> ?snd_reviewer:'b reviewer -> ('a * 'b) t -> 'a t * 'b t
val fst_prj   : ?reviewer:'a reviewer -> ('a * 'b) t -> 'a t
val snd_prj   : ?reviewer:'b reviewer -> ('a * 'b) t -> 'b t
val product   : ?reviewer:('a * 'b -> 'a * 'b -> ('a * 'b) review) -> 'a t -> 'b t -> ('a * 'b) t
(* --- *)
val zero      : 'a t
val plus      : 'a t -> 'a t -> 'a t
val array_sum : ('a t) array -> 'a t
val list_sum  : ('a t) list  -> 'a t
(* --- *)
(* Simplified tools (without reviewer): *)
val times     : 'a t -> 'b t -> ('a * 'b) t
val zip       : 'a t * 'b t -> ('a * 'b) t (* uncurried `times' *)
val unzip     : ('a * 'b) t -> 'a t * 'b t
val fst       : ('a * 'b) t -> 'a t
val snd       : ('a * 'b) t -> 'b t

val lengths : 'a t -> int array

(* ----------------------------------- *)
(*          Acquire/Release            *)
(* (do something in protected section) *)
(* ----------------------------------- *)

(* Notifications (?notify) are set by default according to the level of access,
   i.e.  0 ⊢> [],  1 ⊢> [1;0],  2 ⊢> [2;1;0] *)
val notify_defaults : (int list) array (* [|[]; [1; 0]; [2; 1; 0]|] *)

(* Execute the method ('a -> 'b) in the protected section of channel, i.e in exclusivity on the channel.
   This method may be the simplest to use when the structure ('a t) has a "core" (of type 'a) which is
   mutable without any control (no reviewer, i.e. no resistance). In this case, the function ('a -> 'b),
   called in the protected section, may also change the internal state of the core before to provide the
   result of type 'b.
   Note that this genericity leads to non-optimal behaviour, even if the loss in performance is not very
   serious. Indeed, the notification's levels are set by caller, or set by default, and notifications
   happen independently from the real change of core's state. So, some threads may be unnecessarily wake-up
   believing to find a new state. For a more refined behavior, you will have to use `aim' or a derivative
   tool like `apply_method'.
   *)
(* val with_acquire : ?level:int -> ?enter:('a -> bool) -> ?notify:int list -> ?leave:('a -> bool) -> 'a t -> ('a -> 'b) -> (exn, 'b) Either.t *)

(* ----------------------------------- *)
(*               Access                *)
(*          (Acquire-Release)          *)
(* ----------------------------------- *)

type 'a details = { v0: 'a; v1: 'a; mutable v2: 'a option; review: 'a review; status: status; }
(* --- *)

(* General and meticulous access to the channel (dealing with resistances and acquired conjunctions).
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
*)
module Meticulous : sig
  (* --- *)
  val access :
    ?level:int -> ?ephemeral:unit -> ?enter:('a -> bool) -> ?notify:int list -> ?update:('a -> 'a) -> ?leave:('a -> bool) ->
    'a t -> ('a FTCC.t -> 'a details -> 'a -> 'a -> 'b) -> (exn, 'b) Either.t
  (* --- *)
end (* Meticulous *)

(* Two minor but pleasant changes:
   (1) the body ignores the first two arguments (FTTC.t and details), and
   (2) the exception, if any, is re-raised (outside the protected section)
       instead of to be stored in the result of type Either.t *)
val access :
   ?level:int -> ?ephemeral:unit -> ?enter:('a -> bool) -> ?notify:int list -> ?update:('a -> 'a) -> ?leave:('a -> bool) ->
  'a t -> ('a -> 'a -> 'b) -> 'b

(* Read-only specialization of `access', without update (and without ?level (reader) and ?notify (nobody)): *)
val access_ro : ?enter:('a -> bool) -> ?leave:('a -> bool) -> 'a t -> ('a -> 'b) -> 'b

(* ------------------------ *)
(*     Other convenient     *)
(*      instances of        *)
(*    Meticulous.access     *)
(* ------------------------ *)

val get : ?enter:('a -> bool) -> ?leave:('a -> bool) -> 'a t -> 'a (* level is 0 *)
val aim : ?level:int (* 1 *)  -> ?enter:('a -> bool) -> ?notify:int list -> ?leave:('a -> bool) -> 'a t -> ('a -> 'a) -> 'a * ('a details)
val set : ?level:int (* 1 *)  -> ?enter:('a -> bool) -> ?notify:int list -> ?leave:('a -> bool) -> 'a t -> 'a -> unit (* aim |> ignore *)

(* The following methods are similar to `aim' but with a simplified result.
   In particular, `aim_option' returns None if the provided transition has failed,
   otherwise it returns the value resulting from the last read, that is the first component of the `aim' result. *)
val aim_succeed : ?level:int (* 1 *) -> ?enter:('a -> bool) -> ?notify:int list -> ?leave:('a -> bool) -> 'a t -> ('a -> 'a) -> bool
val aim_option  : ?level:int (* 1 *) -> ?enter:('a -> bool) -> ?notify:int list -> ?leave:('a -> bool) -> 'a t -> ('a -> 'a) -> 'a option
val aim_human   : ?level:int (* 1 *) -> ?enter:('a -> bool) -> ?notify:int list -> ?leave:('a -> bool) -> 'a t -> ('a -> 'a) -> 'a Res.Review.h
(* --- *)

(* ---------------------------- *)
(*    Facilities/readability    *)
(* ---------------------------- *)

val reader     : int (* 0 *)
val writer     : int (* 1 *)
val maintainer : int (* 2 *)

(* ---------------------------- *)
(*          Access              *)
(*  (as method application)     *)
(* ---------------------------- *)

module Method : sig
  type ('a,'b,'c) meth
  (* --- *)
  val define :
    ?level:int (*1*) -> ?ephemeral:unit -> ?enter:('a->bool) -> ?notify:int list -> ?update:('a->'a) -> ?leave:('a->bool) ->
    ('a->'a->'b->'c) -> ('a,'b,'c) meth
  (* --- *)
  val apply  : ('a,'b,'c) meth -> 'a t -> 'b -> 'c
  (* --- *)
  val product : ('a1,'b1,'c1) meth -> ('a2,'b2,'c2) meth -> ('a1*'a2, 'b1*'b2, 'c1*'c2) meth
end

(* ------------------------ *)
(*     Access by reader     *)
(*  to the whole directory  *)
(* ------------------------ *)

(* Access as reader, without guards, to the several components of the disjunction (i.e. to the several files of the directory): *)
val fold : 'a t -> 's -> ('s -> 'a lazy_t -> 's) -> 's

(* Instances of `fold': *)
val exists  : 'a t -> ('a -> bool) -> bool
val for_all : 'a t -> ('a -> bool) -> bool
val find    : 'a t -> ('a -> bool) -> 'a option

(* -------------------------------- *)
(*      Non-determinism control     *)
(*               i.e.               *)
(*   a writer access combined with  *)
(*      a reader access (fold)      *)
(*      to the whole directory      *)
(* -------------------------------- *)

(* Control the non-determinism (+): *)
module Control : sig

  (* All tools here return the following result, which can be:
     (1) an exception, or
     (2) the value 'b returned by the applied function, combined with the actually acquired channel in case of disjunction.
     Applying these tools to disjunctions (many "files" stored in the "directory"), we are able to acquire again exactly the
     same structure acquired the first time, and continue the work on it. *)
  type ('a,'b) result = (exn, 'b * ('a t lazy_t)) Either.t

  val access :
      ?level:int -> ?ephemeral:unit -> ?enter:('a -> bool) -> ?notify:int list -> ?update:('a -> 'a) -> ?leave:('a -> bool) ->
      'a t -> ('a -> 'a -> 'b) -> ('a,'b) result

  (* In the following tools the folding is done as reader,
     even if the level specified to acquire the conjunction is higher: *)

  val access_with_fold :
      ?level:int -> ?ephemeral:unit -> ?enter:('a -> bool) -> ?notify:int list -> ?update:('a -> 'a) -> ?leave:('a -> bool) ->
      'a t -> 's -> ('s -> 'a lazy_t -> 's) -> ('a -> 'a -> 's -> 'b) -> ('a,'b) result

  val access_with_test_for_all :
      ?level:int -> ?ephemeral:unit -> ?enter:('a -> bool) -> ?notify:int list -> ?update:('a -> 'a) -> ?leave:('a -> bool) ->
      'a t -> ('a -> bool) -> ('a -> 'a -> bool -> 'b) -> ('a,'b) result

  val access_with_test_exists :
      ?level:int -> ?ephemeral:unit -> ?enter:('a -> bool) -> ?notify:int list -> ?update:('a -> 'a) -> ?leave:('a -> bool) ->
      'a t -> ('a -> bool) -> ('a -> 'a -> bool -> 'b) -> ('a,'b) result

  val access_with_find :
      ?level:int -> ?ephemeral:unit -> ?enter:('a -> bool) -> ?notify:int list -> ?update:('a -> 'a) -> ?leave:('a -> bool) ->
      'a t -> ('a -> bool) -> ('a -> 'a -> 'a option -> 'b) -> ('a,'b) result

end (* Control *)


(* ---------------------------- *)
(*       Debugging/testing      *)
(* ---------------------------- *)

val print_active_bindings : unit -> unit

(* Print help on some tools on stderr: *)
module Help : sig
  val access : unit -> unit
  val review : unit -> unit
end

(* ---------------------------- *)
(* Integer protected resistance *)
(* ---------------------------- *)

(* Just for fun. Note that these functions may fail and this failure is represented
   by `false' (because of the resistance's reviewer, i.e. the indicator function): *)
val incr : int t -> bool
val decr : int t -> bool

(* ---------------------------- *)
(*          Toolkit             *)
(* ---------------------------- *)

(** Just for fun: opening this module you redefine the standard [ref], [!] and [:=]
    in order to operate on this kind of structure instead of standard references. *)
module Toolkit :
  sig
    val ref : ?reviewer:('a reviewer) -> 'a -> 'a t
    val ( ! )  : 'a t -> 'a
    val ( := ) : 'a t -> 'a -> unit
    val incr   : int t -> unit  (* ignore result *)
    val decr   : int t -> unit  (* ignore result *)
    val ppi    : int t -> int   (* ++i *)
    val ipp    : int t -> int   (* i++ *)
    val mmi    : int t -> int   (* --i *)
    val imm    : int t -> int   (* i-- *)
  end

(* ---------------------------- *)
(*          Examples            *)
(* ---------------------------- *)

(*

(* In channels ('a option) overwrites are forbidden because the message must be received before leaving place for the next one: *)
let forbid_overwrite v0 v1 =
  match (v0,v1) with
  | Some x0, Some x1 when x0 <> x1 -> Res.rejected ~comment:"overwrite forbidden" ()
  | _, _ -> Res.accepted ()
;;
(* val forbid_overwrite : 'a option -> 'a option -> 'b review *)

(* No more than 100, odd integers patched to the next even: *)
let accept_even_le_100 = fun _ v -> if v>100 then Res.rejected ~comment:">100" () else if (v mod 2 = 0) then Res.accepted () else Res.revised (v+1) ;;
(* val accept_even_le_100 : 'a -> int -> int review *)

(* No more than 100, even integers patched to the next odd: *)
let accept_odd_le_100 = fun _ v -> if v>100 then Res.rejected ~comment:">100" () else if (v mod 2 = 1) then Res.accepted () else Res.revised (v+1) ;;

let rx = Res.Reviewer.compose (forbid_overwrite) (Res.Reviewer.option_lift_snd accept_even_le_100) ;;
(* val rx : int option Res.Reviewer.t *)

let ry = Res.Reviewer.compose (forbid_overwrite) (Res.Reviewer.option_lift_snd accept_odd_le_100) ;;
(* val ry : int option Res.Reviewer.t *)

let x = Channel.create ~reviewer:(rx) None ;;
(* val x : int option Channel.t *)

Channel.Club_chain_book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 1; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|15; 1|]} *)

let y = Channel.create ~reviewer:(ry) None ;;
(* val y : int option Channel.t *)

Channel.Club_chain_book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 2; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|14; 2|]} *)

Channel.aim_human x (fun _ -> Some 10);;
(*
[2743697.0]: Lock: ACQUIRED CLUB #200 at level 1
[2743697.0]: Channel.aim: about to decide stabilization for super structures of resistance #202
[2743697.0]: Channel.Club2UC_book.find: about to find unstable resistances involved by club #200 (#wt=0, member=false)
[2743697.0]: Channel.Stabilize.take_decision: NEEDLESS for resistance #202
[2743697.0]: Lock: RELEASED CLUB #200 at level 1
- : int option Res.Review.h = `Accepted
*)

let xy = Channel.product x y ;;
(* val xy : (int option * int option) Channel.t *)

Channel.get xy ;;
(* - : int option * int option = (Some 10, None) *)

Channel.Conjunction.Book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 3; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|13; 3|]} *)

Channel.Club_chain_book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 3; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|13; 3|]} *)

let xy2 = Channel.product x y ;;
(* val xy2 : (int option * int option) Channel.t *)

Channel.Conjunction.Book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 4; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|12; 4|]} *)

Channel.Club_chain_book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 3; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|13; 3|]} *)

let xy, xy2 = ("old xy may be collected", "old xy2 may be collected") ;;
(* val xy  : string = "old xy may be collected"
   val xy2 : string = "old xy2 may be collected" *)

Gc.full_major () ;;
(*
[2844715.0]: Channel.Club_chain_book:  weak hash table CLEANED (removed 0 elements)
[2844715.0]: Channel.Conjunction: weak hash table CLEANED (removed 0 elements)
- : unit = ()
*)

Gc.full_major () ;;
(*
[2844715.0]: Channel.Conjunction: weak hash table CLEANED (removed 2 elements)
[2844715.0]: Channel.Club_chain_book:  weak hash table CLEANED (removed 1 elements)
*)

Channel.Club_chain_book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 2; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|14; 2|]} *)

Channel.Conjunction.Book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 2; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|14; 2|]} *)

(* --- *)

Channel.Club2UC_book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 0; num_buckets = 16; max_bucket_length = 0; bucket_histogram = [|16|]} *)

let xy2 = Channel.product ~reviewer:(fun _ _ -> Res.accepted ()) x y ;;
(*
[2844715.0]: Channel.Club2UC_book.register: REGISTERING COMMITTER for resistance #230 (#clubs=2)
[2844715.0]: Channel.Conjunction: register: REGISTERING structure #230 (GC-alarm: true)
val xy2 : (int option * int option) Channel.t =
*)

Channel.Conjunction.Book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 3; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|13; 3|]} *)

Channel.Club2UC_book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 2; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|14; 2|]} *)

let xy2 = "old xy2 may be collected" ;;

Gc.full_major () ;;
(*
[2844715.0]: Channel.Club2UC_book: weak hash table CLEANED (removed 0 elements)
[2844715.0]: Channel.Club_chain_book:  weak hash table CLEANED (removed 0 elements)
[2844715.0]: Channel.Conjunction: weak hash table CLEANED (removed 0 elements)
- : unit = () *)

Gc.full_major () ;;
(*
[2844715.0]: Channel.Club2UC_book: weak hash table CLEANED (removed 1 elements)
[2844715.0]: Channel.Club_chain_book:  weak hash table CLEANED (removed 0 elements)
[2844715.0]: Channel.Conjunction: weak hash table CLEANED (removed 0 elements)
- : unit = () *)

Gc.full_major () ;;
(*
[2844715.0]: Channel.Club2UC_book: weak hash table CLEANED (removed 0 elements)
[2844715.0]: Channel.Club_chain_book:  weak hash table CLEANED (removed 1 elements)
[2844715.0]: Channel.Conjunction: weak hash table CLEANED (removed 0 elements)
- : unit = () *)

Channel.Club_chain_book.stats_alive () ;;
(* Here num_bindings should be 2, but the next Gc.full_major all should be clean: *)
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 3; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|13; 3|]} *)

Channel.Club2UC_book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 0; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|14; 2|]} *)

Channel.Conjunction.Book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 2; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|14; 2|]} *)

Gc.full_major () ;;
(* It's ok now: *)
Channel.Club_chain_book.stats_alive () ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 2; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|14; 2|]} *)

(* --- *)

Ocamlbricks_log.enable ~level:2 () ;;
(* - : unit = () *)

Channel.aim_human x (fun _ -> Some 10);;
(*
[2743697.0]: Lock.Readers_writer: acquire_guards: L1-READER AT L1 ACQUIRED (action n°1)
[2743697.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2743697.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2743697.0]: Lock: ACQUIRED CLUB #200 at level 1
[2743697.0]: Channel.aim: about to decide stabilization for super structures of resistance #202
[2743697.0]: Channel.Club2UC_book.find: about to find unstable resistances involved by club #200 (#wt=0, member=false)
[2743697.0]: Channel.Stabilize.take_decision: NEEDLESS for resistance #202
[2743697.0]: Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels 1, 0
[2743697.0]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
[2743697.0]: Lock.Readers_writer: release_code:   L1-READER AT L1 => RELEASED
[2743697.0]: Lock: RELEASED CLUB #200 at level 1
- : int option Res.Review.h = `Accepted
*)

Ocamlbricks_log.enable ~level:1 () ;;
(* - : unit = () *)

Channel.get x ;;
(*
[2743697.0]: Lock: ACQUIRED CLUB #200 at level 0
[2743697.0]: Lock: RELEASED CLUB #200 at level 0
- : int option = Some 10
*)

Channel.aim_human x (fun _ -> Some 12);;
(*
[2743697.0]: Lock: ACQUIRED CLUB #200 at level 1
[2743697.0]: Channel.aim: notifications are not required
[2743697.0]: Lock: RELEASED CLUB #200 at level 1
- : int option Res.Review.h = `Error (Failure "overwrite forbidden")
*)

Channel.aim_human x (fun _ -> None);;
(*
[2743697.0]: Lock: ACQUIRED CLUB #200 at level 1
[2743697.0]: Channel.aim: notifications are not required
[2743697.0]: Lock: RELEASED CLUB #200 at level 1
- : int option Res.Review.h = `Accepted
*)

Channel.aim_human y (fun _ -> Some 10);;
(* - : int option Res.Review.h = `Revised (Some 11) *)

Channel.aim_human y (fun _ -> Some 13);;
(* - : int option Res.Review.h = `Error (Failure "overwrite forbidden") *)

let xy = Channel.product x y ;;
(* val xy : (int option * int option) Channel.t *)

let x' = Channel.fst xy ;;
(* val x' : int option Channel.t *)
x' = x ;;
(* - : bool = true *)

x' == x ;;
(* - : bool = false *)

let y' = Channel.snd xy ;;
(* val y' : int option Channel.t *)

y' = y, y' == y ;;
(* - : bool * bool = (true, false) *)

Channel.lengths x ;;
(* - : int array = [|1|] *)

Channel.lengths y ;;
(* - : int array = [|1|] *)

Channel.lengths (Channel.plus x x) ;;
(* - : int array = [|1|] *)

Channel.lengths (Channel.plus x y) ;;
(* - : int array = [|1; 1|] *)

Channel.lengths xy ;;
(* - : int array = [|2|] *)

let z = Channel.create None ;;
(* val z : '_a option Channel.t *)

let xy_z = Channel.product ~reviewer:(fun ((x0,y0),z0) ((x1,y1),z1) ->
  Misc.pr "Warning: in xy_z reviewer!\n";
  if (z1=None) && (x1<>None) && (y1<>None) then Res.revised ((None,None), Option.combine x1 y1) else Res.accepted ()) xy z ;;
(*
[2743697.0]: Channel.Club2UC_book: REGISTERING committer for resistance #237 (#clubs=3)
[2743697.0]: Channel.Conjunction: register: REGISTERING structure #237 (GC-alarm: true)

val xy_z : ((int option * int option) * (int * int) option) Channel.t
*)

open Channel.Toolkit ;;

!xy_z ;;
(*
[2743697.0]: Lock: ACQUIRED CLUB #200 at level 0
[2743697.0]: Lock: ACQUIRED CLUB #204 at level 0
[2743697.0]: Lock: ACQUIRED CLUB #232 at level 0
Warning: in xy_z reviewer!
[2743697.0]: Lock: RELEASED CLUB #200 at level 0
[2743697.0]: Lock: RELEASED CLUB #204 at level 0
[2743697.0]: Lock: RELEASED CLUB #232 at level 0
- : (int option * int option) * (int * int) option = ((None, Some 11), None)
*)

x := Some 34 ;;
(*
[2743697.0]: Lock: ACQUIRED CLUB #200 at level 1
[2743697.0]: Channel.aim: about to decide stabilization for super structures of resistance #202
[2743697.0]: Channel.Club2UC_book.find: about to find unstable resistances involved by club #200 (#wt=3, member=true)
[2743697.0]: Channel.Stabilize.take_decision: ABOUT TO LAUNCH A STABILIZER for 1 unstable conjunction(s) involved by #202
[2743697.0]: Lock: RELEASED CLUB #200 at level 1
- : unit = ()
[2743697.1]: Channel.Stabilize.stabilizer: ABOUT TO START THE VISIT
[2743697.1]: Lock: ACQUIRED CLUB #200 at level 0
[2743697.1]: Lock: ACQUIRED CLUB #204 at level 0
[2743697.1]: Lock: ACQUIRED CLUB #232 at level 0
Warning: in xy_z reviewer!
[2743697.1]: Channel.Stabilize.stabilizer: ABOUT TO RELEASE BROADCASTING ALL LEVELS
[2743697.1]: Lock: RELEASED CLUB #232 at level 0
[2743697.1]: Channel.Stabilize.stabilizer: ABOUT TO RELEASE BROADCASTING ALL LEVELS
[2743697.1]: Lock: RELEASED CLUB #204 at level 0
[2743697.1]: Channel.Stabilize.stabilizer: ABOUT TO RELEASE BROADCASTING ALL LEVELS
[2743697.1]: Lock: RELEASED CLUB #200 at level 0
[2743697.1]: Channel.Stabilize.stabilizer: RESULT OF THE VISIT (something changed and notifications sent): true
*)

!xy_z ;;
(* - : (int option * int option) * (int * int) option = ((None, None), Some (34, 11)) *)

let xy' = Channel.fst xy_z ;;
(*
[2394547.0]: Channel.Club2UC_book: REGISTERING committer for resistance #238 (#clubs=3)
[2394547.0]: Channel.Conjunction: register: REGISTERING structure #238 (GC-alarm: true)
val xy' : (int option * int option) Channel.t
*)

Channel.lengths xy' ;;
(* - : int array = [|3|] *)

Channel.lengths xy_z ;;
(* - : int array = [|3|] *)

!xy' ;;
(* xy' has the same complexity of xy_z (because is the same structure with z hidden):
---
[2743697.0]: Lock: ACQUIRED CLUB #200 at level 0
[2743697.0]: Lock: ACQUIRED CLUB #204 at level 0
[2743697.0]: Lock: ACQUIRED CLUB #232 at level 0
Warning: in xy_z reviewer!
[2743697.0]: Lock: RELEASED CLUB #200 at level 0
[2743697.0]: Lock: RELEASED CLUB #204 at level 0
[2743697.0]: Lock: RELEASED CLUB #232 at level 0
- : int option * int option = (None, None)
*)

(* Note: old x' and y' are covered by these new definitions and may be collected: *)
(* let x', y' = Channel.split xy' ;; *)
let x'', y'' = Channel.split xy' ;;
(*
[2743697.0]: Channel.Club2UC_book.register: REGISTERING COMMITTER for resistance #248 (#clubs=3)
[2743697.0]: Channel.Club2UC_book.register: REGISTERING COMMITTER for resistance #249 (#clubs=3)
val x' : int option Channel.t
val y' : int option Channel.t
*)

(* Channel.lengths x', Channel.lengths y' ;; *)
Channel.lengths x'', Channel.lengths y'' ;;
(* - : int array * int array = ([|3|], [|3|]) *)

let z' = Channel.snd xy_z ;;
(*
[2743697.0]: Channel.Club2UC_book: REGISTERING committer for resistance #252 (#clubs=3)
[2743697.0]: Channel.Conjunction: register: REGISTERING structure #252 (GC-alarm: true)
val z' : (int * int) option Channel.t
*)

(* NOTE: old names x,y,z used as components to build xy_z, are not *covered* by x', y' and z'.
   All these new symbols are projections, or "views", of the monolitic group xy_z. *)

Channel.aim_human x (fun _ -> Some 77) ;;
(*
[2743697.0]: Lock: ACQUIRED CLUB #200 at level 1
[2743697.0]: Channel.aim: about to decide stabilization for super structures of resistance #202
[2743697.0]: Channel.Club2UC_book.find: about to find unstable resistances involved by club #200 (#wt=15, member=true)
[2743697.0]: Channel.Stabilize.take_decision: ABOUT TO LAUNCH A STABILIZER for 5 unstable conjunction(s) involved by #202
[2743697.0]: Lock: RELEASED CLUB #200 at level 1
- : int option Res.Review.h = `Revised (Some 78)
[2743697.2]: Channel.Stabilize.stabilizer: ABOUT TO START THE VISIT
[2743697.2]: Lock: ACQUIRED CLUB #200 at level 0
[2743697.2]: Lock: ACQUIRED CLUB #204 at level 0
[2743697.2]: Lock: ACQUIRED CLUB #232 at level 0
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
[2743697.2]: Lock: RELEASED CLUB #232 at level 0
[2743697.2]: Lock: RELEASED CLUB #204 at level 0
[2743697.2]: Lock: RELEASED CLUB #200 at level 0
[2743697.2]: Channel.Stabilize.stabilizer: RESULT OF THE VISIT (something changed and notifications sent): false
*)

(* Ocamlbricks_log.disable () ;; *)

!xy_z ;;
(*
[2743697.0]: Lock: ACQUIRED CLUB #200 at level 0
[2743697.0]: Lock: ACQUIRED CLUB #204 at level 0
[2743697.0]: Lock: ACQUIRED CLUB #232 at level 0
Warning: in xy_z reviewer!
[2743697.0]: Lock: RELEASED CLUB #200 at level 0
[2743697.0]: Lock: RELEASED CLUB #204 at level 0
[2743697.0]: Lock: RELEASED CLUB #232 at level 0
- : (int option * int option) * (int * int) option = ((Some 78, None), Some (34, 11))
*)

(* But we can also use the "view" y' instead of the "component" y: *)
Channel.aim_human y' (fun _ -> Some 78) ;;
(*
[2743697.0]: Lock: ACQUIRED CLUB #200 at level 1
[2743697.0]: Lock: ACQUIRED CLUB #204 at level 1
[2743697.0]: Lock: ACQUIRED CLUB #232 at level 1
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
[2743697.0]: Channel.aim: about to decide stabilization for super structures of resistance #249
[2743697.0]: Channel.Club2UC_book.find: about to find unstable resistances involved by club #200 (#wt=15, member=true)
[2743697.0]: Channel.Club2UC_book.find: about to find unstable resistances involved by club #204 (#wt=15, member=true)
[2743697.0]: Channel.Club2UC_book.find: about to find unstable resistances involved by club #232 (#wt=15, member=true)
[2743697.0]: Channel.Stabilize.take_decision: ABOUT TO LAUNCH A STABILIZER for 12 unstable conjunction(s) involved by #249
[2743697.0]: Lock: RELEASED CLUB #200 at level 1
[2743697.3]: Channel.Stabilize.stabilizer: ABOUT TO START THE VISIT
[2743697.0]: Lock: RELEASED CLUB #204 at level 1
[2743697.3]: Lock: ACQUIRED CLUB #200 at level 0
[2743697.0]: Lock: RELEASED CLUB #232 at level 1
- : int option Res.Review.h = `Revised (Some 79)
[2743697.3]: Lock: ACQUIRED CLUB #204 at level 0
[2743697.3]: Lock: ACQUIRED CLUB #232 at level 0
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
[2743697.3]: Lock: RELEASED CLUB #232 at level 0
[2743697.3]: Lock: RELEASED CLUB #204 at level 0
[2743697.3]: Lock: RELEASED CLUB #200 at level 0
[2743697.3]: Channel.Stabilize.stabilizer: RESULT OF THE VISIT (something changed and notifications sent): false
*)

!xy_z ;;
(* - : (int option * int option) * (int * int) option = ((Some 78, Some 79), Some (34, 11)) *)

(* At the user level, y and y' resist in the same way, but y is less complex then y' which is a view of xy_z.
   Actually: *)

Channel.aim_human y (fun _ -> Some 81) ;;
(*
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-READER AT L1 ACQUIRED (action n°1)
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2394547.0]: Channel.aim: notifications are not required
[2394547.0]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
[2394547.0]: Lock.Readers_writer: release_code:   L1-READER AT L1 => RELEASED
- : int option Res.Review.h = `Error (Failure "overwrite forbidden")
*)

Channel.aim_human y' (fun _ -> Some 81) ;;
(* y' is a view of xy_z:
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-READER AT L1 ACQUIRED (action n°1)
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-READER AT L1 ACQUIRED (action n°1)
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-READER AT L1 ACQUIRED (action n°1)
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
[2394547.0]: Channel.aim: notifications are not required
[2394547.0]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
[2394547.0]: Lock.Readers_writer: release_code:   L1-READER AT L1 => RELEASED
[2394547.0]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
[2394547.0]: Lock.Readers_writer: release_code:   L1-READER AT L1 => RELEASED
[2394547.0]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
[2394547.0]: Lock.Readers_writer: release_code:   L1-READER AT L1 => RELEASED
- : int option Res.Review.h = `Error (Failure "overwrite forbidden")
*)

!xy_z ;;
(* - : (int option * int option) * (int * int) option = ((Some 78, Some 79), Some (34, 11)) *)

(* We take now the double message from z: *)

let receive (t: 'a option Channel.t) : 'a =
  Channel.apply_method ~enter:((<>)None) (fun (Some msg) () -> None, (fun _ -> msg)) t () ;;
(* val receive : 'a option Channel.t -> 'a *)

let f = Future.make (fun () -> let msg = receive z in Misc.pr "future f: received: %d %d\n" (fst msg) (snd msg)) () ;;
(*
val f : unit Future.t = <abstr>
[2394547.4]: Lock.Readers_writer: acquire_guards: L1-READER AT L1 ACQUIRED (action n°1)
[2394547.4]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2394547.4]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2394547.4]: Channel.aim: about to decide stabilization for super structures of resistance #228
[2394547.4]: Channel.Club2UC_book.find: about to find unstable resistances involved by club #226 (#wt=15, member=true)
[2394547.4]: Channel.Stabilize.take_decision: ABOUT TO LAUNCH A STABILIZER for 5 unstable conjunction(s) involved by #228 ...
[2394547.4]: Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels 1, 0
[2394547.5]: Channel.Stabilize.stabilizer: ABOUT TO START THE VISIT
[2394547.4]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
[2394547.5]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2394547.5]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2394547.4]: Lock.Readers_writer: release_code:   L1-READER AT L1 => RELEASED
future f: received: 34 11
[2394547.5]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2394547.5]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2394547.5]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2394547.5]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
[2394547.5]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2394547.5]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
[2394547.5]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2394547.5]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
[2394547.5]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2394547.5]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
[2394547.5]: Channel.Stabilize.stabilizer: RESULT OF THE VISIT (something changed and someone notified): false
*)

let f = Future.make (fun () -> let msg = receive z in Misc.pr "future f: received: %d %d\n" (fst msg) (snd msg)) () ;;
(*
val f : unit Future.t = <abstr>
[2394547.6]: Lock.Readers_writer: acquire_guards: L1-READER AT L1 ACQUIRED (action n°1)
[2394547.6]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2394547.6]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2394547.6]: Channel.aim: about to decide stabilization for super structures of resistance #228
[2394547.6]: Channel.Club2UC_book.find: about to find unstable resistances involved by club #226 (#wt=15, member=true)
[2394547.6]: Channel.Stabilize.take_decision: ABOUT TO LAUNCH A STABILIZER for 5 unstable conjunction(s) involved by #228 ...
[2394547.6]: Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels 1, 0
[2394547.7]: Channel.Stabilize.stabilizer: ABOUT TO START THE VISIT
[2394547.6]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
[2394547.6]: Lock.Readers_writer: release_code:   L1-READER AT L1 => RELEASED
future f: received: 78 79
[2394547.7]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2394547.7]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2394547.7]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2394547.7]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2394547.7]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2394547.7]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
[2394547.7]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2394547.7]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
[2394547.7]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2394547.7]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
[2394547.7]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2394547.7]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
[2394547.7]: Channel.Stabilize.stabilizer: RESULT OF THE VISIT (something changed and someone notified): false
*)

!xy_z ;;
(* - : (int option * int option) * (int * int) option = ((None, None), None) *)

Future.taste f ;;
(* - : unit option = Some () *)

!z ;;
(* - : (int * int) option = None *)

(***  Commits go up and down  ***)

let f1 = Future.make (fun () -> let msg = receive z in Misc.pr "future f1: received: %d %d\n" (fst msg) (snd msg)) () ;;
let f2 = Future.make (fun () -> let msg = receive z in Misc.pr "future f2: received: %d %d\n" (fst msg) (snd msg)) () ;;

Channel.aim_human x (fun _ -> Some 42) ;;
!xy_z ;;
(* - : (int option * int option) * (int * int) option = ((Some 42, None), None) *)

Channel.aim_human y (fun _ -> Some 81) ;;
(* future f1: received: 42 81 *)

Future.taste f1 ;;
(* - : unit option = Some () *)

Future.taste f2 ;;
(* - : unit option = None *)

!xy_z ;;
(* - : (int option * int option) * (int * int) option = ((None, None), None) *)

Channel.aim_human x (fun _ -> Some 16) ;;
Channel.aim_human y (fun _ -> Some 17) ;;
(*
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-READER AT L1 ACQUIRED (action n°1)
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 DECLARED myself as waiting writer (action n°1)
[2394547.0]: Lock.Readers_writer: acquire_guards: L1-WRITER AT L0 ACQUIRED (action n°2)
[2394547.0]: Channel.aim: about to decide stabilization for super structures of resistance #206
[2394547.0]: Channel.Club2UC_book.find: about to find unstable resistances involved by club #204 (#wt=15, member=true)
[2394547.0]: Channel.Stabilize.take_decision: ABOUT TO LAUNCH A STABILIZER for unstable conjunction(s) involved by #206 ...
[2394547.0]: Lock.Raw: about to broadcast highland waiting rooms (plateau) at levels 1, 0
[2394547.0]: Lock.Readers_writer: release_code:   L1-WRITER AT L0 => RELEASED
[2394547.0]: Lock.Readers_writer: release_code:   L1-READER AT L1 => RELEASED
- : int option Res.Review.h = `Accepted
future f2: received: 16 17
[2394547.13]: Channel.Stabilize.stabilizer: ABOUT TO START THE VISIT
[2394547.13]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2394547.13]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2394547.13]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2394547.13]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
[2394547.13]: Lock.Readers_writer: acquire_guards: L0-READER AT L1 ACQUIRED (action n°1)
[2394547.13]: Lock.Readers_writer: acquire_guards: L0-READER AT L0 ACQUIRED (action n°1)
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
Warning: in xy_z reviewer!
[2394547.13]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2394547.13]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
[2394547.13]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2394547.13]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
[2394547.13]: Lock.Readers_writer: release_code:   L0-READER AT L0 => RELEASED
[2394547.13]: Lock.Readers_writer: release_code:   L0-READER AT L1 => RELEASED
[2394547.13]: Channel.Stabilize.stabilizer: RESULT OF THE VISIT (something changed and someone notified): false
*)

Future.taste f2 ;;
(* - : unit option = Some () *)

!xy_z ;;
(* - : (int option * int option) * (int * int) option = ((None, None), None) *)

*)
