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

(* # --- Comments --- #

   Def. The "switch-size" is its array length, the "comb-size" is its array length.
   ---
   Notation: 1 stands for the `unit' (data-less) type
   ---
   An ('a list) may be encoded as a:
     ('a, 1, 1, 1) switch, or
     ( 1,'a, 1, 1) switch, or
     ( 1, 1,'a, 1) switch
     which means that we can store the informations equivalently on nodes, edges or links,
     where:
     - all reachable switches are {0,1}-size (0=>Nil, 1=>Cons) ("hypo-switching" or "{0,1}-way-switching")
     - all reachable combs are exactly 1-size ("1-way-combing")
     - there are no reachable leafs in the structure, but only nodes without children
   ---
   An ('a array) may be encoded as a:
     (1,'a, 1, 1) switch of arbitrary length (i.e. a forest)
     where:
     - all reachable combs are exactly 0-size (empties); in other words, all edges are "broken" or "semi-edges".
     - there are no reachable vertex neither links
   ---
   A structure is "hypo-switching" when all reachable switches are {0,1}-size (like for lists).
   A structure is "hypo-combing"   when all reachable combs are {0,1}-size.
   ---
   A ('a,'b,'c) "DAG-structure" (vertex, switch, edge, comb or link) may be encoded as a:
     ('a,'b, 1,'c) "1-way-combing" structure (no broken edges), or
     ('a, 1,'b,'c) "hypo-switching" structure (no more than one edge, divided in several links)
   The first encoding seems to be more intuitive.
   ---
   An (('a tensor), i.e. an array of arrays (or tensors), may be encoded as a:
     (1,'a tensor,1,1) switch, or
     (1,1,1,'a tensor) DAG-vertex
     In the last case, we have an exemple of a DAG-structure using meaningfull leafs and simply
     routing nodes (labels of type 1).
   ---
   Note that hyper-edges may be shared like vertex. So, we can consider that they can
   have also multiple entry-points (pointers to), not only multiple outputs (links).
   The same consideration holds for combs! In other words, combs are also multi-inputs and
   multi-outputs.
*)

(* --------------------------------------------
                Basic constructors
   -------------------------------------------- *)

(* val leaf : 't -> ('n,'e,'l,'t) vertex *)
let leaf t = Leaf t

(* val vertex : 'n -> ('n,'e,'l,'t) switch -> ('n,'e,'l,'t) vertex *)
let node n es = Node (n,es)

(* val switch : ('n,'e,'l,'t) edge array -> ('n,'e,'l,'t) switch *)
let switch es = Switch es

(* val edge : 'e -> ('n,'e,'l,'t) link array -> ('n,'e,'l,'t) edge*)
let edge e ls = Edge (e,ls)

(* val comb : ('n,'e,'l,'t) link array -> ('n,'e,'l,'t) comb *)
let comb ls = Comb ls

(* val link : 'l -> ('n,'e,'l,'t) vertex -> ('n,'e,'l,'t) link *)
let link l x  = Link (l,x)

let invalid_address ()               = invalid_arg "invalid_address"
let invalid_address_out_of_bounds () = invalid_arg "invalid_address: index out of bounds"
let array_get xs i = try xs.(i) with _ -> invalid_address_out_of_bounds ()


(* ============================================
                   Accessing
   ============================================ *)

(* injective <=> no-vertex-sharing (no vertex ubiquity)  *)
let rec
   get_vertex v = function
   | [] -> v
   | (i,j)::addr ->
       (match v with
       | Node (n, Switch sw) ->
           let Edge (e, Comb cb) = (array_get sw i) in
           let Link (l, v) = (array_get cb j) in
           get_vertex v addr
       | Leaf t -> invalid_address ()
       )

(** Structured address-based accessors to vertices: *)
module Get_vertex = struct
  type dir = switch_port_index * comb_port_index
  type address = dir list
  let rec
    from_vertex x = function
    | [] -> x
    | dir::addr ->
        (match x with
        | Node (n, sw) -> from_switch sw dir addr
        | Leaf t -> invalid_address ()
        )
  and from_switch (Switch sw)  (i,j) addr = from_edge (array_get sw i) j addr
  and from_edge   (Edge (e,cb))   j  addr = from_comb cb j addr
  and from_comb   (Comb cb)       j  addr = from_link (array_get cb j) addr
  and from_link   (Link (l,v))            = from_vertex v

end (* Get_vertex *)

(** Structured address-based accessors to switches: *)
module Get_switch = struct
  type dir = switch_port_index * comb_port_index
  type address = dir list
  let rec
    from_switch x = function
    | [] -> x
    | (i,j)::addr ->
        let (Switch sw) = x in from_edge (array_get sw i) j addr
  (* --- *)
  and from_edge   (Edge (e,cb)) j addr = from_comb cb j addr
  and from_comb   (Comb cb)     j addr = from_link (array_get cb j) addr
  and from_link   (Link (l,v))         = from_vertex v
  and from_vertex v addr =
   (match v with
    | Node (n, sw) -> from_switch sw addr
    | Leaf t -> invalid_address ()
    )
end (* Get_switch *)

(** Structured address-based accessors to edges: *)
module Get_edge = struct
  type dir = comb_port_index * switch_port_index
  type address = dir list
  let rec
    from_edge x = function
    | [] -> x
    | dir::addr ->
        let (Edge (e,cb)) = x in from_comb cb dir addr
  (* --- *)
  and from_comb (Comb cb) (j,i) addr = from_link (array_get cb j) i addr
  and from_link (Link (l,v)) = from_vertex v
  and from_vertex v i addr =
   (match v with
    | Node (n, sw) -> from_switch sw i addr
    | Leaf t -> invalid_address ()
    )
  and from_switch (Switch sw) i addr = from_edge (array_get sw i) addr
end (* Get_edge *)

(** Structured address-based accessors to combs: *)
module Get_comb = struct
  type dir = comb_port_index * switch_port_index
  type address = dir list
  let rec
    from_comb x = function
    | [] -> x
    | (j,i)::addr ->
        let (Comb cb) = x in from_link (array_get cb j) i addr
  (* --- *)
  and from_link (Link (l,v)) = from_vertex v
  and from_vertex v i addr =
   (match v with
    | Node (n, sw) -> from_switch sw i addr
    | Leaf t -> invalid_address ()
    )
  and from_switch (Switch sw) i = from_edge (array_get sw i)
  and from_edge   (Edge (e,cb)) = from_comb cb
end (* Get_comb *)

(** Structured address-based accessors to links: *)
module Get_link = struct
  type dir = switch_port_index * comb_port_index
  type address = dir list
  let rec
    from_link x = function
    | [] -> x
    | dir::addr ->
        let (Link (l,v)) = x in from_vertex v dir addr
  (* --- *)
  and from_vertex v dir addr =
   (match v with
    | Node (n, sw) -> from_switch sw dir addr
    | Leaf t -> invalid_address ()
    )
  and from_switch (Switch sw)  (i,j) addr = from_edge (array_get sw i) j addr
  and from_edge   (Edge (e,cb))   j  addr = from_comb cb j addr
  and from_comb   (Comb cb)       j  addr = from_link (array_get cb j) addr
end (* Get_link *)


(* ============================================
                Construction
   ============================================ *)

(* -------------------------------------------- *)
module Link = struct
(* -------------------------------------------- *)

  let get_label  (Link (label, vertex)) = label
  let get_vertex (Link (label, vertex)) = vertex

(*   let to_dot (Link (label, vertex))  *)

 end (* Link *)


(* -------------------------------------------- *)
module Comb = struct
(* -------------------------------------------- *)

  let empty () = Comb [||]

  let plug_links ?insert ~links (comb) =
    let Comb ls0 = comb in
    let ls1 = links in
    (* Append or insert the new links: *)
    let ls2 =
      match insert with
      | None     ->  Array.concat [ls0; ls1]
      | Some pos ->
          let k = Array.length ls0 in
          let n = Array.length ls1 in
          Array.init (k+n) (fun i -> if i<pos then ls0.(i) else if i<(pos+n) then ls1.(i-pos) else ls0.(i-n))
    in
    (* --- *)
    Comb (ls2)

  let plug_link ?insert ~link =
    plug_links ?insert ~links:[|link|]

  let plug_vertices ?insert ~labels ~targets =
    let n = Array.length targets in
    let () = assert (n = Array.length labels) in
    let links = Array.mapi (fun i target -> Link (labels.(i), target)) targets in
    plug_links ?insert ~links

  let plug_vertex ?insert ~label ~target =
    plug_vertices ?insert ~labels:[|label|] ~targets:[|target|]

 end (* Comb *)


(* -------------------------------------------- *)
module Edge = struct
(* -------------------------------------------- *)

  let empty (elabel) = Edge (elabel, Comb [||])

  let get_label (Edge (label, comb)) = label
  let get_comb  (Edge (label, comb)) = comb

  let plug_vertices ?insert ~labels ~targets (Edge (e, comb)) =
    Edge (e, Comb.plug_vertices ?insert ~labels ~targets (comb))

  let plug_vertex ?insert ~label ~target (Edge (e, comb)) =
    Edge (e, Comb.plug_vertex ?insert ~label ~target (comb))

 end (* Edge *)


(* -------------------------------------------- *)
module Switch = struct
(* -------------------------------------------- *)

  let empty () = Switch [||]

  let plug_edges ?insert ~edges (switch) =
    let Switch es0 = switch in
    let es1 = edges in
    (* Append or insert the new edges: *)
    let es2 =
      match insert with
      | None     ->  Array.concat [es0; es1]
      | Some pos ->
          let k = Array.length es0 in
          let n = Array.length es1 in
          Array.init (k+n) (fun i -> if i<pos then es0.(i) else if i<(pos+n) then es1.(i-pos) else es0.(i-n))
    in
    (* --- *)
    Switch (es2)

  let plug_edge ?insert ~edge =
    plug_edges ?insert ~edges:[|edge|]

  let plug_vertices ?insert ~labels ~targets =
    let n = Array.length targets in
    let () = assert (n = Array.length labels) in
    let edges = Array.mapi (fun i target -> Edge (labels.(i), target)) targets in
    plug_edges ?insert ~edges

  let plug_vertex ?insert ~label ~target =
    plug_vertices ?insert ~labels:[|label|] ~targets:[|target|]

  let plug_vertices_on_port ?insert ~port ~labels ~targets (Switch edges) =
    let edge' = Edge.plug_vertices ?insert ~labels ~targets edges.(port) in
    Switch (Array.mapi (fun i edge -> if i=port then edge' else edge) edges)

  let plug_vertex_on_port ?insert ~port ~label ~target (Switch edges) =
    let edge' = Edge.plug_vertex ?insert ~label ~target edges.(port) in
    Switch (Array.mapi (fun i edge -> if i=port then edge' else edge) edges)

 end (* Switch *)


(* -------------------------------------------- *)
module Vertex = struct
(* -------------------------------------------- *)

  let empty_node (vlabel) = Node (vlabel, Switch [||])

  let invalid_arg () = invalid_arg "Leafs are non-modifiable terminal vertices"

  let plug_edges ?insert ~edges = function
  | Leaf _ -> invalid_arg ()
  | Node (v, switch) ->
      Node (v, Switch.plug_edges ?insert ~edges switch)

  let plug_edge ?insert ~edge =
    plug_edges ?insert ~edges:[|edge|]

  (* Just operate on the switch component, copying the rest: *)
  let plug_vertices_on_port ?insert ~port ~labels ~targets = function
  | Leaf _ -> invalid_arg ()
  | Node (v, switch) -> Node (v, Switch.plug_vertices_on_port ?insert ~port ~labels ~targets switch)

  (* Special case of plug_vertices_on_port: by default we operate on the first (may be unique) port. *)
  let append_children_on_port ?(switch_port=0) (* 0 *) ?comb_port (* None (append) *) ~llabels ~targets =
    plug_vertices_on_port ?insert:comb_port ~port:switch_port ~labels:llabels ~targets

  let append_child_on_port ?switch_port ?comb_port ~llabel ~target =
      append_children_on_port ?switch_port ?comb_port ~llabels:[|llabel|] ~targets:[|target|]

  (* Special case of plug_edge: we create a comb linked to the provided targets,
      then we plug the hyper-edge built with this comb and the provided elabel: *)
  let append_children_on_a_single_edge ?insert ~elabel ~llabels ~targets =
    let edge = Edge.plug_vertices ~labels:llabels ~targets (Edge.empty elabel) in
    plug_edge ?insert ~edge

  let append_children_on_several_edges ?insert ~elabels ~llabels ~targets =
    let edges =
      Array.mapi
        (fun i elabel -> Edge.plug_vertex ~label:llabels.(i) ~target:targets.(i) (Edge.empty elabel))
        (elabels)
    in
    plug_edges ?insert ~edges

  (* Special case of plug_edge: here the created edge is a simple 2-endpoints
      connector, like in an ordinary graph: *)
  let append_child ?insert ~elabel ~llabel ~target =
    let edge = Edge.plug_vertex ~label:llabel ~target (Edge.empty elabel) in
    plug_edge ?insert ~edge

 end (* Vertex *)

(* Alias: *)
let empty = Comb.empty



(* --------------------------------------------
                Address memoisation
   -------------------------------------------- *)

module Address_tools = struct

  module AddrHash = struct  type t = Obj.t  let equal = (==)  let hash = Hashtbl.hash  end
  module AddrHashtbl = Hashtbl.Make(AddrHash)
  (* For debugging: *)
  let int_of_address x : int = Obj.magic (Obj.repr x)

  (** The default size of hash tables: *)
  let default_size = 51;;
  (* --- *)

  (* val manage_repeated_positions : ('b repeated -> 'a -> 'b) -> ('a -> 'b) *)
  let manage_repeated_positions (f : 'b option -> 'a -> 'b) : 'a -> 'b =
    let ht = AddrHashtbl.create default_size in
    function (x:'a) ->
      let addr = Obj.repr x in
      try
        (* let () = Printf.kfprintf flush stderr "manage_repeated_positions: about to find key %d\n" (int_of_address addr) in *)
        let y = AddrHashtbl.find ht addr in
        f (Some y) x
      with Not_found ->
        begin
          (* let () = Printf.kfprintf flush stderr "manage_repeated_positions: cache fault for key %d\n" (int_of_address addr) in *)
          let y = f None x in
          let () = AddrHashtbl.add ht addr y in
          y
        end
  (* --- *)

end (* Address_tools *)

(* --- Aliases: *)
let manage_repeated_positions = Address_tools.manage_repeated_positions
let id = fun x -> x
(* --- *)

(* --------------------------------------------
             Context_free mapping
   -------------------------------------------- *)

(* --------------------------------------------
   In the context-free setting, we can interpret the whole DAG as a big expression (like an arithmetic expression).
   From leafs, or more generally speaking, from terminal points, we can lift and synthetize values using the operations
   associated to each kind of elements. Note that the information found in a point, is processed before the recursive
   evaluation of its descendance (as for List.map). In other words, the evaluation looks as a bottom-up processing of
   values calculated respecting the implicit order of the structure (the order of adresses).
   Here memoization is not used for efficiency but only to preserve sharing, i.e. ubiquity of objects.
   -------------------------------------------- *)
module Context_free = struct
(* -------------------------------------------- *)

  type 'a repeated = 'a option

  (* Bottom-Up evaluation managing repeated positions: *)
  (* --------------------- *)
  module BotUpEval = struct
  (* --------------------- *)

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

    let botup_eval_functions fVertex fNode fLeaf fSwitch fEdge fComb fLink fn fe fl ft =
      (* --- *)
      let rec from_vertex' repeated vertex =
        let lazy_vertex_value =
          lazy begin match vertex with
          | Node (n, sw) ->
              let n' = fn n in
              let sw' = (Lazy.force from_switch) sw in
              (* bottom-up evaluation: *)
              fNode (n') (sw')
          | Leaf t ->
              let t' = ft t in
              (* bottom-up evaluation: *)
              fLeaf (t')
          end (* lazy_vertex_value *)
        in
        fVertex (repeated) (lazy_vertex_value)
      (* --- *)
      and from_switch' repeated switch =
        let lazy_switch_value =
          lazy begin match switch with
          | Switch es -> Array.map (Lazy.force from_edge) es
          end (* lazy_switch_value *)
        in
        (* bottom-up evaluation: *)
        fSwitch (repeated) (lazy_switch_value)
      (* --- *)
      and from_edge' repeated edge =
        let lazy_edge_value =
          lazy begin match edge with
          | Edge (e, cb) ->
              let e' = fe e in
              let cb' = (Lazy.force from_comb) cb in
              (e', cb')
          end (* lazy_edge_value *)
        in
      (* bottom-up evaluation: *)
      fEdge (repeated) (lazy_edge_value)
      (* --- *)
      and from_comb' repeated comb =
        let lazy_comb_value =
          lazy begin match comb with
          | Comb ls -> Array.map (Lazy.force from_link) ls
          end (* lazy_comb_value *)
        in
        (* bottom-up evaluation: *)
        fComb (repeated) (lazy_comb_value)
      (* --- *)
      and from_link' repeated link =
        let lazy_link_value =
          lazy begin match link with
          | Link (l, v) ->
              let l' = fl l in
              let v' = (Lazy.force from_vertex) v in
              (l', v')
          end (* lazy_link_value *)
        in
      (* bottom-up evaluation: *)
      fLink (repeated) (lazy_link_value)
      (* --- *)
      and from_vertex = lazy (manage_repeated_positions from_vertex')
      and from_switch = lazy (manage_repeated_positions from_switch')
      and from_edge   = lazy (manage_repeated_positions from_edge')
      and from_comb   = lazy (manage_repeated_positions from_comb')
      and from_link   = lazy (manage_repeated_positions from_link')
      (* --- *)
      in
      (* --- *)
      (Lazy.force from_vertex, Lazy.force from_switch, Lazy.force from_edge, Lazy.force from_comb, Lazy.force from_link)

    (* Top-level definitions: *)
    let from_vertex ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t =
      let (f,_,_,_,_) = botup_eval_functions vertex node leaf switch edge comb link n e l t in f

    let from_switch ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t =
      let (_,f,_,_,_) = botup_eval_functions vertex node leaf switch edge comb link n e l t in f

    let from_edge ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t =
      let (_,_,f,_,_) = botup_eval_functions vertex node leaf switch edge comb link n e l t in f

    let from_comb ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t =
      let (_,_,_,f,_) = botup_eval_functions vertex node leaf switch edge comb link n e l t in f

    let from_link ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t =
      let (_,_,_,_,f) = botup_eval_functions vertex node leaf switch edge comb link n e l t in f

  end (* BotUpEval *)

  (* --------------------- *)
  module Adapt_constructors_for_memoizing_map = struct
  (* --------------------- *)
    (* --- *)
    let manage_rp constr = function
    | None   -> (fun ly -> constr (Lazy.force ly))  (* apply the associated constructor *)
    | Some y -> (fun ly -> y)                       (* use memoized value *)

    let vertex r = manage_rp id r
    let switch r = manage_rp switch r                     (* basic constructor lifted to the desired behaviour *)
    let edge   r = manage_rp (fun (e,cb) -> edge e cb) r  (* basic constructor uncurried and lifted *)
    let comb   r = manage_rp comb r                       (* basic constructor lifted *)
    let link   r = manage_rp (fun (l,v) -> link l v) r    (* basic constructor uncurried and lifted *)

  end (* Adapt_constructors_for_memoizing_map *)

  (* --------------------- *)
  module BotUpEndoEval = struct
  (* --------------------- *)
    (* No way in OCaml to have applied functions as optional arguments of the general type ('a -> 'b): *)
    (* --- *)
    open Adapt_constructors_for_memoizing_map
    (* --- *)

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

    let from_vertex ?(vertex=vertex) ?(node=node) ?(leaf=leaf) ?(switch=switch) ?(edge=edge) ?(comb=comb) ?(link=link) ?(n=id) ?(e=id) ?(l=id) ?(t=id) =
      BotUpEval.from_vertex ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t

    let from_switch ?(vertex=vertex) ?(node=node) ?(leaf=leaf) ?(switch=switch) ?(edge=edge) ?(comb=comb) ?(link=link) ?(n=id) ?(e=id) ?(l=id) ?(t=id) =
      BotUpEval.from_switch ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t

    let from_edge ?(vertex=vertex) ?(node=node) ?(leaf=leaf) ?(switch=switch) ?(edge=edge) ?(comb=comb) ?(link=link) ?(n=id) ?(e=id) ?(l=id) ?(t=id) =
      BotUpEval.from_edge ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t

    let from_comb ?(vertex=vertex) ?(node=node) ?(leaf=leaf) ?(switch=switch) ?(edge=edge) ?(comb=comb) ?(link=link) ?(n=id) ?(e=id) ?(l=id) ?(t=id) =
      BotUpEval.from_comb ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t

    let from_link ?(vertex=vertex) ?(node=node) ?(leaf=leaf) ?(switch=switch) ?(edge=edge) ?(comb=comb) ?(link=link) ?(n=id) ?(e=id) ?(l=id) ?(t=id) =
      BotUpEval.from_link ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t

    (* Alias: *)
    let from_forest = from_switch
  end (* BotUpEndoEval *)

  (* --------------------- *)
  module Map = struct
  (* --------------------- *)
    (* --- *)
    open Adapt_constructors_for_memoizing_map
    (* --- *)
    type ('n0,'e0,'l0,'t0, 'n1,'e1,'l1,'t1, 'a, 'b) morphism =
          n:('n0 -> 'n1) -> e:('e0 -> 'e1) -> l:('l0 -> 'l1) -> t:('t0 -> 't1) ->  'a -> 'b

    let from_vertex ~n ~e ~l ~t = BotUpEval.from_vertex ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t
    let from_switch ~n ~e ~l ~t = BotUpEval.from_switch ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t
    let from_edge   ~n ~e ~l ~t = BotUpEval.from_edge   ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t
    let from_comb   ~n ~e ~l ~t = BotUpEval.from_comb   ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t
    let from_link   ~n ~e ~l ~t = BotUpEval.from_link   ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t
    (* Alias: *)
    let from_forest = from_switch
  end (* Endomorphic *)

  (* --------------------- *)
  module Iter = struct
  (* --------------------- *)
    (* --- *)
    module Adapt_constructors = struct
      (* --- *)
      let manage_rp = Adapt_constructors_for_memoizing_map.manage_rp

      (* We do nothing at constructor level: *)
      let vertex () = ()
      let switch es = ()
      let edge e ls = ()
      let comb ls = ()
      let link l x  = ()

      let vertex r = manage_rp id r
      let switch r = manage_rp switch r                    (* basic constructor lifted to the desired behaviour *)
      let edge   r = manage_rp (fun (e,cb) -> edge e cb) r (* basic constructor uncurried and lifted *)
      let comb   r = manage_rp comb r                      (* basic constructor lifted *)
      let link   r = manage_rp (fun (l,v) -> link l v) r   (* basic constructor uncurried and lifted *)

    end (* Adapt_constructors *)
    open Adapt_constructors
    (* --- *)

    type ('n,'e,'l,'t, 'a) morphism =
      ?n:('n -> unit) -> ?e:('e -> unit) -> ?l:('l -> unit) -> ?t:('t -> unit) ->  'a -> unit

    let leaf t = ()
    let node n es = ()
    (* --- *)
    let from_vertex ?(n=ignore) ?(e=ignore) ?(l=ignore) ?(t=ignore) =
      BotUpEval.from_vertex ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t

    let from_switch  ?(n=ignore) ?(e=ignore) ?(l=ignore) ?(t=ignore) =
      BotUpEval.from_switch ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t

    let from_edge  ?(n=ignore) ?(e=ignore) ?(l=ignore) ?(t=ignore) =
      BotUpEval.from_edge ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t

    let from_comb ?(n=ignore) ?(e=ignore) ?(l=ignore) ?(t=ignore) =
      BotUpEval.from_comb ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t

    let from_link ?(n=ignore) ?(e=ignore) ?(l=ignore) ?(t=ignore) =
      BotUpEval.from_link ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n ~e ~l ~t

    (* Alias: *)
    let from_forest = from_switch
  end (* Endomorphic *)

  (* --------------------- *)
  module Count = struct
  (* --------------------- *)

    type result = < vertices:int; nodes:int; leafs:int; switches:int; edges:int; combs: int; links:int; to_list:(string*int) list; >
    (* --- *)
    module Adapt_constructors = struct
      (* --- *)
      let zero = (0,0,0,0,0,0,0)

      let plus (vs0, ns0, ts0, ws0, es0, cs0, ls0) (vs1, ns1, ts1, ws1, es1, cs1, ls1) =
        (vs0+vs1, ns0+ns1, ts0+ts1, ws0+ws1, es0+es1, cs0+cs1, ls0+ls1)

      (* Manage repeated positions: *)
      let manage_rp constr = function
      | None   -> (fun ly -> constr (Lazy.force ly))  (* apply the associated constructor *)
      | Some y -> (fun ly -> zero)                    (* replace the memoized value by zero *)

      let vertex (vs, ns, ts, ws, es, cs, ls) = ((vs+1), ns, ts, ws, es, cs, ls)
      let node _ (vs, ns, ts, ws, es, cs, ls) = (vs, (ns+1), ts, ws, es, cs, ls)
      let leaf _ = (0,0,1,0,0,0,0)
      let switch = Array.fold_left (plus) (0,0,0,1,0,0,0)
      let edge _ (vs, ns, ts, ws, es, cs, ls) = (vs, ns, ts, ws, (es+1), cs, ls)
      let comb = Array.fold_left (plus) (0,0,0,0,0,1,0)
      let link _ (vs, ns, ts, ws, es, cs, ls)  = (vs, ns, ts, ws, es, cs, (ls+1))

      let vertex r = manage_rp vertex r
      let switch r = manage_rp switch r                    (* constructor lifted to the desired behaviour *)
      let edge   r = manage_rp (fun (e,cb) -> edge e cb) r (* constructor uncurried and lifted *)
      let comb   r = manage_rp comb r                      (* constructor lifted *)
      let link   r = manage_rp (fun (l,v) -> link l v) r   (* constructor uncurried and lifted *)

    end (* Adapt_constructors *)
    open Adapt_constructors

    let format_result (vs, ns, ts, ws, es, cs, ls) =
      object
        method vertices = vs
        method nodes    = ns
        method leafs    = ts
        method switches = ws
        method edges    = es
        method combs    = cs
        method links    = ls
        method to_list  = [("vertices",vs); ("nodes",ns); ("leafs",ts); ("switches",ws); ("edges",es); ("combs",cs); ("links",ls)]
      end

    let from_vertex x = format_result (BotUpEval.from_vertex ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    let from_switch x = format_result (BotUpEval.from_switch ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    let from_edge   x = format_result (BotUpEval.from_edge   ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    let from_comb   x = format_result (BotUpEval.from_comb   ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    let from_link   x = format_result (BotUpEval.from_link   ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    (* Alias: *)
    let from_forest = from_switch
  end (* Count *)

  (* --------------------- *)
  module Ubiquity = struct
  (* --------------------- *)
    (* --- *)
    type result = < vertices:int; nodes:int; leafs:int; switches:int; edges:int; combs: int; links:int; to_list:(string*int) list; answer:bool; >
    (* --- *)
    module Adapt_constructors = struct
      (* --- *)
      let zero = (0,0,0,0,0,0,0)

      let plus (vs0, ns0, ts0, ws0, es0, cs0, ls0) (vs1, ns1, ts1, ws1, es1, cs1, ls1) =
        (vs0+vs1, ns0+ns1, ts0+ts1, ws0+ws1, es0+es1, cs0+cs1, ls0+ls1)

      (* Manage repeated positions: *)
      let manage_rp (make_result) constr = function
      | None   -> (fun ly -> constr (Lazy.force ly))  (* apply the associated constructor *)
      | Some y -> (fun ly -> make_result y)           (* replace the memoized value by the appropriated result *)

      (* 'vertex = (tuple * bool), where the boolean indicates if the vertex is a leaf *)
      let vertex y = y
      let node _ y = (y, false)
      let leaf _   = (zero, true)
      let switch   = Array.fold_left (plus) (zero)
      let edge _ y = y
      let comb     = Array.fold_left (plus) (zero)
      let link _ (y, is_leaf) = y (* ignore the boolean is_leaf and return just the tuple of counters *)

      let vertex r =
         let make_result (tuple, is_leaf) =
           if is_leaf then ((1,0,1,0,0,0,0),is_leaf) else ((1,1,0,0,0,0,0),is_leaf)
         in
         manage_rp (make_result) vertex r
      (* --- *)
      let switch r = manage_rp (fun _ -> (0,0,0,1,0,0,0)) switch r
      let edge   r = manage_rp (fun _ -> (0,0,0,0,1,0,0)) (fun (e,cb) -> edge e cb) r
      let comb   r = manage_rp (fun _ -> (0,0,0,0,0,1,0)) comb r
      let link   r = manage_rp (fun _ -> (0,0,0,0,0,0,1)) (fun (l,v) -> link l v) r
    end (* Adapt_constructors *)
    open Adapt_constructors

    let format_result (vs, ns, ts, ws, es, cs, ls) =
      object
        method vertices = vs
        method nodes    = ns
        method leafs    = ts
        method switches = ws
        method edges    = es
        method combs    = cs
        method links    = ls
        method to_list  = [("vertices",vs); ("nodes",ns); ("leafs",ts); ("switches",ws); ("edges",es); ("combs",cs); ("links",ls)]
        (* The answer of the question "Is there ubiquity, i.e. sharing?": *)
        method answer   = (vs>0 || ns>0 || ts>0 || ws>0 || es>0 || cs>0 || ls>0)
      end

    let from_vertex x = format_result (fst (BotUpEval.from_vertex ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x))
    let from_switch x = format_result (BotUpEval.from_switch ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    let from_edge   x = format_result (BotUpEval.from_edge   ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    let from_comb   x = format_result (BotUpEval.from_comb   ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    let from_link   x = format_result (BotUpEval.from_link   ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    (* Alias: *)
    let from_forest = from_switch
  end (* Ubiquity *)

  (* --------------------- *)
  module Height = struct
  (* --------------------- *)

    type result = < vertices:int; nodes:int; leafs:int; switches:int; edges:int; combs: int; links:int; to_list:(string*int) list; >
    (* --- *)
    module Adapt_constructors = struct
      (* --- *)
      let zero = (0,0,0,0,0,0,0)

      let pairwise_max (vs0, ns0, ts0, ws0, es0, cs0, ls0) (vs1, ns1, ts1, ws1, es1, cs1, ls1) =
        (max vs0 vs1, max ns0 ns1, max ts0 ts1, max ws0 ws1, max es0 es1, max cs0 cs1, max ls0 ls1)

      (* Manage repeated positions: *)
      let manage_rp constr = function
      | None   -> (fun ly -> constr (Lazy.force ly))  (* apply the associated constructor *)
      | Some y -> (fun ly -> zero)                    (* replace the memoized value by zero *)

      let vertex (vs, ns, ts, ws, es, cs, ls) = ((vs+1), ns, ts, ws, es, cs, ls)
      let node _ (vs, ns, ts, ws, es, cs, ls) = (vs, (ns+1), ts, ws, es, cs, ls)
      let leaf _ = (0,0,1,0,0,0,0)
      let switch ys =
        let (vs, ns, ts, ws, es, cs, ls) = Array.fold_left (pairwise_max) (zero) (ys) in
        (vs, ns, ts, (ws+1), es, cs, ls)
      (* --- *)
      let edge _ (vs, ns, ts, ws, es, cs, ls) = (vs, ns, ts, ws, (es+1), cs, ls)
      let comb ys =
        let (vs, ns, ts, ws, es, cs, ls) = Array.fold_left (pairwise_max) (zero) (ys) in
        (vs, ns, ts, ws, es, (cs+1), ls)
      (* --- *)
      let link _ (vs, ns, ts, ws, es, cs, ls)  = (vs, ns, ts, ws, es, cs, (ls+1))

      let vertex r = manage_rp vertex r
      let switch r = manage_rp switch r
      let edge   r = manage_rp (fun (e,cb) -> edge e cb) r
      let comb   r = manage_rp comb r
      let link   r = manage_rp (fun (l,v) -> link l v) r

    end (* Adapt_constructors *)
    open Adapt_constructors

    let format_result (vs, ns, ts, ws, es, cs, ls) =
      object
        method vertices = vs
        method nodes    = ns
        method leafs    = ts
        method switches = ws
        method edges    = es
        method combs    = cs
        method links    = ls
        method to_list  = [("vertices",vs); ("nodes",ns); ("leafs",ts); ("switches",ws); ("edges",es); ("combs",cs); ("links",ls)]
      end

    let from_vertex x = format_result (BotUpEval.from_vertex ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    let from_switch x = format_result (BotUpEval.from_switch ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    let from_edge   x = format_result (BotUpEval.from_edge   ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    let from_comb   x = format_result (BotUpEval.from_comb   ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    let from_link   x = format_result (BotUpEval.from_link   ~vertex ~node ~leaf ~switch ~edge ~comb ~link ~n:(id) ~e:(id) ~l:(id) ~t:(id) x)
    (* Alias: *)
    let from_forest = from_switch
  end (* Height *)

end (* Context_free *)

(* Export the content of previous module at top-level: *)
include Context_free

(* --------------------------------------------
        Mapping as tree (ignoring sharing)
   -------------------------------------------- *)

module AsTree = struct

  let rec
    map_vertex fn fe fl ft = function
    | Node (n, sw) -> Node ((fn n), (map_switch fn fe fl ft sw))
    | Leaf t       -> Leaf (ft t)
  and
    map_switch fn fe fl ft = function
    | Switch es -> Switch (Array.map (map_edge fn fe fl ft) es)
  and
    map_edge fn fe fl ft = function
    | Edge (e, cb) -> Edge (fe e, map_comb fn fe fl ft cb)
  and
    map_comb fn fe fl ft = function
    | Comb ls -> Comb (Array.map (map_link fn fe fl ft) ls)
  and
    map_link fn fe fl ft = function
    | Link (l, v) -> Link (fl l, map_vertex fn fe fl ft v)

  (* Alias: *)
  let map_forest = map_switch

  (* No way in OCaml to have applied functions as optional arguments of the general type ('a -> 'b): *)
  module Endomorphic = struct
    let id = fun x -> x
    let map_vertex ?(n=id) ?(e=id) ?(l=id) ?(t=id) = map_vertex n e l t
    let map_switch ?(n=id) ?(e=id) ?(l=id) ?(t=id) = map_switch n e l t
    let map_edge   ?(n=id) ?(e=id) ?(l=id) ?(t=id) = map_edge   n e l t
    let map_comb   ?(n=id) ?(e=id) ?(l=id) ?(t=id) = map_comb   n e l t
    let map_link   ?(n=id) ?(e=id) ?(l=id) ?(t=id) = map_link   n e l t
    (* Alias: *)
    let map_forest = map_switch
  end (* Endomorphic *)


  (* --------------------------------------------
                    Folding
    -------------------------------------------- *)

  (* This is the type of the first version of folders: *)
  type ('ns, 'es, 'ls, 's, 'n, 'e, 'l, 't, 'target) folder_v0 =
    ('ns -> 'es -> 'ls -> 's -> 'n -> 'ns * 's) ->
    ('ns -> 'es -> 'ls -> 's -> 'e -> 'es * 's) ->
    ('ns -> 'es -> 'ls -> 's -> 'l -> 'ls * 's) ->
    ('ns -> 'es -> 'ls -> 's -> 't -> 's) ->
    'ns -> 'es -> 'ls -> 's -> 'target -> 's

  let rec
    fold_vertex fn fe fl ft sv se sl (s0:'s) = function
    | Node (n, sw) ->
        (* Seul l'état "vertical" `sv' est mis à jour: *)
        let (sv1, s1) = fn sv se sl s0 n in
        fold_switch fn fe fl ft sv1 se sl s1 sw
    | Leaf t ->
        ft sv se sl s0 t
  and
    fold_switch fn fe fl ft sv se sl (s0:'s) = function
    | Switch es ->
        (* Les états "verticaux" (sv se sl) ne sont pas mis à jour: *)
        Array.fold_left (fold_edge fn fe fl ft sv se sl) s0 es
  and
    fold_edge fn fe fl ft sv se sl (s0:'s) = function
    | Edge (e, cb) ->
        (* Seul l'état "vertical" `se' est mis à jour: *)
        let (se1, s1) = fe sv se sl s0 e in
        fold_comb fn fe fl ft sv se1 sl s1 cb
  and
    fold_comb fn fe fl ft sv se sl (s0:'s) = function
    | Comb ls ->
        (* Les états "verticaux" (sv se sl) ne sont pas mis à jour: *)
        Array.fold_left (fold_link fn fe fl ft sv se sl) s0 ls
  and
    fold_link fn fe fl ft sv se sl (s0:'s) = function
    | Link (l, v) ->
        (* Seul l'état "vertical" `sl' est mis à jour: *)
        let (sl1, s1) = fl sv se sl s0 l in
        fold_vertex fn fe fl ft sv se sl1 s1 v

  (* The exported type of folders: *)
  type ('ns, 'es, 'ls, 's, 'n, 'e, 'l, 't, 'target) folder =
    ?n:('ns -> 'es -> 'ls -> 's -> 'n -> 'ns * 's) ->
    ?e:('ns -> 'es -> 'ls -> 's -> 'e -> 'es * 's) ->
    ?l:('ns -> 'es -> 'ls -> 's -> 'l -> 'ls * 's) ->
    ?t:('ns -> 'es -> 'ls -> 's -> 't -> 's) ->
        ns:'ns -> es:'es -> ls:'ls -> 's -> 'target -> 's

  let fn_default = (fun sv se sl s0 x -> (sv,s0))
  let fe_default = (fun sv se sl s0 x -> (se,s0))
  let fl_default = (fun sv se sl s0 x -> (sl,s0))
  let ft_default = (fun sv se sl s0 x -> s0)

  let fold_vertex ?(n=fn_default) ?(e=fe_default) ?(l=fl_default) ?(t=ft_default) ~ns ~es ~ls = fold_vertex n e l t ns es ls
  let fold_switch ?(n=fn_default) ?(e=fe_default) ?(l=fl_default) ?(t=ft_default) ~ns ~es ~ls = fold_switch n e l t ns es ls
  let fold_edge   ?(n=fn_default) ?(e=fe_default) ?(l=fl_default) ?(t=ft_default) ~ns ~es ~ls = fold_edge   n e l t ns es ls
  let fold_comb   ?(n=fn_default) ?(e=fe_default) ?(l=fl_default) ?(t=ft_default) ~ns ~es ~ls = fold_comb   n e l t ns es ls
  let fold_link   ?(n=fn_default) ?(e=fe_default) ?(l=fl_default) ?(t=ft_default) ~ns ~es ~ls = fold_link   n e l t ns es ls
  (* Alias: *)
  let fold_forest = fold_switch

end (* AsTree *)

