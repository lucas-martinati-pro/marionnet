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

(* Interface documentation is in lan_bridge_host.mli (single source). What follows
   are implementation notes only.
   ---
   This module is the twin of nat_bridge_host.ml, deliberately written on the same
   pattern (same JSON reading, same memo-and-at_exit discipline), and deliberately
   NOT factored with it: the two scripts have different sub-commands, different
   reports and different failure modes, and a common layer would have to be
   parameterised by all three. The similarity is worth reading side by side; it is
   not worth a functor. *)

(* --- *)
module Log = Marionnet_log
(* --- *)
module UnixExtra = Ocamlbricks.UnixExtra
(* --- *)

type t = {
  bridge     : string;
  interface  : string option;
  mac        : string option;
  gateway    : string option;
  addresses  : string list;
  owner_pid  : int;
  adopted    : bool;
}

type error = { code : string; message : string }

let string_of_error e = Printf.sprintf "%s: %s" e.code e.message

(* Installed in $PREFIX/share/marionnet/scripts/ and mirrored into $PREFIX/bin/
   by the Makefile, hence reachable by name -- exactly like marionnet-natbridge.sh.
   In the source tree, set MARIONNET_LANBRIDGE_SCRIPT. *)
let script () =
  try Sys.getenv "MARIONNET_LANBRIDGE_SCRIPT"
  with Not_found -> "marionnet-lanbridge.sh"

