(* This file is part of ocamlbricks
   Copyright (C) 2017  Jean-Vincent Loddo

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

module Set_as_array
 : sig
    type 'a t = 'a array
    type 'a compare = 'a -> 'a -> int
    (* --- *)
    val sum         : ?compare:('a compare) -> 'a t list -> 'a t
    val product     : ?compare:('a compare) -> 'a t list -> 'a list t 
    val product_map : ?compare:('b compare) -> 'a t list -> ('a list -> 'b) -> 'b t 
    (* --- *)
    val product1_map : ?compare:('b compare) -> 'a t -> ('a -> 'b) -> 'b t
    val product2_map : ?compare:('c compare) -> 'a t -> 'b t -> ('a -> 'b -> 'c) -> 'c t
    val product3_map : ?compare:('d compare) -> 'a t -> 'b t -> 'c t -> ('a -> 'b -> 'c -> 'd) -> 'd t
    val product4_map : ?compare:('e compare) -> 'a t -> 'b t -> 'c t -> 'd t -> ('a -> 'b -> 'c -> 'd -> 'e) -> 'e t
    val product5_map : ?compare:('f compare) -> 'a t -> 'b t -> 'c t -> 'd t -> 'e t -> ('a -> 'b -> 'c -> 'd -> 'e -> 'f) -> 'f t
    (* --- *)
   end
 = struct

 type 'a t = 'a array
 type 'a compare = 'a -> 'a -> int

 let sum ?(compare=compare) (ts : 'a t list) : 'a t = 
   Array.of_list (List.sort_uniq compare (Array.to_list (Array.concat ts)))
 
 let p2 (xs:'a t) (ys:'b t) : ('a * 'b) t = 
   let f = fun v l -> Array.map (fun x -> (v,x)) l in
   Array.concat (Array.to_list (Array.map (fun v -> f v ys) xs))

 let p2_map (xs:'a t) (ys:'b t) g : 'c t = 
   let f = fun v l -> Array.map (fun x -> g v x) l in
   Array.concat (Array.to_list (Array.map (fun v -> f v ys) xs))
   
 let p3 (xs:'a t) (ys:'b t) (zs:'c t) : ('a * 'b * 'c) t = 
   let f = fun v l -> Array.map (fun (x,y) -> (v,x,y)) l in
   Array.concat (Array.to_list (Array.map (fun v -> f v (p2 ys zs)) xs))

 let p3_map (xs:'a t) (ys:'b t) (zs:'c t) g : 'd t = 
   let f = fun v l -> Array.map (fun (x,y) -> g v x y) l in
   Array.concat (Array.to_list (Array.map (fun v -> f v (p2 ys zs)) xs))
   
 let p4 (xs:'a t) (ys:'b t) (zs:'c t) (ts:'d t) : 'e t = 
   let f = fun v l -> Array.map (fun (x,y,z) -> (v,x,y,z)) l in
   Array.concat (Array.to_list (Array.map (fun v -> f v (p3 ys zs ts)) xs))

 let p4_map (xs:'a t) (ys:'b t) (zs:'c t) (ts:'d t) g : 'e t = 
   let f = fun v l -> Array.map (fun (x,y,z) -> g v x y z) l in
   Array.concat (Array.to_list (Array.map (fun v -> f v (p3 ys zs ts)) xs))
   
 let p5 (xs:'a t) (ys:'b t) (zs:'c t) (ts:'d t) (ws:'e t) : ('a * 'b * 'c * 'd * 'e) t = 
   let f = fun v l -> Array.map (fun (x,y,z,t) -> (v,x,y,z,t)) l in
   Array.concat (Array.to_list (Array.map (fun v -> f v (p4 ys zs ts ws)) xs))

 let p5_map (xs:'a t) (ys:'b t) (zs:'c t) (ts:'d t) (ws:'e t) g : 'f t = 
   let f = fun v l -> Array.map (fun (x,y,z,t) -> g v x y z t) l in
   Array.concat (Array.to_list (Array.map (fun v -> f v (p4 ys zs ts ws)) xs))

 (* --- *)
 
 let product1_map ?(compare=compare) xs g = 
   Array.of_list (List.sort_uniq compare (Array.to_list (Array.map g xs)))
 
 let product2_map ?(compare=compare) xs ys g = 
   Array.of_list (List.sort_uniq compare (Array.to_list (p2_map xs ys g)))
 
 let product3_map ?(compare=compare) xs ys zs g = 
   Array.of_list (List.sort_uniq compare (Array.to_list (p3_map xs ys zs g)))
 
 let product4_map ?(compare=compare) xs ys zs ts g = 
   Array.of_list (List.sort_uniq compare (Array.to_list (p4_map xs ys zs ts g)))
 
 let product5_map ?(compare=compare) xs ys zs ts ws g = 
   Array.of_list (List.sort_uniq compare (Array.to_list (p5_map xs ys zs ts ws g)))

 (* --- *)
  
 let rec product (xss:'a t list) : ('a list) t = 
   let f = fun v l -> Array.map (fun vs -> v::vs) l in
   match xss with
   | [] -> [|[]|]
   | xs::xss -> Array.concat (Array.to_list (Array.map (fun v -> f v (product xss)) xs)) 

 let product_map ?(compare=compare) xss (f:'a list -> 'b) : 'b t = 
   Array.of_list (List.sort_uniq (compare) (Array.to_list (Array.map f (product xss))))
   
 (* Lexicographic extensions of `compare' for lists: *)
 let compare_list ~compare =
   let rec loop xs ys = 
     match (xs,ys) with
     | [],[] -> 0
     | [], _ -> (-1)
     | _ ,[] -> 1
     | x::xs, y::ys -> 
         let result = compare x y in
         if result = 0 then loop xs ys else result
   in loop
   
 (* Redefinition (sort_uniq): *)  
 let product ?(compare=compare) xss = 
   Array.of_list (List.sort_uniq (compare_list ~compare) (Array.to_list (product xss)))

   
end (* Set_as_array *)


module Disjunction :
  sig
    (* --- *)
    type 'a d = ('a c) array
     and 'a c = Lock.c * 'a
     and 'a locked = ('a c) option (* the actual locked value, if any (i.e. if the disjunction is not empty) *)
    (* --- *)
    val return   : 'a -> 'a d           (* make a structure protected by a basic lock (mutex) *)
    val fictive  : 'a -> 'a d           (* make a not really protected structure (i.e. protected by the empty set of conjunctions) *)
    (* --- *)
    val zero     : 'a d                 (* identity element of the sum (the empty set of conjunctions) *)
    val sum      : ('a d) list -> 'a d
    (* --- *)
    (* Simple products: *)
    val product  : ('a d) list -> ('a list) d
    val product2 : ('a d) -> ('b d) -> ('a * 'b) d
    val product3 : ('a d) -> ('b d) -> ('c d) -> ('a * 'b * 'c) d
    val product4 : ('a d) -> ('b d) -> ('c d) -> ('d d) -> ('a * 'b * 'c * 'd) d
    val product5 : ('a d) -> ('b d) -> ('c d) -> ('d d) -> ('e d) -> ('a * 'b * 'c * 'd * 'e) d
    (* --- *)
    (* Compositional products: *)
    val cproduct  : ('a d) list -> ('a list -> 'alist) -> ('alist) d
    val cproduct2 : ('a d) -> ('b d) -> ('a -> 'b -> 'ab) -> ('ab) d
    val cproduct3 : ('a d) -> ('b d) -> ('c d) -> ('a -> 'b -> 'c -> 'abc) -> ('abc) d
    val cproduct4 : ('a d) -> ('b d) -> ('c d) -> ('d d) -> ('a -> 'b -> 'c -> 'd -> 'abcd) -> ('abcd) d
    val cproduct5 : ('a d) -> ('b d) -> ('c d) -> ('d d) -> ('e d) -> ('a -> 'b -> 'c -> 'd -> 'e -> 'abcde) -> ('abcde) d
    (* --- *)
    val try_lock  : ?guard:('a -> bool) -> 'a d -> ('a locked) option
    val lock      : ?guard:('a -> bool) -> ?timeout:float -> 'a d -> 'a locked
    val wait      : 'a locked -> Lock.b option  (* the result is the basic lock where something has happen, if any *)
    val broadcast : 'a locked -> unit           (* alert the involved conjunction *)
    val unlock    : 'a locked -> unit
  end

 = struct 

 type 'a d = ('a c) array
  and 'a c = Lock.Conjunction.c * 'a
  and 'a locked = ('a c) option (* the actual locked value, if any (i.e. if the disjunction is not empty) *)
  
 let return a = 
   let c = Lock.Conjunction.create () in 
   Array.make 1 (c,a)

 let fictive a = 
   let c = Lock.Conjunction.unity in 
   Array.make 1 (c,a)

 let zero = [||]
 let unity = [| (Lock.Conjunction.unity, ()) |] (* the "unity" is the singleton containing the empty conjunction of locks *)
 
 (* The same lock should not be associated to distinct memory adresses. But using fictive locks and composing them
    with real mutexes, we can obtain distinct structures locked by the same conjunction. Thus, the compare 
    function is quite complex and acts on memory addresses. Furthermore, the behaviour of this function is not
    ideal, because it differentiate some structures that we should consider the same. For instance:
    
    let x, y = (ref 0), (ref 0) ;;                          (* distinct structures (currently) hosting the same value *)
    let v1, v2, v3 = ('A',x), ('A',x), ('A',y) ;;           (* v1 and v2 will host forever the same content *)
    v1==v2, v1==v3, v2==v3 ;;                               (* (false, false, false) => not the equality I would *)
    v1=v2,  v1=v3,  v2=v3  ;;                               (* (true,  true,  true)  => not the equality I would *)
    
    The structure v1 and v2 will host forever the same value because their persistent parts are identical and 
    their mutable part are at the same address. So, ideally, the same lock may be used for v1 and v2.
    The compare function I would (may be written in OCaml?), should generate an equality such that:
    v1=v2,  v1=v3,  v2=v3  ;; (* (true, false, false) *)
    *)
 let compare = 
   (* Hack from: https://rosettacode.org/wiki/Address_of_a_variable#OCaml*)
   let address_of (x:'a) : nativeint =
     if Obj.is_block (Obj.repr x) then
       Nativeint.shift_left (Nativeint.of_int (Obj.magic x)) 1 (* magic *)
     else
       raise Not_found
   in
   fun (c,a) (c',a') -> 
     match (Lock.Conjunction.compare c c') with
     | 0 -> 
       (* If locks are equals, the comparaison acts on memory adresses of the related data structure: *)
       Printf.kfprintf flush stderr "WARNING: lock comparison is 0\n";
       if (a == a') then 0 else (* continue *)
       (* If fictive locks had been avoided, the code here should simply be (assert false) *)
       let () = Printf.kfprintf flush stderr "WARNING: lock comparison is 0 and addresses are different\n" in
       (try
          let m, m' = (address_of a), (address_of a') in
          Pervasives.compare m m'
       with
          (* Unboxed persistent value. We can apply Pervasives.compare: *)
          Not_found -> 
            Printf.kfprintf flush stderr "WARNING: unboxed values\n";
            Pervasives.compare a a')
     (* --- *)     
     | result -> result

 (* n-ary sum. The meaning is: (c1 + c2) + c3 = (c1 + c2 + c3) *)
 let sum (ds : 'a d list) : 'a d = 
   Set_as_array.sum ~compare ds

 (* n-ary product. The meaning is: (c1 + c2) ⋅ (c3 + c4 + c5) = (c1⋅c3 + c1⋅c4 + c1⋅c5 + c2⋅c3 + c2⋅c4 + c2⋅c5) *)
 let product (ds : 'a d list) : ('a list) d = 
  if ds = [] then (assert false) else (* continue: *)
  let list_folding cxs = 
    let cs,xs = List.split cxs in
    (Lock.Conjunction.product cs, xs)
  in
  Set_as_array.product_map ~compare ds (list_folding)

 (* n-ary compositional product. *)
 let cproduct (ds : 'a d list) (f:'a list -> 'alist) : ('alist) d = 
  if ds = [] then (assert false) else (* continue: *)
  let list_folding cxs = 
    let cs,xs = List.split cxs in
    (Lock.Conjunction.product cs, f xs)
  in
  Set_as_array.product_map ~compare ds (list_folding)
  
 let product2 (d1 : 'a d) (d2 : 'b d) : ('a * 'b) d = 
  let fusion (c1,a) (c2,b) = (Lock.Conjunction.product [c1;c2], (a,b)) in
  Set_as_array.product2_map ~compare d1 d2 (fusion)
  
 let cproduct2 (d1 : 'a d) (d2 : 'b d) (f:'a -> 'b -> 'ab) : 'ab d = 
  let fusion (c1,a) (c2,b) = (Lock.Conjunction.product [c1;c2], f a b) in
  Set_as_array.product2_map ~compare d1 d2 (fusion)
  
 let product3 (d1 : 'a d) (d2 : 'b d) (d3 : 'c d) : ('a * 'b * 'c) d = 
  let fusion (c1,a) (c2,b) (c3,c) = (Lock.Conjunction.product [c1;c2;c3], (a,b,c)) in
  Set_as_array.product3_map ~compare d1 d2 d3 (fusion)

 let cproduct3 (d1 : 'a d) (d2 : 'b d) (d3 : 'c d) (f:'a -> 'b -> 'c -> 'abc) : ('abc) d = 
  let fusion (c1,a) (c2,b) (c3,c) = (Lock.Conjunction.product [c1;c2;c3], f a b c) in
  Set_as_array.product3_map ~compare d1 d2 d3 (fusion)
  
 let product4 (d1 : 'a d) (d2 : 'b d) (d3 : 'c d) (d4 : 'd d) : ('a * 'b * 'c * 'd) d = 
  let fusion (c1,a) (c2,b) (c3,c) (c4,d) = (Lock.Conjunction.product [c1;c2;c3;c4], (a,b,c,d)) in
  Set_as_array.product4_map ~compare d1 d2 d3 d4 (fusion)
  
 let cproduct4 (d1 : 'a d) (d2 : 'b d) (d3 : 'c d) (d4 : 'd d) (f:'a -> 'b -> 'c -> 'd -> 'abcd) : ('abcd) d = 
  let fusion (c1,a) (c2,b) (c3,c) (c4,d) = (Lock.Conjunction.product [c1;c2;c3;c4], f a b c d) in
  Set_as_array.product4_map ~compare d1 d2 d3 d4 (fusion)

 let product5 (d1 : 'a d) (d2 : 'b d) (d3 : 'c d) (d4 : 'd d) (d5 : 'e d) : ('a * 'b * 'c * 'd * 'e) d = 
  let fusion (c1,a) (c2,b) (c3,c) (c4,d) (c5,e) = (Lock.Conjunction.product [c1;c2;c3;c4;c5], (a,b,c,d,e)) in
  Set_as_array.product5_map ~compare d1 d2 d3 d4 d5 (fusion)

 let cproduct5 (d1 : 'a d) (d2 : 'b d) (d3 : 'c d) (d4 : 'd d) (d5 : 'e d) (f:'a -> 'b -> 'c -> 'd -> 'e -> 'abcde) : ('abcde) d = 
  let fusion (c1,a) (c2,b) (c3,c) (c4,d) (c5,e) = (Lock.Conjunction.product [c1;c2;c3;c4;c5], f a b c d e) in
  Set_as_array.product5_map ~compare d1 d2 d3 d4 d5 (fusion)
  
 type 'a maybe = 'a option
 
 let hashtbl_of t =
   let size = (Array.length t) * 2 in
   let ht = Hashtbl.create (size) in
   let () = Array.iter (fun (c,a) -> Hashtbl.add ht c a) t in
   ht

 let adapt_guard ?guard (* 'a -> bool *) (ht) (involved:'a option ref) : (Lock.c -> bool) option = 
  match guard with
  | None   -> None
  | Some g -> 
     (* --- *)  
     let guard c = 
       (* Note that this guard is always executed in mutual exclusion (see Lock.Disjunction.lock).
          Hence the access of the reference `involved' is protected: conflicting access are avoided. *)
       if (!involved) <> None then false else (* continue: *)   
       try
         let xs = Hashtbl.find_all ht c in (* ht is shared but read-only *)
         (* The provided guard g is tested on all values associated to the same lock: *)
         let x = List.find (fun x -> try g x with _ -> false) xs in
         (* --- *)
         let () = (involved := Some (c,x)) in 
         true (* <= This guard will not be never re-executed *)
       with Not_found -> false
     (* --- *)  
     in
     Some guard
   
 let try_lock ?guard (t : 'a d) : 'a c option maybe =
   let ht = hashtbl_of t in
   let involved = ref None in (* involved structure *)
   let guard = adapt_guard ?guard (ht) (involved) in
   let cs = Array.map fst t in
   let d = Lock.of_conjunction_array cs in (* <= duplicated locks are removed here *)
   match Lock.try_lock ?guard d with
   | None -> None
   | Some (None) -> Some (None)
   | Some (Some c) -> 
       (match !involved with
       | Some (c',x) -> let () = assert (c' == c) in Some (Some (c,x))
       | None -> if guard = None then Some (Some (c, Hashtbl.find ht c)) else assert false)

 let lock ?guard ?timeout (t : 'a d) : 'a c option = 
   let ht = hashtbl_of t in
   let involved = ref None in (* involved structure *)
   let guard = adapt_guard ?guard (ht) (involved) in
   let cs = Array.map fst t in
   let d = Lock.of_conjunction_array cs in (* <= duplicated locks are removed here *)
   match Lock.lock ?guard ?timeout d with
   | None -> None
   | Some c -> 
       (match !involved with
       | Some (c',x) -> let () = assert (c' == c) in Some (c,x)
       | None -> if guard = None then Some (c, Hashtbl.find ht c) else assert false)

 (* val unlock : 'a locked -> unit *)
 let unlock = function
 | None -> ()
 | Some (c,a) -> Lock.unlock c

 (* val wait : 'a locked -> Lock.b option  (* the result is the basic lock where something has happen, if any *) *)
 let wait = function
 | None -> None
 | Some (c,a) -> Lock.wait c

 (* val broadcast : 'a locked -> unit  (* alert the involved conjunction *) *)
  let broadcast = function
 | None -> ()
 | Some (c,a) -> Lock.broadcast c

end


include Disjunction

(* Should we alert other threads waiting on this structure? In other terms, should we perform a broadcast? *)
type alert = bool

(* A "trailer" is an optional thunk executed out of the critical section, that is to say after unlocking the structure. *)
type trailer = (unit -> unit) option

(** Execute thunk in a synchronized block, and return the value returned by the thunk. 
    If executing thunk raises an exception, the same exception is propagated, after correctly unlocking. *)
(*  val access : ?verbose:unit -> ?guard:('a->bool) -> ?timeout:float -> 'a d -> ('a -> 'b * alert * trailer) -> 'b *)
let access ?verbose ?guard ?timeout t (code) =
  (* The following call may raise the Timeout exception, that will be not catched here: *)
  let locked = Disjunction.lock ?guard ?timeout t in
    match locked with 
    | None -> raise Not_found
    | Some (c,a) ->
       (try
          let result, alert, trailer = code a in
          let () = if alert then Lock.broadcast c else () in
          let () = Lock.unlock c in
          let () = match trailer with None -> () | Some thunk -> thunk () in
          result
        with e -> begin
          Lock.unlock c;
          if verbose = Some () then
            (Printf.eprintf
              "Locked.access: exception %s raised in critical section. Unlocking and re-raising.\n"
              (Printexc.to_string e))
            else ();
          raise e;
        end)


(* Simplified interface: *)
let easy_access t (code) =
  let locked = Disjunction.lock t in
    match locked with 
    | None -> raise Not_found
    | Some (c,a) ->
       (try
          let result = code a in
          let () = Lock.unlock c in
          result
        with e -> begin
          Lock.unlock c;
          raise e;
        end)
        
(* val try_access : ?verbose:unit -> ?guard:('a->bool) -> 'a t -> ('a -> 'b * alert * trailer) -> 'b option *)
let try_access ?verbose ?guard t (code) =
  let locked = Disjunction.try_lock ?guard t in
    match locked with 
    | None              -> None              (* failure *)
    | Some None         -> raise Not_found   (* success, but empty disjunction: code cannot be applied *) 
    | Some (Some (c,a)) ->                   (* success *) 
       (try
          let result, alert, trailer = code a in
          let () = if alert then Lock.broadcast c else () in
          let () = Lock.unlock c in
          let () = match trailer with None -> () | Some thunk -> thunk () in
          Some result
        with e -> begin
          Lock.unlock c;
          if verbose = Some () then
            (Printf.eprintf
              "Locked.access: exception %s raised in critical section. Unlocking and re-raising.\n"
              (Printexc.to_string e))
            else ();
          raise e;
        end)

(* Simplified interface: *)
let easy_try_access t (code) =
  let locked = Disjunction.try_lock t in
    match locked with 
    | None              -> None              (* failure *)
    | Some None         -> raise Not_found   (* success, but empty disjunction: code cannot be applied *) 
    | Some (Some (c,a)) ->                   (* success *) 
       (try
          let result = code a in
          let () = Lock.unlock c in
          Some result
        with e -> begin
          Lock.unlock c;
          raise e;
        end)
        
let empty = zero
let make = return
let unity = fictive

type 'a t = 'a d

(* val constructor : ('a -> 'b) -> 'a -> 'b d *)
let constructor f = fun x -> return (f x)

let involved_locks = function
 | None -> [||]
 | Some (c,a) -> c
 
