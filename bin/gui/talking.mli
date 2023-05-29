(* This file is part of marionnet
   Copyright (C) 2010  Jean-Vincent Loddo
   Copyright (C) 2010  Université Paris 13

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

val are_there_shell_special_chars : string -> bool
val does_directory_support_sparse_files : string -> bool

module Msg :
  sig
    val help_repertoire_de_travail : unit -> unit
    val error_saving_while_something_up : unit -> unit
    val help_nom_pour_le_projet : unit -> unit
  end

val check_filename_validity_and_add_extension_if_needed :
  ?identifier:unit  ->  (* Force to use only identifiers i.e. letters, numbers, underscores and dashes *)
  ?extension:string ->  (* By default "mar" *)
  string -> string

(* Alias: *)
type 'a env = 'a Ocamlbricks.Environments.string_env

module EDialog :
  sig
    type edialog = unit -> string env option
    exception BadDialog of string * string
    exception StrangeDialog of string * string * string env
    exception IncompleteDialog

    val compose  : edialog list -> unit -> string env option
    val sequence : edialog list -> unit -> string env option

    val image_filter  : unit -> GFile.filter
    val all_files     : unit -> GFile.filter
    val script_filter : unit -> GFile.filter
    val mar_filter    : unit -> GFile.filter
    val xml_filter    : unit -> GFile.filter
    val jpeg_filter   : unit -> GFile.filter
    val png_filter    : unit -> GFile.filter

    type filter_name = [ `ALL | `DOT of Ocamlbricks.Dot.output_format | `IMG | `JPEG | `MAR | `PNG | `SCRIPT | `BASH | `CONF | `RC | `TXT | `XML ]
    val allfilters : filter_name list

    val get_filter_by_name : filter_name -> GFile.filter

    val ask_for_file :
      ?parent: GWindow.window_skel ->
      ?enrich:string env ->
      ?title:string ->
      ?valid:(string -> bool) ->
      ?filter_names:filter_name list ->
      ?filters:GFile.filter list ->
      ?extra_widget:GObj.widget * (unit -> string) ->
      ?action:GtkEnums.file_chooser_action ->
      ?gen_id:string ->
      ?help:(unit -> unit) option ->
      unit -> string env option

    val ask_for_existing_writable_folder_pathname_supporting_sparse_files :
      ?parent: GWindow.window_skel ->
      ?enrich:Ocamlbricks.Shell.filexpr env ->
      ?help:(unit -> unit) option ->
      title:string -> unit -> Ocamlbricks.Shell.filexpr env option

    val ask_for_fresh_writable_filename :
      ?parent: GWindow.window_skel ->
      ?enrich:string env ->
      title:string ->
      ?filters:GFile.filter list ->
      ?filter_names:filter_name list ->
      ?extra_widget:GObj.widget * (unit -> string) ->
      ?help:(unit -> unit) option ->
      unit -> string env option

    val ask_for_existing_rw_filename :
      ?parent: GWindow.window_skel ->
      ?enrich:Ocamlbricks.Shell.filexpr env ->
      title:string ->
      ?filter_names:filter_name list ->
      ?help:(unit -> unit) option ->
      unit -> string env option

    val ask_for_existing_importable_text_filename :
      ?parent: GWindow.window_skel ->
      ?enrich:Ocamlbricks.Shell.filexpr env ->
      ?max_size_kb:int -> (* 1024 (i.e. 1 Mb)*)
      title:string ->
      ?filter_names:filter_name list ->
      ?help:(unit -> unit) option ->
      unit -> string env option

    val ask_question :
      ?enrich:string env ->
      ?title:string ->
      ?gen_id:string ->
      ?help:(unit -> unit) option ->
      ?cancel:bool ->
      question:string -> unit -> string env option
  end
