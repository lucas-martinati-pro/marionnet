(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009 Jean-Vincent Loddo

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

type t = {
 mutable counter : int;
 mutable stack   : (int list)
}

(* In this way there's a chance that the current value correspond
   to the number of already generated identifiers. *)
let default_initial_value = 1 ;;

(** Create a counter. *)
let create ?(initial_value=default_initial_value) () =
 { counter = initial_value;
   stack   = [];
 }

(** Increment the counter in order to return a fresh integer. *)
let fresh (c:t) =
 function () ->
   let result = c.counter in
   (c.counter <- c.counter + 1);
   result

(** Open a parenthesis. All integers used after this action
    will be able to be recycled once the parenthesis will be closed. *)
let open_parenthesis (c:t) = c.stack <- (c.counter)::(c.stack)

(** Close the parenthesis. The counter is restored to the value which was assigned
    at the moment of last call to [open_parenthesis]. Raise a [Failure] if any parenthesis
    has been opened. *)
let close_parenthesis (c:t) =
 match (c.stack) with
  | x::xs -> c.counter <- x ; c.stack <- xs
  | []    -> failwith "Counter.close_parenthesis: unbalanced usage of parenthesis."

type 'a generator = unit -> 'a

(** Create an int generator. *)
let make_int_generator () =
 let t = create () in fresh t

(** Create an string generator. *)
let make_string_generator ?(prefix="") ?(suffix="") () =
 let g = make_int_generator () in
 function () -> Printf.sprintf "%s%i%s" prefix (g ()) suffix


(** More sophisticated interface using objects: *)
class c ?(initial_value=default_initial_value) () =
 let t = create ~initial_value () in
 object(self)


   method fresh = fresh t
   method open_parenthesis = open_parenthesis t
   method close_parenthesis = close_parenthesis t

   (* New methods: *)

   method set_next_fresh_value_to x = t.counter <- x
   method get_next_fresh_value = t.counter

   method reset =
     t.counter <- initial_value;
     t.stack   <- [];

 end
