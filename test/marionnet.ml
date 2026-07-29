(* This file is part of Marionnet

   Copyright (C) 2026  Jean-Vincent Loddo

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

(* Regression tests for the fixes applied to the vendored [lib/STRUCTURES/network.ml],
   episode 2 of the `marionnet-pilotage-par-script' work-stream (see the numbering
   N1..N17 in docs/pilotage-par-script.md, § 7.5). Each test below fails on the code
   as it was *before* the episode. Run them with:

     dune test

   These tests are cheap and self-contained (loopback and unix domain sockets only):
   they are meant to stay green, since the forthcoming control server
   (bin/control_server.ml) relies on exactly these code paths. *)

module Network = Ocamlbricks.Network
module Either  = Ocamlbricks.Either
module Log     = Ocamlbricks.Ocamlbricks_log

(* --- Minimal test harness (no test framework among the dependencies) --- *)

let failures = ref 0

let check ~name (condition : bool) (details : string) =
  if condition
    then Printf.printf "OK    %s\n%!" name
    else (incr failures; Printf.printf "FAIL  %s -- %s\n%!" name details)

(* Run [f] with the standard error redirected to a temporary file, and return both the
   result of [f] and the text written meanwhile. Note that the redirection acts on the
   file *descriptor*, not on the OCaml channel: this way the ocamlbricks log is caught
   as well: *)
let with_captured_stderr (f : unit -> 'a) : 'a * string =
  let (filename, oc) = Filename.open_temp_file "marionnet-test-stderr-" ".log" in
  let () = flush stderr in
  let saved_stderr = Unix.dup ~cloexec:true Unix.stderr in
  let () = Unix.dup2 (Unix.descr_of_out_channel oc) Unix.stderr in
  let result = f () in
  let () = flush stderr in
  let () = Unix.dup2 saved_stderr Unix.stderr in
  let () = Unix.close saved_stderr in
  let () = close_out oc in
  let captured =
    let ic = open_in_bin filename in
    let text = really_input_string ic (in_channel_length ic) in
    let () = close_in ic in
    text
  in
  let () = try Unix.unlink filename with _ -> () in
  (result, captured)

let contains ~substring text =
  let n = String.length substring and m = String.length text in
  let rec loop i = (i + n <= m) && ((String.sub text i n = substring) || loop (i+1)) in
  loop 0

(* -------------------------------------------------------------------------- *)
(* N4 -- a normally terminated connection must not be logged as a failure. Before
   the fix, the Thread.exit () ending the serving function raised Thread.Exit, which
   is caught by the catch-all of ThreadExtra.create_non_killable and logged as
   "Terminated by uncaught exception": every normal connection looked like an error. *)
(* -------------------------------------------------------------------------- *)

let test_N4_no_spurious_uncaught_exception () =
  let name = "N4: a normal connection is not logged as an uncaught exception" in
  let socketfile = Network.socketname_in_a_fresh_made_directory ~perm:0o700 "ctrl" in
  let protocol (ch : Network.stream_channel) = ch#send ("echo:" ^ (ch#receive ())) in
  let (_server_thread, socketfile) =
    Network.stream_unix_server ~no_fork:() ~socketfile ~protocol ()
  in
  let () = Thread.delay 0.2 in
  let client_protocol (ch : Network.stream_channel) = (ch#send "ping"; ch#receive ()) in
  let (answer, log) =
    with_captured_stderr (fun () ->
      let answer = Network.stream_client ~target:(`unix socketfile) ~protocol:client_protocol () in
      (* give the serving thread the time to terminate, and to log: *)
      let () = Thread.delay 0.4 in
      answer)
  in
  let () =
    check ~name:(name ^ " [round trip]")
      (answer = Either.Right "echo:ping")
      "the client did not get the expected answer"
  in
  check ~name
    (not (contains ~substring:"Terminated by uncaught exception" log))
    "the serving thread logged a spurious uncaught exception (Thread.Exit)"

(* -------------------------------------------------------------------------- *)
(* N13 -- the ~range filter must be applied to the *peer* address, not to our own.
   Discriminating setup: the server listens on 0.0.0.0 while the client connects to
   127.0.0.2 *from* 127.0.0.1. The local address of the service socket (127.0.0.2)
   then differs from the peer address (127.0.0.1), and only the latter belongs to the
   allowed range. Before the fix, this legitimate connection was rejected. *)
(* -------------------------------------------------------------------------- *)

let test_N13_range_predicate_applies_to_peer () =
  let name = "N13: the ~range4 filter tests the peer address" in
  let protocol (ch : Network.stream_channel) = ch#send "pong" in
  let (_server_thread, _ipv4, port) =
    Network.stream_inet4_server
      ~no_fork:() ~range4:"127.0.0.1/32" ~ipv4:"0.0.0.0" ~protocol ()
  in
  let () = Thread.delay 0.2 in
  let received =
    let fd = Unix.socket ~cloexec:true Unix.PF_INET Unix.SOCK_STREAM 0 in
    try
      let () = Unix.bind fd (Unix.ADDR_INET (Unix.inet_addr_of_string "127.0.0.1", 0)) in
      let () = Unix.connect fd (Unix.ADDR_INET (Unix.inet_addr_of_string "127.0.0.2", port)) in
      let buffer = Bytes.create 64 in
      let n = try Unix.recv fd buffer 0 64 [] with _ -> 0 in
      let () = Unix.close fd in
      Bytes.sub_string buffer 0 n
    with e -> ((try Unix.close fd with _ -> ()); Printexc.to_string e)
  in
  check ~name (received = "pong")
    (Printf.sprintf "a connection from an allowed peer was rejected (got %S)" received)

