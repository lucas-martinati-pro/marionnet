(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2012  Jean-Vincent Loddo

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

(** Multi-maps, i.e. maps x->y where x may be associated to zero or several y. They are simply implemented as maps of sets, with the condition that a multimap with a value x associated to the empty set, is equivalent to a multimap where x is unbound. *)

#load "include_type_definitions_p4.cmo";;
INCLUDE DEFINITIONS "../../../../lib/STRUCTURES/multimap.mli"
;;

IFDEF OCAML4_07_OR_LATER THEN
module Pervasives = Stdlib
ENDIF

module Make (Ord_key : Map.OrderedType) (Ord_elt : Map.OrderedType) = struct

  type key = Ord_key.t
  type elt = Ord_elt.t
  type elt_set = SetExtra.Make(Ord_elt).t

  module Set = SetExtra.Make (Ord_elt)
  module Map = MapExtra.Make (Ord_key)

  type t = elt_set Map.t
  let empty = Map.empty

  let find x t =
    try Map.find x t with Not_found -> Set.empty

  let find_list ?sort x t =
    try Set.to_list ~reverse:(sort<>None) (Map.find x t) with Not_found -> []

  let is_empty = Map.is_empty

  let add x y t =
    let s = find x t in
    let s' = Set.add y s in
    Map.add x s' t

  let remove_key = Map.remove

  let remove x y t =
    let s = find x t in
    let s' = Set.remove y s in
    if Set.is_empty s' then Map.remove x t else Map.add x s' t

  (** If the key is bound to the empty set is not really bound to something. *)
  let mem_key x t =
    try not (Set.is_empty (Map.find x t)) with Not_found -> false

  let mem x y t =
    try Set.mem y (Map.find x t) with Not_found -> false

  let fold_key = Map.fold
  let fold f =
    Map.fold (fun x s v -> Set.fold (f x) s v)

  let iter_key = Map.iter
  let iter f =
    Map.iter (fun x s -> Set.iter (f x) s)

  let remove_keys_bound_to_empty_set =
    Map.filter (fun x s -> not (Set.is_empty s))

  let filter_key = Map.filter
  let filter f t =
    let t' = Map.mapi (fun x s -> Set.filter (f x) s) t in
    remove_keys_bound_to_empty_set t'

  let compare = Map.compare (Set.compare)
  let equal = Map.equal (Set.equal)

  let of_list ?(acc=Map.empty) xys =
    List.fold_left (fun t (x,y) -> add x y t) acc xys

  let to_list ?(acc=[]) ?sort t =
    let l = fold (fun x y t -> (x,y)::t) t acc in
    if (sort<>None) then List.rev l else l

  let domain ?sort = Map.domain ~reverse:(sort<>None)

  let codomain ?sorted_by_key t =
    let l = fold (fun x y ys -> y::ys) t [] in
    if (sorted_by_key<>None) then List.rev l else l

  let restrict = Map.restrict

  let inter t1 t2 = filter (fun x y -> mem x y t2) t1
  let diff  t1 t2 = filter (fun x y -> not (mem x y t2)) t1
  let union t1 t2 = fold add t2 t1

end


IFDEF DOCUMENTATION_OR_DEBUGGING THEN
module Examples = struct

(* In order to haven't abstract types for key, elt and elt_set,
   the right way to apply the functor is the following: *)

module Ord_key = struct type t = string let compare = Pervasives.compare end
module Ord_elt = struct type t = int let compare = Pervasives.compare end
module String2int : S with
      type key = Ord_key.t and
      type elt = Ord_elt.t and
      type elt_set = SetExtra.Make(Ord_elt).t
      =  Make(Ord_key)(Ord_elt)

module M = String2int

let t  = M.of_list [("x",2); ("x",1); ("y",3) ]
let t' = M.of_list [("x",7); ("x",1); ("y",3); ("z",4) ]

let diff  = M.diff t t'
let inter = M.inter t t'
let union = M.union t t'

let list_of_t  = M.to_list ~sort:() t
let list_of_t' = M.to_list ~sort:() t'
let list_of_diff = M.to_list ~sort:() diff
let list_of_inter = M.to_list ~sort:() inter
let list_of_union = M.to_list ~sort:() union

end (* module Examples *)
ENDIF


