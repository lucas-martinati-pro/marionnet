(* This file is part of ocamlbricks
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


type filename = string (* Ex: "/dev/pts/10" *)
type pid = int

class stream_channel :
  ?max_input_size:int -> (* 1514 (like Ethernet 802.3) *)
  ?file_perm:int ->      (* 0o640 *)
  filename ->            (* Ex: "/dev/pts/10" *)
  object
    method send    : string -> unit
    method receive : ?at_least:int -> unit -> string
    method peek    : ?at_least:int -> unit -> (string, string) Either.t
    (* --- *)
    method input_char        : unit -> char
    (* Something goes wrong with this method => I remove it from the interface: *)
    (* method input_line        : unit -> string *)
    method input_byte        : unit -> int
    method input_binary_int  : unit -> int
    method input_value       : unit -> 'a
    (* --- *)
    method output_char       : char -> unit
    method output_line       : string -> unit
    method output_byte       : int -> unit
    method output_binary_int : int -> unit
    method output_value      : 'b -> unit
    (* --- *)
    method walk_through_the_exit_door : unit -> (exn, unit) Either.t
    (* protected from exceptions: *)
    method shutdown : ?receive:unit -> ?send:unit -> unit -> unit
    (* --- *)
    (* Low-level method (but suitable for Unix.select): *)
    method get_IO_file_descriptors : Unix.file_descr * Unix.file_descr (* input, output *)
  end

(* --- *)
module Apply_protocol : sig

  val as_call   : ?max_input_size:int -> ?file_perm:int -> filename:string -> protocol:(stream_channel -> 'a) -> unit ->  (exn,'a) Either.t
  val as_thread : ?max_input_size:int -> ?file_perm:int -> filename:string -> protocol:(stream_channel -> 'a) -> unit ->  (exn,'a) Either.t Future.t
  val as_fork   : ?max_input_size:int -> ?file_perm:int -> filename:string -> protocol:(stream_channel -> 'a) -> unit -> ((exn,'a) Either.t Future.t) * pid

end (* Apply_protocol *)
