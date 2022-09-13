(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009 2020  Jean-Vincent Loddo
   Copyright (C) 2009 2020  Université Sorbonne Paris Nord

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


module Log = Ocamlbricks_log

type 'a thread_status =
| Completed of 'a
| Exception of exn

(** The abstract type of a future. *)
type 'a future = (('a thread_status) Egg.t) * Thread.t

(** Alias. *)
type 'a t = 'a future

(** Create a future applying an argument to a function. The result of the function may be got later with [touch] or [taste]. *)
let thread (f:'a -> 'b) (x:'a) : 'b t =
 let egg = Egg.create () in
 let wrap x =
   let y = (try Completed (f x) with e -> Exception e)
   in Egg.release egg y
 in
 let thd = Thread.create wrap x in
 (egg,thd)

let make = thread
let make' x f = thread f x (* flipped version *)

(** {b Wait} until the result is ready. Re-raise [exn] if the future has been interrupted by the exception [exn]. *)
let touch (egg,thd) =
 match Egg.wait egg with
| Completed y -> y
| Exception e -> raise e

(** Check if the result is ready (non-blocking): [None] means {e not ready}, while [Some y] means {e ready with value} [y].
Re-raise [exn] if the future has been interrupted by the exception [exn]. *)
let taste (egg,thd) : 'a option =
 match Egg.taste egg with
 | None   -> None
 | Some v ->
    (match v with
    | Completed y -> Some y
    | Exception e -> raise e
    )

let to_thread (egg,thd) = thd
let of_thread = thread (Thread.join)

(* Reveal exceptions including them in the result (instead of re-raising them
   when touching or tasting). The advantage of using this module is to be able
   to compose computations with the monadic operators of the data type Either. *)
module Reveal = struct

  (* val touch : 'a future -> (exn, 'a) Either.t *)
  let touch (egg,thd) =
    match Egg.wait egg with
    | Completed y -> Either.Right y
    | Exception e -> Either.Left e

  (* val taste : 'a future -> (exn, 'a) Either.t option *)
  let taste (egg,thd) : 'a option =
  match Egg.taste egg with
  | None   -> None
  | Some v ->
      (match v with
      | Completed y -> Some (Either.Right y)
      | Exception e -> Some (Either.Left e)
      )

end (* Reveal *)

let terminated t =
 (Reveal.taste t) <> None

let ready t =
  match Reveal.taste t with
  | Some (Either.Right _) -> true
  | _ -> false

type pid = int

