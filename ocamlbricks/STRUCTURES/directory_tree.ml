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

(* --- *)
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
     module Stair_choices : (Sowide.SOWIDE with type 'a t = 'a Stair.t)
     module File_choices  : (Sowide.SOWIDE with type 'x t = 'x File.t)
  end
= struct

  module Stair_choices : (Sowide.SOWIDE with type 'a t = 'a Stair.t) =
    Sowide.MAKE (struct type 'a t = 'a Stair.t let compare = Stair.compare end)

  module File_choices : (Sowide.SOWIDE with type 'x t = 'x File.t) =
    Sowide.MAKE (struct type 'x t = 'x File.t let compare = File.compare end)

  (* --- *)
  type ('a,'x) t =
    Dir of
       ('x File.t array) *              (* unprefixed vars, i.e. freely available resources or "files" *)
      (('a Stair.t * ('a,'x) t) array)  (* prefixed ordered choices (or "subdirectories") *)

  let return a x =
    Dir ([||], [| (a, Dir ([|x|], [||])) |])

  let files   (Dir (xs, pts)) = xs
  let subdirs (Dir (xs, pts)) = pts

  let rec all_files (Dir (xs, pts)) =
    let _stair_choices, ts = ArrayExtra.split pts in
    Array.concat (xs::(Array.to_list (Array.map (all_files) ts)))

  let rec all_stairs (Dir (_xs, pts)) =
    let stair_choices, ts = ArrayExtra.split pts in
    Array.concat (stair_choices::(Array.to_list (Array.map (all_stairs) ts)))

  let stairs_lengths t =
    let rec loop (depth) (Dir (xs, pts)) =
      let here = if Array.length xs = 0 then [||] else [|depth|] in
      if Array.length pts = 0 then here else (* continue: *)
      let stair_choices, ts = ArrayExtra.split pts in
      let sub = Array.map (loop (depth+1)) ts in
      Array.concat (here::(Array.to_list sub))
    in
    loop 0 t

  (* --- Sums: *)

  let zero = Dir ([||], [||])

  let rec plus (Dir (x1s, pt1s): ('a,'x) t) (Dir (x2s, pt2s): ('a,'x) t) : ('a,'x) t =
    let x12s = File_choices.merge x1s x2s in
    let pt12s = Flip.flip2 ArrayExtra.fold_lefti (pt2s) (pt1s) (fun i (pt2s) (p1, t1) -> (* make now a new pts2: *)
      match Stair_choices.With_projection.locate_or_split (fst) pt2s p1 with
      | Either.Right j ->
          let s12 = plus (snd pt1s.(i)) (snd pt2s.(j)) in
          (* In place! why not? *)
          let () = pt2s.(j) <- (p1, s12) in
          pt2s
      (* --- *)
      | Either.Left (pt2s_A, pt2s_B) -> Array.concat [pt2s_A; [| (p1, t1) |];  pt2s_B]
      )
    in
    Dir (x12s, pt12s)

  let array_sum : ('a, 'x) t array -> ('a, 'x) t =
      fun ts -> Array.fold_left (plus) (zero) ts

  let list_sum : ('a, 'x) t list -> ('a, 'x) t =
      fun ts -> List.fold_left (plus) (zero) ts

  let rec map_files (f: 'x File.t -> 'y File.t) (Dir (xs, pts): ('a,'x) t) : ('a,'y) t =
    let xs = Array.map (f) xs in
    let stair_choices, ts = ArrayExtra.split pts in
    let txs = Array.map (map_files f) ts in
    let r = Dir (xs, ArrayExtra.combine stair_choices txs) in
    r

  let rec iter_files (f: 'x File.t -> unit) (Dir (xs, pts): ('a,'x) t) : unit =
    let () = Array.iter (f) xs in
    let stair_choices, ts = ArrayExtra.split pts in
    Array.iter (iter_files f) ts

  (* val choose : ('a,'x) t -> ('x File.t) option *)
  let rec choose (Dir (xs, pts): ('a,'x) t) : ('x File.t) option =
    let n = Array.length xs in
    if n>0 then
      let j = Random.int n in
      Some (xs.(j))
    else (* continue with n=0: *)
    let d = Array.length pts in
    if d=0 then None else (* continue with d>0: *)
    let i = Random.int d in
    choose (snd pts.(i))

  let prepend (stair) t = Dir ([||], [|(stair, t)|])

end (* MAKE_additive *)

(* --------------------------- *)
(*          Both               *)
(*  Additive & Multiplicative  *)
(* --------------------------- *)

(* A "file" is a zipped functor (with a few exceptions, the result of a construction of the Sexpr module): *)
module type ZIPPED_FUNCTOR =
   sig
     type 'a t
     val map : ('a -> 'b) -> 'a t -> 'b t
     (* --- *)
     val compare : 'a t -> 'a t -> int
     (* --- *)
     val zip   : ('a t * 'b t) -> ('a * 'b) t
     val unzip : ('a * 'b) t -> 'a t * 'b t
     (* --- *)
     val fst   : ('a * 'b) t -> 'a t
     val snd   : ('a * 'b) t -> 'b t
     (* --- *)
   end (* ZIPPED *)

module MAKE (Stair: ORDERED_FUNCTOR) (File: ZIPPED_FUNCTOR)
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
= struct

  include MAKE_additive (Stair) (File)

  (* --- *)
  module Products = struct

  let rec left_injection (file_zip) (x1s: 'x File_choices.ts) (Dir (x2s, pt2s): ('a, 'y) t) : ('a, 'x * 'y) t =
    let x12s : ('x * 'y) File_choices.ts = Array.map (file_zip) (ArrayExtra.product2 x1s x2s) in
    let pt12s = Array.map (fun (p2,t2) -> (p2, left_injection (file_zip) x1s t2)) pt2s in
    Dir (x12s, pt12s)

  let rec right_injection (file_zip) (x2s: 'y File_choices.ts) (Dir (x1s, pt1s): ('a, 'x) t) : ('a, 'x * 'y) t =
    let x12s : ('x * 'y) File_choices.ts = Array.map (file_zip) (ArrayExtra.product2 x1s x2s) in
    let pt12s = Array.map (fun (p1,t1) -> (p1, right_injection (file_zip) x2s t1)) pt1s in
    Dir (x12s, pt12s)

  let rec times (file_zip) ((Dir (x1s, pt1s) as t1): ('a, 'x) t) ((Dir (x2s, pt2s) as t2): ('a, 'y) t) : ('a, 'x * 'y) t =
    (* --- *)
    if (Array.length pt1s) = 0 then (if (Array.length x1s) = 0 then zero else (left_injection  (file_zip) x1s t2)) else (* continue: *)
    if (Array.length pt2s) = 0 then (if (Array.length x2s) = 0 then zero else (right_injection (file_zip) x2s t1)) else (* continue: *)
    (* --- *)
    (* Cartesian product of "files": *)
    let x12s : ('x * 'y) File_choices.ts =
      Array.map (file_zip) (ArrayExtra.product2 x1s x2s)
    in
    (* --- *)
    (* Cartesian product of "subdirectories": *)
    let pt1_pt2_s : (('a Stair.t * ('a,'x) t) * ('a Stair.t * ('a,'y) t)) array =
      ArrayExtra.product2 pt1s pt2s in
    (* --- *)
    let pt12s : ('a Stair.t * ('a, 'x * 'y) t) array = Flip.flip Array.map (pt1_pt2_s) (fun ((p1,t1), (p2,t2)) ->
      match Stair.compare (p1) (p2) with
      |  0 -> (p1, times (file_zip) t1 t2) (* lock unicity (in the sequence) *)
      | -1 -> (p1, times (file_zip) t1 (Dir (x2s, [|(p2,t2)|])))
      |  1 -> (p2, times (file_zip) (Dir (x1s, [|(p1,t1)|])) t2)
      | _ -> assert false
      )
    in
    (* --- *)
    let t12s : (('a, 'x * 'y) t) array = Array.map (fun pt12 -> Dir (x12s, [|pt12|])) pt12s in
    plus (Dir (x12s, [||])) (array_sum t12s)

  let rec split (file_unzip) (Dir (xys, pts): ('a, 'x * 'y) t) : ('a,'x) t * ('a,'y) t =
    let xs, ys = ArrayExtra.split (Array.map (file_unzip) xys) in
    let stair_choices, ts = ArrayExtra.split pts in
    let txs, tys = ArrayExtra.split (Array.map (split file_unzip) ts) in
    let rx = Dir (xs, ArrayExtra.combine stair_choices txs) in
    let ry = Dir (ys, ArrayExtra.combine stair_choices tys) in
    (rx, ry)

  let rec fst_prj (file_fst) (Dir (xys, pts): ('a, 'x * 'y) t) : ('a,'x) t =
    let xs = Array.map (file_fst) xys in
    let stair_choices, ts = ArrayExtra.split pts in
    let txs = Array.map (fst_prj file_fst) ts in
    let rx = Dir (xs, ArrayExtra.combine stair_choices txs) in
    rx

  let rec snd_prj (file_snd) (Dir (xys, pts): ('a, 'x * 'y) t) : ('a,'y) t =
    let ys = Array.map (file_snd) xys in
    let stair_choices, ts = ArrayExtra.split pts in
    let tys = Array.map (snd_prj file_snd) ts in
    let ry = Dir (ys, ArrayExtra.combine stair_choices tys) in
    ry

  end (* Products *)

  (* val times : ?zip:('x File.t * 'y File.t -> ('x * 'y) File.t) -> ('a,'x) t -> ('a,'y) t -> ('a, 'x * 'y) t *)
  let times ?file_zip =
    match file_zip with
    | None            -> Products.times (File.zip)
    | Some (file_zip) -> Products.times (file_zip)

  let split ?file_unzip  =
    match file_unzip with
    | None              -> Products.split (File.unzip)
    | Some (file_unzip) -> Products.split (file_unzip)

  let fst_prj ?file_fst  =
    match file_fst with
    | None            -> Products.fst_prj (File.fst)
    | Some (file_fst) -> Products.fst_prj (file_fst)

  let snd_prj ?file_snd  =
    match file_snd with
    | None            -> Products.snd_prj (File.snd)
    | Some (file_snd) -> Products.snd_prj (file_snd)

  let rec map_file_contents (f: 'x -> 'y) (Dir (xs, pts): ('a,'x) t) : ('a,'y) t =
    let xs = Array.map (File.map f) xs in
    let stair_choices, ts = ArrayExtra.split pts in
    let txs = Array.map (map_file_contents f) ts in
    let r = Dir (xs, ArrayExtra.combine stair_choices txs) in
    r

  (* --- *)

  let fst = fst_prj
  let snd = snd_prj

end (* MAKE *)



