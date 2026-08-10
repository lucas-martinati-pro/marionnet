(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2026  Jean-Vincent Loddo

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

(** The JSON codec of the counters of the treeview `ifconfig' — the eighth and smallest of
    the files a project keeps in [Marshal] form ([states/ifconfig-counters]); work-stream
    `migration-marshal-to-text', see docs/migration-marshal-to-text.md, section 4.3.

    The triple is the one [Treeview_ifconfig] marshals and demarshals, in that very order:

{v
{ "format": "marionnet/ifconfig-counters", "version": 3,
  "obsolete_mac_address_as_int": 12345678,
  "next_ipv4_address_as_int": 1,
  "next_ipv6_address_as_int": "1" }
v}

    Two remarks the schema alone does not carry:

    - [next_ipv6_address_as_int] is an [Int64.t], and it travels {b as a string}: JSON has
      no portable 64 bit integer (its numbers are IEEE 754 doubles as far as any other
      reader is concerned, hence exact only up to 2^53). It is written in one form and
      read in one form only, a string: accepting a JSON number as well would make a
      reread depend on which of the two a writer happened to choose;

    - the first field is [_OBSOLETE_mac_address_as_int] on the OCaml side, kept because it
      is already written "for forward compatibility" and this work-stream is not the place
      to remove a field from a file older binaries may read. Note that it is drawn {e at
      random} at every save ([Treeview_ifconfig#save]), which is why the bench of episode 1
      expects those four bytes, and only those, to change from one save to the next.

    ⚠️ The loading path this codec is meant for is wrapped in a [try ... with _ -> ()]
    ([Treeview_ifconfig#load_counters]): a conversion failing there would be {b silent},
    and a project would go on with fresh-address counters reset to 1 - handing out
    addresses already in use. Hence the unit tests, and hence a bench which checks the
    counters {e explicitly} rather than trusting a load which raises nothing. *)

(** The counters, in the order in which they are marshalled:
    obsolete MAC address, next IPv4 address, next IPv6 address. *)
type t = int * int * Int64.t

(** Encode the counters as a JSON text, newline-terminated. *)
val to_JSON_string : t -> string

(** Decode the counters from a JSON text. Every failure - ill-formed JSON, unexpected
    format or version, missing member, unparsable 64 bit integer - is reported as
    [Error message]. *)
val of_JSON_string : string -> (t, string) result

(** Write the counters into a file. As with the [Marshal] path it replaces, an I/O failure
    is raised, not returned. *)
val to_JSON_file : t -> string -> unit

(** Read the counters from a file. I/O failures are returned as [Error message], together
    with the decoding failures, prefixed by the file name. *)
val of_JSON_file : string -> (t, string) result
