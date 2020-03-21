(* This file is part of ocamlbricks
   Copyright (C) 2012 Jean-Vincent Loddo

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

(** Reference-based folders built from the functor (map). *)

let fold_of_functor
  : map:(('x -> 'y) -> 'x_t -> 'y_t) -> ('a -> 'x -> 'a) -> 'a -> 'x_t -> 'a
  = fun ~map f s0 xs ->
      let state = ref s0 in
      let _ = map (fun x -> (state := f !state x)) xs in
      !state
;;


let map_and_fold_of_functor
  : map:(('x -> 'y) -> 'x_t -> 'y_t) -> ('a -> 'x -> 'y * 'a) -> 'a -> 'x_t -> 'y_t * 'a
  = fun ~map f s0 xs ->
      let state = ref s0 in
      let ys = map (fun x -> let (c,a) = f !state x in state := a; c) xs in
      (ys, !state)
;;

let map_and_fold_of_bifunctor
  : map:(('x1 -> 'y1) -> ('x2 -> 'y2) -> 'x1x2_t -> 'y1y2_t) ->
    ('a -> 'x1 -> 'y1 * 'a) ->
    ('a -> 'x2 -> 'y2 * 'a) ->
    'a -> 'x1x2_t -> 'y1y2_t * 'a
  = fun ~map f1 f2 s0 xs ->
      let state = ref s0 in
      let ys =
	map
	  (fun x1 -> let (y1,a) = f1 !state x1 in state := a; y1)
	  (fun x2 -> let (y2,a) = f2 !state x2 in state := a; y2)
	  xs
      in
      (ys, !state)


let fold_of_bifunctor
  : map:(('x1 -> 'y1) -> ('x2 -> 'y2) -> 'x1x2_t -> 'y1y2_t) ->
    ('a -> 'x1 -> 'a) ->
    ('a -> 'x2 -> 'a) ->
    'a -> 'x1x2_t -> 'a
  = fun ~map f1 f2 s0 xs ->
      let state = ref s0 in
      let _ =
	map
	  (fun x1 -> state := f1 !state x1)
	  (fun x2 -> state := f2 !state x2)
	  xs
      in
      !state


let map_and_fold_of_trifunctor
  : map:(('x1 -> 'y1) -> ('x2 -> 'y2) -> ('x3 -> 'y3) -> 'x1x2x3_t -> 'y1y2y3_t) ->
    ('a -> 'x1 -> 'y1 * 'a) ->
    ('a -> 'x2 -> 'y2 * 'a) ->
    ('a -> 'x3 -> 'y3 * 'a) ->
    'a -> 'x1x2x3_t -> 'y1y2y3_t * 'a
  = fun ~map f1 f2 f3 s0 xs ->
      let state = ref s0 in
      let ys =
	map
	  (fun x1 -> let (y1,a) = f1 !state x1 in state := a; y1)
	  (fun x2 -> let (y2,a) = f2 !state x2 in state := a; y2)
	  (fun x3 -> let (y3,a) = f3 !state x3 in state := a; y3)
	  xs
      in
      (ys, !state)


let fold_of_trifunctor
  : map:(('x1 -> 'y1) -> ('x2 -> 'y2) -> ('x3 -> 'y3) -> 'x1x2x3_t -> 'y1y2y3_t) ->
    ('a -> 'x1 -> 'a) ->
    ('a -> 'x2 -> 'a) ->
    ('a -> 'x3 -> 'a) ->
    'a -> 'x1x2x3_t -> 'a
  = fun ~map f1 f2 f3 s0 xs ->
      let state = ref s0 in
      let _ =
	map
	  (fun x1 -> state := f1 !state x1)
	  (fun x2 -> state := f2 !state x2)
	  (fun x3 -> state := f3 !state x3)
	  xs
      in
      !state

