(* This file is part of our reusable OCaml BRICKS library
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


(* Protect an action from any kind of exception: *)
let protect f x : unit = try f x with _ -> ()

(* Print immediately a message on stderr. For debugging purposes: *)
let pr fmt = Printf.kfprintf flush stderr fmt

(* val try_finalize : finally:('a -> (exn, 'b) Either.t -> 'c) -> ('a -> 'b) -> 'a -> 'b *)
let try_finalize ~finally f x =
  let y = Either.protect f x in
  let _ = Either.protect2 finally x y in
  (* Either.raise: *)
  match y with
  | Either.Right y -> y
  | Either.Left e  -> raise e

(* Apply a function and detect if it returns an ordinary result without raising any exception: *)
let succeed f x : bool = try let _ = f x in true with _ -> false
