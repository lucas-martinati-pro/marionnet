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

(* The privileged door that provides /dev/net/tun. Installed and named exactly
   like the one above, and overridable the same way in a source tree. *)
let tun_device_script () =
  try Sys.getenv "MARIONNET_TUN_DEVICE_SCRIPT" with Not_found -> "marionnet-tun-device.sh"

(* --- Running commands *)

(* Run a command line capturing both channels: an error message is useless
   without the tool's own diagnostic. *)
(* The command line a privileged probe is really given. The locale is FROZEN here,
   and it is not a detail of style: every diagnosis of this module is made by
   READING what sudo, ip and the doors write, and those write in the language of
   the session. Measured in a MarioNUM classroom (2026-09-06): sudo answered
   `sudo: il est necessaire de saisir un mot de passe', no English needle matched,
   and a refusal of the sudoers rule was reported to the user as `this machine
   does not provide /dev/net/tun' -- sending them to `docker run --device' while
   the true sentence was in hand. It is the rule this repository already imposes
   on its own benches (driven-sessions/README.md: a bench which matches a text
   freezes the language), owed here to the application itself.
   LANGUAGE is cleared as well: it OVERRIDES LC_ALL for gettext, so setting the
   latter alone leaves a French sudo French. Pure, and exposed for the test. *)
let privileged_command_line (command : string) : string =
  "LC_ALL=C LANGUAGE= " ^ command ^ " 2>&1"

let run (command : string) : (string, string) result =
  let (output, status) = UnixExtra.run (privileged_command_line command) in
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

(* --- Inspecting the taps present on the host: ours, and the other instances' *)

let our_tap_regexp = Str.regexp (Printf.sprintf "^%s\\([0-9]+\\)-[0-9]+$" tap_prefix)

(* The pid embedded in a tap name of our scheme ("mtap<pid>-<seq>"), if the name
   is one of ours at all. *)
let pid_of_tap_name (name : tap_name) : int option =
  if Str.string_match our_tap_regexp name 0
    then (try Some (int_of_string (Str.matched_group 1 name)) with _ -> None)
    else None

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
            (match pid_of_tap_name name with
             | Some pid -> Some (name, pid)
             | None     -> None)
        | _ -> None
      in
      List.filter_map extract_tap (String.split_on_char '\n' output)

let process_is_alive (pid : int) : bool =
  try Unix.kill pid 0; true with
  | Unix.Unix_error (Unix.ESRCH, _, _) -> false
  | Unix.Unix_error (Unix.EPERM, _, _) -> true   (* alive, just not ours *)
  | _ -> true                                    (* unclear: never purge on a doubt *)

(* See tap_provider.mli. Exposed, with the parsing it relies on, because it is
   the whole decision and the only part provable without creating interfaces
   (bin/tap_provider_test.ml). *)
let sessions_of_taps (taps : tap_name list) : (int * int) list =
  let mine = Unix.getpid () in
  let tally = Hashtbl.create 7 in
  let add tap =
    match pid_of_tap_name tap with
    | Some pid when pid <> mine && process_is_alive pid ->
        let previous = try Hashtbl.find tally pid with Not_found -> 0 in
        Hashtbl.replace tally pid (previous + 1)
    | _ -> ()
  in
  List.iter add taps;
  (* Sorted: a message about "the other sessions" must not depend on a hash order. *)
  List.sort compare (Hashtbl.fold (fun pid count xs -> (pid, count) :: xs) tally [])

let other_live_sessions () : (int * int) list =
  sessions_of_taps (List.map fst (existing_taps ()))

(* The device an `ip -o route show ADDRESS' output routes to, if any: the word
   following "dev" on the first line ("172.23.0.1 dev mtap42-0 scope link").
   Exposed for the test, for the same reason as above. *)
let route_device_of_output (output : string) : string option =
  let first_line = List.hd (String.split_on_char '\n' output) in
  let blank c = if c = '\t' then ' ' else c in
  let words =
    List.filter (fun w -> w <> "")
      (String.split_on_char ' ' (String.trim (String.map blank first_line)))
  in
  let rec search = function
    | "dev" :: device :: _ -> Some device
    | _ :: rest            -> search rest
    | []                   -> None
  in
  search words

let colliding_session_of_address (address : string) : (tap_name * int) option =
  match ip_command ~privileged:false (Printf.sprintf "-o route show %s/32" address) with
  | Error _ -> None
  | Ok output ->
      (match route_device_of_output output with
       | None -> None
       | Some device ->
           (match pid_of_tap_name device with
            | Some pid when pid <> Unix.getpid () && process_is_alive pid -> Some (device, pid)
            | _ -> None))

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

(* --- Garbage collection of the taps of dead processes (the inspection
       primitives it stands on live in the section above) *)

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

(* Why a CAUSE and not a boolean. The probe below answers one question -- "can I
   run our ip commands" -- and for a long time a `false' was reported to the user
   as "the sudoers rule is not installed", which is one of THREE reasons it can
   fail, and not the most frequent one in a classroom. Measured, in containers:

     the sudoers rule is missing   sudo: a password is required
     /dev/net/tun is missing       open: No such file or directory
     no CAP_NET_ADMIN              ioctl(TUNSETIFF): Operation not permitted

   Sending someone to run `marionnet-sudoers.sh install' when their container has
   no tun device wastes their time and hides the real defect (measured on a
   MarioNUM workstation: the rule was perfect, the device absent). *)
type unavailability =
  | No_tun_device        (* nothing at all can create a tap here *)
  | No_permission        (* the kernel refuses: no CAP_NET_ADMIN *)
  | No_sudoers_rule      (* sudo -n refuses the command *)
  | Unclear of string    (* anything else, in the tool's own words *)

let tun_device = "/dev/net/tun"

(* See tap_provider.mli. A pure function, exposed for the test: it is the only
   part of the diagnosis provable without a privilege and without a device, and
   the strings it classifies are the ones measured above, verbatim. *)
let unavailability_of_error (message : string) : unavailability =
  let contains needle =
    try ignore (Str.search_forward (Str.regexp_string needle) message 0); true
    with Not_found -> false
  in
  (* `open: No such file or directory' is what `ip tuntap' writes when the device
     node is missing, and it is looked for BEFORE the sudo signatures: a message
     such as `sudo: /usr/sbin/ip: command not found' also contains "sudo:", so the
     order is what keeps each needle in its own lane. Recognising it here as well
     as through Sys.file_exists is not redundancy for its own sake: the file test
     can pass and the command still fail (a mount namespace of its own, a device
     removed between the two), and the message must stay right. *)
  if contains "open: No such file or directory" then No_tun_device else
  if contains "TUNSETIFF" || contains "Operation not permitted" then No_permission else
  (* The needles are sudo's REFUSALS, not the word `sudo': `sudo: command not
     found' also contains it, and answering that with "install the sudoers rule"
     would be as wrong as the defect this type exists to fix. Anything else falls
     through to Unclear, which shows the words as they came. *)
  if contains "password is required" || contains "not allowed to execute"
     || contains "may not run" || contains "no tty present"
    then No_sudoers_rule
    else Unclear message

let verdict : unavailability option option ref = ref None

(* Deleting a tap that does not exist is a successful no-op (`ip tuntap del'
   returns 0 and creates nothing), and it is covered by our sudoers rule: it is
   thus the exact question we want to ask -- "can I run our ip commands without a
   password" -- with no side effect at all. The name has no <pid>-<seq> shape, so
   it can never designate a real tap of ours.
   --- Two tempting probes that DON'T work: `sudo -n -l <command>' answers "is
   this allowed by SOME rule", not "without a password": on any ordinary desktop
   (%sudo ALL=(ALL:ALL) ALL) it says yes even with no rule of ours installed, and
   `sudo -n' then fails asking for a password. And reading /etc/sudoers.d/marionnet
   is impossible: it is 0440 root:root, as sudoers files must be.
   --- The device is looked at FIRST, and then no command is run at all: it is
   exact, it costs nothing, and it still answers when sudo itself is broken. When
   it is missing, the sudoers rule is not merely innocent -- it was never even
   reached -- and the message says so. *)
let unavailability () : unavailability option =
  match !verdict with
  | Some cause -> cause
  | None ->
      let cause =
        if not (Sys.file_exists tun_device) then Some No_tun_device else
        match ip_command (Printf.sprintf "tuntap del dev %sprobe mode tap" tap_prefix) with
        | Ok _ -> None
        | Error message -> Some (unavailability_of_error message)
      in
      verdict := Some cause;
      cause

let is_usable () : bool = (unavailability () = None)

(* Provide the device node, then RE-MEASURE. See tap_provider.mli.

   Why the application and not the installation. /dev is volatile everywhere: a
   devtmpfs rebuilt at every boot on a machine of its own -- where udev puts the
   node back by itself, so this never runs -- and a FRESH tmpfs at every start
   inside a container, where nothing does. A node made once, while building an
   image or by a postinst, is therefore gone at the next start: the only gesture
   that lasts is the one repeated at each start of the application.

   Why through sudo. mknod(2) of a character device needs CAP_MKNOD, which a plain
   account does not have even inside a container whose bounding set contains it.
   So this asks the same way everything else here does, and the door it calls is
   granted by the socle (block a) of marionnet-sudoers.sh.

   Why the exit status of the door is NOT the answer. Creating the node does not
   prove a tap can be made: opening it may still be refused by a container's
   device cgroup, and TUNSETIFF still needs CAP_NET_ADMIN. So the verdict cache is
   dropped and the real question asked again -- what is returned is what is STILL
   wrong, [None] meaning the taps work now.

   The caller is expected to have found [Some No_tun_device] first: nothing else
   is repaired by a mknod, and a machine whose node is already there must not pay
   a sudo call to be told so. *)
(* What to report once the privileged door has FAILED, given what the machine
   still says ([remaining], measured again -- the door's exit status is not the
   answer, see below). Pure, and exposed for the test.

   The door's own failure is classified by the function that classifies every
   other one. A sudo REFUSAL is the interesting case, and it is not "no device":
   it means this account was granted the socle before this door existed, so the
   remedy is to run marionnet-sudoers.sh install again -- which is exactly what
   the No_sudoers_rule message already says.

   And when the classification recognises NOTHING, the door's words are what is
   reported, instead of the state of the machine. Measured in a classroom
   (2026-09-06): the door was refused by sudo, the refusal was not recognised,
   and the user was told `this machine does not provide /dev/net/tun' -- true
   about the machine, and false about what had just happened. A cause we cannot
   name is not a cause we may replace by a comfortable one: we show the words. *)
let door_verdict ~(message : string) ~(remaining : unavailability option)
  : unavailability option =
  match unavailability_of_error message with
  | No_sudoers_rule -> Some No_sudoers_rule
  | _ ->
      (match remaining with
       | Some No_tun_device when String.trim message <> "" -> Some (Unclear message)
       | other -> other)

let ensure_tun_device () : unavailability option =
  let command = Printf.sprintf "sudo -n %s create" (Filename.quote (tun_device_script ())) in
  match run command with
  | Ok _ -> verdict := None; unavailability ()
  | Error message ->
      verdict := None;
      door_verdict ~message ~remaining:(unavailability ())

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
      verdict := None;
      (match status with
       | Unix.WEXITED 0 when is_usable () -> Ok ()
       | Unix.WEXITED 0 ->
           Error (Printf.sprintf "`%s' reported success but sudo still refuses the tap commands" command)
       | _ -> Error (Printf.sprintf "`%s' failed" command))
