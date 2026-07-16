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

(** The `sudo -n ip ...' replacement for marionnet-daemon. See tap_provider.mli. *)

(* --- *)
module Log = Marionnet_log
(* --- *)
module UnixExtra   = Ocamlbricks.UnixExtra
module StringExtra = Ocamlbricks.StringExtra
(* --- *)

type tap_name = string

let eth42_host_address = "172.23.0.254"
let tap_prefix = "mtap"

(* The daemon constrained the routed addresses to this prefix
   (daemon_language.ml:203-215); we keep the very same guard: *)
let ghost_network_prefix = "172.23."

(* The interface name must fit in IFNAMSIZ (16, final NUL included): *)
let max_tap_name_length = 15

(* Same candidate list as bin/scripts/marionnet-sudoers.sh, and for the same
   reason: sudoers matches on the absolute path, so the rule and the commands we
   run here must designate the same binary, whatever $PATH says. *)
let ip_binary_candidates = ["/usr/sbin/ip"; "/sbin/ip"; "/usr/bin/ip"; "/bin/ip"]
let ip_binary = lazy (List.find_opt Sys.file_exists ip_binary_candidates)

(* Installed in $PREFIX/bin/ by `make install-final-as-root' (as marionnet_telnet.sh
   is), hence reachable by name. In the source tree, set MARIONNET_SUDOERS_SCRIPT. *)
let sudoers_script () =
  try Sys.getenv "MARIONNET_SUDOERS_SCRIPT" with Not_found -> "marionnet-sudoers.sh"

(* --- Running commands *)

