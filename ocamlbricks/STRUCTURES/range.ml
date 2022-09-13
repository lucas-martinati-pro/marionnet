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


IFNDEF OCAML4_02_OR_LATER THEN
module Bytes = struct  include String  let to_string x = x  let of_string x = x  end
type bytes = string
ENDIF

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

exception Out_of_range

type 'a cls = unit -> 'a obj (* A range "class",  i.e. an range object generator *)
 and 'a obj = unit -> 'a     (* A range "object", i.e. an object with an internal state and a single method (itself) *)

(* Alias for the interface: *)
type 'a t = 'a cls

type index = int
 and card  = int

(* The empty class: *)
let empty () = fun () -> raise Out_of_range

(* val to_thunk : 'a t -> (unit -> 'a)
   For testing/debugging: *)
let to_thunk cls = cls ()

(* Example:
    # Range.to_list (Range.initi 8 (fun x -> x*x) ()) ;;
    - : (index * int) list =
    [(0, 0); (1, 1); (2, 4); (3, 9); (4, 16); (5, 25); (6, 36); (7, 49)]
    *)
(* val initi : card -> (index -> 'a) -> (index * 'a) cls  (* add the integer index *) *)
let initi n f () : (index * 'a) obj =
  let j = ref 0 in
  fun () ->
    let j0 = !j in
    if (j0 >= n) then raise Out_of_range else (* continue: *)
    let () = incr j in
    (j0, f j0)

(* val init  : card -> (index -> 'a) -> 'a cls *)
let init n f () : 'a obj =
  let j = ref 0 in
  fun () ->
    let j0 = !j in
    if (j0 >= n) then raise Out_of_range else (* continue: *)
    let () = incr j in
    (f j0)

(* val inits : card -> 's -> ('s -> index -> 's * 'a) -> ('s * 'a) cls *)
let inits n s0 f () : ('s * 'a) obj =
  let j = ref 0 in
  let s = ref s0 in
  fun () ->
    let j0 = !j in
    if (j0 >= n) then raise Out_of_range else (* continue: *)
    let ((s1, x) as result) = f !s j0 in
    (incr j; s:=s1; result)

(* val initl : card -> 's -> ('s -> index -> 's * 'a) -> 'a cls  (* equivalent to (map fst) ∘ inits *) *)
let initl n s0 f () : 'a obj =
  let j = ref 0 in
  let s = ref s0 in
  fun () ->
    let j0 = !j in
    if (j0 >= n) then raise Out_of_range else (* continue: *)
    let (s1, x) = f !s j0 in
    (incr j; s:=s1; x)

(* As for arrays, make a constant range: *)
let makei n (x:'a) () : (index * 'a) obj =
  let j = ref 0 in
  fun () ->
    let j0 = !j in
    if (j0 >= n) then raise Out_of_range else (* continue: *)
    let () = incr j in
    (j0, x)

(* As for arrays, make a constant range: *)
let make n (x:'a) () : 'a obj =
  let j = ref 0 in
  fun () ->
    let j0 = !j in
    if (j0 >= n) then raise Out_of_range else (* continue: *)
    let () = incr j in
    x

(* val of_listi : 'a list -> (index * 'a) cls  *)
let of_listi (xs : 'a list) () : (index * 'a) obj =
  let j = ref 0 in
  let r = ref xs in
  fun () ->
    match !r with
    | []    -> raise Out_of_range
    | x::xs ->
        let j0 = !j in
        let () = (r := xs) in
        let () = incr j in
        (j0, x)

(* val of_list : 'a list -> 'a cls  *)
let of_list (xs : 'a list) () : 'a obj =
  let r = ref xs in
  fun () ->
    match !r with
    | []    -> raise Out_of_range
    | x::xs -> (r := xs; x)

(* val of_arrayi : 'a array -> (index * 'a) cls  *)
let of_arrayi (xs : 'a array) () : (index * 'a) obj =
  let n = Array.length xs in
  let j = ref 0 in
  fun () ->
    let j0 = !j in
    if j0 = n then raise Out_of_range else (* continue: *)
    let () = incr j in
    (j0, xs.(j0))

(* val of_array : 'a array -> a cls  *)
let of_array (xs : 'a array) () : 'a obj =
  let n = Array.length xs in
  let j = ref 0 in
  fun () ->
    let j0 = !j in
    if j0 = n then raise Out_of_range else (* continue: *)
    let () = incr j in
    xs.(j0)

(* val of_separated_arrays : 'i array -> 'a array -> ('i * 'a) cls *)
let of_separated_arrays (js : 'i array) (xs : 'a array) : ('i * 'a) cls =
  let n = Array.length js in
  let () = assert ((Array.length xs) = n) in
  fun () ->
    let j = ref 0 in
    fun () ->
      let j0 = !j in
      if j0 = n then raise Out_of_range else (* continue: *)
      let () = incr j in
      (js.(j0), xs.(j0))

(* val of_stringi : string -> (index * char) cls  *)
let of_stringi (xs : string) () : (index * char) obj =
  let n = String.length xs in
  let j = ref 0 in
  fun () ->
    let j0 = !j in
    if j0 = n then raise Out_of_range else (* continue: *)
    let () = incr j in
    (j0, xs.[j0])

(* val of_string : string -> char cls  *)
let of_string (xs : string) () : char obj =
  let n = String.length xs in
  let j = ref 0 in
  fun () ->
    let j0 = !j in
    if j0 = n then raise Out_of_range else (* continue: *)
    let () = incr j in
    xs.[j0]

IFNDEF OCAML4_07_OR_LATER THEN
module Seq = struct
  type 'a t = unit -> 'a node
   and 'a node = Nil | Cons of 'a * 'a t
end
module Hashtbl = struct
  type ('a,'b) t = ('a,'b) Hashtbl.t
  let to_list t = Hashtbl.fold (fun x y l -> (x,y)::l) t []
  (* --- *)
  let list_to_seq xs =
    let rec loop xs () = match xs with
      | [] -> Seq.Nil
      | x :: xs -> Seq.Cons (x, loop xs)
    in
    loop xs
  (* --- *)
  let to_seq ht = list_to_seq (to_list ht)
end
ENDIF

(* val of_seq : 'a Seq.t -> 'a cls  *)
let of_seq (xs : 'a Seq.t) () : 'a obj =
  let r = ref xs in
  fun () ->
    match (!r) () with
    | Seq.Nil        -> raise Out_of_range
    | Seq.Cons(x,xs) -> (r := xs; x)

(* val of_seqi : 'a Seq.t -> (index * 'a) cls  *)
let of_seqi (xs : 'a Seq.t) () : (index * 'a) obj =
  let j = ref 0 in
  let r = ref xs in
  fun () ->
    match (!r) () with
    | Seq.Nil -> raise Out_of_range
    | Seq.Cons(x,xs) ->
        let j0 = !j in
        let () = (r := xs) in
        let () = incr j in
        (j0, x)

(* val of_hashtbl : ('i,'a) Hashtbl.t -> ('i * 'a) cls  *)
let of_hashtbl (ht : ('i,'a) Hashtbl.t) =
  let s = Hashtbl.to_seq ht in
  of_seq s

(* --- *)

module Int : sig
    type start = int
     and stop  = int
     and step  = int
    (* --- *)
    (* (step≥0) => "forward"  loop (broken when value ≥ stop) *)
    (* (step<0) => "backward" loop (broken when value ≤ stop) *)
    val make  : ?verbose:unit -> (start * stop * step) -> int t
    val makei : ?verbose:unit -> (start * stop * step) -> (index * int) t
    (* --- *)
    val forward   : ?verbose:unit -> ?step:int -> start:int -> stop:int -> unit -> int t
    val forwardi  : ?verbose:unit -> ?step:int -> start:int -> stop:int -> unit -> (index * int) t
    (* --- *)
    val backward  : ?verbose:unit -> ?step:int -> start:int -> stop:int -> unit -> int t
    val backwardi : ?verbose:unit -> ?step:int -> start:int -> stop:int -> unit -> (index * int) t
end
= struct

  type start = int
   and stop  = int
   and step  = int

  let pr fmt = Printf.kfprintf flush stderr fmt

  let check_forward ~step ~start ~stop () : unit =
    if (stop <= start) then (pr "Range.Int: Warning: the forward range (%d,%d,%d) is empty\n" start stop step) else
    if (step = 0) then (pr "Range.Int: Warning: the forward range (%d,%d,%d) is constant\n" start stop step) else
    if (step < 0) then (pr "Range.Int: Warning: the forward range (%d,%d,%d) seems rather a backward infinite range\n" start stop step) else
    ()

  let check_backward ~step ~start ~stop () : unit =
    if (stop >= start) then (pr "Range.Int: Warning: the backward range (%d,%d,%d) is empty\n" start stop step) else
    if (step = 0) then (pr "Range.Int: Warning: the backward range (%d,%d,%d) is constant\n" start stop step) else
    if (step > 0) then (pr "Range.Int: Warning: the backward range (%d,%d,%d) seems rather a forward infinite range\n" start stop step) else
    ()

  let forwardi ?verbose ?(step=1) ~start ~stop () : (index * int) cls =
    let () = if (verbose = Some ()) then check_forward ~step ~start ~stop () in
    (* --- *)
    fun () ->
      let j = ref 0 in
      let x = ref start in
      fun () ->
        let x0 = !x in
        if (x0 >= stop) then raise Out_of_range else (* continue: *)
        let j0 = !j in
        let () = (x := x0 + step) in
        let () = incr j in
        (j0, x0)

  let backwardi ?verbose ?(step=(-1)) ~start ~stop () : (index * int) cls =
    let () = if (verbose = Some ()) then check_backward ~step ~start ~stop () in
    (* --- *)
    fun () ->
      let j = ref 0 in
      let x = ref start in
      fun () ->
        let x0 = !x in
        if (x0 <= stop) then raise Out_of_range else (* continue: *)
        let j0 = !j in
        let () = (x := x0 + step) in
        let () = incr j in
        (j0, x0)

  let forward ?verbose ?(step=1) ~start ~stop () : int cls =
    let () = if (verbose = Some ()) then check_forward ~step ~start ~stop () in
    (* --- *)
    fun () ->
      let x = ref start in
      fun () ->
        let x0 = !x in
        if (x0 >= stop) then raise Out_of_range else (* continue: *)
        let () = (x := x0 + step) in
        x0

  let backward ?verbose ?(step=(-1)) ~start ~stop () : int cls =
    let () = if (verbose = Some ()) then check_backward ~step ~start ~stop () in
    (* --- *)
    fun () ->
      let x = ref start in
      fun () ->
        let x0 = !x in
        if (x0 <= stop) then raise Out_of_range else (* continue: *)
        let () = (x := x0 + step) in
        x0

  let make ?verbose (start, stop, step) =
    if step >=0 then forward  ?verbose ~start ~stop ~step ()
                else backward ?verbose ~start ~stop ~step ()

  let makei ?verbose (start, stop, step) =
    if step >=0 then forwardi  ?verbose ~start ~stop ~step ()
                else backwardi ?verbose ~start ~stop ~step ()

  (* Examples:

      Range.to_list (Range.Int.forward ~start:0 ~stop:8 ());;
      (* - : int list = [0; 1; 2; 3; 4; 5; 6; 7] *)

      Range.to_list (Range.Int.forwardi ~start:1 ~stop:11 ~step:2 ());;
      (* - : (int * int) list = [(0, 1); (1, 3); (2, 5); (3, 7); (4, 9)] *)

      Range.to_list (Range.Int.make (0,8,1));;
      (* - : int list = [0; 1; 2; 3; 4; 5; 6; 7] *)

      Range.to_list (Range.Int.make (2,-3,-1));;
      (* - : int list = [2; 1; 0; -1; -2] *)

      Range.to_list (Range.Int.makei (2,-3,-1));;
      (* - : (int * int) list = [(0, 2); (1, 1); (2, 0); (3, -1); (4, -2)] *)
    *)

end (* Range.Int *)

(* Type shared by modules Fraction, Rational and Float: *)
type fraction = int * int

module Fraction = struct

  let to_float (a,b) =
    (float_of_int a) /. (float_of_int b)

  (* Ex: int_power 2 10 = 1024 *)
  let int_power =
    let rec pow a x n =
      if n = 0 then a else pow (a * (if n mod 2 = 0 then 1 else x)) (x * x) (n / 2) in
    pow 1

  (* val gcd : int -> int -> int *)
  let rec gcd a b =
    if b = 0 then a else gcd b (a mod b)

  let of_int x = (x,1)

  (* Fraction.of_float 3.141592 ;;
    - : int * int = (392699, 125000)

    Fraction.of_float ~decimals:5 3.141592 ;;
    - : int * int = (314159, 100000)
    *)
  let of_float =
    (* 64 bits => 18, 32 bits => 9 *)
    let max_decimals = int_of_float (log10 (float_of_int max_int)) in
    (* --- *)
    fun ?decimals x ->
      let decimals =
        match decimals with
        | None -> max_decimals
        | Some d ->
            if (d<0 || d>max_decimals)
              then
                invalid_arg
                  (Printf.sprintf "Range.Fraction.of_float: decimals %d not in the admissible range [0,%d] for this architecture" d max_decimals)
              else d
      in
      let k = int_power 10 (decimals) in
      let n = int_of_float (floor (x *. (float_of_int k) +. 0.5)) in
      let g = gcd n k in
      (n/g, k/g)

    (* val addition : int * int -> int * int -> int * int
       Quick implementation using gcd instead of prime numbers:
       ---
         a/b + c/d =
           (a⋅d + c⋅b) / (b⋅d) =                  (* x = gcd(b,d)  =>  b = b'⋅x  and  d = d'⋅x  *)
           (a⋅d'⋅x + c⋅b'⋅x) / (b'⋅x ⋅ d'⋅x) =    (* divide now all terms by x *)
           (a⋅d' + c⋅b') / (b'⋅ d'⋅x) =           (* d = d'⋅x *)
           (a⋅d' + c⋅b') / (b'⋅ d)
         Finally, the result may be itself simplified using the gcd once more.
       ---
      *)
    let addition (a,b) (c,d) =
      let x = gcd b d in
      let b' = b/x in
      let d' = d/x in
      let r1 = a*d' + c*b' in
      let r2 = b'*d in
      let y = gcd r1 r2 in
      (r1/y, r2/y)

    (* Lift the negative sign to numerator, if any: *)
    let lift_sign ((a,b) as x) =
      let () = assert (b<>0) in
      if b>0 then x else (-a,-b)

    let is_not_negative x =
      let (a,b) = lift_sign x in
      (a>=0)

    (* Ex: unify_to_same_denominator (3,4) (2,5);;
          - : fraction * fraction = ((15, 20), (8, 20)) *)
    let unify_to_same_denominator (a,b) (c,d) =
      let (a,b) = lift_sign (a,b) in
      let (c,d) = lift_sign (c,d) in
      let x = gcd b d in
      let b' = b/x in
      let d' = d/x in
      let den = b'*d in
      ((a*d', den), (c*b',den))

    let unify_3_to_same_denominator x y z =
      let x,y = unify_to_same_denominator x y in
      let x,z = unify_to_same_denominator x z in
      let y,z = unify_to_same_denominator y z in
      (x,y,z)

    (* Alias: *)
    let unify = unify_to_same_denominator

    let addition_with_same_denominator (a,b) (c,d) =
      (* let () = assert (b=d) in *)
      (a + c, b)

    let compare_with_same_denominator (a,b) (c,d) =
      (* let () = assert (b=d) in *)
      compare a c

    let compare (a,b) (c,d) =
      let x = gcd b d in
      let b' = b/x in
      let d' = d/x in
      compare (a*d') (c*b')

end (* Fraction *)

module Rational : sig
    type start = fraction  and stop = fraction  and  step = fraction
    (* --- *)
    val forward   : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> fraction t
    val forwardi  : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> (index * fraction) t
    (* --- *)
    val backward  : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> fraction t
    val backwardi : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> (index * fraction) t
    (* --- *)
    (* (step≥0) => "forward"  loop (broken when value ≥ stop) *)
    (* (step<0) => "backward" loop (broken when value ≤ stop) *)
    val make  : ?verbose:unit -> (start * stop * step) -> fraction t
    val makei : ?verbose:unit -> (start * stop * step) -> (index * fraction) t
end
= struct

  type start = fraction  and stop = fraction  and  step = fraction


  let pr fmt (a,a') (b,b') (c,c') = Printf.kfprintf flush stderr fmt a a' b b' c c'

  let check_forward ~step ~start ~stop () : unit =
    let f = Fraction.compare in
    if (f stop start) <= 0 then (pr "Range.Rational: Warning: the forward range (%d/%d, %d/%d, %d/%d) is empty\n" start stop step) else
    if (fst step) = 0      then (pr "Range.Rational: Warning: the forward range (%d/%d, %d/%d, %d/%d) is constant\n" start stop step) else
    if (f step (0,1)) < 0  then (pr "Range.Rational: Warning: the forward range (%d/%d, %d/%d, %d/%d) seems rather a backward infinite range\n" start stop step) else
    ()

  let check_backward ~step ~start ~stop () : unit =
    let f = Fraction.compare in
    if (f stop start) >= 0 then (pr "Range.Rational: Warning: the backward range (%d/%d, %d/%d, %d/%d) is empty\n" start stop step) else
    if (fst step) = 0      then (pr "Range.Rational: Warning: the backward range (%d/%d, %d/%d, %d/%d) is constant\n" start stop step) else
    if (f step (0,1)) > 0  then (pr "Range.Rational: Warning: the backward range (%d/%d, %d/%d, %d/%d) seems rather a forward infinite range\n" start stop step) else
    ()

  let forwardi ?verbose ?step ~start ~stop () : (index * fraction) cls =
    let step = match step with Some v -> v | None -> let (a,b) = start in (1, abs b) in
    let () = if (verbose = Some ()) then check_forward ~step ~start ~stop () in
    (* To optimize addition and compare:*)
    let (start, stop, step) = Fraction.unify_3_to_same_denominator start stop step in
    (* --- *)
    fun () ->
      let j = ref 0 in
      let x = ref start in
      fun () ->
        let x0 = !x in
        if ((Fraction.compare_with_same_denominator x0 stop) >= 0) then raise Out_of_range else (* continue: *)
        let j0 = !j in
        let () = (x := Fraction.addition_with_same_denominator x0 step) in
        let () = incr j in
        (j0, x0)

  let backwardi ?verbose ?step ~start ~stop () : (index * fraction) cls =
    let step = match step with Some v -> v | None -> let (a,b) = start in (-1, abs b) in
    let () = if (verbose = Some ()) then check_backward ~step ~start ~stop () in
    (* To optimize addition and compare:*)
    let (start, stop, step) = Fraction.unify_3_to_same_denominator start stop step in
    (* --- *)
    fun () ->
      let j = ref 0 in
      let x = ref start in
      fun () ->
        let x0 = !x in
        if ((Fraction.compare_with_same_denominator x0 stop) <= 0) then raise Out_of_range else (* continue: *)
        let j0 = !j in
        let () = (x := Fraction.addition_with_same_denominator x0 step) in
        let () = incr j in
        (j0, x0)

  let forward ?verbose ?step ~start ~stop () : fraction cls =
    let step = match step with Some v -> v | None -> let (a,b) = start in (1, abs b) in
    let () = if (verbose = Some ()) then check_forward ~step ~start ~stop () in
    (* To optimize addition and compare:*)
    let (start, stop, step) = Fraction.unify_3_to_same_denominator start stop step in
    (* --- *)
    fun () ->
      let x = ref start in
      fun () ->
        let x0 = !x in
        if ((Fraction.compare_with_same_denominator x0 stop) >= 0) then raise Out_of_range else (* continue: *)
        let () = (x := Fraction.addition_with_same_denominator x0 step) in
        x0

  let backward ?verbose ?step ~start ~stop () : fraction cls =
    let step = match step with Some v -> v | None -> let (a,b) = start in (-1, abs b) in
    let () = if (verbose = Some ()) then check_backward ~step ~start ~stop () in
    (* To optimize addition and compare:*)
    let (start, stop, step) = Fraction.unify_3_to_same_denominator start stop step in
    (* --- *)
    fun () ->
      let x = ref start in
      fun () ->
        let x0 = !x in
        if ((Fraction.compare_with_same_denominator x0 stop) <= 0) then raise Out_of_range else (* continue: *)
        let () = (x := Fraction.addition_with_same_denominator x0 step) in
        x0

  let make ?verbose (start, stop, step) =
    if (Fraction.is_not_negative step)
      then forward  ?verbose ~start ~stop ~step ()
      else backward ?verbose ~start ~stop ~step ()

  let makei ?verbose (start, stop, step) =
    if (Fraction.is_not_negative step)
      then forwardi  ?verbose ~start ~stop ~step ()
      else backwardi ?verbose ~start ~stop ~step ()

  (* Examples:

      Range.Rational.make ~verbose:() ((0,10), (5,7), (2,10)) |> Range.to_list ;;
      (* - : Range.Rational.stop list = [(0, 70); (14, 70); (28, 70); (42, 70)] *)

      Range.Rational.make ~verbose:() ((0,10), (-5,7), (-2,10)) |> Range.to_list ;;
      (*- : Range.Rational.stop list = [(0, 70); (-14, 70); (-28, 70); (-42, 70)]  *)

      Range.Rational.forward ~verbose:() ~start:(0,10) ~stop:(5,7) () |> Range.to_list ;;
      (* - : Range.Rational.stop list = [(0, 70); (7, 70); (14, 70); (21, 70); (28, 70); (35, 70); (42, 70); (49, 70)] *)

      Range.Rational.forward ~verbose:() ~start:(0,10) ~stop:(5,7) ~step:(1,10) () |> Range.to_list ;;
      (* - : Range.Rational.stop list = [(0, 70); (7, 70); (14, 70); (21, 70); (28, 70); (35, 70); (42, 70); (49, 70)] *)
    *)

end (* Range.Rational *)


(* ------------------------------------- *)
module Obj : sig
(* ------------------------------------- *)

  val empty : 'a obj
  val singleton : 'a -> 'a obj
  val of_lazy : 'a lazy_t -> 'a obj

  val map  : ('a -> 'b) -> 'a obj -> 'b obj
  val mapi : ('i -> 'a -> 'b) -> ('i * 'a) obj -> 'b obj

  val map2  : ('a -> 'b -> 'c) -> 'a obj -> 'b obj -> 'c obj
  val map2i : ('i * 'j -> 'a * 'b -> 'c) -> ('i * 'a) obj -> ('j * 'b) obj -> 'c obj

  val reindex : 'a obj -> (index * 'a) obj
  val unindex : ('i * 'a) obj -> 'a obj (* map snd *)

  val filter  : ('a -> bool) -> 'a obj -> 'a obj
  val filteri : ('i -> 'a -> bool) -> ('i * 'a) obj -> ('i * 'a) obj

  val skip  : ('a -> bool) -> 'a obj -> 'a obj
  val skipi : ('i -> 'a -> bool) -> ('i * 'a) obj -> ('i * 'a) obj

  val cut  : ('a -> bool) -> 'a obj -> 'a obj
  val cuti : ('i -> 'a -> bool) -> ('i * 'a) obj -> ('i * 'a) obj

  val break  : ('a -> bool) -> 'a obj -> 'a obj
  val breaki : ('i -> 'a -> bool) -> ('i * 'a) obj -> ('i * 'a) obj

  val uniq       : 'a obj -> 'a obj
  val uniqi      : ('i * 'a) obj -> ('i * 'a) obj (* ignoring indexes *)
  val uniq_image : ('a ->'b) -> 'a obj -> 'a obj

  val destruct: 'a obj -> ('a * 'a obj) option (* Not really interesting *)

  val append_cls : 'a obj -> 'a cls -> 'a obj
  val append_obj : 'a obj -> 'a obj -> 'a obj
  val cons       : 'a -> 'a obj -> 'a obj
  val lazy_cons  : 'a lazy_t -> 'a obj -> 'a obj

  val append_taking_the_last_state : 's -> ('s * 'a) obj -> ('s -> ('s * 'a) obj) -> ('s * 'a) obj

  val to_revlist  : 'a obj -> 'a list
  val to_list     : 'a obj -> 'a list (* List.rev ∘ to_revlist *)

  val to_revlisti : ('i * 'a) obj -> 'a list (* ignoring indexes *)
  val to_listi    : ('i * 'a) obj -> 'a list (* ignoring indexes, doing (List.rev ∘ to_revlisti) *)

  val to_array    : 'a obj -> 'a array
  val to_arrayi   : ('i * 'a) obj -> 'a array (* ignoring indexes *)
  val to_separated_arrays : ('i * 'a) obj -> 'i array * 'a array

  val to_array_with_length  : int -> 'a obj -> 'a array
  val to_array_with_lengthi : int -> ('i * 'a) obj -> 'a array (* ignoring indexes *)

  val to_string    : char obj -> string
  val to_stringi   : ('i * char) obj -> string (* ignoring indexes *)
  val to_string_with_length  : int -> char obj -> string
  val to_string_with_lengthi : int -> ('i * char) obj -> string (* ignoring indexes *)

  val memoize  : 'a obj -> 'a cls         (* of_list ∘ to_list *)
  val memoizei : ('i * 'a) obj -> 'a cls  (* of_list ∘ to_listi *)

  val reverse  : 'a obj -> 'a cls         (* of_list ∘ to_revlist  (=> memoized) *)
  val reversei : ('i * 'a) obj -> 'a cls  (* of_list ∘ to_revlisti (=> memoized) *)

  val combine  : 'a obj -> 'b obj -> ('a * 'b) obj
  val combinei : ('i * 'a) obj -> ('j * 'b) obj -> (('i * 'j) * ('a * 'b)) obj

  (* Combine as long as possible (alap) *)
  val combine_alap  : 'a obj -> 'b obj -> ('a option * 'b option) obj
  val combine_alapi : ('i * 'a) obj -> ('j * 'b) obj -> (('i option * 'j option) * ('a option * 'b option)) obj

  val fst   : ('a * 'b) obj -> 'a obj
  val snd   : ('a * 'b) obj -> 'b obj
  val fsti  : (('i * 'j) * ('a * 'b)) obj -> ('i * 'a) obj
  val sndi  : (('i * 'j) * ('a * 'b)) obj -> ('j * 'b) obj

  val twist  : ('a * 'b) obj -> ('b * 'a) obj
  val twisti : (('i * 'j) * ('a * 'b)) obj -> (('j * 'i) * ('b * 'a)) obj

  (* Strange, quite unusable, tools (the results share the same original object): *)
  (*  val split  : ('a * 'b) obj -> ('a obj) * ('b obj)
      val spliti : (('i * 'j) * ('a * 'b)) obj -> ('i * 'a) obj * ('j * 'b) obj *)

  (* "fold" variants: *)

  val fold  : range:'a obj -> init:'s -> body:('s -> 'a -> 's) -> 's
  val foldi : range:('i * 'a) obj -> init:'s -> body:('s -> 'i -> 'a -> 's) -> 's

  module Fold : sig
    val gen_while_do  : break:('s -> 'a -> 's option) -> range:'a obj -> init:'s -> body:('s -> 'a -> 's) -> 's
    val gen_do_while  : break:('s -> 'a -> 's option) -> range:'a obj -> init:'s -> body:('s -> 'a -> 's) -> 's

    val while_do      : ('s -> 'a -> bool) -> range:'a obj -> init:'s -> body:('s -> 'a -> 's) -> 's
    val do_while      : ('s -> 'a -> bool) -> range:'a obj -> init:'s -> body:('s -> 'a -> 's) -> 's

    val gen_while_doi : break:('s -> 'i -> 'a -> 's option) -> range:('i * 'a) obj -> init:'s -> body:('s -> 'i -> 'a -> 's) -> 's
    val gen_do_whilei : break:('s -> 'i -> 'a -> 's option) -> range:('i * 'a) obj -> init:'s -> body:('s -> 'i -> 'a -> 's) -> 's

    val while_doi     : ('s -> 'i -> 'a -> bool) -> range:('i * 'a) obj -> init:'s -> body:('s -> 'i -> 'a -> 's) -> 's
    val do_whilei     : ('s -> 'i -> 'a -> bool) -> range:('i * 'a) obj -> init:'s -> body:('s -> 'i -> 'a -> 's) -> 's
  end

end (* Obj signature *)

= struct

  (* The empty object: *)
  let empty () = raise Out_of_range

  (* val singleton : 'a -> 'a obj *)
  let singleton x =
    let already_shot = ref false in
    fun () ->
      if !already_shot then raise Out_of_range else (already_shot:=true; x)

  (* val of_lazy : 'a lazy_t -> a obj *)
  let of_lazy (x : 'a lazy_t) : 'a obj =
    let already_shot = ref false in
    fun () ->
      if !already_shot then raise Out_of_range else (already_shot:=true; Lazy.force x)

  let map (f : 'a -> 'b) (range : 'a obj) : 'b obj =
    fun () -> f (range ())

  let mapi (f : 'i -> 'a -> 'b) (range : ('i * 'a) obj) : 'b obj =
    fun () ->
      let (i, x) = range () in
      f i x

  (* val map2 : ('a -> 'b -> 'c) -> 'a obj -> 'b obj -> 'c obj *)
  let map2 f r1 r2 =
    fun () -> f (r1 ()) (r2 ())

  (* val map2i : ('i * 'j -> 'a * 'b -> 'c) -> ('i * 'a) obj -> ('j * 'b) obj -> 'c obj *)
  let map2i f r1 r2 =
    fun () ->
      let (i,a) = r1 () in
      let (j,b) = r2 () in
      f (i,j) (a,b)

  let filter (p : 'a -> bool) (range : 'a obj) : 'a obj =
    let rec loop () =
      let y = range () in
      if p y then y else (* continue: *)
      loop ()
    in
    loop

  let filteri (p : 'i -> 'a -> bool) (range : ('i * 'a) obj) : ('i * 'a) obj =
    let rec loop () =
      let (i,y) as result = range () in
      if p i y then result else (* continue: *)
      loop ()
    in
    loop

  (* Negation of filter: *)
  let skip (p : 'a -> bool) (range : 'a obj) : 'a obj =
    let rec loop () =
      let y = range () in
      if p y then loop () else (* continue: *)
      y
    in
    loop

  (* Negation of filteri: *)
  let skipi (p : 'i -> 'a -> bool) (range : ('i * 'a) obj) : ('i * 'a) obj =
    let rec loop () =
      let (i,y) as result = range () in
      if p i y then loop () else (* continue: *)
      result
    in
    loop

  (* As skip but cuts the rest of sequence: *)
  let cut (p : 'a -> bool) (range : 'a obj) : 'a obj =
    let loop () =
      let y = range () in
      if p y then raise Out_of_range else (* continue: *)
      y
    in
    loop

  (* As skip but cuts the rest of sequence: *)
  let cuti (p : 'i -> 'a -> bool) (range : ('i * 'a) obj) : ('i * 'a) obj =
    let loop () =
      let (i,y) as result = range () in
      if p i y then raise Out_of_range else (* continue: *)
      result
    in
    loop

  (* As cut but the last element is taken: *)
  let break (p : 'a -> bool) (range : 'a obj) : 'a obj =
    let broken = ref false in
    let loop () =
      if !broken then raise Out_of_range else (* continue: *)
      let y = range () in
      if p y then (broken:=true; y) else y
    in
    loop

  (* As cuti but the last element is taken: *)
  let breaki (p : 'i -> 'a -> bool) (range : ('i * 'a) obj) : ('i * 'a) obj =
    let broken = ref false in
    let loop () =
      if !broken then raise Out_of_range else (* continue: *)
      let (i,y) as result = range () in
      if p i y then (broken:=true; result) else result
    in
    loop

  (* val reindex : 'a obj -> (index * 'a) obj *)
  let reindex (range : 'a obj) : (index * 'a) obj =
    let j = ref 0 in
    fun () ->
      let x = range () in
      let j0 = !j in
      let () = incr j in
      (j0, x)

  (* val unindex : ('i * 'a) obj -> 'a obj (* map snd *) *)
  let unindex (range : ('i * 'a) obj) : 'a obj =
    fun () ->
      let (_, x) = range () in
      x

  let uniq (range : 'a obj) : 'a obj =
    let set = Hashset.make () in
    let rec loop () =
      let y = range () in
      if Hashset.mem set y then loop () else (* continue: *)
      let () = Hashset.add set y in
      y
    in
    loop

  (* Ignoring indexes: *)
  let uniqi (range : ('i *'a) obj) : ('i * 'a) obj =
    let set = Hashset.make () in
    let rec loop () =
      let (i, y) = range () in
      if Hashset.mem set y then loop () else (* continue: *)
      let () = Hashset.add set y in
      (i,y)
    in
    loop

  (* Ignoring with mapping: *)
  let uniq_image (f:'a ->'b) (range : 'a obj) : 'a obj =
    let set = Hashset.make () in
    let rec loop () =
      let x = range () in
      let y = f x in
      if Hashset.mem set y then loop () else (* continue: *)
      let () = Hashset.add set y in
      x
    in
    loop

  (* val destruct: 'a obj -> ('a * 'a obj) option *)
  let destruct r =
    try
      let x = r () in
      Some (x, r)
    with Out_of_range -> None

  (* val append : 'a obj -> 'a cls -> 'a obj *)
  let append_cls (r1 : 'a obj) (r2 : 'a cls) : 'a obj =
    let r = ref r1 in
    let already_switched = ref false in
    fun () ->
      try (!r) ()
      with Out_of_range when (!already_switched = false) ->
         (r:=r2 (); already_switched:=true; (!r) ())

  let append_obj (r1 : 'a obj) (r2 : 'a obj) : 'a obj =
    let r = ref r1 in
    let already_switched = ref false in
    fun () ->
      try (!r) ()
      with Out_of_range when (!already_switched = false) ->
         (r:=r2; already_switched:=true; (!r) ())

  (* val cons : 'a -> 'a obj -> 'a obj *)
  let cons x = append_obj (singleton x)

  (* val lazy_cons : 'a lazy -> 'a t -> 'a t *)
  let lazy_cons x = append_obj (of_lazy x)

  (* val append_taking_the_last_state : 's -> ('s * 'a) obj -> ('s -> ('s * 'a) obj) -> ('s * 'a) obj
     ---
     # let r1 = Range.of_listi ['A'; 'B'; 'C'; ] () ;;
     # let r2 s = Range.Obj.map (fun (i,x) -> (i+s+1,x)) (Range.of_listi ['A'; 'B'; 'C'; ] ()) ;;
     # let r12  = Range.Obj.append_taking_the_last_state 0 r1 r2 ;;
     val r12 : (int * char) Range.obj
     # r12 () ;;
     - : int * char = (0, 'A')
     # r12 () ;;
     - : int * char = (1, 'B')
     # r12 () ;;
     - : int * char = (2, 'C')
     # r12 () ;;
     - : int * char = (3, 'A')
     # r12 () ;;
     - : int * char = (4, 'B')
     # r12 () ;;
     - : int * char = (5, 'C')
     # r12 () ;;
     Exception: Range.Out_of_range.
  *)
  let append_taking_the_last_state s0 xss f =
    let range = ref xss in
    let last  = ref s0 in
    let already_switched = ref false in
    fun () ->
      try
        let (s,x) as result = (!range) () in
        let () = (last := s) in
        result
      with Out_of_range when (!already_switched = false) -> begin
          let yss = f (!last) in
          (range:=yss; already_switched:=true; yss ())
        end

  (* val to_revlist : 'a obj -> 'a list *)
  let to_revlist (range : 'a obj) : 'a list =
    let rec loop acc =
      try loop ((range ())::acc)
      with Out_of_range -> acc
    in
    loop []

  (* val to_revlisti : ('i,'a) obj -> 'a list *)
  let to_revlisti (range : ('i * 'a) obj) : 'a list =
    let rec loop acc =
      try
        let (_,x) = range () in
        loop (x::acc)
      with Out_of_range -> acc in
      loop []

  (* val to_list : 'a obj -> 'a list *)
  let to_list (range : 'a obj) = List.rev (to_revlist range)

  (* val to_listi : ('i,'a) obj -> 'a list *)
  let to_listi (range) = List.rev (to_revlisti range)

  (* --- arrays --- *)

  let to_array (range : 'a obj) : 'a array =
    (* Make the reversed list of items counting then number of elements: *)
    let rec loop i acc =
      try loop (i+1) ((range ())::acc)
      with Out_of_range -> (i, acc)
    in
    let (n, jxs) = loop 0 [] in
    (* --- *)
    match jxs with
    | []    -> [||]
    | x::xs ->
        let a = Array.make n x in
        (* --- *)
        let rec loop i = function
        | []    -> a
        | x::xs -> (a.(i) <- x;  loop (i-1) xs)
        in
        loop (n-2) xs

  let to_arrayi (range : ('i *'a) obj) : 'a array =
    (* Make the reversed list of items counting then number of elements and ignoring indexes (snd): *)
    let rec loop i acc =
      try
        let (_, x) = range () in
        loop (i+1) (x::acc)
      with Out_of_range -> (i, acc)
    in
    let (n, xs) = loop 0 [] in
    (* --- *)
    match xs with
    | []    -> [||]
    | x::xs ->
        let a = Array.make n x in
        (* --- *)
        let rec loop i = function
        | []    -> a
        | x::xs -> (a.(i) <- x;  loop (i-1) xs)
        in
        loop (n-2) xs

  (* As the previous tool, but efficiently splits the array of couples: *)
  let to_separated_arrays (range : ('i * 'a) obj) : ('i array) * ('a array) =
    (* Make the reversed list of items counting then number of elements: *)
    let rec loop i acc =
      try loop (i+1) ((range ())::acc)
      with Out_of_range -> (i, acc)
    in
    let (n, jxs) = loop 0 [] in
    (* --- *)
    match jxs with
    | []    -> [||], [||]
    | (j,x)::jxs ->
        let a = Array.make n j in
        let b = Array.make n x in
        (* --- *)
        let rec loop i = function
        | []         -> (a,b)
        | (j,x)::jxs -> (a.(i) <- j; b.(i) <- x; loop (i-1) jxs)
        in
        loop (n-2) jxs

  let to_array_with_lengthi (n:int) (range : ('i * 'a) obj) : 'a array =
    try
      Array.init n (fun i -> let (_,x) = range () in x)
    with Out_of_range ->
      invalid_arg "Range.to_arrayi: the range has a shorter length than expected"

  let to_array_with_length (n:int) (range : 'a obj) : 'a array =
    try
      Array.init n (fun i -> range ())
    with Out_of_range ->
      invalid_arg "Range.to_array: the range has a shorter length than expected"

  (* --- strings --- *)

  let to_string (range : char obj) : string =
    (* Make the reversed list of items counting then number of elements: *)
    let rec loop i acc =
      try loop (i+1) ((range ())::acc)
      with Out_of_range -> (i, acc)
    in
    let (n, jxs) = loop 0 [] in
    (* --- *)
    let result =
      match jxs with
      | []    -> (Bytes.of_string "")
      | x::xs ->
          let a = Bytes.make n x in
          (* --- *)
          let rec loop i = function
          | []    -> a
          | x::xs -> (Bytes.set a i x;  loop (i-1) xs)
          in
          loop (n-2) xs
    in
    Bytes.to_string result

  let to_stringi (range : ('i * char) obj) : string =
    (* Make the reversed list of items counting then number of elements and ignoring indexes (snd): *)
    let rec loop i acc =
      try
        let (_, x) = range () in
        loop (i+1) (x::acc)
      with Out_of_range -> (i, acc)
    in
    let (n, xs) = loop 0 [] in
    (* --- *)
    let result =
      match xs with
      | []    -> (Bytes.of_string "")
      | x::xs ->
          let a = Bytes.make n x in
          (* --- *)
          let rec loop i = function
          | []    -> a
          | x::xs -> (Bytes.set a i x;  loop (i-1) xs)
          in
          loop (n-2) xs
    in
    Bytes.to_string result

  let to_string_with_lengthi (n:int) (range : ('i * char) obj) : string =
    try
      String.init n (fun i -> let (_,x) = range () in x)
    with Out_of_range ->
      invalid_arg "Range.to_stringi: the range has a shorter length than expected"

  let to_string_with_length (n:int) (range : char obj) : string =
    try
      String.init n (fun i -> range ())
    with Out_of_range ->
      invalid_arg "Range.to_string: the range has a shorter length than expected"

  (* ---- *)

  (* val memoize : 'a obj -> 'a cls *)
  let memoize (range: 'a obj) : 'a cls =
    of_list (to_list range)

  (* val memoize_reindexing : ('i,'a) obj -> (index, 'a) cls *)
  let memoizei (range: ('i * 'a) obj) : 'a cls =
    of_list (to_listi range)

  (* val reverse : 'a obj -> 'a cls *)
  let reverse (range) =
    of_list ((to_revlist range))

  (* val reversei : ('i * 'a) obj -> 'a cls *)
  let reversei (range) =
    of_list (to_revlisti range)

  (* Combine as long as possible (alap). The result has the length of the longest sequence: *)
  let combine_alap (r1 : 'a obj) (r2 : 'b obj) : ('a option * 'b option) obj =
    fun () ->
      let x1 = try Some (r1 ()) with Out_of_range -> None in
      let x2 = try Some (r2 ()) with Out_of_range -> None in
      if (x1 = None) && (x2 = None) then raise Out_of_range else
      (x1, x2)

  let combine_alapi (r1 : ('i * 'a) obj) (r2 : ('j * 'b) obj) : (('i option * 'j option) * ('a option * 'b option)) obj =
    fun () ->
      let ix = try Some (r1 ()) with Out_of_range -> None in
      let jy = try Some (r2 ()) with Out_of_range -> None in
      match ix, jy with
      | None       , None       -> raise Out_of_range
      | Some (i,x) , Some (j,y) -> ((Some i, Some j), (Some x, Some y))
      | Some (i,x) , None       -> ((Some i, None  ), (Some x, None  ))
      | None       , Some (j,y) -> ((None  , Some j), (None  , Some y))

  let combine (r1 : 'a obj) (r2 : 'b obj) : ('a * 'b) obj =
    fun () -> (r1 (), r2 ())

  let combinei (r1 : ('i * 'a) obj) (r2 : ('j * 'b) obj) : (('i * 'j) * ('a * 'b)) obj =
    fun () ->
      let (i, x) = r1 () in
      let (j, y) = r2 () in
      ((i,j) , (x,y))

  let fst (r : ('a * 'b) obj) : 'a obj =
    fun () -> let (a, _) = r () in a

  let snd (r : ('a * 'b) obj) : 'b obj =
    fun () -> let (_, b) = r () in b

  let fsti (r : (('i * 'j) * ('a * 'b)) obj) : ('i * 'a) obj =
    fun () -> let (i, _), (a, _) = r () in (i,a)

  let sndi (r : (('i * 'j) * ('a * 'b)) obj) : ('j * 'b) obj =
    fun () -> let (_, j), (_, b) = r () in (j,b)

  let twist (r : ('a * 'b) obj) : ('b * 'a) obj =
    fun () -> let (a,b) = r () in (b,a)

  let twisti (r : (('i * 'j) * ('a * 'b)) obj) : (('j * 'i) * ('b * 'a)) obj =
    fun () -> let (i,j), (a,b) = r () in ((j,i),(b,a))

  (* The couple share the same origin => quite strange (use Cls.split instead): *)
  (*   let split (r : ('a * 'b) obj) : ('a obj) * ('b obj) = ((fst r), (snd r)) *)

  (* The couple share the same origin => quite strange (use Cls.spliti instead): *)
  (*   let spliti (r : (('i * 'j) * ('a * 'b)) obj) : ('i * 'a) obj * ('j * 'b) obj = ((fsti r), (sndi r)) *)

  (* -----------------------------------------------------
          "fold" variants working on range objects

       Note: even if some functions are simple instances
             of a general scheme, they are reimplemented
             for efficiency
     ------------------------------------------------------ *)

  let fold ~(range : 'a obj) ~init ~(body:'s -> 'a -> 's) : 's =
    (* --- *)
    let sr = ref init in           (* state reference (s) *)
    try
      let () =
        while true do
          let x = range () in
          (sr := body (!sr) x);    (* execute the body *)
        done
      in
      !sr
    (* --- *)
    with
      Out_of_range -> !sr

  let foldi ~(range : ('i * 'a) obj) ~init ~(body:'s -> 'i -> 'a -> 's) : 's =
    (* --- *)
    let sr = ref init in             (* state reference (s) *)
    try
      let () =
        while true do
          let (i,x) = range () in
          (sr := body (!sr) i x);    (* execute the body *)
        done
      in
      !sr
    (* --- *)
    with
      Out_of_range -> !sr

  module Fold = struct

    let gen_while_do ~(break : 's -> 'a -> 's option) ~(range : 'a obj) ~init ~(body:'s -> 'a -> 's) : 's =
      (* --- *)
      let sr = ref init in           (* state reference (s) *)
      try
        let () =
          let xr = ref (range ()) in
          while (match break !sr !xr with None -> true | Some s' -> (sr := s'); false) do
            sr := body (!sr) (!xr);  (* execute the body *)
            xr := range ();          (* prepare the next iteration, if any *)
          done
        in
        !sr
      (* --- *)
      with
        Out_of_range -> !sr

    let while_do (cond : 's -> 'a -> bool) ~(range : 'a obj) ~init ~(body:'s -> 'a -> 's) : 's =
      (* --- *)
      let sr = ref init in           (* state reference (s) *)
      try
        let () =
          let xr = ref (range ()) in
          while (cond !sr !xr) do
            sr := body (!sr) (!xr);  (* execute the body *)
            xr := range ();          (* prepare the next iteration, if any *)
          done
        in
        !sr
      (* --- *)
      with
        Out_of_range -> !sr

    let gen_do_while ~(break : 's -> 'a -> 's option) ~(range : 'a obj) ~init ~(body:'s -> 'a -> 's) : 's =
      (* --- *)
      let sr = ref init in           (* state reference (s) *)
      try
        let () =
          let xr = ref (range ()) in
          (* --- First (unguarded) iteration: *)
          sr := body (!sr) (!xr);    (* execute the body *)
          xr := range ();            (* prepare the next iteration, if any *)
          (* --- continue as a while_do *)
          while (match break !sr !xr with None -> true | Some s' -> (sr := s'); false) do
            sr := body (!sr) (!xr);  (* execute the body *)
            xr := range ();          (* prepare the next iteration, if any *)
          done
        in
        !sr
      (* --- *)
      with
        Out_of_range -> !sr

    let do_while (cond : 's -> 'a -> bool) ~(range : 'a obj) ~init ~(body:'s -> 'a -> 's) : 's =
      (* --- *)
      let sr = ref init in           (* state reference (s) *)
      try
        let () =
          let xr = ref (range ()) in
          (* --- First (unguarded) iteration: *)
          sr := body (!sr) (!xr);    (* execute the body *)
          xr := range ();            (* prepare the next iteration, if any *)
          (* --- continue as a while_do *)
          while (cond !sr !xr) do
            sr := body (!sr) (!xr);  (* execute the body *)
            xr := range ();          (* prepare the next iteration, if any *)
          done
        in
        !sr
      (* --- *)
      with
        Out_of_range -> !sr

    let gen_while_doi ~(break : 's -> 'i -> 'a -> 's option) ~(range : ('i * 'a) obj) ~init ~(body:'s -> 'i -> 'a -> 's) : 's =
      (* --- *)
      let sr = ref init in           (* state reference (s) *)
      try
        let () =
          let ixr = ref (range ()) in
          while (let (i,x) = !ixr in match break !sr i x with None -> true | Some s' -> (sr := s'); false) do
            let (i,x) = !ixr in
            sr := body (!sr) i x;   (* execute the body *)
            ixr := range ();         (* prepare the next iteration, if any *)
          done
        in
        !sr
      (* --- *)
      with
        Out_of_range -> !sr

    let while_doi (cond : 's -> 'i -> 'a -> bool) ~(range : ('i * 'a) obj) ~init ~(body:'s -> 'i -> 'a -> 's) : 's =
      (* --- *)
      let sr = ref init in           (* state reference (s) *)
      try
        let () =
          let ixr = ref (range ()) in
          while (let (i,x) = !ixr in cond !sr i x) do
            let (i,x) = !ixr in
            sr := body (!sr) i x;   (* execute the body *)
            ixr := range ();         (* prepare the next iteration, if any *)
          done
        in
        !sr
      (* --- *)
      with
        Out_of_range -> !sr

    let gen_do_whilei ~(break : 's -> 'i -> 'a -> 's option) ~(range : ('i * 'a) obj) ~init ~(body:'s -> 'i -> 'a -> 's) : 's =
      (* --- *)
      let sr = ref init in           (* state reference (s) *)
      try
        let () =
          let ixr = ref (range ()) in
          (* --- First (unguarded) iteration: *)
          let (i,x) = !ixr in
          sr  := body (!sr) i x;  (* execute the body *)
          ixr := range ();        (* prepare the next iteration, if any *)
          (* --- continue as a while_do *)
          while (let (i,x) = !ixr in match break !sr i x with None -> true | Some s' -> (sr := s'); false) do
            let (i,x) = !ixr in
            sr  := body (!sr) i x;  (* execute the body *)
            ixr := range ();        (* prepare the next iteration, if any *)
          done
        in
        !sr
      (* --- *)
      with
        Out_of_range -> !sr

    let do_whilei (cond : 's -> 'i -> 'a -> bool) ~(range : ('i * 'a) obj) ~init ~(body:'s -> 'i -> 'a -> 's) : 's =
      (* --- *)
      let sr = ref init in           (* state reference (s) *)
      try
        let () =
          let ixr = ref (range ()) in
          (* --- First (unguarded) iteration: *)
          let (i,x) = !ixr in
          sr  := body (!sr) i x;  (* execute the body *)
          ixr := range ();        (* prepare the next iteration, if any *)
          (* --- continue as a while_do *)
          while (let (i,x) = !ixr in cond !sr i x) do
            let (i,x) = !ixr in
            sr  := body (!sr) i x;  (* execute the body *)
            ixr := range ();        (* prepare the next iteration, if any *)
          done
        in
        !sr
      (* --- *)
      with
        Out_of_range -> !sr

  end (* Obj.Fold *)

end (* Obj *)

(* Tools defined using the corresponding function in the module Obj *)
(* ------------------------------------- *)
module Cls = struct
(* ------------------------------------- *)

  let cons x cls () = Obj.append_cls (Obj.singleton x) cls
  (* let lazy_cons x cls () = Obj.append_cls (Obj.of_lazy x) cls *)
  let lazy_cons x cls () = Obj.lazy_cons x (cls ())

  let singleton x () = Obj.singleton x
  let of_lazy   x () = Obj.of_lazy x

  let filter  p cls () = Obj.filter  p (cls ())
  let filteri p cls () = Obj.filteri p (cls ())

  let skip  p cls () = Obj.skip  p (cls ())
  let skipi p cls () = Obj.skipi p (cls ())

  let cut  p cls () = Obj.cut  p (cls ())
  let cuti p cls () = Obj.cuti p (cls ())

  let break  p cls () = Obj.break  p (cls ())
  let breaki p cls () = Obj.breaki p (cls ())

  let map   f cls () = Obj.map   f (cls ())
  let mapi  f cls () = Obj.mapi  f (cls ())

  let map2  f cls1 cls2 () = Obj.map2  f (cls1 ()) (cls2 ())
  let map2i f cls1 cls2 () = Obj.map2i f (cls1 ()) (cls2 ())

  let append c1 c2 () = Obj.append_cls (c1 ()) (c2)

  let to_list     cls = Obj.to_list (cls ())
  let to_listi    cls = Obj.to_listi (cls ())
  let to_revlist  cls = Obj.to_revlist (cls ())
  let to_revlisti cls = Obj.to_revlisti (cls ())

  let to_array  cls = Obj.to_array (cls ())
  let to_arrayi cls = Obj.to_arrayi (cls ())

  let to_separated_arrays     cls = Obj.to_separated_arrays (cls ())
  let to_array_with_length  n cls = Obj.to_array_with_length n (cls ())
  let to_array_with_lengthi n cls = Obj.to_array_with_lengthi n (cls ())

  let to_string  cls = Obj.to_string (cls ())
  let to_stringi cls = Obj.to_stringi (cls ())
  let to_string_with_length  n cls = Obj.to_string_with_length n (cls ())
  let to_string_with_lengthi n cls = Obj.to_string_with_lengthi n (cls ())

  let memoize  cls = Obj.memoize  (cls ())
  let memoizei cls = Obj.memoizei (cls ())
  let reverse  cls = Obj.reverse  (cls ())
  let reversei cls = Obj.reversei (cls ())

  let reindex cls () = Obj.reindex (cls ())
  let unindex cls () = Obj.unindex (cls ())

  let uniq  cls () = Obj.uniq  (cls ())
  let uniqi cls () = Obj.uniqi (cls ())
  let uniq_image f cls () = Obj.uniq_image f (cls ())

  let fold ~range  = Obj.fold ~range:(range ())
  let foldi ~range = Obj.foldi ~range:(range ())

  module Fold = struct
    let wholly  = fold
    let whollyi = foldi

    let gen_while_do ~break ~range  = Obj.Fold.gen_while_do ~break ~range:(range ())
    let gen_do_while ~break ~range  = Obj.Fold.gen_do_while ~break ~range:(range ())
    let while_do cond ~range        = Obj.Fold.while_do cond ~range:(range ())
    let do_while cond ~range        = Obj.Fold.do_while cond ~range:(range ())

    let gen_while_doi ~break ~range = Obj.Fold.gen_while_doi ~break ~range:(range ())
    let gen_do_whilei ~break ~range = Obj.Fold.gen_do_whilei ~break ~range:(range ())
    let while_doi cond ~range       = Obj.Fold.while_doi cond ~range:(range ())
    let do_whilei cond ~range       = Obj.Fold.do_whilei cond ~range:(range ())
  end

  let length range = fold ~range ~init:0 ~body:(fun s _ -> s+1)

  (* val last  : init:'a -> 'a t -> 'a *)
  let last  ~init range = fold  ~range ~init ~body:(fun _ x -> x)
  let lasti ~init range = foldi ~range ~init ~body:(fun _ i x -> (i,x))

  (* val last_apply : init:'a -> ('a -> 'b) -> 'a t -> 'b *)
  let last_apply ~init f range =
    let y = fold ~range ~init ~body:(fun _ x -> x) in
    f y

  let last_applyi ~init f range =
    let (i,y) = foldi ~range ~init ~body:(fun _ i x -> (i,x)) in
    f i y

  let combine  c1 c2 () = Obj.combine  (c1 ()) (c2 ())
  let combinei c1 c2 () = Obj.combinei (c1 ()) (c2 ())

  let combine_alap  c1 c2 () = Obj.combine_alap  (c1 ()) (c2 ())
  let combine_alapi c1 c2 () = Obj.combine_alapi (c1 ()) (c2 ())

  let fst cls () = Obj.fst (cls ())
  let snd cls () = Obj.snd (cls ())

  let fsti cls () = Obj.fsti (cls ())
  let sndi cls () = Obj.sndi (cls ())

  (* The two results are built on different objects (no sharing between them): *)
  let split  cls = ((fst  cls), (snd  cls))
  let spliti cls = ((fsti cls), (sndi cls))

  let twist  cls () = Obj.twist  (cls ())
  let twisti cls () = Obj.twisti (cls ())

end (* Cls *)

(* ---------------------------------------------------------
                         bind
               (based as usual on append)
   --------------------------------------------------------- *)

(* val return : 'a -> 'a cls *)
let return = Cls.singleton

(* val bind  : 'a cls -> ('a -> 'b cls) -> 'b cls *)
let bind cls f =
  let rec loop obj () : 'b obj =
    let x = obj () in
    let bs = f x in
    let r' = Obj.append_cls (bs ()) (fun () -> loop obj ()) in
    r'
  (* --- *)
  in
  fun () -> loop (cls ()) ()

(* val bindi : ('i * 'a) cls -> ('i -> 'a -> 'b cls) -> 'b cls *)
let bindi cls f =
  let rec loop obj () : 'b obj =
    let i, x = obj () in
    let bs = f i x in
    let r' = Obj.append_cls (bs ()) (fun () -> loop obj ()) in
    r'
  (* --- *)
  in
  fun () -> loop (cls ()) ()

(* val join : 'a cls cls -> 'a cls *)
let join clss =
  let rec loop obj () : 'b obj =
    let cls = obj () in
    let r' = Obj.append_cls (cls ()) (fun () -> loop obj ()) in
    r'
  (* --- *)
  in
  fun () -> loop (clss ()) ()

(* val product : 'a cls -> 'b cls -> ('a * 'b) cls *)
let product xs ys =
  bind xs (fun a ->
    bind ys (fun b ->
      return (a,b)
      ))

(* val dep_product : 'a cls -> ('a -> 'b cls) -> ('a * 'b) cls *)
let dep_product xs ys =
  bind xs (fun a ->
    bind (ys a) (fun b ->
      return (a,b)
      ))

(* val producti : ('i * 'a) cls -> ('j * 'b) cls -> (('i * 'j) * ('a * 'b)) cls *)
let producti xs ys =
  bind xs (fun (i,a) ->
    bind ys (fun (j,b) ->
      return ((i,j),(a,b))
      ))

(* val dep_producti : ('i * 'a) cls -> ('i -> 'a -> ('j * 'b) cls) -> (('i * 'j) * ('a * 'b)) cls *)
let dep_producti xs ys =
  bind xs (fun (i,a) ->
    bind (ys i a) (fun (j,b) ->
      return ((i,j),(a,b))
      ))

(* val power  : 'a cls -> int -> ('a list) cls *)
let rec power xs k =
  if k=0 then empty else
  if k=1 then Cls.map (fun x -> [x]) xs else
  bind xs (fun x ->
    Cls.map (fun l -> x::l) (power xs (k-1))
    )

(* val poweri : ('i * 'a) cls -> int -> (('i list) * ('a list)) cls *)
let rec poweri ixs k =
  if k=0 then empty else
  if k=1 then Cls.map (fun (i,x) -> [i],[x]) ixs else
  bindi ixs (fun i x ->
    Cls.map (fun (is, xs) -> (i::is, x::xs)) (poweri ixs (k-1))
    )

(* val of_array2D : 'a array array -> 'a cls *)
let of_array2D x2s =
  bind (of_array x2s) (of_array)

(* val of_array2Di : 'a array array -> ((index * index) * 'a) cls *)
let of_array2Di x2s =
  bindi (of_arrayi x2s) (fun i xs ->
    Cls.mapi (fun j x -> (i,j),x) (of_arrayi xs)
    )

(* val of_array3D  : 'a array array array -> 'a cls *)
let of_array3D x3s =
  bind (of_array x3s) (of_array2D)

(* val of_array3Di : 'a array array array -> ((index * index * index) * 'a) cls *)
let of_array3Di x3s =
  bindi (of_arrayi x3s) (fun i x2s ->
    Cls.mapi (fun (j1,j2) x -> (i,j1,j2),x) (of_array2Di x2s)
    )

(* val of_array4D  : 'a array array array array -> 'a cls *)
let of_array4D x4s =
  bind (of_array x4s) (of_array3D)

(* val of_array4Di : 'a array array array array -> ((index * index * index * index) * 'a) cls *)
let of_array4Di x4s =
  bindi (of_arrayi x4s) (fun i x3s ->
    Cls.mapi (fun (j1,j2,j3) x -> (i,j1,j2,j3),x) (of_array3Di x3s)
    )

(* val of_array5D  : 'a array array array array array -> 'a cls *)
let of_array5D x5s =
  bind (of_array x5s) (of_array4D)

(* val of_array5Di : 'a array array array array array -> ((index * index * index * index * index) * 'a) cls *)
let of_array5Di x5s =
  bindi (of_arrayi x5s) (fun i x4s ->
    Cls.mapi (fun (j1,j2,j3,j4) x -> (i,j1,j2,j3,j4),x) (of_array4Di x4s)
    )

(* Examples:
let xss = Array.init 5 (fun i -> Array.init (i+1) (fun j -> (i+1)*(j+1))) ;;
val xss : int array array =
[|[|1|]; [|2; 4|]; [|3; 6; 9|]; [|4; 8; 12; 16|]; [|5; 10; 15; 20; 25|]|]

Range.to_list (Range.of_array2D xss) ;;
- : int list = [1; 2; 4; 3; 6; 9; 4; 8; 12; 16; 5; 10; 15; 20; 25]

Range.to_list (Range.of_array2Di xss) ;;
- : ((index * index) * int) list =
[((0, 0), 1);
 ((1, 0), 2); ((1, 1), 4);
 ((2, 0), 3); ((2, 1), 6);  ((2, 2), 9);
 ((3, 0), 4); ((3, 1), 8);  ((3, 2), 12); ((3, 3), 16);
 ((4, 0), 5); ((4, 1), 10); ((4, 2), 15); ((4, 3), 20); ((4, 4), 25)]

let x3s = Array.init 5 (fun i -> Array.init (i+1) (fun j -> Array.init (j+1) (fun h -> (i+1)*(j+1)*(h+1)))) ;;
val x3s : int array array array =
[| [|[|1|]|];
   [|[|2|]; [|4; 8|]|];
   [|[|3|]; [|6; 12|]; [|9; 18; 27|]|];
   [|[|4|]; [|8; 16|]; [|12; 24; 36|]; [|16; 32; 48; 64|]|];
   [|[|5|]; [|10; 20|]; [|15; 30; 45|]; [|20; 40; 60; 80|]; [|25; 50; 75; 100; 125|]|] |]

Range.to_list (Range.of_array3D x3s) ;;
- : int list =
[1; 2; 4; 8; 3; 6; 12; 9; 18; 27; 4; 8; 16; 12; 24; 36; 16; 32; 48; 64; 5; 10; 20; 15; 30; 45; 20; 40; 60; 80; 25; 50; 75; 100; 125]

Range.to_list (Range.of_array3Di x3s) ;;
- : ((int * int * int) * int) list =
[((0, 0, 0), 1);  ((1, 0, 0), 2);   ((1, 1, 0), 4);  ((1, 1, 1), 8);
 ((2, 0, 0), 3);  ((2, 1, 0), 6);   ((2, 1, 1), 12); ((2, 2, 0), 9);
 ((2, 2, 1), 18); ((2, 2, 2), 27);  ((3, 0, 0), 4);  ((3, 1, 0), 8);
 ((3, 1, 1), 16); ((3, 2, 0), 12);  ((3, 2, 1), 24); ((3, 2, 2), 36);
 ((3, 3, 0), 16); ((3, 3, 1), 32);  ((3, 3, 2), 48); ((3, 3, 3), 64);
 ((4, 0, 0), 5);  ((4, 1, 0), 10);  ((4, 1, 1), 20); ((4, 2, 0), 15);
 ((4, 2, 1), 30); ((4, 2, 2), 45);  ((4, 3, 0), 20); ((4, 3, 1), 40);
 ((4, 3, 2), 60); ((4, 3, 3), 80);  ((4, 4, 0), 25); ((4, 4, 1), 50);
 ((4, 4, 2), 75); ((4, 4, 3), 100); ((4, 4, 4), 125)]

*)

(* ---------------------------------------------------------
                     Selections
                  (based on bind)
   --------------------------------------------------------- *)

(* ------------------------------------ *)
module Linear_power :
(* ------------------------------------ *)
  sig
    val make  : int (* k *) ->       'a  array ->            'a list  t
    val makei : int (* k *) -> ('i * 'a) array -> ('i list * 'a list) t
    val unoptimized : int (* k *) -> (index * 'a) array -> (index list * 'a list) t
    (* --- *)
    val filter_banned_places : Bitmasks.t -> (index * 'a) t -> (index * 'a) t
  end
(* ------------------------------------ *)
= struct

  (* INCLUDE "../STRUCTURES/RANGE/range.Linear_power.ml" *)

  let filter_banned_places (banned_places) =
    Cls.filteri (fun i _ -> (Bitmasks.mem i banned_places) = false)

  (* Hp: k>=1 *)
  let power_scheme (self) ~n ~(banned_places : Bitmasks.t) k (ixs : (index * 'a) cls) : (index list * 'a list) cls =
    (* --- *)
    let filter = filter_banned_places (banned_places) in
    (* --- *)
    if k=1 then
      Cls.mapi (fun i x -> ([i],[x])) (filter ixs)
    else (* continue with k>=1 *)
    (* --- *)
    bindi (filter ixs) (fun i x ->
      let banned_places = Bitmasks.add (i) (banned_places) in
      Cls.map (fun (is,xs) -> (i::is, x::xs)) (self ~n ~banned_places (k-1) ixs)
      )

  (* Alias: *)
  module Sel = Selections.Linear_power

  (* Recursively optimized scheme application: *)
  let rec make ~sel_make ~n ~(banned_places : Bitmasks.t) k (c1 : (index * 'a) cls) : (index list * 'a list) cls =
    (* Generate arrays with at most 16384/k indexes (where k is the length of inner lists of indexes): *)
    (* --- *)
    if (k>1) && (acceptable n k) then
      (* Optimized version: *)
      (* --- *)
      let filter = filter_banned_places (banned_places) in
      (* --- *)
      let js, xs = Cls.to_separated_arrays (filter c1) in
      let n' = Array.length js in (* n' = n - #banned_places *)
      let sels  : (index list) array = sel_make (n',k) in
      (* sels must be "translated" by js and xs in order to be a linear power of the filtered object c1() *)
      let jss : (index list) array = Array.map (List.map (fun i -> js.(i))) sels in
      let xss : ('a    list) array = Array.map (List.map (fun i -> xs.(i))) sels in
      (* --- *)
      of_separated_arrays (jss) (xss)
      (* --- *)
    else
      (* We begin with the ordinary method knowing that some recursive calls will be optimized: *)
      power_scheme (make ~sel_make) ~n ~banned_places k c1

  (* --- *)
  (* Global definitions for `make': *)
  and acceptable =
    (* Arrays of indexes of size up to 64Kb are stored instead of regenerated many times: *)
    let max_array_size = 65536 in
    fun n k -> not (Sel.skip ~max_array_size (n,k))

  (* Hp: k≥1. Redefinition: n is calculated (length) from the provided (supposed finite) range: *)
  let make k (xs : 'a array) : ('a list) cls =
    (* --- *)
    (* Transform the provided 'a array into a (index, 'a) sequence: *)
    let c1 : (index * 'a) cls = of_arrayi xs in
    let n = Array.length xs in
    (* --- *)
    if (k>n) then empty (* no solutions without repetitions *) else (* continue with n≥k: *)
    (* --- *)
    (* Sel.make is memoized again because we accept arrays of a greater size.
       Note however that is not a global memoization: the memoizations starts only now, i.e.
       once the couple (n,k) is provided, and disappears when the function returns. *)
    let sel_make = Memo.memoize (*~trace_faults:() ~trace_success:()*) Sel.make in
    (* --- *)
    let result : (index list * 'a list) cls =
      make ~sel_make ~n ~banned_places:(Bitmasks.empty ~dim:n ()) k c1
    in
    (* --- *)
    (* Remove additional indexes (useful to make the power, but not relevant for the user): *)
    Cls.mapi (fun _index x -> x) (result)

  (* Hp: k≥1. Split ('i * 'a) lists as final step of the generating process: *)
  let makei k (ixs : ('i * 'a) array) : ('i list * 'a list) cls =
    Cls.map (List.split) (make k ixs)

  (* For debugging: *)
  let unoptimized k (ixs : (index * 'a) array) : (index list * 'a list) cls =
    let range : (index * 'a) cls = of_array ixs in
    let n = Array.length ixs in
    let rec unoptimized ~n ~banned_places k r = power_scheme (unoptimized) ~n ~banned_places k r in
    unoptimized ~n ~banned_places:(Bitmasks.empty ~dim:n ()) k range

end (* Linear_power *)

(* ------------------------------------ *)
module Unordered_linear_power :
(* ------------------------------------ *)
  sig
    val make  : int (* k *) ->       'a  array ->            'a list  t
    val makei : int (* k *) -> ('i * 'a) array -> ('i list * 'a list) t
    val unoptimized : int (* k *) -> (index * 'a) array -> (index list * 'a list) t
  end
(* ------------------------------------ *)
= struct
  (* INCLUDE "../STRUCTURES/RANGE/range.Unordered_linear_power.ml" *)

  (* val singleton : int -> Bitmasks.t array
     Memoized for n <= Bitmasks.b * 2 (124 ) *)
  let singleton =
    let singleton n = Array.init n (Bitmasks.singleton ~dim:n) in
    let max_n = Bitmasks.dpi * 2 (* 64 bits architecture => max_n=124 *) in
    Memo.memoize ~skip:(fun n -> n>max_n) singleton

  (* Hp: k>=1 *)
  let power_scheme (self) ~n ~(banned_places : Bitmasks.t) k ixs : ((index list * Bitmasks.t) * 'a list) cls =
    (* --- *)
    let filter = Linear_power.filter_banned_places (banned_places) in
    (* --- *)
    if k=1 then
      let singleton = singleton n in
      Cls.mapi (fun i x -> (([i], singleton.(i)),[x])) (filter ixs)
    else (* continue with k>=1 *)
    (* --- *)
    Cls.uniq_image (fun ((is, bm), xs) -> bm) (
      bindi (filter ixs) (fun i x ->
        let banned_places = Bitmasks.add (i) (banned_places) in
        Cls.map (fun ((is, bm), xs) -> ((i::is, Bitmasks.add i bm), x::xs)) (self ~n ~banned_places (k-1) ixs)
        ))

  (* Alias: *)
  module Sel = Selections.Unordered_linear_power

  (* Recursively optimized scheme application: *)
  let rec make ~sel_make ~n ~(banned_places : Bitmasks.t) k (c1 : (index * 'a) cls) : ((index list * Bitmasks.t) * 'a list) cls =
    (* Generate arrays with at most 16384/k indexes (where k is the length of inner lists of indexes): *)
    (* --- *)
    if (k>1) && (acceptable n k) then
      (* Optimized version: *)
      (* --- *)
      let filter = Linear_power.filter_banned_places (banned_places) in
      (* --- *)
      let js, xs = Cls.to_separated_arrays (filter c1) in
      let n' = Array.length js in (* n' = n - #banned_places *)
      let sels  : (index list) array = sel_make (n',k) in
      (* sels must be "translated" by js and xs in order to be a linear power of the filtered object c1() *)
      let jss : (index list) array = Array.map (List.map (fun i -> js.(i))) sels in
      let xss : ('a    list) array = Array.map (List.map (fun i -> xs.(i))) sels in
      (* --- *)
      (* The bitmasks structure is made here to render this function compatible with power_scheme: *)
      let jsbs = Array.map (fun js -> (js, Bitmasks.of_list ~dim:n js)) jss in
      (* --- *)
      of_separated_arrays (jsbs) (xss)
      (* --- *)
    else
      (* We begin with the ordinary method knowing that some recursive calls will be optimized: *)
      power_scheme (make ~sel_make) ~n ~banned_places k c1

  (* --- *)
  (* Global definitions for `make': *)
  and acceptable =
    (* Arrays of indexes of size up to 64Kb are stored instead of regenerated many times: *)
    let max_array_size = 65536 in
    fun n k -> not (Sel.skip ~max_array_size (n,k))

  (* Hp: k≥1. Redefinition: n is calculated (length) from the provided array: *)
  let make k (xs : 'a array) : ('a list) cls =
    (* --- *)
    (* Transform the provided 'a array into a (index, 'a) sequence : *)
    let c1  : (index * 'a) cls = of_arrayi xs in
    let n = Array.length xs in
    (* --- *)
    if (k>n) then empty (* no solutions without repetitions *) else (* continue with n≥k: *)
    (* --- *)
    (* Sel.make is memoized again because we accept arrays of a greater size.
       Note however that is not a global memoization: the memoizations starts only now, i.e.
       once the couple (n,k) is provided, and disappears when the function returns. *)
    let sel_make = Memo.memoize (*~trace_faults:() ~trace_success:()*) Sel.make in
    (* --- *)
    let result : ((index list * Bitmasks.t) * 'a list) cls =
      make ~sel_make ~n ~banned_places:(Bitmasks.empty ~dim:n ()) k c1
    in
    (* --- *)
    (* Remove additional indexes and bitmasks (useful to make the power, but not relevant for the user): *)
    Cls.mapi (fun _stuff x -> x) (result)

  (* Hp: k≥1. Split ('i * 'a) lists as final step of the generating process: *)
  let makei k (ixs : ('i * 'a) array) : ('i list * 'a list) cls =
    Cls.map (List.split) (make k ixs)

  (* For debugging: *)
  let unoptimized k (ixs : (index * 'a) array) : (index list * 'a list) cls =
    let range : (index * 'a) cls = of_array ixs in
    let n = Array.length ixs in
    let rec unoptimized ~n ~banned_places k r = power_scheme (unoptimized) ~n ~banned_places k r in
    let result = unoptimized ~n ~banned_places:(Bitmasks.empty ~dim:n ()) k range in
    Cls.mapi (fun (is,bm) xs -> (is,xs)) (result)

end (* Unordered_linear_power *)

(* ------------------------------------ *)
module Unordered_power :
(* ------------------------------------ *)
  sig
    val make  : int (* k *) ->       'a  array ->            'a list  t
    val makei : int (* k *) -> ('i * 'a) array -> ('i list * 'a list) t
    val unoptimized : int (* k *) -> (index * 'a) array -> (index list * 'a list) t
  end
= struct
(* ------------------------------------ *)
  (* INCLUDE "../STRUCTURES/RANGE/range.Unordered_power.ml" *)

  (* Note: because we are in a non-linear context, the involved unicity (Cls.uniq_image) is
           related to the multiset equivalence, not on the set equivalence.
           In other terms, we have to use Bitmmasks.t instead of Bitmasks.t. *)

  (* val singleton : int -> Bitmmasks.t array
     Memoized for n <= Bitmasks.b * 2 (124 ) *)
  let singleton =
    let singleton n = Array.init n (Bitmmasks.singleton ~dim:n) in
    let max_n = Bitmasks.dpi * 2 (* 64 bits architecture => max_n=124 *) in
    Memo.memoize ~skip:(fun n -> n>max_n) singleton

  (* Hp: k>=1 *)
  let power_scheme (self) ~n k (ixs : (index * 'a) cls) : ((index list * Bitmmasks.t) * 'a list) cls =
    (* --- *)
    if k=1 then
      let singleton = singleton n in (* multiset singleton *)
      Cls.mapi (fun i x -> (([i], singleton.(i)),[x])) (ixs)
    else (* continue with k>=1 *)
    (* --- *)
    Cls.uniq_image (fun ((is, bm), xs) -> bm) (
      bindi (ixs) (fun i x ->
        Cls.map (fun ((is, bm), xs) -> ((i::is, Bitmmasks.add i bm), x::xs)) (self ~n (k-1) ixs)
        ))

  (* Alias: *)
  module Sel = Selections.Unordered_power

  let sel_to_separated_arrays xs =
    fun (n,k) ->
      let sels : (index list) array = Sel.make (n,k) in
      (* --- *)
      let jss : (index list) array = sels in
      let xss : ('a    list) array = Array.map (List.map (fun i -> xs.(i))) sels in
      (* --- *)
      let jsbs = Array.map (fun js -> (js, Bitmmasks.of_list ~dim:n js)) jss in (* !!!!!!!!!!!!!!! OCCORRE UNA VERSIONE EFFICIENTE DI Bitmmasks.of_list !!!!!! *)
      (* --- *)
      (jsbs, xss)

  (* Recursively optimized scheme application: *)
  let rec make ~sel_make ~n k (c1 : (index * 'a) cls) : ((index list * Bitmmasks.t) * 'a list) cls =
    (* Generate arrays with at most 16384/k indexes (where k is the length of inner lists of indexes): *)
    (* --- *)
    if (k>1) && (acceptable n k) then
      (* Optimized version: *)
      (* --- *)
      let (jsbs, xss) = sel_make (n,k) in
      of_separated_arrays (jsbs) (xss)
      (* --- *)
    else
      (* We begin with the ordinary method knowing that some recursive calls will be optimized: *)
      power_scheme (make ~sel_make) ~n k c1

  (* --- *)
  (* Global definitions for `make': *)
  and acceptable =
    (* Arrays of indexes of size up to 64Kb are stored instead of regenerated many times: *)
    let max_array_size = 65536 in
    fun n k -> not (Sel.skip ~max_array_size (n,k))

  (* Hp: k≥1. Redefinition: n is calculated (length) from the provided (supposed finite) range: *)
  let make k (xs : 'a array) : ('a list) cls =
    (* --- *)
    (* Transform the provided 'a array into a (index, 'a) sequence: *)
    let c1 : (index * 'a) cls = of_arrayi xs in
    let n = Array.length xs in
    (* --- *)
    if (n=0) then empty (* 0ᵏ = 0 with k≥1 *) else (* continue with n≥1: *)
    (* --- *)
    let sel_make = (sel_to_separated_arrays xs) in
    (* --- *)
    let result : ((index list * Bitmmasks.t) * 'a list) cls =
      make ~sel_make ~n k c1
    in
    (* --- *)
    (* Remove additional indexes (useful to make the power, but not relevant for the user): *)
    Cls.mapi (fun _stuff x -> x) (result)

  (* Hp: k≥1. Split ('i * 'a) lists as final step of the generating process: *)
  let makei k (ixs : ('i * 'a) array) : ('i list * 'a list) cls =
    Cls.map (List.split) (make k ixs)

  (* For debugging: *)
  let unoptimized k (ixs : (index * 'a) array) : (index list * 'a list) cls =
    let range : (index * 'a) cls = of_array ixs in
    let n = Array.length ixs in
    let rec unoptimized ~n k r = power_scheme (unoptimized) ~n k r in
    let result = unoptimized ~n k range in
    Cls.mapi (fun (is,bm) xs -> (is,xs)) (result)

end (* Unordered_power *)

(* ------------------------------------ *)
module Power :
(* ------------------------------------ *)
  sig
    val make  : int (* k *) ->       'a  array ->            'a list  t
    val makei : int (* k *) -> ('i * 'a) array -> ('i list * 'a list) t
    val unoptimized : int (* k *) -> (index * 'a) array -> (index list * 'a list) t
  end
(* ------------------------------------ *)
= struct
  (* INCLUDE "../STRUCTURES/RANGE/range.Power.ml" *)

  (* Hp: k>=1 *)
  let power_scheme (self) k (ixs : (index * 'a) cls) : (index list * 'a list) cls =
    (* --- *)
    if k=1 then
      Cls.mapi (fun i x -> ([i],[x])) (ixs)
    else (* continue with k>=1 *)
    (* --- *)
    bindi (ixs) (fun i x ->
      Cls.map (fun (is, xs) -> (i::is, x::xs)) (self (k-1) ixs)
      )

  (* Alias: *)
  module Sel = Selections.Power

  let sel_to_separated_arrays xs =
    fun (n,k) ->
      let sels : (index list) array = Sel.make (n,k) in
      (* --- *)
      let jss : (index list) array = sels in
      let xss : ('a    list) array = Array.map (List.map (fun i -> xs.(i))) sels in
      (* --- *)
      (jss, xss)

  (* Recursively optimized scheme application: *)
  let rec make ~sel_make ~n k (c1 : (index * 'a) cls) : (index list * 'a list) cls =
    (* Generate arrays with at most 16384/k indexes (where k is the length of inner lists of indexes): *)
    (* --- *)
    if (k>1) && (acceptable n k) then
      (* Optimized version: *)
      (* --- *)
      let (jss, xss) = sel_make (n,k) in
      of_separated_arrays (jss) (xss)
      (* --- *)
    else
      (* Ordinary method with some optimized recursive calls: *)
      power_scheme (make ~sel_make ~n) k c1

  (* --- *)
  (* Global definitions for `make': *)
  and acceptable =
    (* Arrays of indexes of size up to 64Kb are stored instead of regenerated many times: *)
    let max_array_size = 65536 in
    fun n k -> not (Sel.skip ~max_array_size (n,k))

  (* Hp: k≥1. Redefinition: n is calculated (length) from the provided (supposed finite) range: *)
  let make k (xs : 'a array) : ('a list) cls =
    (* --- *)
    (* Transform the provided 'a array into a (index, 'a) sequence: *)
    let c1 : (index * 'a) cls = of_arrayi xs in
    let n = Array.length xs in
    (* --- *)
    if (n=0) then empty (* 0ᵏ = 0 with k≥1 *) else (* continue with n≥1: *)
    (* --- *)
    let sel_make = (sel_to_separated_arrays xs) in
    (* --- *)
    let result : (index list * 'a list) cls =
      make ~sel_make ~n k c1
    in
    (* --- *)
    (* Remove additional indexes (useful to make the power, but not relevant for the user): *)
    Cls.mapi (fun _index x -> x) (result)

  (* Hp: k≥1. Split ('i * 'a) lists as final step of the generating process: *)
  let makei k (ixs : ('i * 'a) array) : ('i list * 'a list) cls =
    Cls.map (List.split) (make k ixs)

  (* For debugging: *)
  let unoptimized k (ixs : (index * 'a) array) : (index list * 'a list) cls =
    let range : (index * 'a) cls = of_array ixs in
    let rec unoptimized k r = power_scheme (unoptimized) k r in
    unoptimized k range

end (* Power *)

(* ------------------------------------ *)
module Bounded_power :
(* ------------------------------------ *)
  sig
    val make  : int (* k *) -> ('a  * card) array -> 'a list  t
    val makei : int (* k *) -> (('i * 'a) * card) array -> ('i list * 'a list) t
  end
  (* Examples:

      Range.to_list (Range.Bounded_power.make 2 [|('A',3); ('B',2); ('C',1)|]);;
      (* - : char list list = [['A'; 'A']; ['A'; 'B']; ['A'; 'C']; ['B'; 'A']; ['B'; 'B']; ['B'; 'C']; ['C'; 'A']; ['C'; 'B']] *)

      Range.to_list (Range.Bounded_power.make 3 [|('A',3); ('B',2); ('C',1)|]);;
      (* - : char list list =
      [['A'; 'A'; 'A']; ['A'; 'A'; 'B']; ['A'; 'A'; 'C']; ['A'; 'B'; 'A']; ['A'; 'B'; 'B']; ['A'; 'B'; 'C']; ['A'; 'C'; 'A']; ['A'; 'C'; 'B'];
       ['B'; 'A'; 'A']; ['B'; 'A'; 'B']; ['B'; 'A'; 'C']; ['B'; 'B'; 'A']; ['B'; 'B'; 'C']; ['B'; 'C'; 'A']; ['B'; 'C'; 'B'];
       ['C'; 'A'; 'A']; ['C'; 'A'; 'B']; ['C'; 'B'; 'A']; ['C'; 'B'; 'B']] *)

      let y1 = Range.to_list (Range.Bounded_power.make 3 [|('A',1); ('B',1); ('C',1); ('D',1); ('E',1) |]);;
      let y2 = Range.to_list (Range.Linear_power.make  3 [|'A'; 'B'; 'C'; 'D'; 'E'|]);;
      y1 = y2 ;;
      (* - : bool = true *)
  *)
(* ------------------------------------ *)
= struct
  (* INCLUDE "../STRUCTURES/RANGE/range.Bounded_power.ml" *)

  let filter_with_bounds (bounds) =
    Cls.filteri (fun i _ -> Bitmmasks.mem i bounds)

  (* val singleton : int -> Bitmasks.t array
     Memoized for n <= Bitmasks.b * 2 (probably 124) *)
  let singleton =
    let singleton n = Array.init n (Bitmmasks.singleton ~dim:n) in
    let max_n = Bitmasks.dpi * 2 (* 64 bits architecture => max_n=124 *) in
    Memo.memoize ~skip:(fun n -> n>max_n) singleton

  (* Hp: k>=1 *)
  let rec bounded_power ~n ~(bounds : Bitmmasks.t) k ixs : ((index list * Bitmmasks.t) * 'a list) cls =
    (* --- *)
    let filter = filter_with_bounds (bounds) in
    (* --- *)
    if k=1 then
      let singleton = singleton n in
      Cls.mapi (fun i x -> (([i], singleton.(i)),[x])) (filter ixs)
    else (* continue with k>=1 *)
    (* --- *)
    Cls.uniq_image (fun ((is, bm), xs) -> (bm, is)) (  (* <= here we check the unicity using the bitmasks first for efficiency *)
      bindi (filter ixs) (fun i x ->
        let bounds = Bitmmasks.remove (i) (bounds) in
        Cls.map (fun ((is, bm), xs) -> ((i::is, Bitmmasks.add i bm), x::xs)) (bounded_power ~n ~bounds (k-1) ixs)
        ))

  (* val make  : int (* k *) -> ('a  * card) cls -> ('a list) cls
     Hp: k≥1. Here n is calculated (length) from the provided (supposed finite) range: *)
  let make k (xcs : ('a * card) array) : ('a list) cls =
    (* --- *)
    (* Transform the provided 'a array into a (index, 'a) sequence: *)
    let xs    = Array.map fst xcs in
    let cards = Array.map snd xcs in
    (* --- *)
    let c1  : (index * 'a) cls = of_arrayi xs in
    let n = Array.length xs in
    (* --- *)
    if (n=0) then empty (* 0ᵏ = 0 with k≥1 *) else (* continue with n≥1: *)
    (* --- *)
    let bounds = Bitmmasks.of_multiplicities ~dim:n cards in
    (* --- *)
    let result : ((index list * Bitmmasks.t) * 'a list) cls =
      bounded_power ~n ~bounds k c1
    in
    (* --- *)
    (* Remove additional indexes and bitmasks (useful to make the power, but not relevant for the user): *)
    Cls.mapi (fun _stuff x -> x) (result)

  (* Hp: k≥1. Split ('i * 'a) lists as final step of the generating process: *)
  (* val makei : int (* k *) -> (('i * 'a) * card) cls -> ('i list * 'a list) cls *)
  let makei k (ixcs : (('i * 'a) * card) array) : ('i list * 'a list) cls =
    Cls.map (List.split) (make k ixcs)

end (* Bounded_power *)

(* ------------------------------------ *)
module Unordered_bounded_power :
(* ------------------------------------ *)
  sig
    val make  : int (* k *) ->       ('a  * card) array -> 'a list  t
    val makei : int (* k *) -> (('i * 'a) * card) array -> ('i list * 'a list) t
  end
  (* Examples :

      Range.to_list (Range.Unordered_bounded_power.make 2 (Range.of_list [('A',3); ('B',2); ('C',1)]));;
      - : char list list = [['A'; 'A']; ['A'; 'B']; ['A'; 'C']; ['B'; 'B']; ['B'; 'C']]

      Range.to_list (Range.Unordered_bounded_power.make 3 (Range.of_list [('A',3); ('B',2); ('C',1)]));;
      (* - : char list list = [['A'; 'A'; 'A']; ['A'; 'A'; 'B']; ['A'; 'A'; 'C']; ['A'; 'B'; 'B']; ['A'; 'B'; 'C']; ['B'; 'B'; 'C']] *)

      let y1 = Range.to_list (Range.Unordered_bounded_power.make 3 (Range.of_list [('A',1); ('B',1); ('C',1); ('D',1); ('E',1) ]));;
      let y2 = Range.to_list (Range.Unordered_linear_power.make  3 (Range.of_list ['A'; 'B'; 'C'; 'D'; 'E']));;
      y1 = y2 ;;
      (* - : bool = true *)

  *)
(* ------------------------------------ *)
= struct
  (* INCLUDE "../STRUCTURES/RANGE/range.Unordered_bounded_power.ml" *)

  let filter_with_bounds (bounds) =
    Cls.filteri (fun i _ -> Bitmmasks.mem i bounds)

  (* val singleton : int -> Bitmasks.t array
     Memoized for n <= Bitmasks.b * 2 (124 ) *)
  let singleton =
    let singleton n = Array.init n (Bitmmasks.singleton ~dim:n) in
    let max_n = Bitmasks.dpi * 2 (* 64 bits architecture => max_n=124 *) in
    Memo.memoize ~skip:(fun n -> n>max_n) singleton

  (* Hp: k>=1 *)
  let rec bounded_power ~n ~(bounds : Bitmmasks.t) k ixs : ((index list * Bitmmasks.t) * 'a list) cls =
    (* --- *)
    let filter = filter_with_bounds (bounds) in
    (* --- *)
    if k=1 then
      let singleton = singleton n in
      Cls.mapi (fun i x -> (([i], singleton.(i)),[x])) (filter ixs)
    else (* continue with k>=1 *)
    (* --- *)
    Cls.uniq_image (fun ((is, bm), xs) -> bm) (
      bindi (filter ixs) (fun i x ->
        let bounds = Bitmmasks.remove (i) (bounds) in
        Cls.map (fun ((is, bm), xs) -> ((i::is, Bitmmasks.add i bm), x::xs)) (bounded_power ~n ~bounds (k-1) ixs)
        ))

  (* val make  : int (* k *) -> ('a  * card) cls -> ('a list) cls
     Hp: k≥1. Here n is calculated (length) from the provided (supposed finite) range: *)
  let make k (xcs : ('a * card) array) : ('a list) cls =
    (* --- *)
    (* Transform the provided 'a sequence into a (index, 'a) sequence: *)
    let xs    = Array.map fst xcs in
    let cards = Array.map snd xcs in
    (* --- *)
    let c1  : (index * 'a) cls = of_arrayi xs in
    let n = Array.length xs in
    (* --- *)
    if (n=0) then empty (* 0ᵏ = 0 with k≥1 *) else (* continue with n≥1: *)
    (* --- *)
    let bounds = Bitmmasks.of_multiplicities ~dim:n cards in
    (* --- *)
    let result : ((index list * Bitmmasks.t) * 'a list) cls =
      bounded_power ~n ~bounds k c1
    in
    (* --- *)
    (* Remove additional indexes and bitmasks (useful to make the power, but not relevant for the user): *)
    Cls.mapi (fun _stuff x -> x) (result)

  (* Hp: k≥1. Split ('i * 'a) lists as final step of the generating process: *)
  (* val makei : int (* k *) -> (('i * 'a) * card) cls -> ('i list * 'a list) cls *)
  let makei k (ixcs : (('i * 'a) * card) array) : ('i list * 'a list) cls =
    Cls.map (List.split) (make k ixcs)

end (* Unordered_bounded_power *)

(* -------------------------------------
   Optimized selections of k elements from a range (of n).
   This module contains 12 variants implemented quite efficiently.

   Note however that a (unoptimized) variant already exists:
     (power (Range.of_array xs) k) = (Range.Selections.make ~repetitions:() ?unordered:None ~k xs)
   ------------------------------------- *)
module Selections : sig

  (* With or without (unbounded) repetitions, ordered or not (4 cases per function => 8 variants): *)

  val make  : ?repetitions:unit -> ?unordered:unit -> k:int -> 'a array -> ('a list) t
  val makei : ?repetitions:unit -> ?unordered:unit -> k:int -> ('i * 'a) array -> ('i list * 'a list) t

  (* With bounded repetitions, ordered or not (2 cases per function => 4 variants).
     Bounded variants are not optimized. *)

  type quantity = int

  val bounded  : ?unordered:unit -> k:int -> ('a * quantity) array -> ('a list) t
  val boundedi : ?unordered:unit -> k:int -> (('i * 'a) * quantity) array -> ('i list * 'a list) t

end
(* ------------------------------------- *)
= struct

  (* With or without (unbounded) repetitions, ordered or not (4 cases per function => 8 variants): *)

  (* val make  : ?repetitions:unit -> ?unordered:unit -> k:int -> 'a array -> ('a list) cls *)
  let make ?repetitions ?unordered ~k xs =
    (* --- *)
    if (k<0) then invalid_arg "Range.Selections.make: negative number of places" else (* continue: *)
    if (k=0) then Cls.singleton [] (* n⁰ = 0⁰ = 1 *) else (* continue with k≥1 *)
    (* --- *)
    match unordered, repetitions with
    (* --- *)
    (* (Linear_power) The order is relevant, elements cannot be duplicated: *)
    | None, None -> Linear_power.make k xs
    (* --- *)
    (* (Power) The order is relevant, elements can be duplicated: *)
    | None, Some () -> Power.make k xs
    (* --- *)
    (* (Unordered_linear_power) The order is irrelevant, elements cannot be duplicated: *)
    | Some (), None -> Unordered_linear_power.make k xs
    (* --- *)
    (* (Unordered_power) The order is irrelevant, elements can be duplicated: *)
    | Some (), Some () -> Unordered_power.make k xs

  (* val makei : ?repetitions:unit -> ?unordered:unit -> k:int -> ('i * 'a) array -> ('i list * 'a list) cls *)
  let makei ?repetitions ?unordered ~k xs =
    (* --- *)
    if (k<0) then invalid_arg "Range.Selections.makei: negative number of places" else (* continue: *)
    if (k=0) then Cls.singleton ([],[]) (* n⁰ = 0⁰ = 1 *) else (* continue with k≥1 *)
    (* --- *)
    match unordered, repetitions with
    (* --- *)
    (* (Linear_power) The order is relevant, elements cannot be duplicated: *)
    | None, None -> Linear_power.makei k xs
    (* --- *)
    (* (Power) The order is relevant, elements can be duplicated: *)
    | None, Some () -> Power.makei k xs
    (* --- *)
    (* (Unordered_linear_power) The order is irrelevant, elements cannot be duplicated: *)
    | Some (), None -> Unordered_linear_power.makei k xs
    (* --- *)
    (* (Unordered_power) The order is irrelevant, elements can be duplicated: *)
    | Some (), Some () -> Unordered_power.makei k xs

  (* With bounded repetitions, ordered or not (2 cases per function => 4 variants): *)

  type quantity = int

  (* val bounded  : ?unordered:unit -> k:int -> ('a * quantity) array -> ('a list) cls *)
  let bounded ?unordered ~k xs =
    (* --- *)
    if (k<0) then invalid_arg "Range.Selections.bounded: negative number of places" else (* continue: *)
    if (k=0) then Cls.singleton [] (* n⁰ = 0⁰ = 1 *) else (* continue with k≥1 *)
    (* --- *)
    match unordered with
    (* --- *)
    (* (Bounded_power) The order is relevant: *)
    | None -> Bounded_power.make k xs
    (* --- *)
    (* (Unordered_bounded_power) The order is irrelevant: *)
    | Some () -> Unordered_bounded_power.make k xs

  (* val boundedi : ?unordered:unit -> k:int -> (('i * 'a) * quantity) array -> ('i list * 'a list) cls *)
  let boundedi ?unordered ~k xs =
    (* --- *)
    if (k<0) then invalid_arg "Range.Selections.boundedi: negative number of places" else (* continue: *)
    if (k=0) then Cls.singleton ([],[]) (* n⁰ = 0⁰ = 1 *) else (* continue with k≥1 *)
    (* --- *)
    match unordered with
    (* --- *)
    (* (Bounded_power) The order is relevant: *)
    | None -> Bounded_power.makei k xs
    (* --- *)
    (* (Unordered_bounded_power) The order is irrelevant: *)
    | Some () -> Unordered_bounded_power.makei k xs

end (* Selections *)

type quantity = int

let of_selections = Selections.make
let of_selectionsi = Selections.makei
let of_bounded_selections = Selections.bounded
let of_bounded_selectionsi = Selections.boundedi

(* val of_permutations : 'a array -> ('a list) t *)
(* Alias for Range.Selections.make ?unordered:None ?repetitions:None ~k:(Range.length xs) xs *)
let of_permutations xs =
  Selections.make ?unordered:None ?repetitions:None ~k:(Array.length xs) xs

(* val of_combinations : k:int -> 'a array -> ('a list) t *)
(* Alias for Range.Selections.make ~unordered:() ?repetitions:None ~k *)
let of_combinations ~k xs =
  Selections.make ~unordered:() ?repetitions:None ~k xs

(* Alias: *)
let of_ksubsets = of_combinations

(* Concatenation of combinations for k=1..(Array.length xs) *)
(* val of_subsets : 'a array -> ('a list) t *)
let of_subsets xs =
  let n = Array.length xs in
  let ks = Int.forward ~start:0 ~stop:(n+1) () in
  bind ks (fun k -> of_combinations ~k xs)

let of_permutationsi xs =
  Selections.makei ?unordered:None ?repetitions:None ~k:(Array.length xs) xs

(* val of_combinations : k:int -> 'a array -> ('a list) t *)
(* Alias for Range.Selections.make ~unordered:() ?repetitions:None ~k xs *)
let of_combinationsi ~k xs =
  Selections.makei ~unordered:() ?repetitions:None ~k xs

(* Alias: *)
let of_ksubsetsi = of_combinationsi

(* Concatenation of combinations for k=1..(Array.length xs) *)
(* val of_subsets : 'a array -> ('a list) t *)
let of_subsetsi xs =
  let n = Array.length xs in
  let ks = Int.forward ~start:0 ~stop:(n+1) () in
  bind ks (fun k -> of_combinationsi ~k xs)

(* ---------------------------------------------------------
                        Foreach
    (bind with states based on append_taking_the_last_state)
   --------------------------------------------------------- *)

(* val foreach : 'a  cls -> 's -> ('s -> 'a -> ('s * 'b) cls) -> ('s, 'b) cls
---
let r1 = Range.of_list ['A'; 'B'; 'C'] ;;
let r2 = Range.of_list [3.14; 2.71] ;;
open Range ;;

let r =
  foreach r1 0 (fun s x ->
    foreach r2 s (fun s y ->
      singleton (s+1, (x,y,s))
  )) ;;

Range.to_list r ;;
- : (int * (char * float * int)) list =
[(1, ('A', 3.14, 0)); (2, ('A', 2.71, 1));
 (3, ('B', 3.14, 2)); (4, ('B', 2.71, 3));
 (5, ('C', 3.14, 4)); (6, ('C', 2.71, 5))]
*)
let foreach cls s0 f =
  let rec loop obj s () : ('s * 'b) obj =
    let x = obj () in
    let sbs = (f s x) in
    (* Preserva la pigrizia prendendo l'ultimo stato: *)
    let r' = Obj.append_taking_the_last_state (s) (sbs ()) (fun s' -> loop obj s' ()) in
    r'
  (* --- *)
  in
  fun () -> loop (cls ()) s0 ()

(* val foreachi : ('i * 'a) cls -> 's -> ('s -> 'i -> 'a -> ('s * 'b) cls) -> ('s * 'b) cls *)
let foreachi cls s0 f =
  let rec loop obj s () : ('s * 'b) obj =
    let i, x = obj () in
    let sbs = (f s i x) in
    (* Preserva la pigrizia prendendo l'ultimo stato: *)
    let r' = Obj.append_taking_the_last_state (s) (sbs ()) (fun s' -> loop obj s' ()) in
    r'
  (* --- *)
  in
  fun () -> loop (cls ()) s0 ()


IFDEF DOCUMENTATION_OR_DEBUGGING THEN
(* ---------------------------------------------------------
                foreach vs StateT.bind
   --------------------------------------------------------- *)

module StateT
: sig
    type ('s,'a) t = 's -> ('s * 'a) cls

    (* val return : 'a -> ('s,'a) t *)
    val return    : 'a -> 's -> ('s * 'a) cls

    (* val bind : ('s, 'a) t -> ('a -> ('s, 'b) t) -> ('s, 'b) t *)
    val bind    : ('s -> ('s * 'a) cls) -> ('a -> 's -> ('s * 'b) cls) -> 's -> ('s * 'b) cls

    (* val lift : 'a cls -> ('s,'a) t *)
    val lift : 'a cls -> 's -> ('s * 'a) cls

  end
= struct
    type ('s, 'a) t = 's -> ('s * 'a) cls

    let lift cls = fun s -> (*Range.*)bind cls (fun x -> (*Range.*)return (s,x))

    let bind (m : ('s, 'a) t) (f : 'a -> ('s, 'b) t) : ('s, 'b) t =
       fun s -> (*Range.*)bind (m s) (fun (s',x) -> f x s')

    let return x = fun s -> (*Range.*)return (s,x)

  end (* StateT *)

(* val StateT.bind : ('s -> ('s * 'a) cls) -> ('a -> 's -> ('s * 'b) cls) -> 's -> ('s * 'b) cls *)
(* val foreach     : 'a cls -> 's -> ('s -> 'a -> ('s * 'b) cls) -> ('s, 'b) cls *)
(* val foreach_v2  : 'a cls -> 's -> ('s -> 'a -> ('s * 'b) cls) -> ('s, 'b) cls *)
let foreach_v2 cls s0 f =
  let flipped_f a s = f s a in
  StateT.bind (StateT.lift cls) (flipped_f) s0

(* Example:

let r1 = Range.of_list ['A'; 'B'; 'C'] ;;
let r2 = Range.of_list [3.14; 2.71] ;;
open Range ;;

let r =
  foreach_v2 r1 0 (fun s x ->
    foreach_v2 r2 s (fun s y ->
      singleton (s+1, (x,y,s))
  )) ;;

(* val r : (int * (char * float * int)) cls *)
Range.to_list r ;;
(*  - : (int * (char * float * int)) list =
    [(1, ('A', 3.14, 0)); (1, ('A', 2.71, 0)); (1, ('B', 3.14, 0));
     (1, ('B', 2.71, 0)); (1, ('C', 3.14, 0)); (1, ('C', 2.71, 0))] *)
*)

ENDIF
(* --------------------------------------------------------- *)


(* In this module the functions are structured with labelled arguments,
   where ~body is suggested to be defined as last argument. *)
(* --------------------------------------------------------- *)
module Nest = struct
(* --------------------------------------------------------- *)

  (* val layer : range:'a cls -> init:'s -> body:('s -> 'a -> ('s * 'b) cls) -> ('s * 'b) cls *)
  let layer ~range ~init ~body = foreach range init body

  (* val layeri : range:('i * 'a) cls -> init:'s -> body:('s -> 'i -> 'a -> ('s * 'b) cls) -> ('s * 'b) cls *)
  let layeri ~range ~init ~body = foreachi range init body

  (* val core : range:'a cls -> init:'s -> body:('s -> 'a -> 's * 'b) -> ('s * 'b) cls *)
  let core ~range ~init ~body = (* map_folding *)
    let rec loop obj s () : ('s * 'b) obj =
      let x = obj () in
      let (s',b) = (body s x) in
      Cls.cons (s',b) (loop obj s') ()
    (* --- *)
    in
    fun () -> loop (range ()) init ()

  (* val init : range:'a t -> init:'s -> body:('s -> 'a ->  's * 'b) -> 'b t  (* Equivalent to snd∘core *) *)
  let init ~range ~init ~body = (* init_folding *)
    let rec loop obj s () : 'b obj =
      let x = obj () in
      let (s',b) = (body s x) in
      Cls.cons (b) (loop obj s') ()
    (* --- *)
    in
    fun () -> loop (range ()) init ()

  (* val corei : range:('i * 'a) cls -> init:'s -> body:('s -> 'i -> 'a -> 's * 'b) -> ('s * 'b) cls *)
  let corei ~range ~init ~body =  (* map_foldingi *)
    let rec loop obj s () : ('s * 'b) obj =
      let i, x = obj () in
      let (s',b) = (body s i x) in
      Cls.cons (s',b) (loop obj s') ()
    (* --- *)
    in
    fun () -> loop (range ()) init ()

  (* val initi : range:('i * 'a) t -> init:'s -> body:('s -> 'i -> 'a ->  's * 'b) -> 'b t (* snd∘corei *) *)
  let initi ~range ~init ~body =  (* init_foldingi *)
    let rec loop obj s () : 'b obj =
      let i, x = obj () in
      let (s',b) = (body s i x) in
      Cls.cons (b) (loop obj s') ()
    (* --- *)
    in
    fun () -> loop (range ()) init ()

  (* val trail : range:'a cls -> init:'s -> body:('s -> 'a -> 's) -> 's cls *)
  let trail ~range ~init ~body =
    let rec loop obj s () : 's obj =
      let x = obj () in
      let s' = (body s x) in
      Cls.cons s' (loop obj s') ()
    (* --- *)
    in
    fun () -> loop (range ()) init ()

  (* val traili : range:('i * 'a) cls -> init:'s -> body:('s -> 'i -> 'a -> 's) -> 's cls *)
  let traili ~range ~init ~body =
    let rec loop obj s () : 's obj =
      let i, x = obj () in
      let s' = (body s i x) in
      Cls.cons s' (loop obj s') ()
    (* --- *)
    in
    fun () -> loop (range ()) init ()

  IFDEF DOCUMENTATION_OR_DEBUGGING THEN
  (* layer has the same type but is not stateT_bind: *)
  (* val stateT_bind : range:'a cls -> init:'s -> body:('s -> 'a -> ('s * 'b) cls) -> ('s * 'b) cls *)
  let stateT_bind ~range ~init ~body = foreach_v2 range init body
  ENDIF

end (* Nest *)

(*(*(*(*  (* val fold : ?break:('s -> 'a -> bool) -> range:'a t -> init:'s -> body:('s -> 'a -> 's) -> 's *)
  let fold = Cls.fold

  (* val foldi : range:('i * 'a) cls -> init:'s -> body:('s -> 'i -> 'a -> 's) -> 's *)
  let foldi = Cls.foldi*)*)*)*)

(* ------------------------------------------------
                  Consumers
               (based on fold)
   ------------------------------------------------ *)

(* val for_all : ('a -> bool) -> 'a cls -> bool *)
let for_all p range =
  Cls.Fold.while_do (fun s _ -> s) ~range ~init:true ~body:(fun _ -> p)

(* val exists : ('a -> bool) -> 'a t -> bool *)
let exists p range =
  Cls.Fold.do_while (fun s _ -> not s) ~range ~init:false ~body:(fun _ -> p)

(* val for_alli : ('i -> 'a -> bool) -> ('i * 'a) t -> bool *)
let for_alli p range =
  Cls.Fold.while_doi (fun s _ _ -> s) ~range ~init:true ~body:(fun _ -> p)

(* val existsi : ('i -> 'a -> bool) -> ('i * 'a) t -> bool *)
let existsi p range =
  Cls.Fold.do_whilei (fun s _ _ -> not s) ~range ~init:false ~body:(fun _ -> p)

(* val for_all2 : ('a -> 'b -> bool) -> 'a cls -> 'b cls -> bool *)
let for_all2 p r1 r2 =
  let range = Cls.combine r1 r2 in
  Cls.Fold.while_do (fun s _ -> s) ~range ~init:true ~body:(fun _ (x1,x2) -> p x1 x2)

(* val exists2  : ('a -> 'b -> bool) -> 'a cls -> 'b cls -> bool *)
let exists2 p r1 r2 =
  let range = Cls.combine r1 r2 in
  Cls.Fold.do_while (fun s _ -> not s) ~range ~init:false ~body:(fun _ (x1,x2) -> p x1 x2)

(* val for_all2i : ('i * 'j -> 'a * 'b -> bool) -> ('i * 'a) t -> ('j * 'b) t -> bool *)
let for_all2i p r1 r2 =
  let range = Cls.combinei r1 r2 in
  Cls.Fold.while_doi (fun s _ _ -> s) ~range ~init:true ~body:(fun _ -> p)

(* val exists2i  : ('i * 'j -> 'a * 'b -> bool) -> ('i * 'a) t -> ('j * 'b) t -> bool *)
let exists2i p r1 r2 =
  let range = Cls.combinei r1 r2 in
  Cls.Fold.do_whilei (fun s _ _ -> not s) ~range ~init:false ~body:(fun _ -> p)

(* --- *)
include Cls
(* --- *)

(* Some redefinitions (confortable API): *)

let to_array ?length =
  match length with None -> to_array | Some n -> to_array_with_length n

let to_arrayi ?length =
  match length with None -> to_arrayi | Some n -> to_array_with_lengthi n

let to_string ?length =
  match length with None -> to_string | Some n -> to_string_with_length n

let to_stringi ?length =
  match length with None -> to_stringi | Some n -> to_string_with_lengthi n

(* Defined mapping function in Rational: *)
module Float : sig
    type start = fraction  and stop = fraction  and  step = fraction
    (* --- *)
    val forward   : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> float t
    val forwardi  : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> (index * float) t
    (* --- *)
    val backward  : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> float t
    val backwardi : ?verbose:unit -> ?step:fraction -> start:fraction -> stop:fraction -> unit -> (index * float) t
    (* --- *)
    (* (step≥0) => "forward"  loop (broken when value ≥ stop) *)
    (* (step<0) => "backward" loop (broken when value ≤ stop) *)
    val make  : ?verbose:unit -> (start * stop * step) -> float t
    val makei : ?verbose:unit -> (start * stop * step) -> (index * float) t
end
= struct

  type start = fraction  and stop = fraction  and  step = fraction

  let fraction_to_float (a,b) =
    (float_of_int a) /. (float_of_int b)

  let fraction_to_floati i (a,b) =
    (i, (float_of_int a) /. (float_of_int b))

  let forwardi ?verbose ?step ~start ~stop () : (index * float) cls =
    Rational.forwardi ?verbose ?step ~start ~stop () |> (Cls.mapi fraction_to_floati)

  let backwardi ?verbose ?step ~start ~stop () : (index * float) cls =
    Rational.backwardi ?verbose ?step ~start ~stop () |> (Cls.mapi fraction_to_floati)

  let forward ?verbose ?step ~start ~stop () : float cls =
    Rational.forward ?verbose ?step ~start ~stop () |> (Cls.map fraction_to_float)

  let backward ?verbose ?step ~start ~stop () : float cls =
    Rational.backward ?verbose ?step ~start ~stop () |> (Cls.map fraction_to_float)

  let make ?verbose (start, stop, step) =
    Rational.make ?verbose (start, stop, step) |> (Cls.map fraction_to_float)

  let makei ?verbose (start, stop, step) =
    Rational.makei ?verbose (start, stop, step) |> (Cls.mapi fraction_to_floati)

  (* Examples:

      Range.Float.forward ~verbose:() ~start:(0,10) ~stop:(10,10) () |> Range.to_list ;;
      (* - : float list = [0.; 0.1; 0.2; 0.3; 0.4; 0.5; 0.6; 0.7; 0.8; 0.9] *)

      Range.Float.forward ~verbose:() ~start:(0,10) ~stop:(10,10) ~step:(2,10) () |> Range.to_list ;;
      (* - : float list = [0.; 0.2; 0.4; 0.6; 0.8] *)

      Range.Float.forward ~verbose:() ~start:(0,10) ~stop:(7,7) ~step:(4,20) () |> Range.to_list ;;
      (* - : float list = [0.; 0.2; 0.4; 0.6; 0.8] *)

      Range.Float.backward ~verbose:() ~start:(1,1) ~stop:(0,1) ~step:(-4,20) () |> Range.to_list ;;
      (* - : float list = [1.; 0.8; 0.6; 0.4; 0.2] *)

      (* Middle Riemann sum: *)
      let integral f ~start ~stop ~step () =
        let range = Range.Float.forward ~verbose:() ~start ~stop ~step () in
        let sum   = Range.fold ~range ~init:0. ~body:(fun s x -> s +. f x) in
        let start = Range.Fraction.to_float start in
        let stop  = Range.Fraction.to_float stop  in
        let step  = Range.Fraction.to_float step  in
        let result = (sum -. (f start)/.2. -. (f stop)/.2.) *. (step) in
        result ;;

      (* val integral : (float -> float) -> start:Range.fraction -> stop:Range.fraction -> step:Range.fraction -> unit -> float *)

      integral (sin) ~start:(0, 100) ~stop:(31416,10000) ~step:(1,100) ()  ;;
      (* - : float = 1.99999006504029753 (* should be 2. *) *)

      integral (sin) ~start:(Range.Fraction.of_int 0) ~stop:(Range.Fraction.of_float 3.14159265359) ~step:(1,1000) ()  ;;
      (* - : float = 1.99999995404099207 (* should be 2. *) *)

      integral (cos) ~start:(0, 100) ~stop:(31416, 10000) ~step:(1,100) ()  ;;
      (* - : float = 0.00159264598558394037 (* should be 0.00159265 *) *)

    *)

end (* Range.Float *)

(* Just a mapping of Int tools: *)
module Char = struct
    type start = char  and stop = char  and  step = int
    (* --- *)
    (* val make  : ?verbose:unit -> (start * stop * step) -> char t *)
    let make ?verbose (start, stop, step) =
      Int.make ?verbose (Char.code start, Char.code stop, step) |> Cls.map (Char.chr)

    (* val makei : ?verbose:unit -> (start * stop * step) -> (index * char) t *)
    let makei ?verbose (start, stop, step) =
      Int.makei ?verbose (Char.code start, Char.code stop, step) |> Cls.mapi (fun i y -> (i, Char.chr y))

    (* Examples:
       Range.Char.make ('m','a',-2) |> Range.to_list  ;;
       (* - : char list = ['m'; 'k'; 'i'; 'g'; 'e'; 'c'] *)
     *)

end (* Char *)
