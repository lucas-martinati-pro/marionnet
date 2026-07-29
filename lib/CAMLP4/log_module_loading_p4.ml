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
$ ocamlc -c -pp camlp4of -I +camlp4 camlp4of.cma log_module_loading_p4.ml

Usage:
$ ocamlc -c -pp "camlp4of log_module_loading_p4.cmo" your_source.ml
------------------------------------------------------------- *)
module type Unit = sig end
open Camlp4

(** Module registering the filter at loading-time as a side-effect. *)
module Log_module_loading_p4 : Unit = struct

 module Id = struct
  let name    = "log_module_loading_p4"
  let version = Sys.ocaml_version
 end

 module Make (AstFilters : Camlp4.Sig.AstFilters) = struct
  open AstFilters
  open Ast

  let first_str_item = ref true ;;
  (* let () = Printf.kfprintf flush stderr "camlp4: Registering filter log_module_loading_p4\n" ;; *)

  (* The modules that would be made circular by the preambule injected below. Matched on the
     SUFFIX of the basename, not on the basename itself: merlin / ocaml-lsp does not hand the
     buffer over as is, it preprocesses a temporary copy named /tmp/merlinpp<hash><basename>,
     for which an equality test misses — the editor then reported "Unbound module
     Marionnet_log" inside Marionnet_log itself. The names below are specific enough for a
     suffix test to be safe (at worst a hypothetical my_version.ml would silently lose its
     loading trace). *)
  let modules_to_be_left_alone =
    [(*"gui.ml";*) "meta.ml"; "marionnet_log.ml"; "ocamlbricks_log.ml"; "version.ml"; ] ;;

  let is_to_be_left_alone file_name =
    let base = Filename.basename file_name in
    List.exists (fun x -> base = x || Filename.check_suffix base x) modules_to_be_left_alone ;;

  register_str_item_filter
   (Ast.map_str_item
    (function
     | s when !first_str_item ->
         (first_str_item := false);
         let loc = Ast.loc_of_str_item s in
         let file_name = Loc.file_name loc in
         (* Avoid circular recursion for Log and Meta modules: *)
         if is_to_be_left_alone file_name then
           begin
            (* Printf.kfprintf flush stderr "camlp4: Skipping to apply filter log_module_loading_p4 to %s\n" file_name; *)
             s
           end
         else begin
           (* Printf.kfprintf flush stderr "camlp4: Applying filter log_module_loading_p4 to %s\n" file_name; *)
           (* let () = Log.printf1 "Loading module %s\n" $str:file_name$ *)
           let preambule = <:str_item@loc<
               let () = Marionnet_log.printf1 "Loading module %s\n" $str:file_name$
               >>
           in
           StSem (loc, preambule, s)
           end
     (* --- *)
     | s -> s )
    )#str_item
   ;;

 end

 let module M = Camlp4.Register.AstFilter(Id)(Make) in ()

end (* Log_module_loading_p4 *)
