(* This file is part of ocamlbricks
   Copyright (C) 2012  Jean-Vincent Loddo

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

type 'a t = unit -> 'a

(** Transform a thunk in a one-shot thunk, i.e. a thunk that is not really executed more than once; 
    the second and subsequent calls return immediately the previous result: *)
let linearize thunk =
 let already_called = ref None in
 fun () ->
   match !already_called with
   | Some y -> y
   | None ->
       begin
         let y = thunk () in
         already_called := Some y; (* memoise *)
         y
       end

let one_shot = linearize

(** The resulting thunk will be protected from exceptions.
    It will translate all exceptions in the output [()]. *)
let protect ~fallback thunk =
 (fun () -> try thunk () with _ -> fallback ())

(** Simply the application. *)
let apply thunk = thunk ()



(** Conversion from lazy. Note that the result is directly a linear (one-shot) thunk because of the lazyness.
    However, the tool [linearize] still remains interesting for this kind of thunks.
    Actually, if the lazy value raises an exception, the resulting thunk raises this exception for each call,
    while the linearized one raises this exception only once. *)
let of_lazy l = fun () -> Lazy.force l
let to_lazy thunk = lazy (thunk ())

type id = int
type linear = bool

let rec first_success pred = function
| []    -> None
| t::ts ->
  let y = t () in
  (match (pred y) with
   | false -> first_success pred ts
   | true  -> Some y
   )

let first_attempt p0 ts =
 let p1 = function None -> false | Some x -> p0 x in
 Option.join (first_success p1 ts)

module Make_class_with_discipline (M : Container.T_with_identifiers) = struct

let dress_thunk ?fallback ?one_shot thunk =
  let thunk =
    match fallback with
    | Some fallback -> protect ~fallback thunk
    | None -> thunk
  in
  let result =
    match one_shot with
    | Some () -> ((linearize thunk), true) (* linearize is not really needed here *)
    | None    -> (thunk, false)
  in
  result

class ['a] container ?fallback () =
 let fallback_default = fallback in
 object (self)
  val container = M.create ()

  val mutable revno = 0
  method revno = revno

  method register_thunk
    : ?fallback:'a t -> ?one_shot:unit -> 'a t -> id
    = fun ?fallback ?one_shot thunk ->
      let fallback = if fallback=None then fallback_default else fallback in
      let id = M.push (dress_thunk ?fallback ?one_shot thunk) container in
      revno <- revno + 1;
      id

  method register_lazy
    : ?fallback:'a t -> 'a Lazy.t -> id
    = fun ?fallback lazy_action ->
      let fallback = if fallback=None then fallback_default else fallback in
      let thunk = of_lazy lazy_action in
      let id = M.push (dress_thunk ?fallback ~one_shot:() thunk) container in
      revno <- revno + 1;
      id

  method apply
    : 'b. ?folder:('b -> 'a -> 'b) -> 'b -> 'b
    = fun ?folder acc ->
      (* Redefine the folder in order to apply the thunk, then the folder: *)
      let folder =
	match folder with
	| None   -> (fun acc y -> acc)
	| Some f -> f
      in
      let folder acc (thunk, linear) = folder acc (thunk ()) in
      let result = M.fold folder acc container in
      let () = M.filter (fun (thunk, linear) -> not linear) container in
      result

  (* The application is delayed but it will act on the current (not the future) 
     list of thunks. Note also that the one-shot thunks are immediately removed. *)
  method delayed_apply 
    : 'b. ?folder:('b -> 'a -> 'b) -> 'b -> 'b Lazy.t
    = fun ?folder acc ->
      (* Redefine the folder in order to apply the thunk, then the folder: *)
      let folder =
	match folder with
	| None   -> (fun acc y -> acc)
	| Some f -> f
      in
      let folder acc (thunk, linear) = folder acc (thunk ()) in
      let ts = M.to_list container in
      let () = M.filter (fun (thunk, linear) -> not linear) container in
      let result = lazy (List.fold_left folder acc ts) in
      result
      
  method remove id =
    M.remove_by_id id container;
    revno <- revno + 1

  method get id = fst (M.get_by_id id container)
end (* class container *)

