(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2019  Jean-Vincent Loddo

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


(** Efficient operations on multisets of natural numbers (indexes) based on bitmasks.
    The equality test between two multisets is specially efficient. *)


(* Stratified bitmasks. The length of the array corresponds to the maximal multiplicity in the multiset. *)
type t = Bitmasks.t array
 and multiplicity = int
 and dim          = int (* maximal cardinality of the support set *)
 and index        = int


let dim t = Bitmasks.dim t.(0)
let support t = t.(0)

(* val empty : ?dim:int -> unit -> t *)
(* The maximum set cardinality (not multiplicity) must be specified at creation time. *)
let empty ?dim (* by default Bitmmask.b *) () =
  [| Bitmasks.empty ?dim () |]

(* val singleton : ?dim:int -> index -> t *)
let singleton ?dim (* by default Bitmmask.b *) index =
  [| Bitmasks.singleton ?dim index |]

(* val mem : index -> t -> bool *)
let mem (i:index) (t:t) : bool =
  Bitmasks.mem i t.(0)

(* val mul : index -> t -> multiplicity. Dichotomic. *)
let mul (i:index) (t:t) : int =
  let n = Array.length t in
  if not (Bitmasks.mem i t.(0)) then 0 else (* continue: *)
  (* --- *)
  (* Invariant: (Bitmasks.mem i t.(a)) *)
  let rec loop a b =
    if (a >= b) || (Bitmasks.mem i t.(b)) then (b+1) else (* continue: *)
    let k = (a + b) / 2 in
    if Bitmasks.mem i t.(k) then loop k (b-1) else loop a (k-1)
  in loop 0 (n-1)

(* val add : index -> t -> t *)
let add (i:index) (t:t) : t =
  let n = Array.length t in
  let m = mul i t in
  if (m = n) then
    let dim = Bitmasks.dim t.(0) in
    Array.concat [t; (singleton ~dim i) ]
  else (* m < n *)
  (* --- *)
  let r = Array.copy t in (* small array of small arrays *)
  let depth = m (* -1 +1 *) in
  let bm = Bitmasks.add i r.(depth) in
  let () = (r.(depth) <- bm) in
  r

(* val remove : index -> t -> t *)
let remove (i:index) (t:t) : t =
  if not (Bitmasks.mem i t.(0)) then t else (* continue: *)
  let n = Array.length t in
  let m = mul i t in (* m>=1 *)
  if (m < n) then
    let r = Array.copy t in (* small array of small arrays *)
    let depth = (m-1) in
    let b = Bitmasks.remove i r.(depth) in
    let () = r.(depth) <- b in
    r
  else (* m = n >= 1 *)
    let depth = (n-1) in
    let b = Bitmasks.remove i t.(depth) in
    if (n>1) && (Bitmasks.is_empty b) then
      Array.sub t 0 (n-1)
    else
      let r = Array.copy t in (* small array of small arrays *)
      let () = r.(depth) <- b in
      r

(* val of_list : ?dim:int -> index list -> t *)
let of_list ?dim (js : index list) : t =
  let t0 = empty ?dim () in
  List.fold_left (fun t i -> add i t) t0 js

(* From ArrayExtra: *)
let sort_saving_positions (xs:'a array) : (int * 'a) array =
  let ys = Array.mapi (fun i x -> (x,i)) xs in
  let () = Array.sort (fun (x,_) (y,_) -> compare x y) ys in
  Array.map (fun (p,i) -> (i,p)) ys

(* The multiset is defined by the multiplicity associated to each index of the array:
   val of_multiplicities : ?dim:int (* Array.length *) -> multiplicity array -> t *)
let of_multiplicities ?dim (ms : multiplicity array) : t =
  let dim = match dim with Some c -> c | None -> Array.length ms in
  (* We sort with increasing multiplicity for efficiency: *)
  let ims = sort_saving_positions ms in (* Ex: [| 3; 7; 5 |] => [|(0, 3); (2, 5); (1, 7)|] *)
  let () =
    let (i0, m0) = ims.(0) in
    if m0 < 0 then invalid_arg (Printf.sprintf "Bitmmask.of_multiplicities: negative multiplicity (%d) for index %d" m0 i0) else ()
  in
  (* --- *)
  let replicas = Array.concat (Array.to_list (Array.map (fun (i,m) -> Array.make m i) ims)) in (* Ex: [|0; 0; 0; 2; 2; 2; 2; 2; 1; 1; 1; 1; 1; 1; 1|] *)
  of_list ~dim (Array.to_list replicas)

(* val to_list : t -> index list *)
let to_list t =
 List.concat (Array.to_list (Array.map (Bitmasks.to_list) t))

let is_empty t = Bitmasks.is_empty t.(0)

(* From ArrayExtra: similar to the standard [List.for_all], implemented directly, i.e. without conversion. *)
let array_for_alli p s =
 let l = Array.length s in
 let rec loop i =
  if i>=l then true else
  (p i s.(i)) && loop (i+1)
 in loop 0

let subset t1 t2 = Bitmasks.subset t1.(0) t2.(0)

(* val may_be_subset : t -> t -> bool. *)
let submset (t1:t) (t2:t) =
  array_for_alli (fun i layer1 -> let layer2 = t2.(i) in Bitmasks.subset layer1 layer2) t1

(* None means "incomparable", (Some 0) means "equals", (Some (-1)) means "submset", (Some 1) means "supermset" *)
(* val compare : t -> t -> int option *)
let compare t1 t2 =
 if t1 = t2 then Some 0 else (* continue: *)
 if submset t1 t2 then Some (-1) else (* continue: *)
 if submset t2 t1 then Some  (1) else (* continue: *)
 None

