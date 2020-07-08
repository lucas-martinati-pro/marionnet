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

(* val ( => ) : ('a -> bool) -> ('a -> bool) -> 'a -> bool *)
let (=>) p0 p1 = fun x -> if (not (p0 x)) then true else (p1 x)

(* val implies : ('a -> bool) -> ('a -> bool) -> 'a -> bool *)
let implies  p0 p1 = fun x -> if (not (p0 x)) then true else (p1 x)

(* val implies2 : ('a -> 'b -> bool) -> ('a -> 'b -> bool) -> 'a -> 'b -> bool *)
let implies2 p0 p1 = fun x y -> if (not (p0 x y)) then true else (p1 x y)

(* val or2  : ('a -> bool) -> ('a -> bool) -> 'a -> bool *)
(* val and2 : ('a -> bool) -> ('a -> bool) -> 'a -> bool *)

let  or2 p0 p1 = fun x -> if (p0 x) then true else (p1 x)
let and2 p0 p1 = fun x -> if (p0 x) then (p1 x) else false

(* val or3  : ('a -> bool) -> ('a -> bool) -> ('a -> bool) -> 'a -> bool *)
(* val and3 : ('a -> bool) -> ('a -> bool) -> ('a -> bool) -> 'a -> bool *)

let  or3 p0 p1 p2 = fun x -> if (p0 x) then true else (or2 p1 p2 x)
let and3 p0 p1 p2 = fun x -> if (p0 x) then (and2 p1 p2 x) else false

(* val disjunction : ('a -> bool) list -> 'a -> bool *)
let disjunction ps x = List.exists  (fun p -> p x) ps

(* val conjunction : ('a -> bool) list -> 'a -> bool *)
let conjunction ps x = List.for_all (fun p -> p x) ps

(* All of type: 'a -> 'a -> bool *)
let lt x y = (y < x)
let eq x y = (y = x)
let ne x y = (y != x)
let le x y = (y <= x)
let gt x y = (y > x)
let ge x y = (y >= x)

let even x = (x mod 2 = 0)
let odd  x = (x mod 2 = 1)

(* val not : ('a -> bool) -> 'a -> bool *)
let not p = fun x -> not (p x)
