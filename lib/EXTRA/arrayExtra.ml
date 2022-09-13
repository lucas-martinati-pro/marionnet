(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009 Jean-Vincent Loddo

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

type 'a t = 'a array

(* Equivalent to the standard [Array.of_list] but the list is not scanned twice.
    The function raises [Invalid_argument] if the real length of the list differs
    from the announced one. *)
let of_known_length_list ?(reversing=false) len =
  let errmsg1 = "unexpected list length (overstated size)"  in
  let errmsg2 = "unexpected list length (understated size)" in
  function
  | []    -> [||]
  | x::xs ->
      let a = Array.make len x in
      (* --- *)
      if reversing then begin
        let rec loop i = function
        | []    -> (if i=(-1) then a else invalid_arg errmsg1)
        | x::xs -> (try a.(i) <- x with _ -> invalid_arg errmsg2); loop (i-1) xs
        in
        loop (len-2) xs
      end
      (* --- *)
      else begin
        let rec loop i = function
        | []    -> (if i=len then a else invalid_arg errmsg1)
        | x::xs -> (try a.(i) <- x with _ -> invalid_arg errmsg2); loop (i+1) xs
        in
        loop 1 xs
      end

(** {b Example}:
{[
# init2 3 (fun i -> (i+1,i*2)) ;;
  : int array * int array = ([|1; 2; 3|], [|0; 2; 4|])
]} *)
let init2 n f =
  if n = 0 then ([||],[||]) else
  let (x0,y0) = f 0 in
  let xs = Array.make n x0 in
  let ys = Array.make n y0 in
  for i = 1 to (n-1) do
    let (x,y) = f i in
    xs.(i) <- x;
    ys.(i) <- y;
  done;
  (xs,ys)

let split xys = init2 (Array.length xys) (fun i -> xys.(i))
let combine xs ys = Array.init (Array.length xs) (fun i -> xs.(i), ys.(i))

(** {b Example}:
{[
# product2 [|1;2;3|] [|'a';'b'|] ;;
  : (int * char) array = [|(1, 'a'); (1, 'b'); (2, 'a'); (2, 'b'); (3, 'a'); (3, 'b')|]
]} *)
let product2 xs ys =
  let n1 = Array.length xs in
  let n2 = Array.length ys in
  let n = n1 * n2 in
  if n=0 then [||] else
  let xys = Array.make n (xs.(0), ys.(0)) in
  (* --- *)
  let () =
    for i = 0 to (n1-1) do
      let offset = i * n2 in
      for j = 0 to (n2-1) do
        xys.(offset + j) <- (xs.(i), ys.(j))
      done;
    done
  in
  (* --- *)
  xys

(* val product_fold_left2  : 'a array -> 'b array -> 's -> ('s -> 'a -> 'b -> 's) -> 's
   ---
   product_fold_left2 [|1;2;3|] [|"aaa";"bbb"|] [] (fun s x y -> (x,y)::s) ;;
   - : (int * string) list =
   [(3, "bbb"); (3, "aaa"); (2, "bbb"); (2, "aaa"); (1, "bbb"); (1, "aaa")]
*)
let product_fold_left2 xs ys s f =
  let n1 = Array.length xs in
  let n2 = Array.length ys in
  let n = n1 * n2 in
  if n=0 then s else
  (* --- *)
  let s = ref s in
  let () =
    for i = 0 to (n1-1) do
      for j = 0 to (n2-1) do
        s := f (!s) xs.(i) ys.(j)
      done;
    done
  in
  (* --- *)
  (!s)

(* val product_fold_lefti2  : 'a array -> 'b array -> 's -> (int * int -> 's -> 'a -> 'b -> 's) -> 's
   ---
   product_fold_lefti2 [|true; false|] [|"aaa";"bbb"|] [] (fun ij s x y -> (ij,(x,y))::s) ;;
   - : ((int * int) * (bool * string)) list =
   [((1, 1), (false, "bbb")); ((1, 0), (false, "aaa")); ((0, 1), (true, "bbb")); ((0, 0), (true, "aaa"))]
*)
let product_fold_lefti2 xs ys s f =
  let n1 = Array.length xs in
  let n2 = Array.length ys in
  let n = n1 * n2 in
  if n=0 then s else
  (* --- *)
  let s = ref s in
  let () =
    for i = 0 to (n1-1) do
      for j = 0 to (n2-1) do
        s := f (i,j) (!s) xs.(i) ys.(j)
      done;
    done
  in
  (* --- *)
  (!s)

(* val product3 : 'a array -> 'b array -> 'c array -> ('a * 'b * 'c) array *)
let product3 xs ys zs =
  let n1 = Array.length xs in
  let n2 = Array.length ys in
  let n3 = Array.length zs in
  let n = n1 * n2 * n3 in
  if n=0 then [||] else
  let xyzs = Array.make n (xs.(0), ys.(0), zs.(0)) in
  (* --- *)
  let () =
    let n23 = n2 * n3 in
    for i = 0 to (n1-1) do
      let offset1 = i * n23 in
      for j = 0 to (n2-1) do
        let offset2 = offset1 + j * n3 in
          for h = 0 to (n3-1) do
            xyzs.(offset2 + h) <- (xs.(i), ys.(j), zs.(h))
          done;
      done;
    done
  in
  (* --- *)
  xyzs



