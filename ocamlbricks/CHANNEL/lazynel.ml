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

(** Thread-safe deferred computations as algebraic channels. *)

(* Basic tools: *)

let get_thread_id () =
   Thread.id (Thread.self ())

(* -------------------- *)
(*   Unprotected Core   *)
(* -------------------- *)

module Core = struct

  (* Note that 'c is the type of 'a projections, if any: *)
  type 'a t = {
    source : 'a lazy_t;
    target : 'a status;
    }
  (* --- *)
  and 'a status =
    | Unforced
    | Work_in_progress of thread_id * ('a hublet) lazy_t
    | Forced of (exn, 'a) Either.t
  (* --- *)
  and thread_id = int
  and 'a hublet = ((exn, 'a) Either.t) Hublet.t

  type ownership = bool

  (* -------------------- *)
  (*    Constructor       *)
  (* -------------------- *)

  (* val make : (unit -> 'a) -> 'a t *)
  let make (thunk) : 'a t =
    let source = Lazy.from_fun (thunk) in
    let target = Unforced in
    {source; target}

  (* -------------------- *)
  (*       Methods        *)
  (* -------------------- *)

  let try_to_take_ownership_or_force_hublet (t : 'a t) : 'a t =
    (* --- *)
    match t.target with
    (* --- *)
    (* This thread takes the ownership and responsibility to compute the value: *)
    | Unforced ->
        let workinprogress = Work_in_progress (get_thread_id (), lazy (Hublet.create ())) in
        { t with target = workinprogress}
    (* --- *)
    (* NOTE: another thread is computing the value => force the hublet that will be used by this thread.
       In this way, the owner will know that other threads are waiting for the result: *)
    | Work_in_progress (thread_id, hublet) when (not (Lazy.is_val hublet)) ->
        let _ = Lazy.force hublet in
        t
    (* --- *)
    | _ -> t

 let set_value (y: (exn, 'a) Either.t) (t: 'a t) : 'a t =
    { t with target = Forced y }

  let ownership (t: 'a t) : ownership (*bool*) =
    match t.target with
    | Work_in_progress (thread_id, _hublet) -> (thread_id = get_thread_id ())
    | _ -> false

  let is_val (t: 'a t) : bool =
    match t.target with
    | Forced (Either.Right _) -> true
    | _ -> false

  let is_forced (t: 'a t) : bool =
    match t.target with Forced _ -> true | _ -> false

  let is_unforced (t: 'a t) : bool =
    match t.target with Unforced -> true | _ -> false

  let extract_forced (t: 'a t) : (exn, 'a) Either.t =
    match t.target with Forced y -> y | _ -> assert false

  let to_option (t: 'a t) : ((exn, 'a) Either.t) option =
    match t.target with
    | Forced y -> Some y
    | _ -> None

  let status_to_option (s: 'a status) : ((exn, 'a) Either.t) option =
    match s with
    | Forced y -> Some y
    | _ -> None

  let is_status_forced (s: 'a status) : bool =
    match s with Forced _ -> true | _ -> false

end (* Core *)

(* -------------------- *)
(*   Protected channel  *)
(* -------------------- *)

(* The channel may be empty or it may contain a message: *)
type 'a t = ('a Core.t) Channel.t
 and 'a core = 'a Core.t

let create (thunk) = Channel.create (Core.make (thunk))
let from_fun = create

(* -------------------- *)
(*       Methods        *)
(* -------------------- *)

(* val get_or_compute_image : 'a t -> (exn, 'a) Either.t *)
let force_or_wait_value ?reuse (t: 'a t) : (exn, 'a) Either.t =
  (* --- *)
  let (suspension, status, ownership), t' =
    match reuse with
    | None ->
       (* The simplest solution is the non-deterministic choice: *)
       Channel.Control.access ~level:(Channel.writer) ~update:(Core.try_to_take_ownership_or_force_hublet) (t) (fun _core0 core1 ->
         (core1.Core.source, core1.Core.target, Core.ownership core1)
         ) |> Either.extract_or_raise
       (* --- *)
    | Some () ->
       (* Find something already forced or in-progress in the disjunction: *)
       Channel.Control.access_with_find
          ~level:(Channel.writer) ~update:(Core.try_to_take_ownership_or_force_hublet) (t) (fun c -> not (Core.is_unforced c)) (fun _core0 core1 found ->
          match found with
          | None                       -> (core1.Core.source, core1.Core.target, Core.ownership core1)
          | Some forced_or_in_progress -> (forced_or_in_progress.Core.source, forced_or_in_progress.Core.target, false)
          ) |> Either.extract_or_raise
       (* --- *)
  in
  (* Note that t (or more precisely t') is released here. *)
  match status with
  (* --- *)
  | Core.Forced y -> y
  (* --- *)
  | Core.Work_in_progress (thread_id, hublet) when (not ownership) ->
      Hublet.receive (Lazy.force hublet)
  (* --- *)
  | Core.Work_in_progress (thread_id, hublet) (* when ownership *) ->
      (* The thread is the owner and responsible of the value computation, so: *)
      (* --- *)
      (* Do computation out of protected section (because of ownership): *)
      let y = Either.protect (Lazy.force) (suspension) in
      (* --- *)
      (* Access now as maintainer to the same structure acquired below (t', not t): *)
      let hublet_created : bool =
        Channel.access ~level:(Channel.maintainer) ~update:(Core.set_value y) (Lazy.force t') (fun _ _ ->
          (* This test must be done in the protected section, not out:
             Are there some threads waiting for the value? *)
          Lazy.is_val hublet
          )
      in
      (* --- *)
      let () = if hublet_created then
        Hublet.send (Lazy.force hublet) y
      in
      y
  (* --- *)
  | Core.Unforced -> assert false


(* val force : ?reuse:unit -> 'a t -> 'a *)
let force ?reuse t =
  force_or_wait_value ?reuse t |> Either.extract_or_raise

(* val force_opt : ?reuse:unit -> 'a t -> 'a option *)
let force_opt ?reuse t =
  force_or_wait_value ?reuse t |> Either.to_option

(* val wait : 'a t -> 'a *)
let wait t =
  Channel.access ~level:(Channel.reader) ~enter:(Core.is_forced) (t) (fun _ -> Core.extract_forced)
    |> Either.extract_or_raise

(* val wait_opt : 'a t -> 'a option *)
let wait_opt t =
  Channel.access ~level:(Channel.reader) ~enter:(Core.is_forced)  (t) (fun _ -> Core.extract_forced)
    |> Either.to_option

(* val is_val : 'a t -> bool *)
let is_val t =
  Channel.exists (t) (Core.is_val)

(* val is_forced : 'a t -> bool *)
let is_forced t =
  Channel.exists (t) (Core.is_forced)

(* val is_unforced : 'a t -> bool *)
let is_unforced t =
  Channel.for_all (t) (Core.is_unforced)

(* val taste : 'a t -> ((exn, 'a) Either.t) option *)
let taste t =
  Channel.fold (t) (Core.Unforced) (fun s lcore -> if Core.is_status_forced s then s else max s (Lazy.force lcore).Core.target)
    |> Core.status_to_option

