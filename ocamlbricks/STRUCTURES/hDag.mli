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

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

(* A vertex may be terminal in two distinct senses:
   (1) because it's a leaf with its associate information ('t)
   (2) because it's a node with its associate information ('n) but without children.
   # ---
   A simple example of this situation is a filesystem, where (1) are files and (2)
   are empty directories.
   # ---
   The starting point may be a vertex, an edge, a comb (forest) or a link.
   *)
type ('n,'e,'l,'t) vertex = Node   of 'n * ('n,'e,'l,'t) switch | Leaf of 't
 and ('n,'e,'l,'t) switch = Switch of ('n,'e,'l,'t) edge array
 and ('n,'e,'l,'t) edge   = Edge   of 'e * ('n,'e,'l,'t) comb
 and ('n,'e,'l,'t) comb   = Comb   of ('n,'e,'l,'t) link array
 and ('n,'e,'l,'t) link   = Link   of 'l * ('n,'e,'l,'t) vertex

(* May be the most natural starting point: *)
type ('n,'e,'l,'t) forest = ('n,'e,'l,'t) switch

type switch_port_index = int
 and comb_port_index   = int
 and index             = int
 and dir               = switch_port_index * comb_port_index
 and address           = dir list
 and low_level_address = index list
 and lladdress         = low_level_address

(* Basic constructors: *)
val leaf   : 't -> ('n,'e,'l,'t) vertex
val node   : 'n -> ('n,'e,'l,'t) switch -> ('n,'e,'l,'t) vertex
val switch : ('n,'e,'l,'t) edge array   -> ('n,'e,'l,'t) switch
val edge   : 'e -> ('n,'e,'l,'t) comb   -> ('n,'e,'l,'t) edge
val comb   : ('n,'e,'l,'t) link array   -> ('n,'e,'l,'t) comb
val link   : 'l -> ('n,'e,'l,'t) vertex -> ('n,'e,'l,'t) link
(* --- *)
val empty  : unit -> ('n,'e,'l,'t) comb (* empty stands for Comb.empty *)

(* Visiting the structure, it's possible to reach several time the same point,
   that we call "repetead positions". A repeated position may be associated to
   a value, that should be the result of visit calculated the first time: *)
type 'a repeated = 'a option

(* Alias for Get_vertex.from_vertex: *)
val get_vertex : ('n,'e,'l,'t) vertex -> address -> ('n,'e,'l,'t) vertex

(** Structured address-based accessors to vertices: *)
module Get_vertex :
  sig
    type dir = switch_port_index * comb_port_index
    type address = dir list
    (* --- *)
    val from_vertex : ('n,'e,'l,'t) vertex -> address -> ('n,'e,'l,'t) vertex
    val from_switch : ('n,'e,'l,'t) switch -> dir -> address -> ('n,'e,'l,'t) vertex
    val from_edge   : ('n,'e,'l,'t) edge   -> comb_port_index -> address -> ('n,'e,'l,'t) vertex
    val from_comb   : ('n,'e,'l,'t) comb   -> comb_port_index -> address -> ('n,'e,'l,'t) vertex
    val from_link   : ('n,'e,'l,'t) link   -> address -> ('n,'e,'l,'t) vertex
  end

(** Structured address-based accessors to switches: *)
module Get_switch :
  sig
    type dir = switch_port_index * comb_port_index
    type address = dir list
    (* --- *)
    val from_switch : ('n,'e,'l,'t) switch -> address -> ('n,'e,'l,'t) switch
    val from_edge   : ('n,'e,'l,'t) edge   -> comb_port_index -> address -> ('n,'e,'l,'t) switch
    val from_comb   : ('n,'e,'l,'t) comb   -> comb_port_index -> address -> ('n,'e,'l,'t) switch
    val from_link   : ('n,'e,'l,'t) link   -> address -> ('n,'e,'l,'t) switch
    val from_vertex : ('n,'e,'l,'t) vertex -> address -> ('n,'e,'l,'t) switch
  end

