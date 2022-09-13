(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008  Luca Saiu
   Copyright (C) 2009, 2010, 2017  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2009, 2010, 2017  Université Paris 13

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


type thunk = unit -> unit
 and  task = thunk

val do_in_parallel : thunk list -> unit

exception Kill_task_runner

class task_runner :
  object
    method prepend           : ?name:string -> task -> unit
    method run               : string -> task -> unit
    method schedule          : ?name:string -> task -> unit
    method schedule_parallel : (string * task) list -> unit
    method schedule_tasks    :  (string * string list * task) list -> unit
    (* --- *)
    method wait_for_all_currently_scheduled_tasks : unit
  end

val the_task_runner : task_runner
