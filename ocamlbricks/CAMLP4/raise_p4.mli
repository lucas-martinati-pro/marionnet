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

(** Intercept [raise] calls for logging. *)

(** Usage (in your <source>.ml):
{[
#load "raise_p4.cmo"
;;
]}

With this directive all calls of the form [raise <exception>] will be replaced by:
- a call [Log.printf ~v:1 "Raising exception <exception> at <location>\n"]
- followed by the real [Pervasives.raise <exception>] call.

You can set another verbosity level by the directive:
{[
%str_item set_raise_filter_verbosity 2;;
]}

You can escape the filter in a file with the directive:
{[
%str_item escape_raise_filter;;
]}

You can reactivate the filter in a file with the directive:
{[
%str_item enable_raise_filter;;
]}
*)
