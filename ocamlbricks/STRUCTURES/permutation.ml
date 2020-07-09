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

IFDEF OCAML4_07_OR_LATER THEN
module Pervasives = Stdlib
ENDIF

(* Bijective mapping index -> index *)
type t = index array
 and index = int
 and length = int

module Tools = struct

  let array_init_x2 n f =
    if n = 0 then ([||],[||]) else
    let (x1,x2) = f 0 in
    let t1 = (Array.make n x1) in
    let t2 = (Array.make n x2) in
    for i = 1 to (n-1) do
      let (x1,x2) = f i in
      t1.(i) <- x1;
      t2.(i) <- x2;
    done;
    (t1, t2)

  let array_split2 ts =
    array_init_x2 (Array.length ts) (fun i -> ts.(i))

  (* val array_fold_lefti : (int -> 'a -> 'b -> 'a) -> 'a -> 'b array -> 'a *)
  let array_fold_lefti f s0 xs =
    let l = Array.length xs in
    let rec loop acc i =
      if i>=l then acc else
      let acc = f i acc xs.(i) in
      loop acc (i+1)
    in loop s0 0

  (* ArrayExtra.mapi_folding : (int -> 's -> 'a -> 'b * 's) -> 's -> 'a array -> 'b array *)
  (* array_mape = map "(e)xtended" with a folding activity, providing a result returned as second element. *)
  let array_mape (f : 's -> index -> 'a -> 'b * 's) (s0 : 's) (xs : 'a array) : 'b array * 's =
    let n = Array.length xs in
    if n = 0 then ([||], s0) else begin
      let (y0, s1) = f s0 0 (xs.(0)) in
      let result = Array.make n y0 in
      let state = ref s1 in
      for i = 1 to n-1 do
        let (y,z) = f (!state) i (xs.(i)) in
        result.(i) <- y ;
        state := z;
      done;
      (result, !state)
    end

  (* ArrayExtra.mapi_folding : (int -> 's -> 'a -> 'b * 's) -> 's -> 'a array -> 'b array *)
  (* array_mapg = map "(g)eneralised" with a folding activity, not providing a result *)
  let array_mapg (f : 's -> index -> 'a -> 'b * 's) (s0 : 's) (xs : 'a array) : 'b array =
    let ys, _ = array_mape f s0 xs in ys (* fst *)

end

(* ----------------------------------
           Basic constructors

    identity, swap, reverse, priority
   ---------------------------------- *)

(* val identity : length -> t *)
let identity n = Array.init n (fun i -> i)

(* val shuffle : length -> t *)
let shuffle n =
  let js = identity n in
  let () =
    Array.iteri
      (fun i x ->
        let choice = i + (Random.int (n-i)) in
        js.(i)<-js.(choice); js.(choice)<-x)
      js
  in
  js

(* val swap : length -> (index * index) list -> t *)
let swap n ijs =
  let p = identity n in
  let () = List.iter (fun (i,j) -> let x = p.(i) in p.(i) <- p.(j);  p.(j) <- x) ijs in
  p

(* val reverse  : length -> t *)
let reverse n =
  let last = n - 1 in
  Array.init n (fun i -> last-i)

(* val priority : length -> index -> t
   ---
   priority 10 7 ;;
   - : int array = [|7; 0; 1; 2; 3; 4; 5; 6; 8; 9|]*)
let priority n k =
  let k = if k<0 then (n - ((-k) mod n)) else k mod n in
  Array.init n (fun i -> if i=0 then k else if i<=k then (i-1) else i)

(* --- *)
module Int_set = Set.Make (struct  type t = int  let compare = compare  end)

(* priorities 10 [|3;5;8|] ;;
   - : int array = [|3; 5; 8; 0; 1; 2; 4; 6; 7; 9|] *)
let priorities n ks =
  let ks = List.map (fun k -> if k<0 then (n - ((-k) mod n)) else k mod n) ks in
  (* --- *)
  let kset, ks_length = List.fold_left (fun (s,n) k -> (Int_set.add k s), n+1) (Int_set.empty, 0) ks in
  let kset_card = Int_set.cardinal kset in
  if (kset_card < ks_length) then
    let msg = Printf.sprintf "Permutation.priorities: found %d duplicated indexes" (ks_length - kset_card) in
    invalid_arg msg
  else (* continue: *)
  (* --- *)
  let p = identity n in
  let pset = Int_set.diff (Int_set.of_list (Array.to_list p)) kset in
  let result = List.append ks (Int_set.elements pset) in
  Array.of_list result

(* ----------------------------------
                Shift
   ---------------------------------- *)

(* val shift_left : length -> int -> t *)
let shift n k =
  let p = identity n in
  let k = if k<0 then (n - ((-k) mod n)) else k in
  Array.init n (fun i -> p.((i+k) mod n))

(* val shift_left : length -> int -> t
   ---
   shift_left 1 (shift_left 2 (identity 10)) ;;
   - : int array = [|3; 4; 5; 6; 7; 8; 9; 0; 1; 2|]*)
let shift_left = shift

(* val shift_right : length -> int -> t
   ---
   shift_right 3 (identity 10) ;;
   - : int array = [|7; 8; 9; 0; 1; 2; 3; 4; 5; 6|] *)
let shift_right k = shift_left (-k)

(* ----------------------------------
                Inverse
   ---------------------------------- *)

(* val inverse : t -> t *)
let inverse p =
  let n = Array.length p in
  let result = Array.make n 0 in
  let () = Array.iteri (fun i j -> result.(j)<-i) p in
  result

(* ----------------------------------
                Append
   ---------------------------------- *)

(* append p1 p2 = Array.append p1 (translate (Array.length p1) p2)
    where:    q = translate k p   =>   q.(i) = p.(i) + k
   ---
   concat_list ps = List.fold_left append [] ps  (but implemented in a slightly more efficient way) *)

let translate k p =
  Array.map (fun i-> i+k) p

(* val append : t -> t -> t *)
let append p1 p2 = Array.append p1 (translate (Array.length p1) p2)

(* val concat_array : t array -> t *)
let concat_array perms =
  let perms_translated =
    Tools.array_mapg (fun s _ perm -> (translate s perm), (s + Array.length perm)) 0 (perms)
  in
  Array.concat (Array.to_list perms_translated)

(* val concat_list  : t list  -> t *)
let concat_list perms = concat_array (Array.of_list perms)

(* ----------------------------------
                Compose
   ---------------------------------- *)

(* val array_apply : t -> 'a array -> 'a array *)
let array_apply js xs =
  let ys = Array.copy xs in
  let () = Array.iteri (fun i j -> ys.(i) <- xs.(j)) js in ys

(* val array_apply_in_place : t -> 'a array -> unit *)
let array_apply_in_place js xs =
  let ys = Array.copy xs in
  Array.iteri (fun i j -> xs.(i) <- ys.(j)) js

(* val compose : t -> t -> t
  (compose t1 t2) means (t1; t2), i.e. is equivalent to perform t1 then t2. *)
let compose p1 p2 =
  array_apply p2 p1

(* val compose_list  : t -> t list  -> t *)
let compose_list p0 =
  List.fold_left (compose) p0

(* val compose_array : t -> t array -> t *)
let compose_array p0 =
  Array.fold_left (compose) p0

(* ---------------------------------- *)
module Compose = struct
(* ---------------------------------- *)

  (* Compose.f t = compose t (f (Array.length t)) *)

  (* val shuffle  : t -> t *)
  let shuffle t = compose t (shuffle (Array.length t))

  (* val swap : t -> (index * index) list -> t *)
  let swap t ijs = compose t (swap (Array.length t) ijs)

  (* val reverse  : t -> t *)
  let reverse t = compose t (reverse (Array.length t))

  (* val priority : t -> index -> t *)
  let priority t i = compose t (priority (Array.length t) i)

  (* val priorities : t -> index list -> t *)
  let priorities t ks = compose t (priorities (Array.length t) ks)

  (* val shift_left : t -> int -> t *)
  let shift_left t k = compose t (shift_left (Array.length t) k)

  (* val shift_right : t -> int -> t *)
  let shift_right t k = compose t (shift_right (Array.length t) k)

end (* Compose *)

(* val check : t -> bool *)
let check t =
  let id = identity (Array.length t) in
  try id = (compose t (inverse t)) with _ -> false

let import t =
  if check t then t else (* continue: *)
  let n = Array.length t in
  let msg = Printf.sprintf "Permutation.import: not a bijection [0,%d] -> [0,%d]" (n-1) (n-1) in
  invalid_arg msg

(* ---------------------------------- *)
module Array = struct
(* ---------------------------------- *)

  (* ---------------------------------- *)
  module In_place = struct
  (* ---------------------------------- *)

    (* val apply   : t -> 'a array -> unit *)
    let apply = array_apply_in_place

    (* val unapply : t -> 'a array -> unit *)
    let unapply js = array_apply_in_place (inverse js)

    (* --- *)
    (* val sort    : ?stable:unit -> ?compare:('a compare) -> 'a array -> unit * t *)
    let sort ?stable ?(compare=Pervasives.compare) (xs:'a array) : unit * t =
      let xis = Array.mapi (fun i x -> (x,i)) xs in
      let () =
        match stable with
        | None    -> Array.sort        (fun (x,_) (y,_) ->  compare x y) xis
        | Some () -> Array.stable_sort (fun (x,_) (y,_) ->  compare x y) xis
      in
      let p = Array.map (snd) xis in
      let () = array_apply_in_place p xs in (* in place *)
      ((), p)

    (* val shuffle : 'a array -> unit * t *)
    let shuffle xs =
      let p  = shuffle (Array.length xs) in
      let () = array_apply_in_place p xs in
      ((), p)

    (* val reverse : 'a array -> unit * t *)
    let reverse xs =
      let p  = reverse (Array.length xs) in
      let () = array_apply_in_place p xs in
      ((), p)

    (* val swap : 'a array -> (index * index) list -> unit * t *)
    let swap xs ijs =
      let p  = swap (Array.length xs) (ijs) in
      let () = array_apply_in_place p xs in
      ((), p)

    (* val priority : 'a array -> index -> unit * t *)
    let priority xs i =
      let p  = priority (Array.length xs) (i) in
      let ys = array_apply_in_place p xs in
      (ys, p)

    (* val priorities : 'a array -> index list -> unit * t *)
    let priorities xs ks =
      let p  = priorities (Array.length xs) (ks) in
      let ys = array_apply_in_place p xs in
      (ys, p)

    (* val shift_left  : 'a array -> int -> unit * t *)
    let shift_left xs k =
      let p  = shift_left (Array.length xs) (k) in
      let ys = array_apply_in_place p xs in
      (ys, p)

    (* val shift_right : 'a array -> int -> unit * t *)
    let shift_right xs k =
      let p  = shift_right (Array.length xs) (k) in
      let ys = array_apply_in_place p xs in
      (ys, p)

  end (* Array.In_place *)

  (* --- *)

  (* val apply : t -> 'a array -> 'a array *)
  let apply = array_apply

  (* val unapply : t -> 'a array -> 'a array *)
  let unapply js = array_apply (inverse js)

  (* val map : t -> ('a -> 'b) -> 'a array -> 'b array *)
  let map p f xs =
    unapply p (Array.map f (apply p xs))

  (*  val mapi  : t -> (int -> 'a -> 'b) -> 'a array -> 'b array
      ---
      let xs = [|'A'; 'B'; 'C'; 'D'; 'E'; 'F'; 'G'; 'H'; 'I'; 'J'|];;

      Permutation.Array.mapi (priority 3 (identity 10)) (fun i x -> let () = Printf.printf "%d  " i in (i,Char.escaped x)) xs ;;
      3  0  1  2  4  5  6  7  8  9  - : (int * bytes) array =
      [|(0, "A"); (1, "B"); (2, "C"); (3, "D"); (4, "E"); (5, "F"); (6, "G"); (7, "H"); (8, "I"); (9, "J")|]

      Array.mapi (fun i x -> let () = Printf.printf "%d  " i in (i,Char.escaped x)) xs ;;
      0  1  2  3  4  5  6  7  8  9  - : (int * bytes) array =
      [|(0, "A"); (1, "B"); (2, "C"); (3, "D"); (4, "E"); (5, "F"); (6, "G"); (7, "H"); (8, "I"); (9, "J")|] *)
  let mapi p f xs =
    unapply p (Array.mapi (fun j x -> f p.(j) x) (apply p xs))

  (* val iteri : t -> (int -> 'a -> unit) -> 'a array -> unit
     ---
     let xs = [|'A'; 'B'; 'C'; 'D'; 'E'; 'F'; 'G'; 'H'; 'I'; 'J'|];;

     Array.iteri (Printf.printf "%d:%c  ") xs  ;;
     0:A  1:B  2:C  3:D  4:E  5:F  6:G  7:H  8:I  9:J  - : unit = ()

     array_iteri (priority 3 (identity 10)) (Printf.printf "%d:%c  ") xs  ;;
     3:D  0:A  1:B  2:C  4:E  5:F  6:G  7:H  8:I  9:J  - : unit = () *)
  let iteri p f xs =
    Array.iteri (fun j x -> f p.(j) x) (apply p xs)

  (* val foldi : t -> (int -> 'a -> 'b -> 'a) -> 'a -> 'b array -> 'a *)
  let foldi p f s0 xs =
    Tools.array_fold_lefti (fun j s x -> f p.(j) s x) s0 (apply p xs)

  (* --- *)
  (* val sort : ?stable:unit -> ?compare:('a compare) -> 'a array -> 'a array * t *)
  let sort ?stable ?(compare=Pervasives.compare) (xs:'a array) : ('a array) * t =
    let xis = Array.mapi (fun i x -> (x,i)) xs in
    let () =
      match stable with
      | None    -> Array.sort        (fun (x,_) (y,_) ->  compare x y) xis
      | Some () -> Array.stable_sort (fun (x,_) (y,_) ->  compare x y) xis
    in
    Tools.array_split2 xis

  (* val shuffle : 'a array -> 'a array * t *)
  let shuffle xs =
    let p  = shuffle (Array.length xs) in
    let ys = array_apply p xs in
    (ys, p)

  (* val reverse : 'a array -> 'a array * t *)
  let reverse xs =
    let p  = reverse (Array.length xs) in
    let ys = array_apply p xs in
    (ys, p)

  (* val swap : 'a array -> (index * index) list -> 'a array * t *)
  let swap xs ijs =
    let p  = swap (Array.length xs) (ijs) in
    let ys = array_apply p xs in
    (ys, p)

  (* val priority : 'a array -> index -> 'a array * t *)
  let priority xs i =
    let p  = priority (Array.length xs) (i) in
    let ys = array_apply p xs in
    (ys, p)

  (* val priorities : 'a array -> index list -> 'a array * t *)
  let priorities xs ks =
    let p  = priorities (Array.length xs) (ks) in
    let ys = array_apply p xs in
    (ys, p)

  (* val shift_left  : 'a array -> int -> 'a array * t *)
  let shift_left xs k =
    let p  = shift_left (Array.length xs) (k) in
    let ys = array_apply p xs in
    (ys, p)

  (* val shift_right : 'a array -> int -> 'a array * t *)
  let shift_right xs k =
    let p  = shift_right (Array.length xs) (k) in
    let ys = array_apply p xs in
    (ys, p)

end (* Array *)
