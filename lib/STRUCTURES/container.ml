(* This file is part of ocamlbricks
   Copyright (C) 2013  Jean-Vincent Loddo

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

#load "include_type_definitions_p4.cmo";;
INCLUDE DEFINITIONS "../../../../lib/STRUCTURES/container.mli"
;;

(* Fresh is morally an optional argument of the functor: *)
module Add_identifiers
  (Fresh : sig val fresh : (unit -> int) option end)
  (Container: T)
  : T_with_identifiers
  =
  struct

  type id = int
  type 'a t = (id * 'a) Container.t

  (* The inner generator of fresh identifiers: *)
  let fresh =
    match Fresh.fresh with
    | None ->
       let c = Counter.create () in
       Counter.fresh c
    | Some f -> f

  (* Common identical functions: *)
  let create   = Container.create
  let clear    = Container.clear
  let copy     = Container.copy
  let is_empty = Container.is_empty
  let rev      = Container.rev
  let rev_copy = Container.rev_copy
  let length   = Container.length
  let is_empty = Container.is_empty
  let length   = Container.length
  let rev      = Container.rev
  let rev_copy = Container.rev_copy

  (* Functions with the same name but abstracting from identifiers: *)
  let pop t = snd (Container.pop t)
  let top t = snd (Container.top t)
  let iter   f = Container.iter (fun (_,x) -> f x)
  let filter f = Container.filter (fun (_,x) -> f x)
  let map    f = Container.map (fun (id,x) -> (id,f x))
  let fold   f = Container.fold (fun b (id,x) -> f b x)
  let to_list t  = List.map snd (Container.to_list t)
  let of_list xs = Container.of_list (List.map (fun x -> (fresh ()),x) xs)

  (* Identical functions but changing name ("i" suffix): *)
  let pushi   = Container.push
  let copushi = Container.copush
  let popi    = Container.pop
  let topi    = Container.top
  let iteri   = Container.iter
  let filteri = Container.filter
  let mapi    = Container.map
  let foldi   = Container.fold
  let to_assoc_list = Container.to_list
  let of_assoc_list = Container.of_list

  (* Push and co: *)

  let push x t =
    let id = fresh () in
    let () = Container.push (id,x) t in
    id

  let copush t x =
    let id = fresh () in
    let () = Container.copush t (id,x) in
    id

  (* Now the two functions that represent the real purpose of having identifiers: *)

  exception Found

  let get_by_id id t =
    let result = ref None in
    try
      Container.iter (fun (j,x) -> if j = id then (result := Some x; raise Found)) t;
      raise Not_found
    with Found -> Option.extract (!result)

  let remove_by_id id =
    Container.filter (fun (j,_) -> j<>id)

  module Fresh = struct let fresh = Some fresh end
end


module Stack_with_identifiers =
  Add_identifiers
    (struct let fresh=None end)
    (StackExtra)

module Queue_with_identifiers =
  Add_identifiers
    (struct let fresh=None end)
    (struct include Queue  include QueueExtra end)