(** Structured address-based accessors to edges: *)
module Get_edge :
  sig
    type dir = comb_port_index * switch_port_index
    type address = dir list
    (* --- *)
    val from_edge   : ('n,'e,'l,'t) edge   -> address -> ('n,'e,'l,'t) edge
    val from_comb   : ('n,'e,'l,'t) comb   -> dir -> address -> ('n,'e,'l,'t) edge
    val from_link   : ('n,'e,'l,'t) link   -> switch_port_index -> address -> ('n,'e,'l,'t) edge
    val from_vertex : ('n,'e,'l,'t) vertex -> switch_port_index -> address -> ('n,'e,'l,'t) edge
    val from_switch : ('n,'e,'l,'t) switch -> switch_port_index -> address -> ('n,'e,'l,'t) edge
  end

(** Structured address-based accessors to combs: *)
module Get_comb :
  sig
    type dir = comb_port_index * switch_port_index
    type address = dir list
    val from_comb   : ('n,'e,'l,'t) comb   -> address -> ('n,'e,'l,'t) comb
    val from_link   : ('n,'e,'l,'t) link   -> switch_port_index -> address -> ('n,'e,'l,'t) comb
    val from_vertex : ('n,'e,'l,'t) vertex -> switch_port_index -> address -> ('n,'e,'l,'t) comb
    val from_switch : ('n,'e,'l,'t) switch -> switch_port_index -> address -> ('n,'e,'l,'t) comb
    val from_edge   : ('n,'e,'l,'t) edge   -> address -> ('n,'e,'l,'t) comb
  end

(** Structured address-based accessors to links: *)
module Get_link :
  sig
    type dir = switch_port_index * comb_port_index
    type address = dir list
    val from_link   : ('n,'e,'l,'t) link   -> address -> ('n,'e,'l,'t) link
    val from_vertex : ('n,'e,'l,'t) vertex -> dir -> address -> ('n,'e,'l,'t) link
    val from_switch : ('n,'e,'l,'t) switch -> dir -> address -> ('n,'e,'l,'t) link
    val from_edge   : ('n,'e,'l,'t) edge   -> comb_port_index -> address -> ('n,'e,'l,'t) link
    val from_comb   : ('n,'e,'l,'t) comb   -> comb_port_index -> address -> ('n,'e,'l,'t) link
  end


module Link :
  sig
    val get_label  : ('n,'e,'l,'t) link -> 'l
    val get_vertex : ('n,'e,'l,'t) link -> ('n,'e,'l,'t) vertex
  end

module Comb :
  sig

    val empty : unit -> ('n,'e,'l,'t) comb

    val plug_links : ?insert:comb_port_index -> links:('n,'e,'l,'t) link array -> ('n,'e,'l,'t) comb -> ('n,'e,'l,'t) comb
    val plug_link  : ?insert:comb_port_index -> link:('n,'e,'l,'t) link -> ('n,'e,'l,'t) comb -> ('n,'e,'l,'t) comb

    val plug_vertices :
      ?insert:comb_port_index ->
      labels:'l array ->
      targets:('n,'e,'l,'t) vertex array ->
      ('n,'e,'l,'t) comb -> ('n,'e,'l,'t) comb

    val plug_vertex :
      ?insert:comb_port_index ->
      label:'l ->
      target:('n,'e,'l,'t) vertex ->
      ('n,'e,'l,'t) comb -> ('n,'e,'l,'t) comb
  end

module Edge :
  sig

    val empty : 'e -> ('n,'e,'l,'t) edge

    val get_label : ('n,'e,'l,'t) edge -> 'e
    val get_comb  : ('n,'e,'l,'t) edge -> ('n,'e,'l,'t) comb

    val plug_vertices :
      ?insert:comb_port_index ->
      labels:'l array ->
      targets:('n,'e,'l,'t) vertex array ->
      ('n,'e,'l,'t) edge -> ('n,'e,'l,'t) edge

    val plug_vertex :
      ?insert:comb_port_index ->
      label:'l ->
      target:('n,'e,'l,'t) vertex ->
      ('n,'e,'l,'t) edge -> ('n,'e,'l,'t) edge
  end

module Switch :
  sig

    val empty : unit -> ('n,'e,'l,'t) switch

    val plug_edges :
      ?insert:switch_port_index ->
      edges:('n,'e,'l,'t) edge array ->
      ('n,'e,'l,'t) switch -> ('n,'e,'l,'t) switch

    val plug_edge :
      ?insert:switch_port_index ->
      edge:('n,'e,'l,'t) edge ->
      ('n,'e,'l,'t) switch -> ('n,'e,'l,'t) switch

  end

