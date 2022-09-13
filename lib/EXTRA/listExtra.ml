(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Jean-Vincent Loddo

   Trivial change in 2008 by Luca Saiu

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

type 'a t = 'a list

(** Filter and map in the same loop using an {e heuristic} function (i.e. a function ['a -> 'b option]). *)
let filter_map ?acc f =
 let acc = match acc with None -> [] | Some l -> l in
 let rec loop acc = function
  | []    -> acc
  | x::xs ->
     (match (f x) with
     | None   -> (loop acc xs)
     | Some y -> y::(loop acc xs)
     )
 in loop acc

(** Filter according to the element and its index in the list (starting from 0). *)
let filteri ?acc p =
 let acc = match acc with None -> [] | Some l -> l in
 let rec loop i = function
 | []    -> acc
 | x::xs ->
     if p i x
       then (x::(loop (i+1) xs))
       else (loop (i+1) xs)
 in loop 0

(** Find and map in the same loop using an {e heuristic} function (i.e. a function ['a -> 'b option]). *)
let rec find_map f =
  function
  | []    -> raise Not_found
  | x::xs ->
     (match (f x) with
     | None   -> (find_map f xs)
     | Some y -> y
     )

(** As standard [List.map] but with the possibility to provide an accumulator (which will be appended to the result). *)
let map ?acc f =
 let acc = match acc with None -> [] | Some l -> l in
 let rec loop acc = function
 | []    -> acc
 | x::xs -> let y = f x in (y::(loop acc xs))
 in loop acc

let mapi ?acc f =
 let acc = match acc with None -> [] | Some l -> l in
 let rec loop i acc = function
 | []    -> acc
 | x::xs -> let y = f i x in (y::(loop (i+1) acc xs))
 in loop 0 acc

(** As standard [List.rev_map] but with the possibility to provide an accumulator (which will be appended to the result). *)
let rev_map ?acc f =
 let acc = match acc with None -> [] | Some l -> l in
 let rec loop acc = function
 | []    -> acc
 | x::xs -> loop ((f x)::acc) xs
 in
 loop acc

let rev_mapi ?acc f =
 let acc = match acc with None -> [] | Some l -> l in
 let rec loop i acc = function
 | []    -> acc
 | x::xs -> let y = f i x in loop (i+1) (y::acc) xs
 in
 loop 0 acc

(** {b Example}:
{[ map_folding (fun s x -> (x+s,s+x)) 0 [0;1;2;3;4;5] ;;
  : int array = [|0; 1; 3; 6; 10; 15|]
]} *)
let map_folding ?acc f s0 =
 let acc = match acc with None -> [] | Some l -> l in
 let rec loop s acc = function
 | []    -> acc
 | x::xs -> let (y,s') = f s x in (y::(loop s' acc xs))
 in loop s0 acc

let mapi_folding ?acc f s0 =
 let acc = match acc with None -> [] | Some l -> l in
 let rec loop s i acc = function
 | []    -> acc
 | x::xs -> let (y,s') = f i s x in (y::(loop s' (i+1) acc xs))
 in loop s0 0 acc

let map_fold ?acc fy fs s0 =
 let acc = match acc with None -> [] | Some l -> l in
 let rec loop s acc = function
 | []    -> (acc, s)
 | x::xs ->
     let y  = fy s x in
     let s' = fs s x in
     let (res_l, res_s) = loop s' acc xs in
     ((y::res_l), res_s)
 in loop s0 acc

let mapi_fold ?acc fy fs s0 =
 let acc = match acc with None -> [] | Some l -> l in
 let rec loop s i acc = function
 | []    -> (acc, s)
 | x::xs ->
     let y  = fy i s x in
     let s' = fs i s x in
     let (res_l, res_s) = loop s' (i+1) acc xs in
     ((y::res_l), res_s)
 in loop s0 0 acc

(** As standard [Array.init] but for lists. *)
let init n f =
 if n<0 then invalid_arg "ListExtra.init" else
 let rec loop i =
   if i = n then [] else
   let x = f i in x::(loop (i+1))
 in loop 0

(** As standard [List.flatten] but with the possibility to provide an accumulator (which will be appended to the result). *)
let flatten ?acc =
 let acc = match acc with None -> [] | Some l -> l in
 let rec loop = function
 | [] -> acc
 | x::xs -> x @ (loop xs)
 in
 loop

(** Like [List.find] but returns an option. *)
let rec search p = function
 | [] -> None
 | x::xs -> if p x then (Some x) else (search p xs)

let searchi p xs =
 let rec loop p i = function
  | [] -> None
  | x::xs -> if p x then (Some (i,x)) else (loop p (i+1) xs)
 in loop p 0 xs

