(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2010  Jean-Vincent Loddo
   Copyright (C) 2010  Université Paris 13

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

val s_ : string -> string
val f_ : ('a, 'b, 'c) format -> ('a, 'b, 'c) format

val localeprefix : string

(** Print, on the log, what the cascade choosing [localeprefix] decided: the candidate
    directories of each origin (dune-site, MARIONNET_LOCALEPREFIX, the development tree,
    Meta.localeprefix), the directory finally retained and the origin it comes from — and a
    warning when the retained catalogue is one found under /usr, which belongs to another
    Marionnet. The cascade runs at link time, when the log's debug level is still the constant
    0 of [Marionnet_log]; its messages are therefore kept aside and printed by this function,
    which [Initialization] calls as soon as the real level is set. Calling it twice prints
    twice: it has no other effect. *)
val log_diagnosis : unit -> unit
