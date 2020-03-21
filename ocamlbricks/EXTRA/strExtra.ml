(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007-2011  Jean-Vincent Loddo

   Trivial changes:
   Copyright (C) 2007  Luca Saiu
   Other minor changes in 2008 by Luca Saiu

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

(** {b Meaning:} this type represents the result of a matching between a regular expression and a string {b when it succeeds}.

    A result [(x,(a,b),gl)] means that:

	- there exists a substring [x] of the input string
	  that matches the regular expression;

    	- the integers [a] and [b] (the {e frame}) are the positions (indexes)
	  of the beginning and the end of the substring [x] w.r.t. the input string;

    	- the value [gl] is the list of substrings which have matched the groups defined in
    	  the regular expression; the length of this list will be equal to the number of groups
    	  defined in the regular expression.

{b Examples}:

{[
#  let r = mkregexp ~prefix:["("] ~groups:["[0-9]*"; "[,]?"; "[0-9]*"] ~suffix:[")"] () ;;
val r : Str.regexp = <abstr>

# First.matching r "abcd" ;;
  : StrExtra.result option = None

# First.matching r "(16,7)" ;;
  : StrExtra.result option = Some ("(16,7)", (0, 5), ["16"; ","; "7"])

# let x = object_of_result (Option.extract (First.matching r "(16,7)")) ;;
val x : < frame : int * int; groups : string list; matched : string > = <obj>

# x#frame ;;
  : int * int = (0, 5)

# x#matched ;;
  : string = "(16,7)"

# x#groups ;;
  : string list = ["16"; ","; "7"]
]}*)
type result = string * (int * int) * string list

(** An more explicit structured version of a matching result: *)
let result_as_object (matched,frame,groups) =
  object
    method matched = matched
    method frame = frame
    method groups = groups
  end


(** Facility for building regular expressions.
    The call [mkregexp ~prefix ~groups ~suffix ()] causes the following actions:
    - the strings in [prefix] are simply catenated in a unique string (the {e prefix})
    - the strings in [groups] are catenated enclosing each one into ["\\("] and ["\\)"] in order to define distinct {e groups}
    - the strings in [suffix] are simply catenated in a unique string (the {e suffix})
    - the result is the compiled regexp of the catenation of {e prefix}, {e groups} and {e suffix} {b in this order}.

    The optional parameter [mode] has type [[> `prefix, `suffix, `whole, `inner]] and sets the meaning
    of the regular expression as pattern: a prefix-pattern, a suffix-pattern, a whole-pattern or
    an {b inner-pattern} (which is the default). In other words, the string obtained
    as described above, is modified prepending ["^"] if [mode] is in [[`prefix; `whole]], and is modified
    appending ["$"] if [mode] is in [[`suffix; `whole]]. So, by default nothing is prepended or appended.
*)
let mkregexp ?(mode=`inner) ?case_insensitive ?(prefix=[]) ?(groups=[]) ?(suffix=[]) () =
   let concat = String.concat "" in
   let prefix_pattern = concat prefix in
   let groups_pattern = concat (List.map (fun x-> concat ["\\("; x ;"\\)"]) groups) in
   let suffix_pattern = concat suffix in
   let left_pattern  = match mode with `prefix | `whole -> "^" | _ -> "" in
   let right_pattern = match mode with `suffix | `whole -> "$" | _ -> "" in
   let expr = concat [left_pattern; prefix_pattern; groups_pattern ; suffix_pattern; right_pattern] in
   match case_insensitive with
   | None    -> Str.regexp expr
   | Some () -> Str.regexp_case_fold expr

(** The call [matched_groups i x] returns the list
    of substrings of [x] matching groups starting from the group number [i].
    See the standard [Str.matched_group] for more details. *)
let rec matched_groups i x : (string list) =
  try
    let g=(Str.matched_group i x) in
    g::(matched_groups (i+1) x)
  with _ -> []

(** The heuristic [match_frame r s (a,b)] try to match the substring [(a,b)]
    of the string [s] with the compiled regular expression [r]. *)
let match_frame (r:Str.regexp) (s:string) (a,b) : result option =
  try
    let s  = String.sub s a (b-a+1)   in
    let i  = Str.search_forward r s 0 in
    let y  = Str.matched_string s     in
    let j  = (Str.match_end ())-1     in
    Some (y, (a+i,a+j), (matched_groups 1 s))
  with Not_found -> None


(** The heuristic [match_whole r s (a,b)] try to match the whole string [s]
    with the compiled regular expression [r]. *)
let match_whole (r:Str.regexp) (s:string) : result option =
  try
    let a  = Str.search_forward r s 0 in
    let y  = Str.matched_string s     in
    let b  = (Str.match_end ())-1     in
    Some (y, (a,b), (matched_groups 1 s))
  with Not_found -> None

(** Looking for a first (and single) matching or substitution. *)
module First = struct

(** Try to match the whole string or a frame of it (if specified) with the regular expression.

{b Example}:
{[# First.matching (Str.regexp "[0-9]+") "---12---345---6---7890---" ;;
  : StrExtra.result option = Some ("12", (3, 4), [])
]} *)
let matching ?frame regexp s =
  match frame with
  | None    -> match_whole regexp s
  | Some ab -> match_frame regexp s ab

(** Predicative version of [matching]. The answer is simply a boolean value indicating if they matches.

{b Example}:
{[# First.matchingp (Str.regexp "[0-9]+") "---12---345---6---7890---" ;;
  : bool = true
]} *)
let matchingp ?frame regexp s = ((matching ?frame regexp s) <> None)

(** Similar to the standard [Str.substitute_first] but the value used to substitute is built from
    a function taking the [result] of the matching (not the whole string as for [Str.substitute_first]).

{b Example}:
{[# First.replace (Str.regexp "[0-9]+") (fun (x,(a,b),gs) -> if a<10 then x^x else x^x^x)  "---12---345---6---7890---" ;;
  : string = "---1212---345---6---7890---"
]} *)
let replace ?frame regexp f s =
  let s  = match frame with
  | None       -> s
  | Some (a,b) -> String.sub s a (b-a+1)
  in
  match (match_whole regexp s) with
  | None -> s
  | Some r ->
      let y = f r in
      Str.replace_first regexp y s

(** Similar to the standard [Str.substitute_first] but the value used to substitute is built from
    a function taking the matched substring (not the whole string as for [Str.substitute_first].

{b Example}:
{[# First.substitute (Str.regexp "[0-9]+") (fun x -> x^x)  "---12---345---6---7890---" ;;
  : string = "---1212---345---6---7890---"
]} *)
let substitute ?frame regexp f s =
  let s  = match frame with
  | None       -> s
  | Some (a,b) -> String.sub s a (b-a+1)
  in
  match (match_whole regexp s) with
  | None -> s
  | Some (x,_,_) ->
      let y = f x in
      Str.replace_first regexp y s

end (* module First *)

(** Multiple matchings or substitutions. *)
module Global = struct

(** Get all matches of the regexp with portions of the given string.

{b Example}:
{[# Global.matching (Str.regexp "[0-9]+") "---12---345---6---7890---" ;;
  : result list = [("12", (3, 4), []);  ("345", (8, 10), []);  ("6", (14, 14), []);  ("7890", (18, 21), [])]
]}

The optional parameter [overlap] allows the user to match substrings that overlapped each other. This behaviour concerns only regular expressions {b with groups}: when a matching occurs, the next will be searched immediately after the first matched group, not after the whole matched substring.
{b Example}:
{[# Global.matching (Str.regexp "[0-9]+ [0-9]+") "111 222 333 aaa 444" ;;
  : result list = [("111 222", (0, 6), [])]

# Global.matching ~overlap:() (mkregexp ~groups:["[0-9]+"; " "; "[0-9]+"] ()) "111 222 333 aaa 444" ;;
  : result list = [("111 222", (0, 6), ["111"; " "; "222"]);  ("222 333", (4, 10), ["222"; " "; "333"])]
]}*)
let matching ?frame ?overlap regexp s =
 let s  = match frame with
 | None       -> s
 | Some (a,b) -> String.sub s a (b-a+1)
 in
 let n = String.length s in
 let next = match overlap with
  | None    -> fun (a,b) -> b+1
  | Some () -> fun (a,b) -> try (Str.group_end 1)+1 with _ -> b+1
 in
 let rec loop i =
   if i >=n then [] else
   try
     let a  = Str.search_forward regexp s i in
     let y  = Str.matched_string s      in
     let b  = (Str.match_end ())-1      in
     let answer = (y, (a,b), (matched_groups 1 s)) in
     answer::(loop (next (a,b)))
   with Not_found -> []
 in loop 0


(** Replace all matches of the regexp with a value calculated from the matching result.

{b Example}:
{[# Global.replace (Str.regexp "[0-9]+") (fun (x,(a,b),gs) -> if a<10 then x else x^x)  "---12---345---6---7890---" ;;
  : string = "---12---345---66---78907890---"
]} *)
let replace ?frame ?overlap regexp f s =
  let s  = match frame with
  | None       -> s
  | Some (a,b) -> String.sub s a (b-a+1)
  in
  let results = matching ?overlap regexp s in
  let (i,xs) =
    List.fold_left
      (fun (i,xs) ((_,(a,b),_) as result) ->
         let y = f result in
         let i'= b+1 in
         let xs' = y::(String.sub s i (max 0 (a-i)))::xs in
         (i', xs'))
       (0,[])
       results
  in
  let n = String.length s in
  let xs = (String.sub s i (n-i))::xs in
  (String.concat "" (List.rev xs))

(** Replace all matches of the regexp with a value calculated from the {b matched string} of the
    matching result.

{b Example}:
{[# Global.substitute (Str.regexp "[0-9]+") (fun x -> x^x)  "---12---345---6---7890---" ;;
  : string = "---1212---345345---66---78907890---"
]} *)
let substitute ?frame ?overlap regexp f = replace ?frame ?overlap regexp (fun (x,_,_) -> f x)

end (* module Global *)

(** Posix character classes. By default the meaning of predicates is {b for all} character in the string the character
    belongs to the corresponding Posix class. The dual interpretation {b it exists}
    (a character in the string such that) may be forced with the optional parameter. *)
module Posix = struct

  (** Alphanumeric characters [[a-zA-Z0-9]] *)
  let alnum  ?exists = First.matchingp (Str.regexp (if exists=None then "^[a-zA-Z0-9]*$"     else "[a-zA-Z0-9]"))

  (** Alphabetic characters [[a-zA-Z]] *)
  let alpha  ?exists = First.matchingp (Str.regexp (if exists=None then "^[a-zA-Z]*$"        else "[a-zA-Z]"))

  (** ASCII characters [[\x00-\x7F]] *)
  let ascii  ?exists = First.matchingp (Str.regexp (if exists=None then "^[\x00-\x7F]*$"     else "[\x00-\x7F]"))

  (** Space and tab [[ \t]] *)
  let blank  ?exists = First.matchingp (Str.regexp (if exists=None then "^[ \t]*$"           else "[ \t]"))

  (** Control characters [[\x00-\x1F\x7F]] *)
  let cntrl  ?exists = First.matchingp (Str.regexp (if exists=None then "^[\x00-\x1F\x7F]*$" else "[\x00-\x1F\x7F]"))

  (** Digits [[0-9]] *)
  let digit  ?exists = First.matchingp (Str.regexp (if exists=None then "^[0-9]*$"           else "[0-9]"))

  (** Visible characters (i.e. anything except spaces, control characters, etc.) [[\x21-\x7E]] *)
  let graph  ?exists = First.matchingp (Str.regexp (if exists=None then "^[\x21-\x7E]*$"     else "[\x21-\x7E]"))

  (** Lowercase letters [[a-z]] *)
  let lower  ?exists = First.matchingp (Str.regexp (if exists=None then "^[a-z]*$"           else "[a-z]"))

  (** Visible characters and spaces (i.e. anything except control characters, etc.) [[\x20-\x7E]] *)
  let print  ?exists = First.matchingp (Str.regexp (if exists=None then "^[\x20-\x7E]*$"     else "[\x20-\x7E]"))

  (** Punctuation and symbols *)
  let punct  ?exists = First.matchingp (Str.regexp (if exists=None then "^[!\"#$%&'()*+,\\-./:;<=>?@[\\]^_`{|}~]*$" else "[!\"#$%&'()*+,\\-./:;<=>?@[\\]^_`{|}~]"))

  (** All whitespace characters, including line breaks [[ \t\r\n\\v\\f]] *)
  let space  ?exists = First.matchingp (Str.regexp (if exists=None then "^[ \t\r\n\\v\\f]*$" else "[ \t\r\n\\v\\f]"))

  (** Uppercase letters [[A-Z]] *)
  let upper  ?exists = First.matchingp (Str.regexp (if exists=None then "^[A-Z]*$"           else "[A-Z]"))

  (** Word characters (letters, numbers and underscores) [[A-Za-z0-9_]] *)
  let word   ?exists = First.matchingp (Str.regexp (if exists=None then "^[A-Za-z0-9_]*$"    else "[A-Za-z0-9_]"))

  (** Hexadecimal digits [[A-Fa-f0-9]] *)
  let xdigit ?exists = First.matchingp (Str.regexp (if exists=None then "^[A-Fa-f0-9]*$"     else "[A-Fa-f0-9]"))

  (** Posix character classes as regular expressions *)
  module Regexp = struct

    (** Alphanumeric characters [[a-zA-Z0-9]] *)
    let alnum  = Str.regexp "[a-zA-Z0-9]"

    (** Alphabetic characters [[a-zA-Z]] *)
    let alpha  = Str.regexp "[a-zA-Z]"

    (** ASCII characters [[\x00-\x7F]] *)
    let ascii  = Str.regexp "[\x00-\x7F]"

    (** Space and tab [[ \t]] *)
    let blank  = Str.regexp "[ \t]"

    (** Control characters [[\x00-\x1F\x7F]] *)
    let cntrl  = Str.regexp "[\x00-\x1F\x7F]"

    (** Digits [[0-9]] *)
    let digit  = Str.regexp "[0-9]"

    (** Visible characters (i.e. anything except spaces, control characters, etc.) [[\x21-\x7E]] *)
    let graph  = Str.regexp "[\x21-\x7E]"

    (** Lowercase letters [[a-z]] *)
    let lower  = Str.regexp "[a-z]"

    (** Visible characters and spaces (i.e. anything except control characters, etc.) [[\x20-\x7E]] *)
    let print  = Str.regexp "[\x20-\x7E]"

    (** Punctuation and symbols *)
    let punct  = Str.regexp "[!\"#$%&'()*+,\\-./:;<=>?@[\\]^_`{|}~]"

    (** All whitespace characters, including line breaks [[ \t\r\n\\v\\f]] *)
    let space  = Str.regexp "[ \t\r\n\\v\\f]"

    (** Uppercase letters [[A-Z]] *)
    let upper  = Str.regexp "[A-Z]"

    (** Word characters (letters, numbers and underscores) [[A-Za-z0-9_]] *)
    let word   = Str.regexp "[A-Za-z0-9_]"

    (** Hexadecimal digits [[A-Fa-f0-9]] *)
    let xdigit = Str.regexp "[A-Fa-f0-9]"

  end (* module Posix.Regexp *)

  (** Posix classes as strings. Useful for making regular expressions,
      for instance with [StrExtra.mkregexp]. *)
  module String = struct
    (** Alphanumeric characters [[a-zA-Z0-9]] *)
    let alnum  = "[a-zA-Z0-9]"

    (** Alphabetic characters [[a-zA-Z]] *)
    let alpha  = "[a-zA-Z]"

    (** ASCII characters [[\x00-\x7F]] *)
    let ascii  = "[\x00-\x7F]"

    (** Space and tab [[ \t]] *)
    let blank  = "[ \t]"

    (** Control characters [[\x00-\x1F\x7F]] *)
    let cntrl  = "[\x00-\x1F\x7F]"

    (** Digits [[0-9]] *)
    let digit  = "[0-9]"

    (** Visible characters (i.e. anything except spaces, control characters, etc.) [[\x21-\x7E]] *)
    let graph  = "[\x21-\x7E]"

    (** Lowercase letters [[a-z]] *)
    let lower  = "[a-z]"

    (** Visible characters and spaces (i.e. anything except control characters, etc.) [[\x20-\x7E]] *)
    let print  = "[\x20-\x7E]"

    (** Punctuation and symbols *)
    let punct  = "[!\"#$%&'()*+,\\-./:;<=>?@[\\]^_`{|}~]"

    (** All whitespace characters, including line breaks [[ \t\r\n\\v\\f]] *)
    let space  = "[ \t\r\n\\v\\f]"

    (** Uppercase letters [[A-Z]] *)
    let upper  = "[A-Z]"

    (** Word characters (letters, numbers and underscores) [[A-Za-z0-9_]] *)
    let word   = "[A-Za-z0-9_]"

    (** Hexadecimal digits [[A-Fa-f0-9]] *)
    let xdigit = "[A-Fa-f0-9]"
  end
end

(** Some common classes (identifiers,...) *)
module Class = struct

(** Check if a string can be used as an identifier, i.e. if it matches
    [[^[a-zA-Z][a-zA-Z0-9_]*$]] (without dashes) or [[^[a-zA-Z][a-zA-Z0-9_\\-]*$]] (with dashes). *)
let identifierp =
  let with_dash    = Str.regexp "^[a-zA-Z][a-zA-Z0-9_\\-]*$" in
  let without_dash = Str.regexp "^[a-zA-Z][a-zA-Z0-9_]*$" in
  fun ?allow_dash ->
    match allow_dash with
    | None    -> First.matchingp without_dash
    | Some () -> First.matchingp with_dash

end