let findi p xs =
 match searchi p xs with
 | None -> raise Not_found
 | Some pair -> pair

(* Like [List.exists] but the predicate provides also a result, which is returned.
   Useful to implement a choice among several fallible procedures. *)
let rec first_success p = function
| []    -> None
| x::xs ->
  (match (p x) with
   | None -> first_success p xs
   | y -> y
   )

let iteri f =
 let rec loop i = function
 | []    -> ()
 | x::xs -> let () = f i x in (loop (i+1) xs)
 in loop 0

let shared_property f = function
 | [] -> true
 | x::xs ->
    let y = lazy (f x) in
    List.for_all (fun x -> (f x)=(Lazy.force y)) xs

(** Move some elements on the top of the list. {b Example}:
{[# lift_to_the_top_positions ((=)"suggested") ["a";"b";"suggested";"c"] ;;
  : string list = ["suggested"; "a"; "b"; "c"]
]}*)
let lift_to_the_top_positions pred xs =
  let (ys,zs) = List.partition pred xs in
  List.append ys zs

(** Similar to the standard [List.hd], but retrieve the list of first elements (by default [n=1] as in [List.hd]).
    Thus, the result is a list. *)
let rec head ?(n:int=1) (l:'a list) : ('a list) =
  if n<=0 then [] else let n = (n-1) in
  match l with
  | []   -> []
  | x::r -> x::(head ~n r)

(** Similar to the standard [List.tl], but the tail is extracted from the given index
    (by default [i=1] as in [List.tl]) *)
