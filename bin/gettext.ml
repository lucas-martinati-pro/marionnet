(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2010  Jean-Vincent Loddo
   Copyright (C) 2010  Université Paris 13
   Copyright (C) 2026  Marionnet contributors

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

module Log = Marionnet_log

let diagnosis_lines = ref []
let diagnosis_say fmt = Printf.ksprintf (fun s -> diagnosis_lines := s :: !diagnosis_lines) fmt

let log_diagnosis () =
  List.iter (fun line -> Log.printf1 "%s\n" line) (List.rev !diagnosis_lines)

(* Table storing translations for the active language: string -> string *)
let table : (string, string) Hashtbl.t = Hashtbl.create 512

(* The active language code (e.g. "fr", "en", "de", "es", "it") *)
let active_lang = ref "en"
let get_active_language () = !active_lang

(* Retained directory from which the locale was loaded *)
let retained_locales_dir = ref ""
let localeprefix = ""

let detect_language () : string =
  let candidates = [
    Configuration.get_string_variable "MARIONNET_LANG";
    (try Some (Sys.getenv "MARIONNET_LANG") with Not_found -> None);
    (try Some (Sys.getenv "LC_ALL") with Not_found -> None);
    (try Some (Sys.getenv "LC_MESSAGES") with Not_found -> None);
    (try Some (Sys.getenv "LANG") with Not_found -> None);
  ] in
  let rec loop = function
    | [] -> "en"
    | Some v :: rest when String.trim v <> "" ->
        let s = String.trim v in
        if s = "C" || s = "POSIX" then "en"
        else
          let base = match String.split_on_char '.' s with h :: _ -> h | [] -> s in
          let lang = match String.split_on_char '_' base with h :: _ -> h | [] -> base in
          String.lowercase_ascii lang
    | _ :: rest -> loop rest
  in
  loop candidates

let load_json_file path =
  try
    let json = Yojson.Safe.from_file path in
    match json with
    | `Assoc pairs ->
        List.iter (function
          | (k, `String v) -> Hashtbl.replace table k v
          | _ -> ()
        ) pairs;
        true
    | _ -> false
  with e ->
    diagnosis_say "I18n: error parsing JSON from %s: %s" path (Printexc.to_string e);
    false

let init () =
  let lang = detect_language () in
  active_lang := lang;
  diagnosis_say "I18n: detected language '%s'" lang;
  if lang = "c" then begin
    diagnosis_say "I18n: language is C/POSIX, using in-code default strings"
  end else begin
    let filename = lang ^ ".json" in
    let candidate_dirs =
      (Option.to_list (Configuration.get_string_variable "MARIONNET_LOCALES_PATH"))
      @ (match Development_tree.share_directory () with
         | Some share -> [Filename.concat share "locales"]
         | None -> [])
      @ [
          Filename.concat (Sys.getcwd ()) "bin/locales";
          Filename.concat (Filename.dirname (Filename.dirname Sys.executable_name))
            (Filename.concat "share" (Filename.concat Meta.name "locales"));
          Printf.sprintf "%s/share/%s/locales" Meta.prefix Meta.name;
          "/usr/share/marionnet/locales";
          "/usr/local/share/marionnet/locales";
        ]
    in
    let rec try_dirs = function
      | [] ->
          diagnosis_say "I18n: WARNING: no translation file '%s' found in candidate directories; falling back to English" filename
      | dir :: rest ->
          let file_path = Filename.concat dir filename in
          if Sys.file_exists file_path then begin
            if load_json_file file_path then begin
              retained_locales_dir := dir;
              diagnosis_say "I18n: successfully loaded %d translations for '%s' from %s"
                (Hashtbl.length table) lang file_path
            end else
              try_dirs rest
          end else
            try_dirs rest
    in
    try_dirs candidate_dirs
  end

let () = init ()

let s_ msg =
  match Hashtbl.find_opt table msg with
  | Some trans when trans <> "" -> trans
  | _ -> msg

let f_ fmt =
  let s = string_of_format fmt in
  match Hashtbl.find_opt table s with
  | Some trans when trans <> "" ->
      (try Scanf.format_from_string trans fmt
       with _ -> fmt)
  | _ -> fmt
