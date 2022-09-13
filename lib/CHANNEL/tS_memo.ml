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

(** Thread-safe weak memoization, with or without projections
    (for uncurried functions with several arguments). *)

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

(* Note that 'c is the type of 'a projections, if any: *)
type ('a,'b,'c) book = {
  mutex    : Mutex.t;
  table_ab : ('a, ('a,'b) binding) Table.t;
  table_ca : (('a -> 'c) * ('c, 'a) Table.t) option;
  }
 (* --- *)
 and ('a,'b) binding =
   | Work_in_progress of thread_id * ('b Hublet.t) lazy_t
   | Finished of 'b
 (* --- *)
 and thread_id = int
 and ownership = bool

(* val make : ?identifier:('a -> int) -> ?equality:('a -> 'a -> bool) -> ?size:int -> ?prj:('a -> 'c) -> unit -> ('a, 'b, 'c) book *)
let make ?identifier ?equality ?size ?(prj:('a -> 'c) option) () : ('a,'b,'c) book =
  let mutex = Mutex.create () in
  let table_ab = Table.make ~weak:() (* ephemerons *) ?identifier ?equality ?size () in
  (* Physical equality for projections: *)
  let table_ca = Flip.flip (Option.map) (prj) (fun prj ->
    prj, (Table.make ~weak:() (* ephemerons *) ~equality:(==) ?size ())
    )
  in
  {mutex; table_ab; table_ca}

(* val get_image_or_ownership : ('a, 'b, 'c) book -> 'a -> ('a, 'b) binding * ownership
   Note that: ownership <=> not found in the book
   *)
let get_image_or_ownership (book : ('a,'b,'c) book) (x:'a) : ('a,'b) binding * (ownership) =
  let my_thread_id = lazy (Tools.get_thread_id ()) in
  (* --- *)
  Tools.with_mutex (book.mutex) (fun () ->
    let result = book.table_ab#find_or_bind (x) (lazy (Work_in_progress (Lazy.force my_thread_id, lazy (Hublet.create ())))) in
    (* Force the creation of the hublet in this critical section, if necessary: *)
    let ownership = Lazy.is_val (my_thread_id) in (* bound => is_val => ownership *)
    let () =
      (if not ownership then match result with
        | Work_in_progress (thread_id, hublet) when (not (Lazy.is_val hublet)) -> (Lazy.force hublet |> ignore)
        | _ -> ()
        )
    in
    result, ownership
    )

(* val set_image : finally:(unit -> 'result) -> ('a, 'b, 'c) book -> 'a -> 'b -> 'result *)
let set_image ~(finally: unit -> 'result) (book : ('a,'b,'c) book) (x:'a) (y:'b) : 'result =
  (* --- *)
  match book.table_ca with
  (* Version without projection: *)
  | None ->
      Tools.with_mutex (book.mutex) (fun () ->
        let () = book.table_ab#replace (x) (Finished y) in
        finally ()
        )
  (* Version with projection: *)
  | Some (prj, table_ca) ->
      Tools.with_mutex (book.mutex) (fun () ->
        let () = book.table_ab#replace (x) (Finished y) in
        let () = table_ca#replace (prj x) (x) in
        finally ()
        )

(* val get_or_compute_image : ('a, 'b, 'c) book -> 'a -> ('a -> 'b) -> 'b *)
let get_or_compute_image (book) (x:'a) (f:'a -> 'b) =
    (* --- *)
    match get_image_or_ownership (book) (x) with
    (* --- *)
    | (Finished y), ownership ->
        let () = assert (not ownership) in
        let () = DEBUGGING(Log.printf ~v:2 "TS_memo.get_or_compute_image: image found => finished\n") in
        y
    (* --- *)
    | (Work_in_progress (thread_id, hublet)), false ->
        let () = DEBUGGING(Log.printf ~v:2 "TS_memo.get_or_compute_image: about to wait for receiving\n") in
        Hublet.receive (Lazy.force hublet)
    (* --- *)
    | (Work_in_progress (thread_id, hublet)), true ->
        (* The thread is the owner and responsible of the image computation, so: *)
        let () = assert (thread_id = Tools.get_thread_id ()) in
        let () = DEBUGGING(Log.printf ~v:2 "TS_memo.get_or_compute_image: about start computation\n") in
        let y = f x in
        let () = DEBUGGING(Log.printf ~v:2 "TS_memo.get_or_compute_image: image calculated\n") in
        (* Action to do in critical section: *)
        let finally () : bool = (Lazy.is_val hublet) in
        let hublet_created = set_image ~finally book x y in
        let () = if hublet_created then
          let () = DEBUGGING(Log.printf ~v:2 "TS_memo.get_or_compute_image: about to send calculated image to waiting receiver(s)\n") in
          Hublet.send (Lazy.force hublet) y
        in
        y

(* val weakly_memoize : ?identifier:('a -> int) -> ?equality:('a -> 'a -> bool) -> ?size:int -> ?prj:('a -> 'c) -> ('a -> 'b) -> 'a -> 'b *)
let weakly_memoize ?identifier ?equality ?size ?prj (f: 'a->'b) : 'a -> 'b =
  let book = make ?identifier ?equality ?size ?prj () in
  fun x -> get_or_compute_image (book) (x) (f)

