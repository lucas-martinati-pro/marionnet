(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009  Jean-Vincent Loddo

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

type 'a t = {
  mutable barrier   : bool        ;
  condition         : Condition.t ;
  mutex             : Mutex.t     ;
  mutable egg       : 'a option   ;
  mutable release_power_available : bool    ;
  }

(** Create an egg structure. *)
let create () = {
  barrier         = true ;
  condition       = Condition.create () ;
  mutex           = Mutex.create () ;
  egg             = None  ;
  release_power_available = true ;
  }

(* Included here from MutexExtra for efficiency. *)
let with_mutex mutex thunk =
  Mutex.lock mutex;
  try
    let result = thunk () in
    Mutex.unlock mutex;
    result
  with e -> begin
    Mutex.unlock mutex;
    (Printf.eprintf
      "Egg.with_mutex: exception %s raised in critical section. Unlocking and re-raising.\n"
      (Printexc.to_string e));
    raise e;
  end

(** Wait for the egg. If the egg is ready, return its value immediately. *)
let wait t =
  with_mutex t.mutex (fun () ->
    begin
     while t.barrier do
       (Condition.wait t.condition t.mutex)
     done;
     match t.egg with
     | Some x -> x
     | None   -> assert false
    end)

(** Non-blocking wait: get the current optional value of the egg. *)
let taste t =
  with_mutex t.mutex (fun () -> t.egg)

(** [release t v] release the value [v] (the egg) for the structure [t]. Broadcast all pending readers.
    Future readers will get the egg immediately without blocking. This call is typically performed once forever. *)
let release t v =
  with_mutex t.mutex (fun () ->
    begin
     (t.barrier <- false);
     (t.egg <- Some v);
     (Condition.broadcast t.condition);
    end)

(** Acquire the power to release the egg, i.e. the power to be {e the} writer. *)
let acquire_release_power t =
  with_mutex t.mutex (fun () ->
    if t.barrier && t.release_power_available
     then begin
       t.release_power_available <- false;
       true
      end
     else false)
