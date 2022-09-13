(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Jean-Vincent Loddo

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

(** Basic shortcuts and syntactic sugar. *)

(** {2 Pipelines of functions } *)

(** Mnemonic (unix-reminiscent) and funny aliases for function composition. *)

(** Make a pipeline of functions. It's simply the function composition, of course,
    not a real pipeline (stream composition), so keep an eye on memory allocation. *)
let (||>) f g = fun x -> g (f x);;

(** {b Example}

  {[  "ls" => ( SSys.run || fst || SString.toList ) ;; ]}

{b Working with tuples} *)

let identity = fun x -> x;;
let id = identity ;;

let (@@) f g = fun (x,y) -> ((f x),(g y));;

let curry   f = fun x y   -> f (x,y) ;;
let uncurry f = fun (x,y) -> f x y   ;;

(** {b Example}. Definition of the pattern matching function :

{[ let match_pattern pat str : bool =
    let string_match (p,s) = (Str.string_match p s 0) in

    (pat,str) => ( (Str.regexp\@\@identity) || string_match ) ;;
]}
In this example, pat is given to Str.regexp and str is given to identity.

 {b Example}. Remove the element with the given index:
{[ let rmindex l i =
    (l,l) => ((identity\@\@indexes) || (uncurry List.combine) || (List.filter (fun (x,j) ->j<>i)) || List.split || fst) ;;]}*)

(** {2 Default for ['a option]} *)

(** Short cut for quickly open an optional value.

{b Example}
{[# let x = Some 4 ;;
val x : int option = Some 4
]}
Now you can write:
{[# x |=> 7 ;;
  : int = 4
]}
instead of write:
{[ match x with Some v -> v | None -> 7;; ]}
*)
let (|=>) (x:'a option) (default:'a) = match x with Some v -> v | None -> default;;

(** {2 Other shortcuts} *)

(** Other recurrent shortcuts. *)

(** Equivalent to [function () -> ()]. *)
let  nothing = function () -> () ;;

(** Equivalent to [()]. *)
let  skip    = () ;;

(** Equivalent to [int]. *)
type identifier = int;;


(** A {e filter} is function that transform elements in the same domain
   (endo-function). *)
type 'a filter = 'a -> 'a
;;

