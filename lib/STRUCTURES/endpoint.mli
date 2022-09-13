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

module Source :
 sig
  type t =
  | Unix_descr of Unix.file_descr
  | In_channel of in_channel
  | Filename   of string
  | String     of string
  | Empty

  val to_file_descr : t -> Unix.file_descr * bool
  val to_in_channel : t -> in_channel * bool
  val to_string : t -> string

  val with_file_descr : t -> (Unix.file_descr -> 'a) -> 'a
  val with_in_channel : t -> (in_channel -> 'a) -> 'a
  
(** {2 Source iterators (map, iter, fold) } *)
  
  type line = string
  type word = string
  type delimiter = char
  type recno = int   (* The total number of input records seen so far, starting from 1 *)
  type fieldno = int (* The total number of fields seen so far, starting from 1 *)

(** {b Iterators on lines } *)
  
  val fold_lines : ('a -> recno -> line -> 'a) -> 'a -> t -> 'a
  val  map_lines : (recno -> line -> 'a)   -> t -> 'a array
  val iter_lines : (recno -> line -> unit) -> t -> unit

(** {b Iterators on lines considered as word lists } *)
  
  val  map_word_lists : ?d:delimiter -> (recno -> word list -> 'a) -> t -> 'a array
  val iter_word_lists : ?d:delimiter -> (recno -> word list -> unit) -> t -> unit
  val fold_word_lists : ?d:delimiter -> ('a -> recno -> word list -> 'a) -> 'a -> t -> 'a
  
(** {b Iterators on lines considered as word arrays } *)

  val  map_word_arrays : ?d:delimiter -> (recno -> word array -> 'a) -> t -> 'a array
  val iter_word_arrays : ?d:delimiter -> (recno -> word array -> unit) -> t -> unit
  val fold_word_arrays : ?d:delimiter -> ('a -> recno -> word array -> 'a) -> 'a -> t -> 'a

(** {b Iterators on words } *)

  val fold_words : ?d:delimiter -> ('a -> recno -> fieldno -> word -> 'a) -> 'a -> t -> 'a
  val iter_words : ?d:delimiter -> (recno -> fieldno -> word -> unit) -> t -> unit
  val  map_words : ?d:delimiter -> (recno -> fieldno -> word -> 'a) -> t -> 'a array array
  
 end

module Sink :
 sig
  type t =
  | Unix_descr        of Unix.file_descr
  | Out_channel       of out_channel
  | Filename          of string
  | Filename_append   of string
  | Filename_overtype of string
  | Fun_thread        of (Unix.file_descr -> unit)
  | String_queue      of String_queue.t
  | Trash

  val to_file_descr  : t -> Unix.file_descr * bool
  val to_out_channel : t -> out_channel * bool
  val to_string : t -> string

  val with_out_channel : t -> (out_channel -> 'a) -> 'a
  val with_file_descr  : t -> (Unix.file_descr -> 'a) -> 'a

(** {2 Print arrays of strings}
Note that the names of the optional parameters [?rs] (line/record separator) and [?fs] (word/field separator) 
have been choosen to resemble to the corrispondent variables in [awk]. *)

  type line = string
  type word = string
  type linesep = string
  type wordsep = string

  val print_string      : t -> string -> unit
  val print_lines       : ?rs:linesep -> t -> line array -> unit
  val print_word_lists  : ?rs:linesep -> ?fs:wordsep -> t -> word list array -> unit
  val print_word_arrays : ?rs:linesep -> ?fs:wordsep -> t -> word array array -> unit

(** {2 Print arrays of tuples}
{b Example}:
{[
Sink.printf2 (Sink.Filename "/tmp/foo") "%s ==> %F\n"  [| ("AAA", 3.14); ("BBB", 6.28); |] ;;
  : unit = ()
 
UnixExtra.cat "/tmp/foo" ;;
  : string = "AAA ==> 3.14\nBBB ==> 6.28\n"
]} *)
  
  val printf1 : t -> 
    ('x1 -> unit, out_channel, unit) format -> 'x1 array -> unit
  
  val printf2 : t -> 
    ('x1 -> 'x2 -> unit, out_channel, unit) format ->
    ('x1 * 'x2) array -> unit

  val printf3 : t ->
    ('x1 -> 'x2 -> 'x3 -> unit, out_channel, unit) format ->
    ('x1 * 'x2 * 'x3) array -> unit

  val printf4 : t ->
    ('x1 -> 'x2 -> 'x3 -> 'x4 -> unit, out_channel, unit) format ->
    ('x1 * 'x2 * 'x3 * 'x4) array -> unit

  val printf5 : t ->
    ('x1 -> 'x2 -> 'x3 -> 'x4 -> 'x5 -> unit, out_channel, unit) format ->
    ('x1 * 'x2 * 'x3 * 'x4 * 'x5) array -> unit

  val printf6 : t ->
    ('x1 -> 'x2 -> 'x3 -> 'x4 -> 'x5 -> 'x6 -> unit, out_channel, unit) format ->
    ('x1 * 'x2 * 'x3 * 'x4 * 'x5 * 'x6) array -> unit

  val printf7 : t ->
    ('x1 -> 'x2 -> 'x3 -> 'x4 -> 'x5 -> 'x6 -> 'x7 -> unit, out_channel, unit) format ->
    ('x1 * 'x2 * 'x3 * 'x4 * 'x5 * 'x6 * 'x7) array -> unit

  val printf8 : t ->
    ('x1 -> 'x2 -> 'x3 -> 'x4 -> 'x5 -> 'x6 -> 'x7 -> 'x8 -> unit, out_channel, unit) format ->
    ('x1 * 'x2 * 'x3 * 'x4 * 'x5 * 'x6 * 'x7 * 'x8) array -> unit

  val printf9 : t ->
    ('x1 -> 'x2 -> 'x3 -> 'x4 -> 'x5 -> 'x6 -> 'x7 -> 'x8 -> 'x9 -> unit, out_channel, unit) format ->
    ('x1 * 'x2 * 'x3 * 'x4 * 'x5 * 'x6 * 'x7 * 'x8 * 'x9) array -> unit

  val printf10 : t ->
    ('x1 -> 'x2 -> 'x3 -> 'x4 -> 'x5 -> 'x6 -> 'x7 -> 'x8 -> 'x9 -> 'x10 -> unit, out_channel, unit) format ->
    ('x1 * 'x2 * 'x3 * 'x4 * 'x5 * 'x6 * 'x7 * 'x8 * 'x9 * 'x10) array -> unit

  val printf11 : t ->
    ('x1 -> 'x2 -> 'x3 -> 'x4 -> 'x5 -> 'x6 -> 'x7 -> 'x8 -> 'x9 -> 'x10 -> 'x11 -> unit, out_channel, unit) format ->
    ('x1 * 'x2 * 'x3 * 'x4 * 'x5 * 'x6 * 'x7 * 'x8 * 'x9 * 'x10 * 'x11) array -> unit

  val printf12 : t ->
    ('x1 -> 'x2 -> 'x3 -> 'x4 -> 'x5 -> 'x6 -> 'x7 -> 'x8 -> 'x9 -> 'x10 -> 'x11 -> 'x12 -> unit, out_channel, unit) format ->
    ('x1 * 'x2 * 'x3 * 'x4 * 'x5 * 'x6 * 'x7 * 'x8 * 'x9 * 'x10 * 'x11 * 'x12) array -> unit
  
 end
