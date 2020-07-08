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

type ('a,'b) t = Left of 'a | Right of 'b
type ('a,'b) either = ('a,'b) t

let get_right =
 function
  | Right b -> b
  | Left  _ -> invalid_arg "Either.right"

let get_left =
 function
  | Left  a -> a
  | Right _ -> invalid_arg "Either.left"

let left x = Left x
let right x = Right x

let extract ?(failwith_msg="Either.extract") ?(fallback=(fun _ -> failwith failwith_msg)) =
 function
  | Left a -> fallback a
  | Right b -> b

let extract_or x y = match x with
 | Left  a -> y
 | Right b -> b

let extract_or_force x y = match x with
 | Left a -> Lazy.force y
 | Right b -> b

let extract_from_list ?(acc=[]) xs =
 let rec loop = function
 | [] -> acc
 | (Left _)::xs -> (loop xs)
 | (Right b)::xs -> b::(loop xs)
 in
 loop xs

let map (f:'a->'b) = function
 | Right b -> Right (f b)
 | Left  a -> Left a

let bind x f = match x with
 | Right b -> (f b)
 | Left  a -> Left a

let return b = Right b

let iter f = function
 | Right b -> (f b)
 | _ -> ()

let protect f x =
 try Right (f x) with e -> Left e

let protect2 f x y =
 try Right (f x y) with e -> Left e

let protect3 f x y z =
 try Right (f x y z) with e -> Left e

let force x =
 try Right (Lazy.force x) with e -> Left e

(* Alias: *)
let apply_or_catch = protect

let try_finalize ~finally f x =
  let y = protect f x in
  let _ = protect2 finally x y in
  y

(* If is_left, leave the exception slip away: *)
let extract_or_raise = function
| Right y -> y
| Left e  -> raise e

let swap = function
 | Left  x -> Right x
 | Right x -> Left x

let flip = swap

(* val find : 'a list -> ('a -> ('e,'b) Either) -> 'b option *)
let rec find xs p =
  match xs with
  | []    -> None
  | x::xs ->
    (match (p x) with
    | Left e -> find xs p
    | Right y -> Some y
    )

(* val exists : 'a list -> ('a -> ('e,'b) Either) -> bool
   exists xs f = ((find xs f) <> None) *)
let exists xs f = ((find xs f) <> None)

(* all right *)
let for_all xs f =
  List.for_all (fun x -> match (f x) with Left _ -> false | Right _ -> true) (xs)

let raise_first_if_any (eys : (exn, 'a) t list) : unit =
  match (find eys swap) with
  | None -> ()
  | Some e -> raise e


let of_bool = function
 | false -> Left ()
 | true  -> Right ()

let to_bool = function
 | Left  _ -> false
 | Right _ -> true

(* Alias for `to_bool': *)
let is_right = to_bool

(* to_bool |> not *)
let is_left = function
 | Left  _ -> true
 | Right _ -> false

(* val to_option : ('a,'b) t -> 'b option *)
let to_option = function
 | Left  _ -> None
 | Right b -> Some b

let to_list = function
 | Left  _ -> []
 | Right b -> [b]

let to_string ?(a=fun _ -> "_") ?(b=fun _ -> "_") =
 function
 | Left  x -> "Left "^(a x)
 | Right x -> "Right "^(b x)

module Bifunctor = struct

 let map : ('a0 -> 'a1) -> ('b0 -> 'b1) -> ('a0,'b0) t -> ('a1,'b1) t =
   fun f1 f2 ->
     function
     | Left  a -> Left  (f1 a)
     | Right b -> Right (f2 b)

end

