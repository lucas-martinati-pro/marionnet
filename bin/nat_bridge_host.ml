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

(* Interface documentation is in nat_bridge_host.mli (single source). What follows
   are implementation notes only. *)

(* --- *)
module Log = Marionnet_log
(* --- *)
module UnixExtra = Ocamlbricks.UnixExtra
(* --- *)

type t = {
  bridge       : string;
  subnet       : string;
  host_address : string;
  gateway      : string;
  guest_range  : string;
  owner_pid    : int;
  instance     : int option;
}

type error = { code : string; message : string }

let string_of_error e = Printf.sprintf "%s: %s" e.code e.message

(* Installed in $PREFIX/share/marionnet/scripts/ and mirrored into $PREFIX/bin/
   by the Makefile, hence reachable by name -- exactly like marionnet-sudoers.sh
   (Tap_provider.sudoers_script). In the source tree, set MARIONNET_NATBRIDGE_SCRIPT. *)
let script () =
  try Sys.getenv "MARIONNET_NATBRIDGE_SCRIPT"
  with Not_found -> "marionnet-natbridge.sh"

(* The owner pid must be OURS and must be passed explicitly. The script defaults
   it to $PPID, which under `UnixExtra.run' is the /bin/sh it was started from,
   not Marionnet: relying on that default would name the bridge after a process
   that dies immediately, and `gc' would collect it under our feet. *)
let owner_pid = Unix.getpid ()

(* --- Running the auxiliary command
   ---
   The contract: stdout is exactly one JSON object, stderr is the human trace.
   They must therefore NOT be merged (Tap_provider.run merges them, because there
   the whole output IS the diagnostic). stderr goes to the log, where it belongs:
   it is the list of privileged commands that were run on this host. *)

let json_of_output (output : string) : (Yojson.Safe.t, error) result =
  match Yojson.Safe.from_string output with
  | json -> Ok json
  | exception _ ->
      Error { code = "E_INTERNAL";
              message = Printf.sprintf "the report is not JSON: %s" (String.trim output) }

let log_stderr (path : string) : unit =
  try
    let text = UnixExtra.cat path in
    if String.trim text <> "" then Log.printf1 "Nat_bridge_host: %s\n" (String.trim text)
  with _ -> ()

let run_json (arguments : string list) : (Yojson.Safe.t, error) result =
  let stderr_path = Filename.temp_file "marionnet-natbridge-" ".stderr" in
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

let is_ok json = (member "ok" json) = Some (`Bool true)

(* An unsuccessful report always carries `error' and `message'; the defaults are
   there so that a malformed report is still an error and never an exception. *)
let error_of_json json = {
  code    = (match string_member "error" json with Some c -> c | None -> "E_INTERNAL");
  message = (match string_member "message" json with
             | Some m -> m
             | None -> "the report says failure but carries no message");
}

let t_of_json json : (t, error) result =
  match string_member "bridge" json, string_member "subnet" json with
  | Some bridge, Some subnet ->
      let field key default = match string_member key json with Some v -> v | None -> default in
      Ok { bridge;
           subnet;
           host_address = field "host_address" (subnet ^ ".1");
           gateway      = field "gateway"      (subnet ^ ".1");
           guest_range  = field "guest_range"  (subnet ^ ".2-" ^ subnet ^ ".254");
           owner_pid    = (match int_member "owner_pid" json with Some p -> p | None -> owner_pid);
           (* The script publishes `instance' only when it was given one, so the
              absent field IS the unsuffixed name -- not a missing value. *)
           instance     = int_member "instance" json }
  | _ ->
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

(* Absent option, absent argument: the script then uses the unsuffixed name, so
   a caller that knows nothing of instances behaves exactly as it did before. *)
let instance_arguments = function
  | None -> []
  | Some n -> ["--instance"; string_of_int n]

let up ?subnet ?(dhcp=false) ?ipv6 ?(radvd=false) ?instance () : (t, error) result =
  let subnet_arguments = match subnet with None -> [] | Some s -> ["--subnet"; s] in
  (* Off unless asked for, here: the default belongs to the model (the component
     decides, see nat_bridge.ml), not to this thin caller. *)
  let dhcp_arguments = if dhcp then ["--dhcp"] else [] in
  (* `--radvd' without `--ipv6' is a usage error for the script, and rightly so:
     there is no prefix to advertise. We do not even build that argv. *)
  let ipv6_arguments = match ipv6 with
    | None -> []
    | Some address -> ["--ipv6"; address] @ (if radvd then ["--radvd"] else [])
  in
  match call (["up"] @ owner_pid_arguments @ (instance_arguments instance)
              @ subnet_arguments @ dhcp_arguments @ ipv6_arguments) with
  | Error _ as failure -> failure
  | Ok json -> t_of_json json

let down ?instance () : (unit, error) result =
  match call (["down"] @ owner_pid_arguments @ (instance_arguments instance)) with
  | Error _ as failure -> failure
  | Ok _ -> Ok ()

let gc () : (unit, error) result =
  match call ["gc"] with Error _ as failure -> failure | Ok _ -> Ok ()

let status () : (t list, error) result =
  match call ["status"] with
  | Error _ as failure -> failure
  | Ok json ->
      (match member "bridges" json with
       | Some (`List entries) ->
           Ok (List.filter_map (fun entry -> Result.to_option (t_of_json entry)) entries)
       | _ -> Ok [])

(* --- IPv6 (episode 11)
   ---
   Deliberately NOT memoised, unlike `is_usable' below: this answer changes
   without Marionnet doing anything at all -- a Wi-Fi association, a phone
   tethered by USB, a VPN going up or down. The dialog therefore asks again every
   time it opens; it costs one fork, and it is what keeps its three greyed-out
   fields honest.
   ---
   A script that cannot be run answers `false'. That is the safe direction: the
   only harmful answer here is offering an IPv6 that cannot work. *)
let has_ipv6_uplink () : bool =
  match call ["check-ipv6"] with
  | Error _ -> false
  | Ok json -> (member "uplink" json) = Some (`Bool true)

(* --- Usability
   ---
   `status' was used for this until the bug of 2026-09-02, and it was the wrong
   question -- more wrongly than the comment it replaces admitted. That comment
   claimed status exercised the sudo path (`it runs iptables-save'); MEASURED
   (`bash -x marionnet-natbridge.sh status' contains not one `sudo'), do_status
   asks the host NOTHING privileged: it reads /proc and lists bridges with an
   unprivileged `ip'. It therefore answered "usable" on every machine, block (b)
   installed or not -- so Privileges.ensure_natbridge returned Ok WITHOUT ever
   offering the password (privileges.ml: the probe is what it short-circuits
   on), and the refusal surfaced at `up', when nobody was left to ask. A probe
   must exercise what it guards.
   ---
   `check-privileges' asks exactly that, the way lan_bridge_host.ml already did
   (do_check_privileges in the script: a real command of our own list, on a
   bridge name no run can produce, with no effect on anything). Memoised for the
   same reason as before. *)

let usable : bool option ref = ref None

let is_usable () =
  match !usable with
  | Some verdict -> verdict
  | None ->
      let verdict =
        match call ["check-privileges"] with
        | Ok json -> (member "privileged" json) = Some (`Bool true)
        | Error _ -> false
      in
      usable := Some verdict;
      verdict

(* The memoisation above is right for a verdict that only an EXTERNAL event can
   change -- and there is exactly one such event: the sudoers block (b) being
   installed while we run (Privileges.ensure_natbridge). Same idiom as
   Tap_provider.ensure_sudoers_rule, which resets its own cache in place. *)
let forget_usability () = usable := None

(* --- The bridges of this process, each created at most once
   ---
   One bridge per component asking for one, hence a table rather than the single
   memo of episode 3: the key is the instance argument itself, `None' being the
   unsuffixed name. Allocating those numbers is the caller's business.
   ---
   The at_exit is registered only after a bridge really exists, and carries the
   same pid guard as Tap_provider's: at_exit also runs in the children forked by
   ocamlbricks' network servers, and without the guard closing an X11 relay would
   tear down the bridges of the still-running VMs. It takes down EVERY bridge of
   the table: forgetting one would leave a bridge and its NAT rules behind, for
   the `gc' of a later run to collect. *)

let mutex = Mutex.create ()
let mine : (int option, t) Hashtbl.t = Hashtbl.create 4
let at_exit_registered = ref false

let register_at_exit () =
  if not !at_exit_registered then begin
    at_exit_registered := true;
    at_exit (fun () ->
      if Unix.getpid () = owner_pid then
        Hashtbl.iter
          (fun instance bridge ->
             match down ?instance () with
             | Ok () -> Log.printf1 "Nat_bridge_host: %s was removed\n" bridge.bridge
             | Error e -> Log.printf1 "Nat_bridge_host: %s\n" (string_of_error e))
          mine)
  end

let ensure ?subnet ?dhcp ?ipv6 ?radvd ?instance () : (t, error) result =
  Mutex.lock mutex;
  let result =
    try
      match Hashtbl.find_opt mine instance with
      | Some bridge -> Ok bridge
      | None ->
          (match up ?subnet ?dhcp ?ipv6 ?radvd ?instance () with
           | Error _ as failure -> failure
           | Ok bridge ->
               Hashtbl.replace mine instance bridge;
               register_at_exit ();
               Log.printf2 "Nat_bridge_host: %s is up on %s.0/24\n" bridge.bridge bridge.subnet;
               Ok bridge)
    with e -> Mutex.unlock mutex; raise e
  in
  Mutex.unlock mutex;
  result

(* The counterpart of `ensure', called when a component stops -- what the at_exit
   does for everything still held at exit time, but for one bridge, while the
   program goes on.
   ---
   The entry leaves the table even when the removal failed: keeping it would make
   the next `ensure' hand back a bridge that is no longer there, which is a worse
   lie than the leftover itself. And a leftover is not lost: every artefact is
   tagged with its bridge name, so the `gc' of a later run collects it. *)
let release ?instance () : (unit, error) result =
  Mutex.lock mutex;
  let result =
    try
      let outcome = down ?instance () in
      let () = Hashtbl.remove mine instance in
      let () =
        match outcome with
        | Ok () ->
            Log.printf1 "Nat_bridge_host: instance %s was released\n"
              (match instance with None -> "(unsuffixed)" | Some n -> string_of_int n)
        | Error e -> Log.printf1 "Nat_bridge_host: %s\n" (string_of_error e)
      in
      outcome
    with e -> Mutex.unlock mutex; raise e
  in
  Mutex.unlock mutex;
  result
