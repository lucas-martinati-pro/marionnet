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

(** Directory-like data structure. *)

(* --------------------------- *)
(*          Additive           *)
(* --------------------------- *)

(* A "stair" (subdirectory) is a ordered functor: *)
module type ORDERED_FUNCTOR =
  sig
    type 'a t
    val compare : 'a t -> 'a t -> int
  end

module MAKE_additive (Stair: ORDERED_FUNCTOR) (File: ORDERED_FUNCTOR)
: sig
     type ('a, 'x) t =
        Dir of
          ('x File.t array) *               (* unprefixed vars, i.e. freely available resources or "files" *)
          (('a Stair.t * ('a,'x) t) array)  (* prefixed ordered choices (or "subdirectories") *)
     (* --- *)
     val return    : 'a Stair.t -> 'x File.t -> ('a,'x) t
     val prepend   : 'a Stair.t -> ('a,'x) t -> ('a,'x) t
     (* --- *)
     val files     : ('a,'x) t -> ('x File.t) array
     val subdirs   : ('a,'x) t -> ('a Stair.t * ('a,'x) t) array
     val all_files : ('a,'x) t -> ('x File.t) array
     val all_stairs: ('a,'x) t -> ('a Stair.t) array
     (* --- *)
     val stairs_lengths : ('a,'x) t -> int array
     (* --- *)
     val iter_files        : ('x File.t -> unit) -> ('a,'x) t -> unit
     val map_files         : ('x File.t -> 'y File.t) -> ('a,'x) t -> ('a,'y) t
     (* --- *)
     val zero      : ('a,'x) t
     val plus      : ('a,'x) t -> ('a,'x) t -> ('a,'x) t
     val array_sum : ('a,'x) t array -> ('a,'x) t
     val list_sum  : ('a,'x) t list  -> ('a,'x) t
     val choose    : ('a,'x) t -> ('x File.t) option
     (* --- *)
  end


(* A "file" is a zipped functor (with a few exceptions, the result of a construction of the Sexpr module): *)
module type ZIPPED_FUNCTOR =
   sig
     type 'a t
     val map : ('a -> 'b) -> 'a t -> 'b t
     val compare : 'a t -> 'a t -> int
     (* --- *)
     val zip   : ('a t * 'b t) -> ('a * 'b) t
     val unzip : ('a * 'b) t -> 'a t * 'b t
     (* --- *)
     val fst   : ('a * 'b) t -> 'a t
     val snd   : ('a * 'b) t -> 'b t
     (* --- *)
   end (* ZIPPED *)


(* --------------------------- *)
(*          Both               *)
(*  Additive & Multiplicative  *)
(* --------------------------- *)

module MAKE (Stair: ORDERED_FUNCTOR) (File: ZIPPED_FUNCTOR)
: sig
     type ('a, 'x) t =
        Dir of
           ('x File.t array) *              (* unprefixed vars, i.e. freely available resources or "files" *)
          (('a Stair.t * ('a,'x) t) array)  (* prefixed ordered choices (or "subdirectories") *)
     (* --- *)
     val return    : 'a Stair.t -> 'x File.t -> ('a,'x) t
     val prepend   : 'a Stair.t -> ('a,'x) t -> ('a,'x) t
     (* --- *)
     val files     : ('a,'x) t -> ('x File.t) array
     val subdirs   : ('a,'x) t -> ('a Stair.t * ('a,'x) t) array
     val all_files : ('a,'x) t -> ('x File.t) array
     val all_stairs: ('a,'x) t -> ('a Stair.t) array
     (* --- *)
     val stairs_lengths : ('a,'x) t -> int array
     (* --- *)
     val iter_files        : ('x File.t -> unit) -> ('a,'x) t -> unit
     val map_files         : ('x File.t -> 'y File.t) -> ('a,'x) t -> ('a,'y) t
     val map_file_contents : ('x -> 'y) -> ('a,'x) t -> ('a,'y) t
     (* --- *)
     val zero      : ('a,'x) t
     val plus      : ('a,'x) t -> ('a,'x) t -> ('a,'x) t
     val array_sum : ('a,'x) t array -> ('a,'x) t
     val list_sum  : ('a,'x) t list  -> ('a,'x) t
     val choose    : ('a,'x) t -> ('x File.t) option
     (* --- *)
     val times     : ?file_zip   :('x File.t * 'y File.t -> ('x * 'y) File.t) -> (**) ('a,'x) t -> ('a,'y) t -> ('a, 'x * 'y) t
     val split     : ?file_unzip :(('x * 'y) File.t -> 'x File.t * 'y File.t) -> (**) ('a, 'x * 'y) t -> ('a,'x) t * ('a,'y) t
     val fst       : ?file_fst   :(('x * 'y) File.t -> 'x File.t)             -> (**) ('a, 'x * 'y) t -> ('a,'x) t
     val snd       : ?file_snd   :(('x * 'y) File.t -> 'y File.t)             -> (**) ('a, 'x * 'y) t -> ('a,'y) t
  end


(* Example:

module M = Sexpr_dirs.MAKE (struct type 'a t = int let compare = compare end) (Sexpr) ;;

let x = M.return 10 (Sexpr.return 'x') ;;
let xx = M.times x x ;;

M.subdirs xx ;;
(* - : (int * ('_a, char * char) M.t) array = [|(10, <abstr>)|] *)

M.files (snd (M.subdirs xx).(0)) ;;
(* - : (char * char) Sexpr.t array = [|Sexpr.Cons (Sexpr.Atom 'x', Sexpr.Atom 'x')|] *)

let x0 = M.times x M.zero ;;
M.subdirs x0 ;;

x0 = M.zero ;;
(* - : bool = true *)

let x = M.return 10 (Sexpr.return 'x') ;;
let y = M.return 20 (Sexpr.return 'y') ;;
let z = M.return 15 (Sexpr.return 'z') ;;
let t = M.return 25 (Sexpr.return 't') ;;

let uv = M.return 16 (Sexpr.return ('u','v')) ;;

M.plus uv (M.times (M.plus x y) (M.plus z t)) ;;
(* - : ('_a, char * char) M.t =
M.Dir ([||],
 [|(10, M.Dir ([||],
          [|(15, M.Dir ([|Sexpr.Cons (Sexpr.Atom 'x', Sexpr.Atom 'z')|], [||]));
            (25, M.Dir ([|Sexpr.Cons (Sexpr.Atom 'x', Sexpr.Atom 't')|], [||]))|]));
   (15, M.Dir ([||],
          [|(20, M.Dir ([|Sexpr.Cons (Sexpr.Atom 'y', Sexpr.Atom 'z')|], [||]))|]));
   (16, M.Dir ([|Sexpr.Atom ('u', 'v')|],
          [||]));
   (20, M.Dir ([||],
          [|(25, M.Dir ([|Sexpr.Cons (Sexpr.Atom 'y', Sexpr.Atom 't')|], [||]))|]))|])
*)


*)
