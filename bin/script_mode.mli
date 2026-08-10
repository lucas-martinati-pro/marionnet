(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2026  Jean-Vincent Loddo
   Copyright (C) 2026  Université Sorbonne Paris Nord

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

(** Script mode: what becomes of the windows Marionnet opens by itself when nobody is
    sitting in front of it.

    A driven session (control_server.ml, [--control-socket]) keeps the GUI alive and
    observable — that is the whole point of the architecture chosen for this work-stream —
    but Marionnet pops up windows on its own: the splash screen at startup, an information
    dialog when loading an old project had to adapt it (Mandriva images remapped to Trixie,
    kernels substituted...), a warning when a component dies. Left alone they pile up on
    the screen, and, worse, what they *say* is lost to the script: at episode 3a a failed
    [open] was found to report its cause in a non-modal dialog and nowhere else.

    So the answer is not merely "close them": it is *capture, then close*. Every message
    Marionnet would have shown is pushed here, with a monotonic sequence number, and the
    control server serves it as JSON (command [notifications], and inline in the answer to
    [open]). Closing without capturing would have thrown away exactly the information a
    script wants — the list of adaptations being the archetype.

    This module deliberately depends on nothing but Marionnet_log. It is used by
    bin/gui/simple_dialogs.ml, and initialization.ml transitively depends on user_level.ml,
    which depends on simple_dialogs.ml: reading the command line from here would close that
    cycle. Hence [configure], called by marionnet.ml (the root) before anything may show a
    window. *)

(** {2 Configuration} *)

(** Set both settings at once. Must be called by [marionnet.ml] BEFORE the GUI exists and
    before any thread is spawned: the two settings are then read without a mutex, which is
    only sound because nothing writes them afterwards. *)
val configure : enabled:bool -> auto_dismiss_ms:int -> unit

(** Is script mode on, i.e. was [--control-socket] given without [--keep-dialogs]? *)
val enabled : unit -> bool

(** How long a self-opened window stays visible before destroying itself
    ([--dialog-timeout], 2000 ms by default). Deliberately NOT zero: the session is meant to
    stay observable by a human, and the script does not care — it reads the capture. *)
val auto_dismiss_ms : unit -> int

(** {2 Captured messages} *)

type severity = [ `Info | `Warning ]

(** One line of a recapitulative dialog: a summary always visible, a detail behind an
    expander (bin/gui/simple_dialogs.ml, [recapitulative]). *)
type item = {
  summary  : string;
  detail   : string;
  severity : severity;
}

type kind = [ `Info | `Warning | `Error | `Help | `Recap | `Question ]

type notification = {
  seq   : int;      (** Monotonic, NEVER reset — not even by {!clear} — so that a client
                        holding a [--since] from before a clear is never served twice. *)
  time  : float;    (** Unix epoch, as returned by [Unix.gettimeofday]. *)
  kind  : kind;
  title : string;
  body  : string;
  items : item list;  (** Non-empty for a [`Recap] only. *)
}

(** The JSON spelling of the two variants, as served on the channel. *)
val string_of_kind : kind -> string
val string_of_severity : severity -> string

(** Capture one message Marionnet was about to show. Thread-safe, and also journalled to the
    log — a driven session is debugged from the log once the client is gone. The buffer is
    BOUNDED (200 entries, oldest dropped): this is an instrument, not a log file. *)
val notify : kind:kind -> title:string -> ?items:item list -> string -> unit

(** The captured messages in CHRONOLOGICAL order (oldest first), which is how a client wants
    to read them.
    @param since return only those whose [seq] is strictly greater (0, i.e. all, by default). *)
val notifications : ?since:int -> unit -> notification list

(** Drop the captured messages. The sequence counter is not reset; see {!notification}. *)
val clear : unit -> unit

(** The highest sequence number handed out so far — the [--since] a client should send next. *)
val last_seq : unit -> int

(** {2 While a command is being served} *)

(** Run [f], marking THE CALLING THREAD as serving a control-server command for its whole
    duration (re-entrant, and restored even if [f] raises). The scope is the thread, not a
    global flag, and that is essential: a human keeps clicking while the script runs, and a
    GUI callback fires in the GTK main thread, which is never registered here — so a
    confirmation asked by a human is never auto-answered by mistake. *)
val in_command : (unit -> 'a) -> 'a

(** True when a QUESTION must not be shown but answered with the default its caller
    provided, i.e. script mode is on {e and} the calling thread is inside {!in_command}.
    Evaluated by the dialog functions (simple_dialogs.ml, talking.ml) BEFORE they delegate
    to the GTK main thread — still in the caller's thread, which is what makes it meaningful. *)
val must_auto_answer : unit -> bool
