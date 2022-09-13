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

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

(* Notation for type variables:

   - 's represents the type of "states"  (which are updated and returned by the loop)
   - 'i represents the type of "indexes" (often the natural numbers, but the domain may be more general)
   - 'a represents the type of "values"  (given each time with indexes to the body of loop, in order to update the state)
   - 'r represents the type of "ranges"  (i.e. the structures used to generate the sequence of values)

   Basic (b), unidirectional (u), and general (g) loops ('b','u','g' of course!).
   A "general" loop may be used as a "unidirectional" one, that may be used as a "basic" one.
   *)

type ('s,'i,'a) loop  = init:'s -> ('s,'i,'a) body -> 's
 and ('s,'i,'a) body  = ('s -> 'i -> 'a -> 's)
 and ('s,'i,'a) break = ('s -> 'i -> 'a -> bool)

type ('r,'s,'i,'a) r  = range:'r -> ('s,'i,'a) loop                  (* Simple interface, no options, just the range (r) *)
type ('r,'s,'i,'a) u  = ?break:('s,'i,'a) break -> ('r,'s,'i,'a) r   (* With option ?break, but unidirectional (u) *)
type ('r,'s,'i,'a) g  = ?backward:unit -> ('r,'s,'i,'a) u            (* General case (g), with options ?backward and ?break *)

(* A "range" is a triple (start, stop, step).
    The semantics of a range (a,b,s), where s<>0, is :
      - the set {a+ks | k∊ℕ, a+ks < b } if a<=b and s>0, or
      - the set {a+ks | k∊ℕ, a+ks > b } if a>b  and s<0.
    Note that the second limit (b) is not included in the set.
    ---
    The semantics of a char range (a,b) is slightly different because the right limit is
    included, i.e. the represented set is { chr(code(a)+k) | k∊ℕ, code(a)+k <= code(b) }.
    *)
type int_range   = ( start *  stop *  step)
 and float_range = (fstart * fstop * fstep)
 and char_range  = (cstart * cstop)
 and start       = int
 and stop        = int
 and step        = int
 and fstart      = float
 and fstop       = float
 and fstep       = float
 and cstart      = char
 and cstop       = char
 and index       = int

 (* ---------------------------------------
             Checking ranges
    --------------------------------------- *)

let check_int_range (a,b,s) : ('s, index, int) break =
  let forward_break  = fun s j x -> (x >= b) in
  let backward_break = fun s j x -> (x <= b) in
  (* --- *)
  let raise_error () =
    invalid_arg (Printf.sprintf "Loop: Ill-defined range (%d,%d,%d): the step cannot be zero. Use for_thunk() to create infinite loops" a b s)
  in
  if (s = 0) then raise_error () else (* continue: *)
  (* --- *)
  let result = (if (s<0) then backward_break else forward_break) in
  result

let check_float_range (a,b,s) : ('s, index, float) break =
  let raise_error () =
    invalid_arg (Printf.sprintf "Loop: Ill-defined range (%F,%F,%F): the step cannot be zero. Use for_thunk() to create infinite loops" a b s)
  in
  if (classify_float s = FP_zero) then raise_error () else (* continue: *)
  (* --- *)
  let precision =
    let abs_step = (abs_float s) in
    (mod_float (abs_float (b -. a)) abs_step) /. 2.
  in
  let forward_break  () = let b = b -. precision in fun s j x -> (x >= b) in
  let backward_break () = let b = b +. precision in fun s j x -> (x <= b) in
  (* --- *)
  let result = (if (s<0.) then backward_break () else forward_break ()) in
  result

let reverse_well_defined_int_range (a,b,s) =
  let abs_sign_of x : int * int = if x>=0 then (x,1) else (-x,-1) in
  let abs_s, sign_s = abs_sign_of s in
  let rest = ((abs (b-a)) mod abs_s) in
  let delta =
    match rest with
    | 0 -> sign_s * abs_s
    | _ -> sign_s * rest
  in
  let a' = b - delta in
  let b' = a - delta in
  let s' = -s in
  (a',b',s')

 (* --- *)

let reverse_well_defined_float_range (a,b,s) =
  let abs_sign_of x : float * float = if x>=0. then (x,1.) else (-.x,-.1.) in
  let abs_s, sign_s = abs_sign_of s in
  let rest = (mod_float (abs_float (b-.a)) abs_s) in
  let delta =
    match rest with
    | 0. -> sign_s *. abs_s
    | _  -> sign_s *. rest
  in
  let a' = b -. delta in
  let b' = a -. delta in
  let s' = -.s in
  (a',b',s')

 (* ---------------------------------------
             Basic loops

    --------------------------------------- *)

type unbounded_int_range = (start * step)

(* val while_do :
     range:(start * step) ->
     init:'s ->
     break:('s -> index -> int -> bool) ->
     ('s -> index -> int -> 's) -> 's *)
let while_do ?(range=(0,1)) ~init ~break : ('s -> index -> int -> 's) -> 's =
  let (start, step) = range in
  (* --- *)
  let sr = ref init in    (* state reference (s) *)
  let jr = ref 0 in       (* index reference (j) *)
  let xr = ref start in   (* value reference (x) *)
  (* --- *)
  begin fun body ->
    while not (break !sr !jr !xr) do
      let x = !xr in
      (sr := body !sr !jr x);
      (incr jr);
      (xr := x + step);
    done;
    !sr
  end

(* val do_while :
     ?range:(start * step) ->
     init:'s ->
     break:('s -> index -> int -> bool) ->
     ('s -> index -> int -> 's) -> 's *)
let do_while ?(range=(0,1)) ~init ~break : ('s -> index -> int -> 's) -> 's =
  let (start, step) = range in
  (* --- *)
  let sr = ref init in    (* state reference (s) *)
  let jr = ref 0 in       (* index reference (j) *)
  let xr = ref start in   (* value reference (x) *)
  (* --- *)
  begin fun body ->
    (sr := body init 0 start);
    (incr jr);
    (xr := start + step);
    while not (break !sr !jr !xr) do
      let x = !xr in
      (sr := body !sr !jr x);
      (incr jr);
      (xr := x + step);
    done;
    !sr
  end


(* val for_int_range :
     ?backward:unit ->
     ?break:('s -> index -> int -> bool) ->
     range:int_range -> init:'s ->
     ('s -> index -> int -> 's) -> 's *)
let for_int_range ?backward ?break ~range ~init : ('s -> index -> int -> 's) -> 's =
  let natural_break = check_int_range (range) in
  let (start, stop, step), natural_break =
    match backward with
    | None    -> range, natural_break
    | Some () ->
        let range' = reverse_well_defined_int_range (range) in
        let natural_break' = check_int_range (range') in
        let () = assert (range = reverse_well_defined_int_range (range')) in
        range', natural_break'
  in
  (* --- *)
  let break =
    match break with
    | None   -> natural_break
    | Some p -> fun s j x -> (natural_break s j x) || (p s j x)
  in
  (* --- *)
  let sr = ref init in    (* state reference (s) *)
  let jr = ref 0 in       (* index reference (j) *)
  let xr = ref start in   (* value reference (x) *)
  (* --- *)
  begin fun body ->
    while not (break !sr !jr !xr) do
      let x = !xr in
      (sr := body !sr !jr x);
      (incr jr);
      (xr := x + step);
    done;
    !sr
  end

(* val for_float_range :
     ?backward:unit ->
     ?break:('s -> index -> float -> bool) ->
     range:float_range -> init:'s ->
     ('s -> index -> float -> 's) -> 's *)
let for_float_range ?backward ?break ~range ~init : ('s -> index -> float -> 's) -> 's =
  let natural_break = check_float_range (range) in
  let (start, stop, step), natural_break =
    match backward with
    | None    -> range, natural_break
    | Some () ->
        let range' = reverse_well_defined_float_range (range) in
        let natural_break' = check_float_range (range') in
        let () = assert (range = reverse_well_defined_float_range (range')) in
        range', natural_break'
  in
  (* --- *)
  let break =
    match break with
    | None   -> natural_break
    | Some p -> fun s j x -> (natural_break s j x) || (p s j x)
  in
  (* --- *)
  let sr = ref init in    (* state reference (s) *)
  let jr = ref 0 in       (* index reference (j) *)
  let xr = ref start in   (* value reference (x) *)
  (* --- *)
  begin fun body ->
    while not (break !sr !jr !xr) do
      let x = !xr in
      (sr := body !sr !jr x);
      (incr jr);
      (xr := x +. step);
    done;
    !sr
  end

exception Terminated
(* val for_sequence : ?break:('s,'a) break -> range:(index -> 'a) -> init:'s -> ('s,'a) body -> 's *)
let for_sequence_without_break ~range ~init : ('s -> index -> 'a -> 's) -> 's =
  let range j = (try range j with _ -> raise Terminated) in
  (* --- *)
  let sr = ref init in    (* state reference (s) *)
  let jr = ref 0 in       (* index reference (j) *)
    (* --- *)
    begin fun body ->
      try
        let xr = ref (range 0) in (* value reference (x) *)
        while true do
          (sr := body !sr !jr !xr);
          (incr jr);
          (xr := range !jr);
        done;
        !sr
      with
      | Terminated -> !sr
      | e -> raise e
    end

let for_sequence_with_break ~break ~range ~init : ('s -> index -> 'a -> 's) -> 's =
  (* --- *)
  let range j = (try range j with _ -> raise Terminated) in
  (* --- *)
  let sr = ref init in    (* state reference (s) *)
  let jr = ref 0 in       (* index reference (j) *)
    (* --- *)
    begin fun body ->
      try
        let xr = ref (range 0) in (* value reference (x) *)
        while not (break !sr !jr !xr) do
          (sr := body !sr !jr !xr);
          (incr jr);
          (xr := range !jr);
        done;
        !sr
      with
      | Terminated -> !sr
      | e -> raise e
    end

  (* --- *)

(* val for_sequence : ?break:('s,'a) break -> range:(index -> 'a) -> init:'s -> ('s,'a) body -> 's *)
let for_sequence ?break =
  match break with
  | None       -> for_sequence_without_break
  | Some break -> for_sequence_with_break ~break

(* val for_thunk : ?break:('s,'a) break -> range:(unit  -> 'a) -> init:'s -> ('s,'a) body -> 's *)
let for_thunk ?break ~range = for_sequence ?break ~range:(fun _ -> range ())

(* -------------------------------------- *)
(*        Functors and bifunctors         *)
(* -------------------------------------- *)

type ('s,'a,'ta) fold1 = ('s -> 'a -> 's) -> 's -> 'ta -> 's
type ('s,'a,'b,'tab) fold2 = ('s -> 'a -> 'b -> 's) -> 's -> 'tab -> 's

let unidir_of_functor_without_break (fold : ('s * int,'a,'ta) fold1) ~(range: 'ta) ~(init:'s) : ('s -> index -> 'a -> 's) -> 's =
  fun (body : ('s,index,'a) body)  ->
    fst (fold (fun (s,i) x -> (body s i x, (i+1))) (init,0) range)

let unidir_of_functor_with_break (fold : ('s * int,'a,'ta) fold1) ~break ~(range: 'ta) ~(init:'s) : ('s -> index -> 'a -> 's) -> 's =
  let sr = ref init in    (* state reference (sr) *)
  let foldi f =
    fold
      (fun (s,i) x ->
         if break s i x then raise Terminated else (* continue: *)
         let s' = f s i x in
         let () = (sr := s') in
         (s', (i+1))
         )
  in
  fun body ->
    try
      fst (foldi (body) (init,0) (range))
    with
    | Terminated -> !sr
    | e -> raise e

(* val unidir_of_functor   : ('s * index, 'a, 'ta) fold1 -> ('ta,  's, index, 'a) u *)
let unidir_of_functor (fold) ?break =
  match break with
  | None       -> unidir_of_functor_without_break (fold)
  | Some break -> unidir_of_functor_with_break (fold) ~break

(* --- *)
let unidir_of_bifunctor_without_break (fold : ('s * int,'a,'b,'ta) fold2) ~(range: 'ta) ~(init:'s) : ('s -> index -> 'a * 'b -> 's) -> 's =
  fun (body : ('s, index, ('a * 'b)) body)  ->
    fst (fold (fun (s,i) x y -> ((body s i (x,y)), (i+1))) (init,0) range)

let unidir_of_bifunctor_with_break (fold : ('s * int,'a,'b,'ta) fold2) ~break ~(range: 'ta) ~(init:'s) : ('s -> index -> 'a * 'b -> 's) -> 's =
  let sr = ref init in    (* state reference (sr) *)
  let foldi f =
    fold
      (fun (s,i) x y ->
         if break s i (x,y) then raise Terminated else (* continue: *)
         let s' = f s i (x,y) in
         let () = (sr := s') in
         (s', (i+1))
         )
  in
  fun body ->
    try
      fst (foldi (body) (init,0) (range))
    with
    | Terminated -> !sr
    | e -> raise e

(* val unidir_of_functor   : ('s * index, 'a, 'ta) fold1 -> ('ta,  's, index, 'a) u *)
let unidir_of_bifunctor (fold) ?break =
  match break with
  | None       -> unidir_of_bifunctor_without_break (fold)
  | Some break -> unidir_of_bifunctor_with_break (fold) ~break

(* Example of functor's fold conversion:
   val for_queue : ('a Queue.t, 's, int, 'a) u *)
let for_queue ?break = unidir_of_functor (Queue.fold) ?break ;;

(* Example of functor's fold conversion (requires OCaml >= 4.03):
   val for_stack : ('a Queue.t, 's, int, 'a) u *)
IFDEF OCAML4_03_OR_LATER THEN
let for_stack ?break = unidir_of_functor (Stack.fold) ?break ;;
ENDIF

(* Example of functor's fold conversion (requires OCaml >= 4.07):
   val for_seq : ('a Seq.t, 's, int, 'a) u *)
IFDEF OCAML4_07_OR_LATER THEN
let for_seq ?break = unidir_of_functor (Seq.fold_left) ?break ;;
ENDIF

(* Example of bifunctor's fold conversion:
   val for_hashtbl : (('k, 'a) Hashtbl.t, 's, int, 'k * 'a) u *)
let for_hashtbl ?break = unidir_of_bifunctor (fun f s t -> Hashtbl.fold (fun x y s -> f s x y) t s) ?break ;;

module Make_for_map (M : Map.S) = struct
   let for_map ?break = unidir_of_bifunctor (fun f s t -> M.fold (fun x y s -> f s x y) t s) ?break ;;
end

(* END of section functors and bifunctors *)
(* -------------------------------------- *)

let for_array ?backward ?break ~range ~init : ('s -> index -> 'a -> 's) -> 's =
  let xs = range in
  let start, step, natural_break =
    let n = Array.length xs in
    match backward with
    | None    -> (    0,  1, (fun s i -> (i >= n)))
    | Some () -> ((n-1), -1, (fun s i -> (i < 0)))
  in
  (* --- *)
  let break =
    match break with
    | None   -> natural_break
    | Some p -> (fun s i -> (natural_break s i) || (p s i xs.(i)))
  in
  (* --- *)
  let sr = ref init in    (* state reference (s) *)
  let ir = ref start in   (* array index reference (i) *)
  (* --- *)
  begin fun body ->
    while not (break !sr !ir) do
      let i = !ir in
      (sr := body !sr i xs.(i));
      (ir := i + step);
    done;
    !sr
  end

(* val for_list_forward : ?break:('a -> index -> 'b -> bool) -> range:'b list -> init:'a -> ('a -> index -> 'b -> 'a) -> 'a *)
let for_list_forward =
  (* val list_fold_lefti : ('a -> index -> 'b -> 'a) -> 'a -> 'b list -> 'a *)
  let list_fold_lefti f =
    let rec loop i s =
      function
      | [] -> s
      | x::xs -> loop (i+1) (f s i x) xs
    in
    loop 0
  in
  (* With a break condition:
     val list_fold_leftib : ('a -> index -> 'b -> bool) -> ('a -> index -> 'b -> 'a) -> 'a -> 'b list -> 'a *)
  let list_fold_leftib b f =
    let rec loop i s =
      function
      | [] -> s
      | x::xs -> if (b s i x) then s else loop (i+1) (f s i x) xs
    in
    loop 0
  in
  (* --- *)
  fun ?break ~range ~init body ->
    match break with
    | None       -> list_fold_lefti body init range
    | Some break -> list_fold_leftib (fun s i x -> not (break s i x)) body init range


(* val for_list :
     ?backward:unit ->
     ?break:('a -> index -> 'b -> bool) ->
     range:'b list -> init:'a -> ('a -> index -> 'b -> 'a) -> 'a *)
let for_list ?backward =
  match backward with
  | None    -> for_list_forward
  | Some () ->
      (* Use `for_list_forward' to reverse the list (in order to stress the heap, not the stack): *)
      let list_rev xs     = for_list_forward ~range:xs ~init:[] (fun s i x -> x::s) in
      let list_rev_len xs = for_list_forward ~range:xs ~init:([],0) (fun (l,k) i x -> (x::l, k+1)) in
      (* --- *)
      fun ?break ~range ~init body ->
        match break with
        | None ->
            (* Just reverse the list: *)
            let range = list_rev range in
            for_list_forward ~range ~init body
        (* --- *)
        | Some break ->
            (* Reverse the list to run backward, ok, but leave `break' to refer indexes as if the list wasn't reversed: *)
            let range, n = list_rev_len range in
            let last_index = n - 1 in
            let break s i x = break s (last_index - i) x in
            for_list_forward ~break ~range ~init body

module Make_loop_of_indexed_structure
  (M : sig
         type t
         type elt
         val length : t -> int
         val get : t -> index -> elt
       end)
  =
  struct

   (* val for_elt_in_t :
        ?backward:unit -> ?break:('s -> index -> M.elt -> bool) ->
        range:M.t -> init:'s -> ('s -> index -> M.elt -> 's) -> 's  *)
    let for_elt_in_t ?backward ?break ~range ~init : ('s -> index -> M.elt -> 's) -> 's =
      let xs = range in
      let get = M.get xs in
      let break =
        match break with
        | None       -> None
        | Some break -> Some (fun s j i -> break s i (get i))
      in
      (* --- *)
      let range =
        let n = M.length xs in
        match backward with
        | None    -> (0, n, 1)
        | Some () -> ((n-1), -1, -1)
      in
      (* --- *)
      let loop = for_int_range ?backward ?break ~range ~init in
      (* --- *)
      fun body ->
        let body s j i = body s i (get i) in
        loop body

  end (* functor Make_loop_of_indexed_structure *)

module String_loop = Make_loop_of_indexed_structure (struct  type t = string  type elt = char  let length=String.length  let get=String.get  end)
let for_string = String_loop.for_elt_in_t
(* --- *)
module Char_range_loop = Make_loop_of_indexed_structure (struct
    type t = char_range * (unit option)
    type elt = char
    let length ((c1,c2),_) = max 0 (1 + ((Char.code c2) - (Char.code c1)))
    let get ((c1,c2), backward) =
      match backward with
      | None ->
         let offset = (Char.code c1) in
         fun i -> Char.chr (offset + i)
      | Some () ->
         let offset = (Char.code c2) in
         fun i -> Char.chr (offset - i)
  end)
(* val for_char_range  : ?backward:unit -> ?break:('s,char)  break -> range:char_range  -> init:'s -> ('s,char)  body -> 's *)
let for_char_range ?backward ?break ~range =
  Char_range_loop.for_elt_in_t ?backward:None ?break ~range:(range,backward)

(* Note: the function `for_array' could be defined in this way. *)

 (* ---------------------------------------
             Nested loops
    --------------------------------------- *)
module Implementation = struct

  (* A domain is just a triple where the two first components ('backward and 'break) are optional. *)
  (* type ('backward,'break,'range) domain = ('backward option) * ('break option) * 'range *)
  type ('w,'b,'r) domain = ('w option) * ('b option) * 'r

  (* General form of a loop: *)
  (* type ('backward, 'break, 'range, 'state, 'index, 'items) t = ('backward, 'break, 'range) domain -> ('state, 'index, 'items) loop *)
  type ('w, 'b, 'r, 's, 'i, 'a) t = ('w, 'b, 'r) domain -> ('s, 'i, 'a) loop

  (* Simplified version: *)
  type ('r,'s,'i,'a) s = (unit, ('s, 'i, 'a) break, 'r) domain -> ('s, 'i, 'a) loop

  (* Directives for the depth-most level ('d) and for all intermediary levels ('l): *)
  type ('d,'l) nested_options = ('d option) * ('l option array) option

  type ('w,'b,'r,'s,'i,'a) nested_t =
    (('w,'w) nested_options, (('s, 'i array, 'a array) break, 'b) nested_options, 'r, 's, 'i array, 'a array) t

  (* --- *)

  (* The result will ignore both options `backward' and `break':
     val of_ranger  : ('r,'s,'i,'a) r -> ('r,'s,'i,'a) s *)
  let s_of_ranger (loop) = fun (_backward, _break, range) -> loop ~range

  (* The result will ignore the option `backward':
     val of_unidir  : ('r,'s,'i,'a) u -> ('r,'s,'i,'a) s *)
  let s_of_unidir (loop)  = fun (_backward, break, range) -> loop ?break ~range

  (* The representation are equivalent (of course, `t' being just the uncurrying of `g'):
     val of_general : ('r,'s,'i,'a) g -> ('r,'s,'i,'a) s *)
  let s_of_general (loop) = fun (backward, break, range) -> loop ?backward ?break ~range

  (* val to_general : ('r,'s,'i,'a) s -> ('r,'s,'i,'a) g *)
  let s_to_general (loop) = fun ?backward ?break ~range -> loop (backward, break, range)

  (* val to_unidir : ('r,'s,'i,'a) s -> ('r,'s,'i,'a) u *)
  let s_to_unidir (loop) = fun ?break ~range -> loop (None, break, range)

  (* val to_ranger : ('r,'s,'i,'a) s -> ('r,'s,'i,'a) r *)
  let s_to_ranger (loop) = fun ~range -> loop (None, None, range)

(* Auxiliary tool: applied to the global parameter ?backward, allows to interpret the local ones. *)
let backward_switch (global_backward) =
  match global_backward with
  | None   -> (function b -> b)                          (* leave the local backward as is *)
  | Some w -> (function None -> Some w | Some _ -> None) (* negate the local backward *)

(* Note that here the type 'range is a cartesian product: the first component is the range strictly speaking,
   and the second is a possible break condition for the inner loop. This version is "without break" in the
   sense of there is not a global break conditon. *)
let nest_without_global_break (provided_loop) ?backward ~levels ~(domains : int -> 'backward * 'break * 'range) ~init body =
  if levels = 0 then init else (* continue: *)
  (* --- *)
  let n = levels in (* just a convenient alias *)
  let last_depth = n - 1 in
  let switch = backward_switch (backward) in
  (* --- *)
  let rec loop depth (* > 0 *) ~init js xs =
    if (depth > last_depth) then
      let js = (Array.copy js) in
      let xs = (Array.copy xs) in
      body init js xs
    else
    (* --- *)
      (* Local domain at this depth: *)
      let backward, break, range = (domains depth) in
      provided_loop ?backward:(switch backward) ?break ~range ~init (fun s j x ->
        let () = js.(depth) <- j in
        let () = xs.(depth) <- x in
        loop (depth+1) ~init:s js xs
        )
    (* --- *)
  in
  let loop_first_level () =
      let backward, break, range = (domains 0) in
      provided_loop ?backward:(switch backward) ?break ~range ~init (fun s j x ->
         loop 1 ~init:s (Array.make n j) (Array.make n x)
        )
    (* --- *)
  in loop_first_level ()

exception Break
(* --- *)
let nest_with_global_break (provided_loop) ?backward ~break ~levels ~(domains : int -> 'backward * 'break * 'range) ~init body =
  if levels = 0 then init else (* continue: *)
  (* --- *)
  let n = levels in (* just a convenient alias *)
  let last_depth = n - 1 in
  let switch = backward_switch (backward) in
  let backup = ref None in
  (* --- *)
  let rec loop depth (* > 0 *) ~init js xs =
    if (depth > last_depth) then
      let js = (Array.copy js) in
      let xs = (Array.copy xs) in
      (* The difference with `nest_without_global_break' is just the following line: *)
      if break init js xs then
        let () = backup := Some init in
        raise Break
      else (* continue: *)
      (* --- *)
      body init js xs
    else
    (* --- *)
      (* Local domain at this depth: *)
      let backward, break, range = (domains depth) in
      provided_loop ?backward:(switch backward) ?break ~range ~init (fun s j x ->
        let () = js.(depth) <- j in
        let () = xs.(depth) <- x in
        loop (depth+1) ~init:s js xs
        )
    (* --- *)
  in
  let loop_first_level () =
      let backward, break, range = (domains 0) in
      provided_loop ?backward:(switch backward) ?break ~range ~init (fun s j x ->
         loop 1 ~init:s (Array.make n j) (Array.make n x)
        )
    (* --- *)
  in begin
  try
    loop_first_level ()
  with
    | Break -> (match !backup with None -> assert false | Some s -> s)
    | e -> raise e
  end

(* This function merges the two previous ones (with or without ?break).
   It takes a general loop (g) and returns something similar to an abstract one (t).
   ---
   Rewriting types:
   ----
   val nest :
         depth:int ->
     (* -------------------------------------------------------------------------------------------- INPUT: *)

        (?backward:'w -> ?break:'b -> range:'r -> init:'s -> ('s -> 'i -> 'a -> 's) -> 's) ->

     (* -------------------------------------------------------------------------------------------- OUTPUT: *)

        ?backward:('w option * 'w option array option) ->                           (* global and local backward option *)
        ?break:('s, 'i array, 'a array) break option * 'b option array option ->    (* global and local break option *)
        domains:(int -> (backward option) * (('s,'i,'a) break option) * 'r) ->      (* argument is in [0..(depth-1)] *)
        init:'s ->
        ('s -> 'i array -> 'a array -> 's) -> 's
     (* --- *)
  *)
let nest ~depth (provided_loop) ?backward ?break =
  match break with
  | None       -> nest_without_global_break (provided_loop)        ?backward ~levels:(depth)
  | Some break -> nest_with_global_break    (provided_loop) ~break ?backward ~levels:(depth)

let option_extract_pair = function
| None       -> (None, None)
| Some (x,y) -> (x,y)

(* val nest_t_sequence : depth:int -> ('w,'b,'r,'s,'i,'a) t -> ('w,'b, int->'r ,'s,'i,'a) nested_t *)
let nest_t_sequence
  ~depth
  (provided_loop)
  (domain: ('w option * 'w option array option, ('s, 'i array, 'a array) break option * 'b option array option, int -> 'r) domain)
  =
  let provided_loop ?backward ?break ~range = provided_loop (backward, break, range) in
  let (backward_ws), (break_bs), rs = domain in
  let backward, ws = option_extract_pair (backward_ws) in
  let break,    bs = option_extract_pair (break_bs) in
  let ws = (match ws with None -> Array.make depth None | Some ws -> let () = assert ((Array.length ws) = depth) in ws) in
  let bs = (match bs with None -> Array.make depth None | Some bs -> let () = assert ((Array.length bs) = depth) in bs) in
  let domains (i) = (ws.(i), bs.(i), rs i) in
  nest ~depth (provided_loop) ?backward ?break ~domains

(* val nest_t_array : ('w,'b,'r,'s,'i,'a) t -> ('w,'b, 'r array,'s,'i,'a) nested_t *)
let nest_t_array (provided_loop) = function
  | (backward, break, rs) ->
       let depth = Array.length rs in
       let r i = rs.(i) in
       nest_t_sequence ~depth (provided_loop) (backward, break, r)

(* val nest_t_list : ('w,'b,'r,'s,'i,'a) t -> ('w,'b, 'r list ,'s,'i,'a) nested_t *)
let nest_t_list (provided_loop) = function
  | (backward, break, r) -> nest_t_array (provided_loop) (backward, break, Array.of_list r)

(* val nest_t_power : depth:int -> ('w,'b,'r,'s,'i,'a) t -> ('w,'b, 'r ,'s,'i,'a) nested_t *)
let nest_t_power ~depth (provided_loop) = function
  | (backward, break, r) -> nest_t_sequence ~depth (provided_loop) (backward, break, (fun _ -> r))

(* Simplified versions: *)

(* val nest_sequence : depth:int -> ('r,'s,'i,'a) s -> (int->'r, 's, 'i array, 'a array) s *)
let nest_s_sequence ~depth (provided_loop : ('r,'s,'i,'a) s) : (int -> 'r, 's, 'i array, 'a array) s =
  fun (domain: (unit, ('s, 'i array, 'a array) break, int -> 'r) domain) ->
    let provided_loop ?backward ?break ~range = provided_loop (backward, break, range) in
    let backward, break, r = domain in
    let domains (i) = (None, None, r i) in (* on renonce au contrôle imbriqué *)
    nest ~depth (provided_loop) ?backward ?break ~domains

(* val nest_s_array : ('r,'s,'i,'a) s -> ('r array,'s, 'i array, 'a array) s *)
let nest_s_array (provided_loop) = function
  | (backward, break, rs) ->
       let depth = Array.length rs in
       let r i = rs.(i) in
       nest_s_sequence ~depth (provided_loop) (backward, break, r)

(* val nest_s_list : ('r,'s,'i,'a) s -> ('r list, 's, 'i array, 'a array) s *)
let nest_s_list (provided_loop : ('r,'s,'i,'a) s) : ('r list, 's, 'i array, 'a array) s =
  fun (domain: (unit, ('s, 'i array, 'a array) break, 'r list) domain) ->
    let (backward, break, rs) = domain in
    nest_s_array (provided_loop) (backward, break, Array.of_list rs)

(* val nest_s_power : depth:int -> ('r,'s,'i,'a) s -> ('r, 's, 'i array, 'a array) s *)
let nest_s_power ~depth (provided_loop : ('r,'s,'i,'a) s) : ('r, 's, 'i array, 'a array) s =
  fun (domain: (unit, ('s, 'i array, 'a array) break, 'r) domain) ->
    let (backward, break, r) = domain in
    nest_s_sequence ~depth (provided_loop) (backward, break, (fun _ -> r))

end (* Implementation *)

(* A convenient alias: *)
module Impl = Implementation

module Nest_s_array = struct

  let nest_g (provided_loop: ('r,'s,'i,'a) g) : ('r array, 's, 'i array, 'a array) g =
    Impl.s_to_general (Impl.nest_s_array (Impl.s_of_general provided_loop))

  let nest_u (provided_loop: ('r,'s,'i,'a) u) : ('r array, 's, 'i array, 'a array) u =
    Impl.s_to_unidir (Impl.nest_s_array (Impl.s_of_unidir provided_loop))

  let nest_r (provided_loop: ('r,'s,'i,'a) r) : ('r array, 's, 'i array, 'a array) u =
    Impl.s_to_unidir (Impl.nest_s_array (Impl.s_of_ranger provided_loop))

  (* ---  Nested_array.nest_g applied to traditional general loops:  --- *)

  let for_int_ranges   ?backward = nest_g (for_int_range) ?backward
  let for_float_ranges ?backward = nest_g (for_float_range) ?backward
  let for_char_ranges  ?backward = nest_g (for_char_range) ?backward
  let for_arrays       ?backward = nest_g (for_array) ?backward
  let for_lists        ?backward = nest_g (for_list) ?backward
  let for_strings      ?backward = nest_g (for_string) ?backward

end

module Nest_s_list = struct

  let nest_g (provided_loop: ('r,'s,'i,'a) g) : ('r list, 's, 'i array, 'a array) g =
    Impl.s_to_general (Impl.nest_s_list (Impl.s_of_general provided_loop))

  let nest_u (provided_loop: ('r,'s,'i,'a) u) : ('r list, 's, 'i array, 'a array) u =
    Impl.s_to_unidir (Impl.nest_s_list (Impl.s_of_unidir provided_loop))

  let nest_r (provided_loop: ('r,'s,'i,'a) r) : ('r list, 's, 'i array, 'a array) u =
    Impl.s_to_unidir (Impl.nest_s_list (Impl.s_of_ranger provided_loop))

  (* ---  Nested_array.nest_g applied to traditional general loops:  --- *)

  let for_int_ranges   ?backward = nest_g (for_int_range) ?backward
  let for_float_ranges ?backward = nest_g (for_float_range) ?backward
  let for_char_ranges  ?backward = nest_g (for_char_range) ?backward
  let for_arrays       ?backward = nest_g (for_array) ?backward
  let for_lists        ?backward = nest_g (for_list) ?backward
  let for_strings      ?backward = nest_g (for_string) ?backward

end

module Nest_s_depth = struct

  let nest_g ~depth (provided_loop: ('r,'s,'i,'a) g) : ('r, 's, 'i array, 'a array) g =
    Impl.s_to_general (Impl.nest_s_power ~depth (Impl.s_of_general provided_loop))

  let nest_u ~depth (provided_loop: ('r,'s,'i,'a) u) : ('r, 's, 'i array, 'a array) u =
    Impl.s_to_unidir (Impl.nest_s_power ~depth (Impl.s_of_unidir provided_loop))

  let nest_r ~depth (provided_loop: ('r,'s,'i,'a) r) : ('r, 's, 'i array, 'a array) u =
    Impl.s_to_unidir (Impl.nest_s_power ~depth (Impl.s_of_ranger provided_loop))

  (* ---  Nested_array.nest_g applied to traditional general loops:  --- *)

  let for_int_ranges   ~depth = nest_g ~depth (for_int_range)
  let for_float_ranges ~depth = nest_g ~depth (for_float_range)
  let for_char_ranges  ~depth = nest_g ~depth (for_char_range)
  let for_arrays       ~depth = nest_g ~depth (for_array)
  let for_lists        ~depth = nest_g ~depth (for_list)
  let for_strings      ~depth = nest_g ~depth (for_string)

end

module Array = struct

  (* Alias: *)
  let fold = for_array

  (* Just a flipped version of Array.mapi: *)
  let map ~range (f: index -> 'a -> 'b) =
    Array.mapi f range

  (* Just a flipped version of Array.iteri: *)
  let iter ~range (f: index -> 'a -> unit) =
    Array.iteri f range

  let map_folding ~range ~init (f:'s -> index -> 'a -> 'b * 's) =
    let xs = range in
    let n = Array.length xs in
    if n = 0 then [||] else begin
      let (y0, s1) = f init 0 (xs.(0)) in
      let result = Array.make n y0 in
      let state = ref s1 in
      for i = 1 to n-1 do
        let (y,z) = f (!state) i (xs.(i)) in
        result.(i) <- y ;
        state := z;
      done;
      result
    end

  let iter_folding ~range ~init (f:'s -> index -> 'a -> 's) =
    let xs = range in
    let n = Array.length xs in
    if n = 0 then () else begin
      let state = ref init in
      for i = 0 to n-1 do
        state :=  f (!state) i (xs.(i))
      done;
    end

  (* val init_folding : range:int -> init:'s -> ('s -> index -> 'a * 's) -> 'a array *)
  let init_folding ~range ~init (f:'s -> index -> 'a * 's) =
    let n = range in
    if n = 0 then [||] else begin
      let (y0, s1) = f init 0 in
      let result = Array.make n y0 in
      let state = ref s1 in
      for i = 1 to n-1 do
        let (y,z) = f (!state) i in
        result.(i) <- y ;
        state := z;
      done;
      result
    end

  module The_poor_man_combinatorics = struct

    (* Unused: *)
    let factorial x =
      for_int_range ~range:(2,x+1,1) ~init:1 (fun s j x -> s*x)

    (* x! / y! with x>=y *)
    let factorial_ratio x y =
      for_int_range ~range:(y+1,x+1,1) ~init:1 (fun s j x -> s*x)

    (* Ex: int_power 2 10 = 1024 *)
    let int_power =
      let rec pow a x n =
        if n = 0 then a else pow (a * (if n mod 2 = 0 then 1 else x)) (x * x) (n / 2) in
      pow 1

    (* "Disposizioni" *)
    let ordered_selections ?repetitions (n,k) =
      let () = assert (k>=0) in
      match repetitions with
      | None ->
          if (k>n) then 0 else
          factorial_ratio n (n-k)
      | Some () ->
          int_power n k

    let binomial (n,k) =
      let m = min k (n-k) in
      if m < 0 then 0 else
      let rec loop j v =
          if j = m then v
          else loop (j+1) ((v * (n - j)) / (j+1))
      in loop 0 1

    let selections_counter ?unordered ?repetitions (n, k) =
      if k=0 then 0 else (* continue: *)
      (* --- *)
      match unordered, repetitions with
      (* The order is relevant, elements cannot be duplicated: *)
      | None, None -> ordered_selections (n,k)
      (* --- *)
      (* The order is relevant, elements can be duplicated: *)
      | None, Some () -> ordered_selections ~repetitions:() (n,k)
      (* --- *)
      (* The order is irrelevant, elements cannot be duplicated: *)
      | Some (), None -> binomial (n,k)
          (* --- *)
      (* --- *)
      (* The order is irrelevant, elements can be duplicated: *)
      | Some (), Some () -> let n' = (n + k - 1) in binomial (n',k)

  end (* Array.The_poor_man_combinatorics *)

  (* To check if a configuration has been already selected (in a different order): *)
  module Multiset_set = Set.Make (struct type t = int array let compare = compare end)

  type k = int

  (* val selections :
      ?verbose:unit ->
      ?unordered:unit ->
      ?repetitions:unit ->
      ?backward:unit ->
      ?break:('s, index array, 'a array) Loop.break ->
      range:'a array * k -> ('s, index array, 'a array) Loop.loop *)
  let selections ?verbose ?unordered ?repetitions ?backward ?break ~range =
    let (domain, k) : ('a array) * int = range in
    let () = if k < 0 then invalid_arg "Loop.Array.selections: negative number places (k)" in
    let n = Array.length domain in
    (* --- *)
    let () = if (verbose = Some ()) then
          Printf.kfprintf flush stderr
            "Loop.Array.selections: the expected number of loops is %d\n"
            (The_poor_man_combinatorics.selections_counter ?unordered ?repetitions (n,k))
    in
    (* Should be performed at all intermediary levels, not only at the last one.
       To do this optimization, we need a tool like Nest_t_array.for_arrays but
       equipped with a "skip" (or "continue") option similar to the generalized
      "break" condition (that may act at intermediary levels). *)
    let check_index_unicity js : bool =
      let m = Array.make n 0 in
      try
        let () =
          Array.iter (fun j -> if m.(j) > 0 then raise Stack_overflow else m.(j) <- 1) js
        in
        true
      with Stack_overflow -> false
    in
    (* --- *)
    (* Example (n=3): make_multiset_of_indexes [| 0; 0; 1; 2; 2; 0; 0 |] = [|4; 1; 2|] ;; *)
    let make_multiset_of_indexes js : int array =
      let m = Array.make n 0 in
      let () = Array.iter (fun j -> m.(j) <- m.(j) + 1) js
      in m
    in
    (* --- *)
    match unordered, repetitions with
    (* The order is relevant, elements cannot be duplicated: *)
    | None, None ->
        fun ~init body ->
          let nested_ranges = Array.make k domain in
          Nest_s_array.for_arrays ?backward ?break ~range:(nested_ranges) ~init (fun s js xs ->
            (* We are forced to check the unicity of the configuration at the last level :( *)
            if not (check_index_unicity js) then s (* skip this iteration *)  else (* continue: *)
            body s js xs)
    (* --- *)
    (* The order is relevant, elements can be duplicated: *)
    | None, Some () ->
        fun ~init body ->
          let nested_ranges = Array.make k domain in
          Nest_s_array.for_arrays ?backward ?break ~range:(nested_ranges) ~init body
    (* --- *)
    (* The order is irrelevant, elements cannot be duplicated: *)
    | Some (), None ->
        (* --- *)
        fun ~init body ->
          let ms0 = Multiset_set.empty in
          let s0 : 's = init in
          let break = Option.map (fun f (ms, s) js xs -> f s js xs) break in
          (* --- *)
          let nested_ranges = Array.init k (fun i -> Array.sub domain i (n-i)) in
          let index_array_mapping = (Array.mapi (fun i j -> j+i)) in
          (* --- *)
          let _ms1, s1 =
            Nest_s_array.for_arrays ?backward ?break ~range:(nested_ranges) ~init:(ms0, s0) (fun (ms, s) js xs ->
              let js' = index_array_mapping js in
              (* We are forced to check the unicity of the configuration at the last level :( *)
              if not (check_index_unicity js') then (ms, s) (* skip this iteration *)  else (* continue: *)
              (* --- *)
              let m = make_multiset_of_indexes js' in
              (* We check the membership of the configuration (multiset) at the last level: *)
              if (Multiset_set.mem m ms) then (ms, s) (* skip this iteration *)  else (* continue: *)
              (* --- *)
              let ms1 = Multiset_set.add m ms in
              let s1 = body s js' xs in
              (ms1, s1))
          in s1
    (* --- *)
    (* The order is irrelevant, elements can be duplicated: *)
    | Some (), Some () ->
        fun ~init body ->
          let ms0 = Multiset_set.empty in
          let s0 : 's = init in
          let break = Option.map (fun f (ms, s) js xs -> f s js xs) break in
          let nested_ranges = Array.make k domain in
          let _ms1, s1 =
            Nest_s_array.for_arrays ?backward ?break ~range:(nested_ranges) ~init:(ms0, s0) (fun (ms, s) js xs ->
              let m = make_multiset_of_indexes js in
              (* We check the membership of the configuration (multiset) at the last level: *)
              if (Multiset_set.mem m ms) then (ms, s) (* skip this iteration *)  else (* continue: *)
              (* --- *)
              let ms1 = Multiset_set.add m ms in
              let s1 = body s js xs in
              (ms1, s1))
          in s1

end

module List = struct

  (* Alias: *)
  let fold = for_list

  (* Just a flipped version of Array.mapi: *)
  let map ~range (f: index -> 'a -> 'b) =
  List.mapi f range

  (* Just a flipped version of Array.iteri: *)
  let iter ~range (f: index -> 'a -> unit) =
    List.iteri f range

  let map_folding ~range ~init (f:'s -> index -> 'a -> 'b * 's) =
    let rec loop s i = function
    | []    -> []
    | x::xs -> let (y,s') = f s i x in (y::(loop s' (i+1) xs))
    in loop (init) 0 (range)

  let iter_folding ~range ~init (f:'s -> index -> 'a -> 's) =
    let rec loop s i = function
    | []    -> ()
    | x::xs -> let s' = f s i x in (loop s' (i+1) xs)
    in loop (init) 0 (range)

  let init_folding ~range ~init (f:'s -> index -> 'a * 's) =
    let () = if range < 0 then invalid_arg "Loop.Array.init_folding" in
    (* --- *)
    let rec loop s i =
      if i = range then [] else
      let (y,s') = f s i in (y::(loop s' (i+1)))
    in loop (init) 0

end
