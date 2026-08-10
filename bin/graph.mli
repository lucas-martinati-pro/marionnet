(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008  Luca Saiu
   Copyright (C) 2007, 2008  Université Paris 13

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

(* A general-purpose polymorphic DIRECTED graph, imperative (every operation mutates in
   place and returns [unit], except the accessors).
   ---
   Its only client is `task_runner.ml' (which `open's this module) to schedule tasks under a
   dependency relation: an edge a |-> b reads "a depends on b", so `topological_sort' returns
   b before a.
   ---
   NOT thread-safe: no lock anywhere. `task_runner' calls it from its own worker only. *)

(** Node identifier, handed out by [add_node]. Ids are drawn from a SINGLE process-wide
    counter, hence unique across graphs, never recycled, and never reused after
    [remove_node] — an id kept by a caller can therefore only become dangling, never
    silently designate another node. *)
type id = int

(** A graph holding nodes of type ['a]. Abstract: build it with [make_empty_graph]. *)
type 'a graph

val make_empty_graph : unit -> 'a graph

(** Add a node and return its fresh id. Nodes are not compared: adding the same value twice
    yields two distinct nodes. *)
val add_node : 'a -> 'a graph -> id

(** @raise Not_found if the id is unknown (removed, or belonging to another graph). *)
val get_node : id -> 'a graph -> 'a

(** All the node ids, in unspecified order. *)
val get_node_ids : 'a graph -> id list

(** Add the edge [source |-> destination]. Idempotent: a duplicate edge is not inserted, so
    the structure is a set of pairs, not a multigraph. The endpoints are NOT checked for
    existence. *)
val add_edge : id -> id -> 'a graph -> unit

val has_edge : id -> id -> 'a graph -> bool

(** Successors of a node, i.e. the destinations of its outgoing edges. *)
val get_forward_star : id -> 'a graph -> id list

(** Predecessors of a node, i.e. the sources of its incoming edges. *)
val get_backward_star : id -> 'a graph -> id list

(** All the edges as [(source, destination)] pairs, in unspecified order. *)
val get_forward_edges : 'a graph -> (id * id) list

(** The same edges REVERSED, i.e. as [(destination, source)] pairs. *)
val get_backward_edges : 'a graph -> (id * id) list

(** Remove that one edge if it exists, otherwise do nothing. Removes no node. *)
val remove_edge : id -> id -> 'a graph -> unit

(** Remove the node together with every edge touching it; do nothing if the id is unknown. *)
val remove_node : id -> 'a graph -> unit

(** Empty the graph, keeping it usable. *)
val clear : 'a graph -> unit

(** Some topological order of the nodes: if [a |-> b] is an edge then [b] precedes [a] in the
    result. Works on a disconnected graph, every node being returned exactly once.
    ⚠️ The traversal starts from the nodes with an EMPTY backward star, so on a CYCLIC graph
    the result is not merely "undefined": the nodes of a cycle, having no source among their
    ancestors, are simply MISSING from the returned list. *)
val topological_sort : 'a graph -> id list

(** Dump nodes and edges on stdout, using the given printer for a node. Debugging aid. *)
val print_graph : ('a -> unit) -> 'a graph -> unit
