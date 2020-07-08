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

(** Thread-safe deferred computations. *)

(* -------------------- *)
(*        Tools         *)
(* -------------------- *)

(* --- *)
IFDEF DOCUMENTATION_OR_DEBUGGING THEN
  module Log = Ocamlbricks_log
  DEFINE DEBUGGING(x)=x
ELSE
  DEFINE DEBUGGING(x)=()
ENDIF

module Tools = struct

  (* (from MutexExtra:) val with_mutex : ?verbose:unit -> Mutex.t -> (unit -> 'a) -> 'a  *)
  let with_mutex (mutex) (thunk) =
    Mutex.lock mutex;
    try
      let result = thunk () in
      Mutex.unlock mutex;
      result
    with e ->
      (Mutex.unlock mutex; raise e)

   let get_thread_id () =
      Thread.id (Thread.self ())

end (* Tools *)

(* -------------------- *)
(*         Type         *)
(* -------------------- *)

(* Note that 'c is the type of 'a projections, if any: *)
type 'a t = {
  mutex  : Mutex.t;
  source : 'a lazy_t;
  mutable target : 'a binding;
  }
 (* --- *)
 and 'a binding =
   | Unforced
   | Forced of (exn, 'a) Either.t

(* -------------------- *)
(*    Constructors      *)
(* -------------------- *)

(* val make : (unit -> 'a) -> 'a t *)
let make (thunk) : 'a t =
  let mutex = Mutex.create () in
  let source = Lazy.from_fun (thunk) in
  let target = Unforced in
  {mutex; source; target}

(* Alias: *)
let from_fun = make

(* -------------------- *)
(*      Methods         *)
(* -------------------- *)

let force_protected (t : 'a t) : (exn, 'a) Either.t =
  (* --- *)
  Tools.with_mutex (t.mutex) (fun () ->
    match t.target with
    (* --- *)
    | Unforced ->
        (* Do computation within the protected section: other threads trying to access to the channel
            will wake-up at the end of this work, when the channel will be released: *)
        let y = Either.protect (Lazy.force) (t.source) in
        let () = (t.target <- Forced y) in
        y
    (* --- *)
    | Forced y -> y
    )

let is_val (t: 'a t) : bool =
  Tools.with_mutex (t.mutex) (fun () ->
    match t.target with
    | Forced (Either.Right _) -> true
    | _ -> false
    )

let is_forced (t: 'a t) : bool =
  Tools.with_mutex (t.mutex) (fun () ->
    match t.target with
    | Forced _ -> true
    | _ -> false
    )

let extract_forced (t: 'a t) : (exn, 'a) Either.t =
  Tools.with_mutex (t.mutex) (fun () ->
    match t.target with
    | Forced y -> y
    | _ -> assert false
    )

let taste (t: 'a t) : ((exn, 'a) Either.t) option =
  Tools.with_mutex (t.mutex) (fun () ->
    match t.target with
    | Forced y -> Some y
    | Unforced -> None
    )

let force t =
  force_protected t |> Either.extract_or_raise

let force_opt t =
  force_protected t |> Either.to_option
