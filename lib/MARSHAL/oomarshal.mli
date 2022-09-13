(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Luca Saiu

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

(** Object-oriented marshalling support.
    This module contains two distinct marshalling facilities. *)

class ['a] marshaller :
  object
    method from_channel : in_channel -> 'a
    method from_file    : string -> 'a
    method from_string  : string -> 'a
    method to_channel   : 'a -> out_channel -> unit
    method to_file      : 'a -> string -> unit
    method to_string    : 'a -> string
  end
