(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009  Jean-Vincent Loddo

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

type 'a t = 'a option

let extract ?(failwith_msg="Option.extract") ?(fallback=(fun () -> failwith failwith_msg)) =
 function
  | None   -> fallback ()
  | Some x -> x

let extract_or xo y = match xo with
 | Some x -> x
 | None   -> y

let extract_or_force xo y = match xo with
 | Some x -> x
 | None   -> Lazy.force y

let extract_map_or xo f y = match xo with
 | Some x -> f x
 | None   -> y

let map f = function None -> None | Some x -> Some (f x)
let bind x f = match x with None -> None | Some x -> (f x)
let return x = Some x
let iter f = function None -> () | Some x -> (f x)
let join = function
| None -> None
| Some x -> x

(* Monadic definition: *)
let map2 f m1 m2  = bind m1 (function x1 -> map (f x1) m2)
let bind2 m1 m2 f = bind m1 (function x1 -> bind m2 (f x1))
let iter2 f m1 m2 = iter (function x1 -> iter (f x1) m2) m1

(* Extend a binary operation to 'a option.
   ---
   map_binop (max) None None ;;
   - : 'a option = None

   map_binop (max) None (Some 3) ;;
   - : int option = Some 3

  map_binop (max) (Some 5) (Some 3) ;;
  - : int option = Some 5
*)
let map_binop f x1 x2 =
  if x1 = None then x2 else
  if x2 = None then x1 else
  map2 f x1 x2

let filter p x = bind x (fun x -> if p x then Some x else None)

let of_fallible_application ?(fallback=fun _ _ -> ()) f x =
 try Some (f x) with e -> ((fallback e x); None)

let apply_or_catch ?(fallback=fun _ _ -> ()) f x =
 try Some (f x) with e -> ((fallback e x); None)

let protect f x = try Some (f x) with e -> None
let protect2 f x y = try Some (f x y) with e -> None
let protect3 f x y z = try Some (f x y z) with e -> None

(* val try_finalize : finally:('a -> (exn, 'b) Either.t -> 'c) -> ('a -> 'b) -> 'a -> 'b option *)
let try_finalize ~finally f x =
  let y = Either.protect f x in
  let _ = Either.protect2 finally x y in
  match y with
  | Either.Right y -> Some y
  | Either.Left e  -> None

(* val find   : 'a list -> ('a -> 'b option) -> 'b option *)
let rec find xs p =
  match xs with
  | []    -> None
  | x::xs ->
    (match (p x) with
     | None -> find xs p
     | y -> y
     )

(* val exists : 'a list -> ('a -> 'b option) -> bool
   exists xs f = ((find xs f) <> None) *)
let exists xs f = ((find xs f) <> None)
let for_all xs f = List.for_all (fun x -> (f x) <> None) (xs)

let extract_from_list ?(acc=[]) xs =
 let rec loop = function
 | [] -> acc
 | None::xs -> (loop xs)
 | (Some x)::xs -> x::(loop xs)
 in
 loop xs

let of_bool = function
 | false -> None
 | true  -> Some ()

let to_bool = function
 | None   -> false
 | Some _ -> true

let to_list = function None -> [] | Some x -> [x]

(* val split   : ('a * 'b) option -> 'a option * 'b option *)
let split = function
| Some (x1,x2) -> (Some x1), (Some x2)
| None -> None, None

let split3 = function
| Some (x1,x2,x3) -> (Some x1), (Some x2), (Some x3)
| None -> None, None, None

let split4 = function
| Some (x1,x2,x3,x4) -> (Some x1), (Some x2), (Some x3), (Some x4)
| None -> None, None, None, None

let split5 = function
| Some (x1,x2,x3,x4,x5) -> (Some x1), (Some x2), (Some x3), (Some x4), (Some x5)
| None -> None, None, None, None, None

(* val combine : 'a option -> 'b option -> ('a * 'b) option *)
let map3 f m1 m2 m3  = bind m1 (function x1 -> map2 (f x1) m2 m3)
let map4 f m1 m2 m3 m4 = bind m1 (function x1 -> map3 (f x1) m2 m3 m4)
let map5 f m1 m2 m3 m4 m5 = bind m1 (function x1 -> map4 (f x1) m2 m3 m4 m5)

let combine  x y = map2 (fun x y -> (x,y)) x y
let combine3 x y z = map3 (fun x y z -> (x,y,z)) x y z
let combine4 x y z t = map4 (fun x y z t -> (x,y,z,t)) x y z t
let combine5 x y z t u = map5 (fun x y z t u -> (x,y,z,t,u)) x y z t u

(** {b Examples}:
{[
# sprintf "[%4.2f]" None ;;
  : string = "None"

# sprintf ~none:"NULL" "[%4.2f]" None ;;
  : string = "NULL"

# Option.sprintf "[%4.2f]" (Some 3.14159) ;;
  : string = "Some [3.14]"

# Option.sprintf ~frame:"(The result is %s)" "[%4.2f]" (Some 3.14159) ;;
  : string = "(The result is [3.14])"
]}*)
let sprintf ?(none="None") ?frame fmt =
  function
  | None   -> none
  | Some x ->
     (match frame with
     | None      -> Printf.sprintf "Some %s" (Printf.sprintf fmt x)
     | Some fmt' -> Printf.sprintf fmt' (Printf.sprintf fmt x)
     )

let printf ?none ?frame fmt x =
  Printf.printf "%s" (sprintf ?none ?frame fmt x)

let eprintf ?none ?frame fmt x =
  Printf.eprintf "%s" (sprintf ?none ?frame fmt x)

let to_string ?none ?frame ?(a=fun _ -> "<abstr>") x =
  let y = map a x in
  sprintf ?none ?frame "%s" y

let update ?latter x0 =
 if latter = None then x0 else latter
