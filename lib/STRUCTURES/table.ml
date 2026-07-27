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

(* --- Weak tables since OCaml 5.0 ---

   OCaml 5.0 removed `fold', `iter' and `filter_map_inplace' from `Ephemeron.S'
   (iterating over ephemerons is unsound when several domains run in parallel),
   while the object type ('a,'b) t defined below requires them, and our own clients
   really call them (Channel.to_assoc_list, Channel.filter_map_inplace, Hashset.fold).
   The following module rebuilds what `Ephemeron.K1.Make' used to provide, on top of
   the primitives that remain available in 5.x, i.e. `Ephemeron.K1.make'/`query' and
   the `Weak' module. Both are needed, each for its own reason:

     - the ephemeron, because the data must not keep its own key alive: this really
       happens here (in Channel.Club2UC_book the data, a conjunction, contains the
       clubs used as keys), so a weak key with a strong data would leak;

     - the weak pointer, because `Ephemeron.K1.query' requires the key as an argument
       and 5.x provides no way to extract the key from an ephemeron: without an
       enumerable (and non retaining) source of keys, iteration is impossible.

   Soundness: the reason for the upstream removal is the parallel GC. This library is
   currently used by single-domain programs (threads, no `Domain'), where the
   construction is safe. Should it ever be used from several domains, this module must
   be revisited (and the iterating methods of the object type dropped).
*)
module Weaktbl : sig
  type ('k,'d) t
  val create   : hash:('k -> int) -> equal:('k -> 'k -> bool) -> int -> ('k,'d) t
  (* --- *)
  val add      : ('k,'d) t -> 'k -> 'd -> unit
  val replace  : ('k,'d) t -> 'k -> 'd -> unit
  val remove   : ('k,'d) t -> 'k -> unit           (* the most recently added binding *)
  (* --- *)
  val mem      : ('k,'d) t -> 'k -> bool
  val find     : ('k,'d) t -> 'k -> 'd             (* raises Not_found *)
  val find_all : ('k,'d) t -> 'k -> 'd list        (* most recently added first *)
  val length   : ('k,'d) t -> int                  (* bindings, dead ones included *)
  (* --- *)
  val fold     : ('k -> 'd -> 's -> 's) -> ('k,'d) t -> 's -> 's
  val iter     : ('k -> 'd -> unit) -> ('k,'d) t -> unit
  val filter_map_inplace : ('k -> 'd -> 'd option) -> ('k,'d) t -> unit
  (* --- *)
  val clean    : ('k,'d) t -> unit
  val stats    : ('k,'d) t -> Hashtbl.statistics
  val stats_alive : ('k,'d) t -> Hashtbl.statistics
end = struct

  (* A binding: the key is only weakly referenced (`kw', a 1-slot weak array) and the
     data is only referenced by the ephemeron, which drops it as soon as the key dies. *)
  type ('k,'d) entry = {
    kw          : 'k Weak.t;                (* of size 1 *)
    mutable eph : ('k,'d) Ephemeron.K1.t;
    }

  (* Bindings are indexed by the hash of their key (this is also the way
     `Ephemeron.K1.Make' was structured). The field `clean_at' supports the amortized
     automatic cleaning performed by `add' (see below). *)
  type ('k,'d) t = {
    tbl              : (int, ('k,'d) entry) Hashtbl.t;
    hash             : 'k -> int;
    equal            : 'k -> 'k -> bool;
    mutable clean_at : int;
    }

  let min_clean_at = 16

  let create ~hash ~equal size =
    { tbl = Hashtbl.create size; hash; equal; clean_at = max min_clean_at (2*size) }

  let make_entry k d =
    let kw = Weak.create 1 in
    let () = Weak.set kw 0 (Some k) in
    { kw; eph = Ephemeron.K1.make k d }

  (* The current binding of an entry, if its key is still alive: *)
  let entry_get (e) =
    match Weak.get e.kw 0 with
    | None   -> None
    | Some k -> (match Ephemeron.K1.query e.eph k with None -> None | Some d -> Some (k,d))

  let entry_alive (e) = match entry_get e with None -> false | Some _ -> true

  (* Remove all dead bindings. Note that this was done automatically by
     `Ephemeron.K1.Make' when resizing, hence the amortized call in `add': *)
  let clean t =
    let () = Hashtbl.filter_map_inplace (fun _h e -> if entry_alive e then Some e else None) t.tbl in
    t.clean_at <- max min_clean_at (2 * (Hashtbl.length t.tbl))

  let add t k d =
    let () = if (Hashtbl.length t.tbl) >= t.clean_at then clean t in
    Hashtbl.add t.tbl (t.hash k) (make_entry k d)

  (* Note: `Hashtbl.find_all' returns the bindings of a hash in the reverse order of
     introduction, which is exactly the order expected from `find_all' and `remove': *)
  let bucket t k = Hashtbl.find_all t.tbl (t.hash k)

  let find_all t k =
    List.filter_map
      (fun e -> match entry_get e with Some (k',d) when t.equal k k' -> Some d | _ -> None)
      (bucket t k)

  let find_opt t k =
    let rec loop = function
    | []      -> None
    | e :: es -> (match entry_get e with Some (k',d) when t.equal k k' -> Some d | _ -> loop es)
    in
    loop (bucket t k)

  let find t k = match find_opt t k with Some d -> d | None -> raise Not_found
  let mem  t k = match find_opt t k with Some _ -> true | None -> false

  (* As `Hashtbl.replace', the key of the replaced binding becomes the provided one,
     hence the weak pointer is reset together with the ephemeron: *)
  let replace t k d =
    let rec loop = function
    | []      -> add t k d
    | e :: es ->
        (match entry_get e with
         | Some (k',_) when t.equal k k' ->
             let () = Weak.set e.kw 0 (Some k) in
             e.eph <- Ephemeron.K1.make k d
         | _ -> loop es)
    in
    loop (bucket t k)

  (* Remove the most recently added binding of the key, if any. The bucket is rebuilt
     because `Hashtbl.remove' would drop the most recent binding of the *hash*, which
     may belong to another key (collision) or to a dead entry: *)
  let remove t k =
    let es = bucket t k in
    let rec loop acc = function
    | []      -> None
    | e :: es ->
        (match entry_get e with
         | Some (k',_) when t.equal k k' -> Some (List.rev_append acc es)
         | _ -> loop (e::acc) es)
    in
    match loop [] es with
    | None      -> ()
    | Some es' ->
        let h = t.hash k in
        (* Empty the bucket, then re-introduce the survivors in their original order
           (`Hashtbl.add' pushes in front, hence the reversal): *)
        let () = List.iter (fun _ -> Hashtbl.remove t.tbl h) es in
        List.iter (fun e -> Hashtbl.add t.tbl h e) (List.rev es')

  let fold f t s =
    Hashtbl.fold (fun _h e s -> match entry_get e with Some (k,d) -> f k d s | None -> s) t.tbl s

  let iter f t =
    Hashtbl.iter (fun _h e -> match entry_get e with Some (k,d) -> f k d | None -> ()) t.tbl

  (* Dead bindings are removed on the way. The ephemeron is rebuilt because 5.x
     provides no way to set the data of an existing one: *)
  let filter_map_inplace f t =
    Hashtbl.filter_map_inplace
      (fun _h e ->
         match entry_get e with
         | None       -> None
         | Some (k,d) ->
             (match f k d with
              | None    -> None
              | Some d' -> let () = e.eph <- Ephemeron.K1.make k d' in Some e))
      t.tbl

  let length t = Hashtbl.length t.tbl
  let stats  t = Hashtbl.stats t.tbl

  (* Statistics of alive bindings only. The bucket histogram is the one of a fresh copy
     containing the alive bindings, not the one of the current table: only `num_bindings'
     is exact, which is enough for the debugging usage made of it (cf. Channel): *)
  let stats_alive t =
    let copy = Hashtbl.create (Hashtbl.length t.tbl) in
    let () = Hashtbl.iter (fun h e -> if entry_alive e then Hashtbl.add copy h e) t.tbl in
    Hashtbl.stats copy

end (* Weaktbl *)

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

(* Make a weak hash table (with a parametric equality). Note that the underlying
   structure is our own `Weaktbl' and no longer `Ephemeron.K1.Make', which lost its
   iterating functions in OCaml 5.0 (see the comment on top of this file): *)
let new_weaktbl ?identifier ?equality ?(size=default_size) () =
  let hash, equal = match identifier, equality with
  | None, None       -> (Hashtbl.hash, (=))
  | None, Some eq    -> (Hashtbl.hash, eq)
  | Some id, None    -> (fun x -> Hashtbl.hash (id x)), (fun x y -> (id x)=(id y))
  | Some id, Some eq -> (fun x -> Hashtbl.hash (id x)), eq
  in
  let module Table = Weaktbl in
  let ht : ('a, 'b) Table.t = Table.create ~hash ~equal (size) in
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
