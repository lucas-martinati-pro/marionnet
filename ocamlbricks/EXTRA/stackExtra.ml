(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009  Jean-Vincent Loddo

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


type 'a t = { mutable l : 'a list }
exception Empty
let create () = { l = [] }
let clear s = s.l <- []
let copy s = { l = s.l }
let push x s = s.l <- x :: s.l
let pop s = match s.l with x::xs -> s.l <- xs; x | [] -> raise Empty
let top s = match s.l with x::_  -> x            | [] -> raise Empty
let is_empty s = (s.l = [])
let length s = List.length s.l
let iter   f s = List.iter f s.l
let filter f s = (s.l <- List.filter f s.l)
let map    f s = (s.l <- List.map f s.l)
let fold   f x s = List.fold_left f x (s.l)
let rev s = (s.l <- List.rev s.l)
let rev_copy s = { l = List.rev s.l }

(** O(1) list conversion. *)
let to_list s = s.l
let of_list xs = { l = xs }

(* The push against nature (the appended element will be the last out): *)
let copush s x = (s.l <- List.append s.l [x])
