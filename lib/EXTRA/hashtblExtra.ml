(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2010  Jean-Vincent Loddo

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

(** Make extra definitions for Hashtbl. *)

type ('a, 'b) t = ('a, 'b) Hashtbl.t

let search t k  = try Some (Hashtbl.find t k) with Not_found -> None

let to_assoc_list t = Hashtbl.fold (fun x y l -> (x,y)::l) t []

IFDEF OCAML4_OR_LATER THEN
let of_assoc_list ?random ?size l = 
  (* At least 51 buckets when size is not provided: *)
  let n = match size with Some n -> n | None -> max (List.length l) 51 in 
  let ht = Hashtbl.create ?random n in
  let () = List.iter (fun (x,y) -> Hashtbl.add ht x y) l in
  ht
ELSE
let of_assoc_list ?random ?size l = 
  (* At least 51 buckets when size is not provided: *)
  let n = match size with Some n -> n | None -> max (List.length l) 51 in 
  let ht = Hashtbl.create (*?random*) n in
  let () = List.iter (fun (x,y) -> Hashtbl.add ht x y) l in
  ht
ENDIF

let remove_all t x =
 let ys = Hashtbl.find_all t x in
 List.iter (fun _ -> Hashtbl.remove t x) ys

IFDEF OCAML4_OR_LATER THEN
let map f t =
  let n = (Hashtbl.stats t).Hashtbl.num_buckets in
  let t' = Hashtbl.create n in
  let () = Hashtbl.iter (fun k v -> Hashtbl.replace t' k (f v)) t in
  t'

let mapk f t =
  let n = (Hashtbl.stats t).Hashtbl.num_buckets in
  let t' = Hashtbl.create n in
  let () = Hashtbl.iter (fun k v -> Hashtbl.replace t' k (f k v)) t in
  t'

let map2 f t1 t2 = 
  mapk (fun k a -> let b = Hashtbl.find t2 k in f a b) t1

let map2k f t1 t2 = 
  mapk (fun k a -> let b = Hashtbl.find t2 k in f k a b) t1
ENDIF

module Make (H : Hashtbl.HashedType) = struct
 include Hashtbl.Make(H)

 let search t k  = try Some (find t k) with Not_found -> None
 let to_assoc_list t = fold (fun x y l -> (x,y)::l) t []
 let of_assoc_list ?size l = 
   (* At least 51 buckets when size is not provided: *)
   let n = match size with Some n -> n | None -> max (List.length l) 51 in 
   let ht = create (n) in
   let () = List.iter (fun (x,y) -> add ht x y) l in
   ht

 let remove_all t x =
  let ys = find_all t x in
  List.iter (fun _ -> remove t x) ys

IFDEF OCAML4_OR_LATER THEN
 let map f t =
  let n = (stats t).Hashtbl.num_buckets in
  let t' = create n in
  let () = iter (fun k v -> replace t' k (f v)) t in
  t'

 let mapk f t =
  let n = (stats t).Hashtbl.num_buckets in
  let t' = create n in
  let () = iter (fun k v -> replace t' k (f k v)) t in
  t'

 let map2 f t1 t2 = 
  mapk (fun k a -> let b = find t2 k in f a b) t1

 let map2k f t1 t2 = 
  mapk (fun k a -> let b = find t2 k in f k a b) t1
ENDIF

end
