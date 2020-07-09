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

(*  "Resistance", i.e. references that may resist to updates and closed w.r.t to the
    cartesian product.
    ---
    The resistance is based on the notion of "review" which is a generalization of
    the notion of set's indicator functions. Actually, more than return a bool,
    the internal "reviewer" of a resistance may impose itself a "revision", i.e.
    a patch, before to update the resistance.
    ---
    This kind of control is not a mathematician's caprice: in the context of threads
    concurrency, it could be useful to automatically "lift" values written by a
    "writer" to a domain accessible only with more elevated rights (for instance
    by a "mantainer").
*)

IFNDEF OCAML4_03_OR_LATER THEN
type ('a, 'b) result = Ok of 'a | Error of 'b
ENDIF

(* A review is more than the boolean result of the indicator function of a set.
   It express, of course, the boolean case "accepted"/"rejected", but, when the
   value is accepted, it may express the revision that has been applied to the
   value to render it acceptable. Hence, review belongs one of three cases:
   ---
   Error (exn) : 'a t  => false, i.e. "rejected" with comments in exn
   Ok None     : 'a t  => true, "accepted" as is
   Ok Some v   : 'a t  => true, accepted but "revised" to v
   ---
   *)
type 'a review = ('a option, exn) result

(* Review constructors: *)
val accepted : unit -> 'a review
val rejected : ?comment:string -> unit -> 'a review
val revised  : 'a -> 'a review

(* A "reviewer" organize the "resistance" of a structure that encapsules a value of type 'a.
   It takes two arguments, the current value and the aimed update, then returns his verdict
   in the form of a review:
   Example:
     let reviewer = fun _ v -> if v>100 then Res.rejected ">100" else if (v mod 2 = 0) then Res.accepted () else Res.revised (v+1) ;;
   *)
type 'a reviewer = 'a -> 'a -> 'a review

(* ---------------------------- *)
(*         Constructors         *)
(* ---------------------------- *)

(* The type of resistances: *)
type 'a t

