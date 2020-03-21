(* This file is part of ocamlbricks
   Copyright (C) 2011, 2012 Jean-Vincent Loddo

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


(** High-level interface for client-server programming. *)

exception Accepting of exn
exception Connecting of exn
exception Receiving of exn
exception Sending   of exn
exception Closing   of exn
exception Binding   of exn

val string_of_sockaddr             : Unix.sockaddr -> string
val socketfile_of_sockaddr         : Unix.sockaddr -> string
val inet_addr_and_port_of_sockaddr : Unix.sockaddr -> Unix.inet_addr * int

val domain_of_inet_addr : Unix.inet_addr -> Unix.socket_domain

(** Example:
{[# Network.socketname_in_a_fresh_made_directory "ctrl" ;;
  : string = "/tmp/.toplevel-2dd2c2-sockets/ctrl"

# Sys.file_exists "/tmp/.toplevel-2dd2c2-sockets/ctrl" ;;
  : bool = false

# Sys.file_exists "/tmp/.toplevel-2dd2c2-sockets" ;;
  : bool = true

# exit 0 ;;
$ test -e /tmp/.toplevel-2dd2c2-sockets || echo "Directory automatically removed"
Directory automatically removed
]} *)
val socketname_in_a_fresh_made_directory :
  ?temp_dir:string ->
  ?prefix:string ->
  ?suffix:string ->
  ?perm:int->
  string -> string

val fresh_socketname :
  ?temp_dir:string ->
  ?prefix:string ->
  ?suffix:string ->
  unit -> string

class stream_channel :
  ?max_input_size:int ->
  Unix.file_descr ->
  object
    method send    : string -> unit
    method receive : ?at_least:int -> unit -> string
    method peek    : ?at_least:int -> unit -> string option

    method input_char       : unit -> char
    method input_line       : unit -> string
    method input_byte       : unit -> int
    method input_binary_int : unit -> int
    method input_value      : unit -> 'a

    method output_char       : char -> unit
    method output_line       : string -> unit
    method output_byte       : int -> unit
    method output_binary_int : int -> unit
    method output_value      : 'b -> unit

    method shutdown : ?receive:unit -> ?send:unit -> unit -> unit

    method sockaddr0 : Unix.sockaddr
    method sockaddr1 : Unix.sockaddr

    method get_recv_wait_at_least : int
    method get_send_wait_at_least : int
    method set_recv_wait_at_least : int -> unit
    method set_send_wait_at_least : int -> unit

    method get_recv_buffer_size : int
    method get_send_buffer_size : int
    method set_recv_buffer_size : int -> unit
    method set_send_buffer_size : int -> unit

    method get_close_linger : int option
    method set_close_linger : int option -> unit

  end


val line_oriented_channel_of_stream_channel : stream_channel ->
  < receive : unit   -> string;
    send    : string -> unit;
    peek    : unit   -> string option;
    >


class seqpacket_channel :
  ?max_input_size:int ->
  Unix.file_descr ->
  object
    method send    : string -> unit
    method receive : unit -> string
    method peek    : unit -> string option

    method shutdown : ?receive:unit -> ?send:unit -> unit -> unit

    method sockaddr0 : Unix.sockaddr
    method sockaddr1 : Unix.sockaddr

    method get_recv_buffer_size : int
    method get_send_buffer_size : int
    method set_recv_buffer_size : int -> unit
    method set_send_buffer_size : int -> unit

    method get_close_linger : int option
    method set_close_linger : int option -> unit

  end

class dgram_channel :
  ?max_input_size:int ->
  fd0:Unix.file_descr ->
  sockaddr1:Unix.sockaddr ->
  unit ->
  object

    method send    : string -> unit
    method receive : unit -> string
    method peek    : unit -> string option

    method shutdown : ?receive:unit -> ?send:unit -> unit -> unit

    method sockaddr0 : Unix.sockaddr
    method sockaddr1 : Unix.sockaddr

    method chmod_sockaddr0 : int -> unit

    method get_recv_buffer_size : int
    method get_send_buffer_size : int
    method set_recv_buffer_size : int -> unit
    method set_send_buffer_size : int -> unit

    method get_close_linger : int option
    method set_close_linger : int option -> unit

end

val dgram_input_socketfile_of :
  ?dgram_output_socketfile:string ->
  stream_socketfile:string ->
  unit ->  Unix.file_descr * Unix.sockaddr * string

val dgram_input_port_of :
  ?dgram_output_port:int ->
  my_stream_inet_addr:Unix.inet_addr ->
  unit -> Unix.file_descr * Unix.sockaddr * int

type 'a stream_protocol    = stream_channel    -> 'a
type 'a seqpacket_protocol = seqpacket_channel -> 'a
type 'a dgram_protocol     = (stream_channel -> dgram_channel) * (dgram_channel -> 'a)