let sorted_copy ?(compare=(*Pervasives.*)compare) xs =
  let ys = (Array.copy xs) in
  (Array.sort compare ys);
  ys

let fast_sorted_copy ?(compare=(*Pervasives.*)compare) xs =
  let ys = (Array.copy xs) in
  (Array.fast_sort compare ys);
  ys

(** Sort the array saving the position of each element in the original array. {b Example}:
{[ ArrayExtra.sort_saving_positions [| 6.28; 3.14; 1.41; 2.71 |] ;;
  : (int * float) array = [|(2, 1.41); (3, 2.71); (1, 3.14); (0, 6.28)|]
]} *)
let sort_saving_positions ?(compare=(*Pervasives.*)compare) (xs:'a array) : (int * 'a) array =
  let ys = Array.mapi (fun i x -> (x,i)) xs in
  let () = Array.sort (fun (x,_) (y,_) ->  compare x y) ys in
  Array.map (fun (p,i) -> (i,p)) ys

let sort_saving_permutation ?(compare=(*Pervasives.*)compare) (xs:'a array) : (int array) * ('a array) =
  let ys = Array.mapi (fun i x -> (x,i)) xs in
  let () = Array.sort (fun (x,_) (y,_) ->  compare x y) ys in
  let xs, js = split ys in
  (js, xs)

(** {b Example}:
{[ let xs = [| 23; 21; 10; 5; 9; 0; 2; 12; |] ;;
let js, ys = ArrayExtra.sort_saving_permutation xs ;;
val js : int array = [|5; 6; 3; 4; 2; 7; 1; 0|]
val ys : int array = [|0; 2; 5; 9; 10; 12; 21; 23|]
ys = (ArrayExtra.apply_permutation js xs) ;;
 : bool = true
xs = (ArrayExtra.undo_permutation js ys) ;;
 : bool = true ]} *)
let apply_permutation js xs =
  let ys = Array.copy xs in
  let () = Array.iteri (fun i j -> ys.(i) <- xs.(j)) js in
  ys

let undo_permutation js xs =
  let ys = Array.copy xs in
  let () = Array.iteri (fun i j -> ys.(j) <- xs.(i)) js in
  ys

let is_sorted ?(compare=(*Pervasives.*)compare) s : bool =
 let l = Array.length s in
 if l = 0 then true else (* continue: *)
 let rec loop pred i =
  if i>=l then true else
  let x = s.(i) in
  if (compare pred x) = 1 then false else loop x (i+1)
 in loop s.(0) 1

let sort_in_the_same_way ?compare xs yss =
  let perm, xs' = sort_saving_permutation ?compare xs in
  let yss' = List.map (apply_permutation perm) yss in
  perm, xs', yss'

(** {b Example}:
{[# int_seq 3 10 2 ;;
  : int array = [|3; 5; 7; 9|]
]}*)
let int_seq ~min ~max ~incr =
 let rec loop x =
  if x>max then [] else x::(loop (x+incr))
 in
 let xs = loop min in
 Array.of_list xs

let float_seq ~min ~max ~incr =
 let tollerance = incr /. 2. in
 let max = max +. tollerance in
 let rec loop x =
  if x>max then [] else x::(loop (x+.incr))
 in
 let xs = loop min in
 Array.of_list xs

(** Similar to the standard [List.for_all], implemented directly, i.e. without conversion. *)
let for_all p s =
 let l = Array.length s in
 let rec loop i =
  if i>=l then true else
  (p i s.(i)) && loop (i+1)
 in loop 0

(** Similar to the standard [List.exists], implemented directly, i.e. without conversion. *)
let exists p s =
 let l = Array.length s in
 let rec loop i =
  if i>=l then false else
  (p i s.(i)) || loop (i+1)
 in loop 0

(** As the function [exists], but provides the index that verifies the predicate. *)
let lexists p s =
 let l = Array.length s in
 let rec loop i =
  if i>=l then None else
  if (p i s.(i)) then (Some i) else loop (i+1)
 in loop 0

(** As the function [lexists], but searching from the right side. *)
let rexists p s =
 let l = Array.length s in
 let rec loop i =
  if i<0 then None else
  if (p i s.(i)) then (Some i) else loop (i-1)
 in loop (l-1)

