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

(* val weakly_memoize : ?equality:('a -> 'a -> bool) -> ?size:int -> ('a -> 'b) -> 'a -> 'b
   Note the STRUCTURAL equality by default: *)
let weakly_memoize (type keys) ?trace_faults ?(equality=(=)) ?(size=0) f =
  let trace_faults = Option.to_bool trace_faults in
  let module Hashed = struct
      type t = keys
      let hash = Hashtbl.hash
      let equal = (equality)
    end
  in
  let module Weak_table = Ephemeron.K1.Make(Hashed) in
  let ht = Weak_table.create (size) in
  let f' x =
    try
      Weak_table.find ht x
    with Not_found ->
        let y = f x in
        let () = Weak_table.replace ht x y in
        y
  in
  let f'' x =
    try
      Weak_table.find ht x
    with Not_found ->
        let () = Misc.pr "Extreme_sharing: weakly_memoize: FAULT\n" in
        let y = f x in
        let () = Weak_table.replace ht x y in
        y
  in
  if trace_faults then f'' else
  f'

(* val weakly_memoize_with_prj : ?trace_faults:unit -> ?equality:('a -> 'a -> bool) -> ?size:int -> prj:('a -> 'c) -> ('a -> 'b) -> 'a -> 'b *)
let weakly_memoize_with_prj (type keys) (type prj) ?trace_faults ?(equality=(=)) ?(size=0) ~prj f =
  let trace_faults = Option.to_bool trace_faults in
  let module Hashed1 = struct  type t = keys  let hash = Hashtbl.hash  let equal = (equality)  end in
  let module Hashed2 = struct  type t = prj   let hash = Hashtbl.hash  let equal = (==) (* physical equality for projections *)  end in
  (* --- *)
  let module Weak_table1 = Ephemeron.K1.Make(Hashed1) in
  let ht1  = Weak_table1.create (size) in
  (* --- *)
  let module Weak_table2 = Ephemeron.K1.Make(Hashed2) in
  let ht2  = Weak_table2.create (size) in
  (* --- *)
  let f' x =
    try
      Weak_table1.find ht1 x
    with Not_found ->
        let y = f x in
        let () = Weak_table1.replace ht1 x y in
        let () = Weak_table2.replace ht2 (prj x) x in
        y
  in
  let f'' x =
    try
      Weak_table1.find ht1 x
    with Not_found ->
        let () = Misc.pr "Extreme_sharing: weakly_memoize_with_prj: FAULT\n" in
        let y = f x in
        let () = Weak_table1.replace ht1 x y in
        let () = Weak_table2.replace ht2 (prj x) x in
        y
  in
  if trace_faults then f'' else
  f'

(* val make_weakly_memoized_identity : ?size:int (* 0 *) -> unit -> ('a -> 'a) *)
let make_weakly_memoized_identity ?size () =
  weakly_memoize ~equality:(=) ?size (fun x -> x)  (* STRUCTURAL equality *)

(* Shorthand, with default size (0): *)
let make_id () = weakly_memoize (fun x -> x)

(* val attach : ?id:('a -> 'a) -> ('a -> 'b) -> 'a -> 'b *)
let attach ?id =
  let idA = match id with None -> make_id () | Some id -> id in
  fun f x -> (f (idA x))

(* val co_attach : ?id:('b -> 'b) -> ('a -> 'b) -> 'a -> 'b *)
let co_attach ?id =
  let idB = match id with None -> make_id () | Some id -> id in
  fun f x -> idB (f x)

(* val bi_attach : ?idA:('a -> 'a) -> ?idB:('b -> 'b) -> ('a -> 'b) -> 'a -> 'b *)
let bi_attach ?idA ?idB =
  let idA = match idA with None -> make_id () | Some id -> id in
  let idB = match idB with None -> make_id () | Some id -> id in
  fun f x -> idB (f (idA x))

(* val bi_attach_endo : ?id:('a -> 'a) -> ('a -> 'a) -> 'a -> 'a *)
let bi_attach_endo ?id =
  let id = match id with None -> make_id () | Some id -> id in
  fun f x -> id (f (id x))

(* val weakly_memoize_by_physical_eq : ?size:int -> ('a -> 'b) -> 'a -> 'b *)
let weakly_memoize_by_physical_eq ?size f =
  weakly_memoize ~equality:(==) ?size f (* PHYSICAL equality *)

