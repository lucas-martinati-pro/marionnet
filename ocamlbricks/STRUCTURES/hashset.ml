(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2018  Jean-Vincent Loddo

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

let default_size = 51

(** The abstract type of an hashset.
    The mutable identifier (id) and the integer associated to each key are introduced
    only to render the function `to_list' stable (see the comment below): *)
type 'a t = { table : ('a, int) Hashtbl.t; mutable id : int }

(** The hashset constructor. *)
let make ?(size=default_size) () : 'a t = { table=(Hashtbl.create size); id=0; }

let extract_ht t = t.table

(** Return a copy of the provided set (for a persistent usage): *)
let copy t = { table=(Hashtbl.copy t.table); id=t.id; }

(** The member predicate. *)
let mem (hs:'a t) (x:'a) = Hashtbl.mem hs.table x

(** Add a member to the hashset. *)
let add (hs:'a t) (x:'a) =
  if (Hashtbl.mem hs.table x) then () else
  let card = hs.id in
  let () = Hashtbl.add hs.table x card in
  let () = hs.id <- card + 1 in
  ()

(** Remove a member from the hashset. *)
let remove (hs:'a t) (x:'a) = Hashtbl.remove hs.table x

(** Make an hashset from a list. *)
let of_list (l:'a list) : 'a t =
  let n = List.length l in
  let size = int_of_float ((float_of_int n) /. 0.70) in
  let hs = make ~size () in
  let () = (List.iter (add hs) l) in
  hs

(** Make an hashset from an array. *)
let of_array (xs:'a array) : 'a t =
  let n = Array.length xs in
  let size = int_of_float ((float_of_int n) /. 0.70) in
  let hs = make ~size () in
  let () = (Array.iter (add hs) xs) in
  hs

(* To render this function stable, we have to sort the extracted elements
    using the associated identifier, which is incremented each time an
    element is added. In this way, we are able to return the list of elements
    in the order of insertions. *)
let to_list (hs:'a t) =
  let jxs = Hashtbl.fold (fun x j jxs -> (j,x)::jxs) hs.table [] in
  let jxs = List.fast_sort (compare) jxs in
  List.map snd jxs

let to_array (hs:'a t) =
  Array.of_list (to_list hs)

(** Exploit an hashset for implementing the uniq function over lists. Stable. *)
let uniq (xs:'a list) : ('a list) =
  let hs = of_list xs in
  List.filter (fun x -> if mem hs x then (remove hs x; true) else false) xs

let list_uniq = uniq

let array_uniq (xs:'a array) : ('a array) =
  let hs = of_array xs in
  Array.of_list (List.filter (fun x -> if mem hs x then (remove hs x; true) else false) (Array.to_list xs))
