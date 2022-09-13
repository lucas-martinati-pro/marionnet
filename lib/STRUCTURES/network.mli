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

(* --------------------------- *)
(*     Abstract addresses      *)
(* --------------------------- *)

type filename = string
type socketfile = filename
type ipv4_or_v6 = string
type port = int

(* User-friendly server address specification: *)
type server_address = [
 | `unix  of socketfile
 | `inet  of ipv4_or_v6 * port
 ]

val string_of_server_address : server_address -> string

(* A channel is a "port", "gate" or "endpoint", *connected* in some way,
   in the general sense of "plugged", to another port, gate or endpoint
   accessible by the same or another thread, belonging the same or another
   process, running on the same or another OS. *)
(* --------------------------- *)
class type abstract_channel =
(* --------------------------- *)
  object
    method send    : string -> unit
    method receive : ?at_least:int -> unit -> string
    (* method peek : ?at_least:int -> unit -> (string, string) Either.t *)
    method shutdown : ?receive:unit -> ?send:unit -> unit -> unit
    (* Low-level (should be private) method. Descriptors may be the the same for input and output: *)
    method get_IO_file_descriptors : Unix.file_descr * Unix.file_descr
  end

(* --- *)

type pid = int

exception Accepting  of exn
exception Connecting of exn
exception Receiving  of exn
exception Sending    of exn
exception Closing    of exn
exception Binding    of exn

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

(* --------------------------- *)
class stream_channel :
(* --------------------------- *)
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

    (* The same for input and output: *)
    method get_IO_file_descriptors : Unix.file_descr * Unix.file_descr
  end


val line_oriented_channel_of_stream_channel : stream_channel ->
  < receive : unit   -> string;
    send    : string -> unit;
    peek    : unit   -> string option;
    >

(* --------------------------- *)
class seqpacket_channel :
(* --------------------------- *)
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

    (* The same for input and output: *)
    method get_IO_file_descriptors : Unix.file_descr * Unix.file_descr
  end

(* --------------------------- *)
class dgram_channel :
(* --------------------------- *)
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

    (* The same for input and output: *)
    method get_IO_file_descriptors : Unix.file_descr * Unix.file_descr
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
  ?tutor_behaviour:ThreadExtra.Easy_API.options ->
  ?no_fork:unit ->
  ?socketfile:string ->
  protocol:(seqpacket_channel -> unit) ->
  unit -> Thread.t * socketfile

