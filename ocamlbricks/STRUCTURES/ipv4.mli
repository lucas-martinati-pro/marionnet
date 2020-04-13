(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2009 Jean-Vincent Loddo

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

(** IPv4 parsing and printing. *)

(** The internal representation of an ipv4 address. *)
type t = int * int * int * int

(* Alias indicating the purpose of the string: *)
type string = String.t

(** The integer implicitely representing the netmask.
    Admissible values are in the range [0..32]. *)
type cidr = int
type netmask = t
type port = int

(** The internal representation of an ipv4 configuration,
    i.e. a pair [<address>/<cidr>]. *)
type config          = t * cidr
type verbose_config  = t * netmask
type socket          = t * port

(** Completion: *)
val to_config : t -> config option

(** {2 Netmask <-> CIDR} *)

val netmask_of_cidr   : cidr -> netmask
val cidr_of_netmask   : netmask -> cidr
val netmask_of_string : string -> netmask

(** {2 Parsing} *)

val of_string : string -> t
val to_string : t -> string

val config_of_string  : string -> config
val string_of_config  : config -> string

val socket_of_string : string -> socket
val string_of_socket : socket -> string

val import : string -> (t, config) Either.t option

type ipcalc_result =
< ip        : t;
  cidr      : int;
  config    : t * int;
  netmask   : t;
  network   : t;
  broadcast : t;
  hostmin   : t;
  hostmax   : t;
  hosts     : int;
  print     : unit;

  to_string : <
      ip        : string;
      cidr      : string;
      config    : string;
      netmask   : string;
      network   : string;
      broadcast : string;
      hostmax   : string;
      hostmin   : string;
      >;

  contains : t -> bool;
  contains_socket : socket -> bool;
  >

val ipcalc : t -> cidr -> ipcalc_result

(** {2 String checking} *)

module String : sig

 type t = string (* alias *)

 val is_valid_ipv4    : string -> bool
 val is_valid_netmask : string -> bool
 val is_valid_config  : string -> bool

 val ipcalc : config:string ->
  < ip        : string;
    cidr      : string;
    netmask   : string;
    network   : string;
    broadcast : string;
    hostmax   : string;
    hostmin   : string;
    contains  : ip:string -> bool;
    contains_socket : socket:string -> bool;
    print     : unit;
    >

end


