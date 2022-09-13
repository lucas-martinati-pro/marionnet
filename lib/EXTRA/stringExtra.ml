(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007-2009  Jean-Vincent Loddo

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

IFNDEF OCAML4_02_OR_LATER THEN
module Bytes = struct  include String  let to_string x = x  let of_string x = x  end
type bytes = string
ENDIF

(** The type of the standard [Bytes.blit]. *)
type blit_function = bytes -> int -> bytes -> int -> int -> unit

(** Make a blit function that uses the argument [~(perform:char->int->unit)]
    to perform an action for any scanned character. The first
    argument of [perform] is the character that will be copied,
    the second argument is the index in the target string. {b Example}:
{[# let perform c i = Printf.eprintf "Copying character %c at position %d\n" c i in
    let s = from_file ~blit:(blitting ~perform) "/etc/fstab" in
    ... ]} *)
let blitting ~(perform:char->int->unit) : blit_function =
 fun s1 ofs1 s2 ofs2 len ->
  if len < 0 || ofs1 < 0 || ofs1 > Bytes.length s1 - len
             || ofs2 < 0 || ofs2 > Bytes.length s2 - len
  then invalid_arg "Bytes.blitting" else
  let ofs1=ref ofs1 in
  let ofs2=ref ofs2 in
  for _j=1 to len do
    let c = Bytes.get s1 (!ofs1) in
    let i = !ofs2 in
    (perform c i);
    (Bytes.set s2 i c);
    incr ofs1;
    incr ofs2;
  done

(** Import the content of the [Unix] file descriptor. The optional [?(blit=Bytes.blit)] allows
    to perform some operations during the copy of characters (see the function {!StringExtra.blitting}). *)
let from_descr ?(blit:blit_function=Bytes.blit) (fd:Unix.file_descr) : string =
 let q = Queue.create () in
 let buffer_size = 8192 in
 let buff = Bytes.create buffer_size in
 let rec loop1 acc_n =
  begin
   let n = (Unix.read fd buff 0 buffer_size)    in
   if (n=0) then acc_n else ((Queue.push ((Bytes.sub buff 0 n),n) q); loop1 (acc_n + n))
   end in
 let dst_size = loop1 0 in
 let dst = Bytes.create dst_size in
 let rec loop2 dstoff = if dstoff>=dst_size then () else
  begin
  let (src,src_size) = Queue.take q in
  (blit src 0 dst dstoff src_size);
  loop2 (dstoff+src_size)
  end in
 (loop2 0);
 Bytes.to_string dst

(** Similar to {!StringExtra.from_descr} but the user provides the file name instead of the file descriptor. *)
let from_file ?(blit:blit_function=Bytes.blit) (filename:string) : string =
 let fd = (Unix.openfile filename [Unix.O_RDONLY;Unix.O_RSYNC] 0o640) in
 let result = from_descr ~blit fd in
 (Unix.close fd);
 result

(** Similar to {!StringExtra.from_descr} but the user provides the [Pervasives.in_channel] instead of the file descriptor. *)
let from_channel ?(blit:blit_function=Bytes.blit) in_channel : string =
 from_descr ~blit (Unix.descr_of_in_channel in_channel)

(** Make a copy of a string performing an action for any scanned character. *)
let from_string ~(perform:char->int->unit) (src:string) : string =
 let len = String.length src in
 let dst = Bytes.create len in
 let blit = blitting ~perform in
 (blit (Bytes.of_string src) 0 dst 0 len);
 Bytes.to_string dst

(** [nth_index_from s n c nth] return the index of the [nth]
    occurrence of the character [c] searching in [s] from the offset [n].
    Raise [Not_found] if there isn't a sufficient number of occurrences. {b Example}:
{[# nth_index_from "@123@567@" 0 '@' 2;;
  : int = 4 ]}*)
let rec nth_index_from =
 let rec lloop s offset c k =
   if k=0 then offset else (* degenere *)
   if k=1 then String.index_from s offset c else
   let offset' = String.index_from s offset c in
   lloop s (offset'+1) c (k-1) in
 fun s n c k -> if k<0 then nth_rindex_from s n c (-k)
                       else lloop s n c k

(** As [nth_index_from] but searching from the {e right} to the {e left} side. *)
and nth_rindex_from =
 let rec rloop s offset c k =
   if k=0 then offset else (* degenere *)
   if k=1 then String.rindex_from s offset c else
   let offset' = String.rindex_from s offset c in
   rloop s (offset'-1) c (k-1) in
 fun s n c k -> if k<0 then nth_index_from s n c (-k)
                       else rloop s n c k

(** As [nth_index_from] but searching from the beginning of the string (offset [0]). *)
let nth_index s  = nth_index_from  s 0

(** As [nth_rindex_from] but searching from the end of the string. *)
let nth_rindex s = nth_rindex_from s ((String.length s)-1)

(** Similar to the standard [List.for_all], considering a string as a list of characters. *)
let for_all p s =
 let l = String.length s in
 let rec loop i =
  if i>=l then true else
  p s.[i] && loop (i+1)
 in loop 0

(** Similar to {!StringExtra.for_all} but the predicate needs also the index. *)
let for_all_i p s =
 let l = String.length s in
 let rec loop i =
  if i>=l then true else
  p i s.[i] && loop (i+1)
 in loop 0

(** Similar to the standard [List.exists], considering a string as a list of characters. *)
let exists p s =
 let l = String.length s in
 let rec loop i =
  if i>=l then false else
  p s.[i] || loop (i+1)
 in loop 0

(** Similar to {!StringExtra.exists} but the predicate needs also the index. *)
let exists_i p s =
 let l = String.length s in
 let rec loop i =
  if i>=l then false else
  p i s.[i] || loop (i+1)
 in loop 0

(** As the function {!StringExtra.exists}, but provides the index that verifies the predicate. *)
let lexists p s =
 let l = String.length s in
 let rec loop i =
  if i>=l then None else
  if p s.[i] then (Some i) else loop (i+1)
 in loop 0

(** As the function [lexists], but searching from the right side. *)
let rexists p s =
 let l = String.length s in
 let rec loop i =
  if i<0 then None else
  if p s.[i] then (Some i) else loop (i-1)
 in loop (l-1)
;;

let is_prefix x y =
 try
  for_all_i (fun i c -> c = y.[i]) x
 with (Invalid_argument _) -> false
;;

(** [tail s i] return the substring from the index [i] (included) to the end of [s].
    Raise [Invalid_argument "tail"] if the index is out of the string bounds. {b Example}:
{[# tail "azerty" 2;;
 : string = "erty" ]} *)
let tail s i =
 try String.sub s i ((String.length s)-i)
 with Invalid_argument _ -> raise (Invalid_argument "tail")

(** [head s i] return the substring from the beginning of [s] to the index [i] included.
    Raise [Invalid_argument "head"] if the index is out of the string bounds. {b Example}:
{[# head "azerty" 2;;
 : string = "aze"
# head "azerty" 0 ;;
 : string = "a" ]} *)
let head s i =
 try String.sub s 0 (i+1)
 with Invalid_argument _ -> raise (Invalid_argument "head")

(** [frame s c nth1 nth2] return the substring of [s] delimited by
    the [nth1] and the [nth2] occurrence of the character [c].
    Raise [Not_found] if the number of occurrences is lesser than [nth1].
    Raise [Invalid_argument "frame"] if [nth1] is greater than [nth2]. {b Example}:
{[# frame "\@xxx\@yyy\@zzz\@" '@' 1 3 ;;
  : string = "\@xxx\@yyy\@" ]}*)
let frame s c nth1 nth2 =
 if nth2<nth1 then (raise (Invalid_argument "frame")) else
 if nth2=nth1 then String.sub s (nth_index s c nth1) 1 else
 let offset1 = nth_index s c nth1 in
 let offset2 =  try
   nth_index_from s (offset1+1) c (nth2-nth1)
 with Not_found -> (String.length s)-1 in
 String.sub s offset1 (offset2-offset1+1)

(** As [frame] but raise [Not_found] also if the number of occurrences is lesser than [nth2]. *)
let frame_strict s c nth1 nth2 =
 if nth2<nth1 then (raise (Invalid_argument "frame")) else
 if nth2=nth1 then String.sub s (nth_index s c nth1) 1 else
 let offset1 = nth_index s c nth1 in
 let offset2 = nth_index_from s (offset1+1) c (nth2-nth1) in
 String.sub s offset1 (offset2-offset1+1)

(** As [frame] by searching and counting the number of occurrences
    from the {e right} to the {e left} side of string. {b Example}:
{[# rframe "\@xxx\@yyy\@zzz\@" '@' 1 3 ;;
  : string = "\@yyy\@zzz\@" ]} *)
let rframe s c nth1 nth2 =
 if nth2<nth1 then (raise (Invalid_argument "frame")) else
 if nth2=nth1 then String.sub s (nth_rindex s c nth1) 1 else
 let offset1 = nth_rindex s c nth1 in
 let offset2 = try
   nth_rindex_from s (offset1-1) c (nth2-nth1)
 with Not_found -> 0 in
 String.sub s offset2 (offset1-offset2+1)

(** As [rframe] but raise [Not_found] also if the number of occurrences is lesser than [nth2]. *)
let rframe_strict s c nth1 nth2 =
 if nth2<nth1 then (raise (Invalid_argument "frame")) else
 if nth2=nth1 then String.sub s (nth_rindex s c nth1) 1 else
 let offset1 = nth_rindex s c nth1 in
 let offset2 = nth_rindex_from s (offset1-1) c (nth2-nth1) in
 String.sub s offset2 (offset1-offset2+1)

(** Count the number of occurrences of the character in the string. *)
let count =
 let rec loop s c i acc =
  try let i = (String.index_from s i c) in loop s c (i+1) (acc+1)
  with Not_found -> acc
 in fun s c -> loop s c 0 0

(** Note that the last index is (-1) when the character is not found. *)
let count_and_last_index =
 let rec loop s c i acc last_index =
  try let i = (String.index_from s i c) in loop s c (i+1) (acc+1) i
  with Not_found -> (acc,last_index)
 in fun s c -> loop s c 0 0 (-1)

(** Note that the last two indexes may be (-1) if there isn't a sufficient number of occurrences. *)
let count_and_last_two_indexes =
 let rec loop s c i acc last_index penultimate =
  try let i = (String.index_from s i c) in loop s c (i+1) (acc+1) i last_index
  with Not_found -> (acc,last_index,penultimate)
 in fun s c -> loop s c 0 0 (-1) (-1)

(** [not_blank] stands for not [' '], not ['\t'] and not ['\n'] *)
let not_blank = (fun c -> (c<>' ') && (c<>'\t') && (c<>'\n'))

(** Strip the left side of the string with the predicate {!StringExtra.not_blank} *)
let lstrip s =
 match lexists not_blank s with
 | None   -> ""
 | Some i -> String.sub s i (((String.length s))-i)

(** Strip the right side of the string with the predicate {!StringExtra.not_blank} *)
let rstrip s =
 match rexists not_blank s with
 | None   -> ""
 | Some i -> String.sub s 0 (i+1)

(** Strip the both sides of the string with the predicate {!StringExtra.not_blank} *)
let strip s =
 match (lexists not_blank s) with
 |  None   -> ""
 |  Some i -> (match (rexists not_blank s) with
	       | Some j -> String.sub s i (j-i+1)
               | None   -> assert false
               )

(** Remove from the input string the last chars in the set [['\n','\t',' ']].
     Similar to the [rstrip] {e Python} function. Example:
{[# chop "hell o \t\n";;
  : string = "hell o"]} *)
let rec chop x =
  let l = (String.length x) in if (l=0) then x else
   begin
   let last = (String.sub x (l-1) 1) in match last with
   | "\n" | " " | "\t" -> chop (String.sub x 0 (l-1))
   | _ -> x
   end

(** Similar to [cut ~n:1] but returns the list of {e characters} (instead of strings)
    of the input string. {b Example}:
{[# to_charlist "aaabbc";;
  : char list = ['a'; 'a'; 'a'; 'b'; 'b'; 'c']]}*)
let to_charlist (s:string) =
 let l = String.length s in
 let rec loop s l =
  if l=0 then []  else
   let l' = (l-1) in
   (s.[0])::(loop (String.sub s 1 l') l')
 in loop s l


(** Some efficient char list operations (assemble/disassemble). *)
module Charlist = struct

(** Fold a char list into a string. *)
let assemble (xs:char list) : string =
 let n = List.length xs in
 let s = Bytes.create n in
 let rec loop i = function
  | []    -> ()
  | x::xs -> (Bytes.set s i x); loop (i+1) xs
 in (loop 0 xs);
 (Bytes.to_string s)

(** Disassemble (split) the string and return the reversed list of its characters. {b Example}:
{[# disassemble_reversing "abcd" ;;
 : char list = ['d'; 'c'; 'b'; 'a'] ]} *)
let disassemble_reversing ?(acc=[]) (s:string) : char list =
 let n = String.length s in
 let rec loop acc i =
  if i>=n then acc else
  loop ((s.[i])::acc) (i+1)
 in loop acc 0

(** Assemble a list of char into a string reversing the order. {b Example}:
{[# assemble_reversing ['a';'b';'c';'d'] ;;
 : string = "dcba" ]} *)
let assemble_reversing ?length (xs:char list) : string =
 let n = match length with None -> List.length xs | Some x->x in
 let s = Bytes.make n ' ' in
 let rec loop i = function
  | []    -> ()
  | x::xs -> (Bytes.set s i x); loop (i-1) xs
 in (loop (n-1) xs);
 (Bytes.to_string s)

end

(** Convert a list of chars in a string.
{[# of_charlist ['h';'e';'l';'l';'o'];;
  : string = "hello"
]}*)
let of_charlist = Charlist.assemble

(** [expand f s] expand characters of [s] with the string provided by [f], if any,
    or leave the character unchanged if [f] returns [None]. {b Example}:
{[
# expand (function '>' -> Some "&gt;" | _ -> None ) "int -> bool" ;;
  : string = "int -&gt; bool"
]}*)
let expand (f:char -> string option) s =
 let n = String.length s in
 let xs = to_charlist s in
 let (ys,n) =
   List.fold_left
     (fun (ys,n) c -> match f c with
     | None   -> ((c::ys),n)
     | Some x -> ((Charlist.disassemble_reversing ~acc:ys x),(n + (String.length x) - 1))
     )
     ([],n)
     xs
 in
 Charlist.assemble_reversing ~length:n ys

(** Similar to [Array.iteri]. *)
let iteri f s =
  let n = String.length s in
  for i = 0 to n-1 do
    f i (String.unsafe_get s i)
  done

(** Similar to [Array.init]. {b Example}:
{[# init 10 (fun i->if i<3 then 'a' else 'b') ;;
  : string = "aaabbbbbbb"
]} *)
let init n f  =
 let s = Bytes.create n in
 for i = 0 to n-1 do
   (Bytes.set s i (f i))
 done;
 Bytes.to_string s

(** Similar to [Array.map]. {b Example}:
{[# map (fun x -> if x='a' then 'A' else x) "aaabbbac" ;;
  : string = "AAAbbbAc"
]} *)
let map (f:char -> char) s =
 let n = String.length s in
 init n (fun i -> f (String.unsafe_get s i))

(** Similar to [Array.mapi]. {b Example}:
{[# mapi (fun i x -> if x='a' && i<3 then 'A' else x) "aaabbbac" ;;
  : string = "AAAbbbac"
]} *)
let mapi f s =
 let n = String.length s in
 init n (fun i -> f i (String.unsafe_get s i))

let iter2  f a b = iteri (fun i a -> f a (String.unsafe_get b i)) a
let iteri2 f a b = iteri (fun i a -> f i a (String.unsafe_get b i)) a

let map2  f a b = mapi (fun i a -> f a (String.unsafe_get b i)) a
let mapi2 f a b = mapi (fun i a -> f i a (String.unsafe_get b i)) a

(** Similar to the Unix command [tr]. The call [tr a b s] returns a copy of [s]
    where all occurrences of the character [a] have been replaced with [b]. *)
let tr a b = map (fun x -> if x=a then b else x) ;;

let fold_left f y0 s =
 let l = String.length s in
 let rec loop acc i =
  if i>=l then acc else
  let acc = f acc (String.unsafe_get s i) in
  loop acc (i+1)
 in loop y0 0

let fold_lefti f y0 s =
 let l = String.length s in
 let rec loop acc i =
  if i>=l then acc else
  let acc = f i acc (String.unsafe_get s i) in
  loop acc (i+1)
 in loop y0 0

let fold_righti f s y0 =
 let l = String.length s in
 let rec loop acc i =
  if i<0 then acc else
  let acc = f i (String.unsafe_get s i) acc in
  loop acc (i-1)
 in loop y0 (l-1)

let fold_right f s y0 =
 let l = String.length s in
 let rec loop acc i =
  if i<0 then acc else
  let acc = f (String.unsafe_get s i) acc in
  loop acc (i-1)
 in loop y0 (l-1)

let fold_left2  f s0 xs ys = fold_lefti  (fun i s x -> f s x ys.(i)) s0 xs
let fold_right2 f xs ys s0 = fold_righti (fun i x s -> f x ys.(i) s) xs s0

let fold_lefti2  f s0 xs ys = fold_lefti  (fun i s x -> f i s x ys.(i)) s0 xs
let fold_righti2 f xs ys s0 = fold_righti (fun i x s -> f i x ys.(i) s) xs s0

(** Split a string into a list of strings containing
    each one [n] characters of the input string (by default [n=1]). {b Examples}:
{[# cut "aabbc";;
  : string list = ["a"; "a"; "b"; "b"; "c"]

# cut ~n:2 "aabbc";;
  : string list = ["aa"; "bb"; "c"]

# cut ~n:3 "aabbc";;
  : string list = ["aab"; "bc"]
]} *)
let cut ?(n:int=1) (s:string) =
 let l = String.length s in
 let rec loop s l =
  if l=0 then []  else
  if l<n then [s] else
   let l' = (l-n) in
   (String.sub s 0 n)::(loop (String.sub s n l') l')
 in loop s l

(** Split a string into a list of strings using a char delimiter (which is the blank character [d=' '] by default).
    By default contiguous delimiter repetitions are considered as single occurrences.
    In other words, delimiters are squeezed. Set to optional parameter [do_not_squeeze] to disable this behaviour.
    The empty string is converted into the empty list. {b Example}:
{[# split "aaa bbb ccc";;
  : string list = ["aaa"; "bbb"; "ccc"]

# split "aaa   bbb ccc";;
  : string list = ["aaa"; "bbb"; "ccc"]

# split ~do_not_squeeze:() "aaa   bbb ccc";;
  : string list = ["aaa"; ""; ""; "bbb"; "ccc"]

]}*)
let rec split ?do_not_squeeze ?(d:char=' ') (s:string) =
 try
  let l = String.length s in
  let p = String.index s d in
  let rest = split ?do_not_squeeze ~d (StringLabels.sub ~pos:(p+1) ~len:(l-p-1) s) in
  if (do_not_squeeze = None) && (p=0)
    then rest
    else (StringLabels.sub ~pos:0 ~len:p s)::rest
 with
  _ -> if (s="") then [] else [s]

(** Split a string into a string list using a list of blanks as word separators.
    By default blanks are [['\t';' ']] and will be squeezed. *)
let split_squeezing_blanks ?(blanks=['\t';' ']) (s:string) : string list =
 let xs = Charlist.disassemble_reversing s in
 let push_if_not_empty x l = if x=[] then l else (x::l) in
 let rec loop previous_blank acc1 acc2 = function
  | []      -> (push_if_not_empty acc1 acc2)
  | b ::xs when (List.mem b blanks) ->
	if previous_blank
	then loop true acc1 acc2 xs
	else loop true [] (push_if_not_empty acc1 acc2) xs
   |  x  ::xs -> loop false (x::acc1) acc2 xs
  in
  let xs = List.map Charlist.assemble (loop false [] [] xs) in
 xs

(* val word : ?blanks:char list -> string -> int -> string *)
let word ?blanks (s:string) =
  let ws = split_squeezing_blanks ?blanks s in
  let ws = Array.of_list ws in
  fun i -> try ws.(i-1) with _ -> ""

(** Catenate a list of strings in an efficient way: the target string is created once
    (not as happen with a fold of [^]). The optional [?(blit=blit.blit)] allows
    to perform some operations during the copy of characters (see the function {!StringExtra.blitting}). *)
let concat ?(blit:blit_function=Bytes.blit) xs =
 let len  = List.fold_left (fun k s -> k+(String.length s)) 0 xs in
 let dst  = Bytes.create len in
 let _ =
    List.fold_left
    (fun k src ->
       let src = Bytes.of_string src in
       let l=(Bytes.length src) in (blit src 0 dst k l); (k+l)) 0 xs
 in
 Bytes.to_string dst

(** Remove all occurrences of a character from a string. *)
let rm d s = concat (split ~d s) ;;

(** Quote a string using a prefix [l] (by default [l="'"]) and a suffix [r] (by default [r="'"]). *)
let quote ?(l="'") ?(r="'") (x:string) = String.concat "" [l;x;r]

(** Assemble a string with a prefix and a suffix but only if it is {b not} empty, else
     return the empty string ignoring the given prefix and suffix. *)
let assemble_if_not_empty ~prefix ~suffix x =
  if (x="") then "" else (String.concat "" [prefix;x;suffix])

(** [map_concat f l] maps the function [f] on the list [l]
    then merge the result with the separator ([sep=" "] by default). *)
let map_concat ?(sep=" ") f l = String.concat sep (List.map f l)

 (** Merge fields with a separator. {b Example}:
{[# merge_fields "/" [2;4] ["aaa";"bbb";"ccc";"ddd";"eee"] ;;
  : string = "ccc/eee"
]}*)
let merge_fields sep (fieldlist:int list) (l:string list) =
 let l'=(ListExtra.select l fieldlist) in (String.concat sep l')

(** Convert a string in a [line] just adding a newline {b if needed}.
    The function {!StringExtra.chop} may be used as inverse.

{b Example}:
{[# ensure_cr_at_end "hello";;
  : string = "hello\n"

# ensure_cr_at_end "hello\n";;
  : string = "hello\n"]}*)
let ensure_cr_at_end x =
 if x="" then "\n" else (* continue *)
 let l    = (String.length x) in
 let last = (String.sub x (l-1) 1) in
 match last with "\n" -> x | _ -> x^"\n"

type word = string

(** Converting raw text to list of strings and vice-versa.
    A raw text is simply a (may be big) string, i.e. a sequence of lines
    collected in a unique string, where each line terminates with a newline ['\n'].
    The last line in the text may not terminate with a newline. *)
module Text = struct

(** In this context, a line is not structured, it's a flatten string. *)
type line = string

(** A (line structured) text is a {b list} of strings. *)
type t = line list


(** Convert a string list in a raw text.
    Each string in the input list is treated by the function [ensure_cr_at_end] in order to
    add a newline if needed, then the list is folded by a simple catenation ([^]).
    If the input list is empty, the result is the empty string. {b Examples}:
{[# Text.to_string ["AAA";"BBB";"CCC"];;
  : string = "AAA\nBBB\nCCC\n"

# Text.to_string ["AAA";"BBB\n";"CCC"];;
  : string = "AAA\nBBB\nCCC\n"

# Text.to_string ["AAA";"BBB\n\n";"CCC"];;
  : string = "AAA\nBBB\n\nCCC\n"]}*)
let to_string (sl : string list) : string =
 let ll = List.map ensure_cr_at_end sl in
 String.concat "" ll

(** Convert a raw text in a structured text (a string list).
    This function is simply an alias
    for [split ~d:'\n']. {b Examples}:
{[# Text.of_string (UnixExtra.cat "/etc/fstab")  ;;
  : string list =
["/dev/sda1   /                    reiserfs   acl,user_xattr    1 1";
 "/dev/sda3   swap                 swap       defaults          0 0";
 "/dev/sda4   /home                reiserfs   acl,user_xattr    1 1";
 "proc        /proc                proc       defaults          0 0";
 "/dev/fd0    /media/floppy        auto       noauto,user,sync  0 0"]

# Text.of_string (Unix.shell "echo aaa; echo; echo bbb");;
  : string list = ["aaa"; "bbb"]

# Text.of_string ~do_not_squeeze:() (Unix.shell "echo aaa; echo; echo bbb");;
  : string list = ["aaa"; ""; "bbb"] ]} *)
let of_string = (split ~d:'\n')

(** Grep on string lists: only strings matching the pattern are selected.
    The optional arguments [~before] and [~after] correspond to the options
    [-B] and [-A] of the homonymous Unix command.

{b Examples}:
{[# grep "[0-9]" ["aa";"bb";"c8";"dd";"1e"]  ;;
  : string list = ["c8"; "1e"]

# grep "[0-9]$" ["aa";"bb";"c8";"dd";"1e"]  ;;
  : string list = ["c8"]

# "ls" => ( Sys.run || fst || String.to_list || grep ".*mli$" ) ;;
  : string list = ["foo.mli"; "bar.mli"] ]}
*)
let grep ?before ?after (r:Str.regexp) (sl:string list) : string list =
 if before = None && after = None then
   List.filter (StrExtra.First.matchingp r) sl
 else
 let before = Option.extract_or before 0 in
 let after  = Option.extract_or after 0 in
 let sa = Array.of_list sl in
 let last_index = (Array.length sa) - 1 in
 let sl = ListExtra.mapi (fun i s -> (i,s)) sl in
 let xs = List.filter (fun (i,s) -> StrExtra.First.matchingp r s) sl in
 let parts =
   List.map
     (fun (i,line) ->
       let b =
         let before' = min before i in
         Array.to_list (Array.sub sa (i-before') before')
       in
       let a = Array.to_list (Array.sub sa (i+1) (min after (last_index-i))) in
       List.concat [b;[line];a]
       )
     xs
 in
 List.concat parts
;;

(** Here ~do_not_squeeze refers of course to the word delimiter [d]. *)
let collapse_and_split ?do_not_squeeze ?(d=' ') t =
  let s = String.concat (Char.escaped d) t in
  split ?do_not_squeeze ~d s

(** Merge fixed-length size groups of lines. *)
let merge_lines ?(sep=" ") (n:int) xs =
  let xss = ArrayExtra.amass (~size:n) (Array.of_list xs) in
  let zs  = Array.map (fun ys -> String.concat sep (Array.to_list ys)) xss in
  Array.to_list zs

(** Converting raw text to matrix (list of list) of strings (words) and vice-versa. *)
module Matrix = struct

(** We call "words" the strings stored in the matrix. *)
type line = word list

(** A (word structured) text is a {b matrix} of strings. *)
type t = word list list

(** Convert a raw text in a matrix of words.
    By default the function [split_squeezing_blanks] is called for each
    line to separe words. However, specifying a delimiter [~d] and/or setting
    [do_not_squeeze], the conversion will call the function [split ?do_not_squeeze ?d ] instead.
{b Example}:
{[# Text.Matrix.of_string (UnixExtra.shell "ls -i -w1 /etc/ssh/")  ;;
  : string list list =
[["98624"; "moduli"]; ["98625"; "ssh_config"]; ["98626"; "sshd_config"];
 ["274747"; "ssh_host_dsa_key"]; ["274748"; "ssh_host_dsa_key.pub"];
 ["274712"; "ssh_host_key"]; ["274713"; "ssh_host_key.pub"];
 ["274750"; "ssh_host_rsa_key"]; ["274751"; "ssh_host_rsa_key.pub"]]
]} *)
let of_string ?do_not_squeeze ?d x =
  let do_not_squeeze_d, do_not_squeeze_cr =
    match do_not_squeeze with
    | None       -> None, None
    | Some `cr   -> None, (Some ())
    | Some `d    -> (Some ()), None
    | Some `neither -> (Some ()), (Some ())
  in
  let lines = of_string ?do_not_squeeze:do_not_squeeze_cr x in
  if (do_not_squeeze=None) && (d=None)
  then
    List.map split_squeezing_blanks lines
  else
    List.map (split ?do_not_squeeze:do_not_squeeze_d ?d) lines

(** Convert a matrix of words in a raw text.
    By default the word delimiter is the string [d=" "].
{[# let m = Text.Matrix.of_string (Unix.shell "ls -l /etc/ssh/")
  in print_string (Text.Matrix.to_string m);;
total 164
-rw------- 1 root root 132839 2006-11-11 00:12 moduli
-rw-r--r-- 1 root root 2517 2006-11-11 00:12 ssh_config
-rw-r----- 1 root root 3474 2006-11-11 00:12 sshd_config
-rw------- 1 root root 668 2006-11-20 12:50 ssh_host_dsa_key
-rw-r--r-- 1 root root 600 2006-11-20 12:50 ssh_host_dsa_key.pub
-rw------- 1 root root 525 2006-11-20 12:50 ssh_host_key
-rw-r--r-- 1 root root 329 2006-11-20 12:50 ssh_host_key.pub
-rw------- 1 root root 887 2006-11-20 12:50 ssh_host_rsa_key
-rw-r--r-- 1 root root 220 2006-11-20 12:50 ssh_host_rsa_key.pub
  : unit = ()
]}*)
let to_string ?(d=" ") m =
  let rec line_mill acc = function
  | []    -> "\n"::acc
  | [w]   -> "\n"::w::acc
  | w::ws -> line_mill (d::w::acc) ws
  in
  let line_list_mill = List.rev_map (line_mill []) in
  let ws = List.rev (List.concat (line_list_mill m)) in
  String.concat "" ws

let from_file ?do_not_squeeze ?d s = of_string ?do_not_squeeze ?d (from_file s)

end (* module Text.Matrix *)

let from_file ?do_not_squeeze s = of_string ?do_not_squeeze (from_file s)

end (* module Text *)

(** By default the maximum line length is determined by [~width].
   However, setting ?count_all this limit will be the sum of
   [~width] and the lengths of [?tab] and [?prefix]. *)
let fmt ?tab ?prefix ?count_all ?(width=75) s =
 let tab_prefix = match tab with
 | None -> ""
 | Some n when n>=0 -> (String.make n ' ')
 | _ -> invalid_arg "StringExtra.fmt: ?tab must be positive"
 in
 let prefix = match prefix with
 | None        -> tab_prefix
 | Some prefix -> tab_prefix ^ prefix
 in
 let tab_len = String.length prefix in
 let tab_cost = match count_all with
 | None -> 0
 | Some () -> tab_len
 in
 let xs = List.flatten (Text.Matrix.of_string ~d:' ' s) in
 let rec loop acc = function
   | [] -> []
   | (x::xs) when acc = 0 (* first word *) && tab_len=0 ->
        let acc' = String.length x in
        x::(loop acc' xs)
   | (x::xs) when acc = 0 (* first word *) ->
        let acc' = tab_cost + (String.length x) in
        prefix::x::(loop acc' xs)
   | (x::xs) as ys ->
        let acc' = acc + 1 + (String.length x) in
        if acc'>width then "\n"::(loop 0 ys) else " "::x::(loop acc' xs)
 in
 let ys = loop 0 xs in
 String.concat "" ys

let tab ?tab ?prefix s =
 let tab_prefix = match tab with
 | None -> ""
 | Some n when n>=0 -> (String.make n ' ')
 | _ -> invalid_arg "StringExtra.tab: ?tab must be positive"
 in
 let prefix = match prefix with
 | None        -> tab_prefix
 | Some prefix -> tab_prefix ^ prefix
 in
 let prefix = if prefix = "" then "\t" else prefix in
 let yxs = (Text.Matrix.of_string ~do_not_squeeze:`d ~d:' ' s) in
 let yzs =
   List.map
     (function [] -> [prefix] | x::xs -> (Printf.sprintf "%s%s" prefix x)::xs)
     yxs
 in
 (Text.Matrix.to_string ~d:" " yzs)

let make_wide str n =
  if n<0 then invalid_arg "make_wide" else
  match String.length str with
  | l when l = n -> str
  | l when l < n ->  str^(String.make (n-l) ' ')
  | l (* l > n*) ->  String.sub str 0 n


 (* val group_by : ('a -> 'b) -> 'a list -> ('b * 'a list) list
    The result is sorted by labels ('b) with standard `compare':
    Example:
      group_by (String.length) [ "a"; "b"; "abc"; "ab"; "bc"; "bcd"; "abcd"; "cd"; "cde"; "defg" ] ;;
      - : (int * string list) list =
      [(1, ["b"; "a"]); (2, ["cd"; "bc"; "ab"]); (3, ["cde"; "bcd"; "abc"]); (4, ["defg"; "abcd"])]
    *)
 let group_by f xs =
   let lxs = List.map (fun x -> (f x, x)) xs in
   let ht = Hashtbl.create 0 in
   let () = List.iter (fun (l,x) -> Hashtbl.add ht l x) lxs in
   let keys = Hashtbl.fold (fun l x s -> l::s) ht [] in
   let keys = List.sort_uniq (compare) keys in
   List.map (fun l -> l, Hashtbl.find_all ht l) keys

 (* val partition : ('a -> 'b) -> 'a list -> ('a list) list
    As `group_by', but removing labels from the result:
      partition (String.length) [ "a"; "b"; "abc"; "ab"; "bc"; "bcd"; "abcd"; "cd"; "cde"; "defg" ] ;;
      - : string list list = [["b"; "a"]; ["cd"; "bc"; "ab"]; ["cde"; "bcd"; "abc"]; ["defg"; "abcd"]]
    *)
 let partition f xs =
   List.map snd (group_by f xs)

(* absorption [ "a"; "b"; "abc"; "ab"; "bc"; "bcd"; "abcd"; "cd"; "cde"; "defg" ]  ;;
    - : string list = ["b"; "a"; "cd"; "defg"]
    *)
let absorption (xs) =
  let xss = partition (String.length) xs in
  let yss = Array.of_list xss in
  let yss = List.mapi (fun i xs -> List.filter (fun x -> i=0 || List.for_all (fun y -> not (is_prefix y x)) yss.(i-1)) xs) xss in
  List.concat yss