(* A special that deserves a special interface: *)
class unit_protected_container () =
 let fallback_default () = () in
 object (self)
  val container = M.create ()

  val mutable revno = 0
  method revno = revno

  method register_thunk : ?unprotect:unit -> ?one_shot:unit -> 'a t -> id
    = fun ?unprotect ?one_shot thunk ->
      let fallback = if unprotect=None then (Some fallback_default) else None in
      let id = M.push (dress_thunk ?fallback ?one_shot thunk) container in
      revno <- revno + 1;
      id

  method register_lazy : ?unprotect:unit -> 'a Lazy.t -> id
    = fun ?unprotect lazy_action ->
      let fallback = if unprotect=None then (Some fallback_default) else None in
      let thunk = of_lazy lazy_action in
      let id = M.push (dress_thunk ?fallback ~one_shot:() thunk) container in
      revno <- revno + 1;
      id

  method apply : unit -> unit
    = fun () ->
      let () = M.iter   (fun (thunk, linear) -> thunk ()) container in
      let () = M.filter (fun (thunk, linear) -> not linear) container in
      ()

  method remove id =
    M.remove_by_id id container;
    revno <- revno + 1

  method get id = fst (M.get_by_id id container)
end (* class container *)


end (* functor Make_class_with_discipline *)

module FIFO_class_here = Make_class_with_discipline (Container.Queue_with_identifiers)
module LIFO_class_here = Make_class_with_discipline (Container.Stack_with_identifiers)

class ['a] fifo_container ?fallback () =
 object
  inherit ['a] FIFO_class_here.container ?fallback ()
  method as_queue = container
end

class ['a] lifo_container ?fallback () =
 object
  inherit ['a] LIFO_class_here.container ?fallback ()
  method as_stack = container
end

(** [unit] and protected thunks with a slightly different interface: *)
class fifo_unit_protected_container () =
 object
  inherit FIFO_class_here.unit_protected_container ()
  method as_queue = container
end

(** [unit] and protected thunks with a slightly different interface: *)
class lifo_unit_protected_container () =
 object
  inherit LIFO_class_here.unit_protected_container ()
  method as_stack = container
end


IFDEF DOCUMENTATION_OR_DEBUGGING THEN
module Test = struct

(** {[
Thunk.Test.go () ;;
Applying `q' a first time:                                                                                                                                             ---                                                                                                                                                                    I'm the thunk no. 1 (linear:false)
I'm the thunk no. 2 (linear:true)
I'm the thunk no. 3 (linear:false)
I'm the thunk no. 4 (linear:false)
Applying `s' a first time:
---
I'm the thunk no. 4 (linear:false)
I'm the thunk no. 3 (linear:false)
I'm the thunk no. 2 (linear:true)
I'm the thunk no. 1 (linear:false)
Applying `q' a second time:
---
I'm the thunk no. 1 (linear:false)
I'm the thunk no. 3 (linear:false)
I'm the thunk no. 4 (linear:false)
Applying `s' a second time:
---
I'm the thunk no. 4 (linear:false)
I'm the thunk no. 3 (linear:false)
I'm the thunk no. 1 (linear:false)
Applying `q' a third time:
---
I'm the thunk no. 1 (linear:false)
I'm the thunk no. 4 (linear:false)
Applying `s' a third time:
---
I'm the thunk no. 4 (linear:false)
I'm the thunk no. 1 (linear:false)
  : unit = ()
]} *)
let go () =
  let make ?(linear=false) i =
    let thunk () = Printf.printf "I'm the thunk no. %d (linear:%b)\n" i linear in
    thunk
  in
  let q = new fifo_container () in
  let () = ignore (q#register_thunk (make 1)) in
  let () = ignore (q#register_thunk ~one_shot:() (make ~linear:true 2)) in
  let i3 = q#register_thunk (make 3) in
  let () = ignore (q#register_thunk (make 4)) in
  let s = new lifo_container () in
  let () = ignore (s#register_thunk (make 1)) in
  let () = ignore (s#register_thunk ~one_shot:() (make ~linear:true 2)) in
  let j3 = s#register_thunk (make 3) in
  let () = ignore (s#register_thunk (make 4)) in
  let () = Printf.printf "Applying `q' a first time:\n---\n" in
  let () = q#apply () in
  let () = Printf.printf "Applying `s' a first time:\n---\n" in
  let () = s#apply () in
  let () = Printf.printf "Applying `q' a second time:\n---\n" in
  let () = q#apply () in
  let () = Printf.printf "Applying `s' a second time:\n---\n" in
  let () = s#apply () in
  let () = q#remove i3 in
  let () = s#remove j3 in
  let () = Printf.printf "Applying `q' a third time:\n---\n" in
  let () = q#apply () in
  let () = Printf.printf "Applying `s' a third time:\n---\n" in
  let () = s#apply () in
  ()

end (* module Test *)
ENDIF
