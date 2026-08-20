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

(** Driver proving Tap_provider without the GUI and without a guest image.

    Without argument (this is what `dune test' runs) it is READ-ONLY: it shows
    the sudoers rule, whether sudo accepts it, and the taps currently around.

    With --live it really builds a tap and checks, against the kernel, that the
    daemon's network contract is reproduced (address, link state, host-specific
    route), that destruction leaves nothing behind, and that the orphan collector
    only takes the taps of dead processes. This needs the sudoers rule:
      marionnet-sudoers.sh install $(id -un)
    Usage in the source tree:
      MARIONNET_SUDOERS_SCRIPT=bin/scripts/marionnet-sudoers.sh \
        dune exec bin/tap_provider_test.exe -- --live

    With --live-collision=ADDRESS it proves what happens when ANOTHER session already
    routes ADDRESS: the collision is recognised and named, and no tap is created. The
    caller must have fabricated the foreign side first, which the scoped sudoers rule
    allows without a password:
      sleep 900 & pid=$!
      sudo ip tuntap add dev mtap$pid-0 mode tap user $(id -un)
      sudo ip link set mtap$pid-0 up
      sudo ip route add 172.23.0.42/32 dev mtap$pid-0
      dune exec bin/tap_provider_test.exe -- --live-collision=172.23.0.42
      sudo ip link del mtap$pid-0 ; kill $pid

    With --live-bridge=NAME it proves the world_bridge contract the same way
    (tap promisc, up, attached to the bridge NAME, destruction). NAME must be a
    PREEXISTING bridge: creating it is the admin's business, outside the scoped
    sudoers rule. A disposable one:
      sudo ip link add name mnbrtest type bridge     # and afterwards:
      sudo ip link del mnbrtest *)

let printf = Printf.printf

let failures = ref 0

(* Report and count, so that the exit code means something: *)
let check (description : string) (verdict : bool) : unit =
  if verdict then printf "  [ OK ] %s\n%!" description
  else begin incr failures; printf "  [FAIL] %s\n%!" description end

let show (title : string) (command : string) : unit =
  printf "\n--- %s: `%s'\n%!" title command;
  ignore (Sys.command command)

let succeeds (command : string) : bool =
  Sys.command (Printf.sprintf "%s >/dev/null 2>&1" command) = 0

let output_of (command : string) : string =
  fst (Ocamlbricks.UnixExtra.run (command ^ " 2>/dev/null"))

let contains (needle : string) (haystack : string) : bool =
  try ignore (Str.search_forward (Str.regexp_string needle) haystack 0); true
  with Not_found -> false

(* A pid that is certainly dead: a child we spawned and already reaped. *)
let dead_pid () : int =
  let pid = Unix.create_process "/bin/true" [| "/bin/true" |] Unix.stdin Unix.stdout Unix.stderr in
  ignore (Unix.waitpid [] pid);
  pid

(* --- *)

let dry_run () =
  printf "== Tap_provider, dry run: nothing is created, nothing is destroyed.\n\n";
  printf "  tap prefix .............. %s\n" Tap_provider.tap_prefix;
  printf "  eth42 host address ...... %s\n" Tap_provider.eth42_host_address;
  printf "  sudoers rule installed .. %b\n" (Tap_provider.is_usable ());
  printf "\n--- Expected sudoers rule:\n\n";
  (match Tap_provider.sudoers_rule () with
   | Ok text -> print_string text
   | Error e -> printf "  UNAVAILABLE: %s\n" e);
  show "Marionnet taps currently on this host" "ip -o link show | grep -E 'mtap[0-9]+-' || echo '  (none)'";
  (* --- *)
  printf "\n-- Other Marionnet sessions running right now:\n";
  (match Tap_provider.other_live_sessions () with
   | [] -> printf "  (none)\n"
   | sessions ->
       List.iter (fun (pid, taps) -> printf "  process %d, taps: %d\n" pid taps) sessions);
  (* --- *)
  (* The decision behind the detection, proved WITHOUT creating a single interface: creating one
     needs a privilege this test does not have, so the interface names are fabricated here. The
     live foreign process is our own parent -- certainly alive, certainly not us, nothing to clean
     up afterwards. *)
  printf "\n-- The decision, on fabricated interface names:\n";
  let alien = Unix.getppid () in
  let deceased = dead_pid () in
  let tap_of pid seq = Printf.sprintf "%s%d-%d" Tap_provider.tap_prefix pid seq in
  let mine = Unix.getpid () in
  check "nothing is reported when no tap is around"
    (Tap_provider.sessions_of_taps [] = []);
  check "a live foreign process is reported once, with its number of taps"
    (Tap_provider.sessions_of_taps
       [ tap_of alien 0; "eth0"; tap_of deceased 0; tap_of mine 0; tap_of alien 3;
         "mtapfoo-1"; Printf.sprintf "%s%d" Tap_provider.tap_prefix alien ]
     = [ (alien, 2) ]);
  check "the taps of a dead process are not a session"
    (Tap_provider.sessions_of_taps [ tap_of deceased 0; tap_of deceased 1 ] = []);
  check "our own taps are not another session"
    (Tap_provider.sessions_of_taps [ tap_of mine 0 ] = []);
  (* --- *)
  printf "\n-- Reading a route back to its tap:\n";
  check "the device of a route line is found"
    (Tap_provider.route_device_of_output "172.23.0.42 dev mtap4242-0 scope link \\"
     = Some "mtap4242-0");
  check "an empty output routes nowhere"
    (Tap_provider.route_device_of_output "" = None);
  check "a route without a device routes nowhere"
    (Tap_provider.route_device_of_output "unreachable 172.23.0.42" = None);
  (* --- *)
  printf "\n== %s\n" (if !failures = 0 then "All checks passed." else Printf.sprintf "%d CHECK(S) FAILED." !failures);
  printf "\nRun with --live to actually exercise the tap creation.\n"

let live_run () =
  let uid = Unix.getuid () in
  let ip42 = "172.23.0.42" in
  printf "== Tap_provider, live run (uid=%d, ip42=%s)\n\n" uid ip42;
  (* --- *)
  printf "-- The ghost network guard:\n";
  check "an address outside 172.23. is refused"
    (match Tap_provider.make_eth42_tap ~uid ~ip42:"10.0.0.1" with Error _ -> true | Ok _ -> false);
  (* --- *)
  printf "\n-- Creation:\n";
  (match Tap_provider.make_eth42_tap ~uid ~ip42 with
   | Error e -> incr failures; printf "  [FAIL] tap creation: %s\n" e
   | Ok tap ->
       check "the tap exists" (succeeds (Printf.sprintf "ip link show dev %s" tap));
       let addresses = output_of (Printf.sprintf "ip -o addr show dev %s" tap) in
       let route = output_of (Printf.sprintf "ip route get %s" ip42) in
       check (Printf.sprintf "it carries %s/32" Tap_provider.eth42_host_address)
         (contains (Tap_provider.eth42_host_address ^ "/32") addresses);
       check "it is up" (contains "state UP" (output_of (Printf.sprintf "ip -o link show dev %s" tap))
                         || contains ",UP" (output_of (Printf.sprintf "ip -o link show dev %s" tap)));
       check (Printf.sprintf "%s is routed through it" ip42) (contains tap route);
       check "the collision probe does not accuse ourselves"
         (Tap_provider.colliding_session_of_address ip42 = None);
       show "the tap" (Printf.sprintf "ip addr show dev %s" tap);
       show "the route" (Printf.sprintf "ip route get %s" ip42);
       (* --- *)
       printf "\n-- Destruction:\n";
       Tap_provider.destroy_tap tap;
       check "the tap is gone" (not (succeeds (Printf.sprintf "ip link show dev %s" tap)));
       check "its route is gone" (not (contains tap (output_of (Printf.sprintf "ip route get %s" ip42)))));
  (* --- *)
  printf "\n-- Exit of a forked child (as the per-connection X11 relays of x.ml):\n";
  (match Tap_provider.make_eth42_tap ~uid ~ip42 with
   | Error e -> incr failures; printf "  [FAIL] cannot create the witness tap: %s\n" e
   | Ok tap ->
       flush stdout;
       (match Unix.fork () with
        | 0 -> exit 0   (* runs the inherited at_exit handlers, as network.ml's children do *)
        | child -> ignore (Unix.waitpid [] child));
       check "the tap survives the exit of a forked child"
         (succeeds (Printf.sprintf "ip link show dev %s" tap));
       Tap_provider.destroy_tap tap;
       check "the tap is gone after the normal destruction"
         (not (succeeds (Printf.sprintf "ip link show dev %s" tap))));
  (* --- *)
  printf "\n-- The orphan collector:\n";
  (match Tap_provider.make_eth42_tap ~uid ~ip42 with
   | Error e -> incr failures; printf "  [FAIL] cannot create the witness tap: %s\n" e
   | Ok mine ->
       let orphan = Printf.sprintf "%s%d-0" Tap_provider.tap_prefix (dead_pid ()) in
       let user = (Unix.getpwuid uid).Unix.pw_name in
       let created =
         succeeds (Printf.sprintf "sudo -n ip tuntap add dev %s mode tap user %s" orphan user)
       in
       check "a tap of a dead process could be forged" created;
       let purged = Tap_provider.purge_orphan_taps () in
       printf "  purge_orphan_taps () = %d\n" purged;
       check "the orphan was collected" (not (succeeds (Printf.sprintf "ip link show dev %s" orphan)));
       check "our own live tap was spared" (succeeds (Printf.sprintf "ip link show dev %s" mine));
       Tap_provider.destroy_tap mine);
  (* --- *)
  printf "\n== %s\n" (if !failures = 0 then "All checks passed." else Printf.sprintf "%d CHECK(S) FAILED." !failures)

(* Two simultaneous sessions number their machines from scratch and hand them addresses from
   the same range: the second one to start finds its address already routed to a tap of the
   first. This is what episode 9 of `marionnet-todo-transverse' makes visible. *)
let live_collision_run (ip42 : string) =
  printf "== Tap_provider, collision run (ip42=%s)\n\n" ip42;
  match Tap_provider.colliding_session_of_address ip42 with
  | None ->
      incr failures;
      printf "  [FAIL] no other live session routes %s: fabricate one first (see the header of this file)\n" ip42
  | Some (foreign_tap, foreign_pid) ->
      printf "  %s is routed to %s, owned by the process %d\n\n" ip42 foreign_tap foreign_pid;
      check "the colliding tap belongs to another process" (foreign_pid <> Unix.getpid ());
      check "that process is listed among the other live sessions"
        (List.mem_assoc foreign_pid (Tap_provider.other_live_sessions ()));
      (match Tap_provider.make_eth42_tap ~uid:(Unix.getuid ()) ~ip42 with
       | Ok tap ->
           incr failures;
           printf "  [FAIL] a tap was created although %s is already routed elsewhere\n" ip42;
           Tap_provider.destroy_tap tap
       | Error e ->
           check "no tap is created for an address another session already routes" true;
           printf "  the failure reads: %s\n" e);
      check "the foreign tap is left untouched"
        (succeeds (Printf.sprintf "ip link show dev %s" foreign_tap));
      check "our own failed attempt left nothing behind"
        (not (contains (Printf.sprintf "%s%d-" Tap_provider.tap_prefix (Unix.getpid ()))
                (output_of "ip -o link show")));
      printf "\n== %s\n" (if !failures = 0 then "All checks passed." else Printf.sprintf "%d CHECK(S) FAILED." !failures)

let live_bridge_run (bridge : string) =
  let uid = Unix.getuid () in
  printf "== Tap_provider, live bridge run (uid=%d, bridge=%s)\n\n" uid bridge;
  if not (succeeds (Printf.sprintf "ip link show dev %s" bridge)) then begin
    incr failures;
    printf "  [FAIL] the bridge %s does not exist; create it first (see the header of this file)\n" bridge
  end else
  match Tap_provider.make_bridge_tap ~uid ~bridge with
  | Error e -> incr failures; printf "  [FAIL] bridge tap creation: %s\n" e
  | Ok tap ->
      let link = output_of (Printf.sprintf "ip -o link show dev %s" tap) in
      check "the tap exists" (succeeds (Printf.sprintf "ip link show dev %s" tap));
      check "it is promisc" (contains "PROMISC" link);
      check "it is up" (contains "state UP" link || contains ",UP" link);
      check (Printf.sprintf "it is attached to the bridge %s" bridge)
        (contains (Printf.sprintf "master %s" bridge) link);
      show "the tap" (Printf.sprintf "ip link show dev %s" tap);
      (* --- *)
      printf "\n-- Destruction:\n";
      Tap_provider.destroy_tap tap;
      check "the tap is gone" (not (succeeds (Printf.sprintf "ip link show dev %s" tap)));
      check "the bridge is left intact" (succeeds (Printf.sprintf "ip link show dev %s" bridge));
      (* --- *)
      printf "\n== %s\n" (if !failures = 0 then "All checks passed." else Printf.sprintf "%d CHECK(S) FAILED." !failures)

(* Installed Marionnet finds the script in $PATH; here dune has just copied it
   next to us (see the (deps ...) of the test stanza), so make it findable: *)
let () =
  let script = "scripts/marionnet-sudoers.sh" in
  if Sys.getenv_opt "MARIONNET_SUDOERS_SCRIPT" = None && Sys.file_exists script then
    Unix.putenv "MARIONNET_SUDOERS_SCRIPT" (Filename.concat (Sys.getcwd ()) script)

let () =
  let live = Array.exists (fun x -> x = "--live") Sys.argv in
  let live_bridge =
    Array.fold_left
      (fun acc x ->
        if Ocamlbricks.StringExtra.is_prefix "--live-bridge=" x
          then Some (String.sub x 14 (String.length x - 14))
          else acc)
      None Sys.argv
  in
  let live_collision =
    Array.fold_left
      (fun acc x ->
        if Ocamlbricks.StringExtra.is_prefix "--live-collision=" x
          then Some (String.sub x 17 (String.length x - 17))
          else acc)
      None Sys.argv
  in
  (match live, live_bridge, live_collision with
   | _, _, Some address -> live_collision_run address
   | _, Some bridge, None -> (if live then live_run ()); live_bridge_run bridge
   | true, None, None -> live_run ()
   | false, None, None -> dry_run ());
  exit (if !failures = 0 then 0 else 1)
