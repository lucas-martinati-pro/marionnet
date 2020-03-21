(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007 Jean-Vincent Loddo

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

(** Basic fix point operators.

{b Example}:
{[# let fact self = fun x -> if (x=0) then 1 else x * (self (x-1)) ;;
val fact : (int -> int) -> int -> int = <fun>

# let f = fix fact;;
val f : int -> int = <fun>

# f 5;;
  : int = 120
]}*)
let rec fix f =
 f (fun x -> (fix f) x)


(** Fix point operator for making function requiring a parameter (the "{e environment}").

{b Example}:
{[# let fact y self = fun x -> if (x=0) then y else x * (self y (x-1)) ;;
val fact : int -> (int -> int -> int) -> int -> int = <fun>

# let f y = (efix fact y) ;;
val f : int -> int -> int = <fun>

# f 2 5;;
  : int = 240

# f 3 5;;
  : int = 360
]}*)
let rec efix f e =
(f e) (fun y x -> (efix f y) x)


(** Fix point operator with an environment and a treatment (a "{e cure}")
    to perform {b before} each recursive call. The typical example is
    the "memoisation" cure useful for making memoised functions defined
    by a recursive definition (each recursive call must share the same
    hash table).

{b Example}:
{[# let fact y self = fun x -> if (x=0) then y else x * (self y (x-1)) ;;
val fact : int -> (int -> int -> int) -> int -> int = <fun>

(* The cure change the sign at the end of each iteration *)
# let f y = (ecfix (fun g x -> (g x)*(-1)) fact y) ;;
val f : int -> int -> int = <fun>

# f 2 3;;
  : int = 12    (* because of an even number (4) of iterations *)

# f 2 4;;
  : int = -48   (* because of an odd number (5) of iterations *)

# f 2 5;;
  : int = 240   (* because of an even number (6) of iterations *)

(* Tracing the unfolding *)
# let f y = (Fix.ecfix (fun g x -> (print_int x; print_newline ()); (g x)*(-1)) fact y) ;;

# f 2 5;;
5
4
3
2
1
0
  : int = 240
]}*)
let rec ecfix c f e =
 (fun g -> c ((f e) g)) (fun y x -> (ecfix c f y) x)

(** Find the fixpoint using the polymorphic equality: *)
let find ?(equals=(=)) ?(loops_limit=max_int) f x0 =
 let rec loop i x0 = 
   let x1 = f x0 in
   if (equals x0 x1) || (i>=loops_limit) then x1 else loop (i+1) x1
 in
 loop 1 x0

