(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2023  Jean-Vincent Loddo
   Copyright (C) 2023  Université Sorbonne Paris Nord

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

(* --- *)
module Log = Marionnet_log
module Milner = Ocamlbricks.Milner
module Future = Ocamlbricks.Future
module Option = Ocamlbricks.Option

(* --- *)
module At_loading_time = struct
  let get_my_thread_id () = Thread.id (Thread.self ())
  (* --- *)
  (* Unused in this module: *)
  let thread_id = get_my_thread_id ()
  (* --- *)
  let gtk_main_thread_id : unit -> (int option) =
    let ch = Milner.create () in
    let _ = GMain.Idle.add (*?prio*) (fun () -> let () = Milner.send ch (get_my_thread_id ()) in false) in
    fun () -> Milner.taste ch

end (* At_loading_time *)

(* --- *)
let am_I_the_GTK_main_thread () =
  let  my_id = At_loading_time.get_my_thread_id () in
  match At_loading_time.gtk_main_thread_id () with
  | Some gtk_id ->
      let () = Log.printf3 ~v:2 "GMain_actor.am_I_the_GTK_main_thread: known gtk_id (%d) vs my_id (%d) => %b\n" (gtk_id) (my_id) (my_id = gtk_id) in
      (my_id = gtk_id)
  | None ->
      (* If the GTK main thread has not provided its ID, it is assumed to be the main thread of OCaml: *)
      let () = Log.printf3 ~v:2 "GMain_actor.am_I_the_GTK_main_thread: UNKNOWN gtk_id, using At_loading_time.thread_id (%d) vs my_id (%d) => %b\n"
        (At_loading_time.thread_id) (my_id) (my_id = At_loading_time.thread_id)
      in
      (my_id = At_loading_time.thread_id)

(* --- *)
(*let am_I_the_GTK_main_thread () =
  let answer1 = am_I_the_GTK_main_thread () in
  let answer2 = GtkThread.gui_safe () in
  let () = assert (answer1 = answer2) in
  answer1*)

(* --- *)
module EitherExtra = struct
  let protect f x = try Either.Right (f x) with e -> Either.Left e
  let protect2 f x y = try Either.Right (f x y) with e -> Either.Left e
  let protect3 f x y z = try Either.Right (f x y z) with e -> Either.Left e
  (**)
  let extract_or_raise = function Either.Right y -> y | Either.Left e  -> raise e
end

(* --- *)
(* This tool should be called by a "client" thread other than `gtk_main'.
   However, we use Thread.id to prevent the GTK main thread to call this procedure
   and thus remain stucked in a deadlock (waiting a message from itself).
   In this case, apply became the standard function application (protected
   from exceptions).
   ---
   Example:
     let y = GMain_actor.apply (fun x -> x*2) (21) in
     Log.printf1 "Created thread: testing a call to the GTK main thread: result is %d\n" (Either.find_right y |> Option.extract);
   ---
   *)
let apply ?prio (f:'a -> 'b) (x:'a) : (exn, 'b) Either.t =
  (* --- *)
  if am_I_the_GTK_main_thread () then EitherExtra.protect f x else (* continue: *)
  (* --- *)
  let ch = Milner.create () in
  (* --- *)
  (* This code will be executed by the GTK main thread (gtk_main), acting as an "actor": *)
  let f' () : bool =
    try
      let y = f x in
      let () = Milner.send ch (Either.Right y) in
      false
    with e ->
      let () = Milner.send ch (Either.Left e) in
      false
  in
  (* --- *)
  (* This code will be executed by the "caller thread" or "client":  *)
  (* val GMain.Idle.add : ?prio:int -> (unit -> bool) -> id *)
  let _ = GMain.Idle.add ?prio f' in
  let result = Milner.receive (ch) in
  result

(* --- *)
let apply2 ?prio f x1 x2 : (exn, 'b) Either.t =
  apply ?prio (f x1) x2

(* --- *)
let apply3 ?prio f x1 x2 x3 : (exn, 'b) Either.t =
  apply ?prio (f x1 x2) x3

(* val apply_extract  : ?prio:int -> ('a -> 'b) -> 'a -> 'b *)
let apply_extract ?prio f x = apply ?prio f x |> EitherExtra.extract_or_raise
(* --- *)
(* val apply2_extract : ?prio:int -> ('a -> 'b -> 'c) -> 'a -> 'b -> 'c *)
let apply2_extract ?prio f x y = apply2 ?prio f x y |> EitherExtra.extract_or_raise
(* --- *)
(* val apply3_extract : ?prio:int -> ('a -> 'b -> 'c -> 'd) -> 'a -> 'b -> 'c -> 'd *)
let apply3_extract ?prio f x y z = apply3 ?prio f x y z |> EitherExtra.extract_or_raise

(* --- *)
(* This procedure may be asynchronous setting ~async:(). In this case
   the caller doesn't wait for the result; it just gives the "order" of
   applying the function to `gtk_main' then returns immediately to its own activity: *)
let delegate ?async ?prio (f:'a -> unit) (x:'a) : unit =
  (* --- *)
  if async = None then apply f x |> ignore else (* continue: *)
  (* --- *)
  (* This code will be executed by the GTK main thread (gtk_main), acting as an "actor": *)
  let f' () : bool =
    try (let () = f x in false) with e -> false
  in
  (* --- *)
  (* This code will be executed by the "caller thread" or "client":  *)
  (* val GMain.Idle.add : ?prio:int -> (unit -> bool) -> id *)
  let _ = GMain.Idle.add ?prio f' in
  ()

(* --- *)
let delegate2 ?async ?prio f x1 x2 : unit =
  delegate ?async ?prio (f x1) x2

let delegate3 ?async ?prio f x1 x2 x3: unit =
  delegate ?async ?prio (f x1 x2) x3

(* --- *)
(* Asynchronous call where the caller may be interested later for the result: *)
let future ?prio (f:'a -> 'b) (x:'a) : ((exn, 'b) Either.t) Future.t =
  Future.thread (apply ?prio f) x

(* --- *)
let future2 ?prio f x1 x2 : ((exn, 'b) Either.t) Future.t =
  future ?prio (f x1) x2

(* --- *)
let future3 ?prio f x1 x2 x3 : ((exn, 'b) Either.t) Future.t =
  future ?prio (f x1 x2) x3