let search p s =
 let l = Array.length s in
 let rec loop i =
  if i>=l then None else
  let x = s.(i) in
  if (p x) then (Some x) else loop (i+1)
 in loop 0

let searchi p s =
 let l = Array.length s in
 let rec loop i =
  if i>=l then None else
  let x = s.(i) in
  if (p x) then (Some (i,x)) else loop (i+1)
 in loop 0

(* A deterministic random generator: *)
let random_int =
  let seed = Random.get_state (Random.init 72152816) in
  Random.State.int seed

(* val findi_opt :
      ?round_from:int ->
      ?round_from_random:unit ->
      ('a -> bool) -> 'a array -> (int * 'a) option
    Example:
      findi_opt ~round_from_random:() (Pred.even) [|1; 30; 5; 7; 9; 11; 13; 18; 19 |];;
      - : (int * int) option = Some (7, 18)
      findi_opt ~round_from_random:() (Pred.even) [|1; 30; 5; 7; 9; 11; 13; 18; 19 |];;
      - : (int * int) option = Some (1, 30)
*)
let findi_opt ?(round_from=0) ?round_from_random p s =
  let l = Array.length s in
  let round_from = match round_from_random with None -> round_from | Some () -> random_int l in
  let rec loop k i =
    let i = i mod l in
    if k>=l then None else
    let x = s.(i) in
    if (p x) then (Some (i,x)) else loop (k+1) (i+1)
  in loop 0 (round_from)

let find_opt ?(round_from=0) ?round_from_random p s =
  let l = Array.length s in
  let round_from = match round_from_random with None -> round_from | Some () -> random_int l in
  let rec loop k i =
    let i = i mod l in
    if k>=l then None else
    let x = s.(i) in
    if (p x) then (Some x) else loop (k+1) (i+1)
  in loop 0 (round_from)

(* val findi_map : ?round_from:int -> ?round_from_random:unit -> ('a -> 'b option) -> 'a array -> (int * 'b) option *)
let findi_map ?(round_from=0) ?round_from_random p s =
  let l = Array.length s in
  let round_from = match round_from_random with None -> round_from | Some () -> random_int l in
  let rec loop k i =
    let i = i mod l in
    if k>=l then None else
    let x = s.(i) in
    match p x with
    | Some y -> Some (i,y)
    | None -> loop (k+1) (i+1)
  in loop 0 (round_from)

(* val find_map : ?round_from:int -> ?round_from_random:unit -> ('a -> 'b option) -> 'a array -> 'b option *)
let find_map ?(round_from=0) ?round_from_random p s =
  let l = Array.length s in
  let round_from = match round_from_random with None -> round_from | Some () -> random_int l in
  let rec loop k i =
    let i = i mod l in
    if k>=l then None else
    let x = s.(i) in
    match p x with
    | None -> loop (k+1) (i+1)
    | success -> success
  in loop 0 (round_from)


(* val findi_folding : ?round_from:int -> ?round_from_random:unit -> 's -> 'a array -> ('s -> int -> 'a -> 'b option * 's) -> (int * 'b) option * 's *)
let findi_folding ?(round_from=0) ?round_from_random s xs p =
  let l = Array.length xs in
  let round_from = match round_from_random with None -> round_from | Some () -> random_int l in
  let rec loop acc k i =
    let i = i mod l in
    if k>=l then (None, acc) else
    let x = xs.(i) in
    let y, acc = p acc i x in
    match y with
    | Some y -> (Some (i,y), acc)
    | None   -> loop (acc) (k+1) (i+1)
  in loop s 0 (round_from)

(* val find_folding : ?round_from:int -> ?round_from_random:unit -> 's -> 'a array -> ('s -> 'a -> 'b option * 's) -> 'b option * 's *)
let find_folding ?(round_from=0) ?round_from_random s xs p =
  let l = Array.length xs in
  let round_from = match round_from_random with None -> round_from | Some () -> random_int l in
  let rec loop acc k i =
    let i = i mod l in
    if k>=l then (None, acc) else
    let x = xs.(i) in
    let y, acc = p acc x in
    match y with
    | Some y -> (Some y, acc)
    | None   -> loop (acc) (k+1) (i+1)
  in loop s 0 (round_from)


let find p s =
 let l = Array.length s in
 let rec loop i =
  if i>=l then raise Not_found else
  let x = s.(i) in
  if (p x) then x else loop (i+1)
 in loop 0

let findi p s =
 let l = Array.length s in
 let rec loop i =
  if i>=l then raise Not_found else
  let x = s.(i) in
  if (p x) then (i,x) else loop (i+1)
 in loop 0

let shared_property f s =
 let l = Array.length s in
 if l=0 then true else
 let y = lazy (f s.(0)) in
 let p = (fun x -> (f x)=(Lazy.force y)) in
 let rec loop i =
  if i>=l then true else
  (p s.(i)) && loop (i+1)
 in loop 1

module Dichotomic = struct

(** Supposing the array sorted, this function find the index of the
    leftmost supremum (least upper bound) of the provided value.
    In other words, it computes j = min {i | x <= v.(i) }.
    The result is None if there are no upper bounds for {x} in the array.
    A result as Some (true,j) means that v.(j) = x, while Some (false,j) means x < v.(j).

{b Example}:
{[ dichotomic_leftmost_ge 3 [| 0;2;4;4;4;4;4;6;8;10 |];;
   : (bool * index) option = Some (false, 2)

   dichotomic_leftmost_ge 4 [| 0;2;4;4;4;4;4;6;8;10 |];;
   : (bool * index) option = Some (true, 2)

   dichotomic_leftmost_ge 5 [| 0;2;4;4;4;4;4;6;8;10 |];;
   : bool * index) option = Some (false, 7)

   dichotomic_leftmost_ge 100 [| 0;2;4;4;4;4;4;6;8;10 |];;
   : (bool * index) option = None
]} *)
let dichotomic_leftmost_ge ?(compare=(*Pervasives.*)compare) ?(a=0) ?b x v = (* precedentemente dichotomic_search *)
 let eq x y = (compare x y) = 0 in
 let lt x y = (compare x y) = (-1) in
 let le x y = let r = (compare x y) in r = (-1) || r = 0 in
 let b = match b with None -> (Array.length v)-1 | Some b -> b in
 let (a0, b0) = (a, b) in
 let rec loop a b =
   if a=b then a else (* a < b *)
   let i = (a+b)/2 in (* note that (i+1) <= b  by construction *)
   if (lt v.(i) x) then loop (i+1) b else
   (* At this point, x <= v.(i), i.e. we have found an upper bound *)
   if (i > a0) && (le x v.(i-1)) then loop a (i-1) else
   (* v.(i-1) < x <= v.(i) or (i=a0 and x<=v.(a0)) *)
   i
 in
 if lt x v.(a) then Some (false,a) else (* continue: *)
 if lt v.(b) x then None (* there are no upper bounds *) else (* continue: *)
 let i = loop a b in
 Some ((eq v.(i) x),i)


(** Supposing the array sorted, this function find the index of the
    rightmost infimum (greatest lower bound) of the provided value.
    In other words, it computes:  j = max {i | v.(i) <= x }.
    The result is None if there are no lower bounds for {x} in the array.
    A result as Some (true,j) means that v.(j) = x, while Some (false,j) means v.(j) < x.

{b Example}:
{[ dichotomic_rightmost_le (-100) [| 0;2;4;4;4;4;4;6;8;10 |];;
   : (bool * index) option = None

   dichotomic_rightmost_le 3 [| 0;2;4;4;4;4;4;6;8;10 |];;
   : (bool * index) option = Some (false, 1)

   dichotomic_rightmost_le 5 [| 0;2;4;4;4;4;4;6;8;10 |];;
   : (bool * index) option = Some (false, 6)
]} *)
 let dichotomic_rightmost_le ?(compare=(*Pervasives.*)compare) ?(a=0) ?b x v =
 let eq x y = (compare x y) = 0 in
 let lt x y = (compare x y) = (-1) in
 let le x y = let r = (compare x y) in r = (-1) || r = 0 in
 let b = match b with None -> (Array.length v)-1 | Some b -> b in
 let (a0, b0) = (a, b) in
 let rec loop a b =
   if a=b then a else   (* a < b *)
   let i = (a+b+1)/2 in (* note that (i-1) >= a  by construction *)
   if (lt x v.(i)) then loop a (i-1) else
   (* At this point, v.(i) <= x, i.e. we have found a lower bound *)
   if (i < b0) && (le v.(i+1) x) then loop (i+1) b else
   (* v.(i) <= x < v.(i+1) or (i=b0 and v.(b0)<=x) *)
   i
 in
 if lt x v.(a) then None (* there are no lower bounds *) else (* continue: *)
 if lt v.(b) x then Some (false,b) else (* continue: *)
 let i = loop a b in
 Some ((eq v.(i) x),i)

let dichotomic_frame ?compare ?a ?b x v =
 let inf = dichotomic_rightmost_le ?compare ?a ?b x v in (* v.(inf) <= x *)
 if inf = None then None else (* continue: *)
 let sup = dichotomic_leftmost_ge ?compare ?a ?b x v in (*  x <= v.(sup) *)
 if sup = None then None else (* continue: *)
 match (inf, sup) with
 | (Some (false, i)), (Some (false, j)) -> Some (i,j)
 | (Some (true,  i)), (Some (true,  j)) ->
     Some (j,i) (* because v.(i)=v.(j) and the inf (i) is the rightmost while the sup (j) is the leftmost *)
 | _,_ -> assert false

(* Redefinition with ?unicity *)
(** {b Example}:
{[ # let xs = [| 0; 10; 20; 30; 40; 40; 40; 40; 80; 90; 100; |] (* There are duplicates! *) ;;
   # let ys = [| 0; 10; 20; 30; 40; 50; 60; 70; 80; 90; 100; |] (* Unicity! *) ;;

   # dichotomic_frame 30 xs ;;
   : (int * int) option = Some (3, 3)

   # dichotomic_frame 40 xs ;;
   : (int * int) option = Some (4, 7)

   # dichotomic_frame ~unicity:() 40 ys ;;   (* suppose (and exploit) unicity! *)
   : (int * int) option = Some (4, 4)

   # dichotomic_frame 42 xs ;;
   : (int * int) option = Some (7, 8)

   # dichotomic_frame 101 xs ;;
   : (int * int) option = None

   # dichotomic_frame (-1) ;;
   : (int * int) option = None
]} *)
let dichotomic_frame ?compare ?a ?b ?unicity x v =
 match unicity with
 | None    -> dichotomic_frame ?compare ?a ?b x v
 | Some () ->
     let a = match a with None -> 0 | Some a -> a in
     let sup = dichotomic_leftmost_ge ?compare ~a ?b x v in (* x <= v.(sup) *)
     (match sup with
      | None -> None
      (* In the following two cases we suppose the unicity (no duplicated values in the array) *)
      | Some (false,i) -> if i = a then None else Some (i-1,i)
      | Some (true,i)  -> Some (i,i)
      )

let dichotomic_leftmost_gt ?(compare=(*Pervasives.*)compare) ?(a=0) ?b ?unicity x v =
 if compare v.(a) x = 1 then Some a else
 match dichotomic_frame ~compare ~a ?b ?unicity x v with
 | None -> None
 | Some (i,j) ->
    if (compare v.(i) v.(j) = 0) then
      let b = match b with None -> (Array.length v)-1 | Some b -> b in
      let j' = j+1 in if j' > b then None else Some j'
    else
      Some j

let dichotomic_rightmost_lt ?(compare=(*Pervasives.*)compare) ?a ?b ?unicity x v =
 let b = match b with None -> (Array.length v)-1 | Some b -> b in
 if compare x v.(b) = 1 then Some b else
 match dichotomic_frame ~compare ?a ~b ?unicity x v with
 | None -> None
 | Some (i,j) ->
    if (compare v.(i) v.(j) = 0) then
      let a = match a with None -> 0 | Some a -> a in
      let i' = i-1 in if i' < a then None else Some i'
    else
      Some i

end (* Dichotomic *)
(* Included at toplevel: *)
include Dichotomic

let for_all2 f xs ys = for_all (fun i x -> f i x ys.(i)) xs
let exists2  f xs ys = exists  (fun i x -> f i x ys.(i)) xs

let iter2  f a b = Array.iteri (fun i a -> f a b.(i)) a
let iteri2 f a b = Array.iteri (fun i a -> f i a b.(i)) a

let map2  f a b = Array.mapi (fun i a -> f a b.(i)) a
let mapi2 f a b = Array.mapi (fun i a -> f i a b.(i)) a

(** {b Example}:
{[ map_folding (fun s i x -> (x+s,s+x)) 0 [|0;1;2;3;4;5|] ;;
  : int array = [|0; 1; 3; 6; 10; 15|]
]} *)
let mapi_folding (f : int -> 's -> 'a -> 'b * 's) (s0 : 's) (xs : 'a array) : 'b array =
  let n = Array.length xs in
  if n = 0 then [||] else begin
    let (y0, s1) = f 0 s0 (xs.(0)) in
    let result = Array.make n y0 in
    let state = ref s1 in
    for i = 1 to n-1 do
      let (y,z) = f  i (!state) (xs.(i)) in
      result.(i) <- y ;
      state := z;
    done;
    result
  end

let map_folding (f : 's -> 'a -> 'b * 's) (s0 :'s) (xs : 'a array) : 'b array =
  let n = Array.length xs in
  if n = 0 then [||] else begin
    let (y0, s1) = f s0 (xs.(0)) in
    let result = Array.make n y0 in
    let state = ref s1 in
    for i = 1 to n-1 do
      let (y,z) = f (!state) (xs.(i)) in
      result.(i) <- y ;
      state := z;
    done;
    result
  end

(* Array.iteri : (int -> 'a -> unit) -> 'a array -> unit *)
let iteri_folding (f : int -> 's -> 'a -> 's) (s0 : 's) (xs : 'a array) : unit =
  let n = Array.length xs in
  if n = 0 then () else begin
    let s1 = f 0 s0 (xs.(0)) in
    let state = ref s1 in
    for i = 1 to n-1 do
      let z = f  i (!state) (xs.(i)) in
      state := z;
    done;
  end

(* Array.iter : ('a -> unit) -> 'a array -> unit *)
let iter_folding (f : 's -> 'a -> 's) (s0 : 's) (xs : 'a array) : unit =
  let n = Array.length xs in
  if n = 0 then () else begin
    let s1 = f s0 (xs.(0)) in
    let state = ref s1 in
    for i = 1 to n-1 do
      let z = f (!state) (xs.(i)) in
      state := z;
    done;
  end

(* --- *)

(* val mapi_fold : (int -> 's -> 'a -> 'b) -> (int -> 's -> 'a -> 's) -> 's -> 'a array -> 'b array * 's *)
let mapi_fold fy fs s0 xs =
  let n = Array.length xs in
  if n = 0 then ([||], s0) else begin
    let y0 = fy 0 s0 (xs.(0)) in
    let s1 = fs 0 s0 (xs.(0)) in
    let result = Array.make n y0 in
    let state = ref s1 in
    for i = 1 to n-1 do
      let s  = !state in
      let x  = xs.(i) in
      result.(i) <- fy i s x;
      state      := fs i s x;
    done;
    (result, !state)
  end

(* val map_fold : ('s -> 'a -> 'b) -> ('s -> 'a -> 's) -> 's -> 'a array -> 'b array * 's *)
let map_fold fy fs s0 xs =
  let n = Array.length xs in
  if n = 0 then ([||], s0) else begin
    let y0 = fy s0 (xs.(0)) in
    let s1 = fs s0 (xs.(0)) in
    let result = Array.make n y0 in
    let state = ref s1 in
    for i = 1 to n-1 do
      let s  = !state in
      let x  = xs.(i) in
      result.(i) <- fy s x;
      state      := fs s x;
    done;
    (result, !state)
  end

let fold_lefti f y0 s =
 let l = Array.length s in
 let rec loop acc i =
  if i>=l then acc else
  let acc = f i acc s.(i) in
  loop acc (i+1)
 in loop y0 0

let fold_righti f s y0 =
 let l = Array.length s in
 let rec loop acc i =
  if i<0 then acc else
  let acc = f i s.(i) acc in
  loop acc (i-1)
 in loop y0 (l-1)

let fold_left2  f s0 xs ys = fold_lefti  (fun i s x -> f s x ys.(i)) s0 xs
let fold_right2 f xs ys s0 = fold_righti (fun i x s -> f x ys.(i) s) xs s0

let fold_lefti2  f s0 xs ys = fold_lefti  (fun i s x -> f i s x ys.(i)) s0 xs
let fold_righti2 f xs ys s0 = fold_righti (fun i x s -> f i x ys.(i) s) xs s0

let fold_binop f s =
 let l = Array.length s in
 if l = 0 then invalid_arg "ArrayExtra.fold_binop: I cannot fold an empty array" else
 let rec loop acc i =
  if i>=l then acc else
  let acc = f acc s.(i) in
  loop acc (i+1)
 in loop s.(0) 1

(** Similar to [List.partition] but for arrays and with many classes.
{b Example}:
{[
# partition (fun x -> x mod 3) [|0;1;2;3;4;5;6;7;8;9|] ;;
  : int array array = [|[|0; 3; 6; 9|]; [|1; 4; 7|]; [|2; 5; 8|]|]
]} *)
let partition =
  let errmsg = "ArrayExtra.partition: classifier must provide only non-negative integers" in
  fun ?(min_size=0) f a ->
  (* f' is a dynamically type checked version of f: *)
  let f' x = (let y = f x in (if (y<0) then invalid_arg errmsg); y) in
  let max_index = Array.fold_left (fun s x -> max s (f' x)) (-1) a in
  if max_index = -1 then Array.make min_size [||] else
  let ls = Array.make (max min_size (max_index+1)) [] in
  (Array.iter (fun x -> let c = f x in ls.(c) <- x :: ls.(c)) a);
  let result = Array.map (fun l -> Array.of_list (List.rev l)) ls in
  result

let partitioni =
  let errmsg = "ArrayExtra.partitioni: classifier must provide only non-negative integers" in
  fun ?(min_size=0) f a ->
  (* f' is a dynamically type checked version of f: *)
  let f' i x = (let y = f i x in (if (y<0) then invalid_arg errmsg); y) in
  let max_index = fold_lefti (fun i s x -> max s (f' i x)) (-1) a in
  if max_index = -1 then Array.make min_size [||] else
  let ls = Array.make (max min_size (max_index+1)) [] in
  (Array.iteri (fun i x -> let c = f i x in ls.(c) <- x :: ls.(c)) a);
  let result = Array.map (fun l -> Array.of_list (List.rev l)) ls in
  result

(** {b Example}:
{[
# amass ~size:3 [|1;2;3;4;5;6;7;8;9;10|] ;;
  : int array array = [|[|1; 2; 3|]; [|4; 5; 6|]; [|7; 8; 9|]; [|10|]|]
]} *)
let amass ?group_no ?size xs =
  let size =
    match size, group_no with
    | (Some s), _ -> s
    | None, (Some g) ->
        let n = Array.length xs in
        let k = n/g in
        if n mod g > 0 then k+1 else k (* I want exactly g groups *)
    | None, None -> invalid_arg "ArrayExtra.amass: at leat one of the parameters ~size or ~group_no must be provided"
  in
  if size <= 0 then invalid_arg "ArrayExtra.amass: size must be greater than zero" else
  partitioni (fun i x -> i/size) xs

(** {b Example}:
{[
# flatten [|[|1; 2; 3|]; [|4; 5; 6|]; [|7; 8; 9|]; [|10|]|] ;;
  : int array = [|1; 2; 3; 4; 5; 6; 7; 8; 9; 10|]
]} *)
let flatten xss =
  Array.concat (Array.to_list xss)

(** {b Example}:
{[
# cut [1;2;3;0;2] [|0;1;2;3;4;5;6;7;8;9|];;
  : int array list = [[|0|]; [|1; 2|]; [|3; 4; 5|]; [||]; [|6; 7|]]
]} *)
let cut ~lengths xs =
  let start_len_list_of_lengths xs =
    let js,_ = List.fold_left (fun (js,n) x -> ((n+x)::js,n+x)) ([0],0) xs in
    List.combine (List.rev (List.tl js)) xs
  in
  let start_len_list = start_len_list_of_lengths lengths in
  try
    List.map (fun (start, len) -> Array.sub xs start len) start_len_list
  with Invalid_argument s -> invalid_arg (Printf.sprintf "ArrayExtra.cut (%s)" s)

(** As standard [Array.sub] but with optional length (if not provided, the length is defined
    in order to take the rest of the list after the given position) *)
let sub ?len xs pos =
 let len = match len with
 | None -> (Array.length xs) - pos
 | Some n -> n
 in
 Array.sub xs pos len

let rev xs =
  let n = Array.length xs in
  Array.init n (fun i -> xs.(n-1-i))

(** Tools for matrices (arrays of arrays). *)
module Matrix = struct

 type 'a t = 'a array array

 (** [init m n f] returns a fresh [m] x [n] matrix with element [(i,j)] initialized to the result of [(f i j)].  *)
 let init m n f =
  Array.init m (fun i -> Array.init n (f i))

 (** Make a matrix from a list of lists. *)
 let of_list ll =
  if ll = [] then [||] else
  let rows = List.length ll in
  Array.init rows (fun row -> Array.of_list (List.nth ll row))

 (** Make a list of lists from a matrix. *)
 let to_list aa =
  let al = Array.map Array.to_list aa in
  Array.to_list al

 (** Transpose the matrix. *)
 let transpose aa =
  let m = Array.length aa     in
  let n = Array.length aa.(0) in
  if (for_all (fun i a -> (Array.length a) = n) aa)
  then init n m (fun i j -> aa.(j).(i))
  else invalid_arg "transpose: the argument is not a matrix."

end

(** By default the best is the minimal element, i.e. the choice function is set by default to [min]. *)
let best ?(choice=min) = function
 | [||] -> invalid_arg "ArrayExtra.best: empty array"
 | xs   -> fold_lefti (fun i (j,x) y -> if (choice x y) <> x then (i,y) else (j,x)) (0, xs.(0)) xs

let max ?(gt=(>)) xs =
 fold_lefti (fun i (j,x) y -> if gt y x then (i,y) else (j,x)) (0, xs.(0)) xs

let min ?(gt=(>)) xs =
 fold_lefti (fun i (j,x) y -> if gt y x then (j,x) else (i,y)) (0, xs.(0)) xs

(** Example (from the module [Ipv6]):
{[let search_longest_sequence_of_zeros ?leftmost =
  ArrayExtra.search_longest_sequence ?leftmost ((=)0);; ]}*)
let search_longest_sequence ?leftmost p x =
  let (last,_, acc) =
    fold_lefti
       (fun i ((n,j), inseq, acc) v ->
           if p v then
             (* if we are in a sequence, increment the counter: *)
             (if inseq then ((n+1,j), true, acc)
                       (* else reset the counter registering the current result in the list: *)
                       else ((1,i), true, ((n,j)::acc)))
           else
             (* register that the sequence is finished inseq=false: *)
             ((n,j), false, acc))
       ((0,0), false, []) x
  in
  let njs = last::acc in
  let (best_n, best_j) =
    let candidates = match leftmost with
    | None -> njs
    | Some () -> List.rev njs
    in
    List.fold_left
      (fun ((best_n, best_j) as a) ((n,j) as b) -> if n>best_n then b else a)
      (List.hd candidates)
      (List.tl candidates)
  in
  if best_n > 0 then Some (best_j, best_n) else None
;;

let random_permutation xs =
  let n = Array.length xs in
  let js = Array.init n (fun i -> i) in
  let () =
    Array.iteri
      (fun i x ->
        let choice = i + (random_int (n-i)) in
        js.(i)<-js.(choice); js.(choice)<-x)
      js
  in
  Array.map (fun j -> xs.(j)) js

let frequence pred xs =
 let n = Array.length xs in
 if n=0 then invalid_arg "ArrayExtra.frequence: empty array" else (* continue: *)
 let occ = Array.fold_left (fun occ x -> if (pred x) then occ+1 else occ) 0 xs in
 let freq = (float_of_int occ) /. (float_of_int n) in
 (occ, freq)

let count pred xs =
 let n = Array.length xs in
 if n=0 then invalid_arg "ArrayExtra.count: empty array" else (* continue: *)
 Array.fold_left (fun occ x -> if (pred x) then occ+1 else occ) 0 xs

let values_such_that (p : int -> 'a -> bool) xs =
  let ys = fold_lefti (fun i ys x -> if p i x then x::ys else ys) [] xs in
  List.rev ys

let indexes_such_that (p : int -> 'a -> bool) xs =
  let ys = fold_lefti (fun i ys x -> if p i x then i::ys else ys) [] xs in
  List.rev ys

let indexes_and_values_such_that (p : int -> 'a -> bool) xs =
  let ys = fold_lefti (fun i ys x -> if p i x then (i,x)::ys else ys) [] xs in
  List.rev ys

(**
{[# let gs, gvs = group_by (fun x -> (x mod 3), (x, x*x)) [| 0;1;2;3;4;5;6;7;8;9 |] ;;
val gs : int array = [|0; 1; 2|]                                                                                                                                                               val gvs : (int, (int * int) array) M.t = <abstr>

# Hashtbl.find gvs 0 ;;
  : int array = [|(0, 0); (3, 9); (6, 36); (9, 81)|]

# Hashtbl.find gvs 1 ;;
  : int array = [|(1, 1); (4, 16); (7, 49)|]

# Hashtbl.find gvs 2 ;;
  : (int * int) array = [|(2, 4); (5, 25); (8, 64)|]
]}
*)
let group_by f xs =
  let n = Array.length xs in
  let ht = Hashtbl.create n in
  (* domain with the first position where we have found this element in the array *)
  let domain = Hashtbl.create n in
  let domain_add b i = if Hashtbl.mem domain b then () else Hashtbl.replace domain b i in
  (* --- *)
  let () = Array.iteri (fun i a -> let (b,c) = f a in (Hashtbl.add ht b c; domain_add b i)) xs in
  let domain = Array.of_list (Hashtbl.fold (fun x i ixs -> (i,x)::ixs) domain []) in
  let () = Array.sort compare domain in
  let domain = Array.map snd domain in
  (* --- *)
  let result = Hashtbl.create n in
  (* For all items in the domain, we get the list of associated value in ht: *)
  let () = Array.iter (fun b -> Hashtbl.replace result b (Array.of_list (List.rev (Hashtbl.find_all ht b)))) domain in
  domain, result


(* --- Printing --- *)

(** {b Examples}:
{[# sprintf "%.2f" [|1.;2.;3.;4.|] ;;
  : string = "[|1.00; 2.00; 3.00; 4.00|]"

# sprintf ~frame:"The vector is (%s)" ~sep:", " "%.2f" [|1.;2.;3.;4.|] ;;
  : string = "The vector is (1.00, 2.00, 3.00, 4.00)"
]} *)
let sprintf ?frame ?(sep="; ") fmt xs =
  let content = String.concat sep (List.map (Printf.sprintf fmt) (Array.to_list xs)) in
  match frame with
  | None     -> Printf.sprintf "[|%s|]" content
  | Some fmt -> Printf.sprintf fmt content

let printf ?frame ?sep fmt xs =
  Printf.printf "%s" (sprintf ?frame ?sep fmt xs)

let eprintf ?frame ?sep fmt xs =
  Printf.eprintf "%s" (sprintf ?frame ?sep fmt xs)

let to_string ?frame ?sep f xs =
  let ys = Array.map f xs in
  sprintf ?frame ?sep "%s" ys