module Vertex :
  sig

    val empty_node : 'n -> ('n,'e,'l,'t) vertex

    val plug_edges :
      ?insert:switch_port_index ->
      edges:('n,'e,'l,'t) edge array ->
      ('n,'e,'l,'t) vertex -> ('n,'e,'l,'t) vertex

    val plug_edge :
      ?insert:switch_port_index ->
      edge:('n,'e,'l,'t) edge ->
      ('n,'e,'l,'t) vertex -> ('n,'e,'l,'t) vertex

    val append_children_on_port :
      ?switch_port:index (* 0 *) ->
      ?comb_port:index   (* None (=> append) *) ->
      llabels:'l array ->
      targets:('n,'e,'l,'t) vertex array ->
      ('n,'e,'l,'t) vertex -> ('n,'e,'l,'t) vertex

    val append_child_on_port :
      ?switch_port:index (* 0 *) ->
      ?comb_port:index   (* None (=> append) *) ->
      llabel:'l ->
      target:('n,'e,'l,'t) vertex ->
      ('n,'e,'l,'t) vertex -> ('n,'e,'l,'t) vertex

    val append_children_on_a_single_edge :
      ?insert:switch_port_index ->
      elabel:'e ->
      llabels:'l array ->
      targets:('n,'e,'l,'t) vertex array ->
      ('n,'e,'l,'t) vertex -> ('n,'e,'l,'t) vertex

    val append_children_on_several_edges :
      ?insert:switch_port_index ->
      elabels:'e array ->
      llabels:'l array ->
      targets:('n,'e,'l,'t) vertex array ->
      ('n,'e,'l,'t) vertex -> ('n,'e,'l,'t) vertex

    val append_child :
      ?insert:switch_port_index ->
      elabel:'e ->
      llabel:'l ->
      target:('n,'e,'l,'t) vertex ->
      ('n,'e,'l,'t) vertex -> ('n,'e,'l,'t) vertex

  end

(* Bottom-up evaluation, managing repetead positions.
   In other words, we are in a post-order traversal setting,
   where each elements is processed after all its descendent. *)
