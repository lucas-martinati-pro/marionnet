  (*  This file is part of our reusable OCaml BRICKS library
    Copyright (C) 2010  Jean-Vincent Loddo

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.*)

(** Include [.mli]'s type definitions into the corresponding [.ml]. *)

(** Usage (in your <source>.ml):
{[
#load "include_type_definitions_p4.cmo";;
INCLUDE DEFINITIONS "<source>.mli"
]}

Type definitions are, in outline, mli phrases with '=' or exception definitions.
More precisely, only phrases of the following form will be imported:

-  type ... = ... (and ... = ...)*
-  module type ... = ...
-  class type ... = ...
-  exception ...

Any other phrase of <source>.mli will be ignored.
*)
