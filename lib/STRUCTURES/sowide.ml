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


(** (So)rted arrays (wi)thout (d)uplicat(e)s.
    Used as of polymorphic sets, this structure offer an efficient procedure for splitting
    the array into two parts corresponding to the lower-bounds and the upper-bounds of a
    pivot value. *)

(* --- *)

(* Similar to Set.OrderedType but for functors, i.e. parametric types: *)
module type ORDERED_FUNCTOR =
  sig
   type 'a t
   val compare : 'a t -> 'a t -> int
  end

(* Output signature: *)
module type SOWIDE =
  sig
    type 'a t
     and 'a ts = 'a t array
    (* --- *)
     and a = index
     and b = index
     and found = index
     and index = int
    (* --- *)
    val compare : 'a t -> 'a t -> int
    (* --- *)
    val make            : 'a t array -> 'a ts
    val merge           : 'a t array -> 'a t array -> 'a ts
    val mem             : ?a:index -> ?b:index -> 'a t -> 'a ts -> bool
    val find_opt        : ?a:index -> ?b:index -> 'a ts -> 'a t -> found option
    val locate          : ?a:index -> ?b:index -> 'a ts -> 'a t -> (a * b, found) Either.t
    val locate_pedantic : ?a:index -> ?b:index -> 'a ts -> 'a t -> (((a, b) Either.t, a * b) Either.t, found) Either.t
    val locate_or_split : ?a:index -> ?b:index -> 'a ts -> 'a t -> ('a ts * 'a ts, found) Either.t
    (* --- *)
    val substract : 'a t array -> 'a t array -> 'a t array

    (* Modulo a projection of elements (we suppose the array being ordered with this same projection): *)
    module With_projection : sig
      val make            : ('a -> 'b t) -> 'a array -> 'a array
      val merge           : ('a -> 'b t) -> 'a array -> 'a array -> 'a array
      val mem             : ?a:index -> ?b:index -> ('a -> 'b t) -> 'b t -> 'a array -> bool
      val find_opt        : ?a:index -> ?b:index -> ('a -> 'b t) -> 'a array -> 'b t -> found option
      val locate          : ?a:index -> ?b:index -> ('a -> 'b t) -> 'a array -> 'b t -> ((a * b), found) Either.t
      val locate_pedantic : ?a:index -> ?b:index -> ('a -> 'b t) -> 'a array -> 'b t -> (((a, b) Either.t, a * b) Either.t, found) Either.t
      val locate_or_split : ?a:index -> ?b:index -> ('a -> 'b t) -> 'a array -> 'b t -> ('a array * 'a array, found) Either.t
    end (* With_projection *)
  end

