(* This file is part of ocamlbricks
   Copyright (C) 2013, 2014, 2015, 2016, 2017  Jean-Vincent Loddo

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

(** Type aliases: *)
type time = seconds
 and delay = seconds
 and seconds = float

exception Timeout
let coverup f x y = try f x with _ -> y
let flipped_coverup f y x = try f x with _ -> y
 
module Backoff = struct

  type f = collisions -> delay_range
  (* --- *)
   and collisions  = float
   and delay_range = float

  let linear = (fun c->c)
  let exponential = (exp)
  let binary_exponential = (fun c->2.**c)
  
  (* Used by Ethernet CSMA/CD: 
     we define a maximum number of collisions (max{x}) instead of a max range (~max_delay, i.e. max{f(x)}): *)
  let truncated_binary_exponential ?(max_collisions=10) =
    let max_collisions = float_of_int max_collisions in
    fun c -> 2.**(min c max_collisions)
  
end (* Backoff *)

(** Default for functions taking these optional arguments. *)
module Default = struct

  let backoff = Backoff.linear
  let slot = 0.1 (* 0.1 seconds *)
  
end
  
(* Random generators, built from common backoff functions: *) 
module Random = struct

  type g = unit -> delay
  
  (* --- *)
  let make ?(slot = Default.slot) ?(backoff = Default.backoff) () : g =
    let c = ref 0 in (* number of collisions, in the closure *)
    fun () -> 
      let range = abs_float (backoff (float_of_int !c)) in
      let time  = slot *. (Random.float range) in
      let () = incr c in
      time

  let make_with_truncated_range ~max_delay ?(slot = Default.slot) ?(backoff = Default.backoff) () : g =
    let c = ref 0 in (* number of collisions, in the closure *)
    let max_joined = ref false in
    fun () -> 
      let range = match !max_joined with
        | false -> 
            let result = abs_float (backoff (float_of_int !c)) in
            if (result > max_delay) then (max_joined := true; max_delay) else (incr c; result)
        (*--- *)    
        | true -> max_delay
      in
      let time  = slot *. (Random.float range) in
      time
   
  (* make redefined with ?max_delay *)
  (* val make : ?max_delay:time -> ?slot:time -> ?backoff:Backoff.f -> unit -> g *)
  let make ?max_delay = 
    match max_delay with None -> make | Some max_delay -> make_with_truncated_range ~max_delay
      
  (* Common cases: *)    
      
  let linear             ?max_delay ?slot () = make ?max_delay ?slot ~backoff:Backoff.linear ()
  let exponential        ?max_delay ?slot () = make ?max_delay ?slot ~backoff:Backoff.exponential ()
  let binary_exponential ?max_delay ?slot () = make ?max_delay ?slot ~backoff:Backoff.binary_exponential ()
  
  (* Used by Ethernet CSMA/CD: 
     we define a maximum number of collisions (max{x}) instead of a max range (~max_delay, i.e. max{f(x)}): *)
  let truncated_binary_exponential ?(max_collisions=10) ?slot () = 
    let max_collisions = float_of_int max_collisions in
    make ?slot ~backoff:(fun c->2.**(min c max_collisions)) ()

end (* Random *)

(* A "delay" is a function that sleeps (applying Thread.sleep) during a random time 
   in an evolving range (possibly limited by ~max_delay) *)
module Delay = struct

  type p = unit -> unit (* "p" for procedure *)

  let make ?max_delay ?slot (backoff) : p =
    let random = Random.make ?max_delay ?slot ~backoff () in
    fun () -> Thread.delay (random ())
  
  let linear ?max_delay ?slot () : p =
    let random = Random.linear ?max_delay ?slot () in
    fun () -> Thread.delay (random ())
      
  let exponential ?max_delay ?slot () : p =
    let random = Random.exponential ?max_delay ?slot () in
    fun () -> Thread.delay (random ())
    
  let binary_exponential ?max_delay ?slot () : p =
    let random = Random.binary_exponential ?max_delay ?slot () in
    fun () -> Thread.delay (random ())
    
  let truncated_binary_exponential ?max_collisions ?slot () : p =
    let random = Random.truncated_binary_exponential ?max_collisions ?slot () in
    fun () -> Thread.delay (random ())
    
end (* Delay *)
 
(* guard is a "remain" condition: *) 
let loop_while guard f =
  let rec loop token =
    if guard () then loop (f token) else token
  in loop

(* guard is an "exit" condition: *) 
let loop_while_not guard f =
  let rec loop token =
    if guard () then token else loop (f token)
  in loop

(* A "wait_until" is a kind of function that waits until a condition becames true, 
   applying a function "delay" to sleep between two tests. A couple of thunks 
   for unlocking/relocking may be provided to be executed before and after sleeping. *)
module Wait_until = struct
  
  (* 'lock will be simply "unit" if the locking (relock) procedure doesn't return a meaningfull information: *)
  type 'lock f = 
    ?unlock_relock:(unit thunk * 'lock thunk) -> ?timeout_exn:exn -> ?timeout:seconds -> guard:(unit->bool) -> 'lock -> 'lock
   and 'a thunk = unit -> 'a
  
  let wait_until ?unlock_relock ?(timeout_exn=Timeout) ?timeout (guard) (delay) (token:'lock) : 'lock  =
    match unlock_relock, timeout with
    (* --- *)
    | None, None -> 
       let () = while not (coverup guard () false) do delay () done in 
       token
    (* --- *)
    | None, Some timeout -> 
        let starting_time = Unix.gettimeofday () in
        let () = while not (coverup guard () false) do 
          (if ((Unix.gettimeofday ()) -. starting_time) > timeout then raise timeout_exn);
          delay () 
          done
        in
        token
    (* --- *)
    | Some (unlock, relock), None ->
        (* val loop_until : (unit -> bool) -> ('a -> 'a) -> 'a -> unit *)
        loop_while_not (flipped_coverup guard false) 
          (fun _ -> unlock(); delay(); relock ())
          (token)
    (* --- *)
    | Some (unlock, relock), Some timeout -> 
        let starting_time = Unix.gettimeofday () in
        (* val loop_while_not : (unit -> bool) -> ('a -> 'a) -> 'a -> unit *)
        loop_while_not (flipped_coverup guard false) 
          (fun _ -> unlock(); (if ((Unix.gettimeofday ()) -. starting_time) > timeout then raise timeout_exn); delay(); relock ())
          (token)
   
  let make ?max_delay ?slot (backoff_function) : 'lock f =
    fun ?unlock_relock ?timeout_exn ?timeout ~guard token -> 
      let delay = Delay.make ?max_delay ?slot (backoff_function) in
      wait_until ?timeout_exn ?timeout ?unlock_relock (guard) (delay) (token)
          
  let linear ?max_delay ?slot () : 'lock f =
    fun ?unlock_relock ?timeout_exn ?timeout ~guard token -> 
      let delay = Delay.linear ?max_delay ?slot () in
      wait_until ?timeout_exn ?timeout ?unlock_relock (guard) (delay) (token)

  let exponential ?max_delay ?slot () : 'lock f =
    fun ?unlock_relock ?timeout_exn ?timeout ~guard token -> 
      let delay = Delay.exponential ?max_delay ?slot () in
      wait_until ?timeout_exn ?timeout ?unlock_relock (guard) (delay) (token)

  let binary_exponential ?max_delay ?slot () : 'lock f =
    fun ?unlock_relock ?timeout_exn ?timeout ~guard token -> 
      let delay = Delay.binary_exponential ?max_delay ?slot () in
      wait_until ?timeout_exn ?timeout ?unlock_relock (guard) (delay) (token)

  let truncated_binary_exponential ?max_collisions ?slot () : 'lock f =
    fun ?unlock_relock ?timeout_exn ?timeout ~guard token -> 
      let delay = Delay.truncated_binary_exponential ?max_collisions ?slot () in
      wait_until ?timeout_exn ?timeout ?unlock_relock (guard) (delay) (token)

end (* Wait_until *)

(* Simplified interface: *)

type 'a thunk = unit -> 'a

let wait_until ?(backoff=`linear) =
 match backoff with
 | `linear             -> Wait_until.linear
 | `exponential        -> Wait_until.exponential
 | `binary_exponential -> Wait_until.binary_exponential

(* Auxiliary type: *) 
type 'a wait_until_signature = 
  ?unlock_relock:(unit thunk * 'a thunk) -> ?timeout_exn:exn -> ?timeout:seconds -> guard:(unit->bool) -> 'a -> 'a 

let wait_impatiently ?(backoff=`linear) ?max_delay ?slot () =
 let launch (wait_until:'a wait_until_signature) ?unlock_relock ?timeout_exn ~timeout ~guard x =
   try  
     Some (wait_until ?unlock_relock ?timeout_exn ~timeout ~guard x)
   with Timeout -> None
 in
 match backoff with
 | `linear             -> let w = Wait_until.linear ?max_delay ?slot () in launch w
 | `exponential        -> let w = Wait_until.linear ?max_delay ?slot () in launch w
 | `binary_exponential -> let w = Wait_until.linear ?max_delay ?slot () in launch w
 
