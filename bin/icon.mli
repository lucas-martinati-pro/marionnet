(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008  Luca Saiu
   Copyright (C) 2010  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2010  Université Paris 13

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

(* The window icon of every Marionnet window, loaded once at module initialization.
   ---
   Which file is read depends on `Initialization.are_we_in_exam_mode': exam mode has
   its own launcher icon, so that a supervised session is recognizable at a glance.
   Both files live under `Initialization.Path.images'. *)

(** The pixbuf to pass as [~icon:] to every [GWindow.window] / [GWindow.dialog] of the
    application. Read from disk when this module is initialized: a missing image file is
    a startup failure, not a runtime one. *)
val icon_pixbuf : GdkPixbuf.pixbuf
