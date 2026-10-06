(* This file is part of Marionnet, GPL-2.0-or-later.
   Copyright (C) 2026 Marionnet contributors. *)

module Log = Marionnet_log

let guard = Task_guard.create ()
let listener = ref (fun () -> ())
let active () = Task_guard.active guard
let notify () = GMain_actor.delegate (fun () -> !listener ()) ()
let on_change callback = listener := callback; notify ()
let execute ticket task =
  Task_guard.enter guard ticket;
  Fun.protect ~finally:(fun () -> Task_guard.release guard ticket; notify ()) task
let report label e =
  Log.printf2 "Background task %s failed: %s\n" label (Printexc.to_string e);
  Simple_dialogs.report_exception ~title:label ~message:label
    ~advice:(Gettext.s_ "error.advice.report") e ()

(** Start at most one worker per resource. Reserve before spawning, so even
    consecutive GTK events cannot schedule duplicates. Every exit releases it. *)
let start ~key ~label task =
  match Task_guard.reserve guard ~key ~label with
  | None -> None
  | Some ticket ->
      notify ();
      try Some (Thread.create (fun () ->
        try execute ticket task with e -> report label e) ())
      with e -> Task_guard.release guard ticket; notify (); raise e

(** Enqueue onto an existing runner, preserving its process dependency order. *)
let enqueue ~key ~label ~schedule task =
  match Task_guard.reserve guard ~key ~label with
  | None -> false
  | Some ticket ->
      notify ();
      (try schedule (fun () ->
         try execute ticket task with e -> report label e; raise e)
       with e -> Task_guard.release guard ticket; notify (); raise e);
      true

(** Nested project operations run synchronously in their owning worker. Other
    callers fail instead of modifying paths while another operation is active. *)
let run ~key ~label task =
  if Task_guard.owned guard key then task () else
  match Task_guard.reserve guard ~key ~label with
  | None -> failwith (Gettext.s_ "label.wait_please")
  | Some ticket -> notify (); execute ticket task
