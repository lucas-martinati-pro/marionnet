(*  This file is part of our reusable OCaml BRICKS library
    Copyright (C) 2008-2009 Jean-Vincent Loddo

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

(* ocamlc -I +camlp4 camlp4lib.cma -pp camlp4orf -c include_as_string_p4.ml *)

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

(* When this source is read (preprocessing), the variable OCAML4_02_OR_LATER is not set,
   even if we are compiling with OCaml 4.02.x or later.
   This means that the pseudo module Bytes will be used in any case, but it's not a problem. *)
IFNDEF OCAML4_02_OR_LATER THEN
module Bytes = struct  let create=String.create  let set=String.set  let sub=String.sub  let blit=String.blit  let to_string x = x end
ENDIF

open Camlp4.PreCast
open Syntax

(* --- Reading an INCLUDE'd file from outside the build tree (merlin / ocaml-lsp) ---
   The paths passed to INCLUDE_AS_STRING are written relative to the directory camlp4of is
   run from when the build system drives it, hence the leading "../.." steps climbing back
   to the project root. An editor's merlin replays that very same -pp command after chdir'ing
   into the source file's own directory, where such a path denotes nothing: the open failed,
   camlp4of exited non-zero, and the whole file came back to the editor as one syntax error.
   So, when the literal path does not exist, drop its leading parent steps and resolve what
   remains against the project root — located by climbing until a dune-project shows up.
   A build never reaches this fallback. (INCLUDE_AS_STRING_LIST reads its files through the
   same from_file, but the shell pattern it globs is left untouched: no user in this tree.) *)
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

let resolve_even_from_elsewhere fname =
  if Sys.file_exists fname then fname else
  match project_root_from (Sys.getcwd ()) with
  | None      -> fname
  | Some root ->
      let candidate = Filename.concat root (without_leading_parent_steps fname) in
      if Sys.file_exists candidate then candidate else fname
;;

(** Tools for strings. *)
module Tool = struct

(** Import a file into a string. *)
let from_descr (fd:Unix.file_descr) : string =
 let q = Queue.create () in
 let buffer_size = 8192 in
 let buff = Bytes.create buffer_size in
 let rec loop1 acc_n =
  begin
   let n = (Unix.read fd buff 0 buffer_size)    in
   if (n=0) then acc_n else ((Queue.push ((Bytes.sub buff 0 n),n) q); loop1 (acc_n + n))
   end in
 let dst_size = loop1 0 in
 let dst = Bytes.create dst_size in
 let rec loop2 dstoff = if dstoff>=dst_size then () else
  begin
  let (src,src_size) = Queue.take q in
  (Bytes.blit src 0 dst dstoff src_size);
  loop2 (dstoff+src_size)
  end in
 (loop2 0);
(* (Printf.eprintf "Preprocessing: include_as_string: the length of the included string is %d\n" dst_size);*)
 Bytes.to_string dst
;;

let from_file (filename:string) : string =
 let filename = resolve_even_from_elsewhere filename in
 let fd = (Unix.openfile filename [Unix.O_RDONLY;Unix.O_RSYNC] 0o640) in
 let result = from_descr fd in
 (Unix.close fd);
 result
;;

end;;

let readlines ?not_empty_lines_only filename =
 let ch = open_in filename in
 let rec loop acc =
  try loop ((input_line ch)::acc)
  with End_of_file -> acc
 in
 let result = loop [] in
 close_in ch;
 if not_empty_lines_only = Some ()
  then List.filter (fun l -> (String.length l)>0) result
  else result
 ;;

let glob pattern =
  let filename = Filename.temp_file "globbing" ".list" in
  let cmd =
    Printf.sprintf "bash -c 'shopt -s nullglob; for i in %s; do echo $i; done > %s'"
       pattern
       filename
  in
  if (Sys.command cmd) <> 0
   then failwith (Printf.sprintf "include_as_string_p4: glob: error globbing pattern %s" pattern)
   else ();
  let result = readlines ~not_empty_lines_only:() filename in
  Sys.remove filename;
  result
;;

(* -> common tools for camlp4 *)
let ex_cons_app_of_list loc xs =
   List.fold_right (fun x xs -> <:expr@loc< $x$::$xs$ >>) xs <:expr@loc<[]>> ;;


EXTEND Gram
    GLOBAL: expr;
    expr: LEVEL "top"
      [ [ "INCLUDE_AS_STRING"; fname = STRING ->
	    let s = Tool.from_file fname in
       	    let s = String.escaped s in
	    <:expr< $str:s$ >>

        | "INCLUDE_AS_STRING_LIST"; pattern = STRING ->
	    let fname_list = glob pattern in
	    let expr_list =
	     List.map
 	       (fun fname ->
	          let content = String.escaped (Tool.from_file fname) in
	          <:expr< ( $str:fname$ , $str:content$) >>)
	       fname_list
	    in
            ex_cons_app_of_list _loc expr_list
    ] ]
    ;
END;


