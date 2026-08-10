(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008, 2009  Luca Saiu
   Copyright (C) 2010-2026  Jean-Vincent Loddo
   Copyright (C) 2007-2026 Université Sorbonne Paris Nord (USPN)
   Copyright (C) 2026 Université numérique Île-de-France (UNIF)

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

(* The welcome (splash) window: image, version, copyright, warranty and institutional logos.
   ---
   The whole window is BUILT AT MODULE INITIALIZATION, not by `show_splash': the widget
   tree, its labels and its click/key handlers are top-level side effects of splash.ml.
   `show_splash' only maps the already existing window. There is therefore exactly ONE
   splash window per process, and closing it destroys it for good.
   ---
   Not here: the "About" dialog, which is a different window entirely
   (bin/gui/gui_dialog_A_PROPOS.ml). *)

(** Show the splash window. Being a Gtk+ call, it must run in the GTK main thread — from any
    other thread, go through [GMain_actor] (see docs/ARCHITECTURE.md, § Concurrence).
    @param timeout milliseconds after which the window closes by itself (a [GMain.Timeout]);
    without it the window stays until the user clicks it or presses a key.
    Calling it again after the window has been closed is a no-op on a destroyed widget. *)
val show_splash : ?timeout:int -> unit -> unit
