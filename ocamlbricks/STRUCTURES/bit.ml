(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2010 Jean-Vincent Loddo

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

(* Example: first_powers_of_2 ~length:9 = [256; 128; 64; 32; 16; 8; 4; 2; 1] *)
let first_powers_of_2 ~length =
  let rec loop acc j i =
    if i=length then acc else loop (j::acc) (j*2) (i+1) in
  loop [] 1 0 ;;

(* Example: first_powers_of_2_until ~covered_int:89 = [64; 32; 16; 8; 4; 2; 1] *)
let first_powers_of_2_until ~covered_int =
  let rec loop acc j i =
    if j>covered_int then acc else loop (j::acc) (j*2) (i+1) in
  loop [] 1 0 ;;

(** Convert an integer (supposed unsigned) in a list of bits, where each bit is
    represented as a boolean value. The list starts with the more relevant bit and
    ends with the less relevant. The length of the list is automatically minimal,
    hence the first element of the result will always be [true] (for inputs greater
    than [0]). Setting the optional
    parameter [?length] to a value greater than this minimal value, the {e head} of the list will
    be completed by zeros ([false]). On the other hand, setting [?length] to a value lesser
    than the minimal, only the last (less relevant) bits will be returned.
    {b Examples}:
{[# Bit.bits_as_booleans_of_int 34 ;;
  : bool list = [true; false; false; false; true; false]

# Bit.bits_as_booleans_of_int ~length:8 34 ;;
  : bool list = [false; false; true; false; false; false; true; false]

# Bit.bits_as_booleans_of_int ~length:5 34 ;;
  : bool list = [false; false; false; true; false]
]}*)
let bits_as_booleans_of_int ?length i =
 let powers = match length with
 | None        -> first_powers_of_2_until ~covered_int:i
 | Some length -> first_powers_of_2 ~length
 in
 List.rev (snd (List.fold_left (fun (r,l) x -> ((r mod x),((r/x)=1)::l)) (i,[]) powers))


(** The inverse of {!Bit.bits_as_booleans_of_int}: convert a list of booleans in an unsigned integer. *)
let int_of_bits_as_booleans (xs:bool list) =
 let powers = first_powers_of_2 ~length:(List.length xs) in
 let ys = List.combine xs powers in
 List.fold_left (fun acc (x,y) -> acc + if x then y else 0) 0 ys


(** Similar to {!Bit.bits_as_booleans_of_int}, but the result is a list of
    integers (in [{0,1}]).
{b Examples}:
{[# Bit.bits_as_integers_of_int 34 ;;
  : int list = [1; 0; 0; 0; 1; 0]

# Bit.bits_as_integers_of_int ~length:8 34 ;;
  : int list = [0; 0; 1; 0; 0; 0; 1; 0]

# Bit.bits_as_integers_of_int ~length:5 34 ;;
  : int list = [0; 0; 0; 1; 0]
]} *)
let bits_as_integers_of_int ?length i =
 List.map (function false->0|true->1) (bits_as_booleans_of_int ?length i)


(** The inverse of {!Bit.bits_as_integers_of_int}. *)
let int_of_bits_as_integers (xs:int list) =
 int_of_bits_as_booleans
    (List.map
       (function 0->false | 1->true | _ -> invalid_arg "Bit.int_of_bits_as_integers")
       xs)
