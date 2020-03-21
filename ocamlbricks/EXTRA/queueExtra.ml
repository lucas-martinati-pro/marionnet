(* This file is part of ocamlbricks
   Copyright (C) 2013  Jean-Vincent Loddo

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

let to_list q =
  Queue.fold (fun xs x -> x::xs) [] q

let of_list xs =
  let result = Queue.create () in
  let () = List.iter (fun x -> Queue.push x result) xs in
  result

let filter_copy p q0 =
  let q1 = Queue.create () in
  let () = Queue.iter (fun x -> if p x then Queue.push x q1) q0 in
  q1

let filter p q0 =
  let q1 = Queue.create () in
  let () = Queue.iter (fun x -> if p x then Queue.push x q1) q0 in
  let () = Queue.clear q0 in
  Queue.iter (fun x -> Queue.push x q0) q1

let map f q0 =
  let q1 = Queue.create () in
  let () = Queue.iter (fun x -> Queue.push (f x) q1) q0 in
  let () = Queue.clear q0 in
  Queue.iter (fun x -> Queue.push x q0) q1

let map_copy f q0 =
  let q1 = Queue.create () in
  let () = Queue.iter (fun x -> Queue.push (f x) q1) q0 in
  q1

let rev_copy q0 =
  let s1 = Stack.create () in
  let q1 = Queue.create () in
  let () = Queue.iter (fun x -> Stack.push x s1) q0 in
  let () = Stack.iter (fun x -> Queue.push x q1) s1 in
  q1

let rev q0 =
  let s1 = Stack.create () in
  let () = Queue.iter (fun x -> Stack.push x s1) q0 in
  let () = Queue.clear q0 in
  Stack.iter (fun x -> Queue.push x q0) s1

(* The push against nature (the inserted element will be the first out): *)
let copush q0 x =
  let q1 = Queue.create () in
  let () = Queue.push x q1 in
  let () = Queue.iter (fun x -> Queue.push x q1) q0 in
  let () = Queue.clear q0 in
  Queue.iter (fun x -> Queue.push x q0) q1
