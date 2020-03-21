(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2010 Jean-Vincent Loddo

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

module Id_map = MapExtra.Int_map

type id = int
type revision = int
type 'a t = ('a,id) Hashtbl.t * ('a Id_map.t ref) * (unit->id) * (revision ref)

let create ?(size=251) () : 'a t =
 let revision = ref 0 in
 let id_counter  = ref 0 in
 let fresh = fun () -> (incr id_counter); !id_counter in
 (Hashtbl.create size, ref Id_map.empty, fresh, revision)

let add (ta,ti,fresh,revision) a =
  try Hashtbl.find ta a
  with Not_found | Invalid_argument _ (*"equal: functional value"*) ->
    let id = fresh () in
    (ti := Id_map.add id a !ti);
    (Hashtbl.add ta a id);
    (incr revision);
    id

let remove (ta,ti,fresh,revision) id =
  try
   let a = Id_map.find id !ti in
   (Hashtbl.remove ta a);
   (ti := Id_map.remove id !ti);
   (incr revision);
   true
  with Not_found -> false

let mem      (ta,ti,fresh,revision) id = Id_map.mem id !ti
let length   (ta,ti,fresh,revision)    = Hashtbl.length ta
let revision (ta,ti,fresh,revision)    = !revision
let iter f   (ta,ti,fresh,revision)    = Id_map.iter f !ti
let fold f   (ta,ti,fresh,revision)    = Id_map.fold f !ti

let to_list  (ta,ti,fresh,revision)    = Id_map.codomain !ti
let to_assoc_list (ta,ti,fresh,revision) = Id_map.to_list !ti

let of_list xs =
 let t = create () in
 let ys = List.map (add t) xs in
 (t,ys)

module Cached = struct

  let to_list t = Cache.optimize ~revision:revision to_list t
  let to_assoc_list t = Cache.optimize ~revision:revision to_assoc_list t

end


(** Heterogenous cloakroom. add is O(n), remove is O(1), find is O(1).
    Obj.magic is needed here, of course. Use [find] with caution. {b Example}:
{[# let t = M.create () ;;
val t : M.t = <abstr>

# M.add t 42 ;;
  : M.id = 1

# M.add t 3.14 ;;
  : M.id = 2

# M.add t [true;false;false] ;;
  : M.id = 3

# M.add t (fun x -> x+1) ;;
  : M.id = 4

# List.hd (M.find t 3) ;;
  : 'a = <poly>

# List.hd ((M.find t 3):bool list) ;;
  : bool = true

# List.tl ((M.find t 3):bool list) ;;
  : bool list = [false; false]
]} *)
module Hetero = struct
 type id = int
 type revision = int
 (* Note that here an hash table for (id,'a) associations is preferable
    (instead of an heap) because we don't worry about folding/itering complexity.
    For the same reason, the field revision is not very interesting.
    The field length is now not necessary because Hashtbl.length is efficient. *)
 type 'a the_type_if_it_was_homogeneous = (('a * id) list ref) * (id,'a) Hashtbl.t * (unit->id)
 type invention = int option
 type t = invention the_type_if_it_was_homogeneous

 let create ?(size=251) () =
  let id_counter  = ref 0 in
  let fresh = fun () -> (incr id_counter); !id_counter in
  (ref [], Hashtbl.create size, fresh)

 let add (ta,ti,fresh) a =
   try List.assq a !ta
   with Not_found ->
     let id = fresh () in
     let () = ((ta := (a,id)::(!ta)); (Hashtbl.add ti id a)) in
     id

 let remove (ta,ti,fresh) id =
   try
    let a = Hashtbl.find ti id in
    (ta := List.remove_assq a !ta);
    (Hashtbl.remove ti id);
    true
   with Not_found -> false

 let find (ta,ti,fresh) id = Hashtbl.find ti id

 (* add is redefined with magic: *)
 let add t a = add (Obj.magic t) (Obj.magic a)
 let find t id = find (Obj.magic t) id

 let mem (ta,ti,fresh) id = Hashtbl.mem ti id
 let length (ta,ti,fresh) = Hashtbl.length ti

end
