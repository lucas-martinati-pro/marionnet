(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007  Jean-Vincent Loddo
   Copyright (C) 2008  Luca Saiu
   Copyright (C) 2007, 2008  Université Paris 13
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

(** A forest concretization very close to XML: a node is a [tag] together with its
    attributes, i.e. (key, value) bindings where both key and value are strings. *)

(** {2 Types}

    All of them are transparent on purpose: callers build nodes as plain tuples and
    attribute lists, and pattern-match on them. *)

type tag        = string
type attribute  = string * string
type attributes = attribute list

type node   = tag * attributes
type forest = node Forest.t
type t      = forest
type tree   = node * forest  (** the root and the forest of its children *)

(** {2 Interpreters} *)

(** An Xforest interpreter is an object able to update itself reading an Xforest and,
    conversely, able to encode itself into an Xforest. Both [eval_] methods default to
    ignoring their argument, so a subclass overrides only what it understands.

    {b Beware}: that default is also a silent one — an attribute a subclass does not know
    is dropped without a word. *)
class virtual interpreter : unit ->
  object
    (** Interpret a tree: the attributes first, in order, then the children. The tag
        itself is ignored here. *)
    method from_tree : node -> forest -> unit

    method eval_forest_attribute : attribute -> unit
    method eval_forest_child     : tree -> unit

    (** Encode [self] as a tree. Typically calls the same method on the children. *)
    method virtual to_tree : tree

    (** By default, the singleton forest of [self#to_tree]. May be redefined. *)
    method to_forest : forest
  end

(** {2 Printing} *)

(** [print_forest] specialized for xforest: nodes are rendered as [<tag[k="v" ...]>]. *)
val print_xforest : ?level:int -> channel:out_channel -> forest -> unit

(** {2 Non-string fields}

    Facilities for encoding, inside an attribute — which is a [string] —, an object field
    which is not one. Note that this is exactly what makes a forest opaque where it
    matters most (the Quagga configurations of a router, [rc_config]): the work-stream
    `migration-marshal-to-text' is about undoing it, see docs/migration-marshal-to-text.md. *)

val encode : 'a -> string
val decode : string -> 'a

(** {2 JSON codec (project version v3)}

    A textual, self-describing serialization, replacing the [Marshal] dumps of
    [netmodel/network.xml] and [netmodel/dotoptions.marshal]. The shape is:

{v
{ "format": "marionnet/xforest", "version": 3,
  "roots": [ { "tag": "network",
               "attrs": [ [ "name", "projet1" ] ],
               "children": [] } ] }
v}

    Attributes are an ordered {b list of pairs}, never a JSON object: the OCaml type is
    an association list, where the order is meaningful (attributes are interpreted
    sequentially by [#eval_forest_attribute]) and duplicate keys are possible — both
    properties a JSON object would silently destroy.

    Any string which is not valid UTF-8 — an attribute value, but a tag or an attribute
    name just as well — is written as [{"b64": "..."}] instead of a JSON string. That
    fallback is not a precaution against losing data, since the underlying library writes
    raw bytes verbatim and rereads them faithfully; it is the only way to emit a text
    which is valid JSON {e at all}, which is the whole point of the migration. A
    [\uXXXX] escape would {b not} do: it denotes a code point, not a byte.

    Note that the JSON library used does not appear in the signatures below: it is an
    implementation detail, and callers never manipulate a JSON value. *)

(** Encode a forest as an indented, newline-terminated JSON text. *)
val to_JSON_string : t -> string

(** Decode a forest from a JSON text. Every failure — ill-formed JSON, unexpected format
    or version, missing member, undecodable base64 — is reported as [Error message], and
    nothing is ever guessed: the three members of a tree ([tag], [attrs], [children]) are
    all required, and a version this binary does not know is refused by name. *)
val of_JSON_string : string -> (t, string) result

(** Write a forest into a file. As with the [Marshal] path it replaces, an I/O failure is
    raised, not returned: a project which cannot be saved must say so loudly. *)
val to_JSON_file : t -> string -> unit

(** Read a forest from a file. Unlike its writing counterpart, I/O failures are returned
    as [Error message]: an unreadable project file is an ordinary case here, dealt with
    by the caller together with the decoding failures. *)
val of_JSON_file : string -> (t, string) result
