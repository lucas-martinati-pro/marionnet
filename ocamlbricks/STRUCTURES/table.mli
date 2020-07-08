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

(** Generalized hash tables, weak (ephemerons) or standard. *)

(* The type of immediate objects produced by `make': *)
type ('a,'b) t =
    < mem      : 'a -> bool;
      add      : 'a -> 'b -> unit;
      replace  : 'a -> 'b -> unit;
      (* --- *)
      add_list     : ('a * 'b) list -> unit;
      replace_list : ('a * 'b) list -> unit;
      (* --- *)
      find     : 'a -> 'b;
      find_all : 'a -> 'b list;
      find_opt : 'a -> 'b option;
      find_or_bind : 'a -> 'b lazy_t -> 'b;
      (* --- *)
      remove   : 'a -> unit;
      fold     : 's. ('a -> 'b -> 's -> 's) -> 's -> 's;
      iter     : ('a -> 'b -> unit) -> unit;
      length   : int;
      (* --- *)
      filter_map_inplace : ('a -> 'b -> 'b option) -> unit;
      (* --- *)
      to_list       : 'a list;
      to_assoc_list : ('a * 'b) list;
      to_hashtbl    : ('a, 'b) Hashtbl.t; (* a copy *)
      (* --- *)
      (* --- Maintenance --- *)
      (* Note:
          `clean' and `stats_alive' are meaningfull for weak tables.
          For hash tables `clean' do nothing while `stats_alive' is equivalent to `stats'. *)
      clean       : unit;
      stats       : Hashtbl.statistics;
      stats_alive : Hashtbl.statistics;
      is_weak     : bool;
      >

val make :
  ?weak:unit ->                    (* ephemerons *)
  ?identifier:('a -> int) ->       (* implies: hash ≜ (Hashtbl.hash ∘ identifier) and equality x y ≜ (identifier x)=(identifier y) *)
  ?equality:('a -> 'a -> bool) ->  (* instead of (=) *)
  ?size:int ->                     (* 0 *)
  ?init:('a * 'b) list ->          (* None *)
  unit -> ('a,'b) t

(* Example:

let xs = Array.init 3 (fun i -> Bytes.make 10 (Char.chr (65+i))) ;;
(* val xs : string array = [|"AAAAAAAAAA"; "BBBBBBBBBB"; "CCCCCCCCCC"|] *)

let t = Table.make ~weak:() ~equality:(==) () ;;
let () = Array.iter (fun x -> t#add x [x; Bytes.copy x]) xs ;;

t#mem "AAAAAAAAAA" ;;
(* - : bool = false *)

t#mem xs.(0);;
(* - : bool = true *)

t#to_list ;;
- : string list = ["CCCCCCCCCC"; "AAAAAAAAAA"; "BBBBBBBBBB"]

t#to_assoc_list ;;
(* - : (string * string list) list =
   [("CCCCCCCCCC", ["CCCCCCCCCC"; "CCCCCCCCCC"]);
    ("AAAAAAAAAA", ["AAAAAAAAAA"; "AAAAAAAAAA"]);
    ("BBBBBBBBBB", ["BBBBBBBBBB"; "BBBBBBBBBB"])] *)

t#stats ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 3; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|13; 3|]} *)

t#stats_alive ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 3; num_buckets = 16; max_bucket_length = 1; bucket_histogram = [|13; 3|]} *)

let xs = None ;;
(* val xs : 'a option = None *)

Gc.full_major () ;;

t#clean ;;
t#stats_alive ;;
(* - : Hashtbl.statistics = {Hashtbl.num_bindings = 0; num_buckets = 16; max_bucket_length = 0; bucket_histogram = [|16|]} *)

*)
