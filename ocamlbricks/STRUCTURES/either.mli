(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2012  Jean-Vincent Loddo

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

(** Operations on type [('a,'b) Either.t]. *)

type ('a,'b) t = Left of 'a | Right of 'b
type ('a,'b) either = ('a,'b) t

(** Extract the encapsulated value. If the argument is [Left a], the optional [?fallback] is called on the value [a].
    By default [fallback] is set to [fun _ -> failwith "Either.extract"].*)
val extract : ?failwith_msg:string -> ?fallback:('a -> 'b) -> ('a,'b) t -> 'b
val extract_or        : ('a,'b) t -> 'b -> 'b
val extract_or_force  : ('a,'b) t-> 'b Lazy.t -> 'b
val extract_from_list : ?acc:'b list -> ('a,'b) t list -> 'b list

(* Raise Invalid_argument *)
val get_left  : ('a,'b) t -> 'a
val get_right : ('a,'b) t -> 'b

val swap : ('a,'b) t -> ('b,'a) t
val flip : ('a,'b) t -> ('b,'a) t (* alias for `swap' *)

(* Injections: *)
val left  : 'a -> ('a,'b) t
val right : 'b -> ('a,'b) t

val iter : ('b -> unit) -> ('a,'b) t -> unit
val map  : ('b -> 'c) -> ('a,'b) t -> ('a,'c) t
val bind : ('a,'b) t -> ('b -> ('a,'c) t) -> ('a,'c) t
val return : 'b -> ('a,'b) t

val protect  : ('a -> 'b) -> 'a -> (exn, 'b) t
val protect2 : ('a -> 'b -> 'c) -> 'a -> 'b -> (exn, 'c) t
val protect3 : ('a -> 'b -> 'c -> 'd) -> 'a -> 'b -> 'c -> (exn, 'd) t

(* Protect lazy value application: *)
val force : ('a lazy_t) -> (exn, 'a) t

(* Note that ~finally is itself protected by exceptions and its result is ignored. *)
val try_finalize : finally:('a -> (exn, 'b) t -> 'ignored) -> ('a -> 'b) -> 'a -> (exn, 'b) t

(* If is_left, leave the exception slip away: *)
val extract_or_raise : (exn, 'a) t -> 'a

(* alias for `protect': *)
val apply_or_catch : ('a -> 'b) -> 'a -> (exn, 'b) t

val find    : 'a list -> ('a -> ('e,'b) t) -> 'b option
val exists  : 'a list -> ('a -> ('e,'b) t) -> bool
val for_all : 'a list -> ('a -> ('e,'b) t) -> bool

(* xs ⊢> Option.bind (find xs swap) (raise) |> ignore *)
val raise_first_if_any : (exn, 'a) t list -> unit

val of_bool   : bool -> (unit, unit) t
val to_bool   : ('a,'b) t -> bool
val is_right  : ('a,'b) t -> bool (* alias of to_bool *)
val is_left   : ('a,'b) t -> bool (* to_bool |> not *)
val to_option : ('a,'b) t -> 'b option
val to_list   : ('a,'b) t -> 'b list (* singleton or empty *)

val to_string : ?a:('a -> string) -> ?b:('b -> string) -> ('a, 'b) t -> string

module Bifunctor : sig
  val map : ('a0 -> 'a1) -> ('b0 -> 'b1) -> ('a0,'b0) t -> ('a1,'b1) t
end
