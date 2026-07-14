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
        dune exec bin/tap_provider_test.exe -- --live *)

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
       show "the tap" (Printf.sprintf "ip addr show dev %s" tap);
       show "the route" (Printf.sprintf "ip route get %s" ip42);
       (* --- *)
       printf "\n-- Destruction:\n";
       Tap_provider.destroy_tap tap;
       check "the tap is gone" (not (succeeds (Printf.sprintf "ip link show dev %s" tap)));
       check "its route is gone" (not (contains tap (output_of (Printf.sprintf "ip route get %s" ip42)))));
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

(* Installed Marionnet finds the script in $PATH; here dune has just copied it
   next to us (see the (deps ...) of the test stanza), so make it findable: *)
let () =
  let script = "scripts/marionnet-sudoers.sh" in
  if Sys.getenv_opt "MARIONNET_SUDOERS_SCRIPT" = None && Sys.file_exists script then
    Unix.putenv "MARIONNET_SUDOERS_SCRIPT" (Filename.concat (Sys.getcwd ()) script)

let () =
  let live = Array.exists (fun x -> x = "--live") Sys.argv in
  if live then live_run () else dry_run ();
  exit (if !failures = 0 then 0 else 1)
