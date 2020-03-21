(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Jean-Vincent Loddo

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

(** Handling shell scripts in {e OCaml}. A general technique for wrapping
    shell commands or scripts is proposed in this module.
    The technique is applied in the module {!Shell} for building a significative set
    of ready-to-use wrappers corresponding to the most famous {e Unix} tools
    ({b grep}, {b dd}, {b tar},..).
*)

type command = string
type content = string
type arg = string
type call = string
type script = string

val envelop : ?name:string -> script -> call

val make :
  ?at:('a -> string) option ->
  ?it:('b -> string) option ->
  ot:(string -> 'c) ->
  ?script:bool ->
  command -> ?opt:string -> ?args:'a option -> ?input:'b option -> unit -> 'c

val textfilter :
  ?at:('a -> string) option ->
  ?script:bool ->
  command ->
  ?opt:string -> ?args:'a option -> StringExtra.Text.t -> StringExtra.Text.t

module Treat :
  sig
    val identity : ('a -> 'a) option
    val quote : (string -> string) option
    val is_true : string -> bool
  end
