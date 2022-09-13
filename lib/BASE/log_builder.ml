(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2008  Luca Saiu
   Copyright (C) 2010  Jean-Vincent Loddo

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

(* Authors:
 * - Jean-Vincent Loddo: migration from marionnet, synchronization, functorization
 * - Luca Saiu: Original code in marionnet/log.ml
 *)

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

#load "include_type_definitions_p4.cmo";;
INCLUDE DEFINITIONS "../../../../lib/BASE/log_builder.mli"
;;

(* We will use an extended version of Mutex: *)
module Mutex = MutexExtra.Extended_Mutex

(* The global structures are not created at loading time (except global_mutex)
   but only if needed, at the first functor application. *)
let global_structures = ref None
let global_mutex = Mutex.create ()
let get_global_structures () =
 Mutex.with_mutex global_mutex
 (fun () -> match !global_structures with
  | None ->
     let ht = Hashtbl.create 51 in
     let ht_mutex = Mutex.create () in
     let stdout_mutex = Mutex.create () in
     let stderr_mutex = Mutex.create () in
     let () = Hashtbl.add ht "/dev/stdout" (stdout, stdout_mutex) in
     let () = Hashtbl.add ht "/dev/stderr" (stderr, stderr_mutex) in
     let tuple = (ht, ht_mutex, stdout_mutex, stderr_mutex) in
     let () = (global_structures := Some tuple) in
     tuple
  | Some tuple -> tuple
  )

(* The out channels are shared by all threads of the program. Hence, there is a mutex
   per channel. `file "/dev/stdout" (resp. `file "/dev/stderr") is equivalent to `stdout (resp. `stderr). *)
