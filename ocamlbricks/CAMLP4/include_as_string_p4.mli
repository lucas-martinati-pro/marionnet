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

(** Include a file content as a string constant in your code at compile-time. *)

(** Examples:
{[

(* Supposing you are compiling with the camlp4 preprocessor :
   $ ocamlc -c -pp 'camlp4XX -I +ocamlbricks' ... *)
#load "include_as_string_p4.cmo";;

let content = INCLUDE_AS_STRING "/bin/ls" in
Printf.eprintf "The length in word of /bin/ls is %d\n" (String.length content);
let ch = open_out "/tmp/ls_copy" in
Printf.fprintf ch "%s" content;
close_out ch;
;;

let put (filename,content) =
 begin
  Printf.eprintf "The length in word of %s is %d\n" filename (String.length content);
  let ch = open_out ("/tmp/"^Filename.basename filename) in
  Printf.fprintf ch "%s" content;
  close_out ch;
 end
;;

(* Note the usage of ../ requested with ocamlbuild (because compilation happens in _build/) *)
let xs = INCLUDE_AS_STRING_LIST "../share/images/ico.hub.*" in
List.iter put xs
;;
]}
*)
