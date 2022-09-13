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

(** Trace [Option.extract] failures. *)

(** Usage (in your <source>.ml):
{[
#load "option_extract_p4.cmo"
;;
]}
With this directive all calls to [Option.extract] will be replaced by [Option.extract ~failwith_msg:<call location>]. In this way, when the extraction fails, the raised [Failure] exception contains the location of the caller.
*)
