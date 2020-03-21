(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Jean-Vincent Loddo

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

(** The default size of the hash used in the implementation *)
let default_size = 251;;

(** The hashmap class *)
class ['a,'b] hashmap = fun ?(size=default_size) () ->

  object(self)

  (** The state of the hashmap. *)
  val current : ('a,'b) Hashtbl.t = (Hashtbl.create size)

  method get = current

  (** Return the object bound to the given key, or raise Not_found: *)
  method lookup x = (Hashtbl.find current x)

  (** Answer (quickly!) to the question if (x,y) is a member of the map. *)
  method mem x y : bool =  try y = (Hashtbl.find current x) with Not_found -> false

  (** Answer (quickly!) to the question if (x,y) is a member of the map. *)
  method memq x y : bool = try y == (Hashtbl.find current x) with Not_found -> false

  (** Answer if x is bound in the map. *)
  method bound x = Hashtbl.mem current x

  (** Add a binding to the map *)
  method add x y = Hashtbl.replace current x y

  (** Alias for [add] *)
  method replace x y = Hashtbl.replace current x y

  (** Remove the binding for the given key. *)
  method remove x = Hashtbl.remove current x

  (** Make an alist from the map, returning the bindings as <key, value> pairs in some
      unspecified order. *)
  method to_list =
    Hashtbl.fold (fun a b current_list -> (a, b) :: current_list) current []

  (** Add all the binding from the given alist to the map. In case of multiple values
      for a single key it's undefined which value prevails. *)
  method add_list alist =
    ignore (List.map (fun (key, datum) -> self#add key datum) alist)
end;; (* class hashmap *)

(* Functional interface. *)

(** The abstract type of an hashmap. *)
type ('a,'b) t       = ('a,'b) hashmap ;;

(** The hashmap constructor. *)
let make ?(size=default_size) () : ('a,'b) t = new hashmap ~size () ;;

(** Return the object bound to the given key, or raise Not_found: *)
let lookup (h:('a,'b) t) x = h#lookup x

(** The member predicate. *)
let mem (h:('a,'b) t) (x:'a) (y:'b) = h#mem x y;;

(** The member predicate with the physical equality. *)
let memq (h:('a,'b) t) (x:'a) (y:'b) = h#memq x y;;

(** Answer if x is bound in the map. *)
let bound (h:('a,'b) t) (x:'a) = h#bound x ;;

(** Add a binding to the hashmap. *)
let add (h:('a,'b) t) (x:'a) (y:'b) = h#add x y;;

(** Add all the binding from the given alist to the map. In case of multiple values
    for a single key it's undefined which value prevails. *)
let add_list (h:('a,'b) t) (alist:('a * 'b) list) = h#add_list alist;;

(** Replace or add (when not existing) a binding to a map. *)
let replace (h:('a,'b) t) (x:'a) (y:'b) = h#replace x y;;

(** Remove one or all (default) bindings of the given key. *)
let remove (h:('a,'b) t) (x:'a) = h#remove x;;

(** [update t1 t2] updates the map [t1] adding all the bindings from [t2].*)
let update (h1:('a,'b) t) (h2:('a,'b) t) : unit = Hashtbl.iter (h1#add) (h2#get) ;;

(** Make an alist from an hashmap, returning the bindings as <key, value> pairs in some
    unspecified order. *)
let to_list (h:('a,'b) t) = h#to_list;;

(** Make a new hashmap from an alist made of <key, value> pairs. If more than one
    binding is specified for a single key it's undefined which value prevails. *)
let of_list ?size:(size=default_size) alist =
  let h : ('a,'b) t = new hashmap ~size () in
  h#add_list alist;
  h;;