val seqpacket_unix_client :
  ?max_input_size:int ->
  socketfile:string ->
  protocol:(seqpacket_channel -> 'a) ->
  unit -> (exn,'a) Either.t

(** {2 Stream Unix/Internet Domain } *)

(* Multi-domain (unix/inet) stream client: *)
val stream_client :
  ?max_input_size:int ->
  target:server_address -> (* Ex: `unix("/tmp/.X11-unix/X0") or `inet("192.168.1.16", 80) *)
  protocol:(stream_channel -> 'a) ->
  unit -> (exn,'a) Either.t

val stream_unix_server :
  ?max_pending_requests:int ->
  ?max_input_size:int ->
  ?tutor_behaviour:ThreadExtra.Easy_API.options ->
  ?no_fork:unit ->
  ?socketfile:string ->
  protocol:(stream_channel -> unit) ->
  unit -> Thread.t * socketfile

val stream_inet4_server :
  ?max_pending_requests:int ->
  ?max_input_size:int ->
  ?tutor_behaviour:ThreadExtra.Easy_API.options ->
  ?no_fork:unit ->
  ?range4:string ->
  ?ipv4:Ipv4.string ->
  ?port:int ->
  protocol:(stream_channel -> unit) ->
  unit -> Thread.t * Ipv4.string * port

val stream_inet6_server :
  ?max_pending_requests:int ->
  ?max_input_size:int ->
  ?tutor_behaviour:ThreadExtra.Easy_API.options ->
  ?no_fork:unit ->
  ?range6:string ->
  ?ipv6:Ipv6.string ->
  ?port:int ->
  protocol:(stream_channel -> unit) ->
  unit -> Thread.t * Ipv6.string * port

(* Dual stack server (both IPv4&v6): *)
val dual_stream_inet_server :
  ?max_pending_requests:int ->
  ?max_input_size:int ->
  ?tutor_behaviour:ThreadExtra.Easy_API.options ->
  ?no_fork:unit ->
  ?range4:string ->
  ?range6:string ->
  ?ipv4:Ipv4.string ->
  ?ipv6:Ipv6.string ->
  ?port:int ->
  protocol:(stream_channel -> unit) ->
  unit -> (Thread.t * Ipv4.string * port) * (Thread.t * Ipv6.string * port)

(** {2 Datagram Unix/Internet Domain } *)

(* Multi-domain (unix/inet) datagram client: *)
val dgram_client :
  ?stream_max_input_size:int ->
  target:server_address -> (* Ex: `unix("/tmp/.X11-unix/X0") or `inet("192.168.1.16", 80) *)
  bootstrap:(stream_channel -> dgram_channel) ->
  protocol:(dgram_channel -> 'a) ->
  unit -> (exn,'a) Either.t

(* datagram - unix server *)

val dgram_unix_server :
  ?max_pending_requests:int ->
  ?stream_max_input_size:int ->
  ?tutor_behaviour:ThreadExtra.Easy_API.options ->
  ?no_fork:unit ->
  ?socketfile:string ->
  bootstrap:(stream_channel -> dgram_channel) ->
  protocol:(dgram_channel -> unit) ->
  unit -> Thread.t * socketfile


(* datagram - inet4 & inet6 servers *)

val dgram_inet4_server :
  ?max_pending_requests:int ->
  ?stream_max_input_size:int ->
  ?tutor_behaviour:ThreadExtra.Easy_API.options ->
  ?no_fork:unit ->
  ?range4:string ->
  ?ipv4:Ipv4.string ->
  ?port:int ->
  bootstrap:(stream_channel -> dgram_channel) ->
  protocol:(dgram_channel -> unit) ->
  unit -> Thread.t * Ipv4.string * port

val dgram_inet6_server :
  ?max_pending_requests:int ->
  ?stream_max_input_size:int ->
  ?tutor_behaviour:ThreadExtra.Easy_API.options ->
  ?no_fork:unit ->
  ?range6:string ->
  ?ipv6:Ipv6.string ->
  ?port:int ->
  bootstrap:(stream_channel -> dgram_channel) ->
  protocol:(dgram_channel -> unit) ->
  unit -> Thread.t * Ipv6.string * port

(* Dual stack server (both IPv4&v6): *)
val dual_dgram_inet_server :
  ?max_pending_requests:int ->
  ?stream_max_input_size:int ->
  ?tutor_behaviour:ThreadExtra.Easy_API.options ->
  ?no_fork:unit ->
  ?range4:string ->
  ?range6:string ->
  ?ipv4:Ipv4.string ->
  ?ipv6:Ipv6.string ->
  ?port:int ->
  bootstrap:(stream_channel -> dgram_channel) ->
  protocol:(dgram_channel -> unit) ->
  unit -> (Thread.t * Ipv4.string * port) * (Thread.t * Ipv6.string * port)


(* ----------------*)
module Socat : sig
(* ----------------*)

(* (Using "UTF-8 Box Drawing")

                  ┌┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┐
                  ┆              (Process)               ┆
                  ┆            crossover-link            ┆
                  ┆     chA                     chB      ┆
     ░░░░░░░░░░░░░┆    ┌───┐receive     receive┌───┐     ┆░░░░░░░░░░░░░
     ░░░░░░░░░░┄┄┄┄┄┄┄>│ 0 │───────>\ /<───────│ 0 │<┄┄┄┄┄┄┄░░░░░░░░░░░
     ░░░░░░░░░░░░░┆    ├───┤         ╳         ├───┤     ┆░░░░░░░░░░░░░
     ░░░░░░░░░░<┄┄┄┄┄┄┄│ 1 │<───────/ \───────>│ 1 │┄┄┄┄┄┄┄>░░░░░░░░░░░
     ░░░░░░░░░░░░░┆    └───┘ send         send └───┘     ┆░░░░░░░░░░░░░
     ░░░░░░░░░░░░░└┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┘░░░░░░░░░░░░░
     ░░░░░░░░░░░░░░░░░░░░  Unix Operating System  ░░░░░░░░░░░░░░░░░░░░░
     ░░░░░░░░░░░░░░░ acting itself as a crossover-link ░░░░░░░░░░░░░░░░
     ░░░░░░░░░░░ with other endpoints for both chA and chB. ░░░░░░░░░░░
     ░░ Such related endpoints may be TCP/IP sockets (TCP/UDP/SCTP), ░░
     ░░░  Unix sockets, pseudo-terminals, etc, and may require the  ░░░
     ░░░ support of Internet (IPv4/v6) as well as the local system. ░░░
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
*)

 (* -------------------------------- *
         of_stream_server
  * -------------------------------- *)

  val unix_of_stream_server :
    (* unix server parameters: *)
    ?max_pending_requests:int ->
    ?max_input_size:int ->
    ?tutor_behaviour:ThreadExtra.Easy_API.options ->
    ?no_fork:unit ->
    ?socketfile:string ->
    (* client parameters: *)
    target:server_address -> (* Ex: `unix("/tmp/.X11-unix/X0") or `inet("192.168.1.16", 80) *)
    unit ->
      (* unix server result: *)
      Thread.t * socketfile

  val inet4_of_stream_server :
    (* inet4 server parameters: *)
    ?max_pending_requests:int ->
    ?max_input_size:int ->
    ?tutor_behaviour:ThreadExtra.Easy_API.options ->
    ?no_fork:unit ->
    ?range4:string ->
    ?ipv4:Ipv4.string ->
    ?port:int ->
    (* client parameters: *)
    target:server_address -> (* Ex: `unix("/tmp/.X11-unix/X0") or `inet("192.168.1.16", 80) *)
    unit ->
      (* inet4 server result: *)
      Thread.t * Ipv4.string * port

  val inet6_of_stream_server :
    (* inet6 server parameters: *)
    ?max_pending_requests:int ->
    ?max_input_size:int ->
    ?tutor_behaviour:ThreadExtra.Easy_API.options ->
    ?no_fork:unit ->
    ?range6:string ->
    ?ipv6:Ipv6.string ->
    ?port:int ->
    (* client parameters: *)
    target:server_address -> (* Ex: `unix("/tmp/.X11-unix/X0") or `inet("192.168.1.16", 80) *)
    unit ->
      (* inet6 server result: *)
      Thread.t * Ipv6.string * port

  (* Dual stack server (both IPv4&v6): *)
  val dual_inet_of_stream_server :
    (* inet4 and inet6 server parameters: *)
    ?max_pending_requests:int ->
    ?max_input_size:int ->
    ?tutor_behaviour:ThreadExtra.Easy_API.options ->
    ?no_fork:unit ->
    ?range4:string ->
    ?range6:string ->
    ?ipv4:Ipv4.string ->
    ?ipv6:Ipv6.string ->
    ?port:int ->
    (* client parameters: *)
    target:server_address -> (* Ex: `unix("/tmp/.X11-unix/X0") or `inet("192.168.1.16", 80) *)
    unit ->
      (* inet4 and inet6 dual server result: *)
      (Thread.t * Ipv4.string * port) * (Thread.t * Ipv6.string * port)

 (* -------------------------------- *
        Linux's pseudo-terminals
  * -------------------------------- *)

  val pts_of_stream_server :
    (* launch as fork (default) or as thread: *)
    ?no_fork:unit ->
    (* pts parameters: *)
    ?max_input_size:int ->
    ?file_perm:int ->
    filename:string -> (* Ex: "/dev/pts/10" *)
    (* client parameters: *)
    target:server_address -> (* stream server address (socketfile or (ipv4_or_v6, port)) *)
    (* --- *)
    unit ->
      (* pts result with its controller (if ~no_fork is set, the controller contains the pid of the process itself). *)
      ((exn, unit) Either.t Future.t * Future.Control.t) (* the second is a triple (pid, tid, kill_thunk) *)

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
  val stream_unix_echo_server : ?no_fork:unit -> ?socketfile:string -> unit -> Thread.t * socketfile
  val stream_unix_echo_client : socketfile:string -> unit -> (exn, unit) Either.t

  (* Sending a message bigger than 10 characters, we receive a bad (trunked) echo: *)
  val seqpacket_unix_echo_server : ?no_fork:unit -> ?socketfile:string -> unit -> Thread.t * socketfile
  val seqpacket_unix_echo_client : socketfile:string -> unit -> (exn, unit) Either.t

  val dgram_unix_echo_server : ?no_fork:unit -> ?stream_socketfile:string -> unit -> Thread.t * socketfile
  val dgram_unix_echo_client : stream_socketfile:string -> unit -> (exn, unit) Either.t

  val stream_inet_echo_server : ?no_fork:unit -> ?inet6:unit -> ?port:int -> unit -> Thread.t * string * port
  val stream_inet_echo_client : ipv4_or_v6:string -> port:int -> unit -> (exn, unit) Either.t

  val dgram_inet_echo_server : ?no_fork:unit -> ?inet6:unit -> ?port:int -> unit -> Thread.t * string * port
  val dgram_inet_echo_client : ipv4_or_v6:string -> port:int -> unit -> (exn, unit) Either.t

end
ENDIF
