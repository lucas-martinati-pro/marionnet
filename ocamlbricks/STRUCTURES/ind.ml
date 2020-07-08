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

(* ------------------------------------------------------------------------- *)
(*                             Internal types                                *)
(* ------------------------------------------------------------------------- *)

type index = int

(* The simplest case is a bijection when 'k = int and the functions are both the identity over indexes: *)
type 'k indexing =
  | Bijection of ('k -> index) * (index -> 'k)      (* (k2i, i2k) : 'k <-> {0,..,n-1} *)
  | Keys      of ('k, index) Hashtbl.t * ('k array) (* (k2i, i2k) : 'k <-> {0,..,n-1} *)

(* In the simplest case (keys = Bijection(id,id)) the structure is a "tensor" (at this level) *)
type ('k,'a) t = {
  (* --- *)
  keys   : 'k indexing;
  elts   : 'a array;
  (* --- *)
  (* Element's permutation: *)
  perm   : Permutation.t option;
  (* --- *)
  (* Useful only for ungrouping, when 'a is itself of type ('h,'b) t *)
  ungrouping : (Permutation.t array) list;
}

(*
type (_,_) nested =
| Base   : ('k,'a) t -> ('k,'a) nested
| Nested : ('k1, ('k2,'a) nested) t -> ('k1, 'k2 * 'a) nested
*)

type ('k1,'k2,'a) tt = ('k1, ('k2, 'a) t) t
type ('k1,'k2,'k3,'a) ttt = ('k1, ('k2,'k3,'a) tt) t
(* --- *)
type ('k1,'a) t1 = ('k1, 'a) t
type ('k1,'k2,'a) t2 = ('k1, ('k2, 'a) t) t
type ('k1,'k2,'k3,'a) t3 = ('k1, ('k2,'k3,'a) t2) t
type ('k1,'k2,'k3,'k4,'a) t4 = ('k1, ('k2,'k3,'k4,'a) t3) t
type ('k1,'k2,'k3,'k4,'k5,'a) t5 = ('k1, ('k2,'k3,'k4,'k5,'a) t4) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'a) t6 = ('k1, ('k2,'k3,'k4,'k5,'k6,'a) t5) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'a) t7 = ('k1, ('k2,'k3,'k4,'k5,'k6,'k7,'a) t6) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'a) t8 = ('k1, ('k2,'k3,'k4,'k5,'k6,'k7,'k8,'a) t7) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'a) t9 = ('k1, ('k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'a) t8) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'k10,'a) t10 = ('k1, ('k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'k10,'a) t9) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'k10,'k11,'a) t11 = ('k1, ('k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'k10,'k11,'a) t10) t
type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'k10,'k11,'k12,'a) t12 = ('k1, ('k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,'k10,'k11,'k12,'a) t11) t

(* Method to get the array in its original state (ignoring permutations): *)
let get_original_elts t = t.elts

(* Method to get the array of keys in its original state (ignoring permutations): *)
let get_original_keys t : 'k array =
  match t.keys with
  | Bijection (k2i, i2k) -> Array.init (Array.length t.elts) (i2k)  (* i2k : {0,..,n-1} -> 'k *)
  | Keys (_kt, ks)       -> ks

let is_key_member_of t : 'k -> 'bool =
  match t.keys with
  | Bijection (k2i, _i2k) -> (fun k -> let i = (k2i k) in (i<(Array.length t.elts) && (i>=0)))
  | Keys (kt, ks)       -> Hashtbl.mem kt

(* All but keys remains unchanged: *)
let map_keys f t =
  let k1s = get_original_keys t in
  let k2s = Array.map f k1s in
  let ht2 = Hashset.to_hashtbl (*copy!*) (Hashset.of_array k2s) in
  { t with keys = Keys (ht2, k2s) }

(* -------------------- *)
module Preserving_order = struct
  (* Method to get the array in its current state (considering permutations): *)
  let get_elts t : 'a array =
    match t.perm with
    | None      -> t.elts
    | Some perm -> Permutation.Array.apply (perm) t.elts

  (* Method to get the array of keys in its current state (considering permutations): *)
  let get_keys t : 'k array =
    let keys = get_original_keys t in
    match t.perm with
    | None      -> keys
    | Some perm -> Permutation.Array.apply (perm) keys

  (* Method to get both the array and keys in thier current state (considering permutations): *)
  let get_keys_and_elts t : 'k array * 'a array =
    let keys = get_original_keys t in
    match t.perm with
    | None      -> keys, t.elts
    | Some perm -> ((Permutation.Array.apply (perm) keys), (Permutation.Array.apply (perm) t.elts))

end (* Preserving_order *)
(* -------------------- *)

let to_array = Preserving_order.get_elts
let to_keys  = Preserving_order.get_keys

let get_perm t : Permutation.t =
  match t.perm with
  | None      -> Permutation.identity (Array.length t.elts)
  | Some perm -> perm

(*let get_ungrouping t : Permutation.t =
  match t.ungrouping with
  | None      -> Permutation.identity (Array.length t.elts)
  | Some perm -> perm*)

(* Generic tool: *)
let extract_permutation (n:int) (operm : Permutation.t option) : Permutation.t =
  match operm with
  | None      -> Permutation.identity n
  | Some perm -> perm

let append_optional_permutations n1 n2 p1o p2o : Permutation.t option =
  if (p1o  = None) && (p2o = None) then None else (* continue: *)
  let p1  = extract_permutation n1 p1o in
  let p2  = extract_permutation n2 p2o in
  let p   = Permutation.append p1 p2 in (* => p2 translation *)
  Some p

let compose_optional_permutations p1o p2o : Permutation.t option =
  match p1o, p2o with
  | None, None -> None
  | None, Some p2 -> Some p2
  | Some p1, None -> Some p1
  | Some p1, Some p2 -> Some (Permutation.compose p1 p2)

let compose_perm (t: ('k,'a) t) (play : Permutation.t) : ('k,'a) t =
  let perm =
    match t.perm with
    | None      -> Some play
    | Some perm -> Some (Permutation.Array.apply play perm)
  in
  { t with perm}

(* --- *)

let id    = (fun k -> k)
let fake  = (fun _ -> assert false)
let empty = { keys=(Bijection (fake, fake)); elts=[||]; perm=None; ungrouping=[]; }

(* ------------------------------------------------------------------------- *)
module Tools = struct
(* ------------------------------------------------------------------------- *)

 let array_max xs =
  Array.fold_left (fun x y -> if y > x then y else x) xs.(0) xs

 let array_min xs =
  Array.fold_left (fun x y -> if y < x then y else x) xs.(0) xs

 let array_mapg (f : 's -> int -> 'a -> 'b * 's) (s0 : 's) (xs : 'a array) : 'b array * 's =
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

 (* array_iterg: ?start:int -> ('s -> int -> 'a -> 's) -> 's -> 'a array -> 's *)
 let array_iterg ?(start=0) (f : 's -> index -> 'a -> 's) (s0 : 's) (xs : 'a array) : 's =
   let n = Array.length xs in
   if n = 0 then s0 else begin
     let i0 = start in
     let s1 = f s0 i0 (xs.(i0)) in
     let state = ref s1 in
     for i = (i0+1) to (n-1) do
       let z = f (!state) i (xs.(i)) in
       state := z;
     done;
     !state
   end

 (* Alias: *)
 let array_foldi = array_iterg

 (* array_fold: ?start:int -> ('s -> 'a -> 's) -> 's -> 'a array -> 's *)
 let array_fold ?(start=0) (f : 's -> 'a -> 's) (s0 : 's) (xs : 'a array) : 's =
   let n = Array.length xs in
   if n = 0 then s0 else begin
     let i0 = start in
     let s1 = f s0 (xs.(i0)) in
     let state = ref s1 in
     for i = (i0+1) to (n-1) do
       let z = f (!state) (xs.(i)) in
       state := z;
     done;
     !state
   end

 let array_map2  f a b = Array.mapi (fun i a -> f a b.(i)) a
 let array_mapi2 f a b = Array.mapi (fun i a -> f i a b.(i)) a

 (* val ArrayExtra.search : ('a -> bool) -> 'a array -> 'a option
    OBSOLETE? *)
 let array_find_opt p s =
   let l = Array.length s in
   let rec loop i =
     if i>=l then None else
     let x = s.(i) in
     if (p x) then (Some x) else loop (i+1)
   in loop 0

 (* OBSOLETE? *)
 let array_rev_filter (p : 'a -> bool) (xs:'a array) : 'a list =
   Array.fold_left (fun ys x -> if p x then x::ys else ys) [] xs

 let array_filter_map_fold (p : 'a -> bool) (f:'a->'b) (g:'s->'b->'s) (s:'s) (xs:'a array) : 's =
   let ys = Array.fold_left (fun ys x -> if p x then x::ys else ys) [] xs in
   List.fold_right (fun x s -> g s (f x)) ys s

 let array_filter_map (p : 'a -> bool) (f:'a->'b) (xs:'a array) : 'b array =
   let ys = Array.fold_left (fun ys x -> if p x then (f x)::ys else ys) [] xs in
   Array.of_list (List.rev ys)

 (* Make regular array of arrays (i.e. a "matrix"): *)
 let matrix_init m n f = Array.init m (fun i -> Array.init n (fun j -> f i j))

 (* A regular array of arrays is what we generally call "matrix",
    i.e. an array of arrays where inner arrays have the same length. *)
 let transpose_regular_array_of_arrays (xss : 'a array array) =
   let size t = (Array.length t, Array.length t.(0)) in
   let (m,n) = size xss in
   matrix_init n m (fun i j -> xss.(j).(i))

 (* Regularize a jagged array transforming it into a sparse ('a option) matrix. *)
 let regularize_jagged_array_of_arrays (xys : 'a array array) : ('a option) array array =
   let m = Array.length xys in
   let n = Array.fold_left (fun s ys -> max s (Array.length ys)) 0 xys in (* max inner length *)
   (* Make a sparse regular structure: *)
   matrix_init m n
     (fun i ->
        let ys = xys.(i) in
        let n = Array.length ys in
        fun j -> if j<n then Some ys.(j) else None)

 (* Transpose a jagged array transforming it into a sparse ('a option) regular array of arrays. *)
 let transpose_jagged_array_of_arrays (xys : 'a array array) =
   (* Make a sparse regular structure: *)
   let xyos : ('a option) array array = regularize_jagged_array_of_arrays xys in
   (* Transpose the sparse but regular: *)
   let yxos = transpose_regular_array_of_arrays xyos in
   (* Filter and extract meaningfull elements: *)
   let extract = function Some x -> x | None -> assert false in
   Array.map (array_filter_map ((<>)None) extract) yxos

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


 (* OBSOLETE!!!!
    xcs is the array of elements x with thier class c.
    Note that the order of elements determines the choice of indexes for classes .*)
 let array_classify (xcs : ('a * 'c) array)  :  'c array * ('a array array) * ('c, index) Hashtbl.t =
   let n = Array.length xcs in
   let size = int_of_float ((float_of_int n) /. 0.70) in
   let ht_cls_indexes : ('c, int) Hashtbl.t = Hashtbl.create size in
   let ht_cls_elemnts : ('c, 'a)  Hashtbl.t = Hashtbl.create size in
   (* k will be the number of classes, cs the reversed list of classes. *)
   let (k, cs) =
     array_foldi
       (fun ((k,cs) as s) i (x,c) ->
          (* classes are added once: *)
          let s = if Hashtbl.mem ht_cls_indexes c then s else ((Hashtbl.add ht_cls_indexes c k); ((k+1), c::cs)) in
          (* elements of the same key are added to the previous: *)
          let () = Hashtbl.add ht_cls_elemnts c x in
          s)
       (0, [])
       xcs
   in
   (* Place now classes in an array: *)
   let cs : 'c array = array_of_known_length_list ~reversing:true k cs in
   let xss =
     Array.map
      (fun c ->
          (* Note that Hashtbl.find_all returns the list of all data associated
              with the key in reverse order of introduction in the table. *)
          let xs = Hashtbl.find_all (ht_cls_elemnts) c in
          let xs = Array.of_list (List.rev xs) in
          xs)
        cs
   in
   (cs, xss, ht_cls_indexes)

 (* The provided keys must be unique. In this hypothesis, the provided array ok keys represents
    an injective function {0,..,n-1} -> {k|k∊ks} . The purpose of this tool is to make an hasht table
    representing precisely the inverse surjective function {k|k∊ks} -> {0,..,n-1} *)
 let hashtbl_of_unique_keys ~caller n ks =
   let size = int_of_float ((float_of_int n) /. 0.70) in
   let ht = Hashtbl.create size in
   (* Note here `Hashtbl.replace' to be able to check unicity: *)
   let () = Array.iteri (fun i k -> Hashtbl.replace ht k i) ks (* i∊{0,..,n-1} *) in
   let () = (* check unicity of keys: *)
     if (Hashtbl.length ht) <> n
       then invalid_arg (Printf.sprintf "Ind.%s: keys are not unique" caller)
       else ()
   in
   ht

  module Printf
  : sig
      val cell_size_max     : int (* 100 *)
      val cell_size_default : int (*  10 *)
      (* --- *)
      val  sprintf : ?cell_size:int -> string -> string
      val osprintf : ?empty:string -> ?cell_size:int -> soel:('a -> string) -> 'a option -> string
      (* --- *)
      (* lprintf stands for "line printf": *)
      val  lprintf : ?cell_size:int -> string array -> string array
      val olprintf : ?empty:string -> ?cell_size:int -> lines:int -> soel:('a -> string array) -> 'a option -> string array
    end
  = struct

    let cell_size_max = 300
    let cell_size_default = 10

    let sprintf =
      let f x = lazy (format_of_string x) in
      let fs = [|
         f  "%0s"; f  "%1s"; f  "%2s"; f  "%3s"; f  "%4s"; f  "%5s"; f  "%6s"; f  "%7s"; f  "%8s"; f  "%9s";
         f "%10s"; f "%11s"; f "%12s"; f "%13s"; f "%14s"; f "%15s"; f "%16s"; f "%17s"; f "%18s"; f "%19s";
         f "%20s"; f "%21s"; f "%22s"; f "%23s"; f "%24s"; f "%25s"; f "%26s"; f "%27s"; f "%28s"; f "%29s";
         f "%30s"; f "%31s"; f "%32s"; f "%33s"; f "%34s"; f "%35s"; f "%36s"; f "%37s"; f "%38s"; f "%39s";
         f "%40s"; f "%41s"; f "%42s"; f "%43s"; f "%44s"; f "%45s"; f "%46s"; f "%47s"; f "%48s"; f "%49s";
         f "%50s"; f "%51s"; f "%52s"; f "%53s"; f "%54s"; f "%55s"; f "%56s"; f "%57s"; f "%58s"; f "%59s";
         f "%60s"; f "%61s"; f "%62s"; f "%63s"; f "%64s"; f "%65s"; f "%66s"; f "%67s"; f "%68s"; f "%69s";
         f "%70s"; f "%71s"; f "%72s"; f "%73s"; f "%74s"; f "%75s"; f "%76s"; f "%77s"; f "%78s"; f "%79s";
         f "%80s"; f "%81s"; f "%82s"; f "%83s"; f "%84s"; f "%85s"; f "%86s"; f "%87s"; f "%88s"; f "%89s";
         f "%90s"; f "%91s"; f "%92s"; f "%93s"; f "%94s"; f "%95s"; f "%96s"; f "%97s"; f "%98s"; f "%99s";
         (* --- *)
         f "%100s"; f "%101s"; f "%102s"; f "%103s"; f "%104s"; f "%105s"; f "%106s"; f "%107s"; f "%108s"; f "%109s";
         f "%110s"; f "%111s"; f "%112s"; f "%113s"; f "%114s"; f "%115s"; f "%116s"; f "%117s"; f "%118s"; f "%119s";
         f "%120s"; f "%121s"; f "%122s"; f "%123s"; f "%124s"; f "%125s"; f "%126s"; f "%127s"; f "%128s"; f "%129s";
         f "%130s"; f "%131s"; f "%132s"; f "%133s"; f "%134s"; f "%135s"; f "%136s"; f "%137s"; f "%138s"; f "%139s";
         f "%140s"; f "%141s"; f "%142s"; f "%143s"; f "%144s"; f "%145s"; f "%146s"; f "%147s"; f "%148s"; f "%149s";
         f "%150s"; f "%151s"; f "%152s"; f "%153s"; f "%154s"; f "%155s"; f "%156s"; f "%157s"; f "%158s"; f "%159s";
         f "%160s"; f "%161s"; f "%162s"; f "%163s"; f "%164s"; f "%165s"; f "%166s"; f "%167s"; f "%168s"; f "%169s";
         f "%170s"; f "%171s"; f "%172s"; f "%173s"; f "%174s"; f "%175s"; f "%176s"; f "%177s"; f "%178s"; f "%179s";
         f "%180s"; f "%181s"; f "%182s"; f "%183s"; f "%184s"; f "%185s"; f "%186s"; f "%187s"; f "%188s"; f "%189s";
         f "%190s"; f "%191s"; f "%192s"; f "%193s"; f "%194s"; f "%195s"; f "%196s"; f "%197s"; f "%198s"; f "%199s";
         (* --- *)
         f "%200s"; f "%201s"; f "%202s"; f "%203s"; f "%204s"; f "%205s"; f "%206s"; f "%207s"; f "%208s"; f "%209s";
         f "%210s"; f "%211s"; f "%212s"; f "%213s"; f "%214s"; f "%215s"; f "%216s"; f "%217s"; f "%218s"; f "%219s";
         f "%220s"; f "%221s"; f "%222s"; f "%223s"; f "%224s"; f "%225s"; f "%226s"; f "%227s"; f "%228s"; f "%229s";
         f "%230s"; f "%231s"; f "%232s"; f "%233s"; f "%234s"; f "%235s"; f "%236s"; f "%237s"; f "%238s"; f "%239s";
         f "%240s"; f "%241s"; f "%242s"; f "%243s"; f "%244s"; f "%245s"; f "%246s"; f "%247s"; f "%248s"; f "%249s";
         f "%250s"; f "%251s"; f "%252s"; f "%253s"; f "%254s"; f "%255s"; f "%256s"; f "%257s"; f "%258s"; f "%259s";
         f "%260s"; f "%261s"; f "%262s"; f "%263s"; f "%264s"; f "%265s"; f "%266s"; f "%267s"; f "%268s"; f "%269s";
         f "%270s"; f "%271s"; f "%272s"; f "%273s"; f "%274s"; f "%275s"; f "%276s"; f "%277s"; f "%278s"; f "%279s";
         f "%280s"; f "%281s"; f "%282s"; f "%283s"; f "%284s"; f "%285s"; f "%286s"; f "%287s"; f "%288s"; f "%289s";
         f "%290s"; f "%291s"; f "%292s"; f "%293s"; f "%294s"; f "%295s"; f "%296s"; f "%297s"; f "%298s"; f "%299s";
         (* --- *)
         f "%300s";
         |]
      in
      fun ?(cell_size = cell_size_default) ->
        if cell_size > cell_size_max
        then invalid_arg (Printf.sprintf "Ind: cell size is limited to %d characters" cell_size_max)
        else (* continue: *)
          Printf.sprintf (Lazy.force fs.(max 0 (min cell_size cell_size_max)))

    let osprintf =
      let sub s n = (* version replacing the last two chars with ".." *)
        let sub s n = try String.sub s 0 n with _ -> s in (* basic version *)
        let k = (String.length s) in
        if k<=n then s else (* k>n *)
        if n<3 then sub ".." n else
        Printf.sprintf "%s .." (sub s (n-3))
      in
      fun ?empty ?(cell_size = cell_size_default) ->
        let empty = match empty with None -> String.make (cell_size) '/' | Some s -> s in
        fun ~soel os ->
          let s = (match os with None -> empty | Some x -> (sub (soel x) cell_size)) in
          sprintf ~cell_size s

    (* sprintf is redefined with osprintf in order to consider cell limitations (?cell_size): *)
    let sprintf ?cell_size x = osprintf ?cell_size ~soel:(fun x -> x) (Some x)

    let lprintf ?cell_size =
      Array.map (sprintf ?cell_size)

    let olprintf ?empty ?cell_size ~lines ~soel =
      function
      | None   -> Array.make lines (osprintf ?empty ?cell_size ~soel:(fun _ -> assert false) None)
      | Some x -> lprintf ?cell_size (soel x)

  end (* Tools.Printf *)

end (* Tools *)

(* ------------------------------------------------------------------------- *)
module Make_printers_from_lines_generator
(* ------------------------------------------------------------------------- *)
  (* This functor takes a main uncurried function (A₁⨯..⨯Aₙ->B) and produces
     some derived tools in their curried version (A₁->..->Aₙ->B).
     Currying the set of derived functions get the OCaml type checker a bit
     confused (the type checker is not able to generalize the involved type variables).
     I dont see a convenient solution alternative to Obj.magic. *)
(* ------------------------------------------------------------------------- *)
  (M: sig (* Input signature *)
        (* --- *)
        type ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0) args
        type ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a1) t
        type ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0, 'a1, 'b) curried
        (* --- *)
        val lines_of_sparse :
          ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a) args ->
          ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a option) t -> string array
        (* --- *)
        val map : ('a -> 'b) -> ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a) t -> ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'b) t
        (* --- *)
        val currying : (* arrow -> curried *)
          (('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0) args -> ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a1) t -> 'b) ->
          ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0, 'a1, 'b) curried
        (* --- *)
      end) (* Input signature *)

  : sig (* Output signature *)
      (* --- *)
      type ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0, 'a1, 'b) arrow =
        ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0) M.args -> ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a1) M.t -> 'b
      (* --- *)
      (* The fake argument prevents from using Obj.magic: *)
      val lines_of         : ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10,'a, 'a       , string array) M.curried
      val string_of_sparse : ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10,'a, 'a option, string      ) M.curried
      val string_of        : ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10,'a, 'a       , string      ) M.curried
      (* --- *)
      val print_sparse     : ?out_channel:out_channel -> ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a, 'a option, unit) M.curried
      val print            : ?out_channel:out_channel -> ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a, 'a,        unit) M.curried
      (* --- *)
    end (* Output signature *)

  = struct (* Implementation: *)

  type ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0, 'a1, 'b) arrow =
    ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0) M.args -> ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a1) M.t -> 'b

  (* Arrows: *)

  let lines_of args t =
    let t' = M.map (fun x -> Some x) t in
    M.lines_of_sparse args t'

  let string_of_sparse args t =
    let lines = M.lines_of_sparse args t in
    (* Each line ends with "\n" *)
    let lines = Array.map (Printf.sprintf "%s\n") lines in
    String.concat "" (Array.to_list lines)

  let string_of args t =
    let t' = M.map (fun x -> Some x) t in
    string_of_sparse args t'

  let print_sparse ?(out_channel=stdout) args t =
    let msg = string_of_sparse args t in
    Printf.kfprintf flush out_channel "%s" msg

  let print ?(out_channel=stdout) args t =
    let msg = string_of args t in
    Printf.kfprintf flush out_channel "%s" msg

  (* Arrows -> curried.
     NOTE: Obj.magic is necessary because OCaml is not able to generalize the involved type variables and,
     in the meanwhile, the function M.currying must be applied partially. I dont see another convenient solution. *)
  (* --- *)
  let lines_of         = Obj.magic (M.currying lines_of)
  let string_of_sparse = Obj.magic (M.currying string_of_sparse)
  let string_of        = Obj.magic (M.currying string_of)
  (* --- *)
  let print_sparse ?out_channel = Obj.magic (M.currying (print_sparse ?out_channel))
  let print        ?out_channel = Obj.magic (M.currying (print ?out_channel))

end (* Functor As_vector.Make_printers_from_lines_generator *)

module Example_of_Make_printers_from_lines_generator : sig
   val lines_of  : ?x:'b1 -> ?y:'b2 -> 'a array -> string array
   val print     : ?out_channel:out_channel -> ?x:'b1 -> 'a array -> unit
 end
 = struct

 (* Define the curried generator: *)
 let lines_of_sparse ?x ?y (t) =
   match x,y with
   | None, None    -> [|"hello"; "hello"|]
   | None, Some _  -> [|"hello"; "world"|]
   | Some _, None  -> [|"world"; "hello"|]
   | Some _, Some _-> [|"world"; "world"|]

 include Make_printers_from_lines_generator
  (struct
        type ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a) args = ('b1 option) * ('b2 option)
        type ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a) t = 'a array
        type ('b1,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0, 'a1, 'b) curried = ?x:'b1 -> ?y:'b2 -> 'a1 array -> 'b

        (* Uncurrying the curried generator: *)
        let lines_of_sparse ((x,y) as _args) t =
          lines_of_sparse ?x ?y t

        let map = Array.map
        let currying arrow ?x ?y = arrow (x,y)
   end)

   (* Adjust signatures (remove some arguments): *)
   let print = print ?y:None

end (* Example_of_Make_printers_from_lines_generator *)


(* ------------------------------------------------------------------------- *)
(* Tools to create a structure like it was a simple array. *)
(* ------------------------------------------------------------------------- *)
module As_array = struct
(* ------------------------------------------------------------------------- *)

  (* empty with int keys (the function providing indexes is the identity): *)
  let empty = { empty with keys=(Bijection (id,id)) }

  (* val init : int -> (int -> 'a) -> (int,'a) t *)
  let init n f = { empty with elts = Array.init n f; }

  (* val make : int -> 'a -> (int,'a) t *)
  let make n a = { empty with elts = Array.make n a; }

  let singleton x = make 1 x
end (* As_array *)



(* ------------------------------------ *)
module Derived_constructors_up_to_10_keys
(* ------------------------------------ *)
  (M : sig
          type ('k0,'k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9) keys
          type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) source
          type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) target
          val of_assoc_array  : ('k0 * ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) source) array -> ('k0, ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) target) t
          val restruct_tuples : ('k0, 'k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9) keys -> 'a -> 'k0 * ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) source
        end)
(* ------------------------------------ *)
  : sig
    open M
    val init : int -> (index -> 'k0 * ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) source) -> ('k0, ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) target) t
    val make : int -> ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) source -> (index -> 'k0) -> ('k0, ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) target) t
    (* --- *)
    val singleton : 'k0 -> ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) source -> ('k0, ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) target) t
    (* --- *)
    val shape :
      ('a -> 'k0 * ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'b) source) -> 'a array -> ('k0, ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'b) target) t
    (* --- *)
    val shapei :
      (index -> 'a -> 'k0 * ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'b) source) ->
      'a array -> ('k0, ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'b) target) t
    (* --- *)
    val shapeg :
      ('s -> index -> 'a -> ('k0 * ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'b) source) * 's) -> 's ->
      'a array -> ('k0, ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'b) target) t * 's
    (* --- *)
    val dress  :
      ('a -> ('k0, 'k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9) keys) ->
      'a array -> ('k0, ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) target) t
    (* --- *)
    val dressi :
      (index -> 'a -> ('k0, 'k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9) keys) ->
      'a array -> ('k0, ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) target) t
    (* --- *)
    val dressg :
      ('s -> index -> 'a -> (('k0, 'k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9) keys) * 's) -> 's ->
      'a array -> ('k0, ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) target) t * 's
    (* --- *)
    val of_assoc_list  : ('k0 * ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) source) list  -> ('k0, ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9, 'a) target) t
    end
(* ------------------------------------ *)
  = struct

  (* val init : int -> (int -> 'k * 'a) -> ('k,'b) t *)
  let init n f =
    M.of_assoc_array (Array.init n f)

  (* val make : int -> 'b -> (int -> 'k) -> ('k,'b) t *)
  let make n b f =
    init n (fun i -> (f i), b)

  let singleton k x =
    init 1 (fun _ -> (k, x))

  (* val of_assoc_list  : ('k * 'a) list  -> ('k, 'b) t *)
  let of_assoc_list kvs =
    M.of_assoc_array (Array.of_list kvs)

  (* val shape : ('a -> 'k * 'b) -> 'a array -> ('k, 'c) t *)
  let shape f xs =
    M.of_assoc_array (Array.map f xs)

  (* val shapei : (index -> 'a -> 'k * 'b) -> 'a array -> ('k, 'c) t *)
  let shapei f xs =
    M.of_assoc_array (Array.mapi f xs)

  (* val shapeg : ('s -> index -> 'a -> ('k * 'b) * 's) -> 's -> 'a array -> ('k, 'c) t *)
  let shapeg f s0 xs =
    let kbs, s1 = Tools.array_mapg f s0 xs in
    (M.of_assoc_array kbs), s1

  (* val dress : ('a -> 'k) -> 'a array -> ('k, 'b) t *)
  let dress f xs =
    let f' = (fun x -> M.restruct_tuples (f x) x) in
    M.of_assoc_array (Array.map f' xs)

  (* val dressi : (index -> 'a -> 'k) -> 'a array -> ('k, 'b) t *)
  let dressi f xs =
    let f' = (fun i x -> M.restruct_tuples (f i x) x) in
    M.of_assoc_array (Array.mapi f' xs)

  (* val dressg : ('s -> index -> 'a -> 'k * 's) -> 's -> 'a array -> ('k, 'b) t *)
  let dressg f s0 xs =
    let f' = fun s i x -> let (k,s) = (f s i x) in (M.restruct_tuples k x), s in
    let kbs, s1 = (Tools.array_mapg f' s0 xs) in
    (M.of_assoc_array kbs), s1

  end (* Derived_constructors_up_to_10_keys *)

(* ------------------------------------------------------------------------- *)
(* An (associative) tensor viewed as a vector. *)
(* ------------------------------------------------------------------------- *)
module As_vector = struct
(* ------------------------------------------------------------------------- *)

  (* -------------------- *)
  module Make_11 = struct
  (* -------------------- *)

    let of_assoc_array (kvs : ('k * 'a) array) : ('k, 'a) t =
      let n = Array.length kvs in
      let ks, vs = ArrayTk.Tuple_array.split2 kvs in
      let ht = Tools.hashtbl_of_unique_keys ~caller:"Ind.As_vector" n ks in
      { empty with  elts = vs;  keys = Keys (ht, ks); }

    include Derived_constructors_up_to_10_keys(struct
      type ('k0, 'k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9) keys   = 'k0
      type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,  'a) source = 'a
      type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,  'a) target = 'a     (* 11 *)
      let of_assoc_array = of_assoc_array
      let restruct_tuples k0 a = (k0, a)
      end)

    (* Stable: *)
    (* val to_assoc_array : ('k,'a) t -> ('k * 'a) array *)
    let to_assoc_array t =
      let ks, xs = Preserving_order.get_keys_and_elts t in
      ArrayTk.Tuple_array.combine2 ks xs

    (* Stable: *)
    (* val to_assoc_list  : ('k,'a) t -> ('k * 'a) list *)
    let to_assoc_list t =
      Array.to_list (to_assoc_array t)

  end (* As_vector.Make_11 *)

  (* -------------------- *)
  module Make_1N = struct
  (* -------------------- *)

    (* Stable.
      val of_assoc_array : ('k * 'a) array -> ('k, 'a array) t *)
    let of_assoc_array (kxs : ('k * 'a) array) : ('k, 'a array) t =
      let ks, xs = ArrayTk.Tuple_array.split2 (kxs) in
      let hset = Hashset.of_array ks in
      let ks' = Hashset.to_array hset in
      let ht  = Hashset.to_hashtbl (*copy!*) hset in (* mapping key -> index *)
      let n = Array.length ks' in
      let xss, _ =
        ArrayTk.Partition.partitioni ~outer_size:n (fun i _x -> Hashtbl.find ht ks.(i)) xs
      in
      Make_11.init n (fun i -> ks'.(i), xss.(i))

    include Derived_constructors_up_to_10_keys(struct
      type ('k0, 'k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9) keys   = 'k0
      type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,  'a) source = 'a
      type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,  'a) target = 'a array  (* 1N *)
      let of_assoc_array = of_assoc_array
      let restruct_tuples k0 a = (k0, a)
      end)

    (* val to_assoc_array : ('k, 'a array) t -> ('k * 'a) array *)
    let to_assoc_array t =
      let array_concat xss = Array.concat (Array.to_list xss) in
      let kxs's = Make_11.to_assoc_array t in
      let kxs's = Array.map (fun (k, xs) -> Array.map (fun x -> (k,x)) xs) kxs's in
      let kxs   = array_concat (kxs's) in
      kxs

    (* val to_assoc_list  : ('k, 'a array) t -> ('k * 'a) list *)
    let to_assoc_list t =
      Array.to_list (to_assoc_array t)

  end (* Make_1N *)

  (* --------------------------- *)
  (* Module As_vector (continue) *)
  (* --------------------------- *)

  let empty () =
    let empty_ht = (Hashtbl.create 0) in
    { empty with keys = Keys (empty_ht, [||]); }

  (* val length : ('k, 'a) t -> int *)
  let length t = Array.length t.elts
  let shape  t = Array.length t.elts

  (* This function should be applied partially with the structure, in order to apply the result to several keys
     having performed some tests about the structure once: *)
  let get_index t : 'k -> index =
    let i_of = match t.keys with Bijection (k2i,_) -> k2i | Keys (kt, _ks) -> (Hashtbl.find kt) in
    let j_of = match t.perm with None -> i_of | Some p -> (fun k -> p.(i_of k)) in
    fun k ->
      try
        j_of (k)
      with _ -> invalid_arg ("Ind.As_vector.get: key not found")

  (* val get : ('k, 'a) t -> 'k -> 'a *)
  let get t =
    let get_index = get_index t in (* partial application *)
    fun k -> t.elts.(get_index k)

  (* val get : ('k, 'a) t -> 'k -> 'a option *)
  let get_opt t k =
    try
     Some (Array.get t.elts (get_index t k))
    with _ -> None

  let mem = is_key_member_of

  (* val append : ('k,'a) t -> ('k,'a) t -> ('k,'a) t *)
  let append t1 t2 =
    let n1 = Array.length t1.elts in
    let n2 = Array.length t2.elts in
    let elts = Array.append t1.elts t2.elts in
    let keys =
      match t1.keys, t2.keys with
      (* --- *)
      (* Hp: we suppose that the functions converting keys into indexes and reciprocally fails outside their domain: *)
      | Bijection (k2i, i2k), Bijection (k2i', i2k') ->
        (*  k2i  : 'k -> {0,..,n1-1}
            k2i' : 'k -> {0,..,n2-1}
            k2i'': 'k -> {0,..,n1+n2-1} *)
        let k2i'' k = try k2i k with _ -> (k2i' k) + n1 (* translation *) in
        (*  ---
            i2k  : {0,..,n1-1} -> 'k
            i2k' : {0,..,n2-1} -> 'k
            i2k'': {0,..,n1+n2-1} -> 'k *)
        let i2k'' i = try i2k i with _ -> (i2k' (i-n1)) (* translation *) in
        (* --- *)
        Bijection (k2i'', i2k'')
      (* --- *)
      | Keys (_kt1, ks1), Keys (_kt2, ks2) ->
          let ks = Array.append ks1 ks2 in
          let kt = Tools.hashtbl_of_unique_keys ~caller:"As_vector.append" (n1+n2) ks in
          Keys (kt, ks)
      (* --- *)
      (* Hybrid case n.1: *)
      | Keys (_kt1, ks1), Bijection (_k2i, i2k) ->
          let ks2 = Array.init n2 i2k in
          let ks = Array.append ks1 ks2 in
          let kt = Tools.hashtbl_of_unique_keys ~caller:"As_vector.append" (n1+n2) ks in
          Keys (kt, ks)
      (* --- *)
      (* Hybrid case n.2: *)
      | Bijection (_k2i, i2k), Keys (_kt2, ks2) ->
          let ks1 = Array.init n1 i2k in
          let ks = Array.append ks1 ks2 in
          let kt = Tools.hashtbl_of_unique_keys ~caller:"As_vector.append" (n1+n2) ks in
          Keys (kt, ks)
    in
    (* --- *)
    let perm = append_optional_permutations n1 n2 (t1.perm) (t2.perm) in
    (* let ungrouping = append_optional_permutations n1 n2 (t1.ungrouping) (t2.ungrouping) in (* SICURO ???? *) *)
    let ungrouping = [] in
    (* --- *)
    { keys; elts; perm; ungrouping; }

  (* Should be optimized. *)
  let concat ts =
    if Array.length ts = 0 then empty () else
    Tools.array_fold ~start:1 (append) ts.(0) ts

  (* val sort : ?stable:unit -> ?compare:('a compare) -> ('k, 'a) t -> ('k, 'a) t *)
  let sort ?stable ?compare t =
    let _elts, p = Permutation.Array.sort ?stable ?compare (t.elts) in
    { t with perm = Some p }

  (* val shuffle : ('k, 'a) t -> ('k, 'a) t *)
  let shuffle t =
    let p = Permutation.shuffle (Array.length t.elts) in
    { t with perm = Some p }

  (* val reverse : ('k, 'a) t -> ('k, 'a) t *)
  let reverse t =
    let p = Permutation.reverse (Array.length t.elts) in
    compose_perm t p

  (* val swap : (int * int) list -> 'a t -> 'a t *)
  let swap khs t =
    let ijs = List.map (fun (k,h) -> (get_index t k), (get_index t h)) khs in
    let _elts, p = Permutation.Array.swap (Preserving_order.get_elts t) (ijs) in
    compose_perm t p

  (* f is applied to element in their initial order: *)
  let map f t =
    { t with elts = Array.map f t.elts }

  (* f is applied to element in their initial order: *)
  let mapk f t =
    let keys = get_original_keys t in
    { t with elts = Array.mapi (fun i x -> f keys.(i) x) t.elts }

  (* f is applied to element in their initial order: *)
  let mapg f s0 t =
    let keys = get_original_keys t in
    let elts, s1 = Tools.array_mapg (fun s i x -> f s keys.(i) x) s0 t.elts in
    ({ t with elts }, s1)

  (* f is applied to element in their initial order: *)
  let iter f t =
    Array.iter f t.elts

  (* f is applied to element in their initial order: *)
  let iterk f t =
    let keys = get_original_keys t in
    Array.iteri (fun i x -> f keys.(i) x) t.elts

  (* f is applied to element in their initial order: *)
  let iterg f s t =
    let keys = get_original_keys t in
    Tools.array_iterg (fun s i x -> f s keys.(i) x) s t.elts

  let fold f s t =
    Array.fold_left f s t.elts

  (* f is applied to element in their current order.
     However, the mapping doesn't modify the initial order neither the current order: *)
  let map_stable f t =
    match t.perm with
    | None -> map f t
    | Some p ->
        let elts' = Array.map f (Preserving_order.get_elts t) in
        let _elts = Permutation.Array.In_place.unapply p elts' in
        { t with elts = elts' } (* t.perm remains meaningfull in the result *)

  (* f is applied to element in their current order: *)
  let iter_stable f t =
    Array.iter f (Preserving_order.get_elts t)

  (* f is applied to element in their current order: *)
  let iterk_stable f t =
    let keys, elts = Preserving_order.get_keys_and_elts t in
    Array.iteri (fun i x -> f keys.(i) x) elts

  (* f is applied to element in their current order: *)
  let iterg_stable f s t =
    let keys, elts = Preserving_order.get_keys_and_elts t in
    Tools.array_iterg (fun s i x -> f s keys.(i) x) s elts

  let fold_stable (f: 's -> 'a -> 's) (s : 's) (t : ('k, 'a) t) =
    let elts = Preserving_order.get_elts t in
    Array.fold_left f s elts

  (* f is applied to element in their current order: *)
  let mapk_stable f t =
    match t.perm with
    | None -> mapk f t
    | Some p ->
        let keys, elts = Preserving_order.get_keys_and_elts t in
        let elts' = Array.mapi (fun i x -> f keys.(i) x) elts in
        let _elts = Permutation.Array.In_place.unapply p elts' in
        { t with elts = elts' } (* t.perm remains meaningfull in the result *)

  let mapg_stable f s t =
    match t.perm with
    | None -> mapg f s t
    | Some p ->
        let keys, elts = Preserving_order.get_keys_and_elts t in
        let elts', state = Tools.array_mapg (fun s i x -> f s keys.(i) x) s (elts) in
        let _elts = Permutation.Array.In_place.unapply p elts' in
        ({ t with elts = elts' }, state) (* t.perm remains meaningfull in the result *)

  (* Implicitely stable. The constraint here is that the keys of the first structure
     must be injected in the keys of the second. There is any constraint about the order.
     The result inherits the order of the first argument. *)
  let combine t1 t2 =
    let get_t2 = get t2 in (* partial application *)
    mapk (fun k x -> x, (get_t2 k)) t1 (* no need for a stable mapping (relevant example) *)

  (* val split : ('k, 'a * 'b) t -> ('k, 'a) t * ('k, 'b) t  *)
  let split t =
    (* All inner structures except elements are shared (keys, perm, ungrouping): *)
    let xys = t.elts in
    let t1 = { t with elts = Array.map fst xys } in
    let t2 = { t with elts = Array.map snd xys } in
    (t1,t2)

  let permute_like model t =
    let n  = Array.length model.elts in
    let n' = Array.length t.elts in
    let () = if n = n' then () else
      invalid_arg (Printf.sprintf "Ind.As_vector.permute_like: different lengths (%d vs %d)" n n')
    in
    { t with perm = model.perm }

  let group (f:'k -> 'a -> 'g) (t: ('k, 'a) t) : ('g, 'k, 'a) t2 =
    (* Les trois prochaines lignes sont celle de la fonction "group" simple (sans prise de tête): *)
    let kxs  : ('k * 'a) array = Make_11.to_assoc_array t in (* in the current order *)
    let gkxs : ('g, ('k * 'a) array) t = Make_1N.dress (fun (k,x) -> f k x) kxs in
    let result = map (Make_11.of_assoc_array) gkxs in (* map no needs to be stable here *)
    (* --- *)
    (* The grouping permutation is the permutation associated to the partinioning of t,
       composed with the current permutation of t, if any. *)
    let grouping_perm : Permutation.t array (* leaved structured, not catenated *) =
      let gkxs' = Make_11.to_assoc_array gkxs in
      let get_index = get_index t in
      let group_perms : Permutation.t array = Array.map (fun (g, kxs) -> Array.map (fun (k,_) -> get_index k) kxs) gkxs' in
      match t.perm with
      | None   -> group_perms
      | Some p ->
          let current_perms, _split_play = ArrayTk.Split.split_like (group_perms) (p) in
          Tools.array_map2 (Permutation.compose) (current_perms) (group_perms)
          (*  Array.concat (Array.to_list perms) *)
    in
    { result with ungrouping = grouping_perm::t.ungrouping }

  (* Just an alias: *)
  let nest = group

  (* TODO: in the interface: *)
  let rewind (play : Permutation.t) t =
    let keys = Permutation.Array.unapply play (get_original_keys t) in
    let elts = Permutation.Array.unapply play (get_original_elts t) in
    Make_11.dressi (fun i x -> keys.(i)) elts

  (* val ungroup : ('g, 'k, 'a) t2 -> ('k, 'a) t *)
  let ungroup (t2 : ('g, 'k, 'a) t2) : ('k, 'a) t =
    let grouping_perm = List.hd t2.ungrouping in
    (* If the group has been permuted after it creation, the grouping permutation must be updated: *)
    let grouping_perm =
      match t2.perm with
      | None      -> grouping_perm
      | Some perm -> Permutation.Array.apply perm grouping_perm
    in
    (* Now, group permutations may be ignored (restore the state as it was just after grouping): *)
    let t2 = { t2 with perm = None } in
    (* Get the pairs in the original order: *)
    let gts : ('g * ('k,'a) t) array = Make_11.to_assoc_array t2 in
    (* Each structure has its own permutation: *)
    let inner_perms : Permutation.t array =
      Array.map (fun (g, t) -> get_perm t) gts
    in
    (* Forget groups and concat the inner structures in their original order: *)
    let ts = Array.map (fun (g, t) -> {t with perm=None}) gts in
    let result : ('k, 'a) t = concat ts in
    (* --- *)
    let perms = (grouping_perm) in
    (* Destructure (ungroup) perms: *)
    let perm = Array.concat (Array.to_list perms) in
    (* --- *)
    let result = rewind (perm) result in (* restore the original order in the result *)
    (* --- *)
    (* Now flatten inner permutations translating them: *)
    let inner_perm = Permutation.concat_array (inner_perms) in
    (* --- *)
    (* The result may be optimized with perm = None if we detect that inner_perm is the identity *)
    { result with perm = Some inner_perm; ungrouping = List.tl t2.ungrouping }

  (* Just an alias: *)
  let unnest = ungroup

  let pairing t1 t2 =
    let keys1, elts1 = Preserving_order.get_keys_and_elts t1 in
    let keys2, elts2 = Preserving_order.get_keys_and_elts t2 in
    let n  = Array.length keys1 in
    let n' = Array.length keys2 in
    let () = if n = n' then () else
      invalid_arg (Printf.sprintf "Ind.As_vector.pairing: structures have different lengths (%d vs %d)" n n')
    in
    let result = Make_11.init n (fun i -> (keys1.(i), keys2.(i)), (elts1.(i), elts2.(i))) in
    { result with perm = t1.perm } (* permute_like t1 result *)

  (* val currying : (('k1 * 'k2), 'a) t -> ('k1, 'k2, 'a) t2
     currying is group by k1, then (map (map_keys snd)). *)
  let currying (t : (('k1 * 'k2), 'a) t) : ('k1, 'k2, 'a) t2 =
    let t1 : ('k1, ('k1 * 'k2), 'a) t2 = group (fun (k1, _k2) _a -> k1) t in
    map (map_keys snd) t1

  (* val uncurrying : ('k1, 'k2, 'a) t2 -> (('k1 * 'k2), 'a) t
     uncurrying is inject k1 at the second level, then ungroup. *)
  let uncurrying (t2 : ('k1, 'k2, 'a) t2) : (('k1 * 'k2), 'a) t =
    let t2' : ('k1, ('k1 * 'k2), 'a) t2 = mapk (fun k1 -> map_keys (fun k2 -> (k1, k2))) t2 in
    ungroup t2'

  (* Union of previous definitions. The parameter `stable' forces the provided
     function to be called in the current order, not in the initial one. *)
  let map   ?stable f = match stable with None -> map f   | Some () -> map_stable f
  let mapk  ?stable f = match stable with None -> mapk f  | Some () -> mapk_stable f
  let mapg  ?stable f = match stable with None -> mapg f  | Some () -> mapg_stable f
  let iter  ?stable f = match stable with None -> iter f  | Some () -> iter_stable f
  let iterk ?stable f = match stable with None -> iterk f | Some () -> iterk_stable f
  let iterg ?stable f = match stable with None -> iterg f | Some () -> iterg_stable f
  let fold  ?stable f = match stable with None -> fold f  | Some () -> fold_stable f

  let map2 ?stable f t1 t2 =
    map ?stable (fun (x,y) -> f x y) (combine t1 t2)

  let mapk2 ?stable f t1 t2 =
    mapk ?stable (fun k (x,y) -> f k x y) (combine t1 t2)

  let partition (f:'a -> 'c) (t: ('k, 'a) t) : ('c, 'k, 'a) tt =
    (* --- *)
    let ks, xs : 'k array * 'a array = Preserving_order.get_keys_and_elts t in
    let kxcs : (('k * 'a) * 'c) array = Array.mapi (fun i x -> (ks.(i), x), f x) (xs) in
    (* --- *)
    let cs, kxss, cis : 'c array * (('k * 'a) array) array * ('c, index) Hashtbl.t =
      Tools.array_classify kxcs
    in
    let keys : 'c indexing = Keys (cis, cs) in
    let elts :  (('k, 'a) t) array =
      Array.map (fun kxs -> Make_11.init (Array.length kxs) (Array.get kxs)) kxss
    in
    let perm = None and ungrouping = [] in
    { keys; elts; perm; ungrouping; }

  let refinement (f:'a -> 'c) (t: ('k, 'a) t) : ('k, 'c, 'a) tt =
    map_stable (fun x -> Make_11.singleton (f x) x) t


(*  let assoc_array_factorise (kkxs : (('k1 * 'k2) * 'a) array) : ('k1 * (('k2 * 'a) array)) array =
    let kks, xs  = ArrayTk.Tuple_array.split2 (kkxs) in
    let k1s, k2s = ArrayTk.Tuple_array.split2 (kks) in
    let k1s = Hashset.array_uniq k1s in


  let split_keys (t : (('k1 * 'k2), 'a) t) : ('k1, 'k2, 'a) tt =
    let k1s, k2s = ArrayTk.Tuple_array.split2 (Preserving_order.get_keys t) in
    let k1s = Hashset.array_uniq k1s in (* stable *)*)


  (* ------------------------------------ *)
  module (*As_vector.*)Horizontal = struct
  (* ------------------------------------ *)

  (* let xs = As_array.init 5 (fun i -> Char.chr (65+i)) ;;
     As_vector.Horizontal.print ~cell_size:10 ~sok:(string_of_int) ~soel:(fun x -> [|Char.escaped x; Char.escaped x|]) xs ;;

                0            1            2            3            4
     | ---------- | ---------- | ---------- | ---------- | ---------- |
     |          A |          B |          C |          D |          E |
     |          A |          B |          C |          D |          E |
     | ---------- | ---------- | ---------- | ---------- | ---------- |
    *)
    let lines_of_sparse
      ?no_header ?empty ?(cell_size=10) ~(sok:'k -> string) ~(soel:'a -> string array) (t: ('k, 'a option) t) : string array
      =
      let really_empty = String.make (cell_size) ' ' in
      (* --- *)
      (* Column headers: *)
      (*     9       8       7       6       5       3       1       4       2       0    *)
      let hs = if no_header = Some () then "" else
        let hs : string array = Array.map (fun k -> Tools.Printf.sprintf ~cell_size (sok k)) (Preserving_order.get_keys t) in
        let hs = String.concat "   " (Array.to_list hs) in
        hs
      in
      (* --- *)
      (* Column separators: *)
      (* -----   -----   -----   -----   -----   -----   -----   -----   -----   -----    *)
      let seps : string array =
        let sep = String.make (cell_size) '-' in
        Array.map (fun _ -> sep) t.elts
      in
      let seps = String.concat " | " (Array.to_list seps) in
      (* --- *)
      (* Elements : *)
      (*     B       D       a       b       c       d       e   /////   /////   /////   *)
      (* --- *)
      (* xls : each element (x) will correspond to a constant number of lines (ls) *)
      let xls : string array array =
        let yls : (string array option) array = Array.map (Option.map soel) (Preserving_order.get_elts t) in
        (* Get the maximum number of inner lines: *)
        let lines = Tools.array_filter_map_fold ((<>)None) (fun ys -> Array.length (Option.extract ys)) (max) 1 yls in
        (* Array.map (Tools.Printf.olprintf ?empty ~cell_size ~lines ~soel) (Preserving_order.get_elts t)  *)
        Array.map (Tools.Printf.olprintf ?empty ~cell_size ~lines ~soel:(fun x->x)) yls
      in
      (* Now we have to transpose the matrix xls to have an array indexed by lines, not by elements: *)
      (* let lxs = Tools.transpose_jagged_array_of_arrays xls in *)
      let xlos : (string option) array array = Tools.regularize_jagged_array_of_arrays xls in
      (* Transpose the sparse but regular: *)
      let lxos : (string option) array array = Tools.transpose_regular_array_of_arrays xlos in
      (* Extract or transform None into really empty cells: *)
      let extract = function Some x -> x | None -> really_empty in
      let lxs = Array.map (Array.map extract) lxos in
      (* --- *)
      (* Catenate lines: *)
      let ls = Array.map (fun xs -> String.concat " | " (Array.to_list xs)) lxs in
      (* Add headers and separators: *)
      let result =
        match no_header with
        | None    -> Array.concat [ [| hs; seps |]; ls; [| seps |] ]
        | Some () -> Array.concat [ ls; [| seps |] ]
      in
      (* Each line is delimited by "| %s |" except the first: *)
      Array.mapi (fun i -> if i=0 then Printf.sprintf "  %s  " else Printf.sprintf "| %s |") result

    (* --- Generated printers --- *)

    include Make_printers_from_lines_generator
      (struct
            type ('k,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a) args =
              (unit option) * (string option) * (int option) * ('k -> string) * ('a -> string array)

            type ('k,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a) t = ('k, 'a) t1

            type ('k,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0, 'a1, 'b) curried =
              ?no_header:unit -> ?empty:string -> ?cell_size:int ->
              sok:('k -> string) -> soel:('a0 -> string array) ->
              ('k, 'a1) t1 -> 'b

            (* Uncurrying the curried generator: *)
            let lines_of_sparse ((no_header, empty, cell_size, sok, soel) as _args) t =
              lines_of_sparse ?no_header ?empty ?cell_size ~sok ~soel t

            let map f t = map ?stable:None f t
            let currying arrow ?no_header ?empty ?cell_size ~sok ~soel = arrow (no_header, empty, cell_size, sok, soel)
      end)

      (* Adjust signatures (remove the optional argument ?empty): *)
      let string_of = string_of ?empty:None
      let print     = print ?empty:None

  end (* Horizontal *)

  (* ------------------------------------ *)
  module (*As_vector.*)Vertical = struct
  (* ------------------------------------ *)

    (* let xs = As_array.init 3 (fun i -> Char.chr (65+i)) ;;
       As_vector.Vertical.print ~cell_size:10 ~sok:(string_of_int) ~soel:(fun x -> [|Char.escaped x; Char.escaped x|]) xs ;;

           | ---------- |
         0 |          A |
           |          A |
           | ---------- |
         1 |          B |
           |          B |
           | ---------- |
         2 |          C |
           |          C |
           | ---------- |
    *)
    let lines_of_sparse
      ?no_header ?empty ?(cell_size=10) ~(sok:'k -> string) ~(soel:'a -> string array) (t: ('k, 'a option) t) : string array
      =
      (* --- *)
      (* Elements : *)
      let xss, inner_lines : string array array * int =
        let yss : (string array option) array = Array.map (Option.map soel) (Preserving_order.get_elts t) in
        (* Get the maximum number of inner lines: *)
        let lines = Tools.array_filter_map_fold ((<>)None) (fun ys -> Array.length (Option.extract ys)) (max) 1 yss in
        let xss = Array.map (Tools.Printf.olprintf ?empty ~cell_size ~lines ~soel:(fun x->x)) yss in
        xss, lines
      in
      (* --- *)
      (* Row headers: *)
      let hss, really_empty : (string array array) * string =
        if no_header = Some () then ([||], (String.make (cell_size) ' ')) else (* continue: *)
        let ks : string array = Array.map (sok) (Preserving_order.get_keys t) in
        (* Headers have a particular cell_size: the minimum between the provided cell_size and the max length of keys: *)
        let cell_size =
          let max_length = Array.fold_left (fun s y -> max s (String.length y)) 0 ks in
          min cell_size max_length
        in
        let really_empty = String.make (cell_size) ' ' in
        let hs : string array = Array.map (Tools.Printf.sprintf ~cell_size) ks in
        let hss = Array.mapi (fun j _ -> Array.init (inner_lines) (fun i -> if i=0 then hs.(j) else really_empty)) xss in
        hss, really_empty
      in
      (* --- *)
      (* Merge headers with elements: *)
      let hxss : (string array) array =
        Tools.array_map2 (Tools.array_map2 (Printf.sprintf "%s | %s |")) hss xss
      in
      (* --- *)
      (* Row separator: *)
      (* | ----- | *)
      let sep : string =
        let sep = String.make (cell_size) '-' in
        match no_header with
        | Some () -> sep
        | None ->
           Printf.sprintf "%s | %s |" really_empty sep
      in
      (* --- *)
      (* Add a separator after each group of lines associated to an element: *)
      let hxs_sep_s = Array.map (fun hxs -> Array.append hxs [|sep|]) hxss in
      (* --- *)
      let result : string array = Array.concat ([|sep|]::(Array.to_list hxs_sep_s)) in
      result

    (* --- Generated printers --- *)

    include Make_printers_from_lines_generator
      (struct
            type ('k,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a) args =
              (unit option) * (string option) * (int option) * ('k -> string) * ('a -> string array)

            type ('k,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a) t = ('k, 'a) t1

            type ('k,'b2,'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0, 'a1, 'b) curried =
              ?no_header:unit -> ?empty:string -> ?cell_size:int ->
              sok:('k -> string) -> soel:('a0 -> string array) ->
              ('k, 'a1) t1 -> 'b

            (* Uncurrying the curried generator: *)
            let lines_of_sparse ((no_header, empty, cell_size, sok, soel) as _args) t =
              lines_of_sparse ?no_header ?empty ?cell_size ~sok ~soel t

            let map f t = map ?stable:None f t
            let currying arrow ?no_header ?empty ?cell_size ~sok ~soel = arrow (no_header, empty, cell_size, sok, soel)
      end)

      (* Adjust signatures (remove the optional argument ?empty): *)
      let string_of = string_of ?empty:None
      let print     = print ?empty:None

  end (* Vertical *)


end (* As_vector *)


module As_matrix = struct

  (* ------------------- *)
  module Make_11 = struct
  (* ------------------- *)
  (* NOTA che 11 si riferisce all'ultima chiave, la prima essendo necessariamente 1N. *)

    let of_assoc_array (kks : ('k1 * ('k2 * 'a)) array) : ('k1, 'k2, 'a) t2 =
      let kkst : ('k1, ('k2 * 'a) array) t = As_vector.Make_1N.of_assoc_array kks in
      (As_vector.map (As_vector.Make_11.of_assoc_array) kkst)

    include Derived_constructors_up_to_10_keys(struct
      type ('k0, 'k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9) keys   = 'k0 * 'k1
      type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,  'a) source = 'k1 * 'a
      type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,  'a) target = ('k1, 'a) t  (* 11 *)
      let of_assoc_array = of_assoc_array
      let restruct_tuples (k0,k1) a = (k0, (k1, a))
      end)

    (* Stable: *)
    let to_assoc_array (t : ('k1, 'k2, 'a) t2) : ('k1 * ('k2 * 'a)) array =
      let kxst = As_vector.map (As_vector.Make_11.to_assoc_array) t in (* 11 *)
      As_vector.Make_1N.to_assoc_array kxst

    (* Stable: *)
    let to_assoc_list t =
      Array.to_list (to_assoc_array t)

  end (* Make_11 *)


  (* ------------------- *)
  module Make_1N = struct
  (* ------------------- *)
  (* NOTA che 11 si riferisce all'ultima chiave, la prima essendo necessariamente 1N. *)

    let of_assoc_array (kks : ('k1 * ('k2 * 'a)) array) : ('k1, 'k2, 'a array) t2 =
      let kkst : ('k1, ('k2 * 'a) array) t = As_vector.Make_1N.of_assoc_array kks in
      (As_vector.map (As_vector.Make_1N.of_assoc_array) kkst)

    include Derived_constructors_up_to_10_keys(struct
      type ('k0, 'k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9) keys   = 'k0 * 'k1
      type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,  'a) source = 'k1 * 'a
      type ('k1,'k2,'k3,'k4,'k5,'k6,'k7,'k8,'k9,  'a) target = ('k1, 'a array) t  (* 1N *)
      let of_assoc_array = of_assoc_array
      let restruct_tuples (k0,k1) a = (k0, (k1, a))
      end)

    (* Stable: *)
    let to_assoc_array (t : ('k1, 'k2, 'a array) t2) : ('k1 * ('k2 * 'a)) array =
      let kxst = As_vector.map (As_vector.Make_1N.to_assoc_array) t in (* 11 *)
      As_vector.Make_1N.to_assoc_array kxst

    (* Stable: *)
    let to_assoc_list t =
      Array.to_list (to_assoc_array t)

  end (* Make_1N *)

  let get t2 k1 k2 =
    As_vector.get (As_vector.get t2 k1) k2

  let get_opt t2 k1 k2 =
    Option.bind (As_vector.get_opt t2 k1) (fun row -> As_vector.get_opt row k2)

  let map ?stable f =
    As_vector.map ?stable (As_vector.map ?stable f)

  let mapk ?stable f t2 =
    As_vector.mapk ?stable (fun k1 -> As_vector.mapk ?stable (fun k2 x -> f k1 k2 x)) t2

  let mapg ?stable f s t2 =
    As_vector.mapg ?stable (fun s k1 -> As_vector.mapg ?stable (fun s k2 x -> f s k1 k2 x) s) s t2

  let iter ?stable f =
    As_vector.iter ?stable (As_vector.iter ?stable f)

  let iterk ?stable f t2 =
    As_vector.iterk ?stable (fun k1 -> As_vector.iterk ?stable (fun k2 x -> f k1 k2 x)) t2

  let iterg ?stable f s t2 =
    As_vector.iterg ?stable (fun s k1 -> As_vector.iterg ?stable (fun s k2 x -> f s k1 k2 x) s) s t2

  let transpose (t2 : ('k1, 'k2, 'a) t2) : ('k2, 'k1, 'a) t2 =
    let khxs = Make_11.to_assoc_array t2 in
    let hkxs = Array.map (fun (k,(h,x)) -> (h,(k,x))) khxs in
    Make_11.of_assoc_array hkxs

  (* Rectangular matrix: *)
  let to_string_matrix ?empty ?(cell_size=10) ~(sok1:'k1 -> string) ~(sok2:'k2 -> string) ~(soel:'a -> string) (t2: ('k1, 'k2, 'a) t2) =
    let sub s n = try String.sub s 0 n with _ -> s in
    let empty = match empty with None -> String.make (cell_size) '/' | Some s -> s in
    (* --- *)
    let sprintf os =
      let s = (match os with None -> empty | Some s -> (sub s cell_size)) in
      Tools.Printf.sprintf ~cell_size s
    in
    (* Get all inner keys from t2: *)
    let k2s : 'k2 array = Hashset.array_uniq (Array.concat (Array.to_list (to_array (As_vector.map (Preserving_order.get_keys) t2)))) in
    (* Column headers: *)
    let k2sp = Array.map (fun k -> sprintf (Some (sok2 k))) k2s in
    let seps =
      let sep  = String.make (String.length k2sp.(0)) '-' in
      Array.map (fun _ -> sep) k2sp
    in
    (* --- *)
    let k1s : 'k1 array = Preserving_order.get_keys t2 in
    (* Row headers: *)
    let k1sp = Array.map (fun k -> sprintf (Some (sok1 k))) k1s in
    (* --- *)
    let m = Array.length k1s in
    let n = Array.length k2s in
    let matrix =
      Array.init (m+3)
        (fun i ->
           if i=0            then Array.concat [ [|sprintf (Some "")|]; k2sp] else
           if i=1 || i=(m+2) then Array.concat [ [|sprintf (Some "")|]; seps] else
           Array.init (n+1)
             (fun j ->
                if j=0 then k1sp.(i-2) else
                sprintf (Option.map soel (get_opt t2 k1s.(i-2) k2s.(j-1)))))
    in
    matrix

  (* val print : sok1:('k1 -> string) -> sok2:('k2 -> string) -> soel:('a -> string) -> ('k1, 'k2, 'a) t2 -> unit *)
  let print ?(out_channel=stdout) ?empty ?cell_size ~sok1 ~sok2 ~soel t2 =
    let m = to_string_matrix ?empty ?cell_size ~sok1 ~sok2 ~soel t2 in
    let lines = Array.map (fun cs -> String.concat " | " (Array.to_list cs)) m in
    let msg = String.concat " |\n" (Array.to_list lines) in
    Printf.kfprintf flush out_channel "%s |\n" msg

  (* ------------------------------------ *)
  module (*As_matrix.*)Horizontal = struct
  (* ------------------------------------ *)

    let lines_of_sparse
      ?no_header1 ?empty1 ?cell_size1
      ?no_header2 ?empty2 ?cell_size2
      ~(sok1:'k1 -> string)
      ~(sok2:'k2 -> string)
      ~(soel:'a -> string array)
      (t2 : ('k1, 'k2, 'a option) t2)
      : string array
      =
      As_vector.Horizontal.lines_of
        ?no_header:no_header1 ?empty:empty1 ?cell_size:cell_size1
        ~sok:sok1
        ~soel:(As_vector.Vertical.lines_of_sparse
                ?no_header:no_header2 ?empty:empty2 ?cell_size:cell_size2
                ~sok:sok2
                ~soel)
        t2

    (* --- *)

    include Make_printers_from_lines_generator
      (struct
            type ('k1,'k2, 'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0) args =
              (unit option) * (string option) * (int option) *
              (unit option) * (string option) * (int option) *
              ('k1 -> string) *
              ('k2 -> string) *
              ('a0 -> string array)

            type ('k1,'k2, 'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a) t = ('k1, 'k2, 'a) t2

            type ('k1,'k2, 'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0, 'a1, 'b) curried =
              ?no_header1:unit -> ?empty1:string -> ?cell_size1:int ->
              ?no_header2:unit -> ?empty2:string -> ?cell_size2:int ->
              sok1:('k1 -> string) ->
              sok2:('k2 -> string) ->
              soel:('a0 -> string array) ->
              ('k1, 'k2, 'a1) t2 -> 'b

            (* Uncurrying the curried generator: *)
            let lines_of_sparse ((no_header1, empty1, cell_size1, no_header2, empty2, cell_size2, sok1, sok2, soel) as _args) t2 =
                lines_of_sparse ?no_header1 ?empty1 ?cell_size1 ?no_header2 ?empty2 ?cell_size2 ~sok1 ~sok2 ~soel t2

            let map f t2 = map ?stable:None f t2

            let currying (arrow)
              ?no_header1 ?empty1 ?cell_size1 ?no_header2 ?empty2 ?cell_size2 ~sok1 ~sok2 ~soel
              = arrow (no_header1, empty1, cell_size1, no_header2, empty2, cell_size2, sok1, sok2, soel)
      end)

      (* Adjust signatures (remove the optional argument ?empty): *)
      let string_of = string_of ?empty1:None ?empty2:None
      let print     = print     ?empty1:None ?empty2:None

  end (* As_matrix.Horizontal *)

  (* ------------------------------------ *)
  module (*As_matrix.*)Vertical = struct
  (* ------------------------------------ *)

    let lines_of_sparse
      ?no_header1 ?empty1 ?cell_size1
      ?no_header2 ?empty2 ?cell_size2
      ~(sok1:'k1 -> string)
      ~(sok2:'k2 -> string)
      ~(soel:'a -> string array)
      (t2 : ('k1, 'k2, 'a option) t2)
      : string array
      =
      As_vector.Vertical.lines_of
        ?no_header:no_header1 ?empty:empty1 ?cell_size:cell_size1
        ~sok:sok1
        ~soel:(As_vector.Horizontal.lines_of_sparse
                ?no_header:no_header2 ?empty:empty2 ?cell_size:cell_size2
                ~sok:sok2
                ~soel)
        t2

    (* --- *)

    include Make_printers_from_lines_generator
      (struct
            type ('k1,'k2, 'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0) args =
              (unit option) * (string option) * (int option) *
              (unit option) * (string option) * (int option) *
              ('k1 -> string) *
              ('k2 -> string) *
              ('a0 -> string array)

            type ('k1,'k2, 'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a) t = ('k1, 'k2, 'a) t2

            type ('k1,'k2, 'b3,'b4,'b5,'b6,'b7,'b8,'b9,'b10, 'a0, 'a1, 'b) curried =
              ?no_header1:unit -> ?empty1:string -> ?cell_size1:int ->
              ?no_header2:unit -> ?empty2:string -> ?cell_size2:int ->
              sok1:('k1 -> string) ->
              sok2:('k2 -> string) ->
              soel:('a0 -> string array) ->
              ('k1, 'k2, 'a1) t2 -> 'b

            (* Uncurrying the curried generator: *)
            let lines_of_sparse ((no_header1, empty1, cell_size1, no_header2, empty2, cell_size2, sok1, sok2, soel) as _args) t2 =
                lines_of_sparse ?no_header1 ?empty1 ?cell_size1 ?no_header2 ?empty2 ?cell_size2 ~sok1 ~sok2 ~soel t2

            let map f t2 = map ?stable:None f t2

            let currying (arrow)
              ?no_header1 ?empty1 ?cell_size1 ?no_header2 ?empty2 ?cell_size2 ~sok1 ~sok2 ~soel
              = arrow (no_header1, empty1, cell_size1, no_header2, empty2, cell_size2, sok1, sok2, soel)
      end)

      (* Adjust signatures (remove the optional argument ?empty): *)
      let string_of = string_of ?empty1:None ?empty2:None
      let print     = print     ?empty1:None ?empty2:None

  end (* As_matrix.Vertical *)

  (* --- *)
(*  val append  : ('k, 'a) t -> ('k, 'a) t -> ('k, 'a) t
  (* --- Permutations: *)
  val sort    : ?stable:unit -> ?compare:('a compare) -> ('k, 'a) t -> ('k, 'a) t
  val shuffle : ('k, 'a) t -> ('k, 'a) t
  val reverse : ('k, 'a) t -> ('k, 'a) t
  val swap    : ('k * 'k) list -> ('k, 'a) t -> ('k, 'a) t
  (* --- *)
  (* --- Partitions: *)
  (* Ordinary and generalized (with keys and state) constructors: *)
  val partition  : ('a -> 'c) -> ('k, 'a) t -> ('c, 'k, 'a) tt
  val refinement : ('a -> 'c) -> ('k, 'a) t -> ('k, 'c, 'a) tt *)

(*  val partitioni : ?outer_size:int -> ?min_outer_size:int -> (index -> 'a -> class_index) -> 'a t -> 'a tt * play
  val partitiong : ?outer_size:int -> ?min_outer_size:int -> ('s -> index -> 'a -> class_index * 's) -> 's -> 'a t -> 'a tt * play*)

end


module Testing = struct
let x1 = As_array.init 5 (fun i -> Char.chr (65+i)) ;;
let x2 = As_array.init 5 (fun i -> Char.chr (97+i)) ;;
let x1' = As_vector.reverse x1 ;;
let x2' = As_vector.reverse x2 ;;
(* --- *)
let y1 = As_vector.append x1  x2  ;;
let y2 = As_vector.append x1  x2'  ;;
let y3 = As_vector.append x1' x2 ;;
let y4 = As_vector.append x1' x2' ;;

let z1 () = (As_vector.map (fun c -> Printf.printf "%c\n" c; Char.escaped c) y4) ;;
let z2 () = (As_vector.map ~stable:() (fun c -> Printf.printf "%c\n" c; Char.escaped c) y4) ;;

end

(*
open Ind;;
open Testing ;;
let bis = As_vector.partition  (fun x -> (Char.code x) < 97) y1 ;;
let ibs = As_vector.refinement (fun x -> (Char.code x) < 97) y1 ;;

As_matrix.print ~cell_size:5 ~sok1:(string_of_int) ~sok2:(Printf.sprintf "%b") ~soel:(Char.escaped) ibs ;;

      |  true | false |
      | ----- | ----- |
    0 |     A | ///// |
    1 |     B | ///// |
    2 |     C | ///// |
    3 |     D | ///// |
    4 |     E | ///// |
    5 | ///// |     a |
    6 | ///// |     b |
    7 | ///// |     c |
    8 | ///// |     d |
    9 | ///// |     e |
      | ----- | ----- |

As_matrix.print ~cell_size:5 ~sok2:(string_of_int) ~sok1:(Printf.sprintf "%b") ~soel:(Char.escaped) bis ;;

      |     0 |     1 |     2 |     3 |     4 |     5 |     6 |     7 |     8 |     9 |
      | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- |
 true |     A |     B |     C |     D |     E | ///// | ///// | ///// | ///// | ///// |
false | ///// | ///// | ///// | ///// | ///// |     a |     b |     c |     d |     e |
      | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- |

let bis' = As_vector.group (fun k x -> k<2 && (Char.code x) < 97) y1 ;;
As_matrix.print ~cell_size:5 ~sok2:(string_of_int) ~sok1:(Printf.sprintf "%b") ~soel:(Char.escaped) bis' ;;

      |     0 |     1 |     2 |     3 |     4 |     5 |     6 |     7 |     8 |     9 |
      | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- |
 true |     A |     B | ///// | ///// | ///// | ///// | ///// | ///// | ///// | ///// |
false | ///// | ///// |     C |     D |     E |     a |     b |     c |     d |     e |
      | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- |

  let bis' = As_vector.group_stable (fun k x -> k mod 2 = 0 && (Char.code x) < 97) y1 ;;
  let bis'' = As_vector.map (As_vector.reverse) bis' ;;
  let y1''= As_vector.ungroup_stable bis'' ;;
  As_vector.Make_11.to_assoc_array y1'' ;;
  - : (int * char) array =
  [|(2, 'C'); (1, 'B'); (0, 'A'); (9, 'e'); (8, 'd'); (7, 'c'); (6, 'b'); (5, 'a'); (4, 'E'); (3, 'D')|]
let bis3 = As_vector.reverse bis'' ;;
let y3 = As_vector.ungroup_stable bis3 ;;


As_matrix.Vertical.print (*~cell_size:5*) ~sok1:(Printf.sprintf "%b") ~sok2:(string_of_int) ~soel:(fun x -> [|Char.escaped x|]) bis ;;

*)

(*
     |===================================================================================|
     |       9       8       7       6       5       3       1       4       2       0   |
     | | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | |
     | |     B |     D |     a |     b |     c |     d |     e | ///// | ///// | ///// | |
     | | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | |
     |===================================================================================|

     |===================================================================================|
     |       9       8       7       6       5       3       1       4       2       0   |
     | | ----- + ----- + ----- + ----- + ----- + ----- + ----- + ----- + ----- + ----- | |
     | |     B |     D |     a |     b |     c |     d |     e | ///// | ///// | ///// | |
     | | ----- + ----- + ----- + ----- + ----- + ----- + ----- + ----- + ----- + ----- | |
     |===================================================================================|

     |-----------------------------------------------------------------------------------|
     |       9       8       7       6       5       3       1       4       2       0   |
     | | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | |
     | |     B |     D |     a |     b |     c |     d |     e | ///// | ///// | ///// | |
     | | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | |
     |-----------------------------------------------------------------------------------|


utop # As_matrix.Vertical.print ~cell_size1:40 ~cell_size2:6 ~sok1:(Printf.sprintf "%b") ~sok2:(string_of_int) ~soel:(fun x -> [|Char.escaped x; "YYYY"|]) bis ;;
      | ---------------------------------------- |                                                                                                                                    true |        0        1        2        3   .. |                                                                                                                                         | | ------ | ------ | ------ | ------ | .. |
      | |      A |      B |      C |      D | .. |
      | |   YYYY |   YYYY |   YYYY |   YYYY | .. |
      | | ------ | ------ | ------ | ------ | .. |
      | ---------------------------------------- |
false |                             8        9   |
      |                      | ------ | ------ | |
      |                      |      d |      e | |
      |                      |   YYYY |   YYYY | |
      |                      | ------ | ------ | |
      | ---------------------------------------- |
- : unit = ()
─( 22:40:46 )─< command 17 >──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────{ counter: 0 }─
utop # As_matrix.Vertical.print ~cell_size1:80 ~cell_size2:6 ~sok1:(Printf.sprintf "%b") ~sok2:(string_of_int) ~soel:(fun x -> [|Char.escaped x; "YYYY"|]) bis ;;
      | -------------------------------------------------------------------------------- |
 true |               0        1        2        3        4        5        6        7   |                                                                                                 |
               | ------ | ------ | ------ | ------ | ------ | ------ | ------ | ------ | |
      |        |      A |      B |      C |      D |      E |      a |      b |      c | |
      |        |   YYYY |   YYYY |   YYYY |   YYYY |   YYYY |   YYYY |   YYYY |   YYYY | |
      |        | ------ | ------ | ------ | ------ | ------ | ------ | ------ | ------ | |
      | -------------------------------------------------------------------------------- |
false |                                                                     8        9   |
      |                                                              | ------ | ------ | |
      |                                                              |      d |      e | |
      |                                                              |   YYYY |   YYYY | |
      |                                                              | ------ | ------ | |
      | -------------------------------------------------------------------------------- |
- : unit = ()

*)


