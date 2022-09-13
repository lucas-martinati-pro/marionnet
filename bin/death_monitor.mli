(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2020  Jean-Vincent Loddo
   Copyright (C) 2020  Université Sorbonne Paris Nord

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

type process_name = string                      (* name of the executable program we're monitoring *)
type pid = int                                  (* process identifier *)
(* --- *)
type predicate = (pid -> bool)                  (* how to check whether we should invoke the callback *)
type callback  = (pid -> process_name -> unit)  (* the callback *)

(* By default the predicate which causes the callback invocation is "process not alive": *)
val start_monitoring  : ?predicate:(pid -> bool) -> pid -> process_name -> callback -> unit
val stop_monitoring   : pid -> unit
(* --- *)
val stop_polling_loop : unit -> unit
