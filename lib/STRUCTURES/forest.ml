(* This file is part of ocamlbricks
   Copyright (C) 2007, 2008  Luca Saiu
   Copyright (C) 2007, 2010, 2012  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2010, 2012  Université Paris 13

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

(* Authors:
 * - Luca Saiu: initial version
 * - Jean-Vincent Loddo: minor changes (refactoring, comments, public interface)
*)

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

(** This definition prevents equivalences
    (each forest as a unique representation). *)
type 'a t =
  | Nil                    (** empty forest *)
  | Cons of ('a * 'a t) *  (** first tree (root and subtrees) *)
            ('a t)         (** other trees *)

type 'a tree = 'a * 'a t (** a tree is a root with the forest of its children *)
type 'a leaf = 'a        (** a leaf is a tree without children *)

let empty = Nil
let is_empty t = (t=Nil)

(** Prepend a tree to a forest. *)
let cons t f = Cons (t,f)
let add_tree = cons

(** Prepend to a forest a tree which is a leaf. *)
let cons_leaf (x:'a) t = Cons ((x,Nil),t)
let add_leaf = cons_leaf

(** Make a forest with a single tree. *)
let of_tree t = Cons (t,Nil)

let hd = function
| Nil -> None
| Cons(t, _) -> Some t

let tl = function
| Nil -> None
| Cons(_, f) -> Some f

let to_tree = function
| Cons(t, Nil) -> t
| _ -> invalid_arg "Forest.to_tree: the forest is not a singleton"

(** Make a forest with a single tree which is a leaf. *)
let of_leaf (x:'a leaf) = Cons ((x,Nil),Nil)

let tree_of_leaf (x:'a leaf) : 'a tree = (x, Nil)

(** Returns the list of the 'a elements belong the forest.
    The order is depth-first, left-to-right. *)
let rec to_list : 'a t -> 'a list  = function
| Nil -> []
| Cons((root, subtrees), rest) ->
      root :: (List.append (to_list subtrees) (to_list rest))

(** Append the second forest at the end of the first one. *)
let rec concat f1 f2 =
  match f1 with
  | Nil -> f2
  | Cons(t1, f1) -> Cons(t1, concat f1 f2)

(** Map the function over the 'a elements of the forest. *)
let rec map f forest =
  match forest with
    Nil -> Nil
  | Cons((root, subtrees), rest) ->
      let root = f root in
      let subtrees = map f subtrees in
      let rest = map f rest in
      Cons((root, subtrees), rest)

(** Iterate calling f on all nodes. The order is depth-first, left-to-right.
    f has the node as its first parameter, and its "parent-tree-node-option" as
    its second parameter *)
let rec iter_pre_order ?parent (f : 'a -> 'a option -> unit) (forest : 'a t) =
  match forest with
    Nil ->
      ()
  | Cons((root, subtrees), rest) ->
      begin
        f root parent;
        iter_pre_order ~parent:root f subtrees;
        iter_pre_order ?parent f rest
      end

let rec iter_post_order ?parent (f : 'a -> 'a option -> unit) (forest : 'a t) =
  match forest with
    Nil ->
      ()
  | Cons((root, subtrees), rest) ->
      begin
        iter_post_order ~parent:root f subtrees;
        f root parent;
        iter_post_order ?parent f rest
      end

let iter ?post_order =
 match post_order with
 | None    -> iter_pre_order
 | Some () -> iter_post_order

(** Iterate calling f on all nodes. The order is depth-first, left-to-right.
    f has the node as its first parameter, and its "parent-tree-node-option" as
    its second parameter *)
let rec fold_pre_order ?parent (f : 'b -> 'a -> 'a option -> 'b) acc (forest : 'a t) =
  match forest with
    Nil -> acc
  | Cons((root, subtrees), rest) ->
      begin
        let acc = f acc root parent in
        let acc = fold_pre_order ~parent:root f acc subtrees in
        let acc = fold_pre_order ?parent f acc rest in
        acc
      end

let rec fold_post_order ?parent (f : 'b -> 'a -> 'a option -> 'b) acc (forest : 'a t) =
  match forest with
    Nil -> acc
  | Cons((root, subtrees), rest) ->
      begin
        let acc = fold_post_order ~parent:root f acc subtrees in
        let acc = f acc root parent in
        let acc = fold_post_order ?parent f acc rest in
        acc
      end

let fold ?post_order =
 match post_order with
 | None    -> fold_pre_order
 | Some () -> fold_post_order
 
(** Bad nodes (which not verify the property p) are cut and orphans lifted up. *)
let rec filter p forest =
  match forest with
    Nil -> Nil
  | Cons((root, subtrees), rest) ->
      let subtrees = filter p subtrees in
      let rest = filter p rest in
      if p root then
        Cons((root, subtrees), rest)
      else
        concat subtrees rest

(** Return a list of all the nodes in the given forest satisfying the given predicate.
    The order is as usual depth-first, left-to-right. *)
let rec nodes_such_that predicate forest =
  match forest with
    Nil -> []
  | Cons((root, subtrees), rest) ->
      let switch = predicate root in
      let subtrees = nodes_such_that predicate subtrees in
      let rest = nodes_such_that predicate rest in
      let xs = List.append subtrees rest in
      if switch then root::xs else xs

(** Return the node in the given forest satisfying the given predicate.
    The order is as usual depth-first, left-to-right. *)
let rec search predicate forest =
  match forest with
  | Nil -> None
  | Cons((root, subtrees), rest) ->
      if predicate root then (Some root) else
      match (search predicate subtrees) with
      | None -> search predicate rest
      | x -> x
;;

let search_and_replace pred repl t =
  map (fun a -> if pred a then repl a else a) t
;;

(** Return the node in the given forest satisfying the given predicate.
    The order is as usual depth-first, left-to-right. Raises [Not_found]
    if the element is not found. *)
let find predicate forest =
  match search predicate forest with
  | None   -> raise Not_found
  | Some x -> x
;;

(** Return the parent of a node satisfying the given predicate.
    The order is as usual depth-first, left-to-right. *)
let parent_of_node_such_that predicate forest =
 let rec loop ?parent forest =
  match forest with
  | Nil -> None
  | Cons ((root, subtrees), rest) ->
      if predicate root then parent else
      match (loop ~parent:root subtrees) with
      | None -> loop ?parent rest
      | x -> x
 in loop forest
;;

let parent_of node forest =
  parent_of_node_such_that ((=) node) forest
;;

(** Return the first-level nodes (similar to 'find -maxdepth 1'). *)
let rec roots_of = function
  | Nil -> []
  | Cons((root, _), rest) -> root :: (roots_of rest)
;;

(** Return a list of all the children of the given node in the given
    forest, in some unspecified order. Note that the given node may
    appear in several positions in the forest. In this case the result
    is the catenation of childrens of these occurrences. *)
let children_nodes node forest =
  let rec children_nodes_of_existing_node node forest =
  match forest with
    Nil -> []
  | Cons((root, subtrees), rest) ->
      if root = node then
        roots_of subtrees
      else
        List.append
          (children_nodes_of_existing_node node subtrees)
          (children_nodes_of_existing_node node rest)
  in
  match nodes_such_that (fun a_node -> a_node = node) forest with
  |[] -> failwith "children_nodes: node not existing"
  | _ -> children_nodes_of_existing_node node forest

(** Return the root of the single child of the given node.
    Fail if the node has a number of children different from one. *)
let child_node node forest =
  let singlet = children_nodes node forest in
  if List.length singlet <> 1 then
    failwith "child_node: the node has zero or more than one children"
  else
    List.hd singlet

(** Return a list of all the descendant nodes of the given node in the given
    forest. The order is depth-first, left-to-right. *)
let rec descendant_nodes node forest =
  match forest with
    Nil -> []
  | Cons((root, subtrees), rest) ->
      if root = node then
        to_list subtrees
      else
        List.append
          (descendant_nodes node subtrees)
          (descendant_nodes node rest)

(** Grandchildrens *)
let grandchildren_nodes_with_repetitions node forest =
  let children_nodes_of_node = children_nodes node forest in
  List.flatten
    (List.map
       (fun node -> children_nodes node forest)
       children_nodes_of_node);;

let printable_string_of_forest
 ?(level=0)
 ?(string_of_node=(fun _ ->"<NODE>"))
 forest
 =
 let buffer = Buffer.create 100 in
 let print_string x = Buffer.add_string buffer x in
 let print_node x   = Buffer.add_string buffer (string_of_node x) in

 (* Support for indentation *)
 let indent = function level ->
   for _i = 1 to level do print_string "  "; done;
   if level = 0 then print_string "* " else print_string "`-"
 in
 let rec loop ~level = function
  | Nil -> ()
  | Cons((root, subtrees), rest) ->
      begin
	indent level;
	print_node root;
	print_string "\n";
	loop ~level:(level + 1) subtrees;
	loop ~level rest;
      end
 in
 loop ~level forest;
 Buffer.contents buffer
;;

(** A printer for forests: *)
let print_forest ?level ?string_of_node ~channel forest =
  let s = printable_string_of_forest ?level ?string_of_node forest in
  Printf.kfprintf flush channel "%s" s
;;

(** Add the given tree to the given forest, as a new child of every
    found node satisfying the given predicate. The new forest is
    returned *)
let rec add_tree_to_forest_for_each predicate tree_root tree_subtrees forest =
  match forest with
    Nil -> Nil
  | Cons((root, subtrees), rest) ->
      if predicate root then
        let tree = 
          (root, concat
                   (add_tree_to_forest_for_each predicate tree_root tree_subtrees subtrees)
                   (Cons((tree_root, tree_subtrees), Nil)))
        in
        Cons(tree, rest)
      else
        let tree = (root, (add_tree_to_forest_for_each predicate tree_root tree_subtrees subtrees)) in
        Cons(tree, (add_tree_to_forest_for_each predicate tree_root tree_subtrees rest))

(** Add the given tree to the given forest, as a new child of the only
    node satisfying the given predicate, or at toplevel if no node satisfies
    it. If more than a node in the forest satisfies the predicate an exception
    is raised. *)
let add_tree_to_forest predicate tree_root tree_subtrees forest =
  let nodes = to_list forest in
  let satisfying_nodes = List.filter predicate nodes in
  let satisfying_nodes_length = List.length satisfying_nodes in
  if satisfying_nodes_length = 0 then
    concat forest (Cons((tree_root, tree_subtrees), Nil))
  else if satisfying_nodes_length = 1 then
    add_tree_to_forest_for_each predicate tree_root tree_subtrees forest
  else
    failwith
      (Printf.sprintf
         "add_tree_to_forest predicate: more than one node (in fact %i) satisfies the predicate"
         satisfying_nodes_length)


(* --- Jean --- facilities using forests to encode trees: *)

(** Has the forest the form of a tree (i.e. a forest of length 1)? *)
let is_tree = function
| Cons (t,Nil) -> true
| _ -> false


(** Has the forest the form of a leaf? *)
let is_leaf = function
| Cons ((_,Nil),Nil) -> true
| _ -> false


(** A forest may be viewed as a list of trees. *)
let rec to_treelist : 'a t -> 'a tree list = function
| Nil -> []
| Cons (t,f) -> t::(to_treelist f)


(** A list of forests may be viewed as a single big forest.
    The forests in the list are simply catenated. *)
let rec of_forestlist : 'a t list -> 'a t = function
| []                  -> Nil
| Nil::fs             -> of_forestlist fs
| (Cons (t,rest))::fs -> Cons (t, (concat rest (of_forestlist fs)))
;;

(** A list of trees may be recompacted into a single forest. This function
    is similar to the [of_forestlist] but prevents the call to [concat] and
    also checks if all elements are really trees. An exception [Failure "of_nodelist"]
    is raised when a non tree element is encountered (use [of_forestlist] if you want
    flexibility). *)
(*let rec of_treelist (l:'a t list) = match l with
| []                              -> Nil
| (Cons (x,children,Nil))::l' -> Cons (x,children, (of_treelist l'))
| _ -> failwith "of_nodelist" (* A run-time type checking *)*)

let rec of_treelist : 'a tree list -> 'a t = function
| []    -> Nil
| t::ts -> Cons (t, (of_treelist ts))

(** Convert a list of unstructured elements into a forest of leafs. *)
let of_list (l:'a list) = of_forestlist (List.map of_leaf l)

(** {b Example}:
{[let f = Forest.of_acyclic_relation (function 0->[1;2]|1->[3;4;5]|2->[6;7]|3->[8]| _ -> []) [0] in
Forest.print_forest ~string_of_node:(string_of_int) f ~channel:stdout ;;
* 0
  `-1
    `-3
      `-8
    `-4
    `-5
  `-2
    `-6
    `-7 ]} *)
let of_acyclic_relation ~(successors:'a -> 'a list) ~(roots:'a list) : 'a t =
  let rec loop x : 'a tree =
    let children = successors x in
    let children_trees = List.map (loop) children in
    (x, (of_treelist children_trees))
  in
  let treelist = List.map (loop) roots in
  of_treelist (treelist)

let tree_of_acyclic_relation ~(successors:'a -> 'a list) ~(root:'a) : 'a tree =
  let rec loop x : 'a tree =
    let children = successors x in
    let children_trees = List.map (loop) children in
    (x, (of_treelist children_trees))
  in
  loop root

(** Back-propagation (from leafs to roots) of evaluations over a tree: *)  
let rec backprop_tree eval (root, subtrees) =
 let ts = to_treelist subtrees in
 let vs = List.map (backprop_tree eval) ts in
 eval root vs

(** Parallel (using Futures) back-propagation (from leafs to roots) of evaluations over a tree: *)  
let rec backprop_tree_parallel eval (root, subtrees) =
 let ts = to_treelist subtrees in
 let futures = List.map (Future.future (backprop_tree_parallel eval)) ts in
 let vs = List.map (Future.touch) futures in
 eval root vs

(** Back-propagation (from leafs to roots) of evaluations over a forest: *)  
let backprop eval forest =
 let ts = to_treelist forest in
 List.map (backprop_tree eval) ts

(** Parallel (using Futures) back-propagation (from leafs to roots) of evaluations over a forest: *)  
let backprop_parallel eval forest =
 let ts = to_treelist forest in
 let futures = List.map (Future.future (backprop_tree_parallel eval)) ts in
 List.map (Future.touch) futures

let rec sort compare forest =
 let xs = to_treelist forest in
 let ys = List.map (sort_tree compare) xs in
 let zs = List.sort (fun (root1,_) (root2,_) -> compare root1 root2) ys in
 of_treelist zs 

and sort_tree compare (root, subtrees) =
 let subtrees' = sort compare subtrees in
 (root, subtrees')
 
