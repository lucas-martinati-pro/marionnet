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

module StringExtra = struct

let lexists p s =
 let l = String.length s in
 let rec loop i =
  if i>=l then None else
  if p s.[i] then (Some i) else loop (i+1)
 in loop 0

let rexists p s =
 let l = String.length s in
 let rec loop i =
  if i<0 then None else
  if p s.[i] then (Some i) else loop (i-1)
 in loop (l-1)

let not_blank = (fun c -> (c<>' ') && (c<>'\t') && (c<>'\n'))

let lstrip s =
 match lexists not_blank s with
 | None   -> ""
 | Some i -> String.sub s i (((String.length s))-i)

let rstrip s =
 match rexists not_blank s with
 | None   -> ""
 | Some i -> String.sub s 0 (i+1)

let strip s =
 match (lexists not_blank s) with
 |  None   -> ""
 |  Some i -> (match (rexists not_blank s) with
	       | Some j -> String.sub s i (j-i+1)
               | None   -> assert false
               )

end

module Conf = struct

let get_lines file =
 let fd = open_in file in
 let rec loop acc =
  try
   loop ((input_line fd)::acc)
  with _ -> acc
 in loop []

let rec split_equation (s:string) =
 try
  let l = String.length s in
  let p = String.index s '=' in
  let a = String.sub s 0 p in
  let a = StringExtra.strip a in
  let b = String.sub s (p+1) (l-p-1) in
  let b = StringExtra.strip b in
  Some (a,b)
 with
   _ -> None

 let conf filename ~default =
  let xs = get_lines filename in
  let ys = List.map split_equation xs in
  let zs = List.filter ((<>)None) ys in
  let ws = List.map (function Some (x,y) -> (x,y) | _ -> assert false) zs in
  function key -> try List.assoc key ws with Not_found -> default

end

module Add_directive_syntax_extension (Unit : sig end) = struct

 module Id = struct
   let name = "Directive_syntax_extension"
   let version = Sys.ocaml_version
 end

 module Make (Syntax : Sig.Camlp4Syntax) : Sig.Camlp4Syntax = struct
  open Sig
  include Syntax
  EXTEND Gram GLOBAL: str_item sig_item;

    str_item: FIRST [[ "%"; "str_item"; directive = LIDENT; arg = OPT expr ->
      Printf.kfprintf flush stderr "%%str_item directive \"%s\" found.\n" directive;
      match arg with
      | None     -> <:str_item< # $directive$ >>
      | Some arg -> <:str_item< # $directive$ $arg$ >>
    ]];

    sig_item: FIRST [[ "%"; "sig_item"; directive = LIDENT; arg = OPT expr ->
      Printf.kfprintf flush stderr "%%sig_item directive \"%s\" found.\n" directive;
      match arg with
      | None     -> <:sig_item< # $directive$ >>
      | Some arg -> <:sig_item< # $directive$ $arg$ >>
    ]];
  END
 end (* Make *)
let module M = Register.OCamlSyntaxExtension(Id)(Make) in ()
end (* Directive_syntax_extension *)
