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

(** Backward definitions with keyword [where]. *)

(** Usage (in your <source>.ml):
{[
#load "where_p4.cmo"
;;

<str_item_1>

WHERE

<str_item_2>
]}
is expanded as:
{[
<str_item_2>
<str_item_1>
]}

The keyword [where] is accepted instead of [WHERE].

The extension also exists for signature items ([<sig_item>]), and for
expressions (but here the legal keyword is only [where]):

{[ <expr> where <binding> = let <binding> in <expr> ]}

{b Associativity}:
{[ <expr> where <binding1> where <binding2>  =  (<expr> where <binding1>) where <binding2> ]}

{b Precedence}:
{[ let <id> = <expr> where <binding2> and <binding3>  =  let <id> = (<expr> where <binding2> and <binding3>) ]}
*)
