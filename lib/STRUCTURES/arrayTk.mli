(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2018 Jean-Vincent Loddo

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

type  'a t      = 'a array (* alias *)
 and  'a tt     = 'a t t   (* alias *)
 and  index     = int
 and length     = int
 and 'a compare = ('a -> 'a -> int)

module Init_array : sig
  val init_x1 : length -> (index -> 'a) -> 'a t
  val init_x2 : length -> (index -> 'a * 'b) -> 'a t * 'b t
  val init_x3 : length -> (index -> 'a * 'b * 'c) -> 'a t * 'b t * 'c t
  val init_x4 : length -> (index -> 'a * 'b * 'c * 'd) -> 'a t * 'b t * 'c t * 'd t
  val init_x5 : length -> (index -> 'a * 'b * 'c * 'd * 'e) -> 'a t * 'b t * 'c t * 'd t * 'e t
end

module Tuple_array : sig
  (* --- *)
  val split2 : ('a * 'b) t -> 'a t * 'b t
  val split3 : ('a * 'b * 'c) t -> 'a t * 'b t * 'c t
  val split4 : ('a * 'b * 'c * 'd) t -> 'a t * 'b t * 'c t * 'd t
  val split5 : ('a * 'b * 'c * 'd * 'e) t -> 'a t * 'b t * 'c t * 'd t * 'e t
  (* --- *)
  val combine2 : 'a t -> 'b t -> ('a * 'b) t
  val combine3 : 'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t
  val combine4 : 'a t -> 'b t -> 'c t -> 'd t -> ('a * 'b * 'c * 'd) t
  val combine5 : 'a t -> 'b t -> 'c t -> 'd t -> 'e t -> ('a * 'b * 'c * 'd * 'e) t
  (* --- *)
  val split   : ('a * 'b) t -> 'a t * 'b t   (* split2   *)
  val combine : 'a t -> 'b t -> ('a * 'b) t  (* combine2 *)
end

(* =================================================================
                     High-level interface
   ================================================================= *)

module Swap : sig
  type play = (index * index) list
  (* --- *)
   and 'a source = 'a t
   and 'a target = 'a t
  (* --- *)
  val swap   : ?in_place:unit -> (index * index) list -> 'a t -> 'a t * play
  (* --- *)
  val replay : ?in_place:unit -> play -> 'a t -> 'a t
  val rewind : ?in_place:unit -> play -> 'a t -> 'a t
  (* --- *)
  val compose : play -> play -> play (* List.append *)
end

module Permutation : sig
  type play = index t
  (* --- *)
   and 'a source = 'a t
   and 'a target = 'a t

  (* --- *)
  val identity : int -> play
  val shuffle  : int -> play

  val shift_left  : int -> play -> play
  val shift_right : int -> play -> play
  val priority    : int -> play -> play
  val reverse     : play -> play
  val inverse     : play -> play
  val apply       : play -> 'a array -> 'a array
  val unapply     : play -> 'a array -> 'a array (* unapply p xs = apply (inverse p) xs *)

  (* array_map p f xs = unapply p (Array.map f (apply p xs)) *)
  val array_map   : play -> ('a -> 'b) -> 'a array -> 'b array

  (* array_mapi p f xs = unapply p (Array.mapi (fun j x -> f p.(j) x) (apply p xs)) *)
  val array_mapi  : play -> (int -> 'a -> 'b) -> 'a array -> 'b array

  (* array_iteri p f xs = Array.iteri (fun j x -> f p.(j) x) (apply p xs) *)
  val array_iteri : play -> (int -> 'a -> unit) -> 'a array -> unit

  (* array_foldi p f s0 xs = Array.fold_lefti (fun j s x -> f p.(j) s x) s0 (apply p xs) *)
  val array_foldi : play -> (int -> 'a -> 'b -> 'a) -> 'a -> 'b array -> 'a

  (* (compose p1 p2) means (p1; p2), i.e. is equivalent to perform p1 then p2.
      Note also that ?in_place concerns the first argument. *)
  val compose : ?in_place:unit -> play -> play -> play
  val compose_list : play -> play list -> play

  (* append p1 p2 = Array.append p1 (translate (Array.length p1) p2)
     where:    q = translate k p   =>   q.(i) = p.(i) + k  *)
  val append : play -> play -> play

  (* concat_list ps = List.fold_left append [] ps  (but implemented in a slightly more efficient way) *)
  val concat_list  : play list  -> play
  val concat_array : play array -> play
  (* --- *)
  val array_sort    : ?in_place:unit -> ?stable:unit -> ?compare:('a compare) -> 'a t -> 'a t * play
  val array_shuffle : ?in_place:unit -> 'a t -> 'a t * play
  val array_reverse : ?in_place:unit -> 'a t -> 'a t * play
  (* --- *)
  val import_swap : (index * index) list -> length -> play
  val swap        : ?in_place:unit -> (index * index) list -> 'a t -> 'a t * play (* replay∘import_swap *)
  (* --- *)
  val replay  : ?in_place:unit -> play -> 'a t -> 'a t (* apply *)
  val rewind  : ?in_place:unit -> play -> 'a t -> 'a t (* unapply *)
  (* --- *)
  val rotate_right : ?in_place:unit -> rows:int -> 'a t -> 'a t * play
end

module Sorting : sig
  type 'a play = 'a compare * 'a t * unicity * Permutation.play
   and unicity = bool
   and locations  = [ `unique of index | `segment of index * index ]
  (* --- *)
   and 'a source = 'a t
   and 'a target = 'a t
  (* --- *)
  val sort   : ?in_place:unit -> ?stable:unit -> ?compare:('a compare) -> 'a t -> 'a t * 'a play
  (* --- *)
  (* Unicity is not required: *)
  val locate    : 'a play -> ?a:index -> ?b:index -> 'a -> locations option
  val find_all  : 'a play -> ?a:index -> ?b:index -> 'a -> index array
  val assoc_all : 'a play -> ?a:index -> ?b:index -> 'b t -> 'a -> 'b array
  (* --- *)
  (* Unicity is required: *)
  val find      : 'a play -> ?a:index -> ?b:index -> 'a -> index option
  val assoc     : 'a play -> 'b t -> 'a -> 'b option
  (* --- *)
  val replay : ?in_place:unit -> 'a play -> 'b t -> 'b t
  val rewind : ?in_place:unit -> 'a play -> 'b t -> 'b t
end

(* Split.play are a particular case of Partitions.play that may be rewound by flatten! *)
module Split : sig

  (* Note: the implicit outer_size is the length of the array: *)
  type play = total_size * inner_size t
   and inner_size = int (* >=0 *)
   and total_size = int (* >=0 *)
  (* --- *)
   and 'a source = 'a t
   and 'a target = 'a tt

  (* The rest, if any, is appended in the last array, so the argument inner_sizes may be fixed and returned as play: *)
  val split : inner_sizes:(int t) -> 'a t -> 'a tt * play
  val sub   : ?size:int -> pos:index -> 'a t -> 'a tt * play  (* the sub-array is placed as central part among three parts *)
  val pivot : index -> 'a t -> 'a tt * play                   (* the singleton is placed as central part among three parts *)
  (* --- *)
  val amass  : inner_size:int -> 'a t -> 'a tt * play
  val amassg : ?inner_size:int -> ?outer_size:int -> 'a t -> 'a tt * play
  (* --- *)
  val import : 'a tt -> play  (* <= Split.play may be recovered *)
  val get_total_and_inner_sizes : 'a tt -> play (* alias for import *)
  val get_total_size : 'a tt -> int
  val split_like : 'b tt -> 'a t -> 'a tt * play
  (* --- *)
  val flatten : 'a tt -> 'a t
  (* --- *)
  val replay : play -> 'a t  -> 'a tt (* replay is `split' with a slightly different signature *)
  val rewind : play -> 'a tt -> 'a t  (* rewind is `flatten' but knowing the inner sizes *)

  (* This operation is idempotent if and only if the provided matrix (play) is an upper triangular matrix
     (inner sizes are decreasing) without empty rows. The optional parameter ?force allows to transpose a
     matrix even if some rows are empty. *)
  val transpose : ?force:unit -> play -> Permutation.play * play
  (* ---*)

end (* Split *)

module Partition : sig
  (* --- *)
  type play = index tt
   and class_index = int (* 0..(n-1) *)
  (* --- *)
   and 'a source = 'a t
   and 'a target = 'a tt
  (* --- *)
  (* Ordinary and generalized (with indexes and state) constructors: *)
  val partition  : ?outer_size:int -> ?min_outer_size:int -> ('a -> class_index) -> 'a t -> 'a tt * play
  val partitioni : ?outer_size:int -> ?min_outer_size:int -> (index -> 'a -> class_index) -> 'a t -> 'a tt * play
  val partitiong : ?outer_size:int -> ?min_outer_size:int -> ('s -> index -> 'a -> class_index * 's) -> 's -> 'a t -> 'a tt * play
  (* --- *)
  (* In this section, the result ('a tt) is always bipartite: the second part contains all the duplicated elements: *)
  val uniq    : ?compare:('a compare) -> ?sort:unit -> 'a t -> 'a tt * play
  (* --- *)
  val filter  : ('a -> bool) -> 'a t -> 'a tt * play
  val filteri : (index -> 'a -> bool) -> 'a t -> 'a tt * play
  val filterg : ('s -> index -> 'a -> bool * 's) -> 's -> 'a t -> 'a tt * play
  (* --- *)
  (* Equivalent to: partitioni (fun i _ -> i mod outer_size) *)
  val round_robin : outer_size:int -> 'a t -> 'a tt * play
  (* --- *)
  (* The second tool shoud be partially applied in order to obtain a function 'key -> 'details array *)
  val group_by       : ?compare:('key compare) -> ('record -> 'key * 'details) -> 'record t -> ('key  * 'details array) t
  val group_by_assoc : ?compare:('key compare) -> ('record -> 'key * 'details) -> 'record t ->  'key -> 'details array
  (* --- *)
  val replay : play -> 'a t  -> 'a tt
  val rewind : play -> 'a tt -> 'a t
end

module Partition_v2 : sig

  type play = (Permutation.play) * (Split.play) (* (index t) * (total_size * inner_size t) *)
   and 'a source = 'a t
   and 'a target = 'a tt
  (* --- *)
   and play_v1 = Partition.play (* index tt *)
   and play_v2 = play

  val import : Partition.play -> play
  val export : play -> Partition.play

  val replay : play -> 'a t  -> 'a tt
  val rewind : play -> 'a tt -> 'a t
end

