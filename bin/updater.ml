(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2026  Lucas Martinati

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

(** Updater module: handles checking for GitHub releases, CLI updates,
    and GTK notifications/dialogs. *)

module Log = Marionnet_log
module UnixExtra = Ocamlbricks.UnixExtra

open Gettext

type update_info = {
  current : string;
  latest : string;
  url : string;
}

type update_status =
  | Up_to_date of string
  | Update_available of update_info
  | Check_error of string

let find_update_script () : string option =
  let env_override =
    try
      let v = Sys.getenv "MARIONNET_UPDATE_SCRIPT" in
      if v <> "" && Sys.file_exists v then Some v else None
    with Not_found -> None
  in
  match env_override with
  | Some p -> Some p
  | None ->
      let candidates = [
        (let dir = Filename.dirname Sys.executable_name in
         let p = Filename.concat dir "marionnet-update.sh" in
         if Sys.file_exists p then Some p else None);
        (let dir = Filename.dirname Sys.executable_name in
         let p = Filename.concat dir "marionnet-update" in
         if Sys.file_exists p then Some p else None);
        (let p = Filename.concat (Sys.getcwd ()) "bin/scripts/marionnet-update.sh" in
         if Sys.file_exists p then Some p else None);
        (let p = Filename.concat (Sys.getcwd ()) "scripts/marionnet-update.sh" in
         if Sys.file_exists p then Some p else None);
        (if Sys.file_exists "/usr/bin/marionnet-update.sh" then Some "/usr/bin/marionnet-update.sh" else None);
        (if Sys.file_exists "/usr/bin/marionnet-update" then Some "/usr/bin/marionnet-update" else None);
        (if Sys.file_exists "/usr/local/bin/marionnet-update.sh" then Some "/usr/local/bin/marionnet-update.sh" else None);
        (match UnixExtra.run "command -v marionnet-update.sh 2>/dev/null" with
         | (out, Unix.WEXITED 0) when String.trim out <> "" -> Some (String.trim out)
         | _ ->
             (match UnixExtra.run "command -v marionnet-update 2>/dev/null" with
              | (out, Unix.WEXITED 0) when String.trim out <> "" -> Some (String.trim out)
              | _ -> None))
      ] in
      List.find_map (fun x -> x) candidates

let check_update ?(current = Version.version) () : update_status =
  match find_update_script () with
  | None ->
      Check_error (s_ "Update script (marionnet-update.sh) not found.")
  | Some script ->
      let cmd = Printf.sprintf "%s --check --current %s 2>&1" (Filename.quote script) (Filename.quote current) in
      let (output, status) = UnixExtra.run cmd in
      let lines = String.split_on_char '\n' output in
      let first_line = match lines with h :: _ -> String.trim h | [] -> "" in
      match status with
      | Unix.WEXITED 0 ->
          let parts = String.split_on_char ' ' first_line in
          (match parts with
           | "UPDATE_AVAILABLE" :: latest :: cur :: url :: _ ->
               Update_available { current = cur; latest; url }
           | "UPDATE_AVAILABLE" :: latest :: _ ->
               Update_available { current; latest; url = "" }
           | _ ->
               Update_available { current; latest = first_line; url = "" })
      | Unix.WEXITED 1 ->
          let cur =
            match String.split_on_char ' ' first_line with
            | "UP_TO_DATE" :: c :: _ -> c
            | _ -> current
          in
          Up_to_date cur
      | _ ->
          Check_error (if first_line <> "" then first_line else output)

let run_cli_update ?(force = false) () : int =
  match find_update_script () with
  | None ->
      Printf.eprintf "[-] Error: update script (marionnet-update.sh) not found.\n%!";
      1
  | Some script ->
      let cmd =
        Printf.sprintf "%s --cli%s --current %s"
          (Filename.quote script)
          (if force then " --force" else "")
          (Filename.quote Version.version)
      in
      Sys.command cmd

let run_gui_update ?(force = false) () : unit =
  match find_update_script () with
  | None ->
      Simple_dialogs.error
        (s_ "Software Update")
        (s_ "Update script (marionnet-update.sh) not found.")
        ()
  | Some script ->
      let cmd =
        Printf.sprintf "%s --gui%s --current %s &"
          (Filename.quote script)
          (if force then " --force" else "")
          (Filename.quote Version.version)
      in
      ignore (Sys.command cmd)

let format_update_question ~current ~latest =
  Printf.sprintf
    (f_ "A new version of Marionnet is available!\n\nCurrent version: %s\nLatest version: %s\n\nDo you want to update Marionnet now?")
    current latest

let prompt_manual_update_check () : unit =
  let _ = Thread.create (fun () ->
    let status = check_update () in
    GMain_actor.apply_extract (fun () ->
      match status with
      | Update_available info ->
          let question = format_update_question ~current:info.current ~latest:info.latest in
          (match Simple_dialogs.confirm_dialog ~question () with
           | Some true -> run_gui_update ()
           | _ -> ())
      | Up_to_date cur ->
          Simple_dialogs.info
            (s_ "Software Update")
            (Printf.sprintf (f_ "Marionnet is up to date (version %s).") cur)
            ()
      | Check_error err ->
          Simple_dialogs.warning
            (s_ "Software Update")
            (Printf.sprintf (f_ "Unable to check for updates.\nPlease check your Internet connection.\n\nDetail: %s") err)
            ()
    ) ()
  ) () in
  ()

let start_background_check_on_startup () : unit =
  ignore
    (GMain.Timeout.add
       ~ms:2500
       ~callback:(fun () ->
         let _ = Thread.create (fun () ->
           match check_update () with
           | Update_available info ->
               GMain_actor.apply_extract (fun () ->
                 let question = format_update_question ~current:info.current ~latest:info.latest in
                 match Simple_dialogs.confirm_dialog ~question () with
                 | Some true -> run_gui_update ()
                 | _ -> ()
               ) ()
           | _ -> ()
         ) () in
         false
       ))
