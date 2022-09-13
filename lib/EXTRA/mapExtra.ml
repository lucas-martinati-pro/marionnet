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

#load "include_type_definitions_p4.cmo";;
INCLUDE DEFINITIONS "../../../../lib/EXTRA/mapExtra.mli"
;;

IFDEF OCAML4_07_OR_LATER THEN
module Pervasives = Stdlib
ENDIF


module Extend = functor (M:Map.S) -> struct
  include M

  (** Extra functions: *)

  let search (k : key) (m : 'a t) : 'a option =
    try Some (find k m) with Not_found -> None

  let filter (p : key -> 'a -> bool) (m : 'a t) : 'a t =
    fold (fun k a m' -> if p k a then add k a m' else m') m empty

  let filter_map (p : key -> 'a -> bool) (f:'a -> 'b) (m : 'a t) : 'b t =
    fold (fun k a m' -> if p k a then add k (f a) m' else m') m empty

  let filter_mapi (p : key -> 'a -> bool) (f:key -> 'a -> 'b) (m : 'a t) : 'b t =
    fold (fun k a m' -> if p k a then add k (f k a) m' else m') m empty

  let product (m1:'a t) (m2:'b t) : ('a * 'b) t =
    filter_mapi (fun k _ -> mem k m2) (fun k a -> (a, (find k m2))) m1

  let of_list ?(acc=empty) (xs : (key * 'a) list) : 'a t =
    List.fold_left (fun m (k,a) -> add k a m) acc xs

  let to_list ?(acc=[]) ?(reverse=false) (m : 'a t) =
    let acc = if reverse then (List.rev acc) else acc in
    let l = fold (fun k a xs -> (k,a)::xs) m acc in
    if reverse then List.rev l else l

  let domain ?(reverse=true) (m : 'a t) =
    fst (List.split (to_list ~reverse m))

  let codomain ?(reverse=true) (m : 'a t) =
    snd (List.split (to_list ~reverse m))

  let restrict m ks =
    List.fold_left (fun m' k -> try add k (find k m) m' with Not_found -> m') empty ks

  let substract m ks =
    List.fold_left (fun m' k -> remove k m') m ks
 end


module Make (Ord : Map.OrderedType) = Extend (Map.Make (Ord))

module String_map = Make (struct type t = string let compare = Pervasives.compare end)
module Int_map    = Make (struct type t = int    let compare = Pervasives.compare end)

(** The data structure is not really re-implemented: an imperative (destructive) map
    is simply implemented as a reference to a persistent map.
    This reference is update by some functions ([add], [remove], [map],...). *)
module Destructive = struct

 module type S =
   sig
      type key
      type 'a t
      val create    : unit -> 'a t
      val is_empty  : 'a t -> bool
      val add       : key -> 'a -> 'a t -> unit
      val find      : key -> 'a t -> 'a
      val remove    : key -> 'a t -> unit
      val mem       : key -> 'a t -> bool
      val iter      : (key -> 'a -> unit) -> 'a t -> unit
      val map       : ('a -> 'a) -> 'a t -> unit
      val mapi      : (key -> 'a -> 'a) -> 'a t -> unit
      val fold      : (key -> 'a -> 'b -> 'b) -> 'a t -> 'b -> 'b
      val compare   : ('a -> 'a -> int) -> 'a t -> 'a t -> int
      val equal     : ('a -> 'a -> bool) -> 'a t -> 'a t -> bool

      (* Extra functions: *)

      val search      : key -> 'a t -> 'a option
      val copy        : 'a t -> 'a t
      val filter      : (key -> 'a -> bool) -> 'a t -> unit
      val filter_map  : (key -> 'a -> bool) -> ('a -> 'a) -> 'a t -> unit
      val filter_mapi : (key -> 'a -> bool) -> (key -> 'a -> 'a) -> 'a t -> unit
      val of_list     : ?acc:'a t -> (key * 'a) list -> 'a t
      val to_list     : ?acc:(key * 'a) list -> ?reverse:bool -> 'a t -> (key * 'a) list
      val domain      : ?reverse:bool -> 'a t -> key list
      val codomain    : ?reverse:bool -> 'a t -> 'a list
      val restrict    : 'a t -> key list -> unit
      val substract   : 'a t -> key list -> unit

   end

 module Make (Ord : Map.OrderedType) = struct
  module Persistent = Make (Ord)
  type key = Ord.t
  type 'a t = 'a Persistent.t ref
  let create () = ref Persistent.empty
  let is_empty t = Persistent.is_empty (!t)
  let add k a t = (t := Persistent.add k a !t)
  let find k t = Persistent.find k (!t)
  let remove k t = (t := Persistent.remove k !t)
  let mem k t = Persistent.mem k (!t)
  let iter f t = Persistent.iter f (!t)
  let map f t = (t := Persistent.map f !t)
  let mapi f t = (t := Persistent.mapi f !t)
  let fold f t = Persistent.fold f (!t)
  let compare f t0 t1 = Persistent.compare f (!t0) (!t1)
  let equal f t0 t1 = Persistent.equal f (!t0) (!t1)

    (* Extra functions: *)
  let search k t = Persistent.search k (!t)
  let copy t = ref (!t)
  let filter f t = (t := Persistent.filter f !t)
  let filter_map  p f t = (t := Persistent.filter_map  p f !t)
  let filter_mapi p f t = (t := Persistent.filter_mapi p f !t)

  let of_list ?acc l =
    let acc = match acc with None -> None | Some t -> Some (!t) in
    ref (Persistent.of_list ?acc l)

  let to_list ?acc ?reverse t  = Persistent.to_list ?acc ?reverse (!t)
  let domain ?reverse t = Persistent.domain ?reverse (!t)
  let codomain ?reverse t = Persistent.codomain ?reverse (!t)
  let restrict t l = (t := Persistent.restrict (!t) l)
  let substract t l = (t := Persistent.substract (!t) l)
 end

 module String_map = Make (struct type t = string let compare = Pervasives.compare end)
 module Int_map    = Make (struct type t = int    let compare = Pervasives.compare end)

end (* Destructive *)


