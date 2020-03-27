(* This file is part of ocamlbricks
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

(** Little trick allowing to write the first functional argument
    of a 2nd order function, at the end of the syntactic construction.
    The name `flip' is justified by considering the curryfied version
    of the argument, even for flip2 and flip3.
    For instance, considering:

      (1)  List.map2 : ('a -> 'b -> 'c) -> 'a list -> 'b list -> 'c list

    as it was (curryfying after the functional argument):

      (2)  List.map2 : ('a -> 'b -> 'c) * ('a list * 'b list) -> 'c list

    we have:

      (3)  (Flip.flip2) (List.map2) : 'a list -> 'b list -> ('a -> 'b -> 'c) -> 'c list

    as it was (curryfying):

      (4)  (Flip.flip2) (List.map2) : ('a list * 'b list) * ('a -> 'b -> 'c) -> 'c list

    So, modulo curryfication, (4) is the flipped version of (2) and (3) is the flipped
    version of (1).
    *)

val flip  : ('f -> 'x1 -> 'y)                ->  ('x1 -> 'f -> 'y)
val flip2 : ('f -> 'x1 -> 'x2 -> 'y)         ->  ('x1 -> 'x2 -> 'f -> 'y)
val flip3 : ('f -> 'x1 -> 'x2 -> 'x3 -> 'y)  ->  ('x1 -> 'x2 -> 'x3 -> 'f -> 'y)

(* Examples:

    (Flip.flip) (List.map) [0; 2; 4] (fun x ->
        (* A lot of long and useful code here *)
        x+1) ;;
    - : int list = [1; 3; 5]

    (Flip.flip) (List.filter) [0; 2; 4] (fun x ->
        (* A lot of long and useful code here *)
        x mod 4 = 0) ;;
    - : int list = [0; 4]


    (Flip.flip2) (List.map2) [0; 2; 4] [1; 3; 5] (fun x y ->
        (* A lot of long and useful code here *)
        x+y) ;;
    - : int list = [1; 5; 9]

*)
