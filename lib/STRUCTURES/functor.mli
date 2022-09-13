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


val fold_of_functor :
  map:(('x -> unit (*'y*)) -> 'x_t -> 'y_t) ->
  ('a -> 'x -> 'a) -> 'a -> 'x_t -> 'a

val map_and_fold_of_functor :
  map:(('x -> 'y) -> 'x_t -> 'y_t) ->
  ('a -> 'x -> 'y * 'a) -> 'a -> 'x_t -> 'y_t * 'a

(* {2 Bifunctors} *)

val fold_of_bifunctor :
  map:(('x1 -> unit (*'y1*)) -> ('x2 -> unit (*'y2*)) -> 'x1x2_t -> 'y1y2_t) ->
  ('a -> 'x1 -> 'a) -> ('a -> 'x2 -> 'a) -> 'a -> 'x1x2_t -> 'a

val map_and_fold_of_bifunctor :
  map:(('x1 -> 'y1) -> ('x2 -> 'y2) -> 'x1x2_t -> 'y1y2_t) ->
  ('a -> 'x1 -> 'y1 * 'a) -> ('a -> 'x2 -> 'y2 * 'a) ->
  'a -> 'x1x2_t -> 'y1y2_t * 'a

(* {2 Trifunctors} *)

val map_and_fold_of_trifunctor :
  map:(('x1 -> 'y1) -> ('x2 -> 'y2) -> ('x3 -> 'y3) -> 'x1x2x3_t -> 'y1y2y3_t) ->
  ('a -> 'x1 -> 'y1 * 'a) ->
  ('a -> 'x2 -> 'y2 * 'a) ->
  ('a -> 'x3 -> 'y3 * 'a) ->
  'a -> 'x1x2x3_t -> 'y1y2y3_t * 'a

val fold_of_trifunctor :
  map:(('x1 -> unit (*'y1*)) -> ('x2 -> unit (*'y2*)) -> ('x3 -> unit (*'y3*)) -> 'x1x2x3_t -> 'y1y2y3_t) ->
  ('a -> 'x1 -> 'a) ->
  ('a -> 'x2 -> 'a) ->
  ('a -> 'x3 -> 'a) ->
  'a -> 'x1x2x3_t -> 'a