(* The owner pid must be OURS and must be passed explicitly. The script defaults
   it to $PPID, which under `UnixExtra.run' is the /bin/sh it was started from,
   not Marionnet: relying on that default would stamp the bridge alias with a
   process that dies immediately, and the `gc' of another instance would collect
   the bridge under our feet, taking the host's network with it. *)
let owner_pid = Unix.getpid ()

(* --- Running the auxiliary command
   ---
   The contract: stdout is exactly one JSON object, stderr is the human trace.
   They must therefore NOT be merged. stderr goes to the log, where it belongs:
   it is the list of privileged commands that were run on this host -- and for
   this script, that list is the record of what happened to the host's own card. *)

let json_of_output (output : string) : (Yojson.Safe.t, error) result =
  match Yojson.Safe.from_string output with
  | json -> Ok json
  | exception _ ->
      Error { code = "E_INTERNAL";
              message = Printf.sprintf "the report is not JSON: %s" (String.trim output) }

let log_stderr (path : string) : unit =
  try
    let text = UnixExtra.cat path in
    if String.trim text <> "" then Log.printf1 "Lan_bridge_host: %s\n" (String.trim text)
  with _ -> ()

let run_json (arguments : string list) : (Yojson.Safe.t, error) result =
  let stderr_path = Filename.temp_file "marionnet-lanbridge-" ".stderr" in
  let command =
    Printf.sprintf "%s %s 2>%s"
      (Filename.quote (script ()))
      (String.concat " " (List.map Filename.quote arguments))
      (Filename.quote stderr_path)
  in
  let (output, status) = UnixExtra.run command in
  let () = log_stderr stderr_path in
  let () = try Sys.remove stderr_path with _ -> () in
  match json_of_output output with
  | Error _ as failure ->
      (* No JSON at all: the command itself could not run (not installed, not
         executable). Its exit status is the only thing we know. *)
      (match status with
       | Unix.WEXITED 0 -> failure
       | _ ->
           Error { code = "E_INTERNAL";
                   message = Printf.sprintf "`%s' failed and produced no report" command })
  | Ok json -> Ok json

(* --- Reading the report *)

let member (key : string) (json : Yojson.Safe.t) : Yojson.Safe.t option =
  match json with `Assoc bindings -> List.assoc_opt key bindings | _ -> None

let string_member key json =
  match member key json with Some (`String s) -> Some s | _ -> None

let int_member key json =
  match member key json with Some (`Int n) -> Some n | _ -> None

let bool_member key json =
  match member key json with Some (`Bool b) -> Some b | _ -> None

let string_list_member key json =
  match member key json with
  | Some (`List items) ->
      List.filter_map (function `String s -> Some s | _ -> None) items
  | _ -> []

let is_ok json = (member "ok" json) = Some (`Bool true)

(* An unsuccessful report always carries `error' and `message'; the defaults are
   there so that a malformed report is still an error and never an exception. *)
let error_of_json json = {
  code    = (match string_member "error" json with Some c -> c | None -> "E_INTERNAL");
  message = (match string_member "message" json with
             | Some m -> m
             | None -> "the report says failure but carries no message");
}

(* The optional fields really are optional: `up' on a bridge it adopts reports
   whatever the host says about it, and a bridge with no card yet has neither
   interface nor gateway. Absent is a fact here, not a missing value. *)
let t_of_json json : (t, error) result =
  match string_member "bridge" json with
  | Some bridge ->
      Ok { bridge;
           interface = string_member "interface" json;
           mac       = string_member "mac"       json;
           gateway   = string_member "gateway"   json;
           addresses = string_list_member "addresses" json;
           owner_pid = (match int_member "owner_pid" json with Some p -> p | None -> owner_pid);
           adopted   = (match bool_member "adopted" json with Some b -> b | None -> false) }
  | None ->
      Error { code = "E_INTERNAL";
              message = "the report is a success but names no bridge" }

(* [call] factors the shape shared by every sub-command: run it, and let the
   report itself decide between success and failure -- the exit status is only a
   corroboration, the symbolic code is the contract. *)
let call (arguments : string list) : (Yojson.Safe.t, error) result =
  match run_json arguments with
  | Error _ as failure -> failure
  | Ok json -> if is_ok json then Ok json else Error (error_of_json json)

let owner_pid_arguments = ["--owner-pid"; string_of_int owner_pid]

let up ?interface () : (t, error) result =
  let interface_arguments = match interface with None -> [] | Some i -> ["--interface"; i] in
  match call (["up"] @ owner_pid_arguments @ interface_arguments) with
  | Error _ as failure -> failure
  | Ok json -> t_of_json json

(* A `down' that keeps the bridge because somebody else is still on it is a
   SUCCESS: the caller asked, and got a complete answer. Which of the two happened
   is the return value, because it is not a detail -- "the host is back" and "the
   host is still bridged, and here is who for" are different news, and the memo
   below depends on telling them apart. *)
let down ?(force = false) () : (bool, error) result =
  match call (["down"] @ owner_pid_arguments @ (if force then ["--force"] else [])) with
  | Error _ as failure -> failure
  | Ok json ->
      let removed = (bool_member "removed" json) = Some true in
      let () =
        if removed then Log.printf "Lan_bridge_host: the host card is back where it was\n"
        else
          match string_member "message" json with
          | Some message -> Log.printf1 "Lan_bridge_host: %s\n" message
          | None -> ()
      in
      Ok removed

(* --- Usability
   ---
   Unlike the NAT bridge, `status' is NOT a usable probe here: it reads the host
   with an unprivileged `ip' and succeeds whether or not block (c) is installed.
   The script therefore has a sub-command whose only job is to ask the question,
   by running a real command of ours that does nothing (`ip link del' on a bridge
   name we never create); see do_check_privileges in marionnet-lanbridge.sh. *)

let usable : bool option ref = ref None

let is_usable () =
  match !usable with
  | Some verdict -> verdict
  | None ->
      let verdict =
        match call ["check-privileges"] with
        | Ok json -> (bool_member "privileged" json) = Some true
        | Error _ -> false
      in
      usable := Some verdict;
      verdict

(* The memoisation above is right for a verdict that only an EXTERNAL event can
   change -- and there is exactly one such event: the sudoers block (c) being
   installed while we run (Privileges.ensure_lanbridge). *)
let forget_usability () = usable := None

(* --- The one bridge of this host, built at most once by this process
   ---
   One bridge per HOST, not per process (a card has one master), so a memo and not
   a table: what varies is only whether we built it or adopted it.
   ---
   The at_exit is registered only after the bridge really exists, and carries the
   same pid guard as Tap_provider's: at_exit also runs in the children forked by
   ocamlbricks' network servers, and without the guard closing an X11 relay would
   give the host its card back while the virtual machines are still running. It
   calls the plain `down', never `--force': another Marionnet may be on the bridge,
   and its virtual machines are not ours to disconnect. *)

let mutex = Mutex.create ()
let mine : t option ref = ref None
let at_exit_registered = ref false

let register_at_exit () =
  if not !at_exit_registered then begin
    at_exit_registered := true;
    at_exit (fun () ->
      if Unix.getpid () = owner_pid && !mine <> None then
        match down () with
        | Ok _ -> ()
        | Error e -> Log.printf1 "Lan_bridge_host: %s\n" (string_of_error e))
  end

let ensure ?interface () : (t, error) result =
  Mutex.lock mutex;
  let result =
    try
      match !mine with
      | Some bridge -> Ok bridge
      | None ->
          (match up ?interface () with
           | Error _ as failure -> failure
           | Ok bridge ->
               mine := Some bridge;
               register_at_exit ();
               Log.printf2 "Lan_bridge_host: %s is up on %s\n"
                 bridge.bridge
                 (match bridge.interface with Some i -> i | None -> "(no card)");
               Ok bridge)
    with e -> Mutex.unlock mutex; raise e
  in
  Mutex.unlock mutex;
  result

(* The counterpart of `ensure', called when a component stops -- what the at_exit
   does at exit time, but while the program goes on.
   ---
   The memo is forgotten only when the bridge was REALLY removed. Being shared,
   this bridge commonly survives a `down': another component of ours, or another
   Marionnet, still has a tap on it. Forgetting the memo then would be wrong twice
   over -- the at_exit would find nothing to give back, and the next `ensure'
   would run an `up' on a bridge we already hold.
   ---
   A `release' with nothing held is a no-op, and deliberately so: this bridge is
   the host's own card, and a `down' we never asked for could take somebody else's
   bridge down (`down' only counts LIVE tap owners: a bridge just built by another
   instance, with no tap attached yet, would be dismantled under it). *)
let release () : (unit, error) result =
  Mutex.lock mutex;
  let result =
    try
      match !mine with
      | None -> Ok ()
      | Some _ ->
          (match down () with
           | Ok removed ->
               let () = if removed then mine := None in
               Ok ()
           | Error e ->
               let () = Log.printf1 "Lan_bridge_host: %s\n" (string_of_error e) in
               (* Keeping the memo is what gives the at_exit a second chance. *)
               Error e)
    with e -> Mutex.unlock mutex; raise e
  in
  Mutex.unlock mutex;
  result

