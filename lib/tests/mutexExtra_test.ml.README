(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2011  Jean-Vincent Loddo
   Copyright (C) 2011  Université Paris 13

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

(** Test program for recursive mutexes. *)

(* Extended simple mutexes. *)
module EMutex = MutexExtra.EMutex

module Debug = struct
 let mutex = EMutex.create ()
 let active = ref false
 let enable  () = EMutex.with_mutex mutex (fun () -> active := true)
 let disable () = EMutex.with_mutex mutex (fun () -> active := false)
 let switch f x = if !active then (Lazy.force f) x else ()
 let eprintf fmt = switch (lazy (EMutex.apply_with_mutex mutex (Printf.kfprintf flush stderr))) fmt
 let eprintf1 fmt x = switch (lazy (EMutex.apply_with_mutex mutex (Printf.kfprintf flush stderr fmt))) x
 let eprintf2 fmt x y = switch (lazy (EMutex.apply_with_mutex mutex (Printf.kfprintf flush stderr fmt x))) y
 let eprintf3 fmt x y z = switch (lazy (EMutex.apply_with_mutex mutex (Printf.kfprintf flush stderr fmt x y))) z
end (* module Debug *)


module Test (R: sig
   type t
   val create : unit -> t
   val lock   : t -> unit
   val unlock : t -> unit
   val with_mutex       : ?verbose:unit -> t -> (unit -> 'a) -> 'a
   val apply_with_mutex : ?verbose:unit -> t -> ('a -> 'b) -> 'a -> 'b
 end) = struct

let () = Random.self_init ()
let counter = ref 0
let mutex = R.create ()

let rec loop ~action = function
 | 0 -> ()
 | 1 -> R.with_mutex mutex action
 | n -> R.apply_with_mutex mutex (loop ~action) (n-1)

let thread_life ~max_iterations_per_thread ~max_depth () =
  let iterations = Random.int (max_iterations_per_thread+1) in
  let depth = Random.int (max_depth+1) in
  for i = 1 to iterations do
    loop ~action:(fun () -> incr counter) depth;
    (* Here may be interrupted *)
    Thread.delay 0.01;
    loop ~action:(fun () -> decr counter) depth;
  done


let go ?(thread_no=1500) ?(max_iterations_per_thread=200) ?(max_depth=5) () =
  Debug.enable ();
  Debug.eprintf "Testing with:\n";
  Debug.eprintf1 "  thread_no=%d\n" thread_no;
  Debug.eprintf1 "  max_iterations_per_thread=%d\n" max_iterations_per_thread ;
  Debug.eprintf1 "  max_depth=%d (maximal recursive lock number)\n" max_depth ;
  Debug.eprintf1 "BEGIN: counter=%d\n" !counter;
  let ts = Array.init thread_no
    (fun i ->
       let t = Thread.create (thread_life ~max_iterations_per_thread ~max_depth)  () in
       Debug.eprintf1 "i=%d\r" (i+1);
       Thread.delay 0.005;
       t
       )
  in
  Array.iter Thread.join ts;
  Debug.eprintf1 "\rEND:   counter=%d\n" !counter;
  if !counter = 0 then
    Debug.eprintf "Test ok.\n"
  else
    Debug.eprintf "Test KO: unexpected result: at this point counter would be 0\n"
  ;
  flush stderr

end;; (* module Test *)

let module T = Test (MutexExtra.Recursive)
in T.go ()
