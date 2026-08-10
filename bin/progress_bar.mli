(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008  Luca Saiu
   Copyright (C) 2010, 2023  Jean-Vincent Loddo
   Copyright (C) 2007-2023  Université Sorbonne Paris Nord (USPN)

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

(* "Please wait" dialogs shown during a slow operation (saving a project, copying COW files).
   ---
   THREAD DISCIPLINE — this module is meant to be called FROM A WORKER THREAD, and that is
   why both functions below are safe there: they do not touch Gtk+ directly, they go through
   `GMain_actor' (apply_extract / delegate). The caller therefore never has to wrap them.
   ---
   SELF-DESTRUCTION — a dialog is not only closed by `destroy_progress_bar_dialog'. Its own
   animation thread destroys it after ~max_lifetime seconds no matter what, so a forgotten
   dialog cannot survive the operation it was announcing. Consequently
   `destroy_progress_bar_dialog' may well be applied to an already destroyed window. *)

(** How the bar moves: [Pulse] bounces (progress unknown), [Fill f] fills the bar with the
    fraction returned by [f], which is called ~20 times over the dialog's lifetime and must
    return a float in [0., 1.]. [f] runs in the GTK main thread: keep it cheap and blocking-free. *)
type kind = Pulse | Fill of (unit -> float)

(** Build the dialog AND show it, returning its window.
    @param title the window title
    @param text_on_label the main (Pango markup) message
    @param text_on_sub_label an optional second line, omitted when [""]
    @param text_on_bar the text drawn inside the bar itself
    @param kind see {!type:kind}, [Pulse] by default
    @param modal when true the dialog cannot be closed by the user (delete-event is swallowed)
    @param position defaults to [`CENTER] when modal
    @param max_lifetime seconds after which the dialog destroys itself (10. by default) —
           a ceiling, not a schedule: it is normally destroyed earlier by the caller. *)
val make_progress_bar_dialog :
  ?title:string ->
  ?text_on_label:string ->
  ?text_on_sub_label:string ->
  ?text_on_bar:string ->
  ?kind:kind ->
  ?modal:bool ->
  ?position:Gtk.Tags.window_position ->
  ?max_lifetime:float ->
  unit -> GWindow.window

(** Close a dialog returned by {!make_progress_bar_dialog}. Idempotent in practice (the window
    may already have been destroyed by its own lifetime thread). *)
val destroy_progress_bar_dialog : GWindow.window -> unit
