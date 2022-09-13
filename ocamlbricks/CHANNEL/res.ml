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

IFNDEF OCAML4_03_OR_LATER THEN
type ('a, 'b) result = Ok of 'a | Error of 'b
ENDIF

(* --- *)
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
let accepted () = Ok None
let rejected ?(comment="rejected") () = Error (Failure comment)
let revised v  = Ok (Some v)

module Log = Ocamlbricks_log

(* A "reviewer" organize the "resistance" of a structure that encapsules a value of type 'a.
   It takes two arguments, the current value and the aimed update, then returns his verdict
   in the form of a review:
   Example:
     let reviewer = fun _ v -> if v>100 then Res.rejected ~comment:">100" () else if (v mod 2 = 0) then Res.accepted () else Res.revised (v+1) ;;
   *)
type 'a reviewer = 'a -> 'a -> 'a review

(* An "update" is a function that proposes a new value from an older: *)
type 'a update = 'a -> 'a

(* ---------------------------- *)
(*            Review            *)
(* ---------------------------- *)

module Review = struct

  type 'a t = 'a review
  type 'a h = [ `Error of exn | `Accepted | `Revised of 'a ]

  (* val to_bool : 'a t -> bool *)
  let to_bool = function
  | Error _ -> false
  | Ok _ -> true

  let fst (r : ('a * 'b) review) : 'a review =
    match r with
    | Error e -> Error e
    | Ok None -> Ok None
    | Ok (Some (a,b)) -> Ok (Some a)

  let snd (r : ('a * 'b) review) : 'b review =
    match r with
    | Error e -> Error e
    | Ok None -> Ok None
    | Ok (Some (a,b)) -> Ok (Some b)

  (* Private method, used by Exposed.fst_prj and Exposed.snd_prj to
     deal with "official" and "actual" reviewers: *)
  let interpose ~v1 ~(action: 'a -> unit) (r: 'a review) : 'a review =
    match r with
    | Error e      -> r                         (* don't perform the action *)
    | Ok None      -> let () = action v1 in r   (* perform the action on accepted value *)
    | Ok (Some v2) -> let () = action v2 in r   (* perform the action on patched value *)

  (* --- *)
  (* val human_readable : 'a t -> [ `Error of exn | `Accepted | `Revised of 'a ] *)
  let human_readable : 'a t -> 'a h = function
  | Error e      -> `Error e
  | Ok (Some a)  -> `Revised a
  | Ok (None)    -> `Accepted

  let map (f:'a -> 'b) (r : 'a review) : 'b review =
    match r with
    | Error e -> Error e
    | Ok None -> Ok None
    | Ok (Some a) -> Ok (Some (f a))

end (* Review *)

(* ---------------------------- *)
(*           Reviewer           *)
(* ---------------------------- *)

module Reviewer = struct

  type 'a t = 'a reviewer

 (* Protect from exceptions: *)
 let return (f : 'a -> 'a -> 'a review) : 'a reviewer =
   fun a0 a1 ->
     try (f a0 a1)
     with e -> Error e (* exception => rejected *)

 (* Compose protected reviewer (compose revisions): *)
 let compose (f1:'a reviewer) (f2:'a reviewer) : 'a reviewer =
   fun a0 a1 ->
     match f1 a0 a1 with
     | ((Error _) as e1) -> e1           (* 1st reviewer has rejected the update *)
     | Ok a1' ->                         (* 1st reviewer has accepted or revised the update => continue: *)
     (* --- *)
     let a2, revised_by_1st = match a1' with None -> (a1, false) | Some a2 -> (a2, true) in
     match f2 a0 a2 with                 (* same a0, a2 instead of a1 *)
     | ((Error _) as e2) -> e2           (* 2nd reviewer has rejected the update *)
     | Ok a2' ->                         (* 2nd reviewer has accepted or revised the update => continue: *)
     (* --- *)
     let a3, revised_by_2nd = match a2' with None -> (a2, false) | Some a3 -> (a3, true) in
     (* --- *)
     if not revised_by_2nd then
       (if revised_by_1st then (Ok (Some a3))    (* revised  *)
                          else (Ok None))        (* accepted *)
     (* --- *)
     else (* continue in the case revised_by_2nd: *)
     (* --- *)
     (* Is the first reviewer agreed? well, we ask him: *)
     match f1 a0 a3 with
     | ((Error _) as e1) -> e1           (* disagreed => rejected *)
     | Ok None -> Ok (Some a3)           (* ok, it full accepts this 2nd revision => revised *)
     | Ok (Some a4) ->                   (* disagreed and proposes a 3th revision => rejected *)
         Error (Failure "reviewers conflict")

 let compose_optional_reviewers (f1:('a reviewer) option) (f2:('a reviewer) option) : ('a reviewer) option =
   match f1, f2 with
   | None, None -> None
   | Some _, None -> f1
   | None, Some _ -> f2
   | Some f1, Some f2 -> Some (compose f1 f2)

 (* Product of protected reviewers (product of revisions): *)
 let product (f1:'a reviewer) (f2:'b reviewer) : ('a * 'b) reviewer =
   fun (a0, b0) (a1, b1) ->
     match f1 a0 a1 with
     | ((Error _) as e1) -> e1           (* 1st reviewer has rejected the update *)
     | Ok a1' ->                         (* 1st reviewer has accepted or revised the update => continue: *)
     (* --- *)
     match f2 b0 b1 with
     | ((Error _) as e2) -> e2           (* 2nd reviewer has rejected the update *)
     | Ok b1' ->                         (* 2nd reviewer has accepted or revised the update => continue: *)
     (* --- *)
     match (a1', b1') with
     | None, None       -> Ok (None)            (* accepted *)
     | None, Some b2    -> Ok (Some (a1, b2))   (* revised (2nd) *)
     | Some a2, None    -> Ok (Some (a2, b1))   (* revised (1st) *)
     | Some a2, Some b2 -> Ok (Some (a2, b2))   (* revised (both) *)

 (* --- *)
 let product_of_optional_reviewer (f1:('a reviewer) option) (f2:('b reviewer) option) : (('a * 'b) reviewer) option =
   match f1, f2 with
   | None, None -> None
   (* --- *)
   | Some f1, None ->
      let result = (fun (a0, b0) (a1, b1) ->
        match f1 a0 a1 with
        | ((Error _) as e1) -> e1             (* 1st reviewer has rejected the update *)
        | Ok None -> Ok None                  (* 1st reviewer has accepted the update *)
        | Ok (Some a2) -> Ok (Some (a2, b1))  (* 1st reviewer has revised the update *)
        )
      in
      Some (result)
   (* --- *)
   | None, Some f2 ->
      let result = (fun (a0, b0) (a1, b1) ->
        match f2 b0 b1 with
        | ((Error _) as e1) -> e1             (* 2nd reviewer has rejected the update *)
        | Ok None -> Ok None                  (* 2nd reviewer has accepted the update *)
        | Ok (Some b2) -> Ok (Some (a1, b2))  (* 2nd reviewer has revised the update *)
        )
      in
      Some (result)
   (* --- *)
   | Some f1, Some f2 -> Some (product f1 f2)

 (* --- *)

 (* Apply update without a reviewer: *)
 let apply_update ~(update: 'a -> 'a) ~(v0:'a) : 'a (*v1*) * 'a review =
    match Either.protect (update) (v0) with
    | Either.Left (exn) -> (v0, Error exn)          (* rejected *)
    | Either.Right v1   -> (v1, Ok None)            (* v1 immediately accepted *)

 let compose_update_reviewer (reviewer:'a reviewer) ~(update: 'a -> 'a) ~(v0:'a) : 'a (*v1*) * 'a review =
    (* --- *)
    match Either.protect (update) (v0) with
    | Either.Left (exn) -> (v0, Error exn)          (* rejected *)
    | Either.Right v1 ->
    (* continue: *)
    match reviewer (v0) (v1) with
    | Error (exn)              -> (v1, Error exn)   (* v1 rejected *)
    | (Ok None) as result      -> (v1, result)      (* v1 accepted *)
    | (Ok (Some v2)) as result -> (v2, result)      (* v1 revised and turned into v2 *)

 (* Redefined to render the reviewer argument optional: *)
 let compose_update_reviewer ?reviewer ~update ~v0 () =
 match reviewer with
 | None          -> apply_update ~update ~v0
 | Some reviewer -> compose_update_reviewer (reviewer) ~update ~v0

 (* Extend a reviewer to deal with optional values. The reviewer is activated only when both values (old and new)
    are defined (Some). Otherwise, the default review is returned:
    val option_lift : ?default:('a option) review -> ('a reviewer) -> ('a option) reviewer *)
 let option_lift ?(default=accepted()) f ox oy =
   match ox, oy with
   | Some x, Some y -> Review.map (fun z -> Some z) (f x y)
   | _, _ -> default

  (* Lift reviewers that ignore their first argument (the initial value) and take their
     decision looking only to the value proposed as update:
     val option_lift_snd : ?default:('a option) review -> ('a reviewer) -> ('a option) reviewer *)
 let option_lift_snd ?(default=accepted()) f _ oy =
   match oy with
   | Some y -> Review.map (fun z -> Some z) (f y y)
   | _ -> default

end (* Reviewer *)

(* ---------------------------- *)
(*           Exposed            *)
(* ---------------------------- *)

(* After an attempt to write the structure, it may be interesting to detect if
   the resistance has really changed its state. The 1st boolean component says
   if there was a change in sense of physical ("shallow") equality. Forcing the
   2nd boolean component, we can obtain the same information but in sense of
   the structural ("deep") equality: *)
type status = (bool * bool lazy_t)

module Exposed = struct

  type control = commits_no * status
   and commits_no = int

  class type ['a] atom = object
    (* Private methods outside Exposed: *)
    method reviewer : ('a reviewer) option
    (* --- *)
    method commit_required : bool
    method commit          : 'a * (commits_no * status)  (* get the up-to-date contents *)
    method commits_no      : int                         (* get the current number of commit method calls *)
    (* --- *)
    (* The method `compound' express the composite nature of the resistance,
       while the method `stable' express the fact that, at any moment, the current
       value of the resistance doesn't depend from the value of its components
       (all changes of its components will be accepted as is by the compound object).
       *)
    method compound : bool  (* is the structure composed by two or more components? *)
    method stable   : bool  (* is the structure "stable" (or "unstable")? *)
    (* --- *)
    method get : 'a    (* get contents supposing commit already done *)
    method set : 'a -> unit
    (* The unique "public" method, i.e. the unique
       method called ouside Exposed: *)
    method aim : ('a -> 'a) -> 'a * ('a review * status)
  end

  let raise_commit_failure (oid) =
    raise (Failure (Printf.sprintf "Ill-defined reviewer for resistance #%d" oid))

  let no_change : status = (true, lazy true)

  (* --- *)
  let return ?reviewer (v:'a) : 'a atom =
    let reviewer = Option.map (Reviewer.return) reviewer in
    let compose_update_reviewer = Reviewer.compose_update_reviewer ?reviewer in
    let atom =
      object (self)
        val mutable contents = v
        method reviewer = reviewer
        (* --- *)
        val mutable commits_no = 0
        method commits_no = commits_no
        method commit_required = false
        (* --- *)
        method commit : 'a * control =
          let cn = (let cn = commits_no in commits_no <- cn + 1; cn) in
          (contents, (cn, no_change))
        (* --- *)
        method compound = false
        method stable = true
        (* --- *)
        method get = contents
        method set v = (contents <- v)

        method aim (update) : 'a * ('a review * status) =
          let v0 = contents in
          let v2, review = compose_update_reviewer ~update ~v0 (* self#get *) () in
          let status = match review with Error _ -> no_change | _ -> (contents <- v2; (v2==v0, lazy (v2=v0))) (* self#set v2 *) in
          v2, (review, status)

        (* --- *)
        initializer
          self#aim (fun _ -> v) |> (fun (_v2, (rev, _status)) ->
            match rev with
            | Error (_) -> invalid_arg "Res.return: initial value rejected"
            | _ -> () (* ok, it's fine *)
            )

      end (* atom *)
    in
    atom

  (* Add a reviewer to an existing resistance.
     ---
     Note that `cover' adds an object layer to the provided object.
     For the sake of performance, all operators (return, product, fst_prj, snd_prj, split)
     integrate the possibility to add a reviewer immediately, in the same layer introduced
     by the operator to do its job. This option avoids the creation of too many additional
     layers. *)
  let cover (x:'a atom) (reviewer) : 'a atom =
    (* --- *)
    let reviewer = Reviewer.return reviewer in (* protect *)
    (* --- *)
    let reviewer : ('a reviewer) option =
      Reviewer.compose_optional_reviewers (x#reviewer) (* <= prioritary *) (Some reviewer) (* <= last word *)
    in
    let compose_update_reviewer = Reviewer.compose_update_reviewer ?reviewer in
    (* --- *)
    let compound = x#compound in
    let stable = not compound in (* compound ∧ reviewer => unstable *)
    (* --- *)
    let atom =
      object (self)
        (* --- *)
        method reviewer = reviewer
        method commit_required = true
        (* --- *)
        val mutable commits_no = 0
        method commits_no = commits_no
        (* --- *)
        method compound = compound
        method stable = stable
        (* --- *)
        method get = x#get
        method set = x#set

        (* --- *)
        method aim (update) : 'a * ('a review * status) =
          let v0, _ = self#commit in
          let v2, review = compose_update_reviewer ~update ~v0 () in
          let status = match review with Error _ -> no_change | _ -> (x#set v2; (v2==v0, lazy (v2=v0))) in
          v2, (review, status)

        (* --- *)
        method commit : 'a * control =
          let cn = (let cn = commits_no in commits_no <- cn + 1; cn) in
          let v0 = x#get in
          let v1, review = compose_update_reviewer ~update:(fun v0->v0) ~v0 () in
          let status = (v1==v0, lazy (v1=v0)) in
          let control = (cn, status) in
          match review with
          | Error _     -> raise_commit_failure (Oo.id self)
          | Ok (None)   -> (v0, control)
          | Ok (Some _) -> let () = if (v1 != v0) then (x#set v1) in (v1, control)

        (* --- *)
        initializer
          let v0, _ = self#commit in
          self#aim (fun _ -> v0) |> (fun (_v2, (rev, _status)) ->
            match rev with
            | Error (_) -> invalid_arg "Res.cover: initial value rejected"
            | _ -> () (* ok, it's fine *)
            )
      end
    in
    atom

  (* Product's closure: *)
  let product ?reviewer (x : 'a atom) (y : 'b atom) : ('a * 'b) atom =
    (* --- *)
    let stable = x#stable && y#stable && (reviewer = None) in
    (* --- *)
    let xy_reviewer : (('a*'b) reviewer) option =
      Reviewer.product_of_optional_reviewer (x#reviewer) (y#reviewer)
    in
    let reviewer : (('a*'b) reviewer) option =
      Reviewer.compose_optional_reviewers (xy_reviewer) (* <= prioritary *) (reviewer) (* <= last word *)
    in
    let compose_update_reviewer = Reviewer.compose_update_reviewer ?reviewer in
    (* --- *)
    let x_commit_required = x#commit_required in
    let y_commit_required = y#commit_required in
    (* --- *)
    let x_commit_or_get = if x_commit_required then (fun () -> fst x#commit) else (fun () -> x#get) in
    let y_commit_or_get = if y_commit_required then (fun () -> fst y#commit) else (fun () -> y#get) in
    (* --- *)
    let commit_required = x_commit_required || y_commit_required || (reviewer <> None) in
    (* --- *)
    let cons : ('a * 'b) atom =
      object (self)
        (* --- *)
        method reviewer = reviewer
        method commit_required = commit_required
        (* --- *)
        val mutable commits_no = 0
        method commits_no = commits_no
        (* --- *)
        method compound = true
        method stable = stable
        (* --- *)
        method get = (x#get, y#get)
        method set (a,b) = (x#set a; y#set b)

        (* --- *)
        method aim (update) : ('a * 'b) * (('a * 'b) review * status) =
          let v0 = if commit_required then fst self#commit else self#get in
          let v2, review = compose_update_reviewer ~update ~v0 () in
          let status = match review with Error _ -> no_change | _ -> (self#set v2; (v2==v0, lazy (v2=v0))) in
          v2, (review, status)

        (* --- *)
        method commit : ('a * 'b) * control =
          let cn = (let cn = commits_no in commits_no <- cn + 1; cn) in
          let a0 = x_commit_or_get () in
          let b0 = y_commit_or_get () in
          let v0 = (a0, b0) in
          let (a1,b1) as v1, review = compose_update_reviewer ~update:(fun v0->v0) ~v0 () in
          let status = ((a1==a0 && b1==b0), lazy (a1=a0 && b1=b0)) in
          let control = (cn, status) in
          match review with
          | Error _     -> raise_commit_failure (Oo.id self)
          | Ok (None)   -> (v0, control)
          | Ok (Some _) ->
              let () = if (a1 != a0) then (x#set a1) in
              let () = if (b1 != b0) then (y#set b1) in
              (v1, control)

        (* --- *)
        initializer
          let v0, _ = self#commit in
          self#aim (fun _ -> v0) |> (fun (_v2, (rev, _status)) ->
            match rev with
            | Error (_) -> invalid_arg "Res.product: initial value rejected"
            | _ -> () (* ok, it's fine *)
            )

      end (* cons *)
    in
    cons

  (* First projection (forget the second part of the structure).
     Concerning the review process, the product (xy) must have the last word,
     because bigger are less prioritary, i.e. the last arrived: *)
  let fst_prj ?reviewer (xy : ('a * 'b) atom) : 'a atom =
    (* --- *)
    (* xy#stable ∧ (xy#compound => ¬reviewer)  equiv. to:  xy#stable ∧ (¬xy#compound ∨ ¬reviewer)  *)
    let stable = xy#stable && ((not xy#compound) || reviewer = None) in
    let compound = xy#compound in
    (* --- *)
    let x_reviewer : (('a*'b) reviewer) option =
      Reviewer.product_of_optional_reviewer (reviewer) None (* add a fictive second dimension *)
    in
    (* The "actual" reviewer: *)
    let actual_reviewer : (('a*'b) reviewer) option =
      Reviewer.compose_optional_reviewers (x_reviewer) (* <= prioritary *) (xy#reviewer) (* <= last word *)
    in
    (* --- *)
    let xy_commit_required = xy#commit_required in
    let xy_commit_or_get = if xy_commit_required then (fun () -> fst xy#commit) else (fun () -> xy#get) in
    let self_commit_not_required = (reviewer = None) in
    let commit_required = xy_commit_required || (not self_commit_not_required) in
    (* --- *)
    (* Make the first part of the result: *)
    let fst_prj : 'a atom =
      object (self)
        (* --- *)
        method compound = compound
        method stable = stable
        (* --- *)
        (* To correctly update the 2nd component: *)
        val mutable buffer : 'b option = None
        method private set_buffer (a,b) = (buffer <- Some b)
        (* --- *)
        method private post_commit_or_get_snd =
          match buffer with None -> snd (xy#get) | Some b -> let () = (buffer <- None) in b
        (* --- *)

       (* The "official" reviewer: *)
        method reviewer : 'a reviewer option =
          Option.map (fun r a0 a1 ->
            let b0 = (snd xy#get) in
            r (a0,b0) (a1,b0) |> Review.interpose ~v1:(a1,b0) ~action:(self#set_buffer) |> Review.fst)
            (* --- *)
            (actual_reviewer)

        (* --- *)
        val mutable commits_no = 0
        method commits_no = commits_no
        method commit_required = commit_required
        (* --- *)

        method get = (fst xy#get)

        method set a =
          let b = self#post_commit_or_get_snd in
          xy#set (a,b)

        method aim (update) : 'a * ('a review * status) =
          let v0 = if commit_required then fst self#commit else self#get in
          let v2, review = Reviewer.compose_update_reviewer ?reviewer:(self#reviewer) ~update ~v0 () in
          let status = match review with Error _ -> no_change | _ -> (self#set v2; (v2==v0, lazy (v2=v0))) in
          v2, (review, status)

        (* --- *)
        method commit : 'a * control =
          let cn = (let cn = commits_no in commits_no <- cn + 1; cn) in
          let (a0, _b0) as v0 = xy_commit_or_get () in (* xy is now committed, so the reviewer is able to call xy#get *)
          if (self_commit_not_required) then (a0, (cn, no_change)) else (* continue: *)
          let a1, review = Reviewer.compose_update_reviewer ?reviewer:(self#reviewer) ~update:(fun v0->v0) ~v0:(a0) () in
          let status = (a1==a0, lazy (a1=a0)) in
          let control = (cn, status) in
          match review with
            | Error _     -> raise_commit_failure (Oo.id self)
            | Ok (None)   -> (a0, control)
            | Ok (Some _) -> let () = self#set a1 in (a1, control)

        (* --- *)
        initializer
          let v0, _ = self#commit in
          self#aim (fun _ -> v0) |> (fun (_v2, (rev, _status)) ->
            match rev with
            | Error (_) -> invalid_arg "Res.fst_prj: initial value rejected"
            | _ -> () (* ok, it's fine *)
            )

      end (* fst_prj *)
    in
    fst_prj

  (* Second projection (forget the first part of the structure).
     Concerning the review process, the product (xy) must have the last word,
     because bigger are less prioritary, i.e. the last arrived: *)
  let snd_prj ?reviewer (xy : ('a * 'b) atom) : 'b atom =
    (* --- *)
    (* xy#stable ∧ (xy#compound => ¬reviewer)  equiv. to:  xy#stable ∧ (¬xy#compound ∨ reviewer)  *)
    let stable = xy#stable && ((not xy#compound) || reviewer = None) in
    let compound = xy#compound in
    (* --- *)
    let y_reviewer : (('a*'b) reviewer) option =
      Reviewer.product_of_optional_reviewer None (reviewer) (* add a fictive first dimension *)
    in
    (* The "actual" reviewer: *)
    let actual_reviewer : (('a*'b) reviewer) option =
      Reviewer.compose_optional_reviewers (y_reviewer) (* <= prioritary *) (xy#reviewer) (* <= last word *)
    in
    (* --- *)
    let xy_commit_required = xy#commit_required in
    let xy_commit_or_get = if xy_commit_required then (fun () -> fst xy#commit) else (fun () -> xy#get) in
    let self_commit_not_required = (reviewer = None) in
    let commit_required = xy_commit_required || (not self_commit_not_required) in
    (* --- *)
    (* Make the first part of the result: *)
    let snd_prj : 'b atom =
      object (self)
        (* --- *)
        method compound = compound
        method stable = stable
        (* --- *)
        (* To correctly update the 1st component: *)
        val mutable buffer : 'a option = None
        method private set_buffer (a,b) = (buffer <- Some a)
        (* --- *)
        method private post_commit_or_get_fst =
          match buffer with None -> fst (xy#get) | Some a -> let () = (buffer <- None) in a
        (* --- *)

       (* The "official" reviewer: *)
        method reviewer : 'b reviewer option =
          Option.map (fun r b0 b1 ->
            let a0 = (fst xy#get) in
            r (a0,b0) (a0,b1) |> Review.interpose ~v1:(a0,b1) ~action:(self#set_buffer) |> Review.snd)
            (* --- *)
            (actual_reviewer)

        (* --- *)
        val mutable commits_no = 0
        method commits_no = commits_no
        method commit_required = commit_required
        (* --- *)

        method get = (snd xy#get)

        method set b =
          let a = self#post_commit_or_get_fst in
          xy#set (a,b)

        (* --- *)
        method aim (update) : 'b * ('b review * status) =
          let v0 = if commit_required then fst self#commit else self#get in
          let v2, review = Reviewer.compose_update_reviewer ?reviewer:(self#reviewer) ~update ~v0 () in
          let status = match review with Error _ -> no_change | _ -> (self#set v2; (v2==v0, lazy (v2=v0))) in
          v2, (review, status)

        (* --- *)
        method commit : 'b * control =
          let cn = (let cn = commits_no in commits_no <- cn + 1; cn) in
          let (_a0, b0) as v0 = xy_commit_or_get () in (* xy is now committed, so the reviewer is able to call xy#get *)
          if (self_commit_not_required) then (b0, (cn, no_change)) else (* continue: *)
          let b1, review = Reviewer.compose_update_reviewer ?reviewer:(self#reviewer) ~update:(fun v0->v0) ~v0:(b0) () in
          let status = (b1==b0, lazy (b1=b0)) in
          let control = (cn, status) in
          match review with
          | Error _     -> raise_commit_failure (Oo.id self)
          | Ok (None)   -> (b0, control)
          | Ok (Some _) -> let () = self#set b1 in (b1, control)

        (* --- *)
        initializer
          let v0, _ = self#commit in
          self#aim (fun _ -> v0) |> (fun (_v2, (rev, _status)) ->
            match rev with
            | Error (_) -> invalid_arg "Res.snd_prj: initial value rejected"
            | _ -> () (* ok, it's fine *)
            )

      end (* snd_prj *)
    in
    snd_prj

  (* map is defined simply combining product and projection (a function is a special relation).
     Note that there is no reviewer attached because the update imposed by the function is non-negotiable: *)
  let map ?equality (f:'a -> 'b) (x : 'a atom) : 'b atom =
    let a = if x#commit_required then fst x#commit else x#get in
    let f' = Extreme_sharing.weakly_memoize ?equality (* (=) *) f in
    let b = f' a in
    let y = return b in
    let xy_reviewer (x0, y0) (x1, y1) =
      let y2 = f' x1 in
      if y2 = y1 then Ok None else Ok (Some (x1,y2))
    in
    let xy = product ~reviewer:(xy_reviewer) x y in
    snd_prj xy

  let split ?fst_reviewer ?snd_reviewer (xy : ('a * 'b) atom) : ('a atom) * ('b atom) =
    let x = fst_prj ?reviewer:fst_reviewer xy in
    let y = snd_prj ?reviewer:snd_reviewer xy in
    (x, y)

  (* Alias for the interface: *)
  type 'a t = 'a atom

  let id (t : 'a t) : int = (Oo.id t)

  (* compare = oldest (by object identifiers) *)
  let compare (t1 : 'a t) (t2: 'a t) =
     (*Pervasives.*)compare (Oo.id t1) (Oo.id t2)

  let get (t : 'a t) : 'a =
    try
      if t#commit_required then fst t#commit else t#get
    with e -> begin
      let () = Log.printf1 "Res.Exposed.get: resistance #%d cannot be read\n" (id t) in
      raise e
    end

  (* unprotected: *)
  let aim (t : 'a t) : ('a update) -> 'a * ('a review * status) =
    try
      t#aim
    with e -> begin
      let () = Log.printf1 "Res.Exposed.aim: resistance #%d cannot be updated\n" (id t) in
      raise e
    end

  let commit (t : 'a t) : (exn, 'a * control) Either.t =
    try Either.Right (t#commit) with e -> Either.Left e

  let commit_or_warning (t : 'a t) : control =
    let cn = t#commits_no in
    try
      let (_v1, control) = t#commit in control
    with e -> begin
      let () = Log.printf1 "Res.Exposed.commit: resistance #%d cannot be committed\n" (id t) in
      (cn, no_change)
    end

  (* val get_commits_no : 'a t -> int *)
  let commits_no (t : 'a t) : int = t#commits_no

  let stable (t : 'a t) : bool = t#stable

end (* Exposed *)

(* ---------------------------- *)
(*  Genealogy of free products  *)
(* ---------------------------- *)

(* Genealogy of "free" products. We call a product "free" if it hasn't a self-reviewer.
   Both components may have a reviewer, but their product does not.
   Free products (zip) are interesting because they form a bijection
   with their splitting (unzip), and this property may be exploited to
   implement splitting (projection) operations efficiently.
   Hence, we define a module of S-expressions where nodes will be labelled
   by free products and atoms will be non-free objects (i.e. Exposed.atom
   with reviewers).
   *)
module Genealogy = Sexpr.GENEALOGY_OF_ZIPPED (
  struct
    open Exposed
    type 'a t = 'a atom
    let return v = return ?reviewer:None v
    let unzip xy = split ?fst_reviewer:None ?snd_reviewer:None xy
    let zip (x,y) = product ?reviewer:None x y
    let fst = Some (fun xy -> fst_prj ?reviewer:None xy)
    let snd = Some (fun xy -> snd_prj ?reviewer:None xy)
  end)

(* ---------------------------- *)
(*         Constructors         *)
(* ---------------------------- *)

(* S-expression of free products: *)
type 'a t = 'a Genealogy.t

let return ?reviewer (v:'a) : 'a t =
  Genealogy.atom (Exposed.return ?reviewer v)

let product ?reviewer (x : 'a t) (y : 'b t) : ('a * 'b) t =
  match reviewer with
  | None -> (* free => node *)
      Genealogy.product x y  (* cons ∘ Z.zip ∘ (root, root) *)
  (* --- *)
  | Some reviewer -> (* non-free => atom *)
      Genealogy.atom (Exposed.product ~reviewer (Genealogy.root x) (Genealogy.root y))

let cover (x:'a t) (reviewer) : 'a t =
  Genealogy.atom (Exposed.cover (Genealogy.root x) reviewer)

let map ?equality (f:'a -> 'b) (x:'a t) : 'b t =
  Genealogy.atom (Exposed.map ?equality f (Genealogy.root x))

(* Renamed later in `fst' as usual: *)
let fst_prj ?reviewer (xy : ('a * 'b) t) : 'a t =
  match reviewer with
  | None -> (* free => car (fst) *)
      Genealogy.car xy
  (* --- *)
  | Some reviewer -> (* non-free => atom *)
  (*  Genealogy.atom (Exposed.fst_prj ~reviewer (Genealogy.root xy)) *)
      Genealogy.atom (Exposed.cover (Genealogy.car xy |> Genealogy.root) reviewer)

(* Renamed later in `snd' as usual: *)
let snd_prj ?reviewer (xy : ('a * 'b) t) : 'b t =
  match reviewer with
  | None -> (* free => cdr (snd) *)
      Genealogy.cdr xy
  (* --- *)
  | Some reviewer -> (* non-free => atom *)
  (*  Genealogy.atom (Exposed.snd_prj ~reviewer (Genealogy.root xy)) *)
      Genealogy.atom (Exposed.cover (Genealogy.cdr xy |> Genealogy.root) reviewer)

let split ?fst_reviewer ?snd_reviewer (xy : ('a * 'b) t) : ('a t) * ('b t) =
  let x = fst_prj ?reviewer:fst_reviewer xy in
  let y = snd_prj ?reviewer:snd_reviewer xy in
  (x, y)

(* ---------------------------- *)
(*           Methods            *)
(* ---------------------------- *)

(* --- *)
let aim (t : 'a t) : ('a update) -> 'a * ('a review * status) =
  (Genealogy.root t)#aim

(* val aim_option_status : 'a t -> ('a update) -> 'a option * status *)
let aim_option_status t f =
  (Genealogy.root t)#aim f |> (fun (v2, (rev, status)) ->
     match rev with
     | Error _                   -> (None,    status)     (* v0 *)
     | Ok (None)                 -> (Some v2, status)     (* v1 *)
     | Ok ((Some v2) as revised) -> (revised, status)     (* v2 *)
     )

(* val aim_option : 'a t -> ('a update) -> 'a option *)
let aim_option t f =
  (Genealogy.root t)#aim f |> (fun (v2, (rev, _status)) ->
     match rev with
     | Error _                   -> None        (* v0 *)
     | Ok (None)                 -> Some v2     (* v1 *)
     | Ok ((Some v2) as revised) -> revised     (* v2 *)
     )

(* Important point: `get' cannot be defined simply as
   ---
   let get (x : 'a t) : 'a = (Genealogy.root x)#get
   ---
   because the resistance may be in an inconsistent state due to the fact that
   some of its components have changed state autonomously. Before any reading
   it could be necessary to restart the revision process.
   *)
let get (t : 'a t) : 'a =
  let root = (Genealogy.root t) in
  if root#commit_required then fst root#commit else root#get

(* Anachronistic and illusory ;-) *)
let set x v = aim x (fun _ -> v) |> ignore

(* --- Simplified versions of `aim' --- *)

(* val aim_succeed : 'a t -> ('a update) -> bool *)
let aim_succeed t f = aim t f |> (fun (_v2, (rev, _status)) -> Review.to_bool rev)

(* val aim_ignore : 'a t -> ('a update) -> unit *)
let aim_ignore t f = aim t f |> ignore

(* val aim_human : 'a t -> ('a update) -> 'a Review.h *)
let aim_human t f = aim t f |> (fun (_v2, (rev, _status)) -> Review.human_readable rev)

(* ---------------------------- *)
(*           Compare            *)
(* ---------------------------- *)

(* compare = oldest (by object identifiers) *)
let compare (t1 : 'a t) (t2: 'a t) =
  compare (Oo.id (Genealogy.root t1)) (Oo.id (Genealogy.root t2))

let get_id (t : 'a t) =
  (Oo.id (Genealogy.root t))

(* ---------------------------- *)
(*      Method application      *)
(* ---------------------------- *)

(* val apply_ro  : 'a t -> ('a -> 'b) -> 'b
   Trivial pattern added for completeness. May be interesting
   just for flipped arguments: *)
let apply_ro t f = f (get t) (* f is unprotected *)

(* val picky_rw : 'a t -> ('a -> 'a * ('a * ('a review * status) -> 'b)) -> 'b *)
let picky_rw t f =
  (* --- *)
  let k = ref None in
  let e = ref Not_found in
  (* --- *)
  let (v2, (rev, status)) as result =
    (Genealogy.root t)#aim (fun v0 ->
      match Either.protect f v0 with
      | Either.Left exn -> (e := exn); raise exn
      | Either.Right (v1, cont) -> (k := Some cont); v1
      )
  in
  (* --- *)
  (* The continuation is executed when the structure t cannot be modified anymore
     this round (so, should be released in a concurrent context): *)
  match !k with
  | None -> raise (!e)
  | Some cont -> cont (result) (* cont is unprotected *)

(* val apply_rw : 'a t -> ('a -> 'a * ('a -> 'b)) -> 'b *)
let apply_rw t f =
  picky_rw t (fun a -> let (v1, cont) = f a in v1, fun (v2, _) -> cont v2)

(* val picky_rw_meth : ('a -> 'b -> 'a * ('a * ('a review * status) -> 'c)) -> 'a t -> 'b -> 'c *)
let picky_rw_meth f t b = picky_rw t (fun a -> f a b)
let apply_rw_meth f t b = apply_rw t (fun a -> f a b)

(* ---------------------------- *)
(*      Integer resistances     *)
(* ---------------------------- *)

let incr t = aim t (fun v -> v+1) |> (fun (_v2, (rev, _status)) -> Review.to_bool rev)
let decr t = aim t (fun v -> v-1) |> (fun (_v2, (rev, _status)) -> Review.to_bool rev)

(* May be the simplest examples of tools that need the pattern `apply_rw' instead of `aim': *)
let ppi t = apply_rw t (fun v -> v+1, (fun y -> y))   (* ++i *)
let ipp t = apply_rw t (fun v -> v+1, (fun _ -> v))   (* i++ *)
let mmi t = apply_rw t (fun v -> v-1, (fun y -> y))   (* --i *)
let imm t = apply_rw t (fun v -> v-1, (fun _ -> v))   (* i-- *)

(* ---------------------------- *)
(*          Toolkit             *)
(* ---------------------------- *)

(** Just for fun: opening this module you redefine the standard [ref], [!] and [:=]
    in order to operate on this kind of structure instead of standard references. *)
module Toolkit = struct

 let ref ?reviewer v = return ?reviewer v
 let (!) t = get t
 let (:=) t v = set t v

 let incr t = aim t (fun v -> v+1) |> ignore
 let decr t = aim t (fun v -> v-1) |> ignore

 let ppi = ppi  (* ++i *)
 let ipp = ipp  (* i++ *)
 let mmi = mmi  (* --i *)
 let imm = imm  (* i-- *)

end

(* ---------------------------- *)
(*      Last main tools         *)
(* ---------------------------- *)

(* Stdlib's names redefined now: *)
let fst = fst_prj
let snd = snd_prj
