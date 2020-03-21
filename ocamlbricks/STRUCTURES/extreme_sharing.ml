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

type 'b identity = ('b -> 'b)

(* let identity x = x *)

let ht_default_size = 251

let memoize_identity_and_get_ht () =
  let ht = Hashtbl.create (ht_default_size) in
  let f =
    fun x ->
      try
        Hashtbl.find ht x
      with Not_found ->
        begin
          let () = Hashtbl.add ht x x in
          x
        end
  in
  (f, ht)

let memoize_identity () = fst (memoize_identity_and_get_ht ())

(* val id : unit -> 'b identity *)
let id = memoize_identity
let id_ht = memoize_identity_and_get_ht

(* val adhere : ?id:('b -> 'b) -> ('a -> 'b) -> ('a -> 'b) *)
let adhere ?id =
  let id = match id with None -> memoize_identity () | Some id -> id in
  fun f x -> id (f x)

(* Really extreme!  *)
module Sublists = struct

  (* val id : ?elt:'b identity -> unit -> ('b list) identity *)
  let id ?elt () =
    let id_list = memoize_identity () in
    match elt with
    | None ->
        let rec loop = function
        | [] -> []
        | x::xs -> id_list (x::(loop xs))
        in
        loop
    (* --- *)
    | Some id_elt ->
        let rec loop = function
        | [] -> []
        | x::xs -> id_list ((id_elt x)::(loop xs))
        in
        loop

end (* Sublists *)

(* val through_lists : ?elt:'b identity -> unit -> ('b array) identity *)
let through_lists ?elt () =
  let id_elt = match elt with None -> memoize_identity () | Some id -> id in
  List.map (id_elt)

(* Redefinition with a more general interface:
   val through_lists : ?sublists:unit -> ?elt:'b identity -> unit -> ('b list) identity *)
let through_lists ?sublists =
  match sublists with
  | Some () -> Sublists.id
  | None    -> through_lists (* simple version (just a mapping) *)

(* val through_arrays : ?elt:'b identity -> unit -> ('b array) identity *)
let through_arrays ?elt () =
  let id_elt = match elt with None -> memoize_identity () | Some id -> id in
  Array.map (id_elt)

(* Easy interface for arrays (i.e. when the codomain is an array): *)
module Array = struct
  (* Just `through_arrays' composed with `adhere': *)
  (* val adhere : ?elt:'b identity -> ('a -> 'b array) -> ('a -> 'b array) *)
  let adhere ?elt = adhere ~id:(through_arrays ?elt ())

  let id = through_arrays
end

(* Easy interface for lists (i.e. when the codomain is a list): *)
module List = struct
  (* Just `through_lists' composed with `adhere': *)
  (* val adhere : ?sublists:unit -> ?elt:'b identity -> ('a -> 'b list) -> ('a -> 'b list) *)
  let adhere ?sublists ?elt = adhere ~id:(through_lists ?sublists ?elt ())

  let id = through_lists
end

(* General functorized interface: *)
module Through (M:sig  type 'a t  val map : ('a -> 'b) -> ('a t -> 'b t)  end) = struct

 type 'a t = 'a M.t

 let through ?elt () =
   let id_elt = match elt with None -> memoize_identity () | Some id -> id in
   M.map (id_elt)

  let adhere ?elt = adhere ~id:(through ?elt ())
  let id = through

end

