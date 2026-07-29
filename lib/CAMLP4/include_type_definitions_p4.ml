(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2009  Jean-Vincent Loddo

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

(* ocamlc -c -pp camlp4of -I +camlp4 include_type_definitions_p4.ml *)

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

open Camlp4 (* -*- camlp4o -*- *)

module Id = struct
  let name = "Include_type_definitions"
  let version = "$Id: include_type_definitions_p4.ml,v 0.1 2009/03/18 16:16:16 $"
end

(* --- Opening an INCLUDE'd file from outside the build tree (merlin / ocaml-lsp) ---
   The paths passed to INCLUDE DEFINITIONS are written relative to the directory camlp4of
   is run from when the build system drives it, hence the leading "../.." steps climbing
   back to the project root. An editor's merlin replays that very same -pp command after
   chdir'ing into the source file's own directory, where such a path denotes nothing:
   open_in raised Sys_error, camlp4of exited non-zero, and the whole file came back to the
   editor as one syntax error. So, when the literal path fails, drop its leading parent
   steps and resolve what remains against the project root — located by climbing until a
   dune-project shows up. A build never reaches this fallback. *)
let rec project_root_from dir =
  if Sys.file_exists (Filename.concat dir "dune-project") then (Some dir) else
  let parent = Filename.dirname dir in
  if parent = dir then None else project_root_from parent

let without_leading_parent_steps path =
  let rec loop p =
    if (String.length p) >= 3 && (String.sub p 0 3) = "../"
      then loop (String.sub p 3 ((String.length p) - 3))
      else p
  in loop path

let open_in_even_from_elsewhere fname =
  try open_in fname with
  | Sys_error _ as e ->
      let candidate =
        match project_root_from (Sys.getcwd ()) with
        | None      -> None
        | Some root ->
            let c = Filename.concat root (without_leading_parent_steps fname) in
            if Sys.file_exists c then (Some c) else None
      in
      (match candidate with Some c -> open_in c | None -> raise e)

(* ----------------------------------- *)
(* --- Version for OCaml <= 4.02.y --- *)
(* ----------------------------------- *)
IFNDEF OCAML4_04_OR_LATER THEN
(* ----------------------------------- *)
module Make (Syntax : Sig.Camlp4Syntax) = struct
  open Sig
  include Syntax
  
  let change_str_item_outermost_location_to loc = function
    | Ast.StNil _ -> Ast.StNil loc
    | Ast.StSem (_, str_item1, str_item2) -> Ast.StSem (loc, str_item1, str_item2)
    | Ast.StCls (_, class_expr) -> Ast.StCls (loc, class_expr)
    | Ast.StClt (_, class_type) -> Ast.StClt (loc, class_type)
    | Ast.StTyp (_, ctyp) -> Ast.StTyp (loc, ctyp)
    | Ast.StExc (_, ctyp, ident) -> Ast.StExc (loc, ctyp, ident)
    | Ast.StMty (_, str, module_type) -> Ast.StMty (loc, str, module_type)
    (* Other cases are not possible here: *)
    | _ -> assert false
    
  EXTEND Gram
    GLOBAL: str_item;

    str_item: FIRST
      [ [
         "INCLUDE"; "DEFINITIONS"; fname = STRING ->

           let parse_file file =
             let ch = open_in_even_from_elsewhere file in
             let st = Stream.of_channel ch in
             (Gram.parse sig_items (Loc.mk file) st)
           in

           let rec list_of_sgSem = function
            | Ast.SgNil _ -> []
            | Ast.SgSem (_, x, xs) -> x :: (list_of_sgSem xs)
            | x -> [x]
           in

           let t = parse_file fname
           in
           let is_TyDcl_a_definition = function
            | Ast.TyDcl (_, _, _, Ast.TyNil _, _) -> false
            | Ast.TyDcl (_, _, _,    _       , _) -> true
            | _ -> false
           in
           let pred = function
             | Ast.SgTyp (_, (Ast.TyAnd(_,_,_) as t)) ->
                 let xs = Ast.list_of_ctyp t [] in
                 List.for_all is_TyDcl_a_definition xs
             | Ast.SgTyp (_, tyDcl) when (is_TyDcl_a_definition tyDcl) -> true
             | Ast.SgExc (_,_)
             | Ast.SgMty (_,_,_)
             | Ast.SgClt (_,_) -> true
             | _ -> false
           in
           let l = List.filter pred (list_of_sgSem t) in
           let mill = function
             | Ast.SgTyp (a, Ast.TyDcl (b,c,d,e,f)) -> Ast.StTyp (a, Ast.TyDcl (b,c,d,e,f))
             | Ast.SgTyp (a, Ast.TyAnd (b,c,d))     -> Ast.StTyp (a, Ast.TyAnd (b,c,d))
             | Ast.SgExc (a,b)                      -> Ast.StExc (a,b,Ast.ONone)
             | Ast.SgMty (a,b,c)                    -> Ast.StMty (a,b,c)
             | Ast.SgClt (a,b)                      -> Ast.StClt (a,b)
             | _ -> assert false
           in
           let result =
             Ast.stSem_of_list (List.map mill l)
           in
           change_str_item_outermost_location_to _loc result
      ] ]
    ;

  END

end

(* ----------------------------------- *)
(* --- Version for OCaml >= 4.04.y --- *)
(* ----------------------------------- *)
ELSE
(* ----------------------------------- *)
module Make (Syntax : Sig.Camlp4Syntax) = struct
  open Sig
  include Syntax
  
  let change_str_item_outermost_location_to loc = function
    | Ast.StNil _ -> Ast.StNil loc
    | Ast.StSem (_, str_item1, str_item2) -> Ast.StSem (loc, str_item1, str_item2)
    | Ast.StCls (_, class_expr) -> Ast.StCls (loc, class_expr)
    | Ast.StClt (_, class_type) -> Ast.StClt (loc, class_type)
    | Ast.StTyp (_, rec_flag, ctyp) -> Ast.StTyp (loc, rec_flag, ctyp)
    | Ast.StExc (_, ctyp, ident) -> Ast.StExc (loc, ctyp, ident)
    | Ast.StMty (_, str, module_type) -> Ast.StMty (loc, str, module_type)
    (* Other cases are not possible here: *)
    | _ -> assert false
    
  EXTEND Gram
    GLOBAL: str_item;

    str_item: FIRST
      [ [
         "INCLUDE"; "DEFINITIONS"; fname = STRING ->

           let parse_file file =
             let ch = open_in_even_from_elsewhere file in
             let st = Stream.of_channel ch in
             (Gram.parse sig_items (Loc.mk file) st)
           in

           let rec list_of_sgSem = function
            | Ast.SgNil _ -> []
            | Ast.SgSem (_, x, xs) -> x :: (list_of_sgSem xs)
            | x -> [x]
           in

           let t = parse_file fname
           in
           let is_TyDcl_a_definition = function
            | Ast.TyDcl (_, _, _, Ast.TyNil _, _) -> false
            | Ast.TyDcl (_, _, _,    _       , _) -> true
            | _ -> false
           in
           let pred = function
             | Ast.SgTyp (_, rec_flag, (Ast.TyAnd(_,_,_) as t)) ->
                 let xs = Ast.list_of_ctyp t [] in
                 List.for_all is_TyDcl_a_definition xs
             | Ast.SgTyp (_, rec_flag, tyDcl) when (is_TyDcl_a_definition tyDcl) -> true
             | Ast.SgExc (_,_)
             | Ast.SgMty (_,_,_)
             | Ast.SgClt (_,_) -> true
             | _ -> false
           in
           let l = List.filter pred (list_of_sgSem t) in
           let mill = function
             | Ast.SgTyp (a, rec_flag, Ast.TyDcl (b,c,d,e,f)) -> Ast.StTyp (a, rec_flag, Ast.TyDcl (b,c,d,e,f))
             | Ast.SgTyp (a, rec_flag, Ast.TyAnd (b,c,d))     -> Ast.StTyp (a, rec_flag, Ast.TyAnd (b,c,d))
             | Ast.SgExc (a,b)                                -> Ast.StExc (a,b,Ast.ONone)
             | Ast.SgMty (a,b,c)                              -> Ast.StMty (a,b,c)
             | Ast.SgClt (a,b)                                -> Ast.StClt (a,b)
             | _ -> assert false
           in
           let result =
             Ast.stSem_of_list (List.map mill l)
           in
           change_str_item_outermost_location_to _loc result
      ] ]
    ;

  END

end

ENDIF 

let module M = Register.OCamlSyntaxExtension (Id) (Make) in ()
