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

(** Script control server: a line-oriented control channel on a unix socket, served
    in-process, so that Marionnet may be driven by a script (or by an agent) while its GUI
    stays alive and observable. A request is a plain text line; an answer is exactly one
    JSON line. Work-stream `marionnet-pilotage-par-script', see docs/pilotage-par-script.md;
    the user guide is doc-src/scripting/README.md.

    {2 What a reader of this file needs to know}

    This module exports ONE value. Everything else — the grammar, the ~180 top-level items
    implementing it, the JSON writers — is deliberately private, for two reasons:

    - the vocabulary of the channel is not published as OCaml, it is published {b by the
      server itself}, through the [help] command (which answers with the arity of every
      command). That is the "single source" rule of this work-stream: [mrnctl],
      [mrn-check], [mrn2sh] and the Bash completion all derive their grammar from [help],
      so adding a verb here makes it usable and documented everywhere at once. A second
      declaration of the grammar, in an .mli or elsewhere, would defeat exactly that;

    - the channel offers {b the same possibilities and the same limits as the GUI}: it
      calls the very same model, and the state machine of the components is its contract
      (docs/pilotage-par-script.md § 4.10). Its commands are therefore not a separate API
      one could usefully expose to other OCaml modules.

    {2 Invariants worth remembering before touching the implementation}

    - The server is {b opt-in}: without [--control-socket PATH] no socket is created, hence
      no attack surface.
    - It is {b in-process and does not fork} ([~no_fork:()]): forking a GTK process owning
      UML children would be catastrophic. One thread per session, their number bounded.
    - Every mutation of the model goes through [GMain_actor], since only the GTK main
      thread may touch Gtk+ — and, symmetrically, the GTK thread never takes a component's
      mutex (docs/refonte-automate-composants.md).
    - SIGPIPE is neutralised in [marionnet.ml], not here: a global signal disposition
      belongs to the program. Without it a client hanging up kills Marionnet silently. *)

(** Start the control server if, and only if, the option [--control-socket PATH] was given
    ([Initialization.option_control_socket]); otherwise do nothing.

    Called once by [marionnet.ml], after the GUI is built. It NEVER raises and never aborts
    the startup: a bad path, a directory it cannot create, a socket file already served by a
    live process, a [bind] failure — each is logged and Marionnet simply goes on without a
    control channel. A stale socket file left behind by a brutal exit is removed and does
    not prevent a restart. *)
val start_if_requested : State.globalState -> unit