let get_out_channel log_channel =
 let (ht, ht_mutex, stdout_mutex, stderr_mutex) = get_global_structures () in
 let out_channel_and_mutex_of_filename fname =
  (try Hashtbl.find ht fname
     with
      Not_found ->
       begin
        let out_channel = open_out fname in
        let mutex = Mutex.create () in
        (Hashtbl.add ht fname (out_channel,mutex));
        (out_channel, mutex)
       end)
 in
 match log_channel with
  | `stdout -> (stdout, stdout_mutex)
  | `stderr -> (stderr, stderr_mutex)
  | `file fname -> Mutex.apply_with_mutex (ht_mutex) (out_channel_and_mutex_of_filename) fname


module Make
 (Tuning:sig
     val verbosity    : int              (* dynamic *)
     val debug_level  : unit -> int      (* dynamic *)
     val log_channel  : log_channel      (* static  *)
     val synchronized : bool             (* static  *)
   end) : Result =
 struct

  (** We redefine Tuning in order to provide it a modifiable state: *)
  module Tuning = struct
   module Variable = Stateful_modules.Thread_shared_variable
   module Verbosity = Variable (struct type t = int let name=None end)
   module Debug_level = Variable (struct type t = unit -> int let name=None end)
   let () = begin (* Variables initialization: *)
     Verbosity.set Tuning.verbosity;
     Debug_level.set Tuning.debug_level;
   end

   let verbosity = Verbosity.extract
   let debug_level () = Debug_level.extract () ()
   let is_log_enabled ?v () = match v with
    | None   -> (debug_level ()) >= (verbosity ())
    | Some v -> (debug_level ()) >= v
   let log_channel  = Tuning.log_channel
   let synchronized = Tuning.synchronized

   module Set = struct
    let verbosity = Verbosity.set
    let debug_level = Debug_level.set
   end

  end (* Tuning redefinition. *)

  let (out_channel, mutex) = get_out_channel Tuning.log_channel

  let apply_with_mutex (f:'a -> 'b) (x:'a) : 'b =
   Mutex.apply_with_mutex (mutex) f x

  let unprotected_test_is_log_disable ?v ?(force=false) () =
    not ((Tuning.is_log_enabled ?v ()) || force)

  let printf_unsynchronized ?(banner=true) (frmt:('a, out_channel, unit) format) : 'a =
    let () =
      match banner with
      | false -> ()
      | true  ->
	  let thread_id = Thread.id (Thread.self ()) in
	  let pid = Unix.getpid () in
	  let prefix = Printf.sprintf "[%d.%d]: " pid thread_id in
	  Printf.kfprintf flush out_channel "%s" prefix
    in
    Printf.kfprintf flush out_channel frmt

  (* Take a format string and either use it for Printf.printf, or use it
     for a dummy printf-like function which does nothing, according to
     whether we're in debug mode or not: *)
  (* printf0 *)
  let printf ?v ?force ?banner frmt =
   if unprotected_test_is_log_disable ?v ?force () then Printf.ifprintf out_channel frmt else
   if Tuning.synchronized
     then apply_with_mutex (fun () -> printf_unsynchronized ?banner frmt) ()
     else printf_unsynchronized ?banner frmt

  let printf1 ?v ?force ?banner frmt x1 =
   if unprotected_test_is_log_disable ?v ?force () then Printf.ifprintf out_channel frmt x1 else
   if Tuning.synchronized
     then apply_with_mutex (fun () -> printf_unsynchronized ?banner frmt x1) ()
     else printf_unsynchronized ?banner frmt x1

  let printf2 ?v ?force ?banner frmt x1 x2 =
   if unprotected_test_is_log_disable ?v ?force () then Printf.ifprintf out_channel frmt x1 x2 else
   if Tuning.synchronized
     then apply_with_mutex (fun () -> printf_unsynchronized ?banner frmt x1 x2) ()
     else printf_unsynchronized ?banner frmt x1 x2

  let printf3 ?v ?force ?banner frmt x1 x2 x3 =
   if unprotected_test_is_log_disable ?v ?force () then Printf.ifprintf out_channel frmt x1 x2 x3 else
   if Tuning.synchronized
     then apply_with_mutex (fun () -> printf_unsynchronized ?banner frmt x1 x2 x3) ()
     else printf_unsynchronized ?banner frmt x1 x2 x3

  let printf4 ?v ?force ?banner frmt x1 x2 x3 x4 =
   if unprotected_test_is_log_disable ?v ?force () then Printf.ifprintf out_channel frmt x1 x2 x3 x4 else
   if Tuning.synchronized
     then apply_with_mutex (fun () -> printf_unsynchronized ?banner frmt x1 x2 x3 x4) ()
     else printf_unsynchronized ?banner frmt x1 x2 x3 x4

  let printf5 ?v ?force ?banner frmt x1 x2 x3 x4 x5 =
   if unprotected_test_is_log_disable ?v ?force () then Printf.ifprintf out_channel frmt x1 x2 x3 x4 x5 else
   if Tuning.synchronized
     then apply_with_mutex (fun () -> printf_unsynchronized ?banner frmt x1 x2 x3 x4 x5) ()
     else printf_unsynchronized ?banner frmt x1 x2 x3 x4 x5

  let printf6 ?v ?force ?banner frmt x1 x2 x3 x4 x5 x6 =
   if unprotected_test_is_log_disable ?v ?force () then Printf.ifprintf out_channel frmt x1 x2 x3 x4 x5 x6 else
   if Tuning.synchronized
     then apply_with_mutex (fun () -> printf_unsynchronized ?banner frmt x1 x2 x3 x4 x5 x6) ()
     else printf_unsynchronized ?banner frmt x1 x2 x3 x4 x5 x6

  let printf7 ?v ?force ?banner frmt x1 x2 x3 x4 x5 x6 x7 =
   if unprotected_test_is_log_disable ?v ?force () then Printf.ifprintf out_channel frmt x1 x2 x3 x4 x5 x6 x7 else
   if Tuning.synchronized
     then apply_with_mutex (fun () -> printf_unsynchronized ?banner frmt x1 x2 x3 x4 x5 x6 x7) ()
     else printf_unsynchronized ?banner frmt x1 x2 x3 x4 x5 x6 x7

  let printf8 ?v ?force ?banner frmt x1 x2 x3 x4 x5 x6 x7 x8 =
   if unprotected_test_is_log_disable ?v ?force () then Printf.ifprintf out_channel frmt x1 x2 x3 x4 x5 x6 x7 x8 else
   if Tuning.synchronized
     then apply_with_mutex (fun () -> printf_unsynchronized ?banner frmt x1 x2 x3 x4 x5 x6 x7 x8) ()
     else printf_unsynchronized ?banner frmt x1 x2 x3 x4 x5 x6 x7 x8

  let printf9 ?v ?force ?banner frmt x1 x2 x3 x4 x5 x6 x7 x8 x9 =
   if unprotected_test_is_log_disable ?v ?force () then Printf.ifprintf out_channel frmt x1 x2 x3 x4 x5 x6 x7 x8 x9 else
   if Tuning.synchronized
     then apply_with_mutex (fun () -> printf_unsynchronized ?banner frmt x1 x2 x3 x4 x5 x6 x7 x8 x9) ()
     else printf_unsynchronized ?banner frmt x1 x2 x3 x4 x5 x6 x7 x8 x9

  let print_exn ?v ?force ?banner ?(prefix="") ?suffix e =
   match suffix with
   | None        -> printf2 ?v ?force ?banner "%s%s\n"   prefix (Printexc.to_string e)
   | Some suffix -> printf3 ?v ?force ?banner "%s%s%s\n" prefix (Printexc.to_string e) suffix

  module Unprotected = struct

    let printf ?v ?(force=false) ?banner frmt =
      if force || (Tuning.is_log_enabled ?v ())
	then printf_unsynchronized ?banner frmt
	else Printf.ifprintf out_channel frmt (* do nothing (with type 'a) *)

    let print_exn ?v ?force ?banner ?(prefix="") ?suffix e =
    match suffix with
    | None        -> printf ?v ?force ?banner "%s%s\n"   prefix (Printexc.to_string e)
    | Some suffix -> printf ?v ?force ?banner "%s%s%s\n" prefix (Printexc.to_string e) suffix

  end (* Unprotected *)

end (* Make *)

module Make_simple (Tuning:sig val is_log_enabled : unit -> bool end) =
 Make
 (struct
     let verbosity = 1
     let debug_level () = if Tuning.is_log_enabled () then 1 else 0
     let log_channel     = `stderr
     let synchronized    = true
   end)


