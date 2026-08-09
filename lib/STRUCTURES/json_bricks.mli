(* This file is part of ocamlbricks
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

(** The plumbing shared by the JSON codecs of a Marionnet project file (work-stream
    `migration-marshal-to-text', see docs/migration-marshal-to-text.md): a byte-safe
    representation of an OCaml [string], a uniform way of reporting a malformed text,
    and the [{"format", "version", ...}] envelope every one of those files carries.

    Three codecs are built on top of it — the xforest of nodes ({!Xforest}), the forest of
    treeview rows and the counters of the treeview `ifconfig' (both in Marionnet's [bin/])
    — hence this module rather than a copy of the same forty lines three times over: the
    hard part below (there is no way to escape a raw byte in JSON, see {!json_of_string})
    is worth stating, documenting and testing exactly once.

    Unlike the interfaces of the codecs themselves, this one does mention [Yojson]: it
    {e is} the JSON layer of the project, and a caller of these functions is by definition
    building a JSON value. *)

(** {2 Reporting a malformed text} *)

(** Raised while decoding. A codec catches it at its border — see {!of_text} — and turns
    it into an [Error message]: a project file which cannot be read is an ordinary case,
    not an exceptional one. *)
exception Malformed of string

(** [fail "..." x y] raises {!Malformed} with a [Printf]-formatted message. *)
val fail : ('a, unit, string, 'b) format4 -> 'a

(** A human-readable name for the kind of a JSON value ("a string", "an object", ...),
    meant for the message of a decoding failure: what was expected, and what was found. *)
val kind_of : Yojson.Safe.t -> string

(** {2 Byte-safe strings}

    An OCaml [string] is a sequence of bytes; a JSON string is a sequence of Unicode
    characters. The two are not the same thing, and a Marionnet project legitimately holds
    the difference: a marshalled attribute, a comment typed in a guest, a filename in a
    locale nobody remembers. *)

(** Whether a string is valid UTF-8, according to the standard library decoder — taken as
    the reference on purpose, since it also rejects the overlong encodings and the
    surrogates a hand-written check usually lets through. *)
val is_valid_utf_8 : string -> bool

(** Encode a string as a JSON string when it is valid UTF-8, and as [{"b64": "..."}]
    otherwise.

    {b The fallback is not a precaution against losing data}: the underlying library
    writes raw bytes verbatim and rereads them faithfully. It is the only way to emit a
    text which is valid JSON {e at all} — which is the whole point of the migration, a
    project file any other tool can read. And it must be an explicit encoding, never an
    escape: [\uXXXX] denotes a {e code point}, not a byte, so writing 0x8F that way and
    rereading it yields U+008F, that is two bytes once in UTF-8. Silent corruption. *)
val json_of_string : string -> Yojson.Safe.t

(** The inverse of {!json_of_string}. [what] names the thing being decoded, for the
    failure message. Raises {!Malformed} on anything else than a string or a well-formed
    [{"b64": ...}] object. *)
val string_of_json : what:string -> Yojson.Safe.t -> string

(** {2 The envelope} *)

(** [member_of ~where fields key] is the value bound to [key], and raises {!Malformed}
    when there is none — [where] naming the object, for the message. Every member of
    every one of these schemas is {b required}: rebuilding a missing one (an absent
    "children" read as an empty forest, say) would reintroduce exactly the kind of silent
    approximation the migration is about removing. *)
val member_of :
  where:string -> (string * Yojson.Safe.t) list -> string -> Yojson.Safe.t

(** [to_text ~format ~version members] is the indented, newline-terminated JSON text of
    the object made of ["format"], ["version"] and [members], in that order. Indented on
    purpose: a project file which can be diff'ed is one of the reasons this format
    exists. *)
val to_text :
  format:string -> version:int -> (string * Yojson.Safe.t) list -> string

(** [of_text ~format ~version ~decode text] checks that [text] is a JSON object carrying
    the expected [format] and [version], then hands [decode] the accessor of its members
    ([member_of] specialized to the toplevel object). Every failure — ill-formed JSON,
    unexpected format or version, missing member, and whatever {!Malformed} [decode]
    itself raises — is reported as [Error message]. A version this binary does not know is
    refused {e by name}, never guessed at. *)
val of_text :
  format:string -> version:int ->
  decode:((string -> Yojson.Safe.t) -> 'a) -> string -> ('a, string) result

(** {2 Files} *)

(** Write a text into a file. An I/O failure is {b raised}, not returned: a project which
    cannot be saved must say so loudly. *)
val write_file : filename:string -> string -> unit

(** Read a whole file. Unlike its writing counterpart, an I/O failure is returned as
    [Error message]: an unreadable project file is an ordinary case, dealt with by the
    caller together with the decoding failures. *)
val read_file : string -> (string, string) result
