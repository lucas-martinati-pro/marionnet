(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2018 2019  Jean-Vincent Loddo

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


(** Efficient operations on sets of natural numbers (indexes) based on bitmasks.
    Elements of sets are indexes (int) from 0 to (n-1) where n is the cardinality.
    The equality test between two sets is specially efficient.
    This module is accessory for Loop.Range. *)

(* The `dpi', i.e. the (d)imension (p)er (i)nteger is the most relevant constant in this module.
   It represent the maximal cardinality encoded by a single integer.
   For a 64 bit architecture the dpi is 62. *)
let dpi = int_of_float ((log (float_of_int max_int)) /. (log 2.))

(* Ex: int_power 2 10 = 1024 *)
let int_power =
  let rec pow a x n =
    if n = 0 then a else pow (a * (if n mod 2 = 0 then 1 else x)) (x * x) (n / 2) in
  pow 1

(* Useful constants: *)
let pow2 = Array.init dpi (int_power 2)
let pow2_not =
  let pow2dpi = int_power 2 (dpi-1) in
  Array.map (fun x -> (pow2dpi - 1 - x) + pow2dpi) pow2

(* Each integer represent the bitmask for dpi elements: *)
type t = mask array
  (* --- *)
  and mask  = int
  and card  = int
  and dim   = int (* maximal cardinality *)
  and index = int (* 0..(dim-1) *)

(* dim = length * dpi *)
let dim t = (Array.length t) * dpi

(* The maximum set cardinality (dimension) must be specified at creation time. *)
let empty ?(dim=dpi) (* by default dpi  *) () =
  let k = (dim-1)/dpi + 1 in
  Array.make k 0

(* Note: when the index falls outside the currently defined cardinality,
         the array of masks could be expanded just enough. However, in
         this version, for efficiency, we do not allow enlargement. *)
let add (i:index) (t:t) : t =
  let p = i/dpi in (* involded part of the array *)
  let j = i mod dpi in (* involved bit in the mask (integer) *)
  (* The copy should be efficient because the array should be small (may be a singleton): *)
  let r = Array.copy t in
  let () = r.(p) <- (r.(p)) lor (pow2.(j)) in
  r

let add_checking_membership (i:index) (t:t) : t * bool =
  let p = i/dpi in (* involded part of the array *)
  let j = i mod dpi in (* involved bit in the mask (integer) *)
  let member = ((t.(p)) land (pow2.(j))) > 0 in
  if member then (t, true) else (* continue: *)
  (* The copy should be efficient because the array should be small (may be a singleton): *)
  let r = Array.copy t in
  let () = r.(p) <- (r.(p)) lor (pow2.(j)) in
  (r, false)

let add_in_place (i:index) (t:t) : unit =
  let p = i/dpi in (* involded part of the array *)
  let j = i mod dpi in (* involved bit in the mask (integer) *)
  (t.(p) <- (t.(p)) lor (pow2.(j)))

let singleton ?dim (i:index) : t =
  let dim = match dim with None -> (i+1) | Some n -> n in
  let t = empty ~dim () in
  let () = add_in_place i t in
  t

let of_list ?dim (js : index list) : t =
  let t = empty ?dim () in
  let () = List.iter (fun j -> add_in_place j t) js in
  t

let remove (i:index) (t:t) : t =
  let p = i/dpi in (* involded part of the array *)
  let j = i mod dpi in (* involved bit in the mask (integer) *)
  let r = Array.copy t in (* very efficient because the array should be small (may be a singleton) *)
  let () = r.(p) <- (r.(p)) land (pow2_not.(j)) in
  r

let remove_in_place (i:index) (t:t) : unit =
  let p = i/dpi in (* involded part of the array *)
  let j = i mod dpi in (* involved bit in the mask (integer) *)
  (t.(p) <- (t.(p)) land (pow2_not.(j)))

let mem (i:index) (t:t) : bool =
  let p = i/dpi in (* involded part of the array *)
  let j = i mod dpi in (* involved bit in the mask (integer) *)
  ((t.(p)) land (pow2.(j))) > 0

let union (t1:t) (t2:t) : t =
  Array.mapi (fun p m1 -> m1 lor t2.(p)) t1

let inter (t1:t) (t2:t) : t =
  Array.mapi (fun p m1 -> m1 land t2.(p)) t1

let mask_to_array m : bool array =
  Array.init dpi (fun j -> (m land (pow2.(j))) > 0)

let mask_to_revlist m : index list =
  let (_,js) = Array.fold_left (fun (j,js) mb -> if mb then (j+1, j::js) else (j+1, js)) (0,[]) (mask_to_array m) in
  js

let mask_to_list m : index list =
  let (_,js) = Array.fold_right (fun mb (j,js) -> if mb then (j-1, j::js) else (j-1, js)) (mask_to_array m) (dpi-1,[]) in
  js

let to_list t =
  let xss = Array.mapi (fun p m -> let h = (dpi*p) in List.map (fun j -> h+j) (mask_to_list m)) t in
  List.concat (Array.to_list xss)

(* From ArrayExtra: similar to the standard [List.for_all], implemented directly, i.e. without conversion. *)
let array_for_all p xs =
 let n = Array.length xs in
 let rec loop i =
  if i>=n then true else
  (p xs.(i)) && loop (i+1)
 in loop 0

let is_empty =
  array_for_all (fun x -> x=0)

(* From ArrayExtra: similar to the standard [List.for_all], implemented directly, i.e. without conversion. *)
let array_for_alli p s =
 let l = Array.length s in
 let rec loop i =
  if i>=l then true else
  (p i s.(i)) && loop (i+1)
 in loop 0

(* val may_be_subset : t -> t -> bool. *)
let subset (t1:t) (t2:t) = array_for_alli (fun i m1 -> let m2 = t2.(i) in (m1 lor m2) = m2) t1

(* None means "incomparable", (Some 0) means "equals", (Some (-1)) means "subset", (Some 1) means "superset" *)
(* val compare : t -> t -> int option *)
let compare t1 t2 =
 if t1 = t2 then Some 0 else (* continue: *)
 if subset t1 t2 then Some (-1) else (* continue: *)
 if subset t2 t1 then Some  (1) else (* continue: *)
 None