(** Wrappers providing a logged version of functions defined elsewhere. *)
module Extend_with_wrappers (Log : Result) = struct
include Log

type command = string

(** Run Unix.system with the given argument, and raise exception in case of failure;
    return unit on success. *)
let (*UnixExtra.*)system_or_fail ?(hide_output=false) ?(hide_errors=false) (command:command) =
  let suffix1 = if hide_output then " 1>/dev/null" else "" in
  let suffix2 = if hide_errors then " 2>/dev/null" else "" in
  let command = Printf.sprintf "%s%s%s" command suffix1 suffix2 in
  match Unix.system command with
  | Unix.WEXITED 0   -> ()
  | Unix.WEXITED n   -> failwith (Printf.sprintf "Unix.system: the process exited with %i" n)
  | Unix.WSIGNALED _
  | Unix.WSTOPPED _  -> failwith "Unix.system: the process was signaled or stopped"
;;


(** Wrapper for [UnixExtra.system_or_fail]: run system with the given argument,
    and raise exception in case of failure; return unit on success.
    Commands are automatically logged in debug mode. Furthermore, when debugging
    is not enable, a command redirection (/bin/sh compatible, i.e. 1>/dev/null
    2>/dev/null) is automatically appended to the command. In order to prevent
    this behaviour, the function provides the optional parameters ?hide_output
    and ?hide_errors: setting both these parameters to false, you ensure that
    nothing will be appended to the command (in debug mode or not). *)
let system_or_fail ?on_error ?hide_output ?hide_errors (command_line:string) =
  let extract_hide_decision h = match h with
  | None          -> not (Tuning.is_log_enabled ())
  | Some decision -> decision in
  let hide_output = extract_hide_decision hide_output in
  let hide_errors = extract_hide_decision hide_errors in
  let () = Log.printf1 "Executing: %s\n" command_line in
  try
    (*UnixExtra.*)system_or_fail ~hide_output ~hide_errors command_line
  with e ->
   begin
    (match on_error with
    | None         -> ()
    | Some command ->
        try (*UnixExtra.*)system_or_fail ~hide_output ~hide_errors command with _ -> ()
    );
    raise e
   end

(** Equivalent to [ignore (Unix.system command_line)] but with
    logging features. Notice that if the command_line terminates
    with '&' (background), no exceptions will be raised.
    Thus, using '&', there is no effect in setting [~force:true], because the
    shell well exit in any case. However, Log.system_or_ignore
    is preferable with respect to [(ignore (Unix.system command_line))]
    because it shows shell errors only in the debug mode. *)
let system_or_ignore ?on_error ?hide_output ?hide_errors command_line =
 try
  system_or_fail ?on_error ?hide_output ?hide_errors command_line
 with e ->
   begin
   let fmt = format_of_string "Ignoring exception: %s\n" in
   let msg = Printexc.to_string e in
   (match hide_errors with
    | None       -> Log.printf1 fmt msg
    | Some false -> Log.printf1 ~force:true fmt msg
    | Some true  -> ()
    )
    end

let print_backtrace () =
  Log.printf1
    "Backtrace:\n%s\n"
    (StringExtra.tab ~tab:2 (Printexc.get_backtrace ()))

end