(** The behaviour of the thread tutoring a created process may be provided specifying
    what there is to do before and what to do after waiting the termination of the process. *)
type tutoring_thread_behaviour = ThreadExtra.Easy_API.options

(** {2 Seqpacket Unix Domain } *)

val seqpacket_unix_server :
  ?max_pending_requests:int ->
  ?max_input_size:int ->
  ?tutor_behaviour:tutoring_thread_behaviour ->
  ?no_fork:unit ->
  ?socketfile:string ->
  protocol:(seqpacket_channel -> unit) ->
  unit -> Thread.t * string

val seqpacket_unix_client :
  ?max_input_size:int ->
  socketfile:string ->
  protocol:(seqpacket_channel -> 'a) ->
  unit -> (exn,'a) Either.t

(** {2 Stream Unix Domain } *)

val stream_unix_server :
  ?max_pending_requests:int ->
  ?max_input_size:int ->
  ?tutor_behaviour:tutoring_thread_behaviour ->
  ?no_fork:unit ->
  ?socketfile:string ->
  protocol:(stream_channel -> unit) ->
  unit -> Thread.t * string

val stream_unix_client :
  ?max_input_size:int ->
  socketfile:string ->
  protocol:(stream_channel -> 'a) ->
  unit -> (exn,'a) Either.t

(** {2 Stream Internet Domain } *)

val stream_inet4_server :
  ?max_pending_requests:int ->
  ?max_input_size:int ->
  ?tutor_behaviour:tutoring_thread_behaviour ->
  ?no_fork:unit ->
  ?range4:string ->
  ?ipv4:string ->
  ?port:int ->
  protocol:(stream_channel -> unit) ->
  unit -> Thread.t * string * int

val stream_inet6_server :
  ?max_pending_requests:int ->
  ?max_input_size:int ->
  ?tutor_behaviour:tutoring_thread_behaviour ->
  ?no_fork:unit ->
  ?range6:string ->
  ?ipv6:string ->
  ?port:int ->
  protocol:(stream_channel -> unit) ->
  unit -> Thread.t * string * int

val stream_inet_server :
  ?max_pending_requests:int ->
  ?max_input_size:int ->
  ?tutor_behaviour:tutoring_thread_behaviour ->
  ?no_fork:unit ->
  ?range4:string ->
  ?range6:string ->
  ?ipv4:string ->
  ?ipv6:string ->
  ?port:int ->
  protocol:(stream_channel -> unit) ->
  unit -> (Thread.t * string * int) * (Thread.t * string * int)

val stream_inet_client :
  ?max_input_size:int ->
  ipv4_or_v6:string ->
  port:int ->
  protocol:(stream_channel -> 'a) ->
  unit -> (exn,'a) Either.t

(* datagram - unix *)

val dgram_unix_server :
  ?max_pending_requests:int ->
  ?stream_max_input_size:int ->
  ?tutor_behaviour:tutoring_thread_behaviour ->
  ?no_fork:unit ->
  ?socketfile:string ->
  bootstrap:(stream_channel -> dgram_channel) ->
  protocol:(dgram_channel -> unit) ->
  unit -> Thread.t * string

val dgram_unix_client :
  ?stream_max_input_size:int ->
  socketfile:string ->
  bootstrap:(stream_channel -> dgram_channel) ->
  protocol:(dgram_channel -> 'a) ->
  unit -> (exn,'a) Either.t

(* datagram - inet & inet6 *)

val dgram_inet4_server :
  ?max_pending_requests:int ->
  ?stream_max_input_size:int ->
  ?tutor_behaviour:tutoring_thread_behaviour ->
  ?no_fork:unit ->
  ?range4:string ->
  ?ipv4:string ->
  ?port:int ->
  bootstrap:(stream_channel -> dgram_channel) ->
  protocol:(dgram_channel -> unit) ->
  unit -> Thread.t * string * int

val dgram_inet6_server :
  ?max_pending_requests:int ->
  ?stream_max_input_size:int ->
  ?tutor_behaviour:tutoring_thread_behaviour ->
  ?no_fork:unit ->
  ?range6:string ->
  ?ipv6:string ->
  ?port:int ->
  bootstrap:(stream_channel -> dgram_channel) ->
  protocol:(dgram_channel -> unit) ->
  unit -> Thread.t * string * int

val dgram_inet_server :
  ?max_pending_requests:int ->
  ?stream_max_input_size:int ->
  ?tutor_behaviour:tutoring_thread_behaviour ->
  ?no_fork:unit ->
  ?range4:string ->
  ?range6:string ->
  ?ipv4:string ->
  ?ipv6:string ->
  ?port:int ->
  bootstrap:(stream_channel -> dgram_channel) ->
  protocol:(dgram_channel -> unit) ->
  unit -> (Thread.t * string * int) * (Thread.t * string * int)

val dgram_inet_client :
  ?stream_max_input_size:int ->
  ipv4_or_v6:string ->
  port:int ->
  bootstrap:(stream_channel -> dgram_channel) ->
  protocol:(dgram_channel -> 'a) ->
  unit -> (exn,'a) Either.t


module Socat : sig

 (* -------------------------------- *
         of_unix_stream_server
  * -------------------------------- *)

  val inet4_of_unix_stream_server :
    (* inet4 server parameters: *)
    ?max_pending_requests:int ->
    ?max_input_size:int ->
    ?tutor_behaviour:tutoring_thread_behaviour ->
    ?no_fork:unit ->
    ?range4:string ->
    ?ipv4:string ->
    ?port:int ->
    (* unix client parameters: *)
    socketfile:string ->
    unit ->
      (* inet4 server result: *)
      Thread.t * string * int

  val inet6_of_unix_stream_server :
    (* inet6 server parameters: *)
    ?max_pending_requests:int ->
    ?max_input_size:int ->
    ?tutor_behaviour:tutoring_thread_behaviour ->
    ?no_fork:unit ->
    ?range6:string ->
    ?ipv6:string ->
    ?port:int ->
    (* unix client parameters: *)
    socketfile:string ->
    unit ->
      (* inet6 server result: *)
      Thread.t * string * int

  val inet_of_unix_stream_server :
    (* inet4 and inet6 server parameters: *)
    ?max_pending_requests:int ->
    ?max_input_size:int ->
    ?tutor_behaviour:tutoring_thread_behaviour ->
    ?no_fork:unit ->
    ?range4:string ->
    ?range6:string ->
    ?ipv4:string ->
    ?ipv6:string ->
    ?port:int ->
    (* unix client parameters: *)
    socketfile:string ->
    unit ->
      (* inet4 and inet6 dual server result: *)
      (Thread.t * string * int) * (Thread.t * string * int)

  val unix_of_unix_stream_server :
    (* unix server parameters: *)
    ?max_pending_requests:int ->
    ?max_input_size:int ->
    ?tutor_behaviour:tutoring_thread_behaviour ->
    ?no_fork:unit ->
    ?socketfile:string ->
    (* unix client parameters: *)
    dsocketfile:string ->
    unit ->
      (* unix server result: *)
      Thread.t * string


 (* -------------------------------- *
         of_inet_stream_server
  * -------------------------------- *)

  val unix_of_inet_stream_server :
    (* unix server parameters: *)
    ?max_pending_requests:int ->
    ?max_input_size:int ->
    ?tutor_behaviour:tutoring_thread_behaviour ->
    ?no_fork:unit ->
    ?socketfile:string ->
    (* inet client parameters: *)
    ipv4_or_v6:string ->
    port:int ->
    unit ->
      (* unix server result: *)
      Thread.t * string

  val inet4_of_inet_stream_server :
    (* inet4 server parameters: *)
    ?max_pending_requests:int ->
    ?max_input_size:int ->
    ?tutor_behaviour:tutoring_thread_behaviour ->
    ?no_fork:unit ->
    ?range4:string ->
    ?ipv4:string ->
    ?port:int ->
    (* inet client parameters: *)
    ipv4_or_v6:string ->
    dport:int ->
    unit ->
      (* inet4 server result: *)
      Thread.t * string * int

  val inet6_of_inet_stream_server :
    (* inet4 server parameters: *)
    ?max_pending_requests:int ->
    ?max_input_size:int ->
    ?tutor_behaviour:tutoring_thread_behaviour ->
    ?no_fork:unit ->
    ?range6:string ->
    ?ipv6:string ->
    ?port:int ->
    (* inet client parameters: *)
    ipv4_or_v6:string ->
    dport:int ->
    unit ->
      (* inet4 server result: *)
      Thread.t * string * int

  val inet_of_inet_stream_server :
    (* inet4 server parameters: *)
    ?max_pending_requests:int ->
    ?max_input_size:int ->
    ?tutor_behaviour:tutoring_thread_behaviour ->
    ?no_fork:unit ->
    ?range4:string ->
    ?range6:string ->
    ?ipv4:string ->
    ?ipv6:string ->
    ?port:int ->
    (* inet client parameters: *)
    ipv4_or_v6:string ->
    dport:int ->
    unit ->
      (* inet4 and inet6 dual server result: *)
      (Thread.t * string * int) * (Thread.t * string * int)

end

IFDEF DOCUMENTATION_OR_DEBUGGING THEN
module Examples : sig

  (* Set to 10 (chars). This setting is useful to observe the distinct semantics of the
     server receive function according to the kind of socket (stream, dgram, seqpacket). *)
  val server_max_input_size : int

  val simple_echo_server_protocol : < receive : unit -> string; send : string -> unit; .. > -> unit
  val simple_echo_client_protocol : < receive : unit -> string; send : string -> unit; .. > -> unit

  (* Here the method #receive is redefined as #input_line, thus the parameter `max_input_size' is
     meaningless in this case and the whole line is received by the server: *)
  val stream_unix_echo_server : ?no_fork:unit -> ?socketfile:string -> unit -> Thread.t * string
  val stream_unix_echo_client : socketfile:string -> unit -> (exn, unit) Either.t

  (* Sending a message bigger than 10 characters, we receive a bad (trunked) echo: *)
  val seqpacket_unix_echo_server : ?no_fork:unit -> ?socketfile:string -> unit -> Thread.t * string
  val seqpacket_unix_echo_client : socketfile:string -> unit -> (exn, unit) Either.t

  val dgram_unix_echo_server : ?no_fork:unit -> ?stream_socketfile:string -> unit -> Thread.t * string
  val dgram_unix_echo_client : stream_socketfile:string -> unit -> (exn, unit) Either.t

  val stream_inet_echo_server : ?no_fork:unit -> ?inet6:unit -> ?port:int -> unit -> Thread.t * string * int
  val stream_inet_echo_client : ipv4_or_v6:string -> port:int -> unit -> (exn, unit) Either.t

  val dgram_inet_echo_server : ?no_fork:unit -> ?inet6:unit -> ?port:int -> unit -> Thread.t * string * int
  val dgram_inet_echo_client : ipv4_or_v6:string -> port:int -> unit -> (exn, unit) Either.t

end
ENDIF
