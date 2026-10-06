(* GPL-2.0-or-later. Lifecycle regressions against the actual compiled modules.
   Run through lifecycle.py; fixtures use only unprivileged host processes. *)
module Log = Marionnet_log
module Simulation = Dune__exe__Simulation_level
module Tasks = Dune__exe__Task_runner

let check message condition =
  if not condition then failwith message;
  Printf.printf "PASS: %s\n%!" message

class child program arguments = object
  inherit Simulation.process program arguments
    ~unexpected_death_callback:(fun _ _ -> failwith "unexpected death") ()
end

class socket_child program arguments directory = object
  inherit Simulation.process_which_creates_a_socket_at_spawning_time
    program arguments ~working_directory:directory
    ~unexpected_death_callback:(fun _ _ -> ()) ()
end

class device directory fail_start fail_stop = object
  inherit [ < get_name : string > ] Simulation.device
    ~parent:(object method get_name = "fixture" end) ~hublet_no:0
    ~working_directory:directory ~unexpected_death_callback:(fun () -> ()) ()
  method device_type = "fixture"
  method spawn_processes = if !fail_start then failwith "startup fixture"
  method terminate_processes = if !fail_stop then failwith "shutdown fixture"
  method stop_processes = ()
  method continue_processes = ()
end

let fails thunk = try thunk (); false with Failure _ -> true

let () =
  let directory = Sys.getenv "MARIONNET_LIFECYCLE_FIXTURE" in
  let sibling_finished = ref false in
  check "parallel failure is reported after the other worker finishes"
    (fails (fun () -> Tasks.do_in_parallel ~propagate_exceptions:true
      [(fun () -> failwith "fixture");
       (fun () -> Thread.delay 0.15; sibling_finished := true)]) && !sibling_finished);
  Tasks.do_in_parallel [(fun () -> failwith "legacy best-effort fixture")];
  check "best-effort parallel callers retain their behavior" true;
  let fail_start = ref true and fail_stop = ref false in
  let d = new device directory fail_start fail_stop in
  check "failed startup is reported" (fails (fun () -> d#startup));
  fail_start := false;
  d#startup;
  check "a cleaned failed startup can be retried" true;
  fail_stop := true;
  check "failed graceful shutdown is reported" (fails (fun () -> d#gracefully_shutdown));
  fail_stop := false;
  d#gracefully_shutdown;
  check "failed shutdown retains the running state and can be retried" true;
  d#startup;
  fail_stop := true;
  check "failed poweroff is reported" (fails (fun () -> d#shutdown));
  fail_stop := false;
  d#shutdown;
  d#destroy;
  let p = new child "/bin/sleep" ["100"] in
  for _ = 1 to 10 do
    p#spawn;
    let pid = p#get_pid in
    p#terminate;
    check "termination reaps the child before immediate reuse"
      (not (Ocamlbricks.UnixExtra.is_process_alive pid));
    check "the reaper leaves no zombie"
      (try ignore (Unix.waitpid [Unix.WNOHANG] pid); false
       with Unix.Unix_error (Unix.ECHILD, _, _) -> true)
  done;
  p#terminate;
  let marker = Filename.concat directory "ready" in
  let stubborn = new child "/bin/sh"
    ["-c"; "trap '' INT; echo ready > \"$1\"; while :; do :; done"; "fixture"; marker] in
  stubborn#spawn;
  let wait = Ocamlbricks.Spinning.wait_until ~max_delay:0.01 () in
  wait ~timeout:2. ~guard:(fun () -> Sys.file_exists marker) ();
  let pid = stubborn#get_pid in
  stubborn#terminate;
  check "SIGINT-resistant child is killed and reaped"
    (not (Ocamlbricks.UnixExtra.is_process_alive pid));
  let dead = new socket_child "/bin/false" [] directory in
  check "socket startup reports an early exit" (fails (fun () -> dead#spawn));
  check "early socket failure releases its child" (not dead#is_alive);
  let stalled = new socket_child "/bin/sleep" ["100"] directory in
  let started = Unix.gettimeofday () in
  check "socket startup has a deadline"
    (try stalled#spawn; false with Ocamlbricks.Spinning.Timeout -> true);
  check "socket timeout releases its child" (not stalled#is_alive);
  check "socket timeout returns within a bounded interval"
    (Unix.gettimeofday () -. started < 13.)
