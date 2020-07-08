(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2011  Jean-Vincent Loddo

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

(** A [Log_builder.Make] instance ready-to-use in the application loading this module.
    The [debug_level] is initially set to [0], the [verbosity] is set to [1], the [log_channel]
    is set to [`stderr] and [synchronized] is set to [true]. *)

(* Initialized later, by Global_options, in order to break the ciclic dependency: *)
include Log_builder.Make (struct
  let debug_level () = 0           (* the debug_level must be greater or equal to the verbosity, otherwise do nothing *)
  let verbosity = 1                (* the default value of verbosity for printing functions *)
  let log_channel = `stderr        (* put messages here *)
  let synchronized = true          (* using threads *)
 end);;

let enable ?(level=1) () = Tuning.Set.debug_level (fun () -> level)
let disable () = Tuning.Set.debug_level (fun () -> 0)

