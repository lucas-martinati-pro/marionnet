(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007 Jean-Vincent Loddo, Luca Saiu

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

IFNDEF OCAML4_02_OR_LATER THEN
module Bytes = struct  include String  let to_string x = x  let of_string x = x  end
type bytes = string
ENDIF

(* **************************************** *
              Class Env
 * **************************************** *)

(** The class of environments. An ('a,'b) environment is a set of
    <key,value> pairs, where key is of type 'a and value of type 'b.
    A single environment can't contain more than a single binding for
    each key. *)
class ['a,'b] env = fun () -> object (self)
  (** The internal representation of an environment. *)
  val table : ('a, 'b) Hashmap.t = Hashmap.make ()

  (** Convert into a list of pairs. *)
  method to_list     = Hashmap.to_list table

  (** Add a list of binding to the environment. *)
  method add_list xs = Hashmap.add_list table xs

  (** High level accessors. *)

  (** Get the value associated to the given id (key). *)
  method get id    = Hashmap.lookup table id

  (** Add a pair (identifier,value) to the environment. *)
  method add (id,v) = Hashmap.add table id v

  (** Update the environment (self) by another environment which will "cover" previous links.*)
  method updated_by (e:(('a,'b) env)) : unit =
    List.iter (self#add) (e#to_list)

end;;

(** Simple constructor for environments.*)
let make (l:('a*'b) list) = let e=(new env ()) in (e#add_list l); e;;


(* **************************************** *
          Class string_env
 * **************************************** *)

(** {2 String environments }
    The special (and quite common) case where keys are strings allows the user
    to better trace failures of the `get' method. *)

exception Undefined_identifier of string
class ['b] string_env () = object (self)
  inherit [string,'b] env () as super
  method! get id = try (super#get id) with Not_found -> raise (Undefined_identifier id)

  (** {b Example}:
{[# let e = Environment.make_string_env [("aaa", 1); ("bbbbbb",2); ("c",3) ] ;;
val e : int Environment.string_env = <obj>
# Printf.printf "%s" (e#to_string (string_of_int)) ;;
bbbbbb = 2
c      = 3
aaa    = 1
  : unit = ()
]}
*)
  method to_string string_of_alpha =
    match self#to_list with
    | [] -> ""
    | xs ->
       let domain = List.map fst xs in
       let max_length = ListExtra.max (List.map String.length domain) in
       let ys =
         List.map
           (fun (k,v) ->
              let k = Bytes.of_string k in
              let k' = Bytes.make max_length ' ' in
              Bytes.blit k 0 k' 0 (Bytes.length k);
              (Printf.sprintf "%s = %s\n" (Bytes.to_string k') (string_of_alpha v)))
           xs
       in
       List.fold_left (^) (List.hd ys) (List.tl ys)

end;;

(** Simple constructor for string environments.*)
let make_string_env (l:(string*'b) list) = let e=(new string_env ()) in (e#add_list l); e;;

let string_env_updated_by (r:'a string_env) (r':'a string_env) =
  let () = r#updated_by (r' :> (string,'a) env) in
  r


