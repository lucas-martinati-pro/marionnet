(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2018 Jean-Vincent Loddo

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

(** Perform some structural transformations on an array. These operations
    can be reversed or applied again to the same array or to another. *)

IFDEF OCAML4_07_OR_LATER THEN
module Pervasives = Stdlib
ENDIF

type  'a t      = 'a array (* alias *)
 and  'a tt     = 'a t t   (* alias *)
 and  index     = int
 and length     = int
 and 'a compare = ('a -> 'a -> int)

module Init_array = struct

let init_x1 = Array.init
(* --- *)
let init_x2 n f =
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
(* --- *)
let init_x3 n f =
  if n = 0 then ([||],[||],[||]) else
  let (x1,x2,x3) = f 0 in
  let t1 = (Array.make n x1) in
  let t2 = (Array.make n x2) in
  let t3 = (Array.make n x3) in
  for i = 1 to (n-1) do
    let (x1,x2,x3) = f i in
    t1.(i) <- x1;
    t2.(i) <- x2;
    t3.(i) <- x3;
  done;
  (t1, t2, t3)
(* --- *)
let init_x4 n f =
  if n = 0 then ([||],[||],[||],[||]) else
  let (x1,x2,x3,x4) = f 0 in
  let t1 = (Array.make n x1) in
  let t2 = (Array.make n x2) in
  let t3 = (Array.make n x3) in
  let t4 = (Array.make n x4) in
  for i = 1 to (n-1) do
    let (x1,x2,x3,x4) = f i in
    t1.(i) <- x1;
    t2.(i) <- x2;
    t3.(i) <- x3;
    t4.(i) <- x4;
  done;
  (t1, t2, t3, t4)
(* --- *)
let init_x5 n f =
  if n = 0 then ([||],[||],[||],[||],[||]) else
  let (x1,x2,x3,x4,x5) = f 0 in
  let t1 = (Array.make n x1) in
  let t2 = (Array.make n x2) in
  let t3 = (Array.make n x3) in
  let t4 = (Array.make n x4) in
  let t5 = (Array.make n x5) in
  for i = 1 to (n-1) do
    let (x1,x2,x3,x4,x5) = f i in
    t1.(i) <- x1;
    t2.(i) <- x2;
    t3.(i) <- x3;
    t4.(i) <- x4;
    t5.(i) <- x5;
  done;
  (t1, t2, t3, t4, t5)
(* --- *)
end (* Init *)

module Tuple_array = struct
  let split2 ts = Init_array.init_x2 (Array.length ts) (fun i -> ts.(i))
  let split3 ts = Init_array.init_x3 (Array.length ts) (fun i -> ts.(i))
  let split4 ts = Init_array.init_x4 (Array.length ts) (fun i -> ts.(i))
  let split5 ts = Init_array.init_x5 (Array.length ts) (fun i -> ts.(i))
  let combine2 t1 t2 = Array.init (Array.length t1) (fun i -> t1.(i), t2.(i))
  let combine3 t1 t2 t3 = Array.init (Array.length t1) (fun i -> t1.(i), t2.(i), t3.(i))
  let combine4 t1 t2 t3 t4 = Array.init (Array.length t1) (fun i -> t1.(i), t2.(i), t3.(i), t4.(i))
  let combine5 t1 t2 t3 t4 t5 = Array.init (Array.length t1) (fun i -> t1.(i), t2.(i), t3.(i), t4.(i), t5.(i))
  let split = split2
  let combine = combine2
end (* Tuple *)


module Tools = struct

  (* Equivalent to the standard [Array.of_list] but the list is not scanned twice.
     The function raises [Invalid_argument] if the real length of the list differs
     from the announced one. *)
  let array_of_known_length_list ?(reversing=false) len =
    let errmsg1 = "unexpected list length (overstated size)"  in
    let errmsg2 = "unexpected list length (understated size)" in
    function
    | []    -> [||]
    | x::xs ->
        let a = Array.make len x in
        (* --- *)
        if reversing then begin
          let rec loop i = function
          | []    -> (if i=(-1) then a else invalid_arg errmsg1)
          | x::xs -> (try a.(i) <- x with _ -> invalid_arg errmsg2); loop (i-1) xs
          in
          loop (len-2) xs
        end
        (* --- *)
        else begin
          let rec loop i = function
          | []    -> (if i=len then a else invalid_arg errmsg1)
          | x::xs -> (try a.(i) <- x with _ -> invalid_arg errmsg2); loop (i+1) xs
          in
          loop 1 xs
        end

  (* stop not included (as in Python function range): *)
  let fold_lefti ?(start=0) ?stop ?(step=1) f y0 s =
    let stop = match stop with Some n -> n | None -> Array.length s in
    let rec loop acc i =
      if i >= stop then acc else
      let acc = f i acc s.(i) in
      loop acc (i+step)
    in loop y0 start

  (* ArrayExtra.mapi_folding : (int -> 's -> 'a -> 'b * 's) -> 's -> 'a array -> 'b array *)
  (* mape = map "(e)xtended" with a folding activity, providing a result returned as second element. *)
  let mape (f : 's -> index -> 'a -> 'b * 's) (s0 : 's) (xs : 'a array) : 'b array * 's =
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
  (* mapg = map "(g)eneralised" with a folding activity, not providing a result *)
  let mapg (f : 's -> index -> 'a -> 'b * 's) (s0 : 's) (xs : 'a array) : 'b array =
    let ys, _ = mape f s0 xs in ys (* fst *)

  (* Source: ArrayExtra.iteri_folding: (int -> 's -> 'a -> 's) -> 's -> 'a array -> unit *)
  let iterg (f : 's -> index -> 'a -> 's) (s0 : 's) (xs : 'a array) : unit =
    let n = Array.length xs in
    if n = 0 then () else begin
      let s1 = f s0 0 (xs.(0)) in
      let state = ref s1 in
      for i = 1 to n-1 do
        let z = f  (!state) i (xs.(i)) in
        state := z;
      done;
    end

  (* iter "extended" ????? Che differenza con un fold? *)
  let itere (f : 's -> index -> 'a -> 's) (s0 : 's) (xs : 'a array) : 's =
    let n = Array.length xs in
    if n = 0 then s0 else begin
      let s1 = f s0 0 (xs.(0)) in
      let state = ref s1 in
      for i = 1 to n-1 do
        let z = f (!state) i (xs.(i)) in
        state := z;
      done;
      (!state) (* result *)
    end

  (* La funzione precedente mapg poteva essere programmata con questa, cioè:
     let mapg f s0 xs = mapi (simplify_generalized_function_for_mapi f s0) xs
     ---
     val simplify_generalized_function_for_mapi : ('s -> index -> 'a -> 'b * 's) -> 's -> (index -> 'a -> 'b)
     --- *)
  let simplify_generalized_function_for_mapi f s0 =
    let r = ref s0 in
    fun i ->
      (* reset the state (needed when the function is called twice or several times): *)
      let () = (if i=0 then r := s0) in
      (* --- *)
      fun x ->
        let (y, s1) = f !r i x in
        let () = (r := s1) in
        y

  (* ---
     val simplify_generalized_function_for_init : ('s -> index -> 'a * 's) -> 's -> (index -> 'a)
     --- *)
  let simplify_generalized_function_for_init f s0 =
    let r = ref s0 in
    fun i ->
      (* reset the state (needed when the function is called twice or several times): *)
      let () = (if i=0 then r := s0) in
      (* --- *)
      let (y, s1) = f !r i in
      let () = (r := s1) in
      y

  (* val initg : int -> ('s -> int -> 'a * 's) -> 's -> 'a array *)
  let initg n f s0 = Array.init n (simplify_generalized_function_for_init f s0)

  (*  let flatten xss =
      Array.concat (Array.to_list xss) *)

  let range ?start n =
    match start with
    | None   -> Array.init n (fun i -> i)
    | Some x -> Array.init n (fun i -> x+i)

  let rev_range n =
    let last = n-1 in Array.init n (fun i -> last-i)

  (* Returns the real function `compare' and a fake version that may be used to decide the unicity.
     Runnning the fake version, the boolean information about unicity will be stored in the provided
     homonymous reference, returned by make_compare as third component. *)
  let make_compare ?(compare=Pervasives.compare) () : ('a compare * 'a compare * bool ref) =
    let unicity = ref true in
    let rec compare_v0 x y =
      let result = compare x y in
      let () = if result = 0 then (unicity := false; cmp := compare) else () in
      result
    and
      cmp = ref compare_v0
    in
    let fake_compare x y = (!cmp) x y in
    (compare, fake_compare, unicity)

  (* Extend a comparing function to values coupled with indexes: *)
  let extend_compare (compare) (x,i) (y,j) =
    match compare x y with
    | 0 -> Pervasives.compare i j
    | r -> r


end (* Tools *)

module Swap = struct

  type play = (index * index) list (* the list of swaps *)
  (* --- *)
   and 'a source = 'a t
   and 'a target = 'a t

  let swap ?in_place (ijs : (index * index) list) xs =
    let xs = if (in_place = None) then (Array.copy xs) else xs in
    let () = List.iter (fun (i,j) -> let x = xs.(i) in xs.(i) <- xs.(j);  xs.(j) <- x) ijs in
    (xs, ijs)

  let replay ?in_place ijs xs = fst (swap ?in_place ijs xs)
  let rewind ?in_place ijs xs = fst (swap ?in_place (List.map (fun (i,j)->(j,i)) (List.rev ijs)) xs)

  let compose play1 play2 =
    List.append play1 play2

end (* Swap *)

module Permutation = struct
  type play = index array (* bijective mapping: index -> index *)
  (* --- *)
   and 'a source = 'a t
   and 'a target = 'a t

  let identity n = Array.init n (fun i -> i)
  let translate k p = Array.map (fun i-> i+k) p
  let append p1 p2 = Array.append p1 (translate (Array.length p1) p2)

  let concat_array perms =
    let perms_translated =
      Tools.mapg (fun s _ perm -> (translate s perm), (s + Array.length perm)) 0 (perms)
    in
    Array.concat (Array.to_list perms_translated)

  let concat_list perms = concat_array (Array.of_list perms)

  let shift k p =
    let n = Array.length p in
    let k = if k<0 then (n - ((-k) mod n)) else k in
    Array.init n (fun i -> p.((i+k) mod n))

  (* shift_left 1 (shift_left 2 (identity 10)) ;;
     - : int array = [|3; 4; 5; 6; 7; 8; 9; 0; 1; 2|]*)
  let shift_left = shift

  (* shift_right 3 (identity 10) ;;
     - : int array = [|7; 8; 9; 0; 1; 2; 3; 4; 5; 6|] *)
  let shift_right k = shift_left (-k)

  (* priority 7 (priority 3 (identity 10)) ;;
     - : int array = [|7; 3; 0; 1; 2; 4; 5; 6; 8; 9|]*)
  let priority k p =
    let n = Array.length p in
    let k = if k<0 then (n - ((-k) mod n)) else k mod n in
    Array.init n (fun i -> if i=0 then p.(k) else if i<=k then p.(i-1) else p.(i))

  let reverse p =
    let n = Array.length p in
    let last = n - 1 in
    Array.init n (fun i -> p.(last-i))

  let inverse p =
    let n = Array.length p in
    let result = Array.make n 0 in
    let () = Array.iteri (fun i j -> result.(j)<-i) p in
    result

  let replay ?in_place js xs =
    let ys = Array.copy xs in
    match in_place with
    | None    -> let () = Array.iteri (fun i j -> ys.(i) <- xs.(j)) js in ys
    | Some () -> let () = Array.iteri (fun i j -> xs.(i) <- ys.(j)) js in xs

  let apply js xs = replay js xs
  let unapply js = apply (inverse js)

  (* let xs = [|'A'; 'B'; 'C'; 'D'; 'E'; 'F'; 'G'; 'H'; 'I'; 'J'|];;

     array_mapi (priority 3 (identity 10)) (fun i x -> let () = Printf.printf "%d  " i in (i,Char.escaped x)) xs ;;
     3  0  1  2  4  5  6  7  8  9  - : (int * bytes) array =
     [|(0, "A"); (1, "B"); (2, "C"); (3, "D"); (4, "E"); (5, "F"); (6, "G"); (7, "H"); (8, "I"); (9, "J")|]

     Array.mapi (fun i x -> let () = Printf.printf "%d  " i in (i,Char.escaped x)) xs ;;
     0  1  2  3  4  5  6  7  8  9  - : (int * bytes) array =
     [|(0, "A"); (1, "B"); (2, "C"); (3, "D"); (4, "E"); (5, "F"); (6, "G"); (7, "H"); (8, "I"); (9, "J")|] *)
  let array_mapi p f xs =
    unapply p (Array.mapi (fun j x -> f p.(j) x) (apply p xs))

  let array_map p f xs =
    unapply p (Array.map f (apply p xs))

  (* let xs = [|'A'; 'B'; 'C'; 'D'; 'E'; 'F'; 'G'; 'H'; 'I'; 'J'|];;

     Array.iteri (Printf.printf "%d:%c  ") xs  ;;
     0:A  1:B  2:C  3:D  4:E  5:F  6:G  7:H  8:I  9:J  - : unit = ()

     array_iteri (priority 3 (identity 10)) (Printf.printf "%d:%c  ") xs  ;;
     3:D  0:A  1:B  2:C  4:E  5:F  6:G  7:H  8:I  9:J  - : unit = () *)
  let array_iteri p f xs =
    Array.iteri (fun j x -> f p.(j) x) (apply p xs)

  let array_fold_lefti f s0 xs =
    let l = Array.length xs in
    let rec loop acc i =
      if i>=l then acc else
      let acc = f i acc xs.(i) in
      loop acc (i+1)
    in loop s0 0

  (* val array_foldi : play -> (int -> 'a -> 'b -> 'a) -> 'a -> 'b array -> 'a *)
  let array_foldi p f s0 xs =
    array_fold_lefti (fun j s x -> f p.(j) s x) s0 (apply p xs)

  let rewind ?in_place js xs =
    let ys = Array.copy xs in
    match in_place with
    | None    -> let () = Array.iteri (fun i j -> ys.(j) <- xs.(i)) js in ys
    | Some () -> let () = Array.iteri (fun i j -> xs.(j) <- ys.(i)) js in xs

  let compose ?in_place play1 play2 =
    replay ?in_place play2 play1

  let compose_list play = function
    | [] -> play
    | p::ps -> List.fold_left (compose) p ps

  let array_sort ?in_place ?stable ?(compare=Pervasives.compare) (xs:'a array) : ('a array) * play =
    let xis = Array.mapi (fun i x -> (x,i)) xs in
    let () =
      match stable with
      | None    -> Array.sort        (fun (x,_) (y,_) ->  compare x y) xis
      | Some () -> Array.stable_sort (fun (x,_) (y,_) ->  compare x y) xis
    in
    let ys, play = Tuple_array.split2 xis in
    if in_place = None then (ys, play) else (* continue: *)
    let xs = replay ~in_place:() play xs in
    (xs, play)

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

  (* ArrayExtra.random_permutation *)
  let array_shuffle ?in_place xs =
    let n = Array.length xs in
    let js = shuffle n in
    let ys = replay ?in_place js xs in
    (ys, js)

  let array_reverse ?in_place xs =
    let play = Tools.rev_range (Array.length xs) in
    let ys = replay ?in_place play xs in
    (ys, play)

  let import_swap ijs n =
    let r0 = Tools.range n in
    let r1, _ = Swap.swap ~in_place:() (ijs) r0 in
    r1

  let swap ?in_place ijs xs =
    let r1 = import_swap (ijs) (Array.length xs) in
    let ys = replay ?in_place r1 xs in
    (ys, r1)

  let rotate_right ?in_place ~rows xs =
    let n = Array.length xs in
    let () = assert ((rows > 0) && (rows <= n) && (n mod rows) = 0) in
    let js = Array.make n 0 in
    (* --- *)
    let () =
      let cols = n / rows in
      let b0 = rows * (cols-1) in
      let i = ref 0 in
      for r = 0 to (rows-1) do
          let b = ref b0 in
          for _c = 0 to (cols-1) do
            js.(!i) <- r + !b;
            incr i;
            b := !b - rows;
          done
      done
    in
    (* --- *)
    let ys = replay ?in_place js xs in
    (ys, js)


end (* Permutation *)

module Sorting = struct

  type 'a play = 'a compare * 'a array * unicity * Permutation.play
   and unicity = bool
   and locations  = [ `unique of index | `segment of index * index ]
  (* --- *)
   and 'a source = 'a t
   and 'a target = 'a t

  (* --- *)

  (* val sort   : ?in_place:unit -> ?compare:('a compare) -> 'a array -> 'a array * 'a play *)
  let sort ?in_place ?stable ?compare xs =
    let compare, fake_compare, unicity = Tools.make_compare ?compare () in
    let ys, perm_play = Permutation.array_sort ?in_place ?stable ~compare:fake_compare xs in
    let play = (compare, ys, !unicity, perm_play) in
    (ys, play)

  let locate (compare, v, _unicity, _perm_play) ?(a=0) ?b x =
    let b = match b with None -> (Array.length v)-1 | Some b -> b in
    if (a>b) then `outside else (* continue: *)
    (* compare with index `a': *)
    let ca = compare x v.(a) in
    if ca = (-1) then `outside else (* continue: *)
    if ca =   0  then `at(a) else   (* a is a lower bound; continue: *)
    (* compare with index `b': *)
    let cb = compare x v.(b) in
    if cb =   1  then `outside else (* continue: *)
    if cb =   0  then `at(b) else   (* b is an upper bound; continue: *)
    (* --- *)
    let rec loop (last_lb) (last_ub) a b =
      (* let () = Printf.kfprintf flush stderr "loop (%d,%d) [%d,%d]\n" (last_lb) (last_ub) a b in
      let _ = read_line () in *)
      if a>b then `between(last_lb, last_ub) else (* continue: *)
      if a=b then
        match compare x v.(a) with
        |   0  -> `at_with_bounds(a, last_lb, last_ub)
        | (-1) -> `between(last_lb,a)
        |   1  -> `between(a,last_ub)
        | _    -> assert false
      else (* continue: *)
      (* a < b *)
      let i = (a+b)/2 in
      match compare x v.(i) with
      |   0  -> `at_with_bounds(i, last_lb, last_ub)
      | (-1) -> loop (last_lb)  i    a   (i-1)
      |   1  -> loop  i  (last_ub) (i+1)   b
      | _    -> assert false
    in
    loop a b a b

  let find ((compare, v, unicity, _perm_play) as play) ?a ?b x =
    if not unicity then invalid_arg "ArrayTk.Sorting.find: array with duplicates: call locate instead." else (* continue: *)
    match locate play ?a ?b x with
    | `at i | `at_with_bounds (i,_,_) -> Some i
    | _     -> None

  let rec find_leftmost play a b i x =
    match locate play ~a ~b x with
    | `at j -> find_leftmost play a (j-1) j x
    | `at_with_bounds (j, last_lb, last_ub) -> find_leftmost play (last_lb) (j-1) j x
    | _ -> i

  let rec find_rightmost play a b i x =
    match locate play ~a ~b x with
    | `at j -> find_rightmost play (j+1) b j x
    | `at_with_bounds (j, last_lb, last_ub) -> find_leftmost play (j+1) (last_ub) j x
    | _  -> i

  (* locate redefinition: *)
  let locate ((compare, v, unicity, _perm_play) as play) ?a ?b x =
    match unicity with
    (* With unicity, the constructor `at_with_bounds becomes `at and disappears: *)
    | true ->
        (match locate play ?a ?b x with
        | `at i
        | `at_with_bounds (i, _, _) -> Some (`unique i)
        | `between(i,j)             -> None
        | `outside                  -> None
        )
    (* --- *)
    | false ->
       (* Without unicity, the constructors `at and `at_with_bounds become both `segment and disappears: *)
        (match locate play ?a ?b x with
        | `at_with_bounds (i, last_lb, last_ub) ->
            let i0 = find_leftmost  play last_lb (i-1) i x in
            let i1 = find_rightmost play (i+1) last_ub i x in
            Some (if i0 < i1 then `segment (i0,i1) else `unique i)
        (* --- *)
        | `at i ->
            let a = match a with Some a -> a | None -> 0 in
            let b = match b with Some b -> b | None -> (Array.length v)-1  in
            let i0 = find_leftmost  play a (i-1) i x in
            let i1 = find_rightmost play (i+1) b i x in
            Some (if i0 < i1 then `segment (i0, i1) else `unique i)
        (* --- *)
        | `between(i,j) -> None
        | `outside      -> None
        )

  let get (_compare, _xs, _unicity, perm_play) ys i =
    ys.(perm_play.(i))

  let find_all ((compare, xs, unicity, perm_play) as play) ?a ?b x =
    match locate play ?a ?b x with
    | Some (`unique i)        -> [|i|]
    | Some (`segment (i0,i1)) -> (Tools.range ~start:i0 (i1-i0+1))
    | None -> [||]

  let assoc_all ((compare, xs, unicity, perm_play) as play) ?a ?b ys x =
    match locate play ?a ?b x with
    | Some (`unique i)        -> [|ys.(perm_play.(i))|]
    | Some (`segment (i0,i1)) -> Array.map (fun i -> ys.(perm_play.(i))) (Tools.range ~start:i0 (i1-i0+1))
    | None -> [||]

  (* Example:
     ---
     let xs = [| 0; 2; 6; 9; 10; 8; 4 |] ;;
     let ys = Array.map (string_of_int) xs ;;
     let xs', pl = ArrayTk.Sorting.sort xs ;;
     (* The couple (xs,ys) may be viewed as a dictionary (where xs are the keys, ys the values): *)
     ArrayTk.Sorting.assoc pl ys 9 ;;   (* Some "9"  because "9" is the value associated to the key 9 *)
     ArrayTk.Sorting.assoc pl ys 3 ;;   (* None      because the key 3 is not in xs *)
  *)
  let assoc ((_compare, _xs, unicity, perm_play) as play) ys x =   (* requires unicity *)
    if not unicity then invalid_arg "ArrayTk.Sorting.assoc: array with duplicates, cannot be used as set of keys"
    else (* continue: *)
    match find play x with
    | None   -> None
    | Some i -> Some (ys.(perm_play.(i)))

  let replay ?in_place (_compare, _xs, _unicity, perm_play) ys =
    Permutation.replay ?in_place (perm_play) ys

  let rewind ?in_place (_compare, _xs, _unicity, perm_play) ys =
    Permutation.rewind ?in_place (perm_play) ys

end (* Sorting *)


module Split = struct

  (* Note: the implicit outer_size is the length of the array: *)
  type play = total_size * inner_size t
   and inner_size = int (* >=0 *)
   and total_size = int (* >=0 *)
  (* --- *)
   and 'a source = 'a t
   and 'a target = 'a tt

  (* The rest, if any, is appended in the last array, so the argument inner_sizes may be fixed and returned as play: *)
  let split ?total_size ?min_outer_size ~inner_sizes xs : 'a tt * play =
    let m = Array.length (inner_sizes) in
    if m <= 0 then invalid_arg "ArrayTk.Split.split: the array of inner sizes cannot be empty" else
    (* --- *)
    (* Complete the array inner_sizes (with the size of the rest of xs) if needed: *)
    let n0 = Array.length xs in
    let n1 =
      match total_size with
      | None   -> Array.fold_left (+) 0 inner_sizes
      | Some n -> n
    in
    (* Fixing inner_sizes: *)
    let inner_sizes =
      if n1 = n0 then inner_sizes else (* continue: *)
      if n1 < n0 then Array.concat [ inner_sizes; [|(n0-n1)|] ] else (* continue: *)
      let errmsg =
        Printf.sprintf "ArrayTk.Split.split: the sum of inner sizes (%d) exceed the length of the provided array (%d)"
        n1 n0
      in
      invalid_arg errmsg
    in
    (* --- *)
    let inner_sizes =
      match min_outer_size with
      | None   -> inner_sizes
      | Some m ->
          let outer_size = Array.length inner_sizes in
          if outer_size >= m then inner_sizes else (* continue: *)
          (* We will append (m - outer_size) empty classes: *)
          let rest = Array.make (m - outer_size) 0 in
          Array.append (inner_sizes) (rest)
    in
    (* --- *)
    let xss = Tools.mapg (fun j i size -> (Array.sub xs j size), j+size) 0 inner_sizes in
    let play = (n0 , inner_sizes) in
    (xss, play)

  let get_total_size xss =
    Array.fold_left (fun s xs -> s + (Array.length xs)) 0 xss

  let import xss : play =
    let inner_sizes, total_size = Tools.mape (fun s i xs -> let n = Array.length xs in (n, s+n)) 0 xss in
    (total_size, inner_sizes)

  (* Alias for import: *)
  let get_total_and_inner_sizes = import

  (* replay is `split' with a slightly different signature *)
  let replay ((total_size, inner_sizes) as _play) xs =
    fst (split ~total_size ~inner_sizes xs)

  (* rewind is `flatten' (concat) but knowing the inner sizes and the total_length: *)
  let rewind ((total_size, inner_sizes) as _play) xss =
    let rec fix j h =
      if h < inner_sizes.(j) then (j,h) else fix (j+1) 0
    in
    Tools.initg (total_size)
      (fun (j,h) _i ->
         let (j,h) = fix j h in
         xss.(j).(h), (j, h+1))
      (0,0)

  let flatten xss =
    let total_size, inner_sizes = import xss in
    rewind (total_size, inner_sizes) xss

  (** As standard [Array.sub] but with optional length (if not provided, the length is defined
      in order to take the rest of the list after the given position) *)
  let sub ?size ~pos xs =
    let n = Array.length xs in
    let size = match size with
    | None   -> n - pos
    | Some s -> s
    in
    let last_pos  = pos + size in
    let last_size = n - last_pos in
    let p0 = Array.sub xs 0 pos in
    let p1 = Array.sub xs pos size in
    let p2 = Array.sub xs last_pos last_size in
    let play = (n, [| pos; size; last_size |]) in
    ([| p0; p1; p2 |], play)

  let pivot pos =
    sub ~size:1 ~pos

 (* Example:
    # amass ~inner_size:3 [|1;2;3;4;5;6;7;8;9;10|] ;;
    : int array array = [|[|1; 2; 3|]; [|4; 5; 6|]; [|7; 8; 9|]; [|10|]|] *)
  let amass ~inner_size xs =
    if inner_size <= 0 then invalid_arg "ArrayTk.Split.amass: inner size must be strictly greater than zero" else
    let n = Array.length xs in
    let inner_sizes = Array.make (n / inner_size) (inner_size) in
    split ~inner_sizes xs

  let amass_by_outer_size ~outer_size xs =
    let g = outer_size in
    if g <= 0 then invalid_arg "ArrayTk.Split.amass_by_outer_size: outer size must be strictly greater than zero" else
    let n = Array.length xs in
    let inner_size =
      let k = n / g in
      if n mod g > 0 then k+1 else k (* I want exactly g groups *)
    in
    let inner_sizes = Array.make (n / inner_size) (inner_size) in
    split ~min_outer_size:g (* <= this provoke a very strange filling discipline *) ~inner_sizes xs

  (* Generalized amass: *)
  let amassg ?inner_size ?outer_size =
    match inner_size, outer_size with
    | (Some inner_size), _ -> amass ~inner_size
    | _, (Some outer_size) -> amass_by_outer_size ~outer_size
    | None, None ->
        invalid_arg "ArrayTk.Split.amassg: at least one of the parameters ~inner_size or ~outer_size must be provided"

  (* Interface (remove optional parameters: the user doesn't provide the total of inner sizes): *)
  let split ~inner_sizes xs : 'a tt * play =
    split ?total_size:None ?min_outer_size:None ~inner_sizes xs

  let split_like yss =
    let play = import yss in
    fun xs -> let xss = replay play xs in (xss, play)

  (* Transpose a play returns another play: *)
  (*
  open ArrayTk ;;
  let play = (5, [|3;2|]) ;;

  let perm, play' = Split.transpose play ;;
    val perm : Permutation.play = [|0; 3; 1; 4; 2|]
    val play' : Split.play = (5, [|2; 2; 1|])

  let perm', play'' = Split.transpose play' ;;
    val perm' : Permutation.play = [|0; 2; 4; 1; 3|]
    val play'' : Permutation.play = (5, [|3; 2|])

  Permutation.compose perm perm' ;;
    - : Permutation.play = [|0; 1; 2; 3; 4|]
  *)
  let transpose ?force ((n, ns) : play) : Permutation.play * play =
    if n=0 then ([||], (0, [||])) else (* continue: *)
    (* --- *)
    let force = (force = Some ()) in
    let js = Array.map (fun _ -> 0) ns in (* current indexes *)
    let min_cols, max_cols = Array.fold_left (fun (s0,s1) nc -> (min s0 nc),(max s1 nc)) (ns.(0), ns.(0)) ns in
    let () = if (min_cols = 0) && (not force) then (invalid_arg "ArrayTk.transpose: empty row") in
    let inner_sizes = Array.make (max_cols) 0 in
    let i = ref 0 in (* i is the global index i=0..(n-1) *)
    let () =
      while (!i < n) do
        Array.iteri
          (fun c nc ->
            let j = js.(c) in (* current index of the class c *)
            if j < nc then begin
              js.(c) <- j + 1;
              inner_sizes.(j) <- inner_sizes.(j) + 1;
              incr i;
              end)
          (ns)
      done
    in
    (* --- *)
    let js = Array.map (fun _ -> 0) inner_sizes in (* current indexes *)
    let ps = Array.map (fun ni -> Array.make ni 0) inner_sizes in (* (structured) permutation *)
    let i = ref 0 in
    let () =
      while (!i < n) do
        Array.iteri
          (fun c nc ->
            let j = js.(c) in (* current index of the class c *)
            if j < nc then begin
              ps.(c).(j) <- !i;
              (* let () = Printf.kfprintf flush stderr "ps.(%d).(%d) <- %d;\n" c j !i in *)
              js.(c) <- j + 1;
              incr i;
              end)
          (inner_sizes)
      done
    in
    (* --- *)
    let perm = Array.concat (Array.to_list ps) in
    let play = (n, inner_sizes) in
    (perm, play)


end (* Split *)


(* Stessa idea che per il sorting: aggiungo gli indici per avere una traccia della ristrutturazione *)
module Partition = struct

  type play = (index t) t
   and class_index = int (* 0..(n-1) *)
  (* --- *)
   and 'a source = 'a t
   and 'a target = 'a tt

  (* Controllo sulla lunghezza di xs rispetto alla lunghezza dell'originale? *)
  let replay play xs = Array.map (Array.map (fun j -> xs.(j))) play

  (* Fantastico: definita in termini di Permutation.rewind dopo il flattening dei due argomenti: *)
  let rewind play yss =
    let perm_play = Split.flatten play in
    let ys        = Split.flatten yss  in
    Permutation.rewind perm_play ys

  let partition_make_right_now ?(min_outer_size=0) ~outer_size cls (* classes: i -> c *) xs (* elements: i -> x *) =
    if outer_size = 0 then Array.make (min_outer_size) [||] else (* continue: *)
    (* --- *)
    let size = max (min_outer_size) (outer_size) in
    let acc  = Array.make (size) [] in
    let card = Array.make (size)  0 in
    let ()   = Array.iteri (fun i x -> let c = cls.(i) in (acc.(c) <- x :: acc.(c);  card.(c) <- card.(c)+1)) xs in
    let yss  = Array.mapi (fun i ys -> Tools.array_of_known_length_list ~reversing:true card.(i) ys) acc in
    yss

  let partition_errmsg1 = "ArrayTk.Partition.partition: classifier must provide only non-negative integers"
  let partition_errmsg2 = "ArrayTk.Partition.partition: classifier exceed the provided size limit"
  let partition_errmsg3 = "ArrayTk.Partition.partition: outer size must be non-negative"

  let partition_make_without_size ?min_outer_size f xs =
    let cls, max_index =
      Tools.mape
        (fun m i x ->
           let c = (f i x) in
           let () = (if (c<0) then invalid_arg partition_errmsg1) in
           let m = if c>m then c else m in (* m = max c m *)
           (c,m))
        (-1) xs
    in
    (* --- *)
    let outer_size = max_index + 1 in
    partition_make_right_now ?min_outer_size ~outer_size cls xs

  let partition_make_with_size ?min_outer_size ~outer_size f xs =
    let () = (if (outer_size<0) then invalid_arg partition_errmsg3) in
    (* --- *)
    let cls =
      Array.mapi
        (fun i x ->
           let c = (f i x) in
           let () = (if (c<0) then invalid_arg partition_errmsg1) in
           let () = (if (c>=outer_size) then invalid_arg partition_errmsg2) in
           c)
         xs
    in
    (* --- *)
    partition_make_right_now ?min_outer_size ~outer_size cls xs

  (* Interface: *)
  let partitioni ?outer_size ?min_outer_size f xs =
    match outer_size with
    | None            -> partition_make_without_size ?min_outer_size f xs
    | Some outer_size -> partition_make_with_size    ?min_outer_size ~outer_size f xs

  (* Redefined to register the play with the usual trick, i.e. pairing the values with their indexes: *)
  let partitioni ?outer_size ?min_outer_size f xs =
    let xjs = Array.mapi (fun j x -> (x,j)) xs in
    let yss = partitioni ?outer_size ?min_outer_size (fun i (x,j) -> f i x) xjs in
    (* --- *)
    let play   = Array.map (Array.map snd) yss in
    let result = Array.map (Array.map fst) yss in
    result, play

  (* Same tool but forgetting indexes in the classifier: *)
  let partition ?outer_size ?min_outer_size f xs =
    (* Complexify f in order to call partitioni: *)
    partitioni ?outer_size ?min_outer_size (fun i x -> f x) xs

  (* Generalized partitioning: *)
  let partitiong ?outer_size ?min_outer_size f s0 xs =
    (* Simplify f in order to call partitioni: *)
    let f' = Tools.simplify_generalized_function_for_mapi f s0 in
    partitioni ?outer_size ?min_outer_size f' xs

  let uniq ?compare ?sort xs =
    let xjs = Array.mapi (fun j x -> (x,j)) xs in
    let compare1, fake_compare1, unicity = Tools.make_compare ?compare () in
    let fake_compare2 = Tools.extend_compare (fake_compare1) in
    (* --- *)
    let yjs, _perm_play = Permutation.array_sort ~compare:fake_compare2 xjs in
    if !unicity then
      let result = [| xs; [||] |] in
      let play   = [| (Tools.range (Array.length xs)); [||] |] in
      (result, play)
    else (* continue: *)
    (* --- *)
    (* Make the partition in linear time: *)
    let (y0,j0) = yjs.(0) in
    let p0, p1, _ =
      Tools.fold_lefti ~start:1
        (fun i (p0, p1, y0) ((y1, j1) as z) ->
           if compare1 y0 y1 = 0 then (p0, z::p1, y0) else (z::p0, p1, y1))
        ([(y0,j0)], [], y0) yjs
    in
    (* --- *)
    let p0 = (Array.of_list p0) in
    let p1 = (Array.of_list p1) in
    (* --- *)
    if sort = None then (* restore the order of appearence *)
      begin
      let y0s, j0s = Tuple_array.split2 p0 in
      let y1s, j1s = Tuple_array.split2 p1 in
      (* --- *)
      let j0s, pl0 = Permutation.array_sort j0s in
      let j1s, pl1 = Permutation.array_sort j1s in
      (* --- *)
      let y0s = Permutation.replay pl0 y0s in
      let y1s = Permutation.replay pl1 y1s in
      (* --- *)
      let play   = [| j0s; j1s |] in
      let result = [| y0s; y1s |] in
      (* --- *)
      (result, play)
      end
    else  (* leave in the current order (obtained with compare) *)
      begin
      let p0 = Permutation.reverse p0 in
      let p1 = Permutation.reverse p1 in
      (* --- *)
      let y0s, j0s = Tuple_array.split2 p0 in
      let y1s, j1s = Tuple_array.split2 p1 in
      (* --- *)
      let play   = [| j0s; j1s |] in
      let result = [| y0s; y1s |] in
      (* --- *)
      (result, play)
      end

  (* Example:
  let xs = [| 'A';'C';'D';'A';'B';'C';'D';'D';'A' |] ;;
  let ys = Array.init (Array.length xs) (fun i -> i) ;;

  let xys = ArrayTk.Tuple_array.combine xs ys ;;
    val xys : (char * int) array =
      [|('A', 0); ('C', 1); ('D', 2); ('A', 3); ('B', 4); ('C', 5); ('D', 6); ('D', 7); ('A', 8)|]

  let gs = ArrayTk.Partition.group_by (fun xy -> xy) xys  ;;
    val gs : (char * int array) array =
      [|('A', [|0; 3; 8|]); ('B', [|4|]); ('C', [|1; 5|]); ('D', [|2; 6; 7|])|]
  *)
  let group_by ?compare f rs =
    let ks, ds = Tuple_array.split2 (Array.map f rs) in
    let kss, uplay = uniq ?compare ~sort:() ks in
    (* --- *)
    let ks', splay = Sorting.sort ~stable:() ?compare ks in
    let ds' = Array.map (Sorting.assoc_all splay ds) kss.(0) in
    Tuple_array.combine2 kss.(0) ds'

  (* Example (continue):
  let f = ArrayTk.Partition.group_by_assoc (fun xy -> xy) xys  ;;
  f 'A' ;;
    - : int array = [|0; 3; 8|]
  f 'B' ;;
    - : int array = [|4|]
  f 'Z' ;;
  - : int array = [||]
  *)
  let group_by_assoc ?compare f rs =
    let ks, ds = Tuple_array.split2 (Array.map f rs) in
    (* --- *)
    let ks', splay = Sorting.sort ~stable:() ?compare ks in
    Sorting.assoc_all splay ds

  let filter p xs =
    let class_index_of_bool = function true -> 0 | false -> 1 in
    partitioni ~outer_size:2 (fun i x -> class_index_of_bool (p x)) xs

  let filteri p xs =
    let class_index_of_bool = function true -> 0 | false -> 1 in
    partitioni ~outer_size:2 (fun i x -> class_index_of_bool (p i x)) xs

  let filterg p s0 xs =
    filteri (Tools.simplify_generalized_function_for_mapi p s0) xs

  (* --- *)

  let round_robin ~outer_size =
    partitioni ?min_outer_size:None ~outer_size (fun i _ -> i mod outer_size)

end (* Partition *)

(* In this version a partition appears as a composition of a permutation followed by a split: *)
module Partition_v2 = struct

  type play = (Permutation.play) * (Split.play)  (* (index t) * (total_size * inner_size t) *)
  (* --- *)
   and play_v1 = Partition.play  (* index tt *)
   and play_v2 = play
  (* --- *)
   and 'a source = 'a t
   and 'a target = 'a tt

  (*  play_v2  =  ((Split.flatten play_v1), (Split.import play_v1)) *)
  let import (play_v1) : play_v2 =
    let pplay = Split.flatten play_v1 in
    let splay = Split.get_total_and_inner_sizes play_v1 in
    (pplay, splay)

  (*  play_v1  =  Split.replay (play_v2)₁ (play_v2)₂ *)
  let export ((pplay, splay) : play_v2) : play_v1 =
    Split.replay splay pplay

  (* Composition of Split.replay then Permutation.replay: *)
  let replay (pplay, splay) xs =
    let ys  = Permutation.replay pplay xs in
    let yss = Split.replay splay ys in
    yss

  (* Composition of Permutation.rewind then Split.rewind: *)
  let rewind (pplay, splay) yss =
    let ys = Split.rewind splay yss in
    let xs = Permutation.rewind pplay ys in
    xs

end (* Partition_v2 *)

(* ---
(* Metodo funzionale: *)
let xs1,  play = ArrayTk.operation1       args xs   in
let xs2,  play = ArrayTk.operation2 ~play args xs1  in
let xss3, play = ArrayTk.operation3 ~play args xs2  in
let xs4,  play = ArrayTk.operation4 ~play args xss3 in
let ys4 = ArrayTk.replay play ys in
let zs4 = ArrayTk.replay play zs in

(* Metodo imperativo: *)
let () = ArrayTk.follow xs in
let xs1  = ArrayTk.operation1 args xs  in
let xs2  = ArrayTk.operation2 args xs1 in
let xss3 = ArrayTk.operation3 args xs2 in
let xs4  = ArrayTk.operation4 args xss3 in
let ys4  = ArrayTk.replay xs ys in
let zs4  = ArrayTk.replay xs zs in
let () = ArrayTk.free xs in

OSS: il metodo imperativo permette solo di registrare una sequenza di azioni,
     mentre il metodo funzionale permette anche di registrare un'attività arborescente
     (componendo i play in maniera non banale, cioè utilizzandone diversi)
*)

(*

type play =
  | PSwap         of Swap.play
  | PPermutation  of Permutation.play
  | PSplit        of Split.play
  | PPartition    of Partition.play
  | PPartition_v2 of Partition_v2.play

let replay_of_play = function
| PSwap         (play) -> Swap.replay play
| PPermutation  (play) ->
| PSplit        (play) ->
| PPartition    (play) ->
| PPartition_v2 (play) ->

type ('a,'b) step =
(*   | FIdentity     : unit -> ('a,'b) step *)
  | FSwap         : ('a Swap.source         -> 'a Swap.target)         -> ('a Swap.source,         'a Swap.target)         step
  | FPermutation  : ('a Permutation.source  -> 'a Permutation.target)  -> ('a Permutation.source,  'a Permutation.target)  step
  | FSplit        : ('a Split.source        -> 'a Split.target)        -> ('a Split.source,        'a Split.target)        step
  | FPartition    : ('a Partition.source    -> 'a Partition.target)    -> ('a Partition.source,    'a Partition.target)    step
  | FPartition_v2 : ('a Partition_v2.source -> 'a Partition_v2.target) -> ('a Partition_v2.source, 'a Partition_v2.target) step

type ('a,'b) playfun =
  | Step          : ('a,'b) step -> ('a,'b) playfun
  | FComp10       : ('a t, 'a t)  playfun  *  ('a t, index)  step -> ('a t, index) playfun
  | FComp11       : ('a t, 'a t)  playfun  *  ('a t,  'a t)  step -> ('a t, 'a t)  playfun
  | FComp12       : ('a t, 'a t)  playfun  *  ('a t,  'a tt) step -> ('a t, 'a tt) playfun
  | FComp21       : ('a t, 'a tt) playfun  *  ('a tt, 'a t)  step -> ('a t, 'a t)  playfun

let create () = Step(Id ())

(* L'idea è di tradurre una (play list) in una ('a,'b) playfun: *)
let rec playfun_of_playlist acc pl =
  match acc with
  | [] ->

| PSwap         (play) ->
| PPermutation  (play) ->
| PSplit        (play) ->
| PPartition    (play) ->
| PPartition_v2 (play) ->

*)

(*let append (pf : ('a,'b) playfun) (s: ('b,'c) step) : ('a,'c) playfun =
  match s with
  | FPermutation(
Comp (cap,f)*)

(*
let rec eval : type a b. (a,b) cap -> a -> b =
  fun cap x ->
    match cap with
    | Step f -> f x
    | Comp (cap',f) -> f (eval cap' x)*)