(* ------------------------------- *)
module Fork_implementation = struct
(* ------------------------------- *)

  (* Similar to waitpid but protected from the exception [Unix.Unix_error (Unix.EINTR, _, _)].
     If this exception is raised, the function recalls itself and waits again: *)
  let rec waitpid_non_intr (pid) : (exn, bool) Either.t =
    try
      (match (Unix.waitpid [] pid) with
      | (_, Unix.WEXITED _)   -> Either.Right (true)
      | (_, Unix.WSIGNALED _) -> Either.Right (false)
      | (_, _) -> waitpid_non_intr (pid)
      )
    with
      | Unix.Unix_error (Unix.EINTR, _, _) -> waitpid_non_intr pid
      | e -> Either.Left e

  (* There are two reasons to use this low-level function instead of `exit'.
       (1) we don't want inherit the "at_exit" handlers of the main process, if any.
       (2) we want to prevent troubles with toplevels (waitpid fails,
           see https://github.com/ocaml-community/utop/issues/152) *)
  external caml_sys_exit : int -> unit = "caml_sys_exit"
  let exit_call : int -> 'a = Obj.magic (caml_sys_exit)

  (* Protect an action from any kind of exception: *)
  let protect f x : unit = try f x with _ -> ()

  (* This module could be replaced by functions added since OCaml 4.08 in the
     module Bytes (section "Binary encoding/decoding of integers") *)
  module Nat_encoding = struct
    (* --- *)
    let max_length = 4 * 1024*1024*1024 - 1 (* 4G-1 *)
    (* encode_nat [] (max_length) => [255; 255; 255; 255]
       encode_nat [] (1084)       => [4; 60] *)
    let encode_nat =
      let rec loop k acc x =
        if x=0 then (k, acc) else
        let y, r = (x/256), (x mod 256) in
        loop (k+1) (r::acc) y
      in
      fun x ->
        if x>max_length then invalid_arg "more than 4G bytes of data" else
        let ys =
          match loop 0 [] x with
          | (0, [])        -> [|0; 0; 0; 0|]
          | (1, [x])       -> [|0; 0; 0; x|]
          | (2, [x;y])     -> [|0; 0; x; y|]
          | (3, [x;y;z])   -> [|0; x; y; z|]
          | (4, [x;y;z;t]) -> [|x; y; z; t|]
          | (_,_) -> assert false
        in
        Bytes.init 4 (fun i-> char_of_int ys.(i))

    (* decode_nat (encode_nat x) = x *)
    let decode_nat =
      let factors = [| 16777216 (* 256^3 *); 65536 (* 256^2 *); 256 (* 256^1 *); 1 (* 256^0 *) |] in
      fun s ->
        if Bytes.length s <> 4 then invalid_arg "decode_nat" else
        let ys = Array.init 4 (fun i -> factors.(i) * int_of_char (Bytes.get s i)) in
        Array.fold_left (+) 0 ys
  end (* Fork_implementation.Nat_encoding *)

  (* Implemented only using Unix.file_descr (and thus, only using Unix.read and Unix.write)
     instead of Unix.in_channel and Unix.out_channel (with Marshal.from_channel and
     Marshal.to_channel). The unique reason of this choice is to prevent troubles with
     toplevels (more specifically, with toplevels, as for instance "utop", based on tools,
     as for instance Lwt, that wrap some system-calls).
     ---
     Example to test in a toplevel:
     ---
     let f x = Thread.delay 1.; exp (sqrt ((sin x) *. (log x))) ;;
     let a_list = [3.14; 1.27; 1.12; 2.14; 2.09; 2.11; 2.09; 2.18; 1.65; 1.70; 1.16; 1.23; 1.45; 1.56; 1.75 ] ;;
     let f2 () =  Future.List.map ~fork:() f (a_list) |> Future.Reveal.touch ;;
     UnixExtra.perf f2 () ;;
     ---
     *)
  let fork (f:'a ->'b) (x:'a) : ('b future) * pid =
    (*--- *)
    let pid : int Egg.t = Egg.create () in
    (* The following tool will be automatically protected from exceptions by `future': *)
    let fork_and_wait (x:'a) : 'b =
      (* --- *)
      let (fd0,   fd1) = Unix.pipe () in
      let (rdy0, rdy1) = Unix.pipe () in
      let (ack0, ack1) = Unix.pipe () in
      (* --- *)
      (* --- *)
      let marshal_and_send fd1 y : unit =
        try
          let s = Marshal.to_bytes (y) [Marshal.Closures] in
          let n = Bytes.length s in
          (* Send first the length of data (encoded with 4 bytes): *)
          let _ = Unix.write fd1 (Nat_encoding.encode_nat n) 0 4 in
          (* Then send the data: *)
          let _ = Unix.write fd1 s 0 n in
          ()
        with e -> begin
          let () = Log.printf3 "Future.fork: (FORK) marshal_and_send  pid=%d.%d  exn=%s\n" (Unix.getpid ()) (Thread.id (Thread.self ())) (Printexc.to_string e) in
          assert false end
      in
      (* --- *)
      let receive_and_unmarshal fd0 : (exn, 'b) Either.t =
        let rec read_all_bytes fd buff ofs len =
          if len = 0 then () else
          let k = Unix.read fd buff ofs len in
          read_all_bytes fd buff (ofs+k) (len-k)
        in
        try
          (* Read first the length of data (encoded with 4 bytes): *)
          let buf = Bytes.create 4 in
          let () = read_all_bytes fd0 buf 0 4 in
          let n = Nat_encoding.decode_nat buf in
          (* Then read the data: *)
          let buf = Bytes.create n in
          let () = read_all_bytes fd0 buf 0 n in
          let result = ((Marshal.from_bytes buf 0) : (exn, 'b) Either.t) in
          result
        with e -> begin
          let () = Log.printf1 "Future.fork: (THREAD) receive_and_unmarshal FAILED: %s\n" (Printexc.to_string e) in
          raise e end
      in
      (* --- *)
      match Unix.fork () with
      |	0 ->
          (* The child here: *)
          (* --- *)
          let send_result (y : (exn, 'b) Either.t) : unit =
            (* let () = Marshal.to_channel ch1 (y) [Marshal.Closures] in *)
            let () = marshal_and_send fd1 (y) in
            (* --- *)
            let () = Log.printf ~v:2 "Future.fork: (FORK) end of marshall_and_sent, about to send READY\n" in
            let _n = try Unix.write rdy1 (Bytes.of_string "R") 0 1 with _ -> 0 in
            protect Unix.close rdy1; (* Broken pipe => thread wake-up on read() *)
            (* --- *)
            let () = Log.printf ~v:2 "Future.fork: (FORK) about to receive ACK\n" in
            (* Wait until the fork process finished sending the result: *)
            (try ignore (Unix.read ack0 (Bytes.of_string " ") 0 1) with _ -> ());
            (* --- *)
            let () = Log.printf ~v:2 "Future.fork: (FORK) about to close channels and exit\n" in
            protect Unix.close fd1;
            protect Unix.close ack0;
            ()
          in
          begin
            try
              Unix.close fd0;
              Unix.close rdy0;
              Unix.close ack1;
              (* --- *)
              let () = Log.printf ~v:2 "Future.fork: (FORK) about to start computation\n" in
              let y, exit_code = try (Either.Right (f x), 0) with e -> ((Either.Left e), 1) in
              let () = Log.printf ~v:2 "Future.fork: (FORK) end of computation, about to send result\n" in
              (* --- *)
              send_result y;
              (* --- *)
              exit_call (exit_code)
            with e ->
              let () = Log.printf1 "Future.fork: (FORK) exception, about to exit with code 2: %s\n" (Printexc.to_string e) in
              exit_call 2
          end
      (* --- *)
      | child_pid ->
          (* The "father" entering here is a thread of the main process: *)
          let () = Egg.release pid (child_pid) in
          try begin
            (* --- *)
            let receive_result () : (exn, 'b) Either.t =
              let ey : (exn, 'b) Either.t = receive_and_unmarshal fd0 in
              protect Unix.close fd0;
              ey
            in
            let failwith_fork_maybe_killed () = raise (Failure "fork process killed?") in
            (* --- *)
            protect (* <= necessary? *) Unix.close fd1;
            protect (* <= necessary? *) Unix.close rdy1;
            protect (* <= necessary? *) Unix.close ack0;
            (* --- *)
            let () = Log.printf ~v:2 "Future.fork: (THREAD) about to receive RDY\n" in
            (* Wait until the fork process finished sending the result: *)
            let r = (try (Unix.read rdy0 (Bytes.of_string " ") 0 1) with _ -> 0) in
            (* --- *)
            let () = Log.printf1 ~v:2 "Future.fork: (THREAD) RDY received = %d, about to receive result\n" r in
            let () = if not (r=1) then failwith_fork_maybe_killed () in
            (* --- *)
            protect Unix.close rdy0;
            (* --- *)
            let () = if not (Thread.wait_timed_read fd0 1.) then failwith_fork_maybe_killed () in
            let result = receive_result () in
            (* --- *)
            let () = Log.printf ~v:2 "Future.fork: (THREAD) result received, about to send ACK\n" in
            let () = if not (Thread.wait_timed_write ack1 1.) then failwith_fork_maybe_killed () in
            (* --- *)
            (* Send and ack to the fork process: *)
            let a = try Unix.write ack1 (Bytes.of_string "A") 0 1 with _ -> 0 in
            (* --- *)
            let () = protect Unix.close ack1 in
            (* --- *)
            let () = Log.printf2 ~v:2 "Future.fork: (THREAD) ACK sent = %d, about to waitpid %d\n" a (child_pid) in
            (* Wait until the fork has been registered by the system as terminated: *)
            (match waitpid_non_intr (child_pid) with
            (* --- *)
             | Either.Left e      ->
                 let () = Log.printf1 "Future.fork: (THREAD) waitpid_non_intr exception: %s\n" (Printexc.to_string e) in
                 raise e
             (* --- *)
             | Either.Right false ->
                 raise (Failure "fork process killed")
             (* --- *)
             | Either.Right true  ->
                 (* Once the fork terminated, get its result by the pipe (fd0,fd1): *)
                 (* --- *)
                 (match result with
                 | Either.Left  e ->
                     let () = Log.printf1 "Future.fork: (THREAD) bad result (Either.Left) from fork %d\n" (child_pid) in
                     raise e
                 | Either.Right (y:'b) -> y
                 )
             )(* match *)
         end
         with e ->
           let () = Log.printf2 "Future.fork: THREAD tutoring fork %d FAILED: %s\n" (child_pid) (Printexc.to_string e) in
           let () = List.iter (protect Unix.close) [rdy0; fd0; ack1] in
           let _ = waitpid_non_intr (child_pid) in
           raise e (* <= not a problem: all exceptions should be catched by the `thread' implementation *)
    (* --- fork_and_wait *)
    in
    (* --- *)
    let result : 'b future = thread (fork_and_wait) (x) in
    (* --- *)
    (result, Egg.wait pid)

end (* Fork_implementation *)

let fork ?no_compact f x =
  (* Call Gc.compact() by default: *)
  let () = if no_compact = None then Gc.compact () in
  let (y, pid) as result = Fork_implementation.fork f x in
  result

let fork_and_forget_pid ?no_compact f x =
  (fork ?no_compact f x) |> fst

(* Now we can define the general constructor `future', that
   forgets the pid and doesn't execute Gc.compact() when forking: *)
let future ?fork ?no_compact =
  match fork with
  | None    -> thread
  | Some () -> fork_and_forget_pid ?no_compact

(* val bind : 'a future -> ('a -> 'b future) -> 'b future *)
let bind ?fork m f = future ?fork (function m -> touch (f (touch m))) m

let return x =
  let egg = Egg.create () in
  let  () = Egg.release egg (Completed x) in
  let thd = Thread.self () in
  (egg,thd)

(* val cobind : 'a future -> ('a future -> 'b) -> 'b future *)
let cobind ?fork m f = future ?fork f m

module List = struct

  (* List.map (future f) xs |> future (List.map touch) *)
  let map ?fork f xs =
    (* Prepare the main process to (may be many) fork with a clean and compact heap: *)
    let ()= if fork<>None then Gc.compact () in
    let ys = List.map (future ?fork ~no_compact:() f) xs in
    future (List.map touch) ys

  (* val map_reduce : ('a -> 'b) -> ('s -> 'b -> 's) -> s -> 'a list -> 's future
     map_reduce f op s0 xs =
       List.map (future f) xs |> future (List.fold_left (fun s b -> op s (touch b)) s0)
  *)
  let map_reduce ?fork f g s0 xs =
    (* Prepare the main process to (may be many) fork with a clean and compact heap: *)
    let ()= if fork<>None then Gc.compact () in
    let ys = List.map (future ?fork ~no_compact:() f) xs in
    future (List.fold_left (fun s b -> g s (touch b)) s0) ys

end (* List *)

module Array = struct

  (* List.map (future f) xs |> future (List.map touch) *)
  let map ?fork f xs =
    (* Prepare the main process to (may be many) fork with a clean and compact heap: *)
    let ()= if fork<>None then Gc.compact () in
    let ys = Array.map (future ?fork ~no_compact:() f) xs in
    future (Array.map touch) ys

  (* val map_reduce_list : ('a -> 'b) -> ('s -> 'b -> 's) -> s -> 'a list -> 's future
    map_reduce_list f op s0 xs =
      List.map (future f) xs |> future (List.fold_left (fun s b -> op s (touch b)) s0)
  *)
  let map_reduce ?fork f g s0 xs =
    (* Prepare the main process to (may be many) fork with a clean and compact heap: *)
    let ()= if fork<>None then Gc.compact () in
    let ys = Array.map (future ?fork ~no_compact:() f) xs in
    future (Array.fold_left (fun s b -> g s (touch b)) s0) ys

end (* Array *)

(* Future control (some details about fork/thread and thunk to kill or abort them): *)
module Control = struct

  type t = pid * tid * protected_kill
   and tid = int (* current thread identifier *)
   and protected_kill = (unit -> unit)

  let make ?(pid=Unix.getpid ()) ?kill () =
    let tid = Thread.id (Thread.self ()) in
    let kill =
      match kill with
      | Some f -> Fork_implementation.protect f
      | None ->
         (fun () ->
            let my_pid = Unix.getpid () in
            if pid = my_pid then () else (* continue: *)
            try
              Unix.kill pid Sys.sigkill;
              Thread.delay 0.1;
              Unix.kill pid Sys.sigkill
            with _ -> ())
    in
    (pid, tid, kill)

  let get_pid  (pid, tid, protected_kill) = pid
  let get_tid  (pid, tid, protected_kill) = tid
  let get_protected_kill (pid, tid, protected_kill) = protected_kill

end (* Control *)