(* Constructors: *)
val return  : ?reviewer:('a reviewer) -> 'a -> 'a t
(* --- *)
(* Note that `map' has no reviewer attached because the update imposed by the function is non-negotiable.
   The `equality' (by default structural) is used to weakly memoize the provided function: *)
val map     : ?equality:('a -> 'a -> bool) (*(=)*) -> ('a -> 'b) -> 'a t -> 'b t
(* --- *)
val product : ?reviewer:('a * 'b) reviewer -> 'a t -> 'b t -> ('a * 'b) t
val fst     : ?reviewer:('a reviewer) -> ('a * 'b) t -> 'a t
val snd     : ?reviewer:('b reviewer) -> ('a * 'b) t -> 'b t
val split   : ?fst_reviewer:('a reviewer) -> ?snd_reviewer:('b reviewer) -> ('a * 'b) t -> ('a t) * ('b t)
(* --- *)
(* Add a reviewer to an existing resistance.
    ---
    Note that `cover' adds an object layer to the provided object.
    For the sake of performance, all operators (return, product, fst_prj, snd_prj, split)
    integrate the possibility to add a reviewer immediately, in the same layer introduced
    by the operator to do its job. This option avoids the creation of too many additional
    layers: *)
val cover   : 'a t -> 'a reviewer -> 'a t

(* ---------------------------- *)
(*           Methods            *)
(* ---------------------------- *)

(* An "update" is a function that proposes a new value from an older:*)
type 'a update = 'a -> 'a

(* After an attempt to write a resistance, it may be interesting to detect if
   the internal state of the structure was really changed. The 1st boolean component
   says if there was a change in sense of physical ("shallow") equality. Forcing the
   2nd boolean component, we can obtain the same information but in sense of
   the structural ("deep") equality: *)
type status = (bool * bool lazy_t)

(* Methods: *)
val get : 'a t -> 'a

(*  The 2nd argument of aim is a function ('a -> 'a) that takes
    the current value v0 of the resistance to propose an update v1.
    ---
    The review related part of the result, may be:
    Error (exn)  =>  error, not accepted
    Ok Left  v2  =>  proposal accepted but patched (v1 replaced by v2)
    Ok Right v1  =>  proposal accepted as is, without revision *)
val aim : 'a t -> ('a update) -> 'a * ('a review * status)

(* ---------------------------- *)
(*      `aim' instances         *)
(* ---------------------------- *)

(* Simplified versions of `aim' *)

(* Anachronistic and illusory ;-)
   set x v = aim x (fun _ -> v) |> ignore *)
val set : 'a t -> 'a -> unit

(* aim_succeed t f = aim t f |> Review.to_bool *)
val aim_succeed : 'a t -> ('a update) -> bool

(* aim_ignore t f = aim t f |> ignore *)
val aim_ignore  : 'a t -> ('a update) -> unit

(* The result, if any (Some), is the current value of
   the resistance, after the update and a possible revision.
   The result is None iff the update has been rejected. *)
val aim_option  : 'a t -> ('a update) -> 'a option

(* Both services of `aim_option' and `aim_status' integrated in an
   unique tool: *)
val aim_option_status : 'a t -> ('a update) -> 'a option * status

(* ---------------------------- *)
(*           Compare            *)
(* ---------------------------- *)

(* Oo.id *)
val get_id : 'a t -> int

(* compare = oldest (i.e. compare by object identifiers) *)
val compare : 'a t -> 'a t -> int

(* ---------------------------- *)
(*      Method application      *)
(* ---------------------------- *)

(* Trivial pattern added for completeness.
   May be interesting because of flipped arguments.
   apply_ro t f = f (get t) *)
val apply_ro  : 'a t -> ('a -> 'b) -> 'b

(* Apply a function to the data encapsulated by the resistance.
   The method is structured in two stages: the first stage produce
   a value aimed to be the resistance update. The second stage consider
   the real occurred update and its related revision to produce the result: *)
val picky_rw : 'a t -> ('a -> 'a * ('a * ('a review * status) -> 'b)) -> 'b

(* Simplified version: the continuation forgets review and status: *)
val apply_rw : 'a t -> ('a -> 'a * ('a -> 'b)) -> 'b

(* Some trivial induced definitions: apply a function as if the resistance was an object
   (with an additional parameter (b), which represents the input(s) of the method).
   ---
   picky_rw_meth f t b = picky_rw t (fun a -> f a b)
   apply_rw_meth f t b = apply_rw t (fun a -> f a b)
   ---
   *)
val picky_rw_meth : ('a -> 'b -> 'a * ('a * ('a review * status) -> 'c)) -> 'a t -> 'b -> 'c
val apply_rw_meth : ('a -> 'b -> 'a * ('a -> 'c)) -> 'a t -> 'b -> 'c

(* ---------------------------- *)
(*            Review            *)
(* ---------------------------- *)

module Review :
  sig
    (* --- *)
    type 'a t = 'a review
    type 'a h = [ `Error of exn | `Accepted | `Revised of 'a ]
    (* --- *)
    val to_bool : 'a t -> bool
    val fst : ('a * 'b) t -> 'a t
    val snd : ('a * 'b) t -> 'b t
    val human_readable : 'a t -> 'a h
    (* --- *)
    val map : ('a -> 'b) -> 'a t -> 'b t
    (* --- *)
  end (* Review *)

(* aim_human t f = aim t f |> Review.human_readable *)
val aim_human : 'a t -> ('a update) -> 'a Review.h

(* ---------------------------- *)
(*           Reviewer           *)
(* ---------------------------- *)

module Reviewer :
  sig
    type 'a t = 'a -> 'a -> 'a review
    (* --- *)
    (* Protect from exceptions (and translate exceptions into "rejected"): *)
    val return : ('a -> 'a -> 'a review) -> 'a t
    (* --- *)
    val compose : 'a t -> 'a t -> 'a t
    val product : 'a t -> 'b t -> ('a * 'b) t
    (* --- *)
    val product_of_optional_reviewer : ('a t) option -> ('b t) option -> (('a * 'b) t) option
    (* --- *)
    (* Extend a reviewer to deal with optional values. The reviewer is activated only when both values (old and new)
       are defined (Some). Otherwise, the default review is returned:  *)
    val option_lift : ?default:('a option) review -> ('a reviewer) -> ('a option) reviewer
    (* --- *)
    (* Lift reviewers that ignore their first argument (the initial value) and take their
       decision looking only to the value proposed as update: *)
    val option_lift_snd : ?default:('a option) review -> ('a reviewer) -> ('a option) reviewer
  end

(* ---------------------------- *)
(*      Integer resistances     *)
(* ---------------------------- *)

(* Note that `incr' and `ppi' may fail (because of resistance, i.e. the indicator function): *)
val incr : int t -> bool  (* aim t (fun v -> v+1) |> Review.to_bool *)
val decr : int t -> bool  (* aim t (fun v -> v-1) |> Review.to_bool *)
(* --- *)
(* May be the simplest examples of tools that need the pattern `rw_apply' instead of `aim': *)
val ppi : int t -> int         (* ++i *)
val ipp : int t -> int         (* i++ *)
val mmi : int t -> int         (* --i *)
val imm : int t -> int         (* i-- *)

(* ---------------------------- *)
(*          Toolkit             *)
(* ---------------------------- *)

(** Just for fun: opening this module you redefine the standard [ref], [!] and [:=]
    in order to operate on this kind of structure instead of standard references. *)
module Toolkit :
  sig
    val ref : ?reviewer:('a reviewer) -> 'a -> 'a t
    val ( ! )  : 'a t -> 'a
    val ( := ) : 'a t -> 'a -> unit
    val incr   : int t -> unit
    val decr   : int t -> unit
    val ppi    : int t -> int   (* ++i *) (* unprotected *)
    val ipp    : int t -> int   (* i++ *)
    val mmi    : int t -> int   (* --i *) (* unprotected *)
    val imm    : int t -> int   (* i-- *)
  end


(* ---------------------------- *)
(*      Low-level access        *)
(* ---------------------------- *)

module Exposed :
  sig
    type 'a t
    val return  : ?reviewer:('a -> 'a -> 'a review) -> 'a -> 'a t
    val get     : 'a t -> 'a
    val aim     : 'a t -> ('a -> 'a) -> 'a * ('a review * status)
    (* --- *)
    val map     : ?equality:('a -> 'a -> bool) -> ('a -> 'b) -> 'a t -> 'b t
    val cover   : 'a t -> ('a -> 'a -> 'a review) -> 'a t
    val product : ?reviewer:('a * 'b) reviewer -> 'a t -> 'b t -> ('a * 'b) t
    val fst_prj : ?reviewer:'a reviewer -> ('a * 'b) t -> 'a t
    val snd_prj : ?reviewer:'b reviewer -> ('a * 'b) t -> 'b t
    val split   : ?fst_reviewer:'a reviewer -> ?snd_reviewer:'b reviewer -> ('a * 'b) t -> 'a t * 'b t
    val compare : 'a t -> 'a t -> int
    (* --- Low level control: *)
    type control = commits_no * status
     and commits_no = int
     (* --- *)
    val stable  : 'a t -> bool
    val id      : 'a t -> int
    val commit  : 'a t -> (exn, 'a * control) Either.t
    val commit_or_warning : 'a t -> control
    val commits_no : 'a t -> int
  end

(* ---------------------------- *)
(*    Example n°1 (integers)    *)
(* ---------------------------- *)

(* ---
(* No more than 100, odd integers patched to the next even: *)
let reviewer = fun _ v -> if v>100 then Res.rejected ~comment:">100" () else if (v mod 2 = 0) then Res.accepted () else Res.revised (v+1) ;;
(* val reviewer : 'a -> int -> (int option, unit) result *)

let x = Res.return ~reviewer 171 ;;
(* Exception: Invalid_argument "Res.return: initial value rejected".*)

let x = Res.return ~reviewer 11 ;;
(* val x : int t = <abstr> *)

Res.get x ;;
(* - : int = 12 *)

let x' = Res.map (string_of_int) x ;;
(* val x' : string Res.t = <abstr> *)

Res.get x' ;;
(* - : string = "12" *)

Res.aim x (fun v -> v+100) ;;
(* - : int * (int Res.review * Res.status) = (112, (Error (Failure ">100"), (false, <lazy>))) *)

Res.aim_human x (fun v -> v+100) ;;
(* - : int Res.Review.h = `Error (Failure ">100") *)

Res.aim_human x (fun v -> v*2) ;;
(* - : int Res.Review.h = `Accepted *)

Res.get x' ;;
(* - : string = "24" *)

Res.aim_human x (fun v -> v/7) ;;
(* - : int Res.Review.h = `Revised 4 *)

open Res.Toolkit;;

x := !x + 4 ;;
(* - : unit = () *)

let y = ref ~reviewer 51 ;;
(* val y : int t = <abstr> *)

!y ;;
(* - : int = 52 *)

let z = Res.product x y ;;
(* val z : (int * int) t = <abstr> *)

!z ;;
(* - : int * int = (8, 52) *)

z := (10, 62) ;;
(* - : unit = () *)

!z ;;
(* - : int * int = (10, 62) *)

z := (11, 63) ;;
(* - : unit = () *)

!z ;;
(* - : int * int = (12, 64) *)

x := 22;;
(* - : unit = () *)

!z ;;
(* - : int * int = (22, 64) *)

x:=1000;;
(* - : unit = () *)

!z ;;
(* - : int * int = (22, 64) *)

z := (44, 1000) ;;
(* - : unit = () *)

!z ;;
(* - : int * int = (22, 64) *)

z := (43, 99) ;;
(* - : unit = () *)

!z ;;
(* - : int * int = (44, 100) *)

incr y;;
(* - : unit = () *)

!z ;;
(* - : int * int = (44, 100) *)

incr x ;;
(* - : unit = () *)

!z ;;
(* - : int * int = (46, 100) *)

!x' ;;
(* - : string = "46" *)

let x' = Res.map (fun v -> Misc.pr "Updating x'\n"; string_of_int v) x ;;
(* --
Extreme_sharing: weakly_memoize: FAULT
Updating x'
val x' : string Res.t = <abstr>
*)

incr x;;
(* - : unit = () *)

incr x;;
(* - : unit = () *)

incr x;;
(* - : unit = () *)

!x' ;;
(* ---
Extreme_sharing: weakly_memoize: FAULT
Updating x'
- : string = "52"
*)

*)

(* ---------------------------- *)
(*    Example n°2 (channels)    *)
(* ---------------------------- *)

(* ---
(* In channels ('a option) overwrites are forbidden because the message must be received before leaving place for the next one: *)
let forbid_overwrite v0 v1 =
  match (v0,v1) with
  | Some x0, Some x1 when x0 <> x1 -> Res.rejected ~comment:"overwrite forbidden" ()
  | _, _ -> Res.accepted ()
;;
(* val forbid_overwrite : 'a option -> 'a option -> 'b review *)

(* Equivalent definition: *)
let forbid_overwrite ox0 ox1  = Res.Reviewer.option_lift (fun x0 x1 ->
  if x0 <> x1 then Res.rejected ~comment:"overwrite forbidden" () else Res.accepted ())
  ox0 ox1
;;
(* val forbid_overwrite : 'a option -> 'a option -> 'a option Res.review *)

(* No more than 100, odd integers patched to the next even: *)
let accept_even_le_100 = fun _ v -> if v>100 then Res.rejected ~comment:">100" () else if (v mod 2 = 0) then Res.accepted () else Res.revised (v+1) ;;
(* val accept_even_le_100 : 'a -> int -> int review *)

(* No more than 100, even integers patched to the next odd: *)
let accept_odd_le_100 = fun _ v -> if v>100 then Res.rejected ~comment:">100" () else if (v mod 2 = 1) then Res.accepted () else Res.revised (v+1) ;;
(* val accept_odd_le_100 : 'a -> int -> int review *)

let rx = Res.Reviewer.compose (forbid_overwrite) (Res.Reviewer.option_lift_snd accept_even_le_100) ;;
(* val rx : int option Res.Reviewer.t *)

rx (None) (Some 100) |> Res.Review.human_readable  ;;
(* - : int option Res.Review.h = `Accepted *)

rx (None) (Some 120) |> Res.Review.human_readable  ;;
(* - : int option Res.Review.h = `Error (Failure ">100") *)

rx (Some 100) (Some 90) |> Res.Review.human_readable  ;;
(* - : int option Res.Review.h = `Error (Failure "overwrite forbidden") *)

let ry = Res.Reviewer.compose (forbid_overwrite) (Res.Reviewer.option_lift_snd accept_odd_le_100) ;;
(* val ry : int option Res.Reviewer.t *)

let x = Res.return ~reviewer:(rx) None ;;
(* val x : int option Res.t *)

let y = Res.return ~reviewer:(ry) None ;;
(* val y : int option Res.t *)

Res.aim_human x (fun _ -> Some 10);;
(* - : int option Res.Review.h = `Accepted *)

Res.aim_human x (fun _ -> Some 12);;
(* - : int option Res.Review.h = `Error (Failure "overwrite forbidden") *)

Res.aim_human x (fun _ -> None);;
(* - : int option Res.Review.h = `Accepted *)

Res.aim_human y (fun _ -> Some 10);;
(* - : int option Res.Review.h = `Revised (Some 11) *)

Res.aim_human y (fun _ -> Some 13);;
(* - : int option Res.Review.h = `Error (Failure "overwrite forbidden") *)

let xy = Res.product x y ;;
(* val xy : (int option * int option) Res.t = <abstr> *)

let x' = Res.fst xy ;;
(* val x' : int option Res.t = <abstr> *)

x' = x ;;
(* - : bool = true *)

x' == x ;;
(* - : bool = true *)

let y' = Res.snd xy ;;
(* val y' : int option Res.t = <abstr> *)
y' = y, y' == y ;;
(* - : bool * bool = (true, true) *)

x' = y', x = y ;;
(* - : bool * bool = (false, false) *)

let z : (int*int) option Res.t = Res.return None ;;
(* val z : (int * int) option Res.t = <abstr> *)

Option.combine (Some "abc") (Some 3.14) ;;
(* - : (string * float) option = Some ("abc", 3.14) *)

let xy_z = Res.product ~reviewer:(fun ((x0,y0),z0) ((x1,y1),z1) ->
  if (z1=None) && (x1<>None) && (y1<>None) then Res.revised ((None,None), Option.combine x1 y1) else Res.accepted ()) xy z ;;
(* val xy_z : ((int option * int option) * (int * int) option) Res.t = <abstr> *)

open Res.Toolkit ;;

!xy_z ;;
(* - : (int option * int option) * (int * int) option = ((None, Some 11), None) *)

x := Some 34 ;;
(* - : unit = () *)

!xy_z ;;
(* - : (int option * int option) * (int * int) option = ((None, None), Some (34, 11)) *)

let xy = Res.fst xy_z ;;
(* val xy : (int option * int option) Res.t = <abstr> *)

!xy ;;
(* - : int option * int option = (None, None) *)

let x', y' = Res.split xy ;;
(* val x : int option Res.t = <abstr> *)
(* val y : int option Res.t = <abstr> *)

let z' = Res.snd xy_z ;;
(* val z : (int * int) option Res.t *)

(* NOTE: old names x,y,z used as components to build xy_z, are not *covered* by x', y' and z'.
   All these new symbols are projections, or "views", of the monolitic group xy_z. *)

Res.aim_human x (fun _ -> Some 77) ;;
(* - : int option Res.Review.h = `Revised (Some 78) *)

!xy_z ;;
(* - : (int option * int option) * (int * int) option = ((Some 78, None), Some (34, 11)) *)

(* But we can also use the "view" y' instead of the "component" y: *)
Res.aim_human y' (fun _ -> Some 78) ;;
(* - : int option Res.Review.h = `Revised (Some 79) *)

!xy_z ;;
(* - : (int option * int option) * (int * int) option = ((Some 78, Some 79), Some (34, 11)) *)

Res.aim_human y (fun _ -> Some 81) ;;
(* - : int option Res.Review.h = `Error (Failure "overwrite forbidden") *)

!xy_z ;;
(* - : (int option * int option) * (int * int) option = ((Some 78, Some 79), Some (34, 11)) *)

z:= None ;;
(* - : unit = () *)

!xy_z ;;
(* - : (int option * int option) * (int * int) option = ((None, None), Some (78, 79)) *)

*)
