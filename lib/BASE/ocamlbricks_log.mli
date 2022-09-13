(* This file is part of ocamlbricks
   Copyright (C) 2011 Jean-Vincent Loddo

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

val enable  : ?level:int (* 1 *) -> unit -> unit
val disable : unit -> unit

val printf  : ?v:int -> ?force:bool -> ?banner:bool -> ((unit, out_channel, unit) format) -> unit
val printf1 : ?v:int -> ?force:bool -> ?banner:bool -> (('a -> unit, out_channel, unit) format) -> 'a -> unit
val printf2 : ?v:int -> ?force:bool -> ?banner:bool -> (('a -> 'b -> unit, out_channel, unit) format) -> 'a -> 'b -> unit
val printf3 : ?v:int -> ?force:bool -> ?banner:bool -> (('a -> 'b -> 'c -> unit, out_channel, unit) format) -> 'a -> 'b -> 'c -> unit
val printf4 : ?v:int -> ?force:bool -> ?banner:bool -> (('a -> 'b -> 'c -> 'd -> unit, out_channel, unit) format) -> 'a -> 'b -> 'c -> 'd -> unit
val printf5 : ?v:int -> ?force:bool -> ?banner:bool -> (('a -> 'b -> 'c -> 'd -> 'e -> unit, out_channel, unit) format) -> 'a -> 'b -> 'c -> 'd -> 'e -> unit
val printf6 : ?v:int -> ?force:bool -> ?banner:bool -> (('a -> 'b -> 'c -> 'd -> 'e -> 'f -> unit, out_channel, unit) format) -> 'a -> 'b -> 'c -> 'd -> 'e -> 'f -> unit
val printf7 : ?v:int -> ?force:bool -> ?banner:bool -> (('a -> 'b -> 'c -> 'd -> 'e -> 'f -> 'g -> unit, out_channel, unit) format) -> 'a -> 'b -> 'c -> 'd -> 'e -> 'f -> 'g -> unit

val print_exn     : ?v:int -> ?force:bool -> ?banner:bool -> ?prefix:string -> ?suffix:string -> exn -> unit

module Unprotected:
  sig
    val printf        : ?v:int -> ?force:bool -> ?banner:bool -> (('a, out_channel, unit) format) -> 'a
    val print_exn     : ?v:int -> ?force:bool -> ?banner:bool -> ?prefix:string -> ?suffix:string -> exn -> unit
  end

module Tuning :
  sig
    val verbosity      : unit -> int
    val debug_level    : unit -> int
    val is_log_enabled : ?v:int -> unit -> bool
    val log_channel    : Log_builder.log_channel
    val synchronized   : bool

    module Set :
      sig
        val verbosity   : int -> unit
        val debug_level : (unit -> int) -> unit
      end
  end
