(* This file is part of Marionnet, GPL-2.0-or-later.
   Copyright (C) 2026 Marionnet contributors. *)

type ticket = { key : string; label : string; mutable owner : int option }
type t = { mutex : Mutex.t; tickets : (string, ticket) Hashtbl.t }
let create () = { mutex = Mutex.create (); tickets = Hashtbl.create 8 }
let locked t f =
  Mutex.lock t.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.mutex) f
let reserve t ~key ~label = locked t (fun () ->
  if Hashtbl.mem t.tickets key then None else
  let ticket = { key; label; owner = None } in
  Hashtbl.add t.tickets key ticket; Some ticket)
let enter t ticket = locked t (fun () -> ticket.owner <- Some (Thread.id (Thread.self ())))
let owned t key = locked t (fun () ->
  match Hashtbl.find_opt t.tickets key with
  | Some ticket -> ticket.owner = Some (Thread.id (Thread.self ()))
  | None -> false)
let release t ticket = locked t (fun () ->
  match Hashtbl.find_opt t.tickets ticket.key with
  | Some current when current == ticket -> Hashtbl.remove t.tickets ticket.key
  | _ -> ())
let active t = locked t (fun () ->
  Hashtbl.fold (fun _ ticket labels -> (ticket.key, ticket.label) :: labels) t.tickets [])
