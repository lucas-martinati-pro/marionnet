(* This file is part of ocamlbricks
   Copyright (C) 2010 Jean-Vincent Loddo

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

(** Widgets for dot. *)

val filter_of_format : Dot.output_format -> GFile.filter
val filter_of_string : string -> GFile.filter

val make_all_working_filters       : unit -> GFile.filter list
val make_all_working_filters_assoc : unit -> (Dot.output_format * GFile.filter) list

val combo_of_working_output_formats :
  ?active:Dot.output_format ->
  ?add_tearoffs:bool ->
  ?focus_on_click:bool ->
  ?has_frame:bool ->
  ?wrap_width:int ->
  ?width:int ->
  ?height:int ->
  ?packing:(GObj.widget -> unit) ->
  ?show:bool -> unit
  -> GEdit.combo_box * (unit -> Dot.output_format)
