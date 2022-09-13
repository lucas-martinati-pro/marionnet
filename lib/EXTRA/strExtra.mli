(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009 Jean-Vincent Loddo

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

(** Additional features for the standard library [Str]. *)

(** {2 Matching result} *)

type result = string * (int * int) * string list

val result_as_object : result ->
  < matched : string;
    frame   : int * int;
    groups  : string list;
    >

(** {2 Building} *)

val mkregexp :
  ?mode:[> `inner | `prefix | `suffix | `whole ] ->
  ?case_insensitive:unit ->
  ?prefix:string list ->
  ?groups:string list ->
  ?suffix:string list ->
  unit -> Str.regexp

(** {2 First (single) or global (multiple) matching} *)

module First : sig
 val matching   : ?frame:(int*int) -> Str.regexp -> string -> result option
 val matchingp  : ?frame:(int*int) -> Str.regexp -> string -> bool
 val replace    : ?frame:(int*int) -> Str.regexp -> (result -> string) -> string -> string
 val substitute : ?frame:(int*int) -> Str.regexp -> (string -> string) -> string -> string
end

module Global : sig
 val matching   : ?frame:(int*int) -> ?overlap:unit -> Str.regexp -> string -> result list
 val replace    : ?frame:(int*int) -> ?overlap:unit -> Str.regexp -> (result -> string) -> string -> string
 val substitute : ?frame:(int*int) -> ?overlap:unit -> Str.regexp -> (string -> string) -> string -> string
end

(** {2 Tools} *)

module Posix :
  sig

    val alnum  : ?exists:unit -> string -> bool
    val alpha  : ?exists:unit -> string -> bool
    val ascii  : ?exists:unit -> string -> bool
    val blank  : ?exists:unit -> string -> bool
    val cntrl  : ?exists:unit -> string -> bool
    val digit  : ?exists:unit -> string -> bool
    val graph  : ?exists:unit -> string -> bool
    val lower  : ?exists:unit -> string -> bool
    val print  : ?exists:unit -> string -> bool
    val punct  : ?exists:unit -> string -> bool
    val space  : ?exists:unit -> string -> bool
    val upper  : ?exists:unit -> string -> bool
    val word   : ?exists:unit -> string -> bool
    val xdigit : ?exists:unit -> string -> bool

    module String :
      sig
	val alnum   : string
	val alpha   : string
	val ascii   : string
	val blank   : string
	val cntrl   : string
	val digit   : string
	val graph   : string
	val lower   : string
	val print   : string
	val punct   : string
	val space   : string
	val upper   : string
	val word    : string
	val xdigit  : string
      end

    module Regexp :
      sig
	val alnum   : Str.regexp
	val alpha   : Str.regexp
	val ascii   : Str.regexp
	val blank   : Str.regexp
	val cntrl   : Str.regexp
	val digit   : Str.regexp
	val graph   : Str.regexp
	val lower   : Str.regexp
	val print   : Str.regexp
	val punct   : Str.regexp
	val space   : Str.regexp
	val upper   : Str.regexp
	val word    : Str.regexp
	val xdigit  : Str.regexp
      end

end


module Class : sig
 val identifierp : ?allow_dash:unit -> string -> bool
end
