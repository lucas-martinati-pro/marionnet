(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Luca Saiu

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

(** Object-oriented marshalling support.
    This module contains two distinct marshalling facilities. *)


(** Marshalling flags: we want to support sharing but no closures. *)
let flags = [ (* sharing is on by default *) ];;

(** {2 An intuitive but unsafe marshalling facility} *)

(** The abstract superclass of any marshallable object. Objects can be safely
    marshalled via methods, but unmarshalling produces results of unconstrained
    polymorphic types, which must be manually cast by the user. *)

(** The virtual marshallable class, which should be the base class of all
    classes intended for marshalling with this technique. *)
(* ---
class virtual marshallable = object(self)
  (** Marshal [self] into a string, and return the string *)
  method to_string = Marshal.to_string self flags

  (** Marshal [self] into the given channel, and return unit. *)
  method to_channel c = Marshal.to_channel c self flags

  (** Marshal [self] into the given file, and return unit. *)
  method to_file file_name =
    let channel = open_out file_name in
    Marshal.to_channel channel self flags;
    close_out channel
end;;
--- *)

(** Unmarshal (what we hope to be) a [marshallable] object from the given
    string, and return the object with an {e unconstrained polymorphic
    type}. *)
let from_string s = Marshal.from_string s 0;;

(** Unmarshal (what we hope to be) a [marshallable] object from the given
    channel, and return the object with an {e unconstrained polymorphic
    type}. *)
let from_channel c = Marshal.from_channel c;;

(** Unmarshal (what we hope to be) a [marshallable] object from the given
    file, and return the object with an {e unconstrained polymorphic
    type}. *)
let from_file file_name =
    let channel = open_in file_name in
    let result = Marshal.from_channel channel in
    close_in channel;
    result


(** {2 An uglier but safe marshalling facility}
    This implementation uses casts only internally, but requires the creation
    of a marshaller object which serves the single purpose of marshalling and
    unmarshalling the objects it's given, without keeping any internal state;
    all of this is, put honestly, quite ugly.
    Marshallers for non-object types are also supported.
    The marshaller type is correctly inferred. *)

(** The marshaller class, instances of which can marshal and unmarshal objects
    of a given type when requested. *)
class ['a] marshaller = object(self)
  (** Make a new 'a object from the given string, and return it. *)
  method from_string s = ((Marshal.from_string s 0) :> 'a)

  (** Make a new 'a object from the given channel, and return it. *)
  method from_channel c = ((Marshal.from_channel c) :> 'a)

  (** Make a new 'a object from the given file, and return it. *)
  method from_file file_name =
    let channel = open_in file_name in
    let result = ((Marshal.from_channel channel) :> 'a) in
    close_in channel;
    result

  (** Marshal the given object into the given channel, and return unit. *)
  method to_channel (x : 'a) c = Marshal.to_channel c x flags

  (** Marshal the given object into the given file, and return unit. *)
  method to_file (x : 'a) file_name =
    let channel = open_out file_name in
    Marshal.to_channel channel x flags;
    close_out channel

  (** Marshal the given object into a new string, and return the string. *)
  method to_string (x : 'a) = Marshal.to_string x flags
end;;


(** {3 A small example}
{[let m = new marshaller;;
print_float (m#from_string (m#to_string 3.2));;
]}
*)
