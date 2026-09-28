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

(* Table storing fallback translations (English): string -> string *)
let en_table : (string, string) Hashtbl.t = Hashtbl.create 512

(* Table storing translations for the active language: string -> string *)
let table : (string, string) Hashtbl.t = Hashtbl.create 512

(* The active language code (e.g. "fr", "en", "de", "es", "it") *)
let active_lang = ref "en"
let get_active_language () = !active_lang

(* Retained directory from which the locale was loaded *)
let retained_locales_dir = ref ""

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
          let base = match String.split_on_char '@' base with h :: _ -> h | [] -> base in
          base
    | _ :: rest -> loop rest
  in
  loop candidates

let load_json_into tbl path =
  try
    let json = Yojson.Safe.from_file path in
    match json with
    | `Assoc pairs ->
        List.iter (function
          | (k, `String v) -> Hashtbl.replace tbl k v
          | _ -> ()
        ) pairs;
        true
    | _ -> false
  with e ->
    diagnosis_say "I18n: error parsing JSON from %s: %s" path (Printexc.to_string e);
    false

let init () =
  let raw_lang = detect_language () in
  diagnosis_say "I18n: detected language string '%s'" raw_lang;
  let candidate_dirs =
    (Option.to_list (Configuration.get_string_variable "MARIONNET_LOCALES_PATH"))
    @ (match Development_tree.share_directory () with
       | Some share -> [Filename.concat share "locales"]
       | None -> [])
    @ [
        Filename.concat (Filename.dirname Sys.executable_name) "locales";
        Filename.concat (Filename.dirname (Filename.dirname Sys.executable_name)) "bin/locales";
        Filename.concat (Sys.getcwd ()) "bin/locales";
        Filename.concat (Filename.dirname (Filename.dirname Sys.executable_name))
          (Filename.concat "share" (Filename.concat Meta.name "locales"));
        Printf.sprintf "%s/share/%s/locales" Meta.prefix Meta.name;
        "/usr/share/marionnet/locales";
        "/usr/local/share/marionnet/locales";
      ]
  in
  let locales_dir_opt =
    List.find_opt (fun dir -> Sys.file_exists (Filename.concat dir "en.json")) candidate_dirs
  in
  match locales_dir_opt with
  | None ->
      diagnosis_say "I18n: WARNING: locales directory not found in candidate directories"
  | Some dir ->
      retained_locales_dir := dir;
      (* Always load en.json into en_table as universal fallback *)
      let en_path = Filename.concat dir "en.json" in
      if load_json_into en_table en_path then
        diagnosis_say "I18n: successfully loaded %d English fallback translations from %s"
          (Hashtbl.length en_table) en_path;

      let lang_candidates =
        let l = raw_lang in
        let lower = String.lowercase_ascii l in
        let base = match String.split_on_char '_' l with h :: _ -> h | [] -> l in
        let base_lower = String.lowercase_ascii base in
        [l; lower; base; base_lower]
      in
      let chosen_lang =
        let rec find_file = function
          | [] -> None
          | c :: rest ->
              let p = Filename.concat dir (c ^ ".json") in
              if Sys.file_exists p then Some (c, p) else find_file rest
        in
        find_file lang_candidates
      in
      (match chosen_lang with
       | Some (code, path) ->
           active_lang := code;
           if load_json_into table path then
             diagnosis_say "I18n: successfully loaded %d translations for '%s' from %s"
               (Hashtbl.length table) code path
       | None ->
           active_lang := "en";
           diagnosis_say "I18n: no specific locale file found for '%s', using English" raw_lang)

let () = init ()

let s_ msg =
  match Hashtbl.find_opt table msg with
  | Some trans when trans <> "" -> trans
  | _ -> (
      match Hashtbl.find_opt en_table msg with
      | Some trans when trans <> "" -> trans
      | _ -> msg
    )

let f_ fmt =
  let s = string_of_format fmt in
  let trans_opt =
    match Hashtbl.find_opt table s with
    | Some trans when trans <> "" -> Some trans
    | _ -> (
        match Hashtbl.find_opt en_table s with
        | Some trans when trans <> "" -> Some trans
        | _ -> None
      )
  in
  match trans_opt with
  | Some trans ->
      (try Scanf.format_from_string trans fmt with _ -> fmt)
  | None -> fmt