let rec tail ?(i:int=1) (l:'a list) =
  if (i=0) then l else tail ~i:(i-1) (List.tl l)

(** Substract the second argument from the first *)
let substract = fun u d -> let p=(fun y -> not (List.mem y d)) in (List.filter p u)

(** [subset a b] check if [a] is a subset of [b], i.e. if all elements of a belong to b. *)
let subset a b = List.for_all (fun x->(List.mem x b)) a

(** [eqset a b] check if a and b represent the same set of values. *)
let eqset a b = (subset a b) && (subset b a)

(** Intersection of list: AvB=A\(A\B) . *)
let intersection a b = substract a (substract a b)

(** Shortcut for [List.iter] with arguments in the opposite order: before the list, then the action to perfom. *)
let foreach l f = List.iter f l

(** Returns a list with no duplicates.
    For large lists we suggest to use {!Hashset.uniq} instead. *)
let rec uniq = function
  | []   -> []
  | x::r -> if (List.mem x r) then (uniq r) else x::(uniq r)

(** As [uniq] but with the optional argument [take_first] you can set the policy for taking elements.
    By default the policy is the opposite of [uniq], i.e. you take the first occurrence, not the last. *)
let remove_duplicates ?(take_first=true) =
 let rec loop acc = match take_first with
 | true  ->
    (function
    | []    -> acc
    | x::xs -> if (List.mem x acc) then (loop acc xs) else (loop (x::acc) xs)
    )
 | false ->
    (function
    | []    -> acc
    | x::xs -> if (List.mem x xs)  then (loop acc xs) else (loop (x::acc) xs)
    )
  in function xs -> List.rev (loop [] xs)
;;

(** {b Example}:
{[# let xs = ['a';'b';'c';'d';'e';'f';'g';'h';'i';'j'] ;;
#ListExtra.amass 3 xs ;;
  : char list list = [['a'; 'b'; 'c']; ['d'; 'e'; 'f']; ['g'; 'h'; 'i']; ['j']]
# xs = List.concat (ListExtra.amass 3 xs) ;;
  : bool = true ]}*)
let amass ~size xs =
  if size <= 0 then invalid_arg "ListExtra.amass: size must be greater than zero" else
  let rec loop i acc1 acc2 xs =
    if i>size then loop 1 [] ((List.rev acc1)::acc2) xs else
    match xs with
    | []    -> if acc1=[] then acc2 else (List.rev acc1)::acc2
    | x::xs -> loop (i+1) (x::acc1) acc2 xs
  in
  List.rev (loop 1 [] [] xs)


(** {b Example}:
{[# int_seq 3 10 2 ;;
  : int list = [3; 5; 7; 9]
]}*)
let int_seq ~min ~max ~incr =
 let rec loop x =
  if x>max then [] else x::(loop (x+incr))
 in
 loop min
;;

let float_seq ~min ~max ~incr =
 let tollerance = incr /. 2. in
 let max = max +. tollerance in
 let rec loop x =
  if x > max then [] else x::(loop (x+.incr))
 in
 loop min
;;

(** [range a b] returns the list [\[a; (a+1); .. ; (b-1); b\]] containing all the values between the given limits (included) . *)
let range (a:int) (b:int) =
  let rec range a b acc = if a>b then acc else (range a (b-1) (b::acc)) in
   range a b []

(** Alias for range. *)
let interval = range

(** The list of indexes of a list. The first index is [0] as usually. *)
let indexes l = range 0 ((List.length l)-1);;

(** Consider a list as a function from indexes to its content. The function is the identity outside the indexes of the list. *)
let asFunction l = fun i -> try (List.nth l i) with _ -> i

(** Considering a list as a record and select some fields (indexes). Example:

{[# select ["aaa";"bbb";"ccc"] [1;2;0;1];;
  : string list = ["bbb"; "ccc"; "aaa"; "bbb"]
]}
     *)
let select (l:'a list) (fieldlist:int list) =
 let a = Array.of_list l in
 let rec loop = function
 | []    -> []
 | f::fl -> (Array.get a f)::(loop fl)
 in loop fieldlist

(**  Example:
{[# select_from_to [0;1;2;3;4;5;6] 2 5 ;;
  : int list = [2; 3; 4; 5]
]} *)
let select_from_to xs a b =
 try
   Array.to_list (Array.sub (Array.of_list xs) a (b-a+1))
 with Invalid_argument _ -> invalid_arg "ArrayExtra.select_from_to"

(** Remove the element with the given index. *)
let rmindex l i =
 let rec rmindex acc = function
  | (0,x::xs) -> List.append (List.rev acc) xs
  | (i,x::xs) -> rmindex (x::acc) (i-1,xs)
  | (_,[])    -> failwith "rmindex: index out of bounds" in
 rmindex [] (i,l)

(** Search for the first index of an element satisfying a property. *)
let indexSuchThat (pred:'a->bool) (l:'a list) : (int option) =
  let rec indexOf pred l i = (match l with
  | []                  -> None
  | y::r when (pred y)  -> Some i
  | y::r                -> indexOf pred r (i+1) )
  in indexOf pred l 0

(** Search for the first index of an element in a list *)
let indexOf (x:'a) (l:'a list) : (int option) = indexSuchThat ((=)x) l

(** Alias for [indexOf]. *)
let firstIndexOf = indexOf

(** Search for the last index of an element in a list *)
let lastIndexOf x l =
  let n = List.length l in
  match indexOf x (List.rev l) with
  | None   -> None
  | Some i -> Some (n-1-i)

(** Returns a permutation of the list. *)
let rec shuffle l = if l = [] then [] else
  let i = Random.int (List.length l) in
  let l'  = (rmindex l i) in
  (List.nth l i)::(shuffle l')

(** List permutation. The first argument is the function [f] that represents the permutation
    (we suppose that this function will be a bijection w.r.t. the set of indexes of the given list).
    In other words [permute f l] is the list [\[(f 0) ; (f 1) ; (f 2) ; ... \] ].  *)
let permute f l = List.map (fun i -> List.nth l (f i)) (indexes l)

(** Return a random permutation function for the given list. *)
(* let shuffler l = l |> (indexes |>| shuffle |>| asFunction) *)
let shuffler l =
  indexes l |> shuffle |> asFunction

(** Return a random list of indexes for the given list. *)
let shuffleIndexes l =
  indexes l |> shuffle

(** The {e folding} of lists is simply a [List.fold_left] specialization:
     - the first element is the {b head} of the list
     - the folding is performed on the {b tail} of the list.
   This function is adequate for most common cases. *)
let big f = function
  | []   -> invalid_arg "ListExtra.big: I cannot fold an empty list"
  | [x]  -> x
  | x::r -> List.fold_left f x r

(* Alias for `big': *)
let fold_binop f = function
  | []   -> invalid_arg "ListExtra.fold_binop: I cannot fold an empty list"
  | [x]  -> x
  | x::r -> List.fold_left f x r

(** {b Common foldings} *)

(** By default the best is the minimal element, i.e. the choice function is set by default to [min]. *)
let best ?(choice=min) = function
 | []    -> invalid_arg "ListExtra.best: empty list"
 | x::xs -> List.fold_left (fun s x -> choice s x) x xs

(** The polymorphic maximum of a list. *)
let max (l:'a list) : 'a = big max l;;

(** The polymorphic minimum of a list. *)
let min (l:'a list) : 'a = big min l;;

(** Transpose the matrix (list of lists). Raise [Invalid_argument "transpose"] if the argument is not a matrix.
{b Example}:
{[# ListExtra.transpose [[1;2;3]; [4;5;6]; [7;8;9]];;
  : int list list = [[1; 4; 7]; [2; 5; 8]; [3; 6; 9]]
]}*)
let transpose ll =
 let aa  = ArrayExtra.Matrix.of_list ll    in
 let aa' = ArrayExtra.Matrix.transpose  aa in
 let ll' = ArrayExtra.Matrix.to_list aa'   in
 ll'

let rec combine3 l1 l2 l3 = match (l1,l2,l3) with
  | []    , []    , []     -> []
  | x1::r1, x2::r2, x3::r3 -> (x1,x2,x3)::(combine3 r1 r2 r3)
  | _ -> raise (Invalid_argument "combine3")

let rec combine4 l1 l2 l3 l4 = match (l1,l2,l3,l4) with
  | []    , []    , []    , []     -> []
  | x1::r1, x2::r2, x3::r3, x4::r4 -> (x1,x2,x3,x4)::(combine4 r1 r2 r3 r4)
  | _ -> raise (Invalid_argument "combine4")

 let rec combine5 l1 l2 l3 l4 l5 = match (l1,l2,l3,l4,l5) with
  | []    , []    , []    , []    , []     -> []
  | x1::r1, x2::r2, x3::r3, x4::r4, x5::r5 -> (x1,x2,x3,x4,x5)::(combine5 r1 r2 r3 r4 r5)
  | _ -> raise (Invalid_argument "combine5")
 ;;

 let rec combine6 l1 l2 l3 l4 l5 l6 = match (l1,l2,l3,l4,l5,l6) with
  | []    , []    , []    , []    , []    , []     -> []
  | x1::r1, x2::r2, x3::r3, x4::r4, x5::r5, x6::r6 -> (x1,x2,x3,x4,x5,x6)::(combine6 r1 r2 r3 r4 r5 r6)
  | _ -> raise (Invalid_argument "combine6")
 ;;

 let rec combine7 l1 l2 l3 l4 l5 l6 l7 = match (l1,l2,l3,l4,l5,l6,l7) with
  | []    , []    , []    , []    , []    , []    , []     -> []
  | x1::r1, x2::r2, x3::r3, x4::r4, x5::r5, x6::r6, x7::r7 -> (x1,x2,x3,x4,x5,x6,x7)::(combine7 r1 r2 r3 r4 r5 r6 r7)
  | _ -> raise (Invalid_argument "combine7")
 ;;

 let rec combine8 l1 l2 l3 l4 l5 l6 l7 l8 = match (l1,l2,l3,l4,l5,l6,l7,l8) with
  | []    , []    , []    , []    , []    , []    , []    , []     -> []
  | x1::r1, x2::r2, x3::r3, x4::r4, x5::r5, x6::r6, x7::r7, x8::r8 -> (x1,x2,x3,x4,x5,x6,x7,x8)::(combine8 r1 r2 r3 r4 r5 r6 r7 r8)
  | _ -> raise (Invalid_argument "combine8")
 ;;

 (** {2 split 2-8} *)

 let split2 = List.split ;;

 let rec split3 l = match l with
 | [] -> ([],[],[])
 | (x1,x2,x3)::r -> let (s1,s2,s3) = (split3 r) in (x1::s1,x2::s2,x3::s3)
 ;;

 let rec split4 l = match l with
 | [] -> ([],[],[],[])
 | (x1,x2,x3,x4)::r -> let (s1,s2,s3,s4) = (split4 r) in (x1::s1,x2::s2,x3::s3,x4::s4)
 ;;

 let rec split5 l = match l with
 | [] -> ([],[],[],[],[])
 | (x1,x2,x3,x4,x5)::r -> let (s1,s2,s3,s4,s5) = (split5 r) in (x1::s1,x2::s2,x3::s3,x4::s4,x5::s5)
 ;;

 let rec split6 l = match l with
 | [] -> ([],[],[],[],[],[])
 | (x1,x2,x3,x4,x5,x6)::r -> let (s1,s2,s3,s4,s5,s6) = (split6 r) in (x1::s1,x2::s2,x3::s3,x4::s4,x5::s5,x6::s6)
 ;;

 let rec split7 l = match l with
 | [] -> ([],[],[],[],[],[],[])
 | (x1,x2,x3,x4,x5,x6,x7)::r -> let (s1,s2,s3,s4,s5,s6,s7) = (split7 r) in (x1::s1,x2::s2,x3::s3,x4::s4,x5::s5,x6::s6,x7::s7)
 ;;

 let rec split8 l = match l with
 | [] -> ([],[],[],[],[],[],[],[])
 | (x1,x2,x3,x4,x5,x6,x7,x8)::r -> let (s1,s2,s3,s4,s5,s6,s7,s8) = (split8 r) in (x1::s1,x2::s2,x3::s3,x4::s4,x5::s5,x6::s6,x7::s7,x8::s8)
 ;;

(** (Heterogeneous) cartesian products: *)

let rec product2 xs ys =
  match xs with
  | []    -> []
  | x::xs -> List.append (List.map (fun y -> (x,y)) ys) (product2 xs ys)
;;

let rec product3 xs ys zs = match xs with x::xs -> List.append (List.map (fun (y,z) -> (x,y,z)) (product2 ys zs)) (product3 xs ys zs) | [] -> [] ;;
let rec product4 xs ys zs us = match xs with x::xs -> List.append (List.map (fun (y,z,u) -> (x,y,z,u)) (product3 ys zs us)) (product4 xs ys zs us) | [] -> [] ;;
let rec product5 xs ys zs us vs = match xs with x::xs -> List.append (List.map (fun (y,z,u,v) -> (x,y,z,u,v)) (product4 ys zs us vs)) (product5 xs ys zs us vs) | [] -> [] ;;
let rec product6 xs ys zs us vs ts = match xs with x::xs -> List.append (List.map (fun (y,z,u,v,t) -> (x,y,z,u,v,t)) (product5 ys zs us vs ts)) (product6 xs ys zs us vs ts) | [] -> [] ;;
let rec product7 xs ys zs us vs ts ws = match xs with x::xs -> List.append (List.map (fun (y,z,u,v,t,w) -> (x,y,z,u,v,t,w)) (product6 ys zs us vs ts ws)) (product7 xs ys zs us vs ts ws) | [] -> [] ;;
let rec product8 xs ys zs us vs ts ws ls = match xs with x::xs -> List.append (List.map (fun (y,z,u,v,t,w,l) -> (x,y,z,u,v,t,w,l)) (product7 ys zs us vs ts ws ls)) (product8 xs ys zs us vs ts ws ls) | [] -> [] ;;

module Homegeneous_cartesian_products = struct

  (* General case: *)
  type 'a n_tuple = 'a list (* a n-tuple i.e. a list (of homogeneous elements) of length 3 *)
  type 'a choices = 'a list

  (** Thanks to Gabriel Scherer for the basic case correction ([] ⊢> [[]])
      and for the more concise definition.
      Source: http://gallium.inria.fr/blog/on-the-nary-cartesian-product/
      ---
      {b Example}:
      # product [[1;2;3];[4;5];[6]] ;;
        : int list list =
      [[1; 4; 6]; [1; 5; 6]; [2; 4; 6]; [2; 5; 6]; [3; 4; 6]; [3; 5; 6]]
      ---
      Generated tuples have the length equals to the number of arguments:
  *)
  let rec product : ('a choices) n_tuple -> ('a n_tuple) choices  =
    function
    | [] -> [[]]
    | xs :: xss ->
        let rest = product xss in
        List.concat
          (List.map (fun x -> List.map (fun r -> x::r) rest) xs)

  (* Slightly more memory-saving than (List.map ∘ product): the last level lists (tuples)
    of the product are directly passed to the mapped function. So, these tuples are made
    and immediately consumed. However, all tuples of intermediary levels (rest) are generated
    as usual with `product'. *)
  let product_map xss f =
    match xss with
    | [] -> [f []]
    | xs :: xss ->
        let rest = product xss in
        List.concat
          (List.map (fun x -> List.map (fun r -> f (x::r)) rest) xs)

  let product0 = product []
  let product1 x1 = product [x1]
  let product2 x1 x2 = product [x1; x2]
  let product3 x1 x2 x3 = product [x1; x2; x3]
  let product4 x1 x2 x3 x4 = product [x1; x2; x3; x4]
  let product5 x1 x2 x3 x4 x5 = product [x1; x2; x3; x4; x5]
  let product6 x1 x2 x3 x4 x5 x6 = product [x1; x2; x3; x4; x5; x6]
  let product7 x1 x2 x3 x4 x5 x6 x7 = product [x1; x2; x3; x4; x5; x6; x7]
  let product8 x1 x2 x3 x4 x5 x6 x7 x8 = product [x1; x2; x3; x4; x5; x6; x7; x8]

end (* Homegeneous_cartesian_products *)

module Assoc = struct

let mem  = List.mem_assoc
let remove  = List.remove_assoc
let find = List.assoc
let add x y xys =
  (x,y)::(List.remove_assoc x xys)

let set xys x y = add x y xys

let rec find_first xs ys = match xs with
| [] -> raise Not_found
| x::xs -> try List.assoc x ys with Not_found -> find_first xs ys

end

module Assq = struct

let mem = List.mem_assq
let remove  = List.remove_assq
let find = List.assq
let add x y xys =
  (x,y)::(List.remove_assq x xys)

let set xys x y = add x y xys

let rec find_first xs ys = match xs with
| [] -> raise Not_found
| x::xs -> try List.assq x ys with Not_found -> find_first xs ys

end

(** {b Example}:
{[
# cut ~lengths:[1;2;3;0;2] [0;1;2;3;4;5;6;7;8;9] ;;
  : int list list = [[0]; [1; 2]; [3; 4; 5]; []; [6; 7]]
]} *)
let cut ~lengths xs =
  let start_len_list_of_lengths xs =
    let js,_ = List.fold_left (fun (js,n) x -> ((n+x)::js,n+x)) ([0],0) xs in
    List.combine (List.rev (List.tl js)) xs
  in
  let a = Array.of_list xs in
  let start_len_list = start_len_list_of_lengths lengths in
  try
    let segments = List.map (fun (start, len) -> Array.sub a start len) start_len_list in
    List.map Array.to_list segments
  with Invalid_argument s -> invalid_arg (Printf.sprintf "ListExtra.cut (%s)" s)


(** Similar to [List.fold_left] but the iterated function takes three values [(xs, x, xs')], instead of just [x], as second argument.
    In any loop, the value [xs] are the elements already treated in a {b reversed} order
    (because it's a zipper, we look at the traversed structure from the [x] point of view).
    Conversely, [xs'] are the elements that will be treated in the next loops, and this list is not reversed.
    See [ListExtra.perm_fold] for an example of application. *)
let fold_left_zipper f y0 =
 let rec loop acc y =
  function
  | [] -> y
  | x::xs ->
     let y' = f y (acc,x,xs) in
     loop (x::acc) y' xs
 in loop [] y0
(** Fold traversing the permutations of the given list.
    {b Example}:
{[# perm_fold (fun () [x;y;z] -> Printf.printf "(%d,%d,%d)\n" x y z) () [1;2;3] ;;
(1,2,3)
(1,3,2)
(2,1,3)
(2,3,1)
(3,1,2)
(3,2,1)
  : unit = ()
]} *)
let rec perm_fold ?disorder f y =
 let append = match disorder with
 | None    -> List.rev_append
 | Some () -> (@)
 in
 function
 | [] -> y
 | x::[] as xs -> f y xs
 | xs ->
    fold_left_zipper
       (fun y (xs,x,xs') -> let f' a bl = f a (x::bl) in perm_fold f' y (append xs xs'))
       y xs


(** Iterate on all permutations of the given list.
    {b Example}:
{[# perm_iter (function [x;y;z] -> Printf.printf "(%d,%d,%d)\n" x y z | _ -> assert false) [1;2;3] ;;
(1,2,3)
(1,3,2)
(2,1,3)
(2,3,1)
(3,1,2)
(3,2,1)
  : unit = ()
]} *)
let perm_iter ?disorder f xs = perm_fold ?disorder (fun () xs -> f xs) () xs

let perm ?disorder xs =
  match disorder with
  | None    -> List.rev (perm_fold (fun y c -> c::y) [] xs)
  | Some () -> perm_fold ~disorder:() (fun y c -> c::y) [] xs

let perm_map ?disorder f xs =
 match disorder with
  | None    -> List.rev (perm_fold (fun y c -> (f c)::y) [] xs)
  | Some () -> perm_fold ~disorder:() (fun y c -> (f c)::y) [] xs


(** Fold traversing the combinations of the given list. *)
let comb_fold ?disorder=
  match disorder with
  | None ->
      fun ~k f y0 xs ->
	let rec loop acc k y xs =
	  if k=1 then List.fold_left (fun y x -> f y (List.rev_append acc [x])) y xs else
	  fold_left_zipper (fun y (_,x,xs') -> loop (x::acc) (k-1) y xs') y xs
        in
        loop [] k y0 xs
  | Some () ->
      fun ~k f y0 xs ->
        (* Here to preserve the equation: comb ~k xs = List.sort compare (comb ~disorder:() ~k xs) supposing xs sorted *)
        let xs = List.rev xs in
	let rec loop acc k y xs =
	  if k=1 then List.fold_left (fun y x -> f y (x::acc)) y xs else
	  fold_left_zipper (fun y (_,x,xs') -> loop (x::acc) (k-1) y xs') y xs
        in
        loop [] k y0 xs


(** Iterate on all combinations of [k] elements of the given list. *)
let comb_iter ?disorder ~k f = comb_fold ?disorder ~k (fun () c -> f c) ()

(** Map a function on all combinations of [k] elements of the given list. *)
let comb_map ?disorder ~k f =
  match disorder with
  | None    -> fun xs -> List.rev (comb_fold ~k (fun y c -> (f c)::y) [] xs)
  | Some () -> comb_fold ~disorder:() ~k (fun y c -> (f c)::y) []

(** Provide the list of all combinations of [k] elements of the given list.
    {b Example}:
{[# comb ~k:2 ['a';'b';'c';'d'] ;;
  : char list list =
[['a'; 'b']; ['a'; 'c']; ['a'; 'd']; ['b'; 'c']; ['b'; 'd']; ['c'; 'd']]
]} *)
let comb ?disorder ~k =
 match disorder with
 | None    -> fun xs -> List.rev (comb_fold ~k (fun y c -> c::y) [] xs)
 | Some () -> comb_fold ~disorder:() ~k (fun y c -> c::y) []

(** The order here is composite: first a k-combination is choosed (in their order), then its permutations are generated (in their order). *)
let k_perm_fold ?disorder ~k f = comb_fold ?disorder ~k (fun y c -> perm_fold ?disorder f y c)

let k_perm_iter ?disorder ~k f = k_perm_fold ?disorder ~k (fun () c -> f c) ()

let k_perm ?disorder ~k =
 match disorder with
 | Some () -> k_perm_fold ~disorder:() ~k (fun y c -> c::y) []
 | None    -> fun xs -> List.rev (k_perm_fold ~k (fun y c -> c::y) [] xs)

let k_perm_map ?disorder ~k f =
 match disorder with
 | None    -> fun xs -> List.rev (k_perm_fold ~k (fun y c -> (f c)::y) [] xs)
 | Some () -> k_perm_fold ~disorder:() ~k (fun y c -> (f c)::y) []


(* --- Monad's operators --- *)

let return x = [x]
let bind m f = List.concat (List.map f m)

(* --- Prefixes --- *)
(**
{[# prefixes [1;2;3] ;;
  : int list list = [[]; [1]; [1; 2]; [1; 2; 3]]
]} *)
let rec prefixes = function
| [] -> [[]]
| x::xs -> []::(List.map (fun p -> x::p) (prefixes xs))

(* val group_by : ('a -> 'b) -> 'a list -> ('b * 'a list) list
  The result is sorted by labels ('b) with standard `compare':
  Example:
    group_by (String.length) [ "a"; "b"; "abc"; "ab"; "bc"; "bcd"; "abcd"; "cd"; "cde"; "defg" ] ;;
    - : (int * string list) list =
    [(1, ["b"; "a"]); (2, ["cd"; "bc"; "ab"]); (3, ["cde"; "bcd"; "abc"]); (4, ["defg"; "abcd"])]
  *)
let group_by f xs =
  let lxs = List.map (fun x -> (f x, x)) xs in
  let ht = Hashtbl.create 0 in
  let () = List.iter (fun (l,x) -> Hashtbl.add ht l x) lxs in
  let keys = Hashtbl.fold (fun l x s -> l::s) ht [] in
  let keys = List.sort_uniq (compare) keys in
  List.map (fun l -> l, Hashtbl.find_all ht l) keys

(* val partition : ('a -> 'b) -> 'a list -> ('a list) list
   As `group_by', but removing labels from the result:
     partition (String.length) [ "a"; "b"; "abc"; "ab"; "bc"; "bcd"; "abcd"; "cd"; "cde"; "defg" ] ;;
     - : string list list = [["b"; "a"]; ["cd"; "bc"; "ab"]; ["cde"; "bcd"; "abc"]; ["defg"; "abcd"]]
  *)
let partition f xs =
  List.map snd (group_by f xs)

(* val is_prefix : ?equality:('a -> 'a -> bool) -> 'a list -> 'a list -> bool *)
let is_prefix ?(equality=(=)) xs ys =
  let rec loop = function
  | ([], _) -> true
  | (x::xs, y::ys) -> if equality x y then loop (xs,ys) else false
  | (_,_) -> false
  in
  loop (xs,ys)

(* val absorption : ?equality:('a -> 'a -> bool) (*(=)*) -> ('a list) list -> ('a list) list
   absorption [ [1]; [2]; [1;2;3]; [1;2]; [2;3]; [2;3;4]; [1;2;3;4]; [3;4]; [3;4;5]; [4;5;6;7] ] ;;
   - : int list list = [[2]; [1]; [3; 4]; [4; 5; 6; 7]]
*)
let absorption ?equality (xs)(*: ('a list) list)*) =
  let is_prefix = is_prefix ?equality in
  let xss = partition (List.length) xs in
  let yss = Array.of_list xss in
  let yss = List.mapi (fun i xs -> List.filter (fun x -> i=0 || List.for_all (fun y -> not (is_prefix y x)) yss.(i-1)) xs) xss in
  List.concat yss

(* --- Printing --- *)

(** {b Examples}:
{[# sprintf "%.2f" [1.;2.;3.;4.] ;;
  : string = "[1.00; 2.00; 3.00; 4.00]"

# sprintf ~frame:"The list is (%s)" ~sep:", " "%.2f" [1.;2.;3.;4.] ;;
  : string = "The list is (1.00, 2.00, 3.00, 4.00)"
]} *)
let sprintf ?frame ?(sep="; ") fmt xs =
  let content = String.concat sep (List.map (Printf.sprintf fmt) xs) in
  match frame with
  | None     -> Printf.sprintf "[%s]" content
  | Some fmt -> Printf.sprintf fmt content

let printf ?frame ?sep fmt xs =
  Printf.printf "%s" (sprintf ?frame ?sep fmt xs)

let eprintf ?frame ?sep fmt xs =
  Printf.eprintf "%s" (sprintf ?frame ?sep fmt xs)

let to_string ?frame ?sep f xs =
  let ys = List.map f xs in
  sprintf ?frame ?sep "%s" ys

(* make (fun x -> if x<10 then Some ([(x,x*x)],x+1) else None) 0 ;;
- : (int * int) list =
[(0, 0); (1, 1); (2, 4); (3, 9); (4, 16); (5, 25); (6, 36); (7, 49); (8, 64); (9, 81)]

make (fun x -> if x<10 then Some ([x;x*x],x+1) else None) 0 ;;
- : int list =
[0; 0; 1; 1; 2; 4; 3; 9; 4; 16; 5; 25; 6; 36; 7; 49; 8; 64; 9; 81]
*)
let rec make f s =
  match f s with
  | None -> []
  | Some (xs, s) -> List.append xs (make f s)


module Memo
 : sig
    class ['a] t : 'a list ->
      object
        method self   : 'a list
        method length : int
        method hd     : 'a
        method tl     : 'a list
        (* --- *)
        method rev : 'a list
        (* --- *)
        method sort   : 'a list
        method sort_uniq : 'a list
        method sort_uniq_reverse : 'a list
        (* --- *)
        method max : 'a
        method min : 'a
      end
    val make : 'a list -> 'a t
  end
 = struct

  class ['a] t (xs:'a list) =
    (* --- *)
    let hd     = lazy (List.hd xs) in
    let tl     = lazy (List.tl xs) in
    let length = lazy (List.length xs) in
    let rev    = lazy (List.rev xs) in
    (* --- *)
    let sort              = lazy (List.sort compare xs) in
    let sort_uniq         = lazy (List.sort_uniq compare xs) in
    let sort_uniq_reverse = lazy (List.sort_uniq (Flip.flip compare) xs) in
    (* --- *)
    let max   = lazy (sort_uniq_reverse |> Lazy.force |> List.hd) in
    let min   = lazy (sort_uniq         |> Lazy.force |> List.hd) in
    (* --- *)
    object
      (* --- *)
      method self   = xs
      method hd     = Lazy.force hd
      method tl     = Lazy.force tl
      method length = Lazy.force length
      (* --- *)
      method rev               = Lazy.force rev
      method sort              = Lazy.force sort
      method sort_uniq         = Lazy.force sort_uniq
      method sort_uniq_reverse = Lazy.force sort_uniq_reverse
      (* --- *)
      method max   = Lazy.force max
      method min   = Lazy.force min
      (* --- *)
    end

  let make xs = new t(xs)

end

(* Tools for "chains", aka sorted, totally ordered lists without duplicates. *)
module Chain = struct

  type 'a t = 'a list

  (*  Examples:
      is_subset (compare) [11;15] [7;9;11;13;14;15] ;;
      - : bool = true
      is_subset (compare) [1;7;11;15] [7;9;11;13;14;15] ;;
      - : bool = false
      is_subset (compare) [7;11;15;16] [7;9;11;13;14;15] ;;
      - : bool = false
      ---
      val is_subset : ?compare:('a -> 'a -> int) -> 'a t -> 'a t -> bool
      ---
      The smallest one (fst) is always late, starts later and arrives earlier: *)
  let is_subset ?(compare=compare) =
    let rec loop = function
    | ([],[])    -> true
    | (x::xs,[]) -> false
    | ([],y::ys) -> true
    | ((x::xs) as xxs, y::ys) ->
        (match compare x y with
        | (-1) -> false
        |   0  -> loop (xs, ys)
        |   1  -> loop (xxs, ys)
        |   _  -> assert false
        )
    in
    fun xs ys -> loop (xs, ys)

end (* Chain *)
