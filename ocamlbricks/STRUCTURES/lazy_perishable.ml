(* This file is part of ocamlbricks
   Copyright (C) 2015  Jean-Vincent Loddo

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

(** Lazy values with a lifetime. When the delay is expired, the value is recalculated. *)

type 'a t = ('a thunk) * (('a status) ref)
 and 'a status = ('a * date) option         (* None => not calculated, Some (y, d) => y calculated at the date d *)
 and date = float
 (* --- *)
 and lifetime = seconds
 and seconds = float
 and 'a thunk = unit -> 'a (* 'a Thunk.t *)

let create (thunk) (lifetime) =
  let already_called = ref None in
  let thunk =
    fun () ->
      let now = Unix.gettimeofday () in
      match !already_called with
      | Some (y, date) when (now -. date) < lifetime -> y
      | _ ->
          begin
            let y = thunk () in
            already_called := Some (y, now); (* memoise *)
            y
          end
  in
  (thunk, already_called)

let force (t, _) = t ()

let set_expired (t, s) =
  (s := None)
