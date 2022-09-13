(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2019  Jean-Vincent Loddo

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

(** Combinatoric selections of n elements to k places,
    ordered or unordered, with or without repetitions.
    Elements are represented by indexes, i.e. by integers
    from 0 to (n-1). *)

type n = int      (* number of elements *)
 and k = int      (* number of places *)
 and index = int  (* 0..(n-1) *)

(* Simple tools: *)
module Tools = struct

  (* Quick-and-dirty memory size calculation (Marshal preserves sharing by default): *)
  let size_of x =
    let b = Bytes.length (Marshal.to_bytes x [Marshal.Closures]) in
    (`bytes b, `Kb (b/1024), `Mb (b/(1048576)))

end (* Tools *)

(* val for_int_range : range:(int * int * int) -> init:'s -> ('s -> int -> 's) -> 's *)
let for_int_range ~range ~init : ('s -> int -> 's) -> 's =
  let (start, stop, step) = range in
  (* --- *)
  let sr = ref init in    (* state reference (s) *)
  let xr = ref start in   (* value reference (x) *)
  (* --- *)
  begin fun body ->
    while (!xr < stop) do
      let x = !xr in
      (sr := body !sr x);
      (xr := x + step);
    done;
    !sr
  end

(* Unused in the rest of the module: *)
let factorial n =
  for_int_range ~range:(2,n+1,1) ~init:1 (fun s n ->
    let s = s*n in
    if s<0 then failwith "factorial" else s)

(* n! / k! with n>=k *)
let factorial_ratio (n,k) =
  let () = assert (n >= k) in
  for_int_range ~range:(k+1,n+1,1) ~init:1 (fun s n ->
    let s = s*n in
    if s<0 then failwith "factorial_ratio" else s)
(* Memoize for (n-k)>20 (result is >= 20! => failure) *)
let factorial_ratio = Memo.memoize ~skip:(fun (n,k) -> (n-k)>20) factorial_ratio

(* Ex: int_power 2 10 = 1024 *)
let int_power =
  let rec pow a0 n k =
    let a1 = a0 * (if k mod 2 = 0 then 1 else n) in
    if a1<a0 || n<0 then failwith "int_power" else (* continue: *)
    if k = 0 then a0 else pow (a1) (n * n) (k / 2) in
  fun n k ->
    if k=0 then 1 else (* continue with k≥1: *)
    if n=0 then 0 else (* continue with n≥1: *)
    try
      pow 1 n k
    with Failure _ ->  begin
      (* try now with float numbers: *)
      let y = int_of_float ((float_of_int n) ** (float_of_int k)) in
      if y <= 0 then failwith "int_power" else y
  end

(* Defined only for n ≥ k ≥ 0 *)
let binomial (n,k) =
  let m = min k (n-k) in
  if m < 0 then invalid_arg (Printf.sprintf "binomial (%d,%d)" n k) else
  (* --- *)
  let rec loop j s =
    if s < 0 (* int overflow *) then
      failwith (Printf.sprintf "Sorry, binomial (%d,%d) is greater than max_int (%d)" n k max_int)
    else (* continue: *)
    if j = m then s
    else loop (j+1) ((s * (n - j)) / (j+1))
  in
  (* --- *)
  loop 0 1

(* Memoize for n<=100 *)
let binomial = Memo.memoize ~skip:(fun (n,k) -> n>100) binomial

(* Count selections: *)
let count ?unordered ?repetitions =
  (* --- *)
  let manage_basic_cases_then (continuation) ((n,k) as nk) =
    (* --- *)
    if (n<0) || (k<0)  then invalid_arg "Selections.count" else (* continue: *)
    if k=0 then 1 else (* continue with k≥1: *)
    if n=0 then 0 else (* continue with n≥1: *)
    continuation nk
  in
  (* --- *)
  let continuation =
    match unordered, repetitions with
    (* --- *)
    (* (Linear_power) The order is relevant, elements cannot be duplicated: *)
    | None, None ->
        fun (n,k) ->
          if (k>n) then 0 else
          factorial_ratio (n, (n-k))
    (* --- *)
    (* (Power) The order is relevant, elements can be duplicated: *)
    | None, Some () ->
        fun (n,k) -> int_power n k
    (* --- *)
    (* (Unordered_linear_power) The order is irrelevant, elements cannot be duplicated: *)
    | Some (), None ->
       fun ((n,k) as nk) ->
         if (k>n) then 0 else
         binomial nk
    (* --- *)
    (* (Unordered_power) The order is irrelevant, elements can be duplicated: *)
    | Some (), Some () ->
        fun (n,k) ->
          let n' = (n + k - 1) in
          binomial (n',k)
  in
  (* --- *)
  manage_basic_cases_then (continuation)
(* --- *)

(* val shared_singleton : index -> index list *)
let shared_singleton =
  let shared : index list -> index list = Extreme_sharing.make_id () in
  let max_shared_index = 255 in
  fun i -> if i <= max_shared_index then shared [i] else [i]

(* Tool for testing and debugging: *)
let fill_internal_hashtbl ?(max_index=255) (skip) (memoized_f) () =
  let pr fmt = Printf.kfprintf flush stderr fmt in
  for_int_range ~range:(1, (max_index+1), 1) ~init:() (fun () n ->
    for_int_range ~range:(1, (max_index+1), 1) ~init:() (fun () k ->
      if skip (n,k) then () else (* continue: *)
      let () = pr "\rFilling hash table with (n,k) = (%d,%d) ..." n k in
      ignore (memoized_f (n,k))
    ))

(* Tool making a "skip" function used for memoization in the next modules: *)
let make_skip_function ~count ~max_array_size () =
  fun ?(max_array_size=max_array_size) (n,k) -> (* n≥1, k≥1 *)
    try
      if (n>255) || (k>255) then true (* skip! *) else (* continue: *)
      let lists_no = count (n,k) in
      (* The size of each list in the array is proportional to k: *)
      let array_size = lists_no * k in
      if array_size <= 0 (* overflow *) then true else (array_size > max_array_size)
    with _ -> true

(*--- *)

module type Details =
  sig
    val count : n * k -> int
    val make  : n * k -> index list array
    (* --- *)
    (* Memoization details: *)
    val max_array_size : int
    val skip           : ?max_array_size:int (* bytes *) -> n * k -> bool
    val ht             : (n * k, index list array) Hashtbl.t
    val hashtbl_size   : unit -> [`bytes of int] * [`Kb of int] * [`Mb of int]
    val hashtbl_fill   : unit -> unit
    val hashtbl_reset  : unit -> unit
  end


(* ?unordered:None  ~repetitions:() *)
module Power = struct

IFDEF DOCUMENTATION_OR_DEBUGGING THEN
  (* Generate an array of lists of indexes (with repetitions). Example:
      # make_model 4 2 ;;
      - : index list array = [| [0; 0]; [0; 1]; [0; 2]; [0; 3];  [1; 0]; [1; 1]; [1; 2]; [1; 3];
                                [2; 0]; [2; 1]; [2; 2]; [2; 3];  [3; 0]; [3; 1]; [3; 2]; [3; 3] |]  *)
  let rec make_model n k : (index list) array =
    if (k=0) then [|[]|] else (* continue: *)
    if (k=1) then Array.init n (fun i -> [i]) else (* continue: *)
    let xss =
      let r = make_model (n) (k-1) in (* not memoized *)
      Array.init n (fun i ->
        Array.map (fun js -> i::js) r
        )
    in
    Array.concat (Array.to_list xss)
ENDIF

  (* Recursive scheme of previous function (next step will be the memoization of this scheme).
     The induction basis here is k=1 *)
  let make_scheme self (n,k) : (index list) array =
    if (k=1) then Array.init n (shared_singleton) (* fun i -> [i] *) else (* continue with k≥2: *)
    let xss =
      let r = self (n, (k-1)) in (* self should be memoized *)
      Array.init n (fun i ->
        Array.map (fun js -> i::js) r
        )
    in
    Array.concat (Array.to_list xss)

  (* --- *)
  let max_array_size = 4096
  let count = count ?unordered:None ~repetitions:()
  let skip  = make_skip_function ~count ~max_array_size ()
  (* --- *)
  let make, ht =
    let id = Extreme_sharing.Array.id () in
    Memo.memoize_scheme_and_get_table ~size:1024 ~skip:(skip ~max_array_size) ~sharing:(Some id) make_scheme

  (* Top-level function. Hp: n≥0, k≥0  *)
  let make (n,k) =
    if (n<0) || (k<0)  then invalid_arg "Selections.make" else (* continue: *)
    if (k=0) then [|[]|] (* n⁰ = 0⁰ = 1 *) else (* continue with k≥1 *)
    if (n=0) then [||]   (* 0ᵏ = 0 *)      else (* continue with n≥1 *)
    make (n,k)

  (* Get the current size of the hashtbl: *)
  let hashtbl_size  () = Tools.size_of (ht)
  let hashtbl_fill  () = fill_internal_hashtbl (skip) (make) ()
  let hashtbl_reset () = Hashtbl.reset (ht)

  (* Results:
      # Power.hashtbl_fill () ;;
      # Power.hashtbl_size () ;;
      (`bytes 1621566, `Kb 1583, `Mb 1)
  *)

end (* Power *)


(* ~unordered:()  ~repetitions:() *)
module Unordered_power = struct

IFDEF DOCUMENTATION_OR_DEBUGGING THEN
  (* Generate an array of lists of indexes (with repetitions, abstracting from the order of appearance). Example:
      # make_model 4 2 ;;
      - : index list array = [| [0; 0]; [0; 1]; [0; 2]; [0; 3];  [1; 1]; [1; 2]; [1; 3];  [2; 2]; [2; 3];  [3; 3]|]  *)
  let rec make_model n k : (index list) array =
    if (k=0) then [|[]|] else (* continue: *)
    if (k=1) then Array.init n (fun i -> [i]) else (* continue: *)
    let shift i js = i::(List.map (fun j -> j+i) js) in
    let xss =
      Array.init n (fun i ->
        let r = make_model (n-i) (k-1) in (* not memoized *)
        Array.map (fun js -> shift i js) r
        )
    in
    Array.concat (Array.to_list xss)
ENDIF

  (* Recursive scheme of previous function (next step will be the memoization of this scheme).
     The induction basis here is k=1 *)
  let make_scheme self (n,k) : (index list) array =
    if (n=0) then [||] (* optimization, not necessary *) else (* continue with n≥1 *)
    if (k=1) then Array.init n (shared_singleton) (* fun i -> [i] *) else (* continue with k≥2: *)
    let shift i js = i::(List.map (fun j -> j+i) js) in
    let xss =
      Array.init n (fun i ->
        let r = self ((n-i), (k-1)) in (* self should be memoized *)
        Array.map (fun js -> shift i js) r
        )
    in
    Array.concat (Array.to_list xss)

  (* --- *)
  let max_array_size = 2048
  let count = count ~unordered:() ~repetitions:()
  let skip = make_skip_function ~count ~max_array_size ()
  (* --- *)

  let make, ht =
    let id = Extreme_sharing.Array.id () in
    Memo.memoize_scheme_and_get_table ~size:1024 ~skip:(skip ~max_array_size) ~sharing:(Some id) make_scheme

  (* Top-level function. Hp: n≥0, k≥0  *)
  let make (n,k) =
    if (n<0) || (k<0)  then invalid_arg "Selections.make" else (* continue: *)
    if (k=0) then [|[]|] (* n⁰ = 0⁰ = 1 *) else (* continue with k≥1 *)
    if (n=0) then [||]   (* 0ᵏ = 0 *)      else (* continue with n≥1 *)
    make (n,k)

  (* Get the current size of the hashtbl: *)
  let hashtbl_size  () = Tools.size_of (ht)
  let hashtbl_fill  () = fill_internal_hashtbl (skip) (make) ()
  let hashtbl_reset () = Hashtbl.reset (ht)

  (* Results:
      # Unordered_power.hashtbl_fill () ;;
      # Unordered_power.hashtbl_size () ;;
      (`bytes 3653032, `Kb 3567, `Mb 3)
  *)

end (* Unordered_power *)


(* ?unordered:None  ?repetitions:None *)
module Linear_power = struct

IFDEF DOCUMENTATION_OR_DEBUGGING THEN
  (* Generate an array of lists of indexes (without repetitions). Example:
      # make_model 4 2 ;;
      - : index list array = [|[0; 1]; [0; 2]; [0; 3];  [1; 0]; [1; 2]; [1; 3];  [2; 0]; [2; 1]; [2; 3];  [3; 0]; [3; 1]; [3; 2]|] *)
  let rec make_model n k : (index list) array =
    if (k=0) then [|[]|] else (* continue: *)
    if (k=1) then Array.init n (fun i -> [i]) else (* continue: *)
    if (k>n) then [||] else (* continue: *)
    let shift i js = i::(List.map (fun j -> if j<i then j else j+1) js) in
    let xss =
      let r = make_model (n-1) (k-1) in (* not memoized *)
      Array.init n (fun i ->
        Array.map (fun js -> shift i js) r
        )
    in
    Array.concat (Array.to_list xss)
ENDIF

  (* Recursive scheme of previous function (next step will be the memoization of this scheme).
     The induction basis here is k=1 *)
  let make_scheme self (n,k) : (index list) array =
    if (k=1) then Array.init n (shared_singleton) (* fun i -> [i] *) else (* continue with k≥2: *)
    let shift i js = i::(List.map (fun j -> if j<i then j else j+1) js) in
    let xss =
      let r = self ((n-1),(k-1)) in (* self should be memoized *)
      Array.init n (fun i ->
        Array.map (fun js -> shift i js) r
        )
    in
    Array.concat (Array.to_list xss)

  (* --- *)
  let max_array_size = 4096
  let count = count ?unordered:None ?repetitions:None
  let skip  = make_skip_function ~count ~max_array_size ()
  (* --- *)
  let make, ht =
    let id = Extreme_sharing.Array.id () in
    Memo.memoize_scheme_and_get_table ~size:1024 ~skip:(skip ~max_array_size) ~sharing:(Some id) make_scheme

  (* Top-level function. Hp: n≥0, k≥0  *)
  let make (n,k) =
    if (n<0) || (k<0)  then invalid_arg "Selections.make" else (* continue: *)
    if (k=0) then [|[]|] (* n⁰ = 0⁰ = 1 *) else (* continue with k≥1 *)
    if (k>n) then [||]   (* no solutions without repetitions *) else (* continue with n≥k: *)
    make (n,k)

  (* Get the current size of the hashtbl: *)
  let hashtbl_size  () = Tools.size_of (ht)
  let hashtbl_fill  () = fill_internal_hashtbl (skip) (make) ()
  let hashtbl_reset () = Hashtbl.reset (ht)

  (* Results:
      # Linear_power.hashtbl_fill () ;;
      # Linear_power.hashtbl_size () ;;
      (`bytes 4182936, `Kb 4084, `Mb 3)
  *)

end (* Linear_power *)


(* ~unordered:()  ?repetitions:None *)
module Unordered_linear_power = struct

IFDEF DOCUMENTATION_OR_DEBUGGING THEN
  (* Generate an array of lists of indexes (without repetitions, abstracting from the order of appearance). Example:
      # make_model 4 2 ;;
      - : index list array = [|[0; 1]; [0; 2]; [0; 3]; [1; 2]; [1; 3]; [2; 3]|] *)
  let rec make_model n k : (index list) array =
    if (k=0) then [|[]|] else (* continue: *)
    if (k=1) then Array.init n (fun i -> [i]) else (* continue: *)
    if (k>n) then [||] else (* continue: *)
    let shift i js = let h=i+1 in i::(List.map (fun j -> j+h) js) in
    let xss =
      Array.init n (fun i ->
        let r = make_model (n-1-i) (k-1) in (* not memoized *)
        Array.map (fun js -> shift i js) r
        )
    in
    Array.concat (Array.to_list xss)
ENDIF

  (* Recursive scheme of previous function (next step will be the memoization of this scheme).
     The induction basis here is k=1 *)
  let make_scheme self (n,k) : (index list) array =
    if (k=1) then Array.init n (shared_singleton) (* fun i -> [i] *) else (* continue with k≥2: *)
    if (k>n) then [||]   else (* continue: *)
    let shift i js = let h=i+1 in i::(List.map (fun j -> j+h) js) in
    let xss =
      Array.init n (fun i ->
        let r = self ((n-1-i),(k-1)) in (* self should be memoized *)
        Array.map (fun js -> shift i js) r
        )
    in
    Array.concat (Array.to_list xss)

  (* --- *)
  let max_array_size = 2048
  let count = count ~unordered:() ?repetitions:None
  let skip  = make_skip_function ~count ~max_array_size ()
  (* --- *)
  let make, ht =
    let id = Extreme_sharing.Array.id () in
    Memo.memoize_scheme_and_get_table ~size:1024 ~skip:(skip ~max_array_size) ~sharing:(Some id) make_scheme

  (* Top-level function. Hp: n≥0, k≥0  *)
  let make (n,k) =
    if (n<0) || (k<0)  then invalid_arg "Selections.make" else (* continue: *)
    if (k=0) then [|[]|] (* n⁰ = 0⁰ = 1 *) else (* continue with k≥1 *)
    if (k>n) then [||]   (* no solutions without repetitions *) else (* continue with n≥k: *)
    make (n,k)

  (* Get the current size of the hashtbl: *)
  let hashtbl_size  () = Tools.size_of (ht)
  let hashtbl_fill  () = fill_internal_hashtbl (skip) (make) ()
  let hashtbl_reset () = Hashtbl.reset (ht)

  (* Results:
      # Unordered_linear_power.hashtbl_fill () ;;
      # Unordered_linear_power.hashtbl_size () ;;
      (`bytes 5294635, `Kb 5170, `Mb 5)
  *)

end (* Unordered_linear_power *)


let make ?unordered ?repetitions =
  (* --- *)
  match unordered, repetitions with
  (* The order is relevant, elements cannot be duplicated: *)
  | None, None -> Linear_power.make
  (* --- *)
  (* The order is relevant, elements can be duplicated: *)
  | None, Some () -> Power.make
  (* --- *)
  (* The order is irrelevant, elements cannot be duplicated: *)
  | Some (), None -> Unordered_linear_power.make
  (* --- *)
  (* The order is irrelevant, elements can be duplicated: *)
  | Some (), Some () -> Unordered_power.make


let permutations n = make ?unordered:None ?repetitions:None (n,n)
let combinations   = make ~unordered:()   ?repetitions:None
let subsets n =
  let ks = Array.to_list (Array.init (n+1) (fun k -> k)) in
  Array.concat (List.map (fun k -> combinations (n,k)) ks)

let half_partitions n =
  if n<=0 then [||] else (* continue: *)
  let () = if (n mod 2) <> 0 then
    invalid_arg (Printf.sprintf "Selections.half_partitions: the provided argument (%d) is not even" n)
  in
  let k = n / 2 in
  let cs = combinations (n,k) in
  let h = (Array.length cs) in
  Array.init (h/2) (fun i -> cs.(i), cs.(h-1-i))

let count_half_partitions n =
  let () = if (n mod 2) <> 0 then
    invalid_arg (Printf.sprintf "Selections.count_half_partitions: the provided argument (%d) is not even" n)
  in
  (binomial (n, n/2)) / 2

(* Stirling number of the second kind.
   val stirling2k : n  * k -> int  *)
let stirling2k (n,k) =
  let rec s n k = if (n=0 && k=0) then 1 else if (n=0 || k=0) then 0 else s (n-1) (k-1) + k * s (n-1) k
  in s n k

(* Equals to stirling2k (n,2) but calculated more efficiently: *)
let count_bipartitions n = (int_power 2 (n-1)) - 1

(* (bipartitions 4) ;;
   - : (int list * int list) array =
   [| ([0], [1; 2; 3]);  ([1], [0; 2; 3]);  ([2], [0; 1; 3]);  ([3], [0; 1; 2]);
      ([0; 1], [2; 3]);  ([0; 2], [1; 3]);  ([0; 3], [1; 2])|] *)
let bipartitions n =
  if n<=1 then [||] else (* continue: *)
  let bs = subsets n in
  let h = (Array.length bs) in
  Array.init (h/2-1) (fun i -> bs.(i+1), bs.(h-2-i))


let singletons_bipartitions n =
  if n<=1 then [||] else (* continue: *)
  let cs1 = combinations (n,1) in
  let cs2 = combinations (n,(n-1)) in
  let h = (Array.length cs1) in
  let () = assert ((Array.length cs2) = h) in
  Array.init h (fun i -> cs1.(i), cs2.(h-1-i))


IFDEF DOCUMENTATION_OR_DEBUGGING THEN

let fill_all_ht () = begin
  let pr fmt = Printf.kfprintf flush stderr fmt in
  (* --- *)
  let () = pr "\r* Filling Power.ht\t\t\t\n" in
  let () = Power.hashtbl_fill () in
  (* --- *)
  let () = pr "\r* Filling Linear_power.ht\t\t\t\n" in
  let () = Linear_power.hashtbl_fill () in
  (* --- *)
  let () = pr "\r* Filling Unordered_power.ht\t\t\t\n" in
  let () = Unordered_power.hashtbl_fill () in
  (* --- *)
  let () = pr "\r* Filling Unordered_linear_power.ht\t\t\t\n" in
  let () = Unordered_linear_power.hashtbl_fill () in
  ()
  end

let stats_all_ht () =
  ((`Power (Hashtbl.stats Power.ht)),
   (`Liner_power (Hashtbl.stats Linear_power.ht)),
   (`Unordered_power (Hashtbl.stats Unordered_power.ht)),
   (`Unordered_linear_power (Hashtbl.stats Unordered_linear_power.ht)))

let total_of_ht_sizes () =
  let size_of = Tools.size_of in
  size_of [| (Power.ht); (Linear_power.ht); (Unordered_power.ht); (Unordered_linear_power.ht); |]

let size_of_all_ht () =
  let size_of = Tools.size_of in
  ((`Power ((size_of Power.ht), `max_array_size Power.max_array_size)),
   (`Liner_power ((size_of Linear_power.ht), `max_array_size Linear_power.max_array_size)),
   (`Unordered_power ((size_of Unordered_power.ht), `max_array_size Unordered_power.max_array_size)),
   (`Unordered_linear_power ((size_of Unordered_linear_power.ht), `max_array_size Unordered_linear_power.max_array_size)),
   (`TOTAL (total_of_ht_sizes ())))

let test () =
  let pr fmt = Printf.kfprintf flush stderr fmt in
  let max_index = 7 in
  let option_values = [| None; Some () |] in
  (* --- *)
  for_int_range ~range:(0, 2, 1) ~init:() (fun () u ->
    let unordered = option_values.(u) in
    (* --- *)
    for_int_range ~range:(0, 2, 1) ~init:() (fun () r ->
      let repetitions = option_values.(r) in
      (* --- *)
      for_int_range ~range:(0, (max_index+1), 1) ~init:() (fun () n ->
        for_int_range ~range:(0, (n+3), 1) ~init:() (fun () k ->
          let () = pr "\rTesting  ~unordered:%d  ~repetitions:%d  (n,k)=(%d,%d) ..." u r n k in
          let result  = make  ?unordered ?repetitions (n,k) in
          let expcard = count ?unordered ?repetitions (n,k) in
          assert ((Array.length result) = expcard)
        ))))
ENDIF