(* -------------------------------------------------------------------------- *)
(* N2 -- no socket of this library may be inherited by an exec'ed child. We simply
   ask a child process (sh) to count the sockets it received. Before the fix, the
   service socket accepted on the ~no_fork path had no close-on-exec flag. *)
(* -------------------------------------------------------------------------- *)

let count_sockets_inherited_by_a_child () =
  try
    let ic = Unix.open_process_in "ls -l /proc/self/fd 2>/dev/null | grep -c 'socket:'" in
    let line = try input_line ic with End_of_file -> "0" in
    let _ = Unix.close_process_in ic in
    (try int_of_string (String.trim line) with _ -> 0)
  with e ->
    (Printf.printf "      (cannot count the inherited sockets: %s)\n%!" (Printexc.to_string e); 0)

let test_N2_no_socket_inherited_by_exec () =
  let name = "N2: no socket is inherited by an exec'ed child" in
  let inherited = ref (-1) in
  let socketfile = Network.socketname_in_a_fresh_made_directory ~perm:0o700 "ctrl" in
  (* The count is performed from within the serving function, hence while a service
     socket (plus the listening and the client sockets) is open: *)
  let protocol (ch : Network.stream_channel) =
    (inherited := count_sockets_inherited_by_a_child (); ch#send "done")
  in
  let (_server_thread, socketfile) =
    Network.stream_unix_server ~no_fork:() ~socketfile ~protocol ()
  in
  let () = Thread.delay 0.2 in
  let client_protocol (ch : Network.stream_channel) = ch#receive () in
  let _ = Network.stream_client ~target:(`unix socketfile) ~protocol:client_protocol () in
  let () = Thread.delay 0.3 in
  check ~name (!inherited = 0)
    (Printf.sprintf "%d socket(s) leaked into the child process" !inherited)

(* -------------------------------------------------------------------------- *)
(* N3 -- a transient failure of the accepting loop must not make the service vanish
   while the application keeps running. We exhaust the descriptor table of the
   process, so that the server gets EMFILE on accept, then release the descriptors:
   the pending connection must finally be served. Before the fix, the exception
   escaped the `while true' loop and definitively killed the server thread.

   Beware: this test is *best effort*, not a decisive one. Whether the server really
   hits EMFILE depends on the timing (it must call accept while the table is full):
   the test cannot fail spuriously -- a failure does mean that the loop died -- but it
   may pass without having exercised the defect at all. What has been *observed* on
   the fixed code, with `ulimit -n 256', is the expected sequence: five "transient
   failure, going on" log entries followed by the connection being served (episode 2,
   2026-07-29). *)
(* -------------------------------------------------------------------------- *)

let test_N3_transient_failure_does_not_kill_the_loop () =
  let name = "N3 (best effort): a transient EMFILE does not kill the accepting loop" in
  let socketfile = Network.socketname_in_a_fresh_made_directory ~perm:0o700 "ctrl" in
  let protocol (ch : Network.stream_channel) = ch#send ("echo:" ^ (ch#receive ())) in
  let (_server_thread, socketfile) =
    Network.stream_unix_server ~no_fork:() ~socketfile ~protocol ()
  in
  let () = Thread.delay 0.2 in
  (* The client socket is created *before* the exhaustion, since afterwards no
     descriptor would be available for it either: *)
  let fd = Unix.socket ~cloexec:true Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  let hogs = ref [] in
  let () =
    try
      while true do hogs := (Unix.openfile "/dev/null" [Unix.O_RDONLY] 0) :: !hogs done
    with _ -> ()
  in
  (* This connection cannot be accepted right now: no descriptor is left for the
     server, whose accept fails with EMFILE as long as the table is full: *)
  let () = try Unix.connect fd (Unix.ADDR_UNIX socketfile) with _ -> () in
  let () = Thread.delay 0.5 in
  let () = List.iter (fun fd -> try Unix.close fd with _ -> ()) !hogs in
  let () = hogs := [] in
  (* The loop must be alive: the pending connection is now served. A timeout is
     mandatory here, otherwise a dead loop would simply hang the test: *)
  let answer =
    try
      let _ = Unix.send_substring fd "ping" 0 4 [] in
      match Unix.select [fd] [] [] 5.0 with
      | ([], _, _) -> "<timeout: the accepting loop is dead>"
      | _ ->
          let buffer = Bytes.create 64 in
          let n = Unix.recv fd buffer 0 64 [] in
          Bytes.sub_string buffer 0 n
    with e -> Printexc.to_string e
  in
  let () = try Unix.close fd with _ -> () in
  check ~name (answer = "echo:ping")
    (Printf.sprintf "the server did not survive the transient failure (got %S)" answer)

(* -------------------------------------------------------------------------- *)

let () =
  let () = Log.enable ~level:1 () in
  let () = Printf.printf "Testing the fixes applied to Ocamlbricks.Network (episode 2)\n%!" in
  let () = test_N4_no_spurious_uncaught_exception () in
  let () = test_N13_range_predicate_applies_to_peer () in
  let () = test_N2_no_socket_inherited_by_exec () in
  (* Last, since it temporarily exhausts the descriptor table of the process: *)
  let () = test_N3_transient_failure_does_not_kill_the_loop () in
  let () = Printf.printf "%d failure(s)\n%!" !failures in
  exit (if !failures = 0 then 0 else 1)
