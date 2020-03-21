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

(** Tools for preprocessors (which cannot use the library). Most of this
    code is extracted from library's modules. This file must be directly
    included in the preprocessor, avoiding in this way linking problems.
    Usage (in your preprocessor):
...
module Tool = struct
 INCLUDE "CAMLP4/common_tools_for_preprocessors.ml"
end
...
*)

module StringExtra :
  sig
    val lexists : (char -> bool) -> string -> int option
    val rexists : (char -> bool) -> string -> int option
    val not_blank : char -> bool
    val lstrip : string -> string
    val rstrip : string -> string
    val strip : string -> string
  end

module Conf :
  sig
    val get_lines : string -> string list
    val split_equation : string -> (string * string) option
    val conf : string -> default:string -> string -> string
  end

module Add_directive_syntax_extension :
  functor (Unit : sig  end) ->
    sig
      module Id : sig val name : string val version : string end
      module Make :
	functor (Syntax : Camlp4.Sig.Camlp4Syntax) ->
	  Camlp4.Sig.Camlp4Syntax
    end
