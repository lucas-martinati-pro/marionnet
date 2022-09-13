(* This file is part of ocamlbricks
   Copyright (C) 2013  Jean-Vincent Loddo

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

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

(* module Mutex = MutexExtra.Recursive *) (* A utiliser pour la construction `lifes', sinon pas nécessaires *)
module Mutex = MutexExtra.Extended_Mutex

module Mutex_group = struct

  module Mutex_set = Set.Make (struct type t = Mutex.t let compare = compare end)

  let merge_and_sort_mutex_lists l1 ls =
    let s = List.fold_left (fun s x -> Mutex_set.add x s) Mutex_set.empty l1 in
    let add s l2 = List.fold_left (fun s x -> Mutex_set.add x s) s l2 in
    let s = List.fold_left (add) s ls in
    Mutex_set.elements s

  type t = {
    head          : Mutex.t;
    tail          : Mutex.t list;
    reversed_tail : Mutex.t list;
    }

  let single () = {
    head = Mutex.create ();
    tail = [];
    reversed_tail = [];
    }

  let to_mutex_list t = t.head :: t.tail

  let of_ordered_mutex_list =
    function
    | m::ms ->
	let ws = List.rev ms in
	{ head = m;
	  tail = ms;
	  reversed_tail = ws; }
    | [] -> assert false

  let group (t1 : t) (ts : t list) =
    let ms =
      let ms1 = to_mutex_list t1 in
      let msl = List.map to_mutex_list ts in
      merge_and_sort_mutex_lists ms1 msl
    in
    of_ordered_mutex_list ms

  let lock t = begin
    Mutex.lock t.head;
    List.iter Mutex.lock t.tail;
    end

  let unlock t = begin
    List.iter Mutex.unlock t.reversed_tail;
    Mutex.unlock t.head;
    end

  let wait alert t = begin
    List.iter Mutex.unlock t.reversed_tail;
    Mutex.wait alert t.head;
    List.iter Mutex.lock t.tail;
    end

  let apply_with_mutex (t:t) f x =
   lock t;
   try
     let result = f x in
     unlock t;
     result
   with e -> begin
     unlock t;
     raise e;
   end

  (* let with_mutex (t:t) thunk = apply_with_mutex t thunk () *)
  let with_mutex (t:t) thunk =
   lock t;
   try
     let result = thunk () in
     unlock t;
     result
   with e -> begin
     unlock t;
     raise e;
   end

end (* module Mutex_group *)

(* Basic notion of equality: *)
let scalar_equality = fun s s' -> (s == s' || s = s')
;;

module Unprotected = struct

(* The structure of an unprotected cortex: *)
type 'state t = {
 alert_on_commit    : Condition.t;
 get_content        : unit -> 'state;
 propose_content    : 'state -> 'state;
 revno              : int ref;
 waiting_no         : int ref;
 equality           : 'state -> 'state -> bool;
 on_proposal        : ('state -> 'state -> 'state) Thunk.fifo_container;
 on_commit          : ('state -> 'state -> unit) Thunk.fifo_container;
 (* "Private methods": *)
 on_proposal_container_unchanged : unit -> bool;
 no_longer_in_use   : bool ref;
 equals_to_current  : ('state -> bool) ref;
}
;;

(* Unprotected.make *)
let make
 ?(equality:('state -> 'state -> bool) option)
 ?(on_proposal:('state -> 'state -> 'state) option)
 ?(on_commit:('state -> 'state -> unit) option)
 ~(get_content:(unit -> 'state))
 ?(set_content:('state -> unit) option)
 ?(propose_content:('state -> 'state) option)
 ()
 : 'state t
 =
 let equality =
   match equality with
   | None -> scalar_equality
   | Some equality -> equality
 in
 (* Will be updated during commit: *)
 let initial_equals_to_current =
   let current = get_content () in
   (* The following partial application of the `equality' predicate is very relevant
      when the content is a reference (for example an object or a cortex): *)
   equality current
 in
 (* Work around for a strange problem of the type-checker about the recursive definition of `self': *)
 let (is_propose_content_provided, propose_content, set_content) =
   let unused = (fun proposal -> assert false) in
   match set_content, propose_content with
   | None    , (Some f) -> (true, f, unused)
   | (Some f), None     -> (false, unused, f)
   | _, _               -> invalid_arg "Cortex.make: ~set_content xor ~propose_content must be provided."
 in
 (* The record is morally an object: *)
 let rec self : 'state t =
  let alert_on_commit = Condition.create () in
  let on_proposal =
    let container = new Thunk.fifo_container ~fallback:(fun () -> fun s0 s1 -> s1) () in
    let () = Option.iter (fun f -> ignore (container#register_thunk (fun () -> f))) on_proposal in
    container
  in
  let on_commit =
    let container = new Thunk.fifo_container ~fallback:(fun () -> fun s0 s1 -> ()) () in
    let () = Option.iter (fun f -> ignore (container#register_thunk (fun () -> f))) on_commit in
    container
  in
  let on_proposal_container_unchanged =
    let previous_revno = ref 0 in
    fun () ->
      let current = self.on_proposal#revno in
      let result = (current = !previous_revno) in
      previous_revno := current;
      result
  in
  let propose_content (proposal) =
    if is_propose_content_provided then propose_content (proposal) else
    let () = set_content (proposal) in
    get_content ()
  in
  { alert_on_commit   = alert_on_commit;
    get_content       = get_content;
    propose_content   = propose_content;
    revno             = ref 0;
    waiting_no        = ref 0;
    equality          = equality;
    equals_to_current = ref initial_equals_to_current;
    on_proposal       = on_proposal;
    on_commit         = on_commit;
    on_proposal_container_unchanged = on_proposal_container_unchanged;
    no_longer_in_use  = ref false;
    }
 (* end of self definition *)
 in
 self

(* Unprotected.return *)
let return
 ?(equality:('state -> 'state -> bool) option)
 ?(on_proposal:('state -> 'state -> 'state) option)
 ?(on_commit:('state -> 'state -> unit) option)
 (content:'state)
 =
 let cell = ref content in
 let get_content () = !cell in
 let set_content v = (cell := v) in
 make ?equality ?on_proposal ?on_commit ~get_content ~set_content ()

(* Unprotected.of_object *)
let of_object
 ?(equality:('state -> 'state -> bool) option)
 ?(on_proposal:('state -> 'state -> 'state) option)
 ?(on_commit:('state -> 'state -> unit) option)
 (x:< get:'state; set:'state -> unit; >)
 =
 let get_content () = x#get in
 let set_content v = x#set v in
 make ?equality ?on_proposal ?on_commit ~get_content ~set_content ()

(* Unprotected.revno_equality *)
let revno_equality x =
  let r = x.revno in
  (fun x' -> x==x' && x'.revno = r)

(* Unprotected.revno_or_content_equality *)
let revno_or_content_equality : 'a t -> 'a t -> bool =
  fun x1 ->
    let r = x1.revno in
    fun x2 ->
      (x1==x2 && x2.revno = r) ||
      (let v1 = x1.get_content () in
       let v2 = x2.get_content () in
       (x1.equality v1 v2) && (x2.equality v2 v1))

(* Unprotected.eval. The universal method, unprotected and without guards: *)
let eval : 'a 'b. ('state -> 'a -> 'state * ('state -> 'b)) -> 'a -> 'state t -> 'b * bool * ('state * 'state) =
  fun f a t ->
    let equals_to_current = !(t.equals_to_current) in
    let current = t.get_content () in
    let (first_proposal, b_of_state) =
      (* Apply the update-proposal `f' *)
      f current a
    in
    (* This test is useful for thread waiting for a commit of a member
       which is no longer in use. This test is redundant because the thread
       should be stopped by the condition ~membership (see below): *)
    if !(t.no_longer_in_use) then ((b_of_state current), false, (current, current)) else
    if (equals_to_current first_proposal) && (t.on_proposal_container_unchanged ())
      then
	(* No changes => no callbacks *)
	((b_of_state current), false, (current, current))
      else begin
	let rec local_fixpoint s =
	  (* Again a partial application: *)
	  let equals_to_s = (t.equality s) in
	  let s' =
	    (* Callbacks raising an exception are ignored: *)
	    t.on_proposal#apply ~folder:(fun state f -> try f current state with _ -> state) s
	  in
	  if equals_to_s (s') then s else local_fixpoint s'
	in
	let locally_fixed_proposal =
	  local_fixpoint first_proposal
	in
        (* A change should be observed, supposing the provided `set_content'
           or 'propose_content' agreed with the `locally_fixed_proposal': *)
        let rec global_fixpoint (s0:'a) : 'a * ('a -> bool) =
          let equals_to_s0 = (t.equality s0) in
          let s1 = t.propose_content (s0) in
          if equals_to_s0 (s1) then (s0, equals_to_s0) else
          let s2 = local_fixpoint s1 in
          global_fixpoint s2
        in
        let globally_fixed_proposal, new_equals_to_current =
          global_fixpoint (locally_fixed_proposal)
        in
        let changed = not (equals_to_current globally_fixed_proposal) in
        if changed then
          begin
            (* A patch is really happened: *)
            t.revno := !(t.revno) + 1;
            t.equals_to_current := new_equals_to_current;
            if !(t.waiting_no) > 0
              then begin
                (* let _ = Printf.kfprintf flush stderr "Cortex.eval: broadcasting to %d waiting threads\n" !(t.waiting_no) in *)
                Condition.broadcast (t.alert_on_commit);
                t.waiting_no := 0
              end;
          end; (* if changed *)
        let result = ((b_of_state globally_fixed_proposal), changed, (current, globally_fixed_proposal)) in
        result
      end (* A fixed proposal has been calculated *)

(* Unprotected.eval redefined: the third component of the result (the state)
   is given to the on_commit callbacks: *)
let eval : 'a 'b. ('state -> 'a -> 'state * ('state -> 'b)) -> 'a -> 'state t -> 'b * bool =
  let are_there_on_commit_callbacks t =
     not (Container.Queue_with_identifiers.is_empty (t.on_commit#as_queue))
  in
  fun f a t ->
    let (b, changed, (s0,s1)) = eval f a t in
    let () =
      if changed && (are_there_on_commit_callbacks t)
	then
	  (* A unique thread is created to execute thunks sequentially with FIFO discipline: *)
	  ignore
	    (Thread.create
	      (t.on_commit#apply ~folder:(fun () f -> try f s0 s1 with _ -> ()))
	      ())
	else ()
    in
    (b, changed)

(* Unprotected.propose. The `propose' specific case (useful for grouping): *)
let eval_propose : 'state -> 'state t -> 'state * bool =
  fun s1 t -> eval (fun s0 s1 -> s1, (fun s2 -> s2)) s1 t

(* Unprotected.guarded_eval. Mutexes must be provided for waiting.
   Note that the evaluation starts immediately if the guard is verified. *)
let guarded_eval
  : 'a 'b.
       guard:('state -> bool) ->
       mutexes:Mutex_group.t ->
       ('state -> 'a -> 'state * ('state -> 'b)) -> 'a -> 'state t -> 'b * bool
  =
  fun ~guard ~mutexes f a t ->
  let () = while not (guard (t.get_content ())) do
    incr (t.waiting_no);
    (* let _ = Printf.kfprintf flush stderr "Cortex.guarded_eval: entering wait (waiting_no = %d)\n" !(t.waiting_no) in *)
    Mutex_group.wait (t.alert_on_commit) mutexes;
    (* let _ = Printf.kfprintf flush stderr "Cortex.guarded_eval: exiting wait (waiting_no = %d)\n" !(t.waiting_no) in *)
    ()
    done
  in
  eval f a t

exception Membership_failure

(* Mutexes must be provided for waiting. The cortex that commits is not necessarely
   the same that will be evaluated (even if by default is the same), but we suppose
   that the provided mutexes lock *both* cortex. Note also that we start waiting
   anyway: the evaluation will be executed after at least one commit. *)
let eval_after_commit
  : ?monitored:('member t) -> (* the cortex that we are waiting for *)
    ?membership:(unit -> bool) ->
    ?guard:('state -> bool) ->
     mutexes:Mutex_group.t ->
    ('state -> 'a -> 'state * ('state -> 'b)) ->
    (* Arguments are flipped for efficiency: *)
    'state t -> 'a -> ('b * bool) option
  =
  fun ?monitored ?(membership=(fun () -> true)) ?guard ~mutexes f t ->
    let (alert_on_commit, waiting_no) =
      match monitored with
      | None   -> (t.alert_on_commit, t.waiting_no)
      | Some m -> (m.alert_on_commit, m.waiting_no)
    in
    let eval_without_guard a =
      begin
	(* Start waiting anyway: *)
	incr (waiting_no);
	Mutex_group.wait (alert_on_commit) mutexes;
        (* Eval after a commit (if the membership is still valid): *)
	if membership () then Some (eval f a t) else None
      end
    in
    let eval_with_guard guard a =
      begin
        try
	  (* Start waiting anyway: *)
	  incr (waiting_no);
	  Mutex_group.wait (alert_on_commit) mutexes;
	  (if not (membership ()) then raise Membership_failure);
	  while not (guard (t.get_content ())) do
	    incr (waiting_no);
	    Mutex_group.wait (alert_on_commit) mutexes;
	    (if not (membership ()) then raise Membership_failure);
	  done;
	  (* Eval after at least one commit: *)
	  Some (eval f a t)
	with
	  Membership_failure -> None
      end
    in
    match guard with
    | None       -> eval_without_guard
    | Some guard -> eval_with_guard guard


let repeat_eval_after_commit
  : ?monitored:('member t) -> (* the cortex that we are waiting for *)
    ?membership:(unit -> bool) ->
    ?guard:('state -> bool) ->
    ?signal_me_in_critical_section:(unit Egg.t) ->
    mutexes:Mutex_group.t ->
    ('state -> 'a -> 'state * ('state -> 'b)) ->
    'state t ->
    (* the boolean result of `folder' denotes the `break' condition: *)
    folder:('c -> ('b * bool) -> 'c * bool) ->
    'a -> 'c -> 'c
  =
  fun ?monitored ?membership ?guard ?signal_me_in_critical_section ~mutexes f t ->
  let () = Option.iter (fun egg -> Egg.release egg ()) (signal_me_in_critical_section) in
  let eval = eval_after_commit ?monitored ?membership ?guard ~mutexes f t in
  fun ~folder a c ->
  let rec loop c =
    match eval a with
    | None   -> c (* A membership failure => break *)
    | Some r ->
        let (c', break) = folder c r in
        if break then c' else loop c'
  in
  loop c

end (* module Unprotected *)

(* Mutexes and related conditions are ordered by mutexes simply with Pervasives.compare.
   The inner evaluation is unprotected. *)
type 'state t = Mutex_group.t * 'state Unprotected.t
(* Recursive cortex?
type 'a r = ('Mutex_group.t t) * 'a Unprotected.t
*)

(*let copy_but_already_protected_by ~mutexes t =
 (mutexes, snd t)
;;*)

let make
 ?mutexes
 ?(equality:('state -> 'state -> bool) option)
 ?(on_proposal:('state -> 'state -> 'state) option)
 ?(on_commit:('state -> 'state -> unit) option)
 ~(get_content:(unit -> 'state))
 ?(set_content:('state -> unit) option)
 ?(propose_content:('state -> 'state) option)
 ()
 : 'state t
 =
 let mutexes =
   match mutexes with
   | None         -> Mutex_group.single ()
   | Some mutexes -> mutexes
 in
 let u =
   Unprotected.make ?equality ?on_proposal ?on_commit ~get_content ?set_content ?propose_content ()
 in
 (mutexes, u)


(* The universal method (protected and guarded version): *)
let eval
  : ?guard:('state -> bool) ->
    ('state -> 'a -> 'state * ('state -> 'b)) -> 'a -> 'state t -> 'b * bool
  =
  fun ?guard f a (mutexes, u) ->
  match guard with
  | None ->
      Mutex_group.apply_with_mutex mutexes (Unprotected.eval f a) u
  | Some guard ->
      Mutex_group.apply_with_mutex mutexes (Unprotected.guarded_eval ~guard ~mutexes f a) u

(* Note that in the protected version the arguments are flipped with respect
   to the unprotected one. Warning: the monitored cortex, if provided, must be
   also locked by the mutexes of t. *)
let eval_after_commit
  : ?monitored:('c t) ->         (* the cortex that we are waiting for *)
    ?membership:(unit -> bool) ->
    ?guard:('state -> bool) ->
    ('state -> 'a -> 'state * ('state -> 'b)) ->
    'a -> 'state t -> ('b * bool) option
  =
  fun ?monitored ?membership ?guard f a t ->
  let monitored = Option.map snd monitored in
  let (mutexes, u) = t in
  Mutex_group.apply_with_mutex mutexes
    (Unprotected.eval_after_commit ?monitored ?membership ?guard ~mutexes f u) a

(* Note that in the protected version the arguments are flipped with respect
   to the unprotected one. Warning: the monitored cortex, if provided, must be
   also locked by the mutexes of t. *)
let repeat_eval_after_commit
  : ?monitored:('m t) ->         (* the cortex that we are waiting for *)
    ?membership:(unit -> bool) ->
    ?guard:('state -> bool) ->
    ?signal_me_in_critical_section:(unit Egg.t) ->
    folder:('c -> ('b * bool) -> 'c * bool) ->
    ('state -> 'a -> 'state * ('state -> 'b)) ->
    'a -> 'state t -> 'c -> 'c
  =
  fun ?monitored ?membership ?guard ?signal_me_in_critical_section ~folder f a t c ->
  let monitored = Option.map snd monitored in
  let (mutexes, u) = t in
  Mutex_group.apply_with_mutex mutexes
    (Unprotected.repeat_eval_after_commit
       ?monitored ?membership ?guard ?signal_me_in_critical_section
       ~mutexes f u ~folder a) c

let eval_get ?guard t = fst (eval ?guard (fun s () -> s, (fun s -> s)) () t)
let eval_set ?guard s1 t = ignore (eval ?guard (fun s0 s1 -> s1, (fun s2 -> s2)) s1 t)
let eval_propose ?guard s1 t = eval ?guard (fun s0 s1 -> s1, (fun s2 -> s2)) s1 t
let eval_move ?guard f t = eval ?guard (fun s0 () -> (f s0), (fun s2 -> s2)) () t

(* Flipped versions: *)
let get ?guard t = fst (eval ?guard (fun s () -> s, (fun s -> s)) () t)
let set ?guard t s1 = ignore (eval ?guard (fun s0 s1 -> s1, (fun s2 -> s2)) s1 t)
let propose ?guard t s1 = eval ?guard (fun s0 s1 -> s1, (fun s2 -> s2)) s1 t
let move ?guard t f = eval ?guard (fun s0 () -> (f s0), (fun s2 -> s2)) () t
(* Reading: *)
let apply  ?guard t f   = fst (eval ?guard (fun s () -> s, (fun s -> f s)) () t)
let apply2 ?guard t f x = fst (eval ?guard (fun s () -> s, (fun s -> f s x)) () t)

let on_proposal_append (mutexes, u) thunk =
  Mutex_group.with_mutex mutexes
    (fun () ->
       u.Unprotected.on_proposal#register_thunk (fun () -> thunk))

let on_proposal_remove (mutexes, u) id =
  Mutex_group.with_mutex mutexes
    (fun () ->
       u.Unprotected.on_proposal#remove id)

let on_proposal_clear (mutexes, u) =
  Mutex_group.with_mutex mutexes
    (fun () ->
       Container.Queue_with_identifiers.clear (u.Unprotected.on_proposal#as_queue))

let on_commit_append (mutexes, u) thunk =
  Mutex_group.with_mutex mutexes
    (fun () ->
       u.Unprotected.on_commit#register_thunk (fun () -> thunk))

let on_commit_remove (mutexes, u) id =
  Mutex_group.with_mutex mutexes
    (fun () ->
       u.Unprotected.on_commit#remove id)

let on_commit_clear (mutexes, u) =
  Mutex_group.with_mutex mutexes
    (fun () ->
       Container.Queue_with_identifiers.clear (u.Unprotected.on_commit#as_queue))

(* Flipped and asynchronous versions: *)
module Async = struct

  let set ?guard t s1 =
    ignore (Thread.create (fun () -> eval ?guard (fun s0 s1 -> s1, (fun s2 -> s2)) s1 t) ())

  let move ?guard t f =
    ignore (Thread.create (fun () -> eval ?guard (fun s0 () -> (f s0), (fun s2 -> s2)) () t) ())

end (* module Async *)

(* May be also called `unit' or `create': 'a -> 'a t *)
let return
 ?(equality:('state -> 'state -> bool) option)
 ?(on_proposal:('state -> 'state -> 'state) option)
 ?(on_commit:('state -> 'state -> unit) option)
 (content:'state)
 =
 let cell = ref content in
 let get_content () = !cell in
 let set_content v = (cell := v) in
 make ?equality ?on_proposal ?on_commit ~get_content ~set_content ()

let of_object
 ?(equality:('state -> 'state -> bool) option)
 ?(on_proposal:('state -> 'state -> 'state) option)
 ?(on_commit:('state -> 'state -> unit) option)
 (x:< get:'state; set:'state -> unit; >)
 =
 let get_content () = x#get in
 let set_content v = x#set v in
 make ?equality ?on_proposal ?on_commit ~get_content ~set_content ()


let repeat_move_proposal_to_group_on_member_commit
  : ?membership:(unit -> bool) ->
    ?guard:('state -> bool) ->
    ?signal_me_in_critical_section:(unit Egg.t) ->
    ?action_and_break_decision_when_accepted:('state -> 'state -> 'state -> bool) ->
    move_proposal:('state -> 'state) ->
    group:'state t ->
   'member t -> unit
  =
  fun
    ?membership
    ?guard
    ?signal_me_in_critical_section
    ?(action_and_break_decision_when_accepted=fun _ _ _ -> false)
    ~move_proposal
    ~group
    member
  ->
  let monitored = member in
  (* The method is similar to `move' but the result is the triple
     of states (before_transition, proposed, after_transition): *)
  let mthd s0 () =
    let s1 = move_proposal s0 in
    (s1, (fun s2 -> (s0,s1,s2)))
  in
  let folder () ((s0,s1,s2), changed) =
    let break =
      if changed
       then (action_and_break_decision_when_accepted s0 s1 s2)
       else false
    in
    ((), break)
  in
  repeat_eval_after_commit
    ~monitored ?membership ?guard ?signal_me_in_critical_section ~folder mthd () group ()

let repeat_propose_to_group_on_member_commit
 ?membership ?guard ?signal_me_in_critical_section
 ?action_and_break_decision_when_accepted
 ~proposal ~group member
 = repeat_move_proposal_to_group_on_member_commit
     ?membership ?guard
     ?signal_me_in_critical_section
     ?action_and_break_decision_when_accepted
     ~move_proposal:(fun _ -> proposal ()) ~group member

let eval_propose ?guard s1 t =
  eval ?guard (fun s0 s1 -> s1, (fun s2 -> s2)) s1 t


type 'a scalar_or_cortex = ('a, ('a t)) Either.t
let scalar x = Either.Left x
let cortex x = Either.Right x

let connection ?on_proposal ?on_commit ?private_fellow (f:'a->'b) (g:'b -> 'a) (member_x : 'a t) : 'b t =
  let (x_mutexes, x) = member_x in
  let mutexes = x_mutexes in
  let equality b =
    let equals_b = x.Unprotected.equality (g b) in
    fun b' -> equals_b (g b')
  in
  let proposal () = f (x.Unprotected.get_content ()) in
  let private_fellow : bool = (private_fellow = Some ()) in
  let x_bell = if private_fellow then None else Some (Egg.create ()) in
  let group =
    Mutex_group.with_mutex mutexes
      (fun () ->
	let content_copy = ref (proposal ()) in
	let get_content () = !content_copy in
	let rec propose_content a =
	  begin
	    let b = fst (Unprotected.eval_propose (g a) x) in
	    let a' = f b in
	    content_copy := a';
	    a'
	  end
	and
	  result : ('b t) Lazy.t =
	    lazy (make ~mutexes ~equality ?on_proposal ?on_commit ~get_content ~propose_content ())
	in
	(* end of recursive definition *)
	let (_, group_u) as group = (Lazy.force result) in
	let membership () = not !(group_u.Unprotected.no_longer_in_use) in
	let trigger_on (member) =
	  repeat_propose_to_group_on_member_commit
	    ~signal_me_in_critical_section:(Option.extract x_bell) ~membership ~proposal ~group (member)
	in
	(* If the encapsulated cortex is private (not accessible outside the connection), nobody will
	   try to modify its state, so there is no need to install an observer: *)
	let _thd1 = if private_fellow then None else Some (Thread.create (trigger_on) (member_x)) in
	group)
  in
  let () = Option.iter (Egg.wait) x_bell in
  group

let view ?equality ?on_proposal ?on_commit ?private_fellow (f:'a->'b) (member_x : 'a t) : 'b t =
  let (x_mutexes, x) = member_x in
  let mutexes = x_mutexes in
  let proposal () = f (x.Unprotected.get_content ()) in
  let private_fellow : bool = (private_fellow = Some ()) in
  let x_bell = if private_fellow then None else Some (Egg.create ()) in
  let group =
    Mutex_group.with_mutex mutexes
      (fun () ->
	let content_copy = ref (proposal ()) in
	let get_content () = !content_copy in
	let rec propose_content a =
	  begin
	    content_copy := a;
	    a
	  end
	and
	  result : ('b t) Lazy.t =
	    lazy (make ~mutexes ?equality ?on_proposal ?on_commit ~get_content ~propose_content ())
	in
	(* end of recursive definition *)
	let (_, group_u) as group = (Lazy.force result) in
	let membership () = not !(group_u.Unprotected.no_longer_in_use) in
	let trigger_on (member) =
	  repeat_propose_to_group_on_member_commit
	    ~signal_me_in_critical_section:(Option.extract x_bell) ~membership ~proposal ~group (member)
	in
	(* If the encapsulated cortex is private (not accessible outside the connection), nobody will
	   try to modify its state, so there is no need to install an observer: *)
	let _thd1 = if private_fellow then None else Some (Thread.create (trigger_on) (member_x)) in
	group)
  in
  let () = Option.iter (Egg.wait) x_bell in
  group


let wrapper ?on_proposal ?on_commit ?private_fellow (member_x : 'a t) : 'a t =
  let (x_mutexes, x) = member_x in
  let mutexes = x_mutexes in
  let equality = x.Unprotected.equality in
  let proposal = x.Unprotected.get_content in
  let private_fellow : bool = (private_fellow = Some ()) in
  let x_bell = if private_fellow then None else Some (Egg.create ()) in
  let group =
    Mutex_group.with_mutex mutexes
      (fun () ->
	let content_copy = ref (proposal ()) in
	let get_content () = !content_copy in
	let rec propose_content v =
	  begin
	    let (v', b) = Unprotected.eval_propose v x in
	    content_copy := v';
	    v'
	  end
	and
	  result : ('a t) Lazy.t =
	    lazy (make ~mutexes ~equality ?on_proposal ?on_commit ~get_content ~propose_content ())
	in
	(* end of recursive definition *)
	let (_, group_u) as group = (Lazy.force result) in
	let membership () = not !(group_u.Unprotected.no_longer_in_use) in
	let trigger_on (member) =
	  repeat_propose_to_group_on_member_commit
	    ~signal_me_in_critical_section:(Option.extract x_bell) ~membership ~proposal ~group (member)
	in
	(* If the encapsulated cortex is private (not accessible outside the connection), nobody will
	   try to modify its state, so there is no need to install an observer: *)
	let _thd1 = if private_fellow then None else Some (Thread.create (trigger_on) (member_x)) in
	group)
  in
  let () = Option.iter (Egg.wait) x_bell in
  group


module Product_pair
  (Prod : sig
     type ('a,'b) t
     val prjA : ('a,'b) t -> 'a
     val prjB : ('a,'b) t -> 'b
     val make : 'a -> 'b -> ('a,'b) t
   end)
 =
 struct

 let product_pair ?on_proposal ?on_commit ?private_a ?private_b (member_x : 'a t) (member_y : 'b t) : (('a,'b) Prod.t) t =
  let (x_mutexes, x) = member_x in
  let (y_mutexes, y) = member_y in
  let mutexes = Mutex_group.group x_mutexes [y_mutexes] in
  let private_a : bool = (private_a = Some ()) in
  let private_b : bool = (private_b = Some ()) in
  let equality v =
    let a, b = (Prod.prjA v), (Prod.prjB v) in
    let equals_a = (x.Unprotected.equality a) in
    let equals_b = (y.Unprotected.equality b) in
    fun v' ->
      let a', b' = (Prod.prjA v'), (Prod.prjB v') in
      (equals_a a') && (equals_b b')
  in
  let proposal () = Prod.make (x.Unprotected.get_content ()) (y.Unprotected.get_content ()) in
  let x_bell = if private_a then None else Some (Egg.create ()) in
  let y_bell = if private_b then None else Some (Egg.create ()) in
  let group =
    Mutex_group.with_mutex mutexes
      (fun () ->
	let content_copy = ref (proposal ()) in
	let get_content () = !content_copy in
	let rec propose_content v =
	  begin
	    let v1, v2 = (Prod.prjA v), (Prod.prjB v) in
	    let (v1', b1) = Unprotected.eval_propose v1 x in
	    let (v2', b2) = Unprotected.eval_propose v2 y in
	    let v' = Prod.make v1' v2' in
	    content_copy := v';
	    v'
	  end
	and
	  result = lazy (make ~mutexes ~equality ?on_proposal ?on_commit ~get_content ~propose_content ())
	in
	let (_, group_u) as group = (Lazy.force result) in
	let membership () = not !(group_u.Unprotected.no_longer_in_use) in
	let trigger_on (bell) (member) =
	  repeat_propose_to_group_on_member_commit
	    ~signal_me_in_critical_section:bell ~membership ~proposal ~group (member)
	in
	(* If a member is private (not accessible outside the group), nobody will
	   try to modify its state, so there is no need to install an observer: *)
	let thread_create (private_flag) (obell) (member) =
	  if private_flag then None else
	  let bell = Option.extract obell in
	  Some (Thread.create (trigger_on bell) (member))
	in
	let _thd1 = thread_create (private_a) (x_bell) (member_x) in
	let _thd2 = thread_create (private_b) (y_bell) (member_y) in
	group)
  in
  let () = Option.iter (Egg.wait) x_bell in
  let () = Option.iter (Egg.wait) y_bell in
  group

 let make
  ?on_proposal
  ?on_commit
  (a:'a scalar_or_cortex)
  (b:'b scalar_or_cortex)
  : (('a,'b) Prod.t) t
  =
  let split_scalar_and_member = function
  | Either.Left scalar  -> (Some scalar), None
  | Either.Right member -> None, (Some member)
  in
  let scalar_x, member_x = split_scalar_and_member (a) in
  let scalar_y, member_y = split_scalar_and_member (b) in
  let member_x, member_y =
    match member_x, member_y with
    | Some member_x, Some member_y -> member_x, member_y
    | Some ((x_mutexes,x) as member_x), None ->
        let member_y =
          let y_mutexes = x_mutexes in
          let y = Unprotected.return (Option.extract scalar_y) in
          (y_mutexes, y)
        in
        member_x, member_y
    | None, Some ((y_mutexes,y) as member_y) ->
        let member_x =
          let x_mutexes = y_mutexes in
          let x = Unprotected.return (Option.extract scalar_x) in
          (x_mutexes, x)
        in
        member_x, member_y
    | None, None -> assert false
  in
  let private_a = Option.map (fun _ -> ()) scalar_x in
  let private_b = Option.map (fun _ -> ()) scalar_y in
  product_pair ?on_proposal ?on_commit ?private_a ?private_b member_x member_y

 end (* Product_pair *)

module Tuple2 = struct
 type ('a,'b) t = 'a * 'b
 let prjA (a,b) = a
 let prjB (a,b) = b
 let make a b = (a,b)
end (* Tuple2 *)

let group_pair ?on_proposal ?on_commit (member_x : 'a t) (member_y : 'b t) : ('a * 'b) t =
  let module M = Product_pair (Tuple2) in
  M.product_pair ?on_proposal ?on_commit (member_x) (member_y)

let group_with_scalar ?on_proposal ?on_commit a b : ('a * 'b) t =
  let module M = Product_pair (Tuple2) in
  M.make ?on_proposal ?on_commit a b


module Product_triple
  (Prod : sig
     type ('a,'b,'c) t
     val prjA : ('a,'b,'c) t -> 'a
     val prjB : ('a,'b,'c) t -> 'b
     val prjC : ('a,'b,'c) t -> 'c
     val make : 'a -> 'b -> 'c -> ('a,'b,'c) t
   end)
 =
 struct

 let product_triple
    ?on_proposal ?on_commit
    (member_x1 : 'a t) (member_x2 : 'b t) (member_x3 : 'c t)
  : (('a,'b,'c) Prod.t) t
  =
  let (x1_mutexes, x1) = member_x1 in
  let (x2_mutexes, x2) = member_x2 in
  let (x3_mutexes, x3) = member_x3 in
  let mutexes = Mutex_group.group x1_mutexes [x2_mutexes; x3_mutexes] in
  let equality v =
    let a, b, c = (Prod.prjA v), (Prod.prjB v), (Prod.prjC v) in
    let equals_a = (x1.Unprotected.equality a) in
    let equals_b = (x2.Unprotected.equality b) in
    let equals_c = (x3.Unprotected.equality c) in
    fun v' ->
      let a', b', c' = (Prod.prjA v'), (Prod.prjB v'), (Prod.prjC v') in
      (equals_a a') && (equals_b b') && (equals_c c')
  in
  let proposal () =
    Prod.make
      (x1.Unprotected.get_content ())
      (x2.Unprotected.get_content ())
      (x3.Unprotected.get_content ())
  in
  let x1_bell = Egg.create () in
  let x2_bell = Egg.create () in
  let x3_bell = Egg.create () in
  let group =
    Mutex_group.with_mutex mutexes
      (fun () ->
	let content_copy = ref (proposal ()) in
	let get_content () = !content_copy in
	let rec propose_content v =
	  begin
	    let v1, v2, v3 = (Prod.prjA v), (Prod.prjB v), (Prod.prjC v) in
	    let (v1', b1) = Unprotected.eval_propose v1 x1 in
	    let (v2', b2) = Unprotected.eval_propose v2 x2 in
	    let (v3', b3) = Unprotected.eval_propose v3 x3 in
	    let v' = Prod.make v1' v2' v3' in
	    content_copy := v';
	    v'
	  end
	and
	  result = lazy (make ~mutexes ~equality ?on_proposal ?on_commit ~get_content ~propose_content ())
	in
	let (_, group_u) as group = (Lazy.force result) in
	let membership () = not !(group_u.Unprotected.no_longer_in_use) in
	let trigger_on (bell) (member) =
	  repeat_propose_to_group_on_member_commit
	    ~signal_me_in_critical_section:bell ~membership ~proposal ~group (member)
	in
	let _thd1 = Thread.create (trigger_on x1_bell) (member_x1) in
	let _thd2 = Thread.create (trigger_on x2_bell) (member_x2) in
	let _thd3 = Thread.create (trigger_on x3_bell) (member_x3) in
	group)
  in
  let () = Egg.wait (x1_bell) in
  let () = Egg.wait (x2_bell) in
  let () = Egg.wait (x3_bell) in
  group

 end (* Product_triple *)

let group_triple ?on_proposal ?on_commit
  (member_x1 : 'a t) (member_x2 : 'b t) (member_x3 : 'c t) : ('a * 'b * 'c) t
  =
  let module M =
    Product_triple (
      struct
        type ('a,'b,'c) t = 'a * 'b * 'c
        let prjA (a,b,c) = a
        let prjB (a,b,c) = b
        let prjC (a,b,c) = c
        let make a b c = (a,b,c)
      end)
  in
  M.product_triple ?on_proposal ?on_commit (member_x1) (member_x2) (member_x3)


module Product_quadruple
  (Prod : sig
     type ('a,'b,'c,'d) t
     val prjA : ('a,'b,'c,'d) t -> 'a
     val prjB : ('a,'b,'c,'d) t -> 'b
     val prjC : ('a,'b,'c,'d) t -> 'c
     val prjD : ('a,'b,'c,'d) t -> 'd
     val make : 'a -> 'b -> 'c -> 'd -> ('a,'b,'c,'d) t
   end)
 =
 struct

 let product_quadruple
    ?on_proposal ?on_commit
    (member_x1 : 'a t) (member_x2 : 'b t) (member_x3 : 'c t) (member_x4 : 'd t)
  : (('a,'b,'c,'d) Prod.t) t
  =
  let (x1_mutexes, x1) = member_x1 in
  let (x2_mutexes, x2) = member_x2 in
  let (x3_mutexes, x3) = member_x3 in
  let (x4_mutexes, x4) = member_x4 in
  let mutexes = Mutex_group.group x1_mutexes [x2_mutexes; x3_mutexes; x4_mutexes] in
  let equality v =
    let a, b, c, d = (Prod.prjA v), (Prod.prjB v), (Prod.prjC v), (Prod.prjD v) in
    let equals_a = (x1.Unprotected.equality a) in
    let equals_b = (x2.Unprotected.equality b) in
    let equals_c = (x3.Unprotected.equality c) in
    let equals_d = (x4.Unprotected.equality d) in
    fun v' ->
      let a', b', c', d' = (Prod.prjA v'), (Prod.prjB v'), (Prod.prjC v'), (Prod.prjD v') in
      (equals_a a') && (equals_b b') && (equals_c c') && (equals_d d')
  in
  let proposal () =
    Prod.make
      (x1.Unprotected.get_content ())
      (x2.Unprotected.get_content ())
      (x3.Unprotected.get_content ())
      (x4.Unprotected.get_content ())
  in
  let x1_bell = Egg.create () in
  let x2_bell = Egg.create () in
  let x3_bell = Egg.create () in
  let x4_bell = Egg.create () in
  let group =
    Mutex_group.with_mutex mutexes
      (fun () ->
	let content_copy = ref (proposal ()) in
	let get_content () = !content_copy in
	let rec propose_content v =
	  begin
	    let v1, v2, v3, v4 = (Prod.prjA v), (Prod.prjB v), (Prod.prjC v), (Prod.prjD v) in
	    let (v1', b1) = Unprotected.eval_propose v1 x1 in
	    let (v2', b2) = Unprotected.eval_propose v2 x2 in
	    let (v3', b3) = Unprotected.eval_propose v3 x3 in
	    let (v4', b4) = Unprotected.eval_propose v4 x4 in
	    let v' = Prod.make v1' v2' v3' v4' in
	    content_copy := v';
	    v'
	  end
	and
	  result = lazy (make ~mutexes ~equality ?on_proposal ?on_commit ~get_content ~propose_content ())
	in
	let (_, group_u) as group = (Lazy.force result) in
	let membership () = not !(group_u.Unprotected.no_longer_in_use) in
	let trigger_on (bell) (member) =
	  repeat_propose_to_group_on_member_commit
	    ~signal_me_in_critical_section:bell ~membership ~proposal ~group (member)
	in
	let _thd1 = Thread.create (trigger_on x1_bell) (member_x1) in
	let _thd2 = Thread.create (trigger_on x2_bell) (member_x2) in
	let _thd3 = Thread.create (trigger_on x3_bell) (member_x3) in
	let _thd4 = Thread.create (trigger_on x4_bell) (member_x4) in
	group)
  in
  let () = Egg.wait (x1_bell) in
  let () = Egg.wait (x2_bell) in
  let () = Egg.wait (x3_bell) in
  let () = Egg.wait (x4_bell) in
  group

 end (* Product_quadruple *)

let group_quadruple ?on_proposal ?on_commit
  (member_x1 : 'a t) (member_x2 : 'b t) (member_x3 : 'c t) (member_x4 : 'd t)
  : ('a * 'b * 'c * 'd) t
  =
  let module M =
    Product_quadruple (
      struct
        type ('a,'b,'c,'d) t = 'a * 'b * 'c * 'd
        let prjA (a,b,c,d) = a
        let prjB (a,b,c,d) = b
        let prjC (a,b,c,d) = c
        let prjD (a,b,c,d) = d
        let make a b c d = (a,b,c,d)
      end)
  in
  M.product_quadruple ?on_proposal ?on_commit (member_x1) (member_x2) (member_x3) (member_x4)


module Product_quintuple
  (Prod : sig
     type ('a,'b,'c,'d,'e) t
     val prjA : ('a,'b,'c,'d,'e) t -> 'a
     val prjB : ('a,'b,'c,'d,'e) t -> 'b
     val prjC : ('a,'b,'c,'d,'e) t -> 'c
     val prjD : ('a,'b,'c,'d,'e) t -> 'd
     val prjE : ('a,'b,'c,'d,'e) t -> 'e
     val make : 'a -> 'b -> 'c -> 'd -> 'e -> ('a,'b,'c,'d,'e) t
   end)
 =
 struct

 let product_quintuple
    ?on_proposal ?on_commit
    (member_x1 : 'a t) (member_x2 : 'b t) (member_x3 : 'c t) (member_x4 : 'd t) (member_x5 : 'e t)
  : (('a,'b,'c,'d,'e) Prod.t) t
  =
  let (x1_mutexes, x1) = member_x1 in
  let (x2_mutexes, x2) = member_x2 in
  let (x3_mutexes, x3) = member_x3 in
  let (x4_mutexes, x4) = member_x4 in
  let (x5_mutexes, x5) = member_x5 in
  let mutexes =
    Mutex_group.group x1_mutexes [x2_mutexes; x3_mutexes; x4_mutexes; x5_mutexes]
  in
  let equality v =
    let a, b, c, d, e = (Prod.prjA v), (Prod.prjB v), (Prod.prjC v), (Prod.prjD v), (Prod.prjE v) in
    let equals_a = (x1.Unprotected.equality a) in
    let equals_b = (x2.Unprotected.equality b) in
    let equals_c = (x3.Unprotected.equality c) in
    let equals_d = (x4.Unprotected.equality d) in
    let equals_e = (x5.Unprotected.equality e) in
    fun v' ->
      let a', b', c', d', e' = (Prod.prjA v'), (Prod.prjB v'), (Prod.prjC v'), (Prod.prjD v'), (Prod.prjE v') in
      (equals_a a') && (equals_b b') && (equals_c c') && (equals_d d') && (equals_e e')
  in
  let proposal () =
    Prod.make
      (x1.Unprotected.get_content ())
      (x2.Unprotected.get_content ())
      (x3.Unprotected.get_content ())
      (x4.Unprotected.get_content ())
      (x5.Unprotected.get_content ())
  in
  let x1_bell = Egg.create () in
  let x2_bell = Egg.create () in
  let x3_bell = Egg.create () in
  let x4_bell = Egg.create () in
  let x5_bell = Egg.create () in
  let group =
    Mutex_group.with_mutex mutexes
      (fun () ->
	let content_copy = ref (proposal ()) in
	let get_content () = !content_copy in
	let rec propose_content v =
	  begin
	    let v1, v2, v3, v4, v5 = (Prod.prjA v), (Prod.prjB v), (Prod.prjC v), (Prod.prjD v), (Prod.prjE v) in
	    let (v1', b1) = Unprotected.eval_propose v1 x1 in
	    let (v2', b2) = Unprotected.eval_propose v2 x2 in
	    let (v3', b3) = Unprotected.eval_propose v3 x3 in
	    let (v4', b4) = Unprotected.eval_propose v4 x4 in
	    let (v5', b5) = Unprotected.eval_propose v5 x5 in
	    let v' = Prod.make v1' v2' v3' v4' v5' in
	    content_copy := v';
	    v'
	  end
	and
	  result = lazy (make ~mutexes ~equality ?on_proposal ?on_commit ~get_content ~propose_content ())
	in
	let (_, group_u) as group = (Lazy.force result) in
	let membership () = not !(group_u.Unprotected.no_longer_in_use) in
	let trigger_on (bell) (member) =
	  repeat_propose_to_group_on_member_commit
	    ~signal_me_in_critical_section:bell ~membership ~proposal ~group (member)
	in
	let _thd1 = Thread.create (trigger_on x1_bell) (member_x1) in
	let _thd2 = Thread.create (trigger_on x2_bell) (member_x2) in
	let _thd3 = Thread.create (trigger_on x3_bell) (member_x3) in
	let _thd4 = Thread.create (trigger_on x4_bell) (member_x4) in
	let _thd5 = Thread.create (trigger_on x5_bell) (member_x5) in
	group)
  in
  let () = Egg.wait (x1_bell) in
  let () = Egg.wait (x2_bell) in
  let () = Egg.wait (x3_bell) in
  let () = Egg.wait (x4_bell) in
  let () = Egg.wait (x5_bell) in
  group

 end (* Product_quintuple *)

let group_quintuple ?on_proposal ?on_commit
  (member_x1 : 'a t) (member_x2 : 'b t) (member_x3 : 'c t) (member_x4 : 'd t) (member_x5 : 'e t)
  : ('a * 'b * 'c * 'd * 'e) t
  =
  let module M =
    Product_quintuple (
      struct
        type ('a,'b,'c,'d,'e) t = 'a * 'b * 'c * 'd * 'e
        let prjA (a,b,c,d,e) = a
        let prjB (a,b,c,d,e) = b
        let prjC (a,b,c,d,e) = c
        let prjD (a,b,c,d,e) = d
        let prjE (a,b,c,d,e) = e
        let make a b c d e = (a,b,c,d,e)
      end)
  in
  M.product_quintuple ?on_proposal ?on_commit (member_x1) (member_x2) (member_x3) (member_x4) (member_x5)


module Sum_pair
  (Sum :
     sig
       type ('a,'b) t
       val injA : 'a -> ('a,'b) t
       val injB : 'b -> ('a,'b) t
       val case : ('a,'b) t -> ('a -> 'y) -> ('b -> 'y) -> 'y
     end)
 =
 struct

 (* General tool used to build both injections: *)
 let make
  ?on_proposal
  ?on_commit
  ?initial
  ?(scalar_or_member_A : 'a scalar_or_cortex option)
  ?(scalar_or_member_B : 'b scalar_or_cortex option)
  ()
  : (('a,'b) Sum.t) t
  =
  let split_scalar_and_member = function
  | None -> None, None
  | Some (Either.Left scalar)  -> (Some scalar), None
  | Some (Either.Right member) -> None, (Some member)
  in
  let scalar_x, member_x = split_scalar_and_member (scalar_or_member_A) in
  let scalar_y, member_y = split_scalar_and_member (scalar_or_member_B) in
  let () =
    assert ((member_x <> None) || (member_y <> None))
  in
  let x_mutexes, x_equality, x_move_proposal, x_initial, x_propose_content, x_bell =
    match member_x with
    | None ->
        (* The extraction fails if this component is set to be initial
           but the initial value is not provided: *)
        let x_initial () = Sum.injA (Option.extract scalar_x) in
        None, scalar_equality, Sum.injA, x_initial, Sum.injA, None
    | Some (x_mutexes, x) ->
        let x_equality = x.Unprotected.equality in
        let x_move_proposal = (fun _ -> Sum.injA (x.Unprotected.get_content ())) in
        let x_initial = (fun () -> Sum.injA (x.Unprotected.get_content ())) in
        let x_propose_content = fun a ->
          let a' = fst (Unprotected.eval_propose a x) in
	  (Sum.injA a')
        in
        let x_bell = Some (Egg.create ()) in
        (Some x_mutexes, x_equality, x_move_proposal, x_initial, x_propose_content, x_bell)
  in
  let y_mutexes, y_equality, y_move_proposal, y_initial, y_propose_content, y_bell =
    match member_y with
    | None ->
        (* The extraction fails if this component is set to be initial
           but the initial value is not provided: *)
        let y_initial () = Sum.injB (Option.extract scalar_y) in
        None, scalar_equality, Sum.injB, y_initial, Sum.injB, None
    | Some (y_mutexes, y) ->
        let y_equality = y.Unprotected.equality in
        let y_move_proposal = (fun _ -> Sum.injB (y.Unprotected.get_content ())) in
        let y_initial = (fun () -> Sum.injB (y.Unprotected.get_content ())) in
        let y_propose_content = fun b ->
          let b' = fst (Unprotected.eval_propose b y) in
	  (Sum.injB b')
        in
        let y_bell = Some (Egg.create ()) in
        (Some y_mutexes, y_equality, y_move_proposal, y_initial, y_propose_content, y_bell)
  in
  let mutexes =
    match x_mutexes, y_mutexes with
    | Some x_mutexes, None           -> x_mutexes
    | None          , Some y_mutexes -> y_mutexes
    | Some x_mutexes, Some y_mutexes -> Mutex_group.group x_mutexes [y_mutexes]
    | None, None -> assert false
  in
  let equality v =
    Sum.case v
      (fun a ->
        let equals_a = x_equality a in
        fun v' ->
          Sum.case v'
            (fun a' -> equals_a a')
            (fun _  -> false))
      (fun b ->
        let equals_b = y_equality b in
        fun v' ->
          Sum.case v'
            (fun _  -> false)
            (fun b' -> equals_b b'))
  in
  let move_proposal v =
    Sum.case v (x_move_proposal) (y_move_proposal)
  in
  let group =
    Mutex_group.with_mutex mutexes
      (fun () ->
	let content_copy =
	  (* The initial state is by default the first component: *)
	  let initial_state =
	    let initial = match initial with
	    | Some i -> i
	    | None   -> Sum.injA ()
	    in
	    Sum.case initial (x_initial) (y_initial)
	   in
	  ref initial_state
	in
	let get_content () = !content_copy in
	let rec propose_content v =
	  let v'= Sum.case v (x_propose_content) (y_propose_content) in
	  content_copy := v';
	  v'
	and
	  result = lazy (make ~mutexes ~equality ?on_proposal ?on_commit ~get_content ~propose_content ())
	in
	let (_, group_u) as group = (Lazy.force result) in
	let membership () = not !(group_u.Unprotected.no_longer_in_use) in
	let trigger_on (bell) (member) =
	  repeat_move_proposal_to_group_on_member_commit
	    ~signal_me_in_critical_section:bell ~membership ~move_proposal ~group (member)
	in
	let create_thread_on = fun bell member -> Thread.create (trigger_on bell) (member) in
	let _thd1 = Option.map2 (create_thread_on) (x_bell) (member_x) in
	let _thd2 = Option.map2 (create_thread_on) (y_bell) (member_y) in
	group)
  in
  let () = Option.iter (Egg.wait) x_bell in
  let () = Option.iter (Egg.wait) y_bell in
  group

 let injA ?on_proposal ?on_commit ?b (a: 'a scalar_or_cortex): (('a,'b) Sum.t) t =
   make ?on_proposal ?on_commit
     ~initial:(Sum.injA ())
     ~scalar_or_member_A:a
     ?scalar_or_member_B:(Option.map (Either.right) b)
     ()

 let injB ?on_proposal ?on_commit ?a (b: 'b scalar_or_cortex) : (('a,'b) Sum.t) t =
   make ?on_proposal ?on_commit
     ~initial:(Sum.injB ())
     ?scalar_or_member_A:(Option.map (Either.right) a)
     ~scalar_or_member_B:b
     ()


end (* Sum_pair *)

module Either_cortex = struct
 module M =
    Sum_pair (
      struct
        type ('a,'b) t = ('a,'b) Either.t
        let injA a = Either.Left a
        let injB b = Either.Right b
        let case t left right = match t with
        | Either.Left  a -> left a
        | Either.Right b -> right b
      end)

 let iLeft  ?on_proposal ?on_commit ?right e = M.injA ?on_proposal ?on_commit ?b:right e
 let iRight ?on_proposal ?on_commit ?left  e = M.injB ?on_proposal ?on_commit ?a:left e

 (* Useful to build (encode) n-ary sums.
    The first argument, when provided, is set to be initial: *)
 let inject_two_optional_cortex (x:'a t option) (y:'b t option) : (('a,'b) Either.t) t option =
   match x,y with
   | None, None   -> None
   | Some x, _    -> Some (iLeft  ?right:y   (Either.Right x))
   | None, Some y -> Some (iRight ?left:None (Either.Right y))

end


module Sum_triple
  (Sum : sig
     type ('a,'b,'c) t
     val injA : 'a -> ('a,'b,'c) t
     val injB : 'b -> ('a,'b,'c) t
     val injC : 'c -> ('a,'b,'c) t
     val case : ('a,'b,'c) t -> ('a -> 'y) -> ('b -> 'y) -> ('c -> 'y) -> 'y
   end)
 =
 struct
   (* Original sum type (s) and its implementation with Either (t): *)
   type ('a,'b,'c) s0 = ('a,'b,'c) Sum.t
   type ('a,'b,'c) s1 = ('a, (('b,'c) Either.t)) Either.t

   let s0_of_s1 = function
   | Either.Left a -> Sum.injA a
   | Either.Right (Either.Left b)  -> Sum.injB b
   | Either.Right (Either.Right c) -> Sum.injC c

   let s1_of_s0 x =
    Sum.case x
     (fun a -> Either.Left a)
     (fun b -> Either.Right (Either.Left b))
     (fun c -> Either.Right (Either.Right c))

   let injA ?on_proposal ?on_commit ?(b: 'b t option) ?(c:'c t option) (a: 'a scalar_or_cortex)
     : (('a,'b,'c) Sum.t) t
     =
     let t1 : (('a,'b,'c) s1) t =
       let member_bc = Either_cortex.inject_two_optional_cortex b c in
       Either_cortex.iLeft ?right:member_bc a
     in
     let t0 : (('a,'b,'c) s0) t =
       connection ?on_proposal ?on_commit (s0_of_s1) (s1_of_s0) t1
     in t0

   let injB ?on_proposal ?on_commit ?(a: 'a t option) ?(c:'c t option) (b: 'b scalar_or_cortex)
     : (('a,'b,'c) Sum.t) t
     =
     let t1 : (('a,'b,'c) s1) t =
       let member_bc = Either_cortex.iLeft ?right:c b in
       Either_cortex.iRight ?left:a (Either.Right member_bc)
     in
     let t0 : (('a,'b,'c) s0) t =
       connection ?on_proposal ?on_commit (s0_of_s1) (s1_of_s0) t1
     in t0

   let injC ?on_proposal ?on_commit ?(a: 'a t option) ?(b:'b t option) (c: 'c scalar_or_cortex)
     : (('a,'b,'c) Sum.t) t
     =
     let t1 : (('a,'b,'c) s1) t =
       let member_bc = Either_cortex.iRight ?left:b c in
       Either_cortex.iRight ?left:a (Either.Right member_bc)
     in
     let t0 : (('a,'b,'c) s0) t =
       connection ?on_proposal ?on_commit (s0_of_s1) (s1_of_s0) t1
     in t0

 end

module Sum_quadruple
  (Sum : sig
     type ('a,'b,'c,'d) t
     val injA   : 'a -> ('a,'b,'c,'d) t
     val injB   : 'b -> ('a,'b,'c,'d) t
     val injC   : 'c -> ('a,'b,'c,'d) t
     val injD   : 'd -> ('a,'b,'c,'d) t
     val case   :
       ('a,'b,'c,'d) t ->
       ('a -> 'y) -> ('b -> 'y) -> ('c -> 'y) -> ('d -> 'y) -> 'y
   end)
 =
 struct
   (* Original sum type (s) and its implementation with Either (t): *)
   type ('a,'b,'c,'d) s0 = ('a,'b,'c,'d) Sum.t
   type ('a,'b,'c,'d) s1 = ('a, ('b, (('c,'d) Either.t)) Either.t) Either.t

   let s0_of_s1 = function
   | Either.Left a -> Sum.injA a
   | Either.Right (Either.Left b)  -> Sum.injB b
   | Either.Right (Either.Right (Either.Left c))  -> Sum.injC c
   | Either.Right (Either.Right (Either.Right d)) -> Sum.injD d

   let s1_of_s0 x =
    Sum.case x
     (fun a -> Either.Left a)
     (fun b -> Either.Right (Either.Left b))
     (fun c -> Either.Right (Either.Right (Either.Left c)))
     (fun d -> Either.Right (Either.Right (Either.Right d)))

   let injA ?on_proposal ?on_commit ?(b: 'b t option) ?(c:'c t option) ?(d:'d t option) (a: 'a scalar_or_cortex)
     : (('a,'b,'c,'d) Sum.t) t
     =
     let t1 : (('a,'b,'c,'d) s1) t =
       let member_cd  = Either_cortex.inject_two_optional_cortex c d in
       let member_bcd = Either_cortex.inject_two_optional_cortex b member_cd in
       Either_cortex.iLeft ?right:member_bcd a
     in
     let t0 : (('a,'b,'c,'d) s0) t =
       connection ?on_proposal ?on_commit (s0_of_s1) (s1_of_s0) t1
     in t0

   let injB ?on_proposal ?on_commit ?(a: 'a t option) ?(c:'c t option) ?(d:'d t option) (b: 'b scalar_or_cortex)
     : (('a,'b,'c,'d) Sum.t) t
     =
     let t1 : (('a,'b,'c,'d) s1) t =
       let member_cd  = Either_cortex.inject_two_optional_cortex c d in
       let member_bcd = Either_cortex.iLeft ?right:member_cd b in
       Either_cortex.iRight ?left:a (Either.Right member_bcd)
     in
     let t0 : (('a,'b,'c,'d) s0) t =
       connection ?on_proposal ?on_commit (s0_of_s1) (s1_of_s0) t1
     in t0

   let injC ?on_proposal ?on_commit ?(a: 'a t option) ?(b:'b t option) ?(d:'d t option) (c: 'c scalar_or_cortex)
     : (('a,'b,'c,'d) Sum.t) t
     =
     let t1 : (('a,'b,'c,'d) s1) t =
       let member_cd = Either_cortex.iLeft ?right:d c in
       let member_bcd = Either_cortex.iRight ?left:b (Either.Right member_cd) in
       Either_cortex.iRight ?left:a (Either.Right member_bcd)
     in
     let t0 : (('a,'b,'c,'d) s0) t =
       connection ?on_proposal ?on_commit (s0_of_s1) (s1_of_s0) t1
     in t0

   let injD ?on_proposal ?on_commit ?(a: 'a t option) ?(b:'b t option) ?(c:'c t option) (d: 'd scalar_or_cortex)
     : (('a,'b,'c,'d) Sum.t) t
     =
     let t1 : (('a,'b,'c,'d) s1) t =
       let member_cd = Either_cortex.iRight ?left:c d in
       let member_bcd = Either_cortex.iRight ?left:b (Either.Right member_cd) in
       Either_cortex.iRight ?left:a (Either.Right member_bcd)
     in
     let t0 : (('a,'b,'c,'d) s0) t =
       connection ?on_proposal ?on_commit (s0_of_s1) (s1_of_s0) t1
     in t0

 end (* Sum_quadruple *)

module Sum_quintuple
  (Sum : sig
     type ('a,'b,'c,'d,'e) t
     val injA   : 'a -> ('a,'b,'c,'d,'e) t
     val injB   : 'b -> ('a,'b,'c,'d,'e) t
     val injC   : 'c -> ('a,'b,'c,'d,'e) t
     val injD   : 'd -> ('a,'b,'c,'d,'e) t
     val injE   : 'e -> ('a,'b,'c,'d,'e) t
     val case   :
       ('a,'b,'c,'d,'e) t ->
       ('a -> 'y) -> ('b -> 'y) -> ('c -> 'y) -> ('d -> 'y) -> ('e -> 'y) -> 'y
   end)
 =
 struct
   (* Original sum type (s) and its implementation with Either (t): *)
   type ('a,'b,'c,'d,'e) s0 = ('a,'b,'c,'d,'e) Sum.t
   type ('a,'b,'c,'d,'e) s1 = ('a, ('b, ('c, (('d,'e) Either.t)) Either.t) Either.t) Either.t

   let s0_of_s1 = function
   | Either.Left a -> Sum.injA a
   | Either.Right (Either.Left b)  -> Sum.injB b
   | Either.Right (Either.Right (Either.Left c))  -> Sum.injC c
   | Either.Right (Either.Right (Either.Right (Either.Left d))) -> Sum.injD d
   | Either.Right (Either.Right (Either.Right (Either.Right e))) -> Sum.injE e

   let s1_of_s0 x =
    Sum.case x
     (fun a -> Either.Left a)
     (fun b -> Either.Right (Either.Left b))
     (fun c -> Either.Right (Either.Right (Either.Left c)))
     (fun d -> Either.Right (Either.Right (Either.Right (Either.Left d))))
     (fun e -> Either.Right (Either.Right (Either.Right (Either.Right e))))

   let injA
     ?on_proposal ?on_commit ?(b: 'b t option) ?(c:'c t option) ?(d:'d t option) ?(e:'e t option)
     (a: 'a scalar_or_cortex)
     : (('a,'b,'c,'d,'e) Sum.t) t
     =
     let t1 : (('a,'b,'c,'d,'e) s1) t =
       let member_de   = Either_cortex.inject_two_optional_cortex d e in
       let member_cde  = Either_cortex.inject_two_optional_cortex c member_de in
       let member_bcde = Either_cortex.inject_two_optional_cortex b member_cde in
       Either_cortex.iLeft ?right:member_bcde a
     in
     let t0 : (('a,'b,'c,'d,'e) s0) t =
       connection ?on_proposal ?on_commit (s0_of_s1) (s1_of_s0) t1
     in t0

   let injB ?on_proposal
     ?on_commit ?(a: 'a t option) ?(c:'c t option) ?(d:'d t option) ?(e:'e t option)
     (b: 'b scalar_or_cortex)
     : (('a,'b,'c,'d,'e) Sum.t) t
     =
     let t1 : (('a,'b,'c,'d,'e) s1) t =
       let member_de   = Either_cortex.inject_two_optional_cortex d e in
       let member_cde  = Either_cortex.inject_two_optional_cortex c member_de in
       let member_bcde = Either_cortex.iLeft ?right:member_cde b in
       Either_cortex.iRight ?left:a (Either.Right member_bcde)
     in
     let t0 : (('a,'b,'c,'d,'e) s0) t =
       connection ?on_proposal ?on_commit (s0_of_s1) (s1_of_s0) t1
     in t0

   let injC ?on_proposal
     ?on_commit ?(a: 'a t option) ?(b:'b t option) ?(d:'d t option) ?(e:'e t option)
     (c: 'c scalar_or_cortex)
     : (('a,'b,'c,'d,'e) Sum.t) t
     =
     let t1 : (('a,'b,'c,'d,'e) s1) t =
       let member_de   = Either_cortex.inject_two_optional_cortex d e in
       let member_cde  = Either_cortex.iLeft ?right:member_de c in
       let member_bcde = Either_cortex.iRight ?left:b (Either.Right member_cde) in
       Either_cortex.iRight ?left:a (Either.Right member_bcde)
     in
     let t0 : (('a,'b,'c,'d,'e) s0) t =
       connection ?on_proposal ?on_commit (s0_of_s1) (s1_of_s0) t1
     in t0

   let injD
     ?on_proposal ?on_commit ?(a: 'a t option) ?(b:'b t option) ?(c:'c t option) ?(e:'e t option)
     (d: 'd scalar_or_cortex)
     : (('a,'b,'c,'d,'e) Sum.t) t
     =
     let t1 : (('a,'b,'c,'d,'e) s1) t =
       let member_de   = Either_cortex.iLeft ?right:e d in
       let member_cde  = Either_cortex.iRight ?left:c (Either.Right member_de) in
       let member_bcde = Either_cortex.iRight ?left:b (Either.Right member_cde) in
       Either_cortex.iRight ?left:a (Either.Right member_bcde)
     in
     let t0 : (('a,'b,'c,'d,'e) s0) t =
       connection ?on_proposal ?on_commit (s0_of_s1) (s1_of_s0) t1
     in t0

   let injE
     ?on_proposal ?on_commit ?(a: 'a t option) ?(b:'b t option) ?(c:'c t option) ?(d:'d t option)
     (e: 'e scalar_or_cortex)
     : (('a,'b,'c,'d,'e) Sum.t) t
     =
     let t1 : (('a,'b,'c,'d,'e) s1) t =
       let member_de   = Either_cortex.iRight ?left:d e in
       let member_cde  = Either_cortex.iRight ?left:c (Either.Right member_de) in
       let member_bcde = Either_cortex.iRight ?left:b (Either.Right member_cde) in
       Either_cortex.iRight ?left:a (Either.Right member_bcde)
     in
     let t0 : (('a,'b,'c,'d,'e) s0) t =
       connection ?on_proposal ?on_commit (s0_of_s1) (s1_of_s0) t1
     in t0

 end

let defuse : 'a t -> unit =
  fun (t_mutexes, t) ->
    Mutex_group.with_mutex t_mutexes
      (fun () ->
         t.Unprotected.no_longer_in_use := true;
         Container.Queue_with_identifiers.clear (t.Unprotected.on_proposal#as_queue);
         Container.Queue_with_identifiers.clear (t.Unprotected.on_commit#as_queue);
         (* Wake up threads waiting on this cortex: *)
         Condition.broadcast (t.Unprotected.alert_on_commit);
         ())

module Option_cortex = struct

 let make ?on_proposal ?on_commit ?none (member_x : 'a t) : ('a option) t =
  let (x_mutexes, x) = member_x in
  let mutexes = x_mutexes in
  let equality = function
    | None -> ((=)None)
    | Some a ->
        let equals_a = (x.Unprotected.equality a) in
        (function
         | Some a' -> equals_a a'
         | None -> false
         )
  in
  let move_proposal = function
    | Some _ -> Some (x.Unprotected.get_content ())
    | None   -> None
  in
  let x_bell = Egg.create () in
  let group =
    Mutex_group.with_mutex mutexes
      (fun () ->
	let content_copy =
	  (* The initial state is the first component: *)
	  let initial_state =
	    if none = Some () then None else Some (x.Unprotected.get_content ())
	  in
	  ref initial_state
	in
	let get_content () = !content_copy in
	let rec propose_content v =
	  let v' =
	    match v with
	    | Some a ->
		let a' = fst (Unprotected.eval_propose a x) in
		(Some a')
	    | None -> None
	  in
	  content_copy := v';
	  v'
	and
	  result = lazy (make ~mutexes ~equality ?on_proposal ?on_commit ~get_content ~propose_content ())
	in
	let (_, group_u) as group = (Lazy.force result) in
	let membership () = not !(group_u.Unprotected.no_longer_in_use) in
	let trigger_on (bell) (member) =
	  repeat_move_proposal_to_group_on_member_commit
	    ~signal_me_in_critical_section:bell ~membership ~move_proposal ~group (member)
	in
	let _thd1 = Thread.create (trigger_on x_bell) (member_x) in
	group)
  in
  let () = Egg.wait (x_bell) in
  group

 let iNone ?on_proposal ?on_commit (member_x : 'a t) : ('a option) t =
   make ?on_proposal ?on_commit ~none:() member_x

 let iSome ?on_proposal ?on_commit (member_x : 'a t) : ('a option) t =
   make ?on_proposal ?on_commit (*~none:()*) member_x

end (* Option_cortex *)

let group_array ?on_proposal ?on_commit (members : ('a t) array) : ('a array) t =
  let size = Array.length members in
  if size = 0 then invalid_arg "Cortex.group_array: empty array" else
  let member_list = Array.to_list members in
  let (mutex_list, xs) =
    let (ms, xs) = List.split member_list in
    (ms, Array.of_list xs)
  in
  let mutexes =
    let head = List.hd (mutex_list) in
    let tail = List.tl (mutex_list) in
    Mutex_group.group head tail
  in
  (* Utility for folding boolean results with the logical operator (&&): *)
  let and_foldi f vs =
    let rec loop i =
      if i>=size then true else
      if f i vs.(i)
        then loop (i+1)
        else false (* stop immediately! *)
    in loop 0
  in
(*  let or_foldi f vs =
    let rec loop i =
      if i>=size then false else
      if f i vs.(i)
        then true (* stop immediately! *)
        else loop (i+1)
    in loop 0
  in*)
  let equality vs =
    let equals_v = Array.mapi (fun i v -> xs.(i).Unprotected.equality v) vs in
    and_foldi (fun i v' -> equals_v.(i) v')
  in
  let proposal () = Array.map (fun x -> x.Unprotected.get_content ()) xs in
  let bells = Array.map (fun x -> Egg.create ()) xs in
  let group =
    Mutex_group.with_mutex mutexes
      (fun () ->
	let content_copy = ref (proposal ()) in
	let get_content () = !content_copy in
	let rec propose_content vs =
	  begin
	    let v'b = Array.mapi (fun i v -> Unprotected.eval_propose v xs.(i)) vs in
	    let v' = (Array.map fst v'b) in
	    content_copy := v';
	    v'
	  end
	and
	  result = lazy (make ~mutexes ~equality ?on_proposal ?on_commit ~get_content ~propose_content ())
	in
	let (_, group_u) as group = (Lazy.force result) in
	let membership () = not !(group_u.Unprotected.no_longer_in_use) in
	let trigger_on (bell) (member) =
	  repeat_propose_to_group_on_member_commit
	    ~signal_me_in_critical_section:bell ~membership ~proposal ~group (member)
	in
	let _threads = Array.mapi (fun i x -> Thread.create (trigger_on bells.(i)) x) members in
	group)
  in
  let () = Array.iter (Egg.wait) bells in
  group


let sum_array ?on_proposal ?on_commit (members : ('a t) array) : (int * 'a) t =
  let size = Array.length members in
  if size = 0 then invalid_arg "Cortex.sum_array: empty array" else
  let member_list = Array.to_list members in
  let (mutex_list, xs) =
    let (ms, xs) = List.split member_list in
    (ms, Array.of_list xs)
  in
  let mutexes =
    let head = List.hd (mutex_list) in
    let tail = List.tl (mutex_list) in
    Mutex_group.group head tail
  in
  let equality (i,a) =
    let equals_a = (xs.(i).Unprotected.equality a) in
    (fun (j,a') -> i=j (* a sum is disjoint union! *) && equals_a a')
  in
  (* At any time, all triggers except one notify changes that will be ignored.
     Actually, only the trigger of the currently enable component causes a
     call to the `get_content' of its related component. The others triggers
     provoke a re-read of the currently enable component... *)
  let move_proposal (i,_) = (i, xs.(i).Unprotected.get_content ()) in
  let bells = Array.map (fun x -> Egg.create ()) xs in
  let group =
    Mutex_group.with_mutex mutexes
      (fun () ->
        (* The initial state is the first component: *)
	let content_copy = ref (0, xs.(0).Unprotected.get_content ()) in
	let get_content () = !content_copy in
	let rec propose_content (i,a) =
	  begin
	    let (a', changed) = Unprotected.eval_propose a xs.(i) in
	    let v' = (i,a') in
	    content_copy := v';
	    v'
	  end
	and
	  result = lazy (make ~mutexes ~equality ?on_proposal ?on_commit ~get_content ~propose_content ())
	in
	let (_, group_u) as group = (Lazy.force result) in
	let membership () = not !(group_u.Unprotected.no_longer_in_use) in
	let trigger_on (bell) (member) =
	  repeat_move_proposal_to_group_on_member_commit
	    ~signal_me_in_critical_section:bell ~membership ~move_proposal ~group (member)
	in
	let _threads = Array.mapi (fun i x -> Thread.create (trigger_on bells.(i)) x) members in
	group)
  in
  let () = Array.iter (Egg.wait) bells in
  group


module Tools = struct

  let lift_equality_to_option : ('a -> 'b -> bool) -> ('a option -> 'b option -> bool) =
  fun p ->
  function
  | None   -> ((=)None)
  | Some a -> (function None -> false | Some b -> (p a b))

end (* Tools *)

module Open = struct
  type 'a neg = Mutex_group.t -> 'a

  let return
    ?(equality:('state -> 'state -> bool) option)
    ?(on_proposal:('state -> 'state -> 'state) option)
    ?(on_commit:('state -> 'state -> unit) option)
    (content:'state)
    : ('a t) neg
    =
    fun mutexes ->
      let cell = ref content in
      let get_content () = !cell in
      let set_content v = (cell := v) in
      make ~mutexes ?equality ?on_proposal ?on_commit ~get_content ~set_content ()

  let of_unprotected (u : 'a Unprotected.t) : 'a t neg =
    fun mutexes -> (mutexes, u)

  let close ?mutexes (f:'a neg) : 'a =
    let mutexes =
      match mutexes with
      | None         -> Mutex_group.single ()
      | Some mutexes -> mutexes
    in
    (f mutexes)

  let group_pair ?on_proposal ?on_commit (x1 : 'a t neg) (x2 : 'b t neg)
    : ('a t * 'b t * ('a * 'b) t) neg
    = fun mutexes ->
        let x1 = close ~mutexes x1 in
        let x2 = close ~mutexes x2 in
        let group = group_pair ?on_proposal ?on_commit x1 x2 in
        (x1, x2, group)

  let group_triple ?on_proposal ?on_commit (x1 : 'a t neg) (x2 : 'b t neg) (x3 : 'c t neg)
    : ('a t * 'b t * 'c t * ('a * 'b * 'c) t) neg
    = fun mutexes ->
        let x1 = close ~mutexes x1 in
        let x2 = close ~mutexes x2 in
        let x3 = close ~mutexes x3 in
        let group = group_triple ?on_proposal ?on_commit x1 x2 x3 in
        (x1, x2, x3, group)

  let group_quadruple ?on_proposal ?on_commit (x1 : 'a t neg) (x2 : 'b t neg) (x3 : 'c t neg) (x4 : 'd t neg)
    : ('a t * 'b t * 'c t * 'd t * ('a * 'b * 'c * 'd) t) neg
    = fun mutexes ->
        let x1 = close ~mutexes x1 in
        let x2 = close ~mutexes x2 in
        let x3 = close ~mutexes x3 in
        let x4 = close ~mutexes x4 in
        let group = group_quadruple ?on_proposal ?on_commit x1 x2 x3 x4 in
        (x1, x2, x3, x4, group)

  let group_quintuple ?on_proposal ?on_commit
      (x1 : 'a t neg) (x2 : 'b t neg) (x3 : 'c t neg) (x4 : 'd t neg) (x5 : 'e t neg)
    : ('a t * 'b t * 'c t * 'd t * 'e t * ('a * 'b * 'c * 'd * 'e) t) neg
    = fun mutexes ->
        let x1 = close ~mutexes x1 in
        let x2 = close ~mutexes x2 in
        let x3 = close ~mutexes x3 in
        let x4 = close ~mutexes x4 in
        let x5 = close ~mutexes x5 in
        let group = group_quintuple ?on_proposal ?on_commit x1 x2 x3 x4 x5 in
        (x1, x2, x3, x4, x5, group)

  let group_array ?on_proposal ?on_commit (members : ('a t neg) array)
  : (('a t array) * ('a array) t) neg
  = fun mutexes ->
      let members = Array.map (close ~mutexes) members in
      let group = group_array ?on_proposal ?on_commit members in
      (members, group)

  let sum_array ?on_proposal ?on_commit (members : ('a t neg) array)
  : (('a t array) * (int * 'a) t) neg
  = fun mutexes ->
      let members = Array.map (close ~mutexes) members in
      let sum = sum_array ?on_proposal ?on_commit members in
      (members, sum)


  module Product_pair
    (Prod : sig
      type ('a,'b) t
      val prjA : ('a,'b) t -> 'a
      val prjB : ('a,'b) t -> 'b
      val make : 'a -> 'b -> ('a,'b) t
    end)
  =
  struct
    let product_pair ?on_proposal ?on_commit (x1 : 'a t neg) (x2 : 'b t neg)
      : ('a t * 'b t * (('a,'b) Prod.t) t) neg
      = fun mutexes ->
	  let x1 = close ~mutexes x1 in
	  let x2 = close ~mutexes x2 in
	  let prod =
	    let module M = Product_pair (Prod) in
	    M.product_pair ?on_proposal ?on_commit x1 x2
	  in
	  (x1, x2, prod)
  end

  (* Redefinition (user version): *)
  let close f = close f
  type 'a opn = 'a neg

  (* Open.lifes.
     Note that the ~proposal may act on the member which has the same mutexes of the group
    => mutexes must be recursive! *)
  let lifes
    ?on_proposal
    ?on_commit
    ~(creator : ?previous:'a -> unit -> 'a t neg)
    ~(terminal : 'a -> bool)
    ()
    : ('a option * 'a t) t neg
    =
    fun mutexes ->
      let equality (ao, at) =
	let au = snd at in
	let equals_to_ao = Tools.lift_equality_to_option (au.Unprotected.equality) (ao) in
	let equals_to_at =
	  let p = Unprotected.revno_equality au in
	  fun at' -> p (snd at')
	in
	fun (ao', at') -> (equals_to_ao ao') && (equals_to_at at')
      in
      let new_member ?previous () =
	(* same mutexes of the group *)
	creator ?previous () mutexes
      in
      let member = new_member () in
      let (_, group_u) as group =
	(*Open.*)return ~equality ?on_proposal ?on_commit (None, member) mutexes
      in
      let membership_of member () =
	let (_, member') = group_u.Unprotected.get_content () in
	member' == member
      in
      let rec
	(* A new member is proposed when the previous reaches a terminal state: *)
	guard (_, member) =
	  let (member_m, member_u) = member in
	  let member_state = member_u.Unprotected.get_content () in
	  terminal (member_state)
      and
	move_proposal (_, member) =
	  let old_member_state = (snd member).Unprotected.get_content () in
	  let member' = new_member ~previous:old_member_state () in
	  ((Some old_member_state), member')
      and
	(* The current thread must be stopped if we are working now on another member.
	  These parameter is redundant because of the usage of ~membership: *)
	action_and_break_decision_when_accepted s0 s1 s2 =
	  (* s0, s1, s2  =  before, proposed, after *)
	  let break =
	    let (_, member0),(_, member2) = s0, s2 in
	    member0 != member2
	  in
	  break
      and
	trigger_on (member) =
	  repeat_move_proposal_to_group_on_member_commit
	    ~membership:(membership_of member)
	    ~guard
	    ~action_and_break_decision_when_accepted
	    ~move_proposal
	    ~group
	    (member)
      (* end of recursive definition *)
      in
      (* Now we start the first thread monitoring the current member: *)
      let _thd1 = Thread.create (trigger_on) member in
      (* And we define a callback preventing to set the group with a member already terminated.
	The `set' operation applied to a group could be very unsafe if we are not sure that
	the mutexes of the member are contained in the mutexes of the group. We prevent
	this problem using exclusively the `creator' function to build members. *)
      let _thunk_id =
	let mutexes_and_members_are_the_same (_, member0) (_, member1) : bool * bool =
	  let (member0_mutexes, member0_unp) = member0 in
	  let (member1_mutexes, member1_unp) = member1 in
	  (member0_mutexes = member1_mutexes), (member0_unp == member1_unp)
	in
	on_proposal_append (group)
	(fun s0 s1 ->
	  let s2 = if guard s1 then move_proposal s1 else s1 in
	  let same_mutexes, same_members = mutexes_and_members_are_the_same s0 s2 in
	  (* Proposal with distinct mutexes are forbidden: *)
	  if not (same_mutexes) then s0 else
	  (* Start a monitoring thread if a new member replace the previous: *)
	  let () =
	    if same_members then ()
	    else begin
	      let member' = snd s2 in
	      let _thd = Thread.create (trigger_on) member' in
	      ()
	      end
	  in
	  s2)
      in
      group

end (* Open *)

type 'a u = 'a t Open.neg

(* Note that the ~proposal may act on the member which has the same mutexes of the group
   => mutexes must be recursive! *)
let lifes
  ?on_proposal
  ?on_commit
  ~(creator : ?previous:'a -> unit -> 'a u)
  ~(terminal : 'a -> bool)
  ()
  : ('a option * 'a t) t
  =
  let mutexes = Mutex_group.single () in
  Open.lifes ?on_proposal ?on_commit ~creator ~terminal () mutexes


module Object = struct

class type ['a] public_interface = object
  method cortex_t : 'a t
  method eval     : 'b 'c. ?guard:('a -> bool) -> ('a -> 'b -> 'a * ('a -> 'c)) -> 'b -> 'c * bool
  method get      : ?guard:('a -> bool) -> unit -> 'a
  method set      : ?guard:('a -> bool) -> 'a -> unit
  method propose  : ?guard:('a -> bool) -> 'a -> 'a * bool
  method move     : ?guard:('a -> bool) -> ('a -> 'a) -> 'a * bool
  method async    : <
    set  : ?guard:('a -> bool) -> 'a -> unit;
    move : ?guard:('a -> bool) -> ('a -> 'a) -> unit;
    >
end

class type ['a] private_interface = object
  method private cortex_t : 'a t
  method private eval     : 'b 'c. ?guard:('a -> bool) -> ('a -> 'b -> 'a * ('a -> 'c)) -> 'b -> 'c * bool
  method private get      : ?guard:('a -> bool) -> unit -> 'a
  method private set      : ?guard:('a -> bool) -> 'a -> unit
  method private propose  : ?guard:('a -> bool) -> 'a -> 'a * bool
  method private move     : ?guard:('a -> bool) -> ('a -> 'a) -> 'a * bool
  method private async    : <
    set  : ?guard:('a -> bool) -> 'a -> unit;
    move : ?guard:('a -> bool) -> ('a -> 'a) -> unit;
    >
end

class ['a] with_public_interface (x:'a t) =
  object
    method cortex_t : 'a t = x

    method eval : 'b 'c. ?guard:('a -> bool) -> ('a -> 'b -> 'a * ('a -> 'c)) -> 'b -> 'c * bool =
      fun ?guard f b -> eval ?guard f b x

    method get : ?guard:('a -> bool) -> unit -> 'a =
      fun ?guard () -> get ?guard x

    method set : ?guard:('a -> bool) -> 'a -> unit =
      fun ?guard v -> set ?guard x v

    method propose : ?guard:('a -> bool) -> 'a -> 'a * bool =
      fun ?guard v -> propose ?guard x v

    method move : ?guard:('a -> bool) -> ('a -> 'a) -> 'a * bool =
      fun ?guard f -> move ?guard x f

    method async =
      object
	method set : ?guard:('a -> bool) -> 'a -> unit =
	  fun ?guard v -> Async.set ?guard x v

	method move : ?guard:('a -> bool) -> ('a -> 'a) -> unit =
	  fun ?guard f -> Async.move ?guard x f
      end
  end

class ['a] with_private_interface (x:'a t) =
  object
    method private cortex_t : 'a t = x

    method private eval : 'b 'c. ?guard:('a -> bool) -> ('a -> 'b -> 'a * ('a -> 'c)) -> 'b -> 'c * bool =
      fun ?guard f b -> eval ?guard f b x

    method private get : ?guard:('a -> bool) -> unit -> 'a =
      fun ?guard () -> get ?guard x

    method private set : ?guard:('a -> bool) -> 'a -> unit =
      fun ?guard v -> set ?guard x v

    method private propose : ?guard:('a -> bool) -> 'a -> 'a * bool =
      fun ?guard v -> propose ?guard x v

    method private move : ?guard:('a -> bool) -> ('a -> 'a) -> 'a * bool =
      fun ?guard f -> move ?guard x f

    method private async =
      object
	method set : ?guard:('a -> bool) -> 'a -> unit =
	  fun ?guard v -> Async.set ?guard x v

	method move : ?guard:('a -> bool) -> ('a -> 'a) -> unit =
	  fun ?guard f -> Async.move ?guard x f
      end
  end

let with_public_interface  : 'a t -> 'a public_interface =
  fun x -> new with_public_interface x

let with_private_interface : 'a t -> 'a private_interface =
  fun x -> new with_private_interface x

end (* Object *)

IFDEF DOCUMENTATION_OR_DEBUGGING THEN
module Make_Examples (Void:sig end) = struct
module Example1 = struct

let x = return 42 ;;
let y = return 10 ;;
let z = group_pair x y ;;
let w = Either_cortex.iLeft ~right:y (Either.Right x) ;;
let s = sum_array [| x; x; y; y |] ;;
propose x 5 ;;

(* Uncomment the following lines in order to follow the stabilization of resistences: *)
 on_commit_append x
  (fun x0 x1 -> Printf.kfprintf flush stderr "x changed from %d to %d\n" x0 x1) ;;

on_proposal_append x
  (fun x0 x1 -> Printf.kfprintf flush stderr "proposed to change x from %d to %d\n" x0 x1; Thread.delay 0.5; x1) ;;

on_proposal_append y
  (fun y0 y1 -> Printf.kfprintf flush stderr "proposed to change y from %d to %d\n" y0 y1; Thread.delay 0.5; y1) ;;

on_proposal_append z
  (fun (x0,y0) (x1,y1) -> Printf.kfprintf flush stderr "proposed to change z from (%d,%d) to (%d,%d)\n" x0 y0 x1 y1;
    Thread.delay 0.5; (x1,y1)) ;;

let even x = (x mod 2 = 0) ;;

let must_be_natural_or_abs =
  fun _x0 x1 -> if x1<0 then (abs x1) else x1 ;;

let must_be_odd_or_decrement =
  fun _x0 x1 -> if even x1 then x1-1 else x1 ;;

let must_be_even_or_increment =
  fun _x0 x1 -> if even x1 then x1 else x1+1 ;;

let snd_must_be_double_of_fst_or_move_away =
  fun (x0,y0) ((x1,y1) as ok) ->
     if (y1 = 2 * x1) then ok else
     if (x1 <> x0) then (x1, x1*2) else
     let y2 = if (even y1) then y1 else y1+1 in
     let x2 = y2/2 in
     (* Prevent cycles: *)
     if (x0 = x2 || y0 = y2) then (x0,y0) else (x2,y2)
     ;;

(* x must be natural and odd: *)
on_proposal_append x (must_be_natural_or_abs) ;;
on_proposal_append x (must_be_odd_or_decrement) ;;

(* y must be natural and even: *)
on_proposal_append y (must_be_natural_or_abs) ;;
on_proposal_append y (must_be_even_or_increment) ;;

(* z = (x,y) requires that y will be the double of x *)
on_proposal_append z (snd_must_be_double_of_fst_or_move_away) ;;

(*
get z ;;
 : int * int = (5, 10)

get w ;;
 : (int, int) Either.t = Either.Left 42

propose x 50 ;;
 : int * bool = (51, true)

get z ;;
 : int * int = (51, 102)

propose x 52 ;;
 : int * bool = (53, true)

get z ;;
 : int * int = (53, 106)

propose y 107 ;;
 : int * bool = (108, true)

get z ;;
 : int * int = (55, 110)


*)

module Triad = struct

  type ('a,'b,'c) t =
  | Apollo of 'a  (* god of the sun, culture and music *)
  | Athena of 'b  (* goddess of war and intellect *)
  | Zeus   of 'c  (* king of the gods *)

  let injA a = Apollo a
  let injB b = Athena b
  let injC c = Zeus c
  let case t f1 f2 f3 =
   match t with
   | Apollo a -> f1 a
   | Athena b -> f2 b
   | Zeus   c -> f3 c

end;; (* Triad *)

module Triad_cortex = Sum_triple (Triad) ;;

let apollo ?zeus   ?athena = Triad_cortex.injA ?b:athena ?c:zeus ;;
let athena ?zeus   ?apollo = Triad_cortex.injB ?a:apollo ?c:zeus ;;
let zeus   ?athena ?apollo = Triad_cortex.injC ?a:apollo ?b:athena ;;

let t = zeus ~athena:x ~apollo:y (scalar "ciao")  ;;

(*
get t ;;
  : (int, int, string) Triad.t = Triad.Zeus "ciao"

propose t (Triad.Apollo 100) ;;
  : (int, int, string) Triad.t * bool = (Triad.Apollo 100, true)    <===================== PROBLEMA DELLA connection (indipendente dal target)!!

get t ;;
  : (int, int, string) Triad.t = Triad.Apollo 98

*)

end (* module Example1 *)

module Example2 = struct

let x = lifes ~creator:(fun ?previous () -> Open.return 42) ~terminal:((>=)0) () ;;
(* val x : (int option * int Cortex.t) Cortex.t = <abstr> *)

let look x = get (snd (get x)) ;;
(* val look : ('a * 'b Cortex.t) Cortex.t -> 'b = <fun> *)

let member x = snd (get x) ;;
(* val member : ('a * 'b Cortex.t) Cortex.t -> 'b Cortex.t = <fun> *)

let y = member x ;;
(* val y : int Cortex.t = <abstr> *)

get y ;;
(* - : int = 42 *)

set y 10;;
(* - : unit = () *)

look x ;;
(* - : int = 10 *)

set y 20;;
(* - : unit = () *)

look x ;;
(* - : int = 20 *)

set y 0;;
(* - : unit = () *)

look x ;;
(* - : int = 42 *)

get x ;;
(* - : int option * int Cortex.t = (Some 0, <abstr>) *)

set y (-11);;
(* - : unit = () *)

get x ;;
(* - : int option * int Cortex.t = (Some 0, <abstr>) *)

look x ;;
(* - : int = 42 *)

let z = return 33 ;;
(* val z : int Cortex.t = <abstr> *)

propose x (None, z) ;;
(* - : (int option * int Cortex.t) * bool = ((Some 0, <abstr>), false) *)

propose x (None, y) ;;
(* - : (int option * int Cortex.t) * bool = ((Some (-11), <abstr>), true) *)

look x;;
(* - : int = 42 *)

set y 11 ;;
(* - : unit = () *)

propose x (None, y) ;;
(* - : (int option * int Cortex.t) * bool = ((None, <abstr>), true) *)

look x;;
(* - : int = 11 *)

set y (-11) ;;

look x;;
(* - : int = 42 *)
end
end (* functor Make_Examples *)
ENDIF


(* Renaming: *)
type ('a,'b) either = ('a,'b) Either.t
module Either = Either_cortex;;
module Option = Option_cortex;;