module BotUpEval :
  sig

    type ('vertex, 'switch, 'edge, 'comb, 'link, 'n0,'e0,'l0,'t0, 'n1,'e1,'l1,'t1, 'a, 'b) morphism =
      (* --- *)
      vertex:('vertex repeated -> 'vertex lazy_t -> 'vertex) ->
      (* --- *)
      node:  ('n1 -> 'switch -> 'vertex) ->
      leaf:  ('t1 -> 'vertex) ->
      (* --- *)
      switch:('switch repeated -> 'edge array lazy_t     -> 'switch) ->
      edge:  ('edge repeated   -> ('e1 * 'comb) lazy_t   -> 'edge)   ->
      comb:  ('comb repeated   -> 'link array lazy_t     -> 'comb)   ->
      link:  ('link repeated   -> ('l1 * 'vertex) lazy_t -> 'link)   ->
      (* --- *)
      n:('n0 -> 'n1) -> e:('e0 -> 'e1) -> l:('l0 -> 'l1) -> t:('t0 -> 't1) ->
      (* --- *)
      'a -> 'b

    val from_vertex : ('vertex, 'switch, 'edge, 'comb, 'link, 'n0,'e0,'l0,'t0, 'n1,'e1,'l1,'t1, ('n0,'e0,'l0,'t0) vertex, 'vertex) morphism
    val from_switch : ('vertex, 'switch, 'edge, 'comb, 'link, 'n0,'e0,'l0,'t0, 'n1,'e1,'l1,'t1, ('n0,'e0,'l0,'t0) switch, 'switch) morphism
    val from_edge   : ('vertex, 'switch, 'edge, 'comb, 'link, 'n0,'e0,'l0,'t0, 'n1,'e1,'l1,'t1, ('n0,'e0,'l0,'t0) edge,   'edge)   morphism
    val from_comb   : ('vertex, 'switch, 'edge, 'comb, 'link, 'n0,'e0,'l0,'t0, 'n1,'e1,'l1,'t1, ('n0,'e0,'l0,'t0) comb,   'comb)   morphism
    val from_link   : ('vertex, 'switch, 'edge, 'comb, 'link, 'n0,'e0,'l0,'t0, 'n1,'e1,'l1,'t1, ('n0,'e0,'l0,'t0) link,   'link)   morphism

end

(* Bottom-up evaluation, managing repetead positions, when the type of the structure remains the same. *)
module BotUpEndoEval :
  sig

    (* --- Forgetting the fact that some arguments are now optional, we have:

    type ('n,'e,'l,'t, 'a) morphism =
      (('n,'e,'l,'t) vertex, ('n,'e,'l,'t) switch, ('n,'e,'l,'t) edge, ('n,'e,'l,'t) comb, ('n,'e,'l,'t) link, 'n, 'e, 'l, 't,  'a, 'a) Eval.morphism

      *)

    type ('n,'e,'l,'t, 'a) morphism =
      (* --- *)
      ?vertex:(('n,'e,'l,'t) vertex repeated -> ('n,'e,'l,'t) vertex lazy_t -> ('n,'e,'l,'t) vertex) ->
      (* --- *)
      ?node:  ('n -> ('n,'e,'l,'t) switch -> ('n,'e,'l,'t) vertex) ->
      ?leaf:  ('t -> ('n,'e,'l,'t) vertex) ->
      (* --- *)
      ?switch:(('n,'e,'l,'t) switch repeated -> ('n,'e,'l,'t) edge array lazy_t    -> ('n,'e,'l,'t) switch) ->
      ?edge:  (('n,'e,'l,'t) edge repeated   -> ('e * ('n,'e,'l,'t) comb) lazy_t   -> ('n,'e,'l,'t) edge)   ->
      ?comb:  (('n,'e,'l,'t) comb repeated   -> ('n,'e,'l,'t) link array lazy_t    -> ('n,'e,'l,'t) comb)   ->
      ?link:  (('n,'e,'l,'t) link repeated   -> ('l * ('n,'e,'l,'t) vertex) lazy_t -> ('n,'e,'l,'t) link)   ->
      (* --- *)
      ?n:('n -> 'n) -> ?e:('e -> 'e) -> ?l:('l -> 'l) -> ?t:('t -> 't) ->
      (* --- *)
      'a -> 'a

    val from_vertex : ('n,'e,'l,'t, ('n,'e,'l,'t) vertex ) morphism
    val from_switch : ('n,'e,'l,'t, ('n,'e,'l,'t) switch ) morphism
    val from_edge   : ('n,'e,'l,'t, ('n,'e,'l,'t) edge   ) morphism
    val from_comb   : ('n,'e,'l,'t, ('n,'e,'l,'t) comb   ) morphism
    val from_link   : ('n,'e,'l,'t, ('n,'e,'l,'t) link   ) morphism

  end (* BotUpEndoEval *)

(* Bottom-up evaluation, managing repeated positions, when the structure remains exactly the same, but data
   associated to nodes, edges, links, and leafs, may change their value and type. *)
module Map :
  sig

    (* Just for info: *)
    type ('n0,'e0,'l0,'t0, 'n1,'e1,'l1,'t1, 'a, 'b) morphism =
      n:('n0 -> 'n1) -> e:('e0 -> 'e1) -> l:('l0 -> 'l1) -> t:('t0 -> 't1) ->  'a -> 'b

    val from_vertex : n:('n0->'n1) -> e:('e0->'e1) -> l:('l0->'l1) -> t:('t0->'t1) -> ('n0,'e0,'l0,'t0) vertex -> ('n1, 'e1, 'l1, 't1) vertex
    val from_switch : n:('n0->'n1) -> e:('e0->'e1) -> l:('l0->'l1) -> t:('t0->'t1) -> ('n0,'e0,'l0,'t0) switch -> ('n1, 'e1, 'l1, 't1) switch
    val from_edge   : n:('n0->'n1) -> e:('e0->'e1) -> l:('l0->'l1) -> t:('t0->'t1) -> ('n0,'e0,'l0,'t0) edge   -> ('n1, 'e1, 'l1, 't1) edge
    val from_comb   : n:('n0->'n1) -> e:('e0->'e1) -> l:('l0->'l1) -> t:('t0->'t1) -> ('n0,'e0,'l0,'t0) comb   -> ('n1, 'e1, 'l1, 't1) comb
    val from_link   : n:('n0->'n1) -> e:('e0->'e1) -> l:('l0->'l1) -> t:('t0->'t1) -> ('n0,'e0,'l0,'t0) link   -> ('n1, 'e1, 'l1, 't1) link
    val from_forest : n:('n0->'n1) -> e:('e0->'e1) -> l:('l0->'l1) -> t:('t0->'t1) -> ('n0,'e0,'l0,'t0) forest -> ('n1, 'e1, 'l1, 't1) forest
  end

(* Bottom-up evaluation, managing repeated positions, when the structure remains exactly the same, but data
   associated to nodes, edges, links, and leafs, may change their value and type. *)
module Iter :
  sig

    (* Just for info: *)
    type ('n,'e,'l,'t, 'a) morphism =
      ?n:('n -> unit) -> ?e:('e -> unit) -> ?l:('l -> unit) -> ?t:('t -> unit) ->  'a -> unit

    val from_vertex : ?n:('n->unit) -> ?e:('e->unit) -> ?l:('l->unit) -> ?t:('t->unit) -> ('n,'e,'l,'t) vertex -> unit
    val from_switch : ?n:('n->unit) -> ?e:('e->unit) -> ?l:('l->unit) -> ?t:('t->unit) -> ('n,'e,'l,'t) switch -> unit
    val from_edge   : ?n:('n->unit) -> ?e:('e->unit) -> ?l:('l->unit) -> ?t:('t->unit) -> ('n,'e,'l,'t) edge   -> unit
    val from_comb   : ?n:('n->unit) -> ?e:('e->unit) -> ?l:('l->unit) -> ?t:('t->unit) -> ('n,'e,'l,'t) comb   -> unit
    val from_link   : ?n:('n->unit) -> ?e:('e->unit) -> ?l:('l->unit) -> ?t:('t->unit) -> ('n,'e,'l,'t) link   -> unit
    val from_forest : ?n:('n->unit) -> ?e:('e->unit) -> ?l:('l->unit) -> ?t:('t->unit) -> ('n,'e,'l,'t) switch -> unit
  end

(* Count distinct elements in a bottom-up evaluation, managing repeated positions. *)
module Count :
  sig
    type result = < vertices:int; nodes:int; leafs:int; switches:int; edges:int; combs: int; links:int; to_list:(string*int) list;  >
    (* --- *)
    val from_vertex : ('n,'e,'l,'t) vertex -> result
    val from_switch : ('n,'e,'l,'t) switch -> result
    val from_edge   : ('n,'e,'l,'t) edge   -> result
    val from_comb   : ('n,'e,'l,'t) comb   -> result
    val from_link   : ('n,'e,'l,'t) link   -> result
    val from_forest : ('n,'e,'l,'t) switch -> result
  end

(* Checking ubiquity (number of occurrences of shared elements) in a bottom-up evaluation, managing repeated positions. *)
module Ubiquity :
  sig
    (* result#answer is the answer of the question "Is there ubiquity, i.e. sharing?": *)
    type result = < vertices:int; nodes:int; leafs:int; switches:int; edges:int; combs: int; links:int; to_list:(string*int) list; answer:bool;  >
    (* --- *)
    val from_vertex : ('n,'e,'l,'t) vertex -> result
    val from_switch : ('n,'e,'l,'t) switch -> result
    val from_edge   : ('n,'e,'l,'t) edge   -> result
    val from_comb   : ('n,'e,'l,'t) comb   -> result
    val from_link   : ('n,'e,'l,'t) link   -> result
    val from_forest : ('n,'e,'l,'t) switch -> result
  end

(* Number of vertex of the longest path. *)
module Height :
  sig
    (* --- *)
    type result = < vertices:int; nodes:int; leafs:int; switches:int; edges:int; combs: int; links:int; to_list:(string*int) list;  >
    (* --- *)
    val from_vertex : ('n,'e,'l,'t) vertex -> result
    val from_switch : ('n,'e,'l,'t) switch -> result
    val from_edge   : ('n,'e,'l,'t) edge   -> result
    val from_comb   : ('n,'e,'l,'t) comb   -> result
    val from_link   : ('n,'e,'l,'t) link   -> result
    val from_forest : ('n,'e,'l,'t) switch -> result
  end
