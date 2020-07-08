(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2020  Jean-Vincent Loddo
   Copyright (C) 2020  Université Sorbonne Paris Nord

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

(** Generalized hash tables, weak (ephemerons) or standard. *)

let default_size = 0

(* The function `make' constructs an immediate object of this type: *)
type ('a,'b) t =
    < mem      : 'a -> bool;
      add      : 'a -> 'b -> unit;
      replace  : 'a -> 'b -> unit;
      (* --- *)
      add_list     : ('a * 'b) list -> unit;
      replace_list : ('a * 'b) list -> unit;
      (* --- *)
      find     : 'a -> 'b;
      find_all : 'a -> 'b list;
      find_opt : 'a -> 'b option;
      find_or_bind : 'a -> 'b lazy_t -> 'b;
      (* --- *)
      remove   : 'a -> unit;
      fold     : 's. ('a -> 'b -> 's -> 's) -> 's -> 's;
      iter     : ('a -> 'b -> unit) -> unit;
      length   : int;
      (* --- *)
      filter_map_inplace : ('a -> 'b -> 'b option) -> unit;
      (* --- *)
      to_list       : 'a list;
      to_assoc_list : ('a * 'b) list;
      to_hashtbl    : ('a, 'b) Hashtbl.t; (* a copy *)
      (* --- *)
      (* --- Maintenance --- *)
      (* Note:
          `clean' and `stats_alive' are meaningfull for weak tables.
          For hash tables `clean' do nothing while `stats_alive' is equivalent to `stats'. *)
      clean       : unit;
      stats       : Hashtbl.statistics;
      stats_alive : Hashtbl.statistics;
      is_weak     : bool;
      >

(* To have long methods with a single implementation: *)
(* val method_to_hashtbl : < clean: unit;  length: int;  to_assoc_list: ('a * 'b) list; .. > -> ('a, 'b) Hashtbl.t *)
let method_to_hashtbl (self) =
  let () = self#clean in
  let size = int_of_float ((float_of_int (self#length)) /. 0.70) in
  let copy = Hashtbl.create size in
  (* We have to use a list because, for the same key, self#iter passes
     arguments to the iterated function in reverse order of introduction: *)
  let () = List.iter (fun (x,y) -> Hashtbl.add copy x y) (self#to_assoc_list) in
  copy

(* Make a standard hash table (with a parametric equality): *)
let new_hashtbl (type keys) ?identifier ?equality ?(size=default_size) () =
  let hash, equal = match identifier, equality with
  | None, None       -> (Hashtbl.hash, (=))
  | None, Some eq    -> (Hashtbl.hash, eq)
  | Some id, None    -> (fun x -> Hashtbl.hash (id x)), (fun x y -> (id x)=(id y))
  | Some id, Some eq -> (fun x -> Hashtbl.hash (id x)), eq
  in
  let module Hashed = struct  type t = keys  let hash = hash  let equal = equal  end in
  let module Table  = Hashtbl.Make(Hashed) in
  let ht : 'b Table.t = Table.create (size) in
  object (self)
      method mem      = Table.mem ht
      method add      = Table.add ht
      method replace  = Table.replace ht
      method add_list     = List.iter (fun (x,y) -> Table.add ht x y)
      method replace_list = List.iter (fun (x,y) -> Table.replace ht x y)
      method find     = Table.find ht
      method find_all = Table.find_all ht
      method find_opt = fun x -> (try Some (Table.find ht x) with Not_found -> None)
      method find_or_bind = fun x y -> (try Table.find ht x  with Not_found -> let y = (Lazy.force y) in Table.replace ht x y; y)
      method remove   = Table.remove ht
      method fold f   = Table.fold f ht
      method iter f   = Table.iter f ht
      method length   = Table.length ht
      method to_list  = Table.fold (fun x y s -> x::s) ht []
      method to_assoc_list = Table.fold (fun x y s -> (x,y)::s) ht []
      method filter_map_inplace f = Table.filter_map_inplace f ht
      method clean    = ()
      method stats    = Table.stats ht
      method stats_alive = Table.stats ht
      method is_weak  = false
      method to_hashtbl = method_to_hashtbl (self)
  end

(* Make a weak hash table (with a parametric equality): *)
let new_weaktbl (type keys) ?identifier ?equality ?(size=default_size) () =
  let hash, equal = match identifier, equality with
  | None, None       -> (Hashtbl.hash, (=))
  | None, Some eq    -> (Hashtbl.hash, eq)
  | Some id, None    -> (fun x -> Hashtbl.hash (id x)), (fun x y -> (id x)=(id y))
  | Some id, Some eq -> (fun x -> Hashtbl.hash (id x)), eq
  in
  let module Hashed = struct  type t = keys  let hash = hash  let equal = equal  end in
  let module Table  = Ephemeron.K1.Make(Hashed) in
  let ht : 'b Table.t = Table.create (size) in
  object (self)
      method mem      = Table.mem ht
      method add      = Table.add ht
      method replace  = Table.replace ht
      method add_list     = List.iter (fun (x,y) -> Table.add ht x y)
      method replace_list = List.iter (fun (x,y) -> Table.replace ht x y)
      method find     = Table.find ht
      method find_all = Table.find_all ht
      method find_opt = fun x -> (try Some (Table.find ht x) with Not_found -> None)
      method find_or_bind = fun x y -> (try Table.find ht x  with Not_found -> let y = (Lazy.force y) in Table.replace ht x y; y)
      method remove   = Table.remove ht
      method fold f   = Table.fold f ht
      method iter f   = Table.iter f ht
      method length   = Table.length ht
      method to_list  = Table.fold (fun x y s -> x::s) ht []
      method to_assoc_list = Table.fold (fun x y s -> (x,y)::s) ht []
      method filter_map_inplace f = Table.filter_map_inplace f ht
      method clean   = Table.clean ht
      method stats   = Table.stats ht
      method stats_alive = Table.stats_alive ht
      method is_weak  = true
      method to_hashtbl = method_to_hashtbl (self)
  end

(** Generalized constructor: *)
let make ?weak ?identifier ?equality ?size ?init () : ('a, 'b) t =
  let t =
    match weak with
    | None    -> new_hashtbl ?identifier ?equality ?size ()
    | Some () -> new_weaktbl ?identifier ?equality ?size ()
  in
  let () = match init with
  | None -> ()
  | Some xs -> t#add_list xs
  in
  (Obj.magic t)
  (* t *)

(*  Comment on this Obj.magic: all works fine (revno 507) until I want to
    define a type for the result of make. I use Obj.magic reluctantly but
    I don't know how to do it properly. Anyway, the result of a `make'
    application is always a weak polymorphic type, as in the previous case,
    so I don't see how Obj.magic could be cause troubles:

    let t = Table.make ~weak:() ~equality:(=) () ;;
    val t : ('_a, '_b) Table.t = <obj>

    ---
    File "STRUCTURES/table.ml", line 143, characters 2-3:
    Error: This expression has type
        < add : 'a -> 'b -> unit; add_list : ('a * 'b) list -> unit;
          ...(((all the stuff without the 's you're looking for)))...
          to_hashtbl : ('a, 'b) Hashtbl.t; to_list : 'a list >
      but an expression was expected of type ('a, 'b) t
      The universal variable 's would escape its scope
*)