(* Run a command line capturing both channels: an error message is useless
   without the tool's own diagnostic. *)
let run (command : string) : (string, string) result =
  let (output, status) = UnixExtra.run (command ^ " 2>&1") in
  match status with
  | Unix.WEXITED 0 -> Ok output
  | _ ->
      let details = String.trim output in
      Error
        (if details = "" then Printf.sprintf "`%s' failed" command
         else Printf.sprintf "`%s' failed: %s" command details)

(* [ip_command args] runs `sudo -n ip args'. With [~privileged:false] the plain
   `ip args' is run instead (listing needs no privilege at all). *)
let ip_command ?(privileged=true) (args : string) : (string, string) result =
  match Lazy.force ip_binary with
  | None -> Error "iproute2 is not installed (no `ip' binary in the usual paths)"
  | Some ip ->
      run (Printf.sprintf "%s%s %s" (if privileged then "sudo -n " else "") ip args)

let user_name_of_uid (uid : int) : (string, string) result =
  try Ok (Unix.getpwuid uid).Unix.pw_name
  with Not_found -> Error (Printf.sprintf "no user name for uid %d" uid)

let current_user_name () : (string, string) result =
  user_name_of_uid (Unix.getuid ())

(* --- Naming and bookkeeping of our own taps *)

let mutex = Mutex.create ()
let next_sequence_number = ref 0
let my_taps : (tap_name, unit) Hashtbl.t = Hashtbl.create 51

let with_mutex f =
  Mutex.lock mutex;
  let result = (try f () with e -> Mutex.unlock mutex; raise e) in
  Mutex.unlock mutex;
  result

(* "mtap<pid>-<seq>": the embedded pid is what makes the garbage collection of
   section `purge_orphan_taps' exact, even with several Marionnet instances. *)
let fresh_tap_name () : tap_name =
  let sequence_number = with_mutex (fun () -> let n = !next_sequence_number in incr next_sequence_number; n) in
  Printf.sprintf "%s%d-%d" tap_prefix (Unix.getpid ()) sequence_number

let register_tap   tap = with_mutex (fun () -> Hashtbl.replace my_taps tap ())
let unregister_tap tap = with_mutex (fun () -> Hashtbl.remove  my_taps tap)
let is_mine        tap = with_mutex (fun () -> Hashtbl.mem     my_taps tap)
let my_tap_list   ()   = with_mutex (fun () -> Hashtbl.fold (fun tap () xs -> tap::xs) my_taps [])

(* Destroying the link destroys its address and its route with it. Unlike the
   daemon's `tunctl -d', which needed the obstinate retrying thread
   (marionnet_daemon.ml:148-193), `ip link del' on a tap nobody has open is
   immediate and reliable. *)
let delete_link (tap : tap_name) : (unit, string) result =
  match ip_command (Printf.sprintf "link del %s" tap) with
  | Ok _ -> Ok ()
  | Error e -> Error e

(* --- Creation *)

let make_eth42_tap ~(uid : int) ~(ip42 : string) : (tap_name, string) result =
  if not (StringExtra.is_prefix ghost_network_prefix ip42) then
    Error (Printf.sprintf "refusing to route %s: outside the %s0.0/16 ghost network" ip42 ghost_network_prefix)
  else
  match user_name_of_uid uid with
  | Error e -> Error e
  | Ok user ->
      let tap = fresh_tap_name () in
      if String.length tap > max_tap_name_length then
        Error (Printf.sprintf "generated interface name `%s' is too long" tap)
      else begin
        (* The daemon's contract, verbatim, in iproute2 syntax
           (marionnet_daemon.ml:124-133). The route needs the link up, hence the
           order: *)
        let steps = [
          Printf.sprintf "tuntap add dev %s mode tap user %s" tap user;
          Printf.sprintf "addr add %s/32 dev %s" eth42_host_address tap;
          Printf.sprintf "link set %s up" tap;
          Printf.sprintf "route add %s/32 dev %s" ip42 tap;
          ]
        in
        let rec perform = function
          | [] -> Ok ()
          | args :: rest ->
              (match ip_command args with
               | Ok _ -> perform rest
               | Error e -> Error e)
        in
        match perform steps with
        | Ok () ->
            register_tap tap;
            Log.printf2 "Tap_provider: the tap %s was created, routing %s\n" tap ip42;
            Ok tap
        | Error e ->
            (* Leave nothing half-built behind: *)
            let _ = delete_link tap in
            Log.printf2 "Tap_provider: failed to create a tap for %s: %s\n" ip42 e;
            Error e
      end

let make_bridge_tap ~(uid : int) ~(bridge : string) : (tap_name, string) result =
  match user_name_of_uid uid with
  | Error e -> Error e
  | Ok user ->
      let tap = fresh_tap_name () in
      if String.length tap > max_tap_name_length then
        Error (Printf.sprintf "generated interface name `%s' is too long" tap)
      else begin
        (* The daemon's contract, verbatim, in iproute2 syntax
           (marionnet_daemon.ml:136-146): promisc and up like its
           `ifconfig 0.0.0.0 promisc up', then attached to the bridge like its
           `brctl addif'. The bridge name comes from the configuration
           (MARIONNET_BRIDGE), hence the quoting: *)
        let steps = [
          Printf.sprintf "tuntap add dev %s mode tap user %s" tap user;
          Printf.sprintf "link set %s promisc on" tap;
          Printf.sprintf "link set %s up" tap;
          Printf.sprintf "link set %s master %s" tap (Filename.quote bridge);
          ]
        in
        let rec perform = function
          | [] -> Ok ()
          | args :: rest ->
              (match ip_command args with
               | Ok _ -> perform rest
               | Error e -> Error e)
        in
        match perform steps with
        | Ok () ->
            register_tap tap;
            Log.printf2 "Tap_provider: the tap %s was created, attached to the bridge %s\n" tap bridge;
            Ok tap
        | Error e ->
            (* Leave nothing half-built behind: *)
            let _ = delete_link tap in
            Log.printf2 "Tap_provider: failed to create a tap on the bridge %s: %s\n" bridge e;
            Error e
      end

(* --- Destruction *)

let destroy_tap (tap : tap_name) : unit =
  if not (is_mine tap) then
    Log.printf1 "Tap_provider: refusing to destroy %s: not a tap of this process\n" tap
  else begin
    (* Unregister in any case: a tap we failed to remove is not ours to retry
       forever, and it is inert (down or unused) anyway. *)
    unregister_tap tap;
    match delete_link tap with
    | Ok () -> Log.printf1 "Tap_provider: the tap %s was destroyed\n" tap
    | Error e -> Log.printf1 "Tap_provider: %s\n" e
  end

(* A crash of the GUI is caught by `purge_orphan_taps' at the next start-up; this
   is just the cheap first line of defence for the ordinary exits.
   --- The pid guard: at_exit also runs in the children forked by ocamlbricks'
   Network servers (the per-connection X11 relays of x.ml, network.ml
   `process_forking_loop'), which inherit my_taps by fork: without the guard,
   closing any X11 connection destroyed the tap of the still-running VM. Only
   the process that created the taps may destroy them. *)
let owner_pid = Unix.getpid ()

let () =
  at_exit (fun () ->
    if Unix.getpid () = owner_pid then List.iter destroy_tap (my_tap_list ()))

(* --- Garbage collection of the taps of dead processes *)

let our_tap_regexp = Str.regexp (Printf.sprintf "^%s\\([0-9]+\\)-[0-9]+$" tap_prefix)

(* Parse `ip -o link show' lines: "3: mtap1234-0: <NO-CARRIER,...> mtu 1500 ..."
   Returns the taps matching our naming scheme, with the pid that created them. *)
let existing_taps () : (tap_name * int) list =
  match ip_command ~privileged:false "-o link show" with
  | Error e ->
      Log.printf1 "Tap_provider: cannot list the network links: %s\n" e;
      []
  | Ok output ->
      let extract_tap line =
        match String.split_on_char ':' line with
        | _index :: name :: _ ->
            (* An interface may be displayed as "name@parent": *)
            let name = List.hd (String.split_on_char '@' (String.trim name)) in
            if Str.string_match our_tap_regexp name 0
              then Some (name, int_of_string (Str.matched_group 1 name))
              else None
        | _ -> None
      in
      List.filter_map extract_tap (String.split_on_char '\n' output)

let process_is_alive (pid : int) : bool =
  try Unix.kill pid 0; true with
  | Unix.Unix_error (Unix.ESRCH, _, _) -> false
  | Unix.Unix_error (Unix.EPERM, _, _) -> true   (* alive, just not ours *)
  | _ -> true                                    (* unclear: never purge on a doubt *)

let purge_orphan_taps () : int =
  let is_orphan (_, pid) = not (process_is_alive pid) in
  let orphans = List.filter is_orphan (existing_taps ()) in
  let purge count (tap, pid) =
    Log.printf2 "Tap_provider: purging %s, left over by the dead process %d\n" tap pid;
    match delete_link tap with
    | Ok () -> count + 1
    | Error e -> Log.printf1 "Tap_provider: %s\n" e; count
  in
  List.fold_left purge 0 orphans

(* --- The sudoers rule *)

let usable : bool option ref = ref None

(* Deleting a tap that does not exist is a successful no-op (`ip tuntap del'
   returns 0 and creates nothing), and it is covered by our sudoers rule: it is
   thus the exact question we want to ask -- "can I run our ip commands without a
   password" -- with no side effect at all. The name has no <pid>-<seq> shape, so
   it can never designate a real tap of ours.
   --- Two tempting probes that DON'T work: `sudo -n -l <command>' answers "is
   this allowed by SOME rule", not "without a password": on any ordinary desktop
   (%sudo ALL=(ALL:ALL) ALL) it says yes even with no rule of ours installed, and
   `sudo -n' then fails asking for a password. And reading /etc/sudoers.d/marionnet
   is impossible: it is 0440 root:root, as sudoers files must be. *)
let is_usable () : bool =
  match !usable with
  | Some verdict -> verdict
  | None ->
      let verdict =
        match ip_command (Printf.sprintf "tuntap del dev %sprobe mode tap" tap_prefix) with
        | Ok _ -> true
        | Error _ -> false
      in
      usable := Some verdict;
      verdict

let sudoers_rule ?user () : (string, string) result =
  match (match user with Some u -> Ok u | None -> current_user_name ()) with
  | Error e -> Error e
  | Ok user ->
      run (Printf.sprintf "%s print %s" (Filename.quote (sudoers_script ())) (Filename.quote user))

let ensure_sudoers_rule () : (unit, string) result =
  if is_usable () then Ok () else
  match current_user_name () with
  | Error e -> Error e
  | Ok user ->
      let command =
        Printf.sprintf "%s install %s" (Filename.quote (sudoers_script ())) (Filename.quote user)
      in
      (* Unix.system, not `run': the script re-executes itself with sudo, which
         may need to prompt for a password on the controlling terminal. *)
      let status = Unix.system command in
      usable := None;
      (match status with
       | Unix.WEXITED 0 when is_usable () -> Ok ()
       | Unix.WEXITED 0 ->
           Error (Printf.sprintf "`%s' reported success but sudo still refuses the tap commands" command)
       | _ -> Error (Printf.sprintf "`%s' failed" command))
