(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2026  Jean-Vincent Loddo
   Copyright (C) 2026  Université Sorbonne Paris Nord

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

(* Script mode: capture-then-close of the windows Marionnet opens by itself. The contract,
   the rationale and the thread discipline are documented in script_mode.mli. *)

(* --- *)
module Log = Marionnet_log

(* ---------------------------------------------------------------- *)
(*                          Configuration                           *)
(* ---------------------------------------------------------------- *)

(* Written once by marionnet.ml, before the GUI exists and before any thread is spawned;
   read from everywhere afterwards. No mutex is needed for these two. *)
let enabled_ref = ref false
let auto_dismiss_ms_ref = ref 2000

let configure ~(enabled:bool) ~(auto_dismiss_ms:int) : unit =
  enabled_ref := enabled;
  auto_dismiss_ms_ref := auto_dismiss_ms;
  if enabled then
    Log.printf1
      "Script_mode: enabled — self-opening windows will be captured then dismissed after %dms\n"
      auto_dismiss_ms

let enabled () : bool = !enabled_ref

(* How long a window stays visible before destroying itself. Not zero on purpose: the
   session is meant to stay *observable*, so a human (or a screenshot) still sees what
   happened; the script does not care, it reads the capture. *)
let auto_dismiss_ms () : int = !auto_dismiss_ms_ref

(* ---------------------------------------------------------------- *)
(*                          Captured messages                       *)
(* ---------------------------------------------------------------- *)

type severity = [ `Info | `Warning ]

(* One line of a recapitulative dialog: a summary always visible, a detail behind an
   expander (simple_dialogs.ml, [recapitulative]). *)
type item = {
  summary  : string;
  detail   : string;
  severity : severity;
}

type kind = [ `Info | `Warning | `Error | `Help | `Recap | `Question ]

type notification = {
  seq   : int;      (* monotonic, never reset, so that --since is meaningful across a clear *)
  time  : float;    (* Unix epoch *)
  kind  : kind;
  title : string;
  body  : string;
  items : item list;
}

let string_of_kind : kind -> string = function
  | `Info     -> "info"
  | `Warning  -> "warning"
  | `Error    -> "error"
  | `Help     -> "help"
  | `Recap    -> "recap"
  | `Question -> "question"

let string_of_severity : severity -> string = function
  | `Info    -> "info"
  | `Warning -> "warning"

(* A bounded buffer: this is an instrument, not a log file. A long session with a chatty
   component must not grow the heap, and a script that never reads is not a reason to keep
   everything. Most recent first. *)
let capacity = 200

let mutex   = Mutex.create ()
let counter = ref 0
let buffer  : notification list ref = ref []
let size    = ref 0

(* [keep n l] = the n first elements of l (fewer if l is shorter). *)
let rec keep n = function
  | x :: tl when n > 0 -> x :: (keep (n-1) tl)
  | _ -> []

let notify ~(kind:kind) ~(title:string) ?(items=[]) (body:string) : unit =
  let n =
    Mutex.protect mutex
      (fun () ->
         let () = incr counter in
         let n = { seq = !counter; time = Unix.gettimeofday (); kind; title; body; items } in
         let () = buffer := n :: !buffer in
         let () = incr size in
         let () =
           if !size > capacity then begin
             buffer := keep capacity !buffer;
             size := capacity
           end
         in
         n)
  in
  (* Journalled too: a driven session is debugged from the log when the client is gone. *)
  Log.printf3 "Script_mode: captured [%s] %s: %s\n"
    (string_of_kind n.kind) n.title
    (if n.body = "" then Printf.sprintf "(%d item(s))" (List.length n.items) else n.body)

(* Chronological order (oldest first), which is how a client wants to read them. *)
let notifications ?(since=0) () : notification list =
  Mutex.protect mutex
    (fun () -> List.rev (List.filter (fun n -> n.seq > since) !buffer))

(* [counter] is *not* reset: sequence numbers stay monotonic for the whole run, so a client
   holding a --since from before the clear is never served a message twice. *)
let clear () : unit =
  Mutex.protect mutex (fun () -> buffer := []; size := 0)

let last_seq () : int = Mutex.protect mutex (fun () -> !counter)

(* ---------------------------------------------------------------- *)
(*                    While a command is being served               *)
(* ---------------------------------------------------------------- *)

(* Questions are a different matter from information. Auto-answering them whenever script
   mode is on would silently defeat the confirmations a *human* asks for — and the human is
   still there, clicking, while the script runs: that is the very premise of architecture A.

   So the scope is not "script mode is on" but "*this* thread is serving a control-server
   command". A global in-flight flag would not do: [open] loads the whole project in the
   serving thread (control_server.ml, cmd_open) and takes seconds, during which a human
   click on "power off everything" would have lost its confirmation. A GUI callback fired
   by a click runs in the GTK main thread, which is never registered here, so the two cases
   cannot be confused.

   The guard is evaluated by the dialog functions *before* they delegate to the GTK main
   thread (simple_dialogs.ml, talking.ml), i.e. still in the caller's thread — which is what
   makes this test meaningful.

   A list rather than a set: at most 8 sessions, and re-entrancy (a command nested in a
   command) is handled by removing a single occurrence. *)
let commands_mutex = Mutex.create ()
let serving_threads : int list ref = ref []

(* Remove one occurrence of [x]. *)
let rec remove_one x = function
  | [] -> []
  | y :: tl -> if y = x then tl else y :: (remove_one x tl)

let in_command : 'a. (unit -> 'a) -> 'a = fun f ->
  let me = Thread.id (Thread.self ()) in
  let () = Mutex.protect commands_mutex (fun () -> serving_threads := me :: !serving_threads) in
  Fun.protect
    ~finally:(fun () ->
       Mutex.protect commands_mutex
         (fun () -> serving_threads := remove_one me !serving_threads))
    f

let in_command_now () : bool =
  let me = Thread.id (Thread.self ()) in
  Mutex.protect commands_mutex (fun () -> List.mem me !serving_threads)

(* True when a question must not be shown but answered by its caller-provided default. *)
let must_auto_answer () : bool = (enabled ()) && (in_command_now ())
