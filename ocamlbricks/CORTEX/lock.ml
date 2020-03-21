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

(* The module in a nutshell:
   (* --- *)
   type b = Mutex.t * Condition.t     (* basic locks *)
    and c = b list                    (* conjunction: an ordered list of basic locks *)
    and d = c list                    (* disjunction: a set of conjunctions *)
    and t = d                         (* a lock is a disjunction *)
   (* --- *)
*)

(** Generic functor to manage (S)et (U)nique sorted lists, i.e. sorted lists without duplicated. *)
module SUList_of_Set = functor (S:Set.S) -> struct
  include S

  type l = elt list
  
  let concat (xss : l list) : l = 
    let r = List.fold_left (fun r xs -> S.union r (S.of_list xs)) (S.empty) xss in
    S.elements r
  
  let make (xs : elt list) : l =
   S.elements (of_list xs)

  let make_from_array (xs : elt array) : l =
    S.elements (Array.fold_left (fun m e -> S.add e m) S.empty xs)
   
  let private_map_cartesian_product (f : elt -> elt -> elt) (t1:t) (l2:l) : t = 
    let t2 = of_list l2 in
    let assoc_to_all (x:elt) (ys:t) : t = 
      S.fold (fun y xys -> S.add (f x y) xys) ys (S.empty)
    in
    S.fold (fun x r -> S.union r (assoc_to_all x t2)) t1 (S.empty)

  let map_cartesian_product (f : elt -> elt -> elt) (l1:l) (l2:l) : t = 
    let t1 = of_list l1 in
    private_map_cartesian_product f t1 l2
   
  (* Exemple:  
      SUList.map_n_fold_cartesian_product (fun x y -> x*y) [[0;1;2]; [3;5]; [10; 100; 1000]];; 
      : SUList.l = [0; 30; 50; 60; 100; 300; 500; 600; 1000; 3000; 5000; 6000; 10000] *)
  let map_n_fold_cartesian_product (f : elt -> elt -> elt) : (l list -> l) = function
   | []    -> []
   | l::ls -> 
       let t = List.fold_left (private_map_cartesian_product f) (of_list l) ls in
       S.elements t

end (* SUList_of_Set() *)

module SUList_of_Ord = functor (Ord:Set.OrderedType) -> SUList_of_Set (Set.Make (Ord))
(* Example: module Int_SUList = SUList_of_Ord (struct type t = int  let compare = compare end) *)

exception Timeout
let coverup f x y = try f x with _ -> y

(* From ArrayExtra: *)
let array_find p s =
 let l = Array.length s in
 let rec loop i =
  if i>=l then raise Not_found else
  let x = s.(i) in
  if (p x) then x else loop (i+1)
 in loop 0

