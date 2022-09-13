(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2020  Jean-Vincent Loddo
   Copyright (C) 2020  Université Sorbonne Paris Nord

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

type 'a t = 'a -> bool
type ('a,'b) t2 = 'a -> 'b -> bool

(* Make the predicate of logical implication. Example:
     List.filter ((fun x -> x>10) => (fun x -> x mod 2 = 1)) [8;9;10;11;12;13;14] ;;
     let open Pred in List.filter ((gt 10) => odd) [8;9;10;11;12;13;14] ;;
     - : int list = [8; 9; 10; 11; 13] *)
val ( => )   : ('a -> bool) -> ('a -> bool) -> 'a -> bool
val implies  : ('a -> bool) -> ('a -> bool) -> 'a -> bool
val implies2 : ('a -> 'b -> bool) -> ('a -> 'b -> bool) -> 'a -> 'b -> bool

val or2  : ('a -> bool) -> ('a -> bool) -> 'a -> bool
val and2 : ('a -> bool) -> ('a -> bool) -> 'a -> bool

val or3  : ('a -> bool) -> ('a -> bool) -> ('a -> bool) -> 'a -> bool
val and3 : ('a -> bool) -> ('a -> bool) -> ('a -> bool) -> 'a -> bool

val disjunction : ('a -> bool) list -> 'a -> bool
val conjunction : ('a -> bool) list -> 'a -> bool

val lt : 'a -> 'a -> bool
val eq : 'a -> 'a -> bool
val ne : 'a -> 'a -> bool
val le : 'a -> 'a -> bool
val gt : 'a -> 'a -> bool
val ge : 'a -> 'a -> bool

val even : int -> bool
val odd  : int -> bool

val not : ('a -> bool) -> 'a -> bool



