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

type update_info = {
  current : string;
  latest : string;
  url : string;
}

type update_status =
  | Up_to_date of string
  | Update_available of update_info
  | Check_error of string

val find_update_script : unit -> string option

val check_update : ?current:string -> unit -> update_status

val run_cli_update : ?force:bool -> unit -> int

val run_gui_update : ?force:bool -> unit -> unit

val prompt_manual_update_check : unit -> unit

val start_background_check_on_startup : unit -> unit
