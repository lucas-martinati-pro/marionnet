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


(* Print immediately a message on stderr. For debugging purposes: *)
let pr fmt = Printf.kfprintf flush stderr fmt

(* Protect an action from any kind of exception: *)
let protect  f x : unit = try f x with _ -> ()
let protect2 f x y : unit = try f x y with _ -> () (* protect (f x) y *)
let protect3 f x y z : unit = try f x y z with e -> ()  (* protect (f x y) z *)

(* Protect an application from any kind of exception with an emergency result in standby: *)
let standby  y f x = try f x with _ -> y
let standby2 y f x1 x2 = try f x1 x2 with _ -> y (* standby y (f x1) x2 *)

(* Apply a function and detect if it returns an ordinary result without raising any exception: *)
let succeed  f x   : bool = try let _ = f x   in true with _ -> false
let succeed2 f x y : bool = try let _ = f x y in true with _ -> false (* succeed (f x) y *)

(* val try_finalize : finally:('a -> (exn, 'b) Either.t -> 'c) -> ('a -> 'b) -> 'a -> 'b *)
let try_finalize ~finally f x =
  let y = Either.protect f x in
  let _ = Either.protect2 finally x y in
  (* Either.raise: *)
  match y with
  | Either.Right y -> y
  | Either.Left e  -> raise e

(* val try_finalize2 : finally:('a -> 'b -> (exn, 'c) Either.t -> 'ignored) -> ('a -> 'b -> 'c) -> 'a -> 'b -> 'c  *)
let try_finalize2 ~finally f x1 x2 =
  try_finalize ~finally:(finally x1) (f x1) x2

(* Thread safe (read-only method): *)
let get_magic_identifier x =
  let r = Obj.repr x in
  let magic = (Obj.magic r : int) in
  magic

let print_repr_info x =
  let r = Obj.repr x in
  let magic = (Obj.magic r : int) in
  let is_block = Obj.is_block r in
  if not (is_block) then Printf.printf "not a block\nmagic: %d\n" magic else (* continue: *)
  let tag  = Obj.tag r in
  let size = Obj.size r in
  let () = Printf.printf "is_block: %b\ntag: %d\nsize: %d\nmagic: %d\n" is_block tag size magic in
  ()

(* Both polymorphic and physical, really magic: *)
(* val magic_physical_compare : 'a -> 'a -> int *)
let magic_physical_compare x y =
  if x==y then 0 else compare (get_magic_identifier x) (get_magic_identifier y)


let follow name f x =
  let () = pr "%s: ENTERING ...\n" name in
  let finally _ _ = pr "%s: RETURNING)\n" name in
  try_finalize ~finally f x

let follow2 name f x1 x2 =
  let () = pr "%s: ENTERING ...\n" name in
  let finally _ _ _ = pr "%s: RETURNING\n" name in
  try_finalize2 ~finally f x1 x2

(* This method exploits implicitely the global counter and lock used internally by OCaml for
   a thread-safe allocation. The generated identifiers (integers) are not progressive but new
   identifiers are greater than previously generated. This property may be fine to distinguish
   younger from older references. *)
let (*thread_safe_*)fresh_id : unit -> int =
  fun () -> Oo.id (object end)
