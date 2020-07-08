(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2018 2020  Jean-Vincent Loddo
   Copyright (C) 2018 2020  Université Sorbonne Paris Nord

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

(** The abstract type of an hashset.
    The mutable identifier (id) and the integer associated to each key are introduced
    only to render the function `to_list' stable (see the comment below): *)
type 'a t = { table : ('a, int) Table.t; mutable id : int }

(** The hashset constructor. *)
let make ?weak ?identifier ?equality (*?init*) ?size () : 'a t =
  { table=(Table.make ?weak ?identifier ?equality ?size ()); id=0; }

let to_hashtbl hs = hs.table#to_hashtbl

(** The member predicate. *)
let mem (hs:'a t) (x:'a) = hs.table#mem x

(** Add a member to the hashset. *)
let add (hs:'a t) (x:'a) =
  if (hs.table#mem x) then () else
  let card = hs.id in
  let () = hs.table#add x card in
  let () = hs.id <- card + 1 in
  ()

(** Variant: add a member to the hashset, if necessary, and get its integer
    identifier in the table (useful for weak tables based on the physical equality): *)
let add' (hs:'a t) (x:'a) : int =
  match (hs.table#find_opt x) with
  | Some id -> id
  | None ->
      let card = hs.id in
      let () = hs.table#add x card in
      let () = hs.id <- card + 1 in
      card

let make_physical_compare ?size () =
  let wt = make ~weak:() ~equality:(==) ?size () in
  fun x y -> if x==y then 0 else (* continue: *)
    let x' : int = add' wt x in
    let y' : int = add' wt y in
    compare x' y'

(** Remove a member from the hashset. *)
let remove (hs:'a t) (x:'a) = hs.table#remove x

(** Make an hashset from a list. *)
let of_list ?weak ?identifier ?equality ?size (l:'a list) : 'a t =
  let n = List.length l in
  let size = match size with Some s -> s | None -> int_of_float ((float_of_int n) /. 0.70) in
  let hs = make ?weak ?identifier ?equality ~size () in
  let () = (List.iter (add hs) l) in
  hs

(** Make an hashset from an array. *)
let of_array ?weak ?identifier ?equality ?size (xs:'a array) : 'a t =
  let n = Array.length xs in
  let size = match size with Some s -> s | None -> int_of_float ((float_of_int n) /. 0.70) in
  let hs = make ?weak ?identifier ?equality ~size () in
  let () = (Array.iter (add hs) xs) in
  hs

let to_list_unstable (hs:'a t) =
  hs.table#fold (fun x j xs -> x::xs) []

(* To render this function stable, we have to sort the extracted elements
    using the associated identifier, which is incremented each time an
    element is added. In this way, we are able to return the list of elements
    in the order of insertions. *)
let to_list_stable (hs:'a t) =
  let jxs = hs.table#fold (fun x j jxs -> (j,x)::jxs) [] in
  let jxs = List.fast_sort (compare) jxs in
  List.map snd jxs

(* Use ~unstable:() to speed up the answer, when the stability is not relevant. *)
let to_list ?unstable =
  match unstable with
  | None    -> to_list_stable
  | Some () -> to_list_unstable

let to_array ?unstable (hs:'a t) =
  Array.of_list (to_list ?unstable hs)

(** Exploit an hashset (and stability) for implementing the uniq function over lists. Stable. *)
let uniq (xs:'a list) : ('a list) =
  let hs = of_list xs in
  List.filter (fun x -> if mem hs x then (remove hs x; true) else false) xs

let list_uniq = uniq

let array_uniq (xs:'a array) : ('a array) =
  let hs = of_array xs in
  Array.of_list (List.filter (fun x -> if mem hs x then (remove hs x; true) else false) (Array.to_list xs))
