(* This file is part of marionnet
   Copyright (C) 2011 Jean-Vincent Loddo

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

(* --- *)
module Log = Marionnet_log
module Configuration_files = Ocamlbricks.Configuration_files
(* --- *)

(* The cascade below runs at module initialization time, and this module is initialized
   very early -- it is what reads MARIONNET_PREFIX, hence it comes BEFORE Initialization,
   which is what gives the log its level. A Log.printf issued here would be dropped,
   whatever verbosity the user asked for. Hence the same deferred diagnosis as Gettext
   (episode 15 of `marionnet-todo-transverse'): the lines are built now and printed by
   [log_diagnosis], which Initialization calls as soon as the level is set. The blindness
   is not theoretical: it is what let a configuration file be looked for at a path which
   never existed, unnoticed (episode 25). *)
let diagnosis_lines = ref []
let diagnosis_say fmt = Printf.ksprintf (fun s -> diagnosis_lines := s :: !diagnosis_lines) fmt

(** Print which configuration files were looked for and which of them were really there,
    now that the log is able to print. Called by Initialization. *)
let log_diagnosis () =
  List.iter (fun line -> Log.printf1 "%s\n" line) (List.rev !diagnosis_lines)

(* The `~' of the last candidate is expanded by the shell which Configuration_files sources;
   the diagnosis has to expand it too, or it would call the user's own file absent. *)
let expand_tilde path =
  if String.length path >= 2 && (String.sub path 0 2) = "~/"
    then Filename.concat (try Sys.getenv "HOME" with Not_found -> "~") (String.sub path 2 (String.length path - 2))
    else path

(* The copy shipped with the software, the lowest priority of all. dune installs it under
   <prefix>/share/marionnet/share/, one `share' DEEPER than the path this list used to name
   (as does <prefix>/etc/marionnet/, where nothing is installed at all): the values shipped
   with Marionnet were therefore never read, and the cascade reduced in practice to
   /etc/marionnet/ and ~/.marionnet/. Measured and corrected at episode 25 of
   `marionnet-todo-transverse'. Its single source in the repository is etc/marionnet.conf,
   which etc/dune installs here -- there is no second copy left to keep in step. *)
let failsafe_copy_of_the_installation =
  Printf.sprintf "%s/share/%s/share/%s.conf" Meta.prefix Meta.name Meta.name

(* And the copy of THIS repository, when the binary runs from the build tree: it must win
   over the installed one, which is the rule episode 22 set for the glade and the images.
   This module cannot ask Initialization.Path (it is evaluated before it, being what reads
   MARIONNET_PREFIX), so it asks Development_tree directly -- that module depends on nothing
   here, which is precisely why it was isolated. *)
let failsafe_copy_of_the_development_tree () =
  Option.map
    (fun share -> Filename.concat share (Printf.sprintf "share/%s.conf" Meta.name))
    (Development_tree.share_directory ())

(** Read configuration files: *)
let configuration =
  (* Lowest priority first: *)
  let file_names =
     [ failsafe_copy_of_the_installation ]                              (* failsafe copy *)
     @ (Option.to_list (failsafe_copy_of_the_development_tree ()))      (* ...of this repository *)
     @ [ Printf.sprintf "%s/etc/%s/%s.conf" Meta.prefix Meta.name Meta.name;
         "/etc/marionnet/marionnet.conf";
         "~/.marionnet/marionnet.conf" ]
  in
  let () =
    diagnosis_say "Configuration: candidate files, lowest priority first:";
    List.iter
      (fun f ->
         let there = Sys.file_exists (expand_tilde f) in
         diagnosis_say "Configuration:   %s %s" (if there then "[read]  " else "[absent]") f)
      file_names
  in
  Configuration_files.make
    ~file_names
                (* An OVERRIDE since episode 7b of `modernisation-world-bridge': naming a
                   bridge here means "attach my LAN bridges to this one, which I built by
                   hand"; saying nothing (or naming nothing) lets Marionnet build and take
                   down its own. Cf. Global_options.explicit_world_bridge_name. *)
    ~variables:["MARIONNET_BRIDGE";
                "MARIONNET_KEYBOARD_LAYOUT";
                "MARIONNET_DEBUG";
                "MARIONNET_PDF_READER";
                "MARIONNET_POSTSCRIPT_READER";
                "MARIONNET_DVI_READER";
                "MARIONNET_HTML_READER";
                "MARIONNET_TEXT_EDITOR";
                (* *Optional* configuration variables: *)
		"MARIONNET_TERMINAL";
                "MARIONNET_PREFIX";
                "MARIONNET_LOCALEPREFIX";
                "MARIONNET_FILESYSTEMS_PATH";
                "MARIONNET_KERNELS_PATH";
                "MARIONNET_VDE_PREFIX";
                "MARIONNET_ROUTER_FILESYSTEM";
                "MARIONNET_ROUTER_KERNEL";
                "MARIONNET_MACHINE_FILESYSTEM";
                "MARIONNET_MACHINE_KERNEL";
                "MARIONNET_ROUTER_PORT0_DEFAULT_IPV4_CONFIG";
                "MARIONNET_ROUTER_PORT0_DEFAULT_IPV6_CONFIG";
                "MARIONNET_DISABLE_WARNING_TEMPORARY_WORKING_DIRECTORY_AUTOMATICALLY_SET";
                "MARIONNET_DISABLE_WARNING_ORPHAN_RUN_DIRECTORIES";
                "MARIONNET_DISABLE_WARNING_OTHER_MARIONNET_SESSIONS";
                "MARIONNET_TMPDIR";
                "MARIONNET_KEEP_ALL_SNAPSHOTS_WHEN_SAVING";
                "MARIONNET_TIMEZONE";
                (* Deep logging, episode 10: an alternative Markdown -> HTML converter (a command
                   reading the Markdown on its standard input). Unset, the conversion is done
                   in-process by cmarkit: see treeview_documents.ml and etc/marionnet.conf. *)
                "MARIONNET_MARKDOWN_TO_HTML";
              ]
    ();;

(* Convenient aliases: *)

type varname = string

let extract_bool_variable_or ~default varname =
  Configuration_files.Logging.extract_bool_variable_or ~default varname (configuration)

let extract_string_variable_or ?k ?unsuitable_value ~default varname =
  Configuration_files.Logging.extract_string_variable_or ?k ?unsuitable_value ~default varname (configuration)

let get_string_variable ?k ?unsuitable_value varname =
  Configuration_files.Logging.get_string_variable ?k ?unsuitable_value varname (configuration)

type source = [ `Filename of string | `Environment ] (* Configuration_files.source *)

let get_string_variable_with_source ?k ?unsuitable_value varname =
  Configuration_files.With_source.get_string_variable ?k ?unsuitable_value varname (configuration)