(* val memoize : ?id:('a -> 'a) -> ('a -> 'b) -> 'a -> 'b *)
let memoize ?id f =     (* ----------------------------------------------  is (f)' ∘ idᴬ --------- NOT (f ∘ idᴬ)' *)
  attach ?id (weakly_memoize_by_physical_eq f)

(* val co_memoize : ?id:('b -> 'b) -> ('a -> 'b) -> 'a -> 'b *)
let co_memoize ?id f =   (* ---------------------------------------------  is (idᴮ ∘ f)' --------- NOT  idᴮ ∘ (f)' *)
  weakly_memoize_by_physical_eq (co_attach ?id f)

(* val bi_memoize_endo : ?id:('a -> 'a) -> ('a -> 'a) -> 'a -> 'a *)
let bi_memoize_endo ?id f = (* ------------------------------------------  is (idᴬ ∘ f)' ∘ idᴬ --- NOT (idᴬ ∘ f ∘ idᴬ)' *)
  (* Same normalization (filter) attached to domain and codomain: *)
  let id = match id with None -> make_id () | Some id -> id in
  attach ~id (weakly_memoize_by_physical_eq (co_attach ~id f))

(* val bi_memoize : ?idA:('a -> 'a) -> ?idB:('b -> 'b) -> ('a -> 'b) -> 'a -> 'b *)
let bi_memoize ?idA ?idB f = (* -----------------------------------------  is (idᴮ ∘ f)' ∘ idᴬ --- NOT (idᴮ ∘ f ∘ idᴬ)' *)
  attach ?id:idA (weakly_memoize_by_physical_eq (co_attach ?id:idB f))

(* Really extreme!  *)
module Sublists = struct

  (* val id : ?elt:'b identity -> unit -> ('b list) identity *)
  let id ?elt () =
    let id_list = make_id () in
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
  let id_elt = match elt with None -> make_id () | Some id -> id in
  List.map (id_elt)

(* Redefinition with a more general interface:
   val through_lists : ?sublists:unit -> ?elt:'b identity -> unit -> ('b list) identity *)
let through_lists ?sublists =
  match sublists with
  | Some () -> Sublists.id
  | None    -> through_lists (* simple version (just a mapping) *)

(* val through_arrays : ?elt:'b identity -> unit -> ('b array) identity *)
let through_arrays ?elt () =
  let id_elt = match elt with None -> make_id () | Some id -> id in
  Array.map (id_elt)

(* Easy interface for arrays (i.e. when the codomain is an array): *)
module Array = struct
  (* Just `through_arrays' composed with the good function: *)
  let co_attach ?elt = co_attach ~id:(through_arrays ?elt ())
  let    attach ?elt =    attach ~id:(through_arrays ?elt ())
  let bi_attach ?eltA ?eltB = bi_attach ~idA:(through_arrays ?elt:eltA ()) ~idB:(through_arrays ?elt:eltB ())
  (* --- *)
  let id = through_arrays
end

(* Easy interface for lists (i.e. when the codomain is a list): *)
module List = struct
  (* Just `through_lists' composed with the good function: *)
  let co_attach ?sublists ?elt = co_attach ~id:(through_lists ?sublists ?elt ())
  let    attach ?sublists ?elt =    attach ~id:(through_lists ?sublists ?elt ())
  let bi_attach ?sublists ?eltA ?eltB = bi_attach ~idA:(through_lists ?sublists ?elt:eltA ()) ~idB:(through_lists ?sublists ?elt:eltB ())
  (* --- *)
  let id = through_lists
end

(* General functorized interface: *)
module Through (M:sig  type 'a t  val map : ('a -> 'b) -> ('a t -> 'b t)  end) = struct

 type 'a t = 'a M.t

 let through ?elt () =
   let id_elt = match elt with None -> make_id () | Some id -> id in
   M.map (id_elt)

  let co_attach ?elt = co_attach ~id:(through ?elt ())
  let    attach ?elt =    attach ~id:(through ?elt ())
  let bi_attach ?eltA ?eltB = bi_attach ~idA:(through ?elt:eltA ()) ~idB:(through ?elt:eltB ())

  let id = through

end

