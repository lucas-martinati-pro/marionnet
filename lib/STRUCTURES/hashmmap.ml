(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Jean-Vincent Loddo
   Copyright (C) 2008  Luca Saiu (wrote the methods remove_key_value_or_fail
                                  and remove_key_value)

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

(** The hashmultimap class *)
class ['a,'b] hashmultimap = fun ?(size=default_size) () ->

  object (self)

  (** The state of the hashmap. *)
  val current : ('a,'b) Hashtbl.t = (Hashtbl.create size)

  method get = current

  (** Return all the objects bound to the given key, or raise Not_found: *)
  method lookup_or_fail x = (Hashtbl.find_all current x)

  (** Return all the objects bound to the given key, or the empty list if no binding is found: *)
  method lookup x = try self#lookup_or_fail x with Not_found -> []

  (** Answer (quickly!) to the question if (x,y) is a member of the (multi) map. *)
  method mem x y  : bool = try List.mem  y (Hashtbl.find_all current x) with Not_found -> false

  (** Answer (quickly!) to the question if (x,y) is a member of the (multi) map. *)
  method memq x y : bool = try List.memq  y (Hashtbl.find_all current x) with Not_found -> false

  (** Answer if x is bound in the multi map. *)
  method bound x = Hashtbl.mem current x

  (** Add a binding to a multi map. A key may be associated to several values, 
      but at most one occurrence of a same binding (key, value) will be stored. 
      This semantics should be the only relevant difference with standard hash tables (Hashtbl). *)
  method add x y = 
    if self#mem x y 
      then () (* don't repeat the same binding several times in the structure *)
      else (Hashtbl.add current x y)

  (** Replace or add (when not existing) a binding to a multi map. *)
  method replace x y = (self#remove ~all:true x); Hashtbl.add current x y

  (** Remove one or all (default) bindings of the given key. *)
  method remove ?(all=true) x =
    if all then
            let rm1binding = (fun k v -> if k=x then (Hashtbl.remove current k) else ()) in
            Hashtbl.iter rm1binding current
           else
	    (Hashtbl.remove current x)

  (** Remove the given <key, value> binding, if present; otherwise do nothing. *)
  method remove_key_value key value =
    let old_values_for_key = self#lookup key in
    let new_values_for_key =
      List.filter
        (fun a_value -> not (value = a_value))
        old_values_for_key in
    let new_bindings_for_key =
      List.rev (* We reverse as we want to keep the previous element 'priority' *)
        (List.map
           (fun a_value -> key, a_value)
           new_values_for_key) in
    self#remove ~all:true key;
    List.iter
      (fun (new_key, new_value) ->
        self#add new_key new_value)
      new_bindings_for_key

  (** Remove the given <key, value> binding, if present; otherwise raise an exception. *)
  method remove_key_value_or_fail key value =
    let old_values_for_key_no = List.length (self#lookup key) in
    self#remove_key_value key value;
    if not ((List.length (self#lookup key)) = (old_values_for_key_no - 1)) then begin
      failwith "remove_key_value_or_fail did not remove *one* element";
    end
  (** Make an alist from the map, returning the bindings as <key, value> pairs in some
      unspecified order. *)
  method to_list =
    Hashtbl.fold (fun a b current_list -> (a, b) :: current_list) current []

  (** Add all the binding from the given alist to the map. *)
  method add_list alist =
    ignore (List.map (fun (key, datum) -> self#add key datum) alist)
end;; (* class hashmultimap *)

(* Functional interface. *)

(** The abstract type of an hashmmap. *)
type ('a,'b) t       = ('a,'b) hashmultimap ;;

(** The hashmmap constructor. *)
let make ?(size=default_size) () : ('a,'b) t = new hashmultimap ~size () ;;

(** Return all the objects bound to the given key, or raise Not_found: *)
let lookup_or_fail (h:('a,'b) t) x = h#lookup_or_fail x;;

(** Return all the objects bound to the given key, or the empty list if no binding is found: *)
let lookup (h:('a,'b) t) x = h#lookup x;;

(** The member predicate. *)
let mem (h:('a,'b) t) (x:'a) (y:'b) = h#mem x y;;

(** The member predicate with the physical equality. *)
let memq (h:('a,'b) t) (x:'a) (y:'b) = h#memq x y;;

(** Answer if x is bound in the multi map. *)
let bound (h:('a,'b) t) (x:'a) = h#bound x ;;

(** Add a binding to the hashmmap. *)
let add (h:('a,'b) t) (x:'a) (y:'b) = h#add x y;;

(** Add all the binding from the given alist to the map. *)
let add_list (h:('a,'b) t) (alist:('a * 'b) list) = h#add_list alist;;

(** [replace h x y] removes all bindings in [h] for the key [x], then add the binding [(x,y)]. *)
let replace (h:('a,'b) t) (x:'a) (y:'b) = h#replace x y;;

(** Remove one or all (default) bindings of the given key. *)
let remove (h:('a,'b) t) ?(all=true) (x:'a) = h#remove ~all x;;

(** [update ~replace t1 t2] updates the map [t1] adding (by calling [add]) all the bindings from [t2].
    If the flag [replace] is [true], all existing keys in [t2] are removed from [t1] before
    insertions take place.*)
let update ?(replace=false) (h1:('a,'b) t) (h2:('a,'b) t) : unit =
  (if replace then Hashtbl.iter (fun x y ->h1#remove x) (h2#get)) ;
  Hashtbl.iter (h1#add) (h2#get) ;;

(** Make an alist from an hashmmap, returning the bindings as <key, value> pairs in some
    unspecified order. *)
let to_list (h:('a,'b) t) = h#to_list;;

(** Make a new hashmmap from an alist made of <key, value> pairs. *)
let of_list ?size:(size=default_size) alist =
  let h : ('a,'b) t = new hashmultimap ~size () in
  ignore (List.map (fun (key, datum) -> h#add key datum) alist);
  h;;
