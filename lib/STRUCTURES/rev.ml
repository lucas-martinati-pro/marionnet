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

(* For efficiency I rewrite a little stack library. *)
type 'a stack = { mutable l : 'a list }
let stack_create () = { l = [] }
let stack_clear s = s.l <- []
let stack_push x s = s.l <- x :: s.l
let stack_pop s = match s.l with x::xs -> s.l <- xs; x | [] -> assert false
let stack_top s = match s.l with x::_  -> x            | [] -> assert false
let stack_is_singleton s = (match s.l with [x] -> true | _ -> false)
let stack_iter f s = List.iter f s.l

(** The abstract type of reversible references. *)
type 'a t =
 { mutable previous : 'a list;
   mutable current  : 'a }

(** Create a reversible reference. *)
let create (v:'a) : 'a t =
 { previous = [];
   current  = v }

(* type 'a register = ('a stack) stack *)

(* A first parenthesis is implicitely opened. I use Obj.magic for efficiency reasons (thunks need to be applied). *)
let the_register =
 let r  = stack_create () in
 let s  = stack_create () in
 let () = stack_push s r  in (Obj.magic r)

let register_change (t:'a t) =
 let s = stack_top the_register in
 stack_push t s

(** Extract the value of the reference. *)
let get t = t.current

(** Set the value of the reference. *)
let set t v =
 begin
 t.previous <- t.current :: t.previous ;
 t.current  <- v;
 register_change t;
 end

(* Called by the register. *)
let unset t : unit =
 match t.previous with
  | v::l ->
     t.previous <- l;
     t.current  <- v;
  | []   -> assert false


(** Define a backtracking point. *)
let open_parenthesis () =
 let s = stack_create () in
 stack_push s the_register

(** Return to the backtracking point defined by the last opened parenthesis. May raise
    a failure in case of unbalanced parenthesis. *)
let close_parenthesis () =
 if stack_is_singleton the_register
  then failwith "Rev.close_parenthesis: unbalanced usage of parenthesis."
  else let s = stack_pop the_register in stack_iter unset s

(** Return to the backtracking point of the last opened parenthesis
    but the parenthesis is not closed: any future operation will concern this
    parenthesis (this stack) and not its parent. *)
let back_parenthesis () =
 let s = stack_top the_register in
 (stack_iter unset s);
 (stack_clear s)

(** Opening this module you redefine the standard [ref], [!] and [:=] in order to
    operate on this kind of structure instead of standard references. *)
module Toolkit = struct

 let ref v = { previous = []; current  = v }

 let (!) t = t.current

 let (:=) t v =
  begin
  t.previous <- t.current :: t.previous ;
  t.current  <- v;
  register_change t;
  end

end
