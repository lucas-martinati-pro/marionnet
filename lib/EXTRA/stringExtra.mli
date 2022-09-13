(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009-2011 Jean-Vincent Loddo

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

(** Additional features for the standard module [String]. *)

IFNDEF OCAML4_02_OR_LATER THEN
type bytes = string
ENDIF

(** {2 Importing & copying} *)

type blit_function = bytes -> int -> bytes -> int -> int -> unit
val blitting : perform:(char -> int -> unit) -> blit_function

val from_descr   : ?blit:blit_function -> Unix.file_descr -> string
val from_file    : ?blit:blit_function -> string -> string
val from_channel : ?blit:blit_function -> in_channel -> string
val from_string  : perform:(char -> int -> unit) -> string -> string

(** {2 Searching indexes} *)

val nth_index_from  : string -> int -> char -> int -> int
val nth_rindex_from : string -> int -> char -> int -> int
val nth_index       : string -> char -> int -> int
val nth_rindex      : string -> char -> int -> int
val for_all         : (char -> bool) -> string -> bool
val for_all_i       : (int -> char -> bool) -> string -> bool
val exists          : (char -> bool) -> string -> bool
val exists_i        : (int -> char -> bool) -> string -> bool
val lexists         : (char -> bool) -> string -> int option
val rexists         : (char -> bool) -> string -> int option

(** {2 Relations} *)

val is_prefix      : string -> string -> bool
val absorption     : string list -> string list

(** {2 Extracting sub-strings} *)

val tail          : string -> int -> string
val head          : string -> int -> string
val frame         : string -> char -> int -> int -> string
val frame_strict  : string -> char -> int -> int -> string
val rframe        : string -> char -> int -> int -> string
val rframe_strict : string -> char -> int -> int -> string

(** {2 Counting} *)

val count                      : string -> char -> int
val count_and_last_index       : string -> char -> int * int
val count_and_last_two_indexes : string -> char -> int * int * int

(** {2 Stripping} *)

val not_blank : char -> bool
val lstrip    : string -> string
val rstrip    : string -> string
val strip     : string -> string
val chop      : string -> string

(** {2 Considering as a char array} *)

val init         : int -> (int -> char) -> string
val iteri        : (int -> char -> unit) -> string -> unit
val iter2        : (char -> char -> unit) -> string -> string -> unit
val iteri2       : (int -> char -> char -> unit) -> string -> string -> unit
val map          : (char -> char) -> string -> string
val mapi         : (int -> char -> char) -> string -> string
val map2         : (char -> char -> char) -> string -> string -> string
val mapi2        : (int -> char -> char -> char) -> string -> string -> string
val fold_left    : ('a -> char -> 'a) -> 'a -> string -> 'a
val fold_lefti   : (int -> 'a -> char -> 'a) -> 'a -> string -> 'a
val fold_left2   : ('a -> char -> 'b -> 'a) -> 'a -> string -> 'b array -> 'a
val fold_lefti2  : (int -> 'a -> char -> 'b -> 'a) -> 'a -> string -> 'b array -> 'a
val fold_right   : (char -> 'a -> 'a) -> string -> 'a -> 'a
val fold_righti  : (int -> char -> 'a -> 'a) -> string -> 'a -> 'a
val fold_right2  : (char -> 'a -> 'b -> 'b) -> string -> 'a array -> 'b -> 'b
val fold_righti2 : (int -> char -> 'a -> 'b -> 'b) -> string -> 'a array -> 'b -> 'b

(** {2 Splitting to char list} *)

val to_charlist : string -> char list
val of_charlist : char list -> string
val expand : (char -> string option) -> string -> string
val tr : char -> char -> string -> string
val rm : char -> string -> string

module Charlist :
  sig
    val assemble              : char list -> string
    val disassemble_reversing : ?acc:char list -> string -> char list
    val assemble_reversing    : ?length:int -> char list -> string
  end

(** {2 Splitting to string list} *)

val cut   : ?n:int -> string -> string list
val split : ?do_not_squeeze:unit -> ?d:char -> string -> string list
val split_squeezing_blanks : ?blanks:char list -> string -> string list

(* The index of the word is in the range 1..n as in `awk'. Blanks are automatically squeezed.
   If the index is out of bounds, the result is the empty string (as in `awk').
   For better performance, should be applied partially providing the input string, then applied
   for several indexes. *)
val word : ?blanks:char list -> string -> int (* 1..n *) -> string

(** {2 Merging strings} *)

val concat       : ?blit:blit_function -> string list -> string
val quote        : ?l:string -> ?r:string -> string -> string
val assemble_if_not_empty : prefix:string -> suffix:string -> string -> string
val map_concat   : ?sep:string -> ('a -> string) -> 'a list -> string
val merge_fields : string -> int list -> string list -> string

(** {2 Text} *)

type word = string
val ensure_cr_at_end : string -> string

module Text :
  sig
    type t = string list
    type line = string
    val to_string : t -> string
    val of_string : ?do_not_squeeze:unit -> string -> t
    val from_file : ?do_not_squeeze:unit -> string -> t
    val grep      : ?before:int -> ?after:int -> Str.regexp -> t -> t
    (* --- *)
    val merge_lines        : ?sep:string -> int -> t -> t
    val collapse_and_split : ?do_not_squeeze:unit -> ?d:char -> t -> word list
    (* --- *)
    module Matrix :
      sig
        type t = word list list
        type line = word list
        val of_string : ?do_not_squeeze:[< `cr | `d | `neither ] -> ?d:char -> string -> t
        val to_string : ?d:string -> t -> string
        val from_file : ?do_not_squeeze:[< `cr | `d | `neither ] -> ?d:char -> string -> t
      end
  end

val fmt : ?tab:int -> ?prefix:string -> ?count_all:unit -> ?width:int -> string -> string
val tab : ?tab:int -> ?prefix:string -> string -> string
val make_wide : string -> int -> string
