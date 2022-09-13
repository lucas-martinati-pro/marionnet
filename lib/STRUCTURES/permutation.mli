(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2018  Jean-Vincent Loddo

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

(** Bijections [0,n] -> [0,n] *)
type t = index array
 and index = int
 and length = int

(* --- *)
val identity    : length -> t
val shuffle     : length -> t
val reverse     : length -> t
val priority    : length -> index -> t
val priorities  : length -> index list -> t
val swap        : length -> (index * index) list -> t
val shift_left  : length -> int -> t
val shift_right : length -> int -> t

(* Does the array represent a bijection? *)
val check : index array -> bool

(* Raises Invalid_argument if the provided array doesn't represent a bijection: *)
val import : index array -> t

(* --- *)
val inverse : t -> t

(* append p1 p2 = Array.append p1 (translate (Array.length p1) p2)
    where:    q = translate k p   =>   q.(i) = p.(i) + k
   ---
   concat_list ps = List.fold_left append [] ps  (but implemented in a slightly more efficient way) *)
val append       : t -> t -> t
val concat_list  : t list  -> t
val concat_array : t array -> t

(* (compose t1 t2) means (t1; t2), i.e. is equivalent to perform t1 then t2. *)
val compose       : t -> t -> t
val compose_list  : t -> t list  -> t
val compose_array : t -> t array -> t


(* Compose.f t = compose t (f (Array.length t)) *)
module Compose : sig

  val shuffle     : t -> t
  val reverse     : t -> t
  val priority    : t -> index -> t

  (* Permutation.Array.priorities [|'a';'b';'c';'d';'e';'f';'g';'h'|] [3;5];;
     - : char array * Permutation.t = ([|'d'; 'f'; 'a'; 'b'; 'c'; 'e'; 'g'; 'h'|], [|3; 5; 0; 1; 2; 4; 6; 7|]) *)
  val priorities  : t -> index list -> t

  val swap        : t -> (index * index) list -> t
  val shift_left  : t -> int -> t
  val shift_right : t -> int -> t

end


module Array : sig

  val apply   : t -> 'a array -> 'a array
  val unapply : t -> 'a array -> 'a array (* unapply p xs = apply (inverse p) xs *)

  (* map p f xs = unapply p (Array.map f (apply p xs)) *)
  val map   : t -> ('a -> 'b) -> 'a array -> 'b array


  (* mapi p f xs = unapply p (Array.mapi (fun j x -> f p.(j) x) (apply p xs))
     ---
     let xs = [|'A'; 'B'; 'C'; 'D'; 'E'; 'F'; 'G'; 'H'; 'I'; 'J'|];;

     Array.mapi (fun i x -> let () = Printf.printf "%d  " i in (i,Char.escaped x)) xs ;;
     0  1  2  3  4  5  6  7  8  9  - : (int * bytes) array =
     [|(0, "A"); (1, "B"); (2, "C"); (3, "D"); (4, "E"); (5, "F"); (6, "G"); (7, "H"); (8, "I"); (9, "J")|]

     module P = Permutation ;;
     P.Array.mapi (P.priority 10 3) (fun i x -> let () = Printf.printf "%d  " i in (i,Char.escaped x)) xs ;;
     3  0  1  2  4  5  6  7  8  9  - : (int * bytes) array =
     [|(0, "A"); (1, "B"); (2, "C"); (3, "D"); (4, "E"); (5, "F"); (6, "G"); (7, "H"); (8, "I"); (9, "J")|]

     *)
  val mapi  : t -> (int -> 'a -> 'b) -> 'a array -> 'b array


  (* iteri p f xs = Array.iteri (fun j x -> f p.(j) x) (apply p xs)
     ---
     let xs = [|'A'; 'B'; 'C'; 'D'; 'E'; 'F'; 'G'; 'H'; 'I'; 'J'|];;

     Array.iteri (Printf.printf "%d:%c  ") xs  ;;
     0:A  1:B  2:C  3:D  4:E  5:F  6:G  7:H  8:I  9:J  - : unit = ()

     module P = Permutation ;;
     P.Array.iteri (P.priority 10 3) (Printf.printf "%d:%c  ") xs  ;;
     3:D  0:A  1:B  2:C  4:E  5:F  6:G  7:H  8:I  9:J  - : unit = () *)
  val iteri : t -> (int -> 'a -> unit) -> 'a array -> unit

  (* foldi p f s0 xs = Array.fold_lefti (fun j s x -> f p.(j) s x) s0 (apply p xs) *)
  val foldi : t -> (int -> 'a -> 'b -> 'a) -> 'a -> 'b array -> 'a

  (* --- *)
  val sort : ?stable:unit -> ?compare:('a -> 'a -> int) -> 'a array -> 'a array * t
  (* --- *)
  val shuffle     : 'a array -> 'a array * t
  val reverse     : 'a array -> 'a array * t
  val priority    : 'a array -> index -> 'a array * t
  val priorities  : 'a array -> index list -> 'a array * t
  val swap        : 'a array -> (index * index) list -> 'a array * t
  val shift_left  : 'a array -> int -> 'a array * t
  val shift_right : 'a array -> int -> 'a array * t


  module In_place : sig

    val apply   : t -> 'a array -> unit
    val unapply : t -> 'a array -> unit
    (* --- *)
    val sort : ?stable:unit -> ?compare:('a -> 'a -> int) -> 'a array -> unit * t
    (* --- *)
    val shuffle     : 'a array -> unit * t
    val reverse     : 'a array -> unit * t
    val priority    : 'a array -> index -> unit * t
    val priorities  : 'a array -> index list -> unit * t
    val swap        : 'a array -> (index * index) list -> unit * t
    val shift_left  : 'a array -> int   -> unit * t
    val shift_right : 'a array -> int   -> unit * t

  end (* Array.In_place *)

end (* Array *)
