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

(** Simple semaphore implementation for threads (not for processes). *)

type t = {
  mutable counter   : int         ;
  condition         : Condition.t ;
  mutex             : Mutex.t     ;
  }

let create ?(mutex=Mutex.create ()) ?(condition=Condition.create ()) ?(init=0) () = {
  counter         = init ;
  condition       = condition ;
  mutex           = mutex ;
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
      "Semaphore.with_mutex: exception %s raised in critical section. Unlocking and re-raising.\n"
      (Printexc.to_string e));
    raise e;
  end

let p ?(n=1) t =
  with_mutex t.mutex (fun () ->
    begin
     while (t.counter < n) do
       (Condition.wait t.condition t.mutex)
     done;
     t.counter <- t.counter - n
    end)

let v ?(n=1) t =
  with_mutex t.mutex (fun () ->
    begin
     (t.counter <- t.counter + n);
     (Condition.signal t.condition);
    end)

let p_nowait ?(n=1) t =
  with_mutex t.mutex (fun () ->
    begin
     if (t.counter < n)
       then false
       else ((t.counter <- t.counter - n); true)
    end)

(** Execute thunk in a synchronized block (p ; code ; v), and return the value returned
    by the thunk. If executing thunk raises an exception the same exception
    is propagated, after correctly releasing (v) the semaphore. *)
let with_semaphore ?(n=1) t thunk =
  p ~n t;
  try
    let result = thunk () in
    v ~n t;
    result
  with e -> begin
    v ~n t;
    (Printf.eprintf
      "Semaphore.with_semaphore: exception %s raised in critical section. Releasing and re-raising.\n"
      (Printexc.to_string e));
    raise e;
  end


(* Included here from ArrayExtra for efficiency. *)
let exists (p : int -> 'a -> bool) (s:'a array) =
 let l = Array.length s in
 let rec loop i =
  if i>=l then false else
  (p i s.(i)) || loop (i+1)
 in loop 0

module Array_and (M:sig val dim:int end) = struct

let dim = M.dim

(* Run-time control on dimension. *)
let () = assert (dim>0)

(** Components are created on the same mutex and condition. *)
let create ?(mutex=Mutex.create ()) ?(condition=Condition.create ()) ?(init=Array.make dim 0) () =
  Array.init dim (fun i -> create ~mutex ~condition ~init:init.(i) ())

let p ?(n=Array.make dim 1) t =
  let (mutex,condition) = (t.(0).mutex, t.(0).condition) in
  with_mutex mutex (fun () ->
    begin
     while exists (fun i s -> (s.counter < n.(i))) t do
       (Condition.wait condition mutex)
     done;
     Array.iteri (fun i s -> s.counter <- s.counter - n.(i)) t
    end)

let v ?(n=Array.make dim 1) t =
  let (mutex,condition) = (t.(0).mutex, t.(0).condition) in
  with_mutex mutex (fun () ->
    begin
     (Array.iteri (fun i s -> s.counter <- s.counter + n.(i)) t);
     (Condition.broadcast condition);
    end)

let p_nowait ?(n=Array.make dim 1) t =
  let (mutex,condition) = (t.(0).mutex, t.(0).condition) in
  with_mutex mutex (fun () ->
    begin
     if exists (fun i s -> (s.counter < n.(i))) t
       then false
       else ((Array.iteri (fun i s -> s.counter <- s.counter - n.(i)) t); true)
    end)

(** Execute thunk in a synchronized block (p ; code ; v), and return the value returned
    by the thunk. If executing thunk raises an exception the same exception
    is propagated, after correctly releasing (v) the semaphore. *)
let with_semaphore ?(n=Array.make dim 1) t thunk =
  p ~n t;
  try
    let result = thunk () in
    v ~n t;
    result
  with e -> begin
    v ~n t;
    (Printf.eprintf
      "Semaphore.with_semaphore: exception %s raised in critical section. Releasing and re-raising.\n"
      (Printexc.to_string e));
    raise e;
  end

(* type a = t array *)
(* type t = a *)

end (* Array_and *)



(* Disjonctive semantics. *)
module Array_or (M:sig val dim:int end) = struct

let dim = M.dim

(* Run-time control on dimension. *)
let () = assert (dim>0)

(** Components are created on the same mutex and condition. *)
let create ?(mutex=Mutex.create ()) ?(condition=Condition.create ()) ?(init=Array.make dim 0) () =
  Array.init dim (fun i -> create ~mutex ~condition ~init:init.(i) ())

(* Auxiliary function similar to exists but setting the result (i,v) in a reference: *)
let find ~aref p a =
 let l = Array.length a in
 let rec loop i =
  if i>=l then false else
  let x = a.(i) in
  if (p i x) then ((aref := Some i); true) else loop (i+1)
 in loop 0

let p ?(n=Array.make dim 1) t =
  let (mutex,condition) = (t.(0).mutex, t.(0).condition) in
  with_mutex mutex (fun () ->
    begin
     let aref = ref None in
     while not (find ~aref (fun i s -> (s.counter >= n.(i))) t) do
       (Condition.wait condition mutex)
     done;
     let i = match !aref with Some i -> i | None -> assert false in
     let k = n.(i) in
     (t.(i).counter <- t.(i).counter - k);
     (i,k)
    end)

let v ~i ~n t =
  let (mutex,condition) = (t.(0).mutex, t.(0).condition) in
  with_mutex mutex (fun () ->
    begin
     (t.(i).counter <- t.(i).counter + n);
     (Condition.broadcast condition);
    end)

let p_nowait ?(n=Array.make dim 1) t =
  let (mutex,condition) = (t.(0).mutex, t.(0).condition) in
  with_mutex mutex (fun () ->
    begin
     let aref = ref None in
     if find ~aref (fun i s -> (s.counter >= n.(i))) t then
         begin
           let i = match !aref with Some i -> i | None -> assert false in
           let k = n.(i) in
           (t.(i).counter <- t.(i).counter - k);
           Some (i,k)
         end
       else
         None
    end)

(** Execute thunk in a synchronized block (p ; code ; v), and return the value returned
    by the thunk. If executing thunk raises an exception the same exception
    is propagated, after correctly releasing (v) the semaphore. *)
let with_semaphore ?(n=Array.make dim 1) t f =
  let (i,k) = p ~n t in
  try
    let result = f ~i ~n:k in
    v ~i ~n:k t;
    result
  with e -> begin
    v ~i ~n:k t;
    (Printf.eprintf
      "Semaphore.with_semaphore: exception %s raised in critical section. Releasing and re-raising.\n"
      (Printexc.to_string e));
    raise e;
  end

(* type a = t array *)
(* type t = a *)

end (* Array_or *)
