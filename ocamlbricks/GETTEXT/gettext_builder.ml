(*This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009, 2010  Luca Saiu

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

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

(* Make the primitives implemented in C visible to the OCaml world: *)
external non_thread_safe_dgettext_primitive : string -> string -> string = "dgettext_primitive";;
external non_thread_safe_initialize_gettext : string -> string -> unit = "initialize_gettext_primitive";;

(* Some precedures aren't thread-safe, so we should sequentialize concurrent calls
   with a mutex.  This code is not very performance-critical anyway... *)
let the_mutex = Mutex.create ();;

let initialize_gettext text_domain locales_directory =
  Mutex.lock the_mutex;
  non_thread_safe_initialize_gettext text_domain locales_directory;
  Mutex.unlock the_mutex;;

(* Wrap the main primitive within a thread-safe function: *)
let dgettext text_domain string_in_english =
  Mutex.lock the_mutex;
  let result = non_thread_safe_dgettext_primitive text_domain string_in_english in
  Mutex.unlock the_mutex;
  result;;

(* Because of some annoying limitation of OCaml I can't really understand, these
   definitions must be repeated here: *)
module type TextDomainAndDirectory = sig
  val text_domain : string;;
  val directory : string;;
end;;
module type Gettext = sig
  val s_ : string -> string;;
  val f_ : (('a, 'b, 'c) format) -> (('a, 'b, 'c) format);;
end;;

module Make (TheTextDomainAndDirectory : TextDomainAndDirectory) : Gettext = struct
  (* Let's bind this text domain to the directory at functor application time: *)
  initialize_gettext TheTextDomainAndDirectory.text_domain TheTextDomainAndDirectory.directory;;

  (* Public versions for strings, with the type we like: *)
  let s_ english_string =
    dgettext TheTextDomainAndDirectory.text_domain english_string;;

  (* Public versions for format strings, with the type we like: *)
  let f_ english_format_string =
    let english_string = string_of_format english_format_string in
    let foreign_string = dgettext TheTextDomainAndDirectory.text_domain english_string in
    Scanf.format_from_string foreign_string english_format_string;;

end;;
