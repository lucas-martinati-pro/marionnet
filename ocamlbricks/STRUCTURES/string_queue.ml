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

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

IFNDEF OCAML4_02_OR_LATER THEN
module Bytes = struct  include String  let to_string x = x  let of_string x = x  end
type bytes = string
ENDIF

(* Each string in the queue comes with its real size <= block_size. *)
type t = {
  writer_mutex            : Mutex.t ; (* writers are queue producers. *)
  block_size              : int ;
  mutable total_size      : int ;
  queue                   : (bytes * int) Queue.t ;
  released                : unit Egg.t;
  reader_mutex            : Mutex.t ; (* The first reader is also the producer of the catenation. *)
  mutable catenation      : string option;
  }

(** Create a string queue. The optional [?block_size=8192] set the size of each string buffer in the queue. *)
let create ?(block_size=8192) () = {
  writer_mutex    = Mutex.create ();
  reader_mutex    = Mutex.create ();
  block_size      = block_size;
  total_size      = 0;
  queue           = Queue.create ();
  released        = Egg.create () ;
  catenation      = None ;
  }

(** The type of the standard [Bytes.blit]. *)
type blit_function = bytes -> int -> bytes -> int -> int -> unit

(** Thread-unsafe versions. If you are not using threads this is the module for you. *)
module Thread_unsafe = struct

(** Import the content of the [Unix] file descriptor into a string queue. *)
let append_from_descr ?(release=true) t (fd:Unix.file_descr) : unit =
 if t.catenation <> None then failwith "String_queue.Thread_unsafe.append_from_descr: queue already consumed (catenated)."
 else begin
  let block_size   = t.block_size in
  let current_size = t.total_size in
  let q = t.queue in
  let buff = Bytes.create block_size in
  let rec loop acc_n =
   begin
    let n = (Unix.read fd buff 0 block_size)    in
    if (n=0) then acc_n else ((Queue.push ((Bytes.sub buff 0 n),n) q); loop (acc_n + n))
   end in
  let dst_size = loop current_size in
  (t.total_size <- dst_size);
  (if release then (Egg.release t.released ()) else ());
 end

(** Efficient concatenation of the string queue content. The queue internal queue is then destructively emptied
    but the result of catenation remains available for other readers. *)
let concat ?(blit:blit_function=Bytes.blit) t : string =
 match t.catenation with
 | Some s -> s
 | None ->
    begin
     let dst_size = t.total_size in
     let q        = t.queue      in
     let dst = Bytes.create dst_size in
     let rec loop dstoff = if dstoff>=dst_size then () else
      begin
       let (src,src_size) = Queue.take q in
       (blit src 0 dst dstoff src_size);
       loop (dstoff+src_size)
     end in
    (loop 0);
    let dst = Bytes.to_string dst in
    (t.catenation <- Some dst);
    dst
   end

end

(* Mutex equipped by with_mutex. *)
module Mutex = MutexExtra.Extended_Mutex

(** Append the content of the [Unix] file descriptor into a string queue. By default, the queue is built then
    released [?(release=true)], then is ready to be catenated by a reader. *)
let append_from_descr ?(release=true) t (fd:Unix.file_descr) : unit =
 Mutex.with_mutex t.writer_mutex (fun () -> Thread_unsafe.append_from_descr ~release t fd)

(** Import the content of the [Unix] file descriptor into a string queue. *)
let from_descr ?(release=true) ?(block_size=8192) (fd:Unix.file_descr) : t =
 let result = create ~block_size () in
 (Thread_unsafe.append_from_descr ~release result fd);
 result

(** Similar to {!String_queue.from_descr}) but the user provides the file name instead of the file descriptor. *)
let from_file ?(release=true) ?(block_size=8192) (filename:string) : t =
 let fd = (Unix.openfile filename [Unix.O_RDONLY;Unix.O_RSYNC] 0o640) in
 let result = from_descr ~release ~block_size fd in
 (Unix.close fd);
 result

(** Similar to {!String_queue.from_descr}) but the user provides the [Pervasives.in_channel] instead of the file descriptor. *)
let from_channel ?(release=true) ?(block_size=8192) in_channel : t =
 from_descr ~release ~block_size (Unix.descr_of_in_channel in_channel)


(** Efficient concatenation of the string queue content. The catenation is performed by the first reader
    when the queue is released by a writer. If a successive reader requires the catenation, it will get it
    immediately. *)
let concat ?(blit:blit_function=Bytes.blit) t : string =
 let () = Egg.wait t.released in
 Mutex.with_mutex t.reader_mutex (fun () -> Thread_unsafe.concat ~blit t)
