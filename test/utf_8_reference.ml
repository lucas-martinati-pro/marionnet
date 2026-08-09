(* This file is part of Marionnet

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

(* A UTF-8 validator written HERE ON PURPOSE, rather than the one the JSON codecs use to
   decide whether a string needs the base64 fallback ([Ocamlbricks.Json_bricks]): checking
   the output of a codec with the very predicate that drives it would be circular — a wrong
   predicate would make both the codec and its test wrong, in agreement, without a single
   assertion complaining. That is not a hypothesis: the bench of episode 2 of the
   work-stream `migration-marshal-to-text' did exactly that, and writing the interface of
   the codec is what revealed it (see docs/migration-marshal-to-text.md, section 8.4).

   It is shared by the test programs of the (tests) stanza — the codec of an xforest
   (episode 2) and the codecs of a treeview and of its counters (episode 3) — so that
   there is one reference, and one only, for the invariant which makes them discriminant:
   `the emitted text is valid UTF-8, hence a candidate for being valid JSON'.

   This one decodes by hand, and rejects what a naive check usually accepts: overlong
   encodings, surrogates (U+D800..U+DFFF) and anything beyond U+10FFFF. Its own correctness
   is checked by the test programs, on a list of valid and invalid samples, BEFORE it is
   used to check anything else. *)

let is_valid (s : string) : bool =
  let n = String.length s in
  let byte i = Char.code s.[i] in
  let continuation i = (i < n) && ((byte i) land 0xC0 = 0x80) in
  let rec loop i =
    if i >= n then true else
    let b = byte i in
    if b < 0x80 then loop (i+1)
    else if b land 0xE0 = 0xC0 then
      (continuation (i+1)) &&
      (let cp = ((b land 0x1F) lsl 6) lor ((byte (i+1)) land 0x3F) in
       (cp >= 0x80) && (loop (i+2)))
    else if b land 0xF0 = 0xE0 then
      (continuation (i+1)) && (continuation (i+2)) &&
      (let cp = ((b land 0x0F) lsl 12) lor (((byte (i+1)) land 0x3F) lsl 6)
                lor ((byte (i+2)) land 0x3F) in
       (cp >= 0x800) && (not ((cp >= 0xD800) && (cp <= 0xDFFF))) && (loop (i+3)))
    else if b land 0xF8 = 0xF0 then
      (continuation (i+1)) && (continuation (i+2)) && (continuation (i+3)) &&
      (let cp = ((b land 0x07) lsl 18) lor (((byte (i+1)) land 0x3F) lsl 12)
                lor (((byte (i+2)) land 0x3F) lsl 6) lor ((byte (i+3)) land 0x3F) in
       (cp >= 0x10000) && (cp <= 0x10FFFF) && (loop (i+4)))
    else false
  in
  loop 0

(* The samples the validator itself is checked against, by every test program using it: *)

let valid_samples =
  [""; "abc"; "caf\xc3\xa9"; "\xe2\x82\xac"; "\xf0\x9f\x98\x80"; "\x00\x7f"]

let invalid_samples =
  [ "\x80";                 (* a lone continuation byte              *)
    "\xc3";                 (* truncated two-byte sequence           *)
    "\xe2\x82";             (* truncated three-byte sequence         *)
    "\xc0\x80";             (* overlong encoding of NUL              *)
    "\xe0\x80\x80";         (* overlong encoding again               *)
    "\xed\xa0\x80";         (* U+D800, a surrogate                   *)
    "\xf5\x80\x80\x80";     (* beyond U+10FFFF                       *)
    "\xff"; "\xfe" ]