(* Make (So)rted arrays (wi)thout (d)uplicat(e)s *)
module MAKE (Type : ORDERED_FUNCTOR) : SOWIDE with type 'a t = 'a Type.t = struct

  type 'a t  = 'a Type.t
   and 'a ts = 'a t array
    (* --- *)
   and a = index
   and b = index
   and found = index
   and index = int

  let compare = Type.compare

  (* val sort_uniq : 'a t array -> 'a t array *)
  let sort_uniq xs =
    let nxs = Array.length xs in
    if nxs = 0 then xs else
    let zs = Array.to_list xs in
    let zs = List.sort_uniq (Type.compare) (zs) in
    Array.of_list zs

  (* val sort_uniq_prj : ('a -> t) -> 'a array -> 'a array -> 'a array *)
  let sort_uniq_prj prj xs =
    let nxs = Array.length xs in
    if nxs = 0 then xs else
    let zs = Array.to_list xs in
    let zs = List.sort_uniq (fun x y -> Type.compare (prj x) (prj y)) (zs) in
    Array.of_list zs

  let make = sort_uniq

  (* val merge : 'a t array -> 'a t array -> 'a t array *)
  let merge xs ys =
    let nxs = Array.length xs in
    if nxs = 0 then ys else
    let nys = Array.length ys in
    if nys = 0 then xs else
    let xs = Array.to_list xs in
    let ys = Array.to_list ys in
    let zs = if nxs < nys then (List.append xs ys) else (List.append ys xs) in
    let zs = List.sort_uniq (Type.compare) (zs) in
    Array.of_list zs

  (* val merge_prj : ('a -> t) -> 'a array -> 'a array -> 'a array *)
  let merge_prj prj xs ys =
    let nxs = Array.length xs in
    if nxs = 0 then ys else
    let nys = Array.length ys in
    if nys = 0 then xs else
    let xs = Array.to_list xs in
    let ys = Array.to_list ys in
    let zs = if nxs < nys then (List.append xs ys) else (List.append ys xs) in
    let zs = List.sort_uniq (fun x y -> Type.compare (prj x) (prj y)) (zs) in
    Array.of_list zs

  (* val find_opt : ?a:int -> ?b:int -> 'a t array -> t -> int option *)
  let find_opt ?(a=0) ?b xs x =
    let b = match b with None -> (Array.length xs)-1 | Some b -> b in
    let rec loop a b =
      if a>b then None else (* continue: *)
      let i = (a+b)/2 in
      match Type.compare x xs.(i) with
      |  0  -> Some i
      | -1 -> loop a (i-1)
      |  1 -> loop (i+1) b
      | _ -> assert false
    in
    loop a b

  (* val find_prj_opt : ?a:int -> ?b:int -> ('a -> t) -> 'a array -> t -> int option *)
  let find_prj_opt ?(a=0) ?b prj xs x =
    let b = match b with None -> (Array.length xs)-1 | Some b -> b in
    let rec loop a b =
      if a>b then None else (* continue: *)
      let i = (a+b)/2 in
      match Type.compare x (prj xs.(i)) with
      |  0  -> Some i
      | -1 -> loop a (i-1)
      |  1 -> loop (i+1) b
      | _ -> assert false
    in
    loop a b

  (* val locate : ?a:int -> ?b:int -> 'a t array -> t -> ((int * int), int) Either.t *)
  let locate ?(a=0) ?b xs x =
    let b = match b with None -> (Array.length xs)-1 | Some b -> b in
    let rec loop (j,k) a b =
      if a>b then Either.Left (j,k) else (* continue: *)
      let i = (a+b)/2 in
      match Type.compare x xs.(i) with
      |  0  -> Either.Right i
      | -1 -> loop (j,i) a (i-1)
      |  1 -> loop (i,k) (i+1) b
      | _ -> assert false
    in
    loop (a,b) a b

  (* val locate_prj : ?a:int -> ?b:int -> ('a -> t) -> 'a array -> t -> ((int * int), int) Either.t *)
  let locate_prj ?(a=0) ?b prj xs x =
    let b = match b with None -> (Array.length xs)-1 | Some b -> b in
    let rec loop (j,k) a b =
      if a>b then Either.Left (j,k) else (* continue: *)
      let i = (a+b)/2 in
      match Type.compare x (prj xs.(i)) with
      |  0  -> Either.Right i
      | -1 -> loop (j,i) a (i-1)
      |  1 -> loop (i,k) (i+1) b
      | _ -> assert false
    in
    loop (a,b) a b

  (* val locate_pedantic : ?a:int -> ?b:int -> 'a t array -> t -> (((int, int) Either.t, int * int) Either.t, int) Either.t *)
  let locate_pedantic ?(a=0) ?b xs x : (((a, b) Either.t, a * b) Either.t, found) Either.t =
    let b = match b with None -> (Array.length xs)-1 | Some b -> b in
    let a0, b0 = a,b in
    let rec loop (j,k) a b =
      if a>b then
        (if j<k  then Either.Left (Either.Right (j,k)) else
         if j=b0 then Either.Left (Either.Left (Either.Right b0))
                 else Either.Left (Either.Left (Either.Left  a0))
         )
      else (* continue: *)
      let i = (a+b)/2 in
      match Type.compare x xs.(i) with
      |  0  -> Either.Right i
      | -1 -> loop (j,i) a (i-1)
      |  1 -> loop (i,k) (i+1) b
      | _ -> assert false
    in
    loop (a,b) a b

  let locate_prj_pedantic ?(a=0) ?b prj xs x : (((a, b) Either.t, a * b) Either.t, found) Either.t =
    let b = match b with None -> (Array.length xs)-1 | Some b -> b in
    let a0, b0 = a,b in
    let rec loop (j,k) a b =
      if a>b then
        (if j<k  then Either.Left (Either.Right (j,k)) else
         if j=b0 then Either.Left (Either.Left (Either.Right b0))
                 else Either.Left (Either.Left (Either.Left  a0))
         )
      else (* continue: *)
      let i = (a+b)/2 in
      match Type.compare x (prj xs.(i)) with
      |  0  -> Either.Right i
      | -1 -> loop (j,i) a (i-1)
      |  1 -> loop (i,k) (i+1) b
      | _ -> assert false
    in
    loop (a,b) a b

  (*  val locate_or_split : ?a:index -> ?b:index -> 'a t array -> t -> ('a t array * 'a t array, found) Either.t
      ---
      Sowide_int.locate_or_split [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (-1) ;;
      - : (int array * int array, int) Either.t = Either.Left ([||], [|0; 10; 20; 30; 40; 50; 60; 70; 100; 1000|])

      Sowide_int.locate_or_split [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (0) ;;
      - : (int array * int array, int) Either.t = Either.Right 0

      Sowide_int.locate_or_split [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (15) ;;
      - : (int array * int array, int) Either.t = Either.Left ([|0; 10|], [|20; 30; 40; 50; 60; 70; 100; 1000|])

      Sowide_int.locate_or_split [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (50) ;;
      - : (int array * int array, int) Either.t = Either.Right 5

      Sowide_int.locate_or_split [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (110) ;;
      - : (int array * int array, int) Either.t = Either.Left ([|0; 10; 20; 30; 40; 50; 60; 70; 100|], [|1000|])

      Sowide_int.locate_or_split [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (1000) ;;
      - : (int array * int array, int) Either.t = Either.Right 9

      Sowide_int.locate_or_split [| 0; 10; 20; 30; 40; 50; 60; 70; 100; 1000 |] (2000) ;;
      - : (int array * int array, int) Either.t = Either.Left ([|0; 10; 20; 30; 40; 50; 60; 70; 100; 1000|], [||])
  *)
  let locate_or_split ?(a=0) ?b xs x : ('a t array * 'a t array, found) Either.t =
    let b = match b with None -> (Array.length xs)-1 | Some b -> b in
    let a0, b0 = a,b in
    let n0 = b0-a0+1 in
    if n0 = 0 then Either.Left ([||],[||]) else (* continue: *)
    let split lc j k =
       let left_part  = lazy (Array.sub xs a0 (j-a0+1)) in
       let right_part = lazy (Array.sub xs k  (b0-k+1)) in
       if j<k  then (Lazy.force left_part, Lazy.force right_part) else
       if lc = (+1) then (Lazy.force left_part, [||]) else ([||], Lazy.force right_part)
    in
    let rec loop lc (* last_compare *) (j,k) a b =
      if a>b then Either.Left (split lc j k) else (* continue: *)
      let i = (a+b)/2 in
      match Type.compare x xs.(i) with
      |  0  -> Either.Right i
      | -1 -> loop (-1) (j,i) a (i-1)
      |  1 -> loop (+1) (i,k) (i+1) b
      | _ -> assert false
    in
    loop 0 (a,b) a b

  (*  val locate_prj_or_split : ?a:index -> ?b:index -> ('a -> t) -> 'a array -> t -> ('a array * 'a array, found) Either.t  *)
  let locate_prj_or_split ?(a=0) ?b prj xs x : ('a array * 'a array, found) Either.t =
    let b = match b with None -> (Array.length xs)-1 | Some b -> b in
    let a0, b0 = a,b in
    let n0 = b0-a0+1 in
    if n0 = 0 then Either.Left ([||],[||]) else (* continue: *)
    let split lc j k =
       let left_part  = lazy (Array.sub xs a0 (j-a0+1)) in
       let right_part = lazy (Array.sub xs k  (b0-k+1)) in
       if j<k  then (Lazy.force left_part, Lazy.force right_part) else
       if lc = (+1) then (Lazy.force left_part, [||]) else ([||], Lazy.force right_part)
    in
    let rec loop lc (* last_compare *) (j,k) a b =
      if a>b then Either.Left (split lc j k) else (* continue: *)
      let i = (a+b)/2 in
      match Type.compare x (prj xs.(i)) with
      |  0  -> Either.Right i
      | -1 -> loop (-1) (j,i) a (i-1)
      |  1 -> loop (+1) (i,k) (i+1) b
      | _ -> assert false
    in
    loop 0 (a,b) a b

  (* val mem : ?a:int -> ?b:int -> t -> 'a t array -> bool *)
  let mem ?a ?b x xs =
    match find_opt ?a ?b xs x with
    | None   -> false
    | Some _ -> true

  let mem_prj ?a ?b prj x xs =
    match find_prj_opt ?a ?b prj xs x with
    | None   -> false
    | Some _ -> true

  (* val substract : 'a ts -> 'a ts -> 'a ts *)
  let substract xs ys =
    let xs1 = Array.mapi (fun i x -> if mem x ys then None else Some x) xs in
    let xs2 = ListExtra.filter_map (fun x -> x) (Array.to_list xs1) in
    Array.of_list xs2


  (* Modulo a projection of elements (we suppose the array being ordered with this same projection): *)
  module With_projection = struct
    let make            = sort_uniq_prj
    let merge           = merge_prj
    let mem             = mem_prj
    let find_opt        = find_prj_opt
    let locate          = locate_prj
    let locate_pedantic = locate_prj_pedantic
    let locate_or_split = locate_prj_or_split
  end (* With_projection *)


end (* Sowide *)

(* Standard cases, with structural and physical compare: *)
module With_structural_compare : SOWIDE with type 'a t = 'a = MAKE (struct type 'a t = 'a let compare = compare end)
module With_physical_compare   : SOWIDE with type 'a t = 'a = MAKE (struct type 'a t = 'a let compare = Misc.magic_physical_compare end)

(* Hash-consing may be applied here: *)
module Type_with_structural_compare (M: sig type t end) : (SOWIDE with type 'a t = M.t) = MAKE (struct
  type 'a t = M.t
  let id : M.t -> M.t = Extreme_sharing.make_id ()
  let compare x y = compare (id x) (id y)
  end)


