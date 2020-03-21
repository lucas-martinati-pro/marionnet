(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2010 Jean-Vincent Loddo

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

(** The result is the thunk managing the cache memory. *)
let optimize ~(revision:'t->int) (f:'t->'a) (t:'t) =
  let r = ref 0 in
  let y = ref None in
  let cache_fault revision =
(*  (Printf.kfprintf flush stderr "Cache fault on revision %d\n" revision); *)
    let result = f t in
    (y := Some result);
    (r := revision);
    result
  in
  let thunk () =
    let revision = revision t in
    if !r = revision
    then match !y with
     | Some y -> y
     | None   -> cache_fault revision
    else cache_fault revision
  in
  thunk
