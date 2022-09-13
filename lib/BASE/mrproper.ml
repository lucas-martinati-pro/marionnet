(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009 2012  Jean-Vincent Loddo

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


let global_object = new Thunk.lifo_unit_protected_container ()

let register_thunk = global_object#register_thunk
let register_lazy  = global_object#register_lazy
let apply          = global_object#apply
let remove         = global_object#remove
let get            = global_object#get
let as_stack ()    = global_object#as_stack

let exit (code) =
  let () = apply () in
  (*Pervasives.*)exit code
