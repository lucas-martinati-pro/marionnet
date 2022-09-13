(* This file is part of ocamlbricks
   Copyright (C) 2012 Jean-Vincent Loddo

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

(** IPv6 parsing and printing. *)

(** The internal representation of an ipv6 address. *)
type t = int array

(* Alias indicating the purpose of the string: *)
type string = String.t

(** The integer implicitely representing the netmask. Admissible values are in the range [0..128]. *)
type cidr = int

(** The internal representation of an ipv6 configuration, i.e. a pair [<address>/<cidr>]. *)
type config = t * cidr

val of_string : string -> t
val to_string : ?uncompress:unit -> t -> string

val config_of_string : string -> config
val string_of_config : ?uncompress:unit -> config -> string

type ipcalc_result =
  < ip       : t;           (** The given address *)
    cidr     : int;         (** The given cidr *)
    config   : t * int;     (** The given address,cidr *)
    netmask  : t;           (** The derived netmask *)
    network  : t;           (** The derived network address *)
    hostmin  : t;           (** Host minimal address in this network *)
    hostmax  : t;           (** Host maximal address in this network *)
    contains : t -> bool;   (** Does the network contain this address? *)
    print    : unit;        (** Print all given and derived informations *)

    (** String conversions: *)
    to_string : <
	ip      : string;
	cidr    : string;
	config  : string;
	netmask : string;
	network : string;
	hostmax : string;
	hostmin : string;
	>
    >


val ipcalc : t -> cidr -> ipcalc_result

module String : sig

 type t = string (* alias *)

 val is_valid_ipv6   : string -> bool
 val is_valid_config : string -> bool

 val ipcalc : config:string ->
  < ip       : string;
    cidr     : string;
    netmask  : string;
    network  : string;
    hostmin  : string;
    hostmax  : string;
    contains : ip:string -> bool;
    print    : unit;
    >
end
