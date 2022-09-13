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

(* ----------------------------------------------------------
Compilation:
$ ocamlc -c -pp camlp4of -I +camlp4 camlp4of.cma option_extract_p4.ml

Usage:
$ ocamlc -c -pp "camlp4of option_extract_p4.cmo" your_source.ml
------------------------------------------------------------- *)
module type Unit = sig end
open Camlp4

(* Module registering the filter at loading-time as a side-effect. *)
module Option_extract_traced : Unit = struct

 module Id = struct
  let name    = "option_extract_p4"
  let version = Sys.ocaml_version
 end

 module Make (AstFilters : Camlp4.Sig.AstFilters) = struct
  open AstFilters
  open Ast

  register_str_item_filter
   (Ast.map_expr
    (function
     | <:expr@loc< Option.extract >> ->
         let failwith_msg = Loc.to_string loc in
         <:expr@loc< Option.extract ~failwith_msg:$str:failwith_msg$ >>
     | e -> e )
    )#str_item

 end

 let module M = Camlp4.Register.AstFilter(Id)(Make) in ()

end (* Option_extract_p4 *)
