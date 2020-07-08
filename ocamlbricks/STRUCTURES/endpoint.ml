(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009  Jean-Vincent Loddo

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

(** Abstract channel endpoints (sources and sinks). *)

IFNDEF OCAML4_02_OR_LATER THEN
module Bytes = struct  include String  let to_string x = x  let of_string x = x  end
type bytes = string
ENDIF

(** Abstract source (or negative) channel endpoints. *)
module Source = struct

(** The abstract type of a source endpoint *)
type t =
  | Unix_descr of Unix.file_descr  (** An already opened unix descriptor. *)
  | In_channel of in_channel       (** An already opened pervasives input channel. *)
  | Filename   of string           (** A file name. *)
  | String     of string           (** A string content. *)
  | Empty                          (** A shorthand for [String ""] *)

(** A string description of the source, for building messages. *)
let to_string = function
 | Unix_descr  c when c=Unix.stdin -> "stdin"
 | Unix_descr  _ -> "Unix descriptor"
 | In_channel  c when c=stdin -> "stdin"
 | In_channel  c -> "in_channel"
 | Filename    f -> f
 | String      s -> "String \""^s^"\""
 | Empty         -> "Empty"

(** Create a unix file descriptor from a source if necessary.
    The function returns also a flag indicating if the descriptor must be closed.
    If the user has given directly a descriptor (unix or standard), the descriptor
    do not must be closed. If the user has given a filename, the on-the-fly created
    descriptor must be closed. *)
let to_file_descr =
  let in_descr_of_string (s:string) =
    let s = Bytes.of_string s in
    let len = (Bytes.length s) in
    let (pread,pwrite) = Unix.pipe () in
    let count = (Unix.write pwrite s 0 len) in
    (assert (count = len));
    (Unix.close pwrite);
    pread
  in
  function
  | Unix_descr  d -> (d, false)
  | In_channel  c -> ((Unix.descr_of_in_channel c), false)
  | Filename    s -> ((Unix.openfile s [Unix.O_RDONLY] 0o640), true)
  | String      s -> ((in_descr_of_string s),true)
  | Empty         -> ((in_descr_of_string ""),true)

(** Same as [to_file_descr] but to create pervasives input channels. *)
let to_in_channel =
  function
  | Unix_descr  d -> ((Unix.in_channel_of_descr d), false)
  | In_channel  c -> (c, false)
  | other_case     ->
      let d, flag = to_file_descr (other_case) in
      (Unix.in_channel_of_descr d), flag

type line = string    (** Lines are strings separated by ['\n'] in the source *)
type word = string    (** Words are substrings of a line *)
type delimiter = char (** Word delimiter, the Blank character by default *)
type recno = int      (** The total number of input records seen so far, starting from [1] *)
type fieldno = int    (** The total number of fields seen so far, starting from [1] *)

(** Open and convert the source into a channel, apply the function, then close it if necessary. *)
let with_in_channel t (f : in_channel -> 'a) =
  let (ch, flag) = to_in_channel t in
  let result = f ch in
  let () = if flag then (close_in ch) in
  result

(** Open and convert the source into a file descriptor, apply the function, then close it if necessary. *)
let with_file_descr t (f : Unix.file_descr -> 'a) =
  let (fd, flag) = to_file_descr t in
  let result = f fd in
  let () = if flag then (Unix.close fd) in
  result

(* Re-implemented in imperative style in order to avoid "Stack overflow during evaluation (looping recursion?)". *)
let fold_lines (f : 'a -> recno -> line -> 'a) s t : 'a =
  with_in_channel t
    begin
      fun ch ->
        let acc = ref s in
        let i = ref 1 in
        let () =
          try while true do
            let line = input_line ch in
            let acc' = (f !acc !i line) in
            incr i;
            acc := acc';
          done
          with End_of_file -> ()
        in
        !acc
    end

let map_lines (f : recno -> line -> 'a) t : 'a array =
  let (xs, size) = fold_lines (fun (acc,_) i line -> ((f i line)::acc),i) ([],0) t in
  ArrayExtra.of_known_length_list ~reversing:true size xs

(** {b Example}:
{[ Source.iter_lines (Printf.printf "(%d) %s\n") (Source.Filename "/etc/fstab") ;;
]} *)
let iter_lines (f : recno -> line -> unit) t =
  fold_lines (fun _ i line -> (f i line)) () t

(* --- *)

let fold_word_lists ?d (f : 'a -> recno -> word list -> 'a) s t : 'a =
  fold_lines (fun a i line -> f a i (StringExtra.split ?d line)) s t

let map_word_lists ?d (f : recno -> word list -> 'a) t : 'a array =
  map_lines (fun i line -> f i (StringExtra.split ?d line)) t

let iter_word_lists ?d (f : recno -> word list -> unit) t =
  iter_lines (fun i line -> f i (StringExtra.split ?d line)) t

(* --- *)

let fold_word_arrays ?d (f : 'a -> recno -> word array -> 'a) s t : 'a =
  fold_lines (fun a i line -> f a i (Array.of_list (StringExtra.split ?d line))) s t

let map_word_arrays ?d (f : recno -> word array -> 'a) t : 'a array =
  map_lines (fun i line -> f i (Array.of_list (StringExtra.split ?d line))) t

let iter_word_arrays ?d (f : recno -> word array -> unit) t =
  iter_lines (fun i line -> f i (Array.of_list (StringExtra.split ?d line))) t

(* --- *)

(** {b Example}:
{[
Source.fold_words (fun n _ _ _ -> n+1) 0 (Source.Filename "/etc/fstab") ;;
: int = 88

UnixExtra.run "wc -w /etc/fstab" ;;
: string * Unix.process_status = ("88 /etc/fstab\n", Unix.WEXITED 0)
]} *)
let fold_words ?d (f : 'a -> recno -> fieldno -> word -> 'a) s t : 'a =
  fold_word_arrays ?d (fun s i ws -> ArrayExtra.fold_lefti (fun j a w -> f a i (j+1) w) s ws) s t

let iter_words ?d (f : recno -> fieldno -> word -> unit) t =
  iter_word_arrays ?d (fun i ws -> Array.iteri (fun j w -> f i (j+1) w) ws) t

(** {b Example}:
{[
Source.map_words (fun _ _ -> String.capitalize_ascii) (Source.Filename "/etc/fstab") ;;
: string array array =
\[|\[|"#"; "/etc/fstab:"; "Static"; "File"; "System"; "Information."|\];
...
|\] ]} *)
let map_words ?d (f : recno -> fieldno -> word -> 'a) t : 'a array array =
  map_word_arrays ?d (fun i ws -> Array.mapi (fun j w -> f i (j+1) w) ws) t

end


(** Abstract sink (or positive) channel endpoints. *)
module Sink = struct

(** The abstract type of a sink endpoint. *)
type t =
  | Unix_descr   of Unix.file_descr            (** An already opened unix descriptor. *)
  | Out_channel  of out_channel                (** An already opened pervasives output channel. *)
  | Filename     of string                     (** A file name, (re)writing. *)
  | Filename_append of string                  (** A file name, appending. *)
  | Filename_overtype of string                (** A file name, overtyping (no truncate). *)
  | Fun_thread   of (Unix.file_descr -> unit)  (** A consumer function. *)
  | String_queue of String_queue.t             (** A string queue. *)
  | Trash                                      (** A sort of /dev/null. *)

(** A string description of the sink, for building messages. *)
let to_string = function
 | Unix_descr  c when c=Unix.stdout -> "stdout"
 | Unix_descr  c when c=Unix.stderr -> "stderr"
 | Unix_descr  _ -> "Unix descriptor"
 | Out_channel c when c=stdout -> "stdout"
 | Out_channel c when c=stderr -> "stderr"
 | Out_channel c -> "out_channel"
 | Filename    f -> f
 | Filename_append f -> ">>"^f
 | Filename_overtype f -> "overtyping "^f
 | Fun_thread   _ -> "Fun_thread"
 | String_queue _ -> "String_queue"
 | Trash          -> "Trash"

(** Create a unix file descriptor from a sink if necessary.
    The function returns also a flag indicating if the descriptor must be closed.
    If the user has given directly a descriptor (unix or standard), the descriptor
    do not must be closed. If the user has given a filename, a treatment function or
    a string queue, the on-the-fly created descriptor must be closed. *)
let to_file_descr =
 let out_descr_of_fun_thread f =
   let (pread,pwrite) = Unix.pipe () in
   let try_close d = try (Unix.close d) with _ -> () in
   let wrap f d =
     (let res = try (f d) with e -> ((try_close d); raise e) in (try_close d); res)
   in
   let () = ignore (Thread.create (wrap f) pread) in
   pwrite
 in
 function
 | Unix_descr   d -> (d, false)
 | Out_channel  c -> ((Unix.descr_of_out_channel c), false)
 | Filename          s -> ((Unix.openfile s [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC;] 0o640), true)
 | Filename_append   s -> ((Unix.openfile s [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_APPEND;] 0o640), true)
 | Filename_overtype s -> ((Unix.openfile s [Unix.O_WRONLY; Unix.O_CREAT;] 0o640), true)
 | Fun_thread   f -> ((out_descr_of_fun_thread f),true)
 | String_queue q ->
    let f = fun fd -> String_queue.append_from_descr ~release:true q fd; in
    ((out_descr_of_fun_thread f),true)
 | Trash ->
    let block_size = 1024 in
    let buff = Bytes.create block_size in
    let rec trash_loop fd =
      let n = (Unix.read fd buff 0 block_size) in
      if (n=0) then () else trash_loop fd
    in
    ((out_descr_of_fun_thread trash_loop),true)

(** Same as [to_file_descr] but to create pervasives output channels. *)
let to_out_channel =
 function
 | Unix_descr   d -> ((Unix.out_channel_of_descr d), false)
 | Out_channel  c -> (c, false)
 | other_case     ->
     let d,flag = to_file_descr (other_case) in
     (Unix.out_channel_of_descr d), flag

(** Open and convert the sink into a channel, apply the function, then close it if necessary. *)
let with_out_channel t (f : out_channel -> 'a) =
  let (ch, flag) = to_out_channel t in
  let result = f ch in
  let () = if flag then (try close_out ch with _ -> ()) in
  result

(** Open and convert the sink into a file descriptor, apply the function, then close it if necessary. *)
let with_file_descr t (f : Unix.file_descr -> 'a) =
  let (fd, flag) = to_file_descr t in
  let result = f fd in
  let () = if flag then (Unix.close fd) in
  result

type line = string      (** Lines are strings separated by default by ['\n'] in the sink *)
type word = string      (** Words are strings separated by default by Blanks in a line *)
type linesep = string   (** Line (record) separator, by default ['\n'] *)
type wordsep = string   (** Word (field) separator, by default [' '] (Blank) *)

let print_string t s =
  with_out_channel t
    (fun ch -> Printf.kfprintf flush ch "%s" s)

let print_lines ?(rs="\n") t xs =
  with_out_channel t
    (fun ch -> Array.iter (fun x -> Printf.fprintf ch "%s%s" x rs) xs)

let print_word_lists ?(rs="\n") ?(fs=" ") t wss =
  with_out_channel t
    (fun ch -> Array.iter (fun ws -> Printf.fprintf ch "%s%s" (String.concat fs ws) rs) wss)

let print_word_arrays ?(rs="\n") ?(fs=" ") t wss =
  with_out_channel t
    (fun ch -> Array.iter (fun ws -> Printf.fprintf ch "%s%s" (String.concat fs (Array.to_list ws)) rs) wss)

let printf1 t fmt xs =
  with_out_channel t
    (fun ch -> Array.iter (function x1 -> Printf.fprintf ch fmt x1) xs)

let printf2 t fmt xs =
  with_out_channel t
    (fun ch -> Array.iter (function x1,x2 -> Printf.fprintf ch fmt x1 x2) xs)

let printf3 t fmt xs =
  with_out_channel t
    (fun ch -> Array.iter (function x1,x2,x3 -> Printf.fprintf ch fmt x1 x2 x3) xs)

let printf4 t fmt xs =
  with_out_channel t
    (fun ch -> Array.iter (function x1,x2,x3,x4 -> Printf.fprintf ch fmt x1 x2 x3 x4) xs)

let printf5 t fmt xs =
  with_out_channel t
    (fun ch -> Array.iter (function x1,x2,x3,x4,x5 -> Printf.fprintf ch fmt x1 x2 x3 x4 x5) xs)

let printf6 t fmt xs =
  with_out_channel t
    (fun ch -> Array.iter (function x1,x2,x3,x4,x5,x6 -> Printf.fprintf ch fmt x1 x2 x3 x4 x5 x6) xs)

let printf7 t fmt xs =
  with_out_channel t
    (fun ch -> Array.iter (function x1,x2,x3,x4,x5,x6,x7 -> Printf.fprintf ch fmt x1 x2 x3 x4 x5 x6 x7) xs)

let printf8 t fmt xs =
  with_out_channel t
    (fun ch -> Array.iter (function x1,x2,x3,x4,x5,x6,x7,x8 -> Printf.fprintf ch fmt x1 x2 x3 x4 x5 x6 x7 x8) xs)

let printf9 t fmt xs =
  with_out_channel t
    (fun ch -> Array.iter (function x1,x2,x3,x4,x5,x6,x7,x8,x9 -> Printf.fprintf ch fmt x1 x2 x3 x4 x5 x6 x7 x8 x9) xs)

let printf10 t fmt xs =
  with_out_channel t
    (fun ch -> Array.iter (function x1,x2,x3,x4,x5,x6,x7,x8,x9,x10 -> Printf.fprintf ch fmt x1 x2 x3 x4 x5 x6 x7 x8 x9 x10) xs)

let printf11 t fmt xs =
  with_out_channel t
    (fun ch -> Array.iter (function x1,x2,x3,x4,x5,x6,x7,x8,x9,x10,x11 -> Printf.fprintf ch fmt x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11) xs)

let printf12 t fmt xs =
  with_out_channel t
    (fun ch -> Array.iter (function x1,x2,x3,x4,x5,x6,x7,x8,x9,x10,x11,x12 -> Printf.fprintf ch fmt x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12) xs)

end
