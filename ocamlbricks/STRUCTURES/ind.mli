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

open ArrayTk

type index = int

(* The simplest case is a bijection when 'k = int and the functions are both the identity over indexes: *)
type 'k indexing =
  | Bijection of ('k -> index) * (index -> 'k)      (* (k2i, i2k) : 'k <-> {0,..,n-1} *)
  | Keys      of ('k, index) Hashtbl.t * ('k array) (* (k2i, i2k) : 'k <-> {0,..,n-1} *)

(* In the simplest case (keys = Bijection(id,id)) the structure is a "tensor" (at this level) *)
type ('k,'a) t = {
  (* --- *)
  keys   : 'k indexing;
  elts   : 'a array;
  (* --- *)
  (* Element's permutation: *)
  perm   : Permutation.play option;
  (* --- *)
  (* Useful only for ungrouping, when 'a is itself of type ('h,'b) t *)
  ungrouping : (Permutation.play array) list;
}

type ('k1,'k2,'a) tt = ('k1, ('k2, 'a) t) t
type ('k1,'k2,'k3,'a) ttt = ('k1, ('k2,'k3,'a) tt) t
(* --- *)
type ('k1,'a) t1 = ('k1, 'a) t
type ('k1,'k2,'a) t2 = ('k1, ('k2, 'a) t) t
type ('k1,'k2,'k3,'a) t3 = ('k1, ('k2,'k3,'a) t2) t
type ('k1,'k2,'k3,'k4,'a) t4 = ('k1, ('k2,'k3,'k4,'a) t3) t
type ('k1,'k2,'k3,'k4,'k5,'a) t5 = ('k1, ('k2,'k3,'k4,'k5,'a) t4) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'a) t6 = ('k1, ('k2,'k3,'k4,'k5,'k6,'a) t5) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'a) t7 = ('k1, ('k2,'k3,'k4,'k5,'k6,'k7,'a) t6) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'a) t8 = ('k1, ('k2,'k3,'k4,'k5,'k6,'k7,'k8,'a) t7) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'a) t9 = ('k1, ('k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'a) t8) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'k10,'a) t10 = ('k1, ('k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'k10,'a) t9) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'k10,'k11,'a) t11 = ('k1, ('k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'k10,'k11,'a) t10) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'k10,'k11,'k12,'a) t12 = ('k1, ('k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'k10,'k11,'k12,'a) t11) t
(* --- *)

val to_array : ('k,'a) t -> 'a array
val to_keys  : ('k,'a) t -> 'k array
(* --- *)
val map_keys :  ('k1 -> 'k2) -> ('k1, 'a) t -> ('k2, 'a) t

module Example_of_Make_printers_from_lines_generator : sig
   val lines_of : ?x:'b1 -> ?y:'b2 -> 'a array -> string array
   val print    : ?out_channel:out_channel -> ?x:'b1 -> 'a array -> unit
end

(* --------------------------------------------------------------------------- *)
module As_array : sig
(* --------------------------------------------------------------------------- *)
  val init : int -> (index -> 'a) -> (index, 'a) t
  val make : int -> 'a -> (index, 'a) t
  (* --- *)
  val empty     : (index, 'a) t
  val singleton : 'a -> (index, 'a) t
end


(* --------------------------------------------------------------------------- *)
module As_vector : sig
(* --------------------------------------------------------------------------- *)

  (* ---------------------------------- *)
  module (*As_vector.*)Make_11 : sig
  (* ---------------------------------- *)
    val init : int -> (int -> 'k * 'a)  -> ('k, 'a) t
    val make : int -> 'a -> (int -> 'k) -> ('k,'a) t
    val singleton : 'k -> 'a -> ('k, 'a) t
    (* --- *)
    val of_assoc_array : ('k * 'a) array -> ('k, 'a) t
    val of_assoc_list  : ('k * 'a) list  -> ('k, 'a) t
    (* --- *)
    val dress  : ('a -> 'k) -> 'a array -> ('k, 'a) t
    val dressi : (index -> 'a -> 'k) -> 'a array -> ('k, 'a) t
    val dressg : ('s -> index -> 'a -> 'k * 's) -> 's -> 'a array -> ('k, 'a) t * 's
    (* --- *)
    val shape  : ('a -> 'k * 'b) -> 'a array -> ('k, 'b) t
    val shapei : (index -> 'a -> 'k * 'b) -> 'a array -> ('k, 'b) t
    val shapeg : ('s -> index -> 'a -> ('k * 'b) * 's) -> 's -> 'a array -> ('k, 'b) t * 's
    (* --- *)
    val to_assoc_array : ('k,'a) t -> ('k * 'a) array
    val to_assoc_list  : ('k,'a) t -> ('k * 'a) list
    (* --- *)
    (* --- *)
  end (* As_vector.Make_11 *)

  (* ---------------------------------- *)
  module (*As_vector.*)Make_1N : sig
  (* ---------------------------------- *)
    val init : int -> (int -> 'k * 'a)  -> ('k, 'a array) t
    val make : int -> 'a -> (int -> 'k) -> ('k, 'a array) t
    val singleton : 'k -> 'a -> ('k, 'a array) t
    (* --- *)
    val of_assoc_array : ('k * 'a) array -> ('k, 'a array) t
    val of_assoc_list  : ('k * 'a) list  -> ('k, 'a array) t
    (* --- *)
    val dress  : ('a -> 'k) -> 'a array -> ('k, 'a array) t
    val dressi : (index -> 'a -> 'k) -> 'a array -> ('k, 'a array) t
    val dressg : ('s -> index -> 'a -> 'k * 's) -> 's -> 'a array -> ('k, 'a array) t * 's
    (* --- *)
    val shape   : ('a -> 'k * 'b) -> 'a array -> ('k, 'b array) t
    val shapei  : (index -> 'a -> 'k * 'b) -> 'a array -> ('k, 'b array) t
    val shapeg  : ('s -> index -> 'a -> ('k * 'b) * 's) -> 's -> 'a array -> ('k, 'b array) t * 's
    (* --- *)
    val to_assoc_list  : ('k, 'a array) t -> ('k * 'a) list
    val to_assoc_array : ('k, 'a array) t -> ('k * 'a) array
    (* --- *)
  end (* As_vector.Make_1N *)

  (* --- *)
  val empty    : unit -> ('k, 'a) t
  (* --- *)
  val length   : ('a, 'b) t -> int
  val shape    : ('a, 'b) t -> int (* is length *)
  (* --- *)
  val mem      : ('k, 'a) t -> 'k -> bool
  val get      : ('k, 'a) t -> 'k -> 'a
  val get_opt  : ('k, 'a) t -> 'k -> 'a option
  (* For vectors (rank 1) prj1 is alias for get => NO NON ci sono abbastanza dimensioni per parlare di proiezioni!!!!! *)
(*  val prj1     : ('k, 'a) t -> 'k -> 'a
  val prj1_opt : ('k, 'a) t -> 'k -> 'a option*)
  (* --- *)
  (* --- *)
  (* --- *)
  (* Somma disjunta per intersezione nulla delle chiavi: *)
  val append  : ('k, 'a) t -> ('k, 'a) t -> ('k, 'a) t
  val concat  : ('k, 'a) t array -> ('k, 'a) t
  (* --- Permutations: *)
  val sort    : ?stable:unit -> ?compare:('a compare) -> ('k, 'a) t -> ('k, 'a) t
  val shuffle : ('k, 'a) t -> ('k, 'a) t
  val reverse : ('k, 'a) t -> ('k, 'a) t
  val swap    : ('k * 'k) list -> ('k, 'a) t -> ('k, 'a) t
  val permute_like : ('h, 'b) t -> ('k, 'a) t -> ('k, 'a) t
  (* --- *)
  (* `stable' forces the provided function to be called in the current order, not in the initial one. *)
  val map     : ?stable:unit ->       ('a -> 'b) -> ('k, 'a) t -> ('k, 'b) t
  val mapk    : ?stable:unit -> ('k -> 'a -> 'b) -> ('k, 'a) t -> ('k, 'b) t
  val mapg    : ?stable:unit -> ('s -> 'k -> 'a -> 'b * 's) -> 's -> ('k, 'a) t -> ('k, 'b) t * 's
  (* --- *)
  val iter    : ?stable:unit ->       ('a -> unit) -> ('k, 'a) t -> unit
  val iterk   : ?stable:unit -> ('k -> 'a -> unit) -> ('k, 'a) t -> unit
  val iterg   : ?stable:unit -> ('s -> 'k -> 'a -> 's) -> 's -> ('k, 'a) t -> 's
  val fold    : ?stable:unit -> ('s -> 'a -> 's) -> 's -> ('k, 'a) t -> 's

  (* --- Products: *)
  (* The second structure must be an *overset* of the first. The result inherits the attributes (perm, grouping) of the first argument. *)
  val combine : ('k, 'a) t -> ('k, 'b) t -> ('k, 'a * 'b) t
  val split   : ('k, 'a * 'b) t -> ('k, 'a) t * ('k, 'b) t
  (* --- Binary operators: based on `combine', all functions are implicitely stable, because elements must be taken in the same order: *)
  val map2    :  ?stable:unit -> ('a -> 'b -> 'c) -> ('k, 'a) t -> ('k, 'b) t -> ('k, 'c) t
  val mapk2   :  ?stable:unit -> ('k -> 'a -> 'b -> 'c) -> ('k, 'a) t -> ('k, 'b) t -> ('k, 'c) t

  (* --- Partitions: *)
  (* Ordinary and generalized (with keys and state) constructors: *)
  val partition  : ('a -> 'c) -> ('k, 'a) t -> ('c, 'k, 'a) t2
  val refinement : ('a -> 'c) -> ('k, 'a) t -> ('k, 'c, 'a) t2
  (* --- *)
  val group      : ('k -> 'a -> 'g) -> ('k, 'a) t -> ('g, 'k, 'a) t2
  val ungroup    : ('g, 'k, 'a) t2 -> ('k, 'a) t
  (* Aliases for group/ungroup:*)
  val nest       : ('k -> 'a -> 'g) -> ('k, 'a) t -> ('g, 'k, 'a) t2
  val unnest     : ('g, 'k, 'a) t2 -> ('k, 'a) t

  (* --- Acting on keys: *)
  (* For pairing, the structures must be of the same length. The result inherits the order of the first argument. *)
  val pairing    : ('k1, 'a) t -> ('k2, 'b) t -> ('k1 * 'k2, 'a * 'b) t
  (* --- *)
  val currying   : (('k1 * 'k2), 'a) t -> ('k1, 'k2, 'a) t2 (* = group by k1, then (map (map_keys snd)) *)
  val uncurrying : ('k1, 'k2, 'a) t2 -> (('k1 * 'k2), 'a) t (* = inject k1 at the second level, then ungroup *)

(*  val partitioni : ?outer_size:int -> ?min_outer_size:int -> (index -> 'a -> class_index) -> 'a t -> 'a tt * play
  val partitiong : ?outer_size:int -> ?min_outer_size:int -> ('s -> index -> 'a -> class_index * 's) -> 's -> 'a t -> 'a tt * play*)

  (* ---------------------------------- *)
  module (*As_vector.*)Horizontal : sig
  (* ---------------------------------- *)

    val lines_of_sparse :
      ?no_header:unit -> ?empty:string -> ?cell_size:int (* 10 *) ->
      sok:('k -> string) -> soel:('a -> string array) -> ('k, 'a option) t -> string array

    val lines_of :
      ?no_header:unit -> ?empty:string -> ?cell_size:int (* 10 *) ->
      sok:('k -> string) -> soel:('a -> string array) -> ('k, 'a) t -> string array

    val string_of_sparse :
      ?no_header:unit -> ?empty:string -> ?cell_size:int (* 10 *) ->
      sok:('k -> string) -> soel:('a -> string array) -> ('k, 'a option) t -> string

    val string_of :
      ?no_header:unit -> ?cell_size:int (* 10 *) ->
      sok:('k -> string) -> soel:('a -> string array) -> ('k, 'a) t -> string

    val print_sparse :
      ?out_channel:out_channel -> ?no_header:unit -> ?empty:string -> ?cell_size:int ->
      sok:('k -> string) -> soel:('a -> string array) -> ('k, 'a option) t -> unit

    val print :
      ?out_channel:out_channel -> ?no_header:unit -> ?cell_size:int ->
      sok:('k -> string) -> soel:('a -> string array) -> ('k, 'a) t -> unit

  end (* As_matrix.Horizontal *)

  (* ---------------------------------- *)
  module (*As_vector.*)Vertical : sig
  (* ---------------------------------- *)

    val lines_of_sparse :
      ?no_header:unit -> ?empty:string -> ?cell_size:int (* 10 *) ->
      sok:('k -> string) -> soel:('a -> string array) -> ('k, 'a option) t -> string array

    val lines_of :
      ?no_header:unit -> ?empty:string -> ?cell_size:int (* 10 *) ->
      sok:('k -> string) -> soel:('a -> string array) -> ('k, 'a) t -> string array

    val string_of_sparse :
      ?no_header:unit -> ?empty:string -> ?cell_size:int (* 10 *) ->
      sok:('k -> string) -> soel:('a -> string array) -> ('k, 'a option) t -> string

    val string_of :
      ?no_header:unit -> ?cell_size:int (* 10 *) ->
      sok:('k -> string) -> soel:('a -> string array) -> ('k, 'a) t -> string

    val print_sparse :
      ?out_channel:out_channel -> ?no_header:unit -> ?empty:string -> ?cell_size:int ->
      sok:('k -> string) -> soel:('a -> string array) -> ('k, 'a option) t -> unit

    val print :
      ?out_channel:out_channel -> ?no_header:unit -> ?cell_size:int ->
      sok:('k -> string) -> soel:('a -> string array) -> ('k, 'a) t -> unit

  end (* As_matrix.Vertical *)


end


(* --------------------------------------------------------------------------- *)
module As_matrix : sig
(* --------------------------------------------------------------------------- *)

  (* NOTE: 11 refers to the last key, because the previous one are obviously 1N *)
  (* ---------------------------------- *)
  module (*As_matrix.*)Make_11 : sig
  (* ---------------------------------- *)
    val init : int -> (int -> 'k1 * ('k2 * 'a))  -> ('k1, 'k2, 'a) t2
    val make : int -> ('k2 * 'a) -> (int -> 'k1) -> ('k1, 'k2, 'a) t2
    val singleton : 'k1 -> ('k2 * 'a) -> ('k1, 'k2, 'a) t2
    (* --- *)
    val of_assoc_array : ('k1 * ('k2 * 'a)) array -> ('k1, 'k2, 'a) t2
    val of_assoc_list  : ('k1 * ('k2 * 'a)) list  -> ('k1, 'k2, 'a) t2
    (* --- *)
    val dress  : ('a -> 'k1 * 'k2) -> 'a array -> ('k1, 'k2, 'a) t2
    val dressi : (index -> 'a -> 'k1 * 'k2) -> 'a array -> ('k1, 'k2, 'a) t2
    val dressg : ('s -> index -> 'a -> ('k1 * 'k2) * 's) -> 's -> 'a array -> ('k1, 'k2, 'a) t2 * 's
    (* --- *)
    val shape  : ('a -> 'k1 * ('k2 * 'b)) -> 'a array -> ('k1, 'k2, 'b) t2
    val shapei : (index -> 'a -> 'k1 * ('k2 * 'b)) -> 'a array -> ('k1, 'k2, 'b) t2
    val shapeg : ('s -> index -> 'a -> ('k1 * ('k2 * 'b)) * 's) -> 's -> 'a array -> ('k1, 'k2, 'b) t2 * 's
    (* --- *)
    val to_assoc_array : ('k1,'k2, 'a) t2 -> ('k1 * ('k2 * 'a)) array
    val to_assoc_list  : ('k1,'k2, 'a) t2 -> ('k1 * ('k2 * 'a)) list
    (* --- *)
  end (* As_matrix.Make_11 *)

  (* ---------------------------------- *)
  module (*As_matrix.*)Make_1N : sig
  (* ---------------------------------- *)
    val init : int -> (int -> 'k1 * ('k2 * 'a))  -> ('k1, 'k2, 'a array) t2
    val make : int -> ('k2 * 'a) -> (int -> 'k1) -> ('k1, 'k2, 'a array) t2
    val singleton : 'k1 -> ('k2 * 'a) -> ('k1, 'k2, 'a array) t2
    (* --- *)
    val of_assoc_array : ('k1 * ('k2 * 'a)) array -> ('k1, 'k2, 'a array) t2
    val of_assoc_list  : ('k1 * ('k2 * 'a)) list  -> ('k1, 'k2, 'a array) t2
    (* --- *)
    val dress  : ('a -> 'k1 * 'k2) -> 'a array -> ('k1, 'k2, 'a array) t2
    val dressi : (index -> 'a -> 'k1 * 'k2) -> 'a array -> ('k1, 'k2, 'a array) t2
    val dressg : ('s -> index -> 'a -> ('k1 * 'k2) * 's) -> 's -> 'a array -> ('k1, 'k2, 'a array) t2 * 's
    (* --- *)
    val shape  : ('a -> 'k1 * ('k2 * 'b)) -> 'a array -> ('k1, 'k2, 'b array) t2
    val shapei : (index -> 'a -> 'k1 * ('k2 * 'b)) -> 'a array -> ('k1, 'k2, 'b array) t2
    val shapeg : ('s -> index -> 'a -> ('k1 * ('k2 * 'b)) * 's) -> 's -> 'a array -> ('k1, 'k2, 'b array) t2 * 's
    (* --- *)
    val to_assoc_array : ('k1,'k2, 'a array) t2 -> ('k1 * ('k2 * 'a)) array
    val to_assoc_list  : ('k1,'k2, 'a array) t2 -> ('k1 * ('k2 * 'a)) list
    (* --- *)
  end (* As_matrix.Make_1N *)


(*(*(*(*(*(*
  (* --- *)
  val init_sparse  : int -> (int -> ('k1 * 'k2) * 'a)  -> ('k1, 'k2, 'a) t2
  val init_uniform : int -> int -> (index -> index -> ('k1 * 'k2) * 'a)  -> ('k1, 'k2, 'a) t2

  val init_uniform : 'k1 array -> 'k2 array -> ('k1 -> 'k2 -> 'a) -> ('k1, 'k2, 'a) t2
  val regular      : 'k1 array -> 'k2 array -> ('k1 -> 'k2 -> 'a) -> ('k1, 'k2, 'a) t2   <= dentro i Make_11

  (* --- *)

  val assoc_array_factorize : ('k1 * ('k2 * 'a)) array -> ('k1 * (('k2 * 'a) array)) array

  *)*)*)*)*)*)

  (* --- *)
  val get     : ('k1, 'k2, 'a) t2 -> 'k1 -> 'k2 -> 'a
  val get_opt : ('k1, 'k2, 'a) t2 -> 'k1 -> 'k2 -> 'a option
  (* --- *)
  val map     : ?stable:unit ->               ('a -> 'b) -> ('k1, 'k2, 'a) t2 -> ('k1, 'k2, 'b) t2
  val mapk    : ?stable:unit -> ('k1 -> 'k2 -> 'a -> 'b) -> ('k1, 'k2, 'a) t2 -> ('k1, 'k2, 'b) t2
  val mapg    : ?stable:unit -> ('s -> 'k1 -> 'k2 -> 'a -> 'b * 's) -> 's -> ('k1, 'k2, 'a) t2 -> ('k1, 'k2, 'b) t2 * 's
  (* --- *)
  val iter    : ?stable:unit ->               ('a -> unit) -> ('k1, 'k2, 'a) t2 -> unit
  val iterk   : ?stable:unit -> ('k1 -> 'k2 -> 'a -> unit) -> ('k1, 'k2, 'a) t2 -> unit
  val iterg   : ?stable:unit -> ('s -> 'k1 -> 'k2 -> 'a -> 's) -> 's -> ('k1, 'k2, 'a) t2 -> 's
  (* --- *)
  val transpose : ('k1, 'k2, 'a) t2 -> ('k2, 'k1, 'a) t2

  val to_string_matrix :
    ?empty:string -> ?cell_size:int ->
    sok1:('k1 -> string) -> sok2:('k2 -> string) -> soel:('a -> string) -> ('k1, 'k2, 'a) t2 -> string array array

  val print :
    ?out_channel:out_channel ->
    ?empty:string -> ?cell_size:int ->
    sok1:('k1 -> string) -> sok2:('k2 -> string) -> soel:('a -> string) -> ('k1, 'k2, 'a) t2 -> unit

  (* ---------------------------------- *)
  module (*As_matrix.*)Horizontal : sig
  (* ---------------------------------- *)

    val lines_of_sparse :
      ?no_header1:unit -> ?empty1:string -> ?cell_size1:int ->
      ?no_header2:unit -> ?empty2:string -> ?cell_size2:int ->
      sok1:('k1 -> string) ->
      sok2:('k2 -> string) ->
      soel:('a -> string array) ->
      ('k1, 'k2, 'a option) t2 -> string array

    val string_of_sparse :
      ?no_header1:unit -> ?empty1:string -> ?cell_size1:int ->
      ?no_header2:unit -> ?empty2:string -> ?cell_size2:int ->
      sok1:('k1 -> string) ->
      sok2:('k2 -> string) ->
      soel:('a -> string array) ->
      ('k1, 'k2, 'a option) t2 -> string

    val string_of :
      ?no_header1:unit -> ?cell_size1:int ->
      ?no_header2:unit -> ?cell_size2:int ->
      sok1:('k1 -> string) ->
      sok2:('k2 -> string) ->
      soel:('a -> string array) ->
      ('k1, 'k2, 'a) t2 -> string

    val print_sparse :
      ?out_channel:out_channel ->
      ?no_header1:unit -> ?empty1:string -> ?cell_size1:int ->
      ?no_header2:unit -> ?empty2:string -> ?cell_size2:int ->
      sok1:('k1 -> string) ->
      sok2:('k2 -> string) ->
      soel:('a -> string array) ->
      ('k1, 'k2, 'a option) t2 -> unit

    val print :
      ?out_channel:out_channel ->
      ?no_header1:unit -> ?cell_size1:int ->
      ?no_header2:unit -> ?cell_size2:int ->
      sok1:('k1 -> string) ->
      sok2:('k2 -> string) ->
      soel:('a -> string array) ->
      ('k1, 'k2, 'a) t2 -> unit

  end (* As_matrix.Horizontal *)

  (* ---------------------------------- *)
  module (*As_matrix.*)Vertical : sig
  (* ---------------------------------- *)

    val lines_of_sparse :
      ?no_header1:unit -> ?empty1:string -> ?cell_size1:int ->
      ?no_header2:unit -> ?empty2:string -> ?cell_size2:int ->
      sok1:('k1 -> string) ->
      sok2:('k2 -> string) ->
      soel:('a -> string array) ->
      ('k1, 'k2, 'a option) t2 -> string array

    val string_of_sparse :
      ?no_header1:unit -> ?empty1:string -> ?cell_size1:int ->
      ?no_header2:unit -> ?empty2:string -> ?cell_size2:int ->
      sok1:('k1 -> string) ->
      sok2:('k2 -> string) ->
      soel:('a -> string array) ->
      ('k1, 'k2, 'a option) t2 -> string

    val string_of :
      ?no_header1:unit -> ?cell_size1:int ->
      ?no_header2:unit -> ?cell_size2:int ->
      sok1:('k1 -> string) ->
      sok2:('k2 -> string) ->
      soel:('a -> string array) ->
      ('k1, 'k2, 'a) t2 -> string

    val print_sparse :
      ?out_channel:out_channel ->
      ?no_header1:unit -> ?empty1:string -> ?cell_size1:int ->
      ?no_header2:unit -> ?empty2:string -> ?cell_size2:int ->
      sok1:('k1 -> string) ->
      sok2:('k2 -> string) ->
      soel:('a -> string array) ->
      ('k1, 'k2, 'a option) t2 -> unit

    val print :
      ?out_channel:out_channel ->
      ?no_header1:unit -> ?cell_size1:int ->
      ?no_header2:unit -> ?cell_size2:int ->
      sok1:('k1 -> string) ->
      sok2:('k2 -> string) ->
      soel:('a -> string array) ->
      ('k1, 'k2, 'a) t2 -> unit

  end (* As_matrix.Vertical *)

(*(*(*(*(*
  val partition  : ('a -> 'c) -> ('k1, 'k2, 'a) t2 -> ('c, 'k1, 'k2, 'a) t3
  val refinement : ('a -> 'c) -> ('k1, 'k2, 'a) t2 -> ('k1, 'k2, 'c, 'a) t3*)*)*)*)*)

  (* --- *)
(*  val append  : ('k, 'a) t -> ('k, 'a) t -> ('k, 'a) t
  (* --- Permutations: *)
  val sort    : ?stable:unit -> ?compare:('a compare) -> ('k, 'a) t -> ('k, 'a) t
  val shuffle : ('k, 'a) t -> ('k, 'a) t
  val reverse : ('k, 'a) t -> ('k, 'a) t
  val swap    : ('k * 'k) list -> ('k, 'a) t -> ('k, 'a) t
  (* --- *)
  (* `stable' forces the provided function to be called in the current order, not in the initial one. *)
  val map     : ?stable:unit ->       ('a -> 'b) -> ('k, 'a) t -> ('k, 'b) t
  val mapk    : ?stable:unit -> ('k -> 'a -> 'b) -> ('k, 'a) t -> ('k, 'b) t
  (* --- Partitions: *)
  (* Ordinary and generalized (with keys and state) constructors: *)
  val partition  : ('a -> 'c) -> ('k, 'a) t -> ('c, 'k, 'a) tt
  val refinement : ('a -> 'c) -> ('k, 'a) t -> ('k, 'c, 'a) tt *)

(*  val partitioni : ?outer_size:int -> ?min_outer_size:int -> (index -> 'a -> class_index) -> 'a t -> 'a tt * play
  val partitiong : ?outer_size:int -> ?min_outer_size:int -> ('s -> index -> 'a -> class_index * 's) -> 's -> 'a t -> 'a tt * play*)

end


(* open Atens;; include Testing;; *)
module Testing : sig
    val x1  : (int, char) t
    val x2  : (int, char) t
    val x1' : (int, char) t
    val x2' : (int, char) t
    (* --- *)
    val y1  : (int, char) t
    val y2  : (int, char) t
    val y3  : (int, char) t
    val y4  : (int, char) t
end