(* Basic locks:  *)
module Basic : 
   sig
     (* --- *)
     type b = Mutex.t * Condition.t
     (* --- *)
     val create    : unit -> b
     val try_lock  : ?guard:(b -> bool) -> b -> bool
     val lock      : ?guard:(b -> bool) -> ?timeout:float -> b -> unit
     val wait      : b -> unit
     val signal    : b -> unit
     val broadcast : b -> unit
     val unlock    : b -> unit
     (* --- *)
     val merge_and_sort_basic_lists : (b list) list -> b list
     val compare   : b -> b -> int
   end
  = struct

  type b = Mutex.t * Condition.t

  let create () : b = (Mutex.create (), (Condition.create ()))
 
  let compare (m0,v0) (m1,v1) = compare m0 m1
  module Set = Set.Make (struct type t = b let compare = compare end)

  let merge_and_sort_basic_lists (bss : b list list) : b list =
    let add s l = List.fold_left (fun s x -> Set.add x s) s l in
    let s = List.fold_left (add) Set.empty bss in
    Set.elements s

  let wait (m,v) = Condition.wait v m
  let broadcast (m,v) = Condition.broadcast v 
  let signal (m,v) = Condition.signal v 
  let unlock (m,v) = Mutex.unlock m

  let try_lock ?guard ((m,v) as b) =
    (Mutex.try_lock m) &&
    (match guard with
    | None -> true
    | Some guard -> 
        if (coverup guard b false) 
        then true   (* fine, the mutex is locked and the guard is true. It's a success (return true) *)
        else begin  (* but if the guard is false, unlock the mutex and fail (return false) *)
          Mutex.unlock m;
          false
        end)

  (* The timeout concerns the time to wait for the guard (not for getting the lock): *)      
  let lock ?guard ?timeout ((m,v) as b) = begin
    let starting_time = if (guard = None) || (timeout = None) then 0. else Unix.gettimeofday () in
    Mutex.lock m;
    match guard, timeout with
    | None, _ -> ()
    | (Some guard), None -> 
        while not (coverup guard b false) do
          Condition.wait v m
        done
    | (Some guard), (Some timeout) -> 
        while not (coverup guard b false) do
          (if ((Unix.gettimeofday ()) -. starting_time) > timeout then (Mutex.unlock m; raise Timeout));
          Condition.wait v m
        done
    end
    
end (* Basic *)

(* Alias: *)
type b = Basic.b

(* Conjunction: a sorted array of basic locks: *)
module Conjunction :
  sig
    (* --- *)
    type c = b array
     and b = Basic.b
    (* --- *)
    val create    : unit -> c
    val product   : c list -> c
    val unity     : c (* empty*)
    val append    : c -> c -> c (* a binary product without reordering *)
    val try_lock  : ?guard:(c -> bool) -> c -> bool
    val lock      : ?guard:(c -> bool) -> ?timeout:float -> c -> unit
    val unlock    : c -> unit
    val wait      : c -> b option  (* the result is the basic where something has happen, if any *)
    val broadcast : c -> unit
    (* --- *)
    val compare   : c -> c -> int
    module Set    : Set.S with type elt = c
  end
  = struct

  type c = b array and b = Basic.b
  
  let create () = Array.make 1 (Basic.create ())
  let unity : c = [||]
  
  let product cs =
    let bs =
      let bss = List.map (Array.to_list) cs in
      Basic.merge_and_sort_basic_lists bss
    in
    Array.of_list bs

  (* This is the same of the product, but the second list is forced to be at the end of the first: *)  
  let append = Array.append
    
  (* Something happens for c if something happens somewhere in c. *)
  let wait c = begin
    match Array.length c with
    | 0 -> None 
    | 1 -> let () = Basic.wait c.(0) in (Some c.(0))  (* Simple case: the conjunction is a singleton *)
    | n  ->
      (* This is the complicated case: c is composed by several basic components. 
         We will start a thread per component, waiting for an event on this component. *)
      let egg_lock = Basic.create () in
      let egg = ref None in   (* protected by the egg_lock *)
      let first_i = ref 0 in  (* protected by the egg_lock, this represents the first index that can remain locked *)
      (* --- *)
      (* A thread takes a triple (i,b,x) where b is a basic lock, i is its index
         and x is a reference on which the thread notifies its termination: *)
      let thread_behaviour (i, b, x) : unit = begin
        Basic.wait b;                            (* wait on the basic component *) 
        (* --- *)
        Basic.lock egg_lock;                     (* BEGIN --- egg_lock protect both egg and x *)
        (if (!egg) = None then (egg := Some b)); (* the first awakened is the winner *)
        x := true;                               (* I'm terminated *) 
        let unlock_b = 
          if (i = !first_i)                      (* slight optimization: while the wait calls *)
            then ((incr first_i); false)         (* exit (relock) in the correct order, dont unlock *)
            else true
        in
        Basic.signal egg_lock;                   (* signal the father on egg_lock (broadcast would do the same job) *)
        Basic.unlock egg_lock;                   (* END --- *)
        (* --- *)
        (* Important point: unlock b (except if b is the first lock, 
           because we have to relock the mutexes in the correct order): *)
        if (unlock_b) then Basic.unlock b;
        end
      (* --- *)
      in
      (* Basic components as simple list: *)
      let bs = Array.to_list c in
      (* The father get the egg_lock before to spawn its children: *)
      Basic.lock egg_lock;
      (* Spawn all threads: *)
      let txbs : (Thread.t * (bool ref) * Basic.b) list = 
        List.mapi 
          (fun i b -> 
             let x  = ref false in (* here x means terminated *)
             let t  = Thread.create thread_behaviour (i, b, x) in
             (t,x,b)) 
          bs 
      in
      (* Now wait for the egg (the basic lock awaked by the context): *)
      Basic.wait egg_lock;
      (* --- *)
      (* Broadcast all living threads waiting on a basic lock, in order to force them to interrupt their 
         waiting to get their lock again. Note that this behaviour generates a kind of "false alarm" for 
         other threads that operate on a structure having an intersection with this conjunction, even if 
         they aren't concerned by the occurred event. Quite ugly but unavoidable at this level. To solve
         this problem, we should have a variant of the OS call system signal() allowing to specify a thread id
         as destination (instead to have only the choice between signal, i.e. one destination, and broadcast(),
         i.e. all destionations). *)
      let living = ref (List.filter (fun (t,x,b) -> not (!x)) txbs) in
      (* --- *)
      while (!living) <> [] do 
        List.iter (fun (t,x,b) -> Basic.broadcast b) (!living);
        Basic.wait egg_lock;
        living := (List.filter (fun (t,x,b) -> not (!x)) (!living));
      done;
      (* --- *)
      (* Now wait the end of all threads in order to be sure that all mutexes have been re-locked: *)
      let () = List.iter (fun (t,x,b) -> Thread.join t) txbs in (* unnecessary (redundant) *)
      (* --- *)
      (* At this point, only the first mutexes are locked (in the worst case only the mutex 0
         is locked, the rest has been unlocked). We have now to lock again the rest of mutexes 
         forcing the correct order: *)
      let () = for i = !first_i (* not zero *) to (n-1) do Basic.lock c.(i) done in
      (* --- *)
      !egg
    end
    
  (* The broadcast is performed backward (just a choice): *)  
  let broadcast c = 
    let last = (Array.length c) - 1 in
    for i = last downto 0 do Basic.broadcast c.(i); done

  (* The unlock *must* be performed backward, i.e. in the reversed order: *)  
  let unlock c = 
    let last = (Array.length c) - 1 in
    for i = last downto 0 do Basic.unlock c.(i); done 
    
  (* If the conjunction is empty, there are two cases according to the presence of the optional argument `guard'. 
     If the guard is provided, "lock with a guard" just means "wait for the guard". if the guard is not provided,
     the lock operation is meaningless. *)  
  let lock ?guard ?timeout c = 
    match (Array.length c) with 
    (* --- *)
    | 0 -> begin
        match guard with
        | None -> ()    (* lock is meaningless *)
        | Some guard -> (* lock means wait (i.e. wait without unlocking-relocking, because there aren't locks!) *)
            (* --- *)
            (* Initialize a wait function that reiterates the tests sleeping an increasing random,
               amount of time between two tests: *)
            let wait_until = Spinning.Wait_until.linear ~max_delay:3. () in (* linear increasing of random delays *)
            wait_until ~timeout_exn:Timeout ?timeout ~guard:(fun () -> guard c) ()
        end
    (* --- *)
    | n -> begin 
        (* The conjunction is not empty: *)
        let starting_time = if (guard = None) || (timeout = None) then 0. else Unix.gettimeofday () in
        let last = (n-1) in
        for i = 0 to last do let (m,v) = c.(i) in Mutex.lock m; done; (* lock in the correct order *)
        match guard, timeout with
        | None,_ -> ()        (* if there is no guard, that's all *)
        (* --- *)
        | (Some guard), None -> 
            while not (coverup guard c false) do
              ignore (wait c) (* ignore the basic lock involved by an alert (signal or broadcast) *) 
            done
        (* --- *)
        | (Some guard), (Some timeout) -> 
            while not (coverup guard c false) do
              (if ((Unix.gettimeofday ()) -. starting_time) > timeout then (unlock c; raise Timeout));
              ignore (wait c) (* ignore the basic lock involved by an alert (signal or broadcast) *) 
            done
        end

  let try_lock ?guard c = 
    match (Array.length c) with 
    (* --- *)    
    | 0 ->
       (match guard with
       | None       -> true
       | Some guard -> coverup guard c false (* just once, not in a loop! *)
       )
    (* --- *)    
    | n -> begin 
        (* The conjunction is not empty: *)
        (* --- *)
        (* This function tries to lock the list of mutexes, returning the acquired mutexes in any case: *)
        let rec loop acc i = 
          if (i = n) then (true, acc) else (* continue: *)
          let (m,v) = c.(i) in
          if Mutex.try_lock m then loop (m::acc) (i+1) else (false, acc)
        in 
        (* --- *)
        match loop [] 0 with
        | (false, rev_ms) -> begin              
              (* Important point: unlock mutexes locked uselessly! *)
              List.iter (Mutex.unlock) rev_ms;
              false
            end
        (* --- *)
        | (true,  rev_ms) ->
            (* All mutexes are locked, but this may be not sufficient: *)
            (match guard with
            | None -> true
            | Some guard -> 
                if (coverup guard c false) 
                then true   (* fine, all mutexes are locked and the guard is true. It's a success (return true) *)
                else begin  (* but if the guard is false, unlock all the mutexes and fail (return false) *)
                  List.iter (Mutex.unlock) rev_ms;
                  false
                end)
        end (* try_lock *)
    
 (* Lexicographic extensions of `compare' for arrays: *)
 let compare_array ~(compare:'a->'a->int) =
   fun xs ys ->
     let n = Array.length xs in
     let m = Array.length ys in
     let rec loop i = 
       if i=n && i=m then 0 else
       if i=n && i<m then (-1) else
       if i<n && i=m then 1 else
       let result = compare xs.(i) ys.(i) in
       if result = 0 then loop (i+1) else result
     in loop 0
  
  (* Pervasives.compare is different, but it should do the same job: *)
  let compare = compare_array ~compare:Basic.compare
  module Set = Set.Make (struct type t = c let compare = compare end)
  
end (* Conjunction *)

(* Alias: *)
type c = Conjunction.c

module Disjunction :
  sig
    (* --- *)
    type d = c array
    (* --- *)
    val create   : unit -> d
    (* --- *)
    val of_conjunction_list  : c list  -> d
    val of_conjunction_array : c array -> d (* removes duplicated *)
    (* --- *)
    val zero     : d            (* identity element of the sum *)
    val sum      : d list -> d
    (* --- *)
    val unity    : d            (* identity element of the product *)
    val product  : d list -> d
    (* --- *)
    val try_lock : ?guard:(c -> bool) -> d -> c option option
    val lock     : ?guard:(c -> bool) -> ?timeout:float -> d -> c option (* The result is None iff the disjunction is empty *)
  end

 = struct 

 type d = c array
 
 let create () = Array.make 1 (Conjunction.create ())

 module Conjunction_list = SUList_of_Ord (struct type t = c  let compare = Conjunction.compare end)

 let zero = [||]
 let unity = [| Conjunction.unity |] (* the "unity" is the singleton containing the empty conjunction *)
 
 (* n-ary sum. The meaning is: (c1 + c2) + c3 = (c1 + c2 + c3) *)
 let sum (ds : d list) : d = Array.of_list (Conjunction_list.concat (List.map Array.to_list ds))
 let of_conjunction_list  (cs : c list)  : d = Array.of_list (Conjunction_list.make cs)
 let of_conjunction_array (cs : c array) : d = Array.of_list (Conjunction_list.make_from_array cs)

 (* n-ary product. The meaning is: (c1 + c2) ⋅ (c3 + c4 + c5) = (c1⋅c3 + c1⋅c4 + c1⋅c5 + c2⋅c3 + c2⋅c4 + c2⋅c5) *)
 let product (ds : d list) : d = 
  if ds = [] then unity else (* continue: *)
  let conj_prod x y = Conjunction.product [x;y] in
  let result = Conjunction_list.map_n_fold_cartesian_product (conj_prod) (List.map Array.to_list ds) in
  Array.of_list result

 type 'a maybe = 'a option
 
 (* In a disjunctive setting, try_lock return the choosen and locked conjunction, if any. *) 
 let try_lock ?guard d : c option maybe =
   if (Array.length d) = 0 then Some None else
   try Some(Some(array_find (Conjunction.try_lock ?guard) d)) with Not_found -> None
  
 (* In a disjunctive setting, the lock is a function that returns the choosen (and locked) conjunction. *) 
 let lock ?guard ?timeout (d:d) : c option = 
 match Array.length d with
 | 1 -> let () = Conjunction.lock ?guard ?timeout d.(0) in Some d.(0) (* Usual case: the disjunction is a singleton *)
 | 0 -> None
 | n when (guard = None) -> begin
    (* When there's not a guard and there's not an immediately free conjunction (try_lock), 
       our simple and perfectible policy is to choose randomly the conjunction to lock. *)
    match try_lock d with   (* try to avoid the random method *)
    | Some result -> result (* bingo! *)
    | None -> 
        (* Choose randomly: *)
        let i = Random.int n in
        let () = Conjunction.lock d.(i) in 
        Some d.(i)
    end
 | n -> 
    match try_lock ?guard d with  (* try to avoid the general but heavy method *)
    | Some result -> result       (* bingo! *)
    | None ->
       (* General (heavy) method involving a thread per basic lock of the conjunction: *)
       begin
        (* All conjunctions are busy or not eligible (guard), so we have to start some parallel threads, sharing an "egg": *)
        let egg_lock = Conjunction.create () in (* it's a unitary conjunction, in other terms a basic lock *)
        let egg = ref None in (* protected by the egg_lock *)
        (* --- *)
        (* Append the egg_lock to all conjunctions (in the last position): *)
        let cs = Array.to_list d in
        let cc's = List.map (fun c -> (c, Conjunction.append c egg_lock)) cs in
        (* --- *)
        let guard = match guard with 
         | None   -> (fun c -> true)                                    (* no guard, never wait *)
         | Some g -> (fun c -> ((!egg) <> None) || (coverup g c false)) (* don't wait if the egg has been released *)
        in
        (* --- *)
        (* Note here that c' is the product (c ⋅ egg_lock). 
           The parameter x is a reference on which the thread notifies its termination: *)
        let thread_behaviour (c,c',x) : unit = begin try
            (* Locking c' we lock also the egg (but the boolean guard is on c). 
               In this way, the waiting is also on c', in order to unlock-relock also the egg_lock: *)
            Conjunction.lock ~guard:(fun _ -> guard c) ?timeout c'; 
            (* --- *)
            (* After locking c' (containing the egg_lock): *)
            x := true;                        (* I'm terminated *) 
            Conjunction.broadcast egg_lock;   (* signal the father and brothers on egg_lock *)
            (* --- *)
            if (!egg) = None
              then begin
                (egg := Some c);              (* I'm the (unique) winner, so I release the involved conjunction c, *)
                Conjunction.unlock egg_lock;  (* and I unlock only the egg_lock (c remains locked) *) 
                end
              else 
                (Conjunction.unlock c')       (* I loose the race, the resource must be immediately unlocked *)
          (* --- *)      
          with Timeout -> () (* Ignore a timeout in a thread: exiting in this way the conjunction isn't locked *)
          end
        (* --- end of thread_behaviour --- *)
        in
        (* The father get the egg_lock before to spawn its children: *)
        Conjunction.lock egg_lock;
        (* Spawn all threads: *)
        let txcs : (Thread.t * (bool ref) * Conjunction.c) list = 
          List.map 
            (fun (c,c') -> 
              let x  = ref false in (* here x means terminated *)
              let t  = Thread.create thread_behaviour (c,c',x) in
              (t,x,c)) 
            cc's 
        in
        (* Now wait for the egg.  *)
        let success : bool = 
          try begin
            let () = 
              match timeout with
              | None -> while ((!egg) = None) do ignore (Conjunction.wait egg_lock); done
              | Some timeout -> 
                  let starting_time = Unix.gettimeofday () in
                  while ((!egg) = None) do
                    (if ((Unix.gettimeofday ()) -. starting_time) > timeout then raise Timeout);
                    ignore (Conjunction.wait egg_lock)
                  done
            in
            true (* Success, no timeout *)
          end                
          with Timeout -> false
        in
        (* Here the egg is done and we have again the egg_lock. *)
        (* --- *)
        (* Now broadcast all living threads on the egg_lock, in order to force them 
           to interrupt their waiting. No "false alarms" are generated directly here. *)
        let living = ref (List.filter (fun (t,x,c) -> not (!x)) txcs) in
        (* --- *)
        while (!living) <> [] do 
          List.iter (fun (t,x,c) -> Conjunction.broadcast egg_lock) (!living);
          ignore (Conjunction.wait egg_lock);
          living := (List.filter (fun (t,x,c) -> not (!x)) (!living));
        done;
        (* --- *)
        (* Here we have again the egg_lock. *)
        let involved_c = match (!egg) with Some c -> c | None -> assert false in
        let () = Conjunction.unlock egg_lock in
        (* --- *)
        if success then Some involved_c else raise Timeout
       end
       
end


include Disjunction

let wait = Conjunction.wait
let broadcast = Conjunction.broadcast
let unlock = Conjunction.unlock

let empty = zero

type t = d (* a "lock" is a disjunction of conjunctions of basic locks *)

(* Alias that helps to clarify the signature of try_lock: *)   
type 'a maybe = 'a option 
type alert = bool

(* A "trailer" is an optional thunk executed out of the critical section, that is to say after unlocking the structure. *)
type trailer = (unit -> unit) option

(* val access  : ?verbose:unit -> ?guard:(c->bool) -> t -> (c -> 'a * alert * trailer) -> 'a *)
(** Execute thunk in a synchronized block, and return the value returned by the thunk. 
    If executing thunk raises an exception, the same exception is propagated, after correctly unlocking. *)
let access ?verbose ?guard ?timeout t (code) =
  (* The following call may raise the Timeout exception, that will be not catched here: *)
  match Disjunction.lock ?guard ?timeout t with 
  | None -> raise Not_found  (* empty disjunction: code cannot be applied *)
  | Some c ->                (* success *)
      try
        (* The idea here is that the `code' recover its environment using the key `c': *)
        let result, alert, trailer = code (c) in
        let () = if alert then Conjunction.broadcast c else () in
        let () = Conjunction.unlock c in
        let () = match trailer with None -> () | Some thunk -> thunk () in
        result
      with e -> begin
        Conjunction.unlock c;
        if verbose = Some () then
          (Printf.eprintf
            "Lock.access: exception %s raised in critical section. Unlocking and re-raising.\n"
            (Printexc.to_string e))
          else ();
        raise e;
      end

(* Non-blocking version: *)
let try_access ?verbose ?guard t (code : c -> 'a * alert * trailer) : 'a option =
  (* try_lock not lock: *)
  match Disjunction.try_lock ?guard t with 
  | None          -> None             (* failure *)
  | Some None     -> raise Not_found  (* success, but empty disjunction: code cannot be applied *)
  | Some (Some c) ->                  (* success *) 
      try
        (* The idea here is that the `code' recover its environment using the key `c': *)
        let result, alert, trailer = code (c) in
        let () = if alert then Conjunction.broadcast c else () in
        let () = Conjunction.unlock c in
        let () = match trailer with None -> () | Some thunk -> thunk () in
        Some result
      with e -> begin
        Conjunction.unlock c;
        if verbose = Some () then
          (Printf.eprintf
            "Lock.access: exception %s raised in critical section. Unlocking and re-raising.\n"
            (Printexc.to_string e))
          else ();
        raise e;
      end
      
