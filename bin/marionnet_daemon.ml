(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2008, 2010  Jean-Vincent Loddo
   Copyright (C) 2008  Luca Saiu
   Copyright (C) 2008, 2010  Université Paris 13

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

(* --- *)
module Log = Marionnet_log

(* Activate log: *)
let () = Log.Tuning.Set.debug_level (fun () -> 1)

(* Convenient aliases: *)
module Parameters      = Daemon_parameters
module Language        = Daemon_language
(* --- *)
module MutexExtra      = Ocamlbricks.MutexExtra
module Hashmap         = Ocamlbricks.Hashmap
module Hashmmap        = Ocamlbricks.Hashmmap
(* --- *)
module Recursive_mutex = MutexExtra.Recursive
(* --- *)
let socket_name      = Parameters.socket_name
let timeout_interval = Parameters.timeout_interval
let debug_interval   = Parameters.debug_interval
let select_timeout   = Parameters.select_timeout

(** Client identifiers are simply automatically-generated sequential integers: *)
type client = int

(** Pretty-print a client identifier: *)
let string_of_client client =
  Printf.sprintf "<client #%i>" client

(** The mutex used to protect the resource map from concurrent access: *)
let the_daemon_mutex =
  Recursive_mutex.create ()

(* -----------------------------------------------------------------------
                          CLIENT INFORMATIONS
                        and related structures
   ----------------------------------------------------------------------- *)

(** An associative structure mapping each client to its resources: *)
let resource_map : (client, Language.resource) Hashmmap.hashmultimap =
  new Hashmmap.hashmultimap ()

let ownership (client: client) (resource : Language.resource) : bool =
  resource_map#mem client resource

(** An associative structure mapping each client to the time of the death
    of its resources (unless they send messages, of course): *)
let client_death_time_map : (client, float) Hashmap.hashmap =
  new Hashmap.hashmap ()

(** An associative structure mapping each client to its socket: *)
let socket_map : (client, Unix.file_descr) Hashmap.hashmap =
  new Hashmap.hashmap ()

(** An associative structure mapping each client to its declared uid: *)
let uid_map : (client, Language.uid) Hashmmap.hashmultimap =
  new Hashmmap.hashmultimap ()

(* Add the binding (client, uid) if the requested resource contains this information: *)
let uid_map_add (client: client) = function
| Language.SocketTap (_tap_name, uid, _bridge_name) ->
    (* Note that the following test is implicitely performed by the method #add with ocamlbricks revno >= 452 *)
    if uid_map#mem (client) (uid)
      then ()
      else uid_map#add (client) (uid)
| _ -> () (* Nothing to do *)

(** Useful to check the consistency before destroying a resource: *)
let uid_consistency (client: client) (uid : Language.uid) : bool =
  let () = Log.printf2 "Looking for client-uid consistency: (#%d, %d)... \n" client uid in
  match (uid_map#lookup client) with
  | [uid'] when uid = uid'  -> true
  | [uid'] when uid <> uid' ->
      let () = Log.printf1 "Error: the client %d has previously declared another uid!\n" client in
      false
  | [] ->
      let () = Log.printf1 "Error: the client %d has not a declared uid!\n" client in
      false
  | _ ->
      let () = Log.printf1 "Error: the client %d has too many declared uid!\n" client in
      false

(* ----------------------------------------------- END of CLIENT STRUCTURES *)

(** Seed the random number generator: *)
let () = Random.self_init ()

(** Generate a random name, very probably unique, with the given prefix: *)
let make_fresh_name prefix =
  let random_number = Random.int 1000000 in
  Printf.sprintf "%s%i" prefix random_number

(** Generate a random name, very probably unique, for a new tap: *)
let make_fresh_tap_name () =
   make_fresh_name "tap"

(** Generate a random name, very probably unique, for a new tap
    for the socket component: *)
let make_fresh_tap_name_for_world_bridge () =
  make_fresh_name "wbtap"

(** Accepted tap prefixes for destructions: *)
let accepted_tap_prefixes =
  ["tap"; "wbtap"]

(** Actually make a tap at the OS level: *)
let make_system_tap (tap_name : Language.tap_name) uid ip_address =
  Log.printf1 "Making the tap %s...\n" tap_name;
  let command_line =
    Printf.sprintf
      "{ tunctl -u %i -t %s && ifconfig %s 172.23.0.254 netmask 255.255.255.255 up; route add %s %s; }"
      (uid) (tap_name) (tap_name) (ip_address) (tap_name)
  in begin
  Log.system_or_fail command_line;
  Log.printf1 "The tap %s was created with success\n" tap_name
  end

(** Actually make a tap at the OS level for the world bridge component: *)
let make_system_tap_for_world_bridge (tap_name : Language.tap_name) uid bridge_name =
  Log.printf1 "Making the tap %s...\n" tap_name;
  let command_line =
    Printf.sprintf
      "{ tunctl -u %i -t %s && ifconfig %s 0.0.0.0 promisc up && brctl addif %s %s; }"
      (uid) (tap_name) (tap_name) (bridge_name) (tap_name)
  in begin
  let on_error = Printf.sprintf "tunctl -d %s" tap_name in
  Log.system_or_fail ~on_error command_line;
  Log.printf1 "The tap %s was created with success\n" tap_name
  end

let repeat_obstinately
  ?(delay=1.)
  ?(delay_increasing=(fun x -> x +. 1.))
  ?(max_attempts=100) (* with increasing \x.x+1 => max waiting time = 100*101/2=5000 seconds > 1 day *)
  (thunk:unit->bool) : unit -> unit =
  let rec loop (delay) (attempts) =
    if attempts > max_attempts then () else (* continue: *)
    if thunk () then () else (* continue: *)
    let () = Thread.delay (delay) in
    loop (delay_increasing delay) (attempts+1)
  in
  fun () -> loop delay 0

let remove_tuntap ~(command:string) (tap_name : Language.tap_name) : bool =
  (* --- *)
  let () = Log.printf1 "Destroying the TUN/TAP interface %s...\n" tap_name in
  (* Try to remove the tuntap with the provided shell command: *)
  let () = ignore (Unix.system command) in
  (* Now test if the tap exists: *)
  let ifconfig_tap = Printf.sprintf "ifconfig %s 2>/dev/null 1>/dev/null" (tap_name) in
  match (Unix.system ifconfig_tap) with
  (* --- *)
  | Unix.WEXITED 0 (* Damn, the tap still exists! *) ->
      let () = Log.printf1 "Failed to destroy the TUN/TAP interface %s\n" tap_name in
      false
  (* --- *)
  | _ -> (* The tap doesn't exist. It's fine: *)
     let () = Log.printf1 "The TUN/TAP interface %s was destroyed with success\n" tap_name in
     true

(** Actually destroy a tap at the OS level for the socket component: *)
let destroy_system_tap_for_world_bridge (tap_name : Language.tap_name) (uid (*unused*))  (bridge_name) =
  let command =
    Printf.sprintf "ifconfig %s down && brctl delif %s %s && tunctl -d %s"
      (tap_name)  (bridge_name) (tap_name)  (tap_name)
  in
  let thunk () : bool = remove_tuntap ~command (tap_name) in
  let _ = Thread.create (repeat_obstinately thunk) () in
  ()

(** Actually destroy a tap at the OS level: *)
let destroy_system_tap (tap_name : Language.tap_name) =
  let command = Printf.sprintf "ifconfig %s down && tunctl -d %s" (tap_name) (tap_name) in
  let thunk () : bool = remove_tuntap ~command (tap_name) in
  let _ = Thread.create (repeat_obstinately thunk) () in
  ()

(** Instantiate the given pattern, actually create the system object, and return
    the instantiated resource: *)
let make_system_resource resource_pattern : Language.resource =
  match resource_pattern with
  (* --- *)
  | Language.AnyTap(uid, ip_address) ->
      let tap_name = make_fresh_tap_name () in
      make_system_tap tap_name uid ip_address;
      Language.Tap tap_name
  (* --- *)
  | Language.AnySocketTap(uid, bridge_name) ->
      let tap_name = make_fresh_tap_name_for_world_bridge () in
      make_system_tap_for_world_bridge tap_name uid bridge_name;
      Language.SocketTap(tap_name, uid, bridge_name)

(** Actually destroyed the system object named by the given resource: *)
let destroy_system_resource resource =
  match resource with
  | Language.Tap tap_name ->
      destroy_system_tap tap_name
  | Language.SocketTap(tap_name, uid, bridge_name) ->
      destroy_system_tap_for_world_bridge tap_name uid bridge_name

(** Create a suitable resource matching the given pattern, and return it.
    Synchronization is performed inside this function, hence the caller doesn't need
    to worry about it: *)
let make_resource client resource_pattern =
  Recursive_mutex.with_mutex (the_daemon_mutex)
    (fun () ->
      try
        (* Create a resource satisfying the given specification, and return it: *)
        Log.printf2
          "Making %s for %s\n"
          (Language.string_of_daemon_resource_pattern resource_pattern)
          (string_of_client client);
        let resource = make_system_resource resource_pattern in
        Log.printf2 "Adding %s for %s\n" (Language.string_of_daemon_resource resource) (string_of_client client);
        resource_map#add client resource;
        uid_map_add client resource;
        resource
      with e -> begin
        Log.printf3 "Failed (%s) when making the resource %s for %s; bailing out.\n"
          (Printexc.to_string e)
          (Language.string_of_daemon_resource_pattern resource_pattern)
          (string_of_client client);
        raise e;
      end)

(** Destroy the given resource. Synchronization is performed inside this function,
    hence the caller doesn't need to worry about it: *)
let destroy_resource (client) (resource) =
  Recursive_mutex.with_mutex (the_daemon_mutex)
    (fun () ->
      try
        Log.printf2 "Removing %s %s\n" (string_of_client client) (Language.string_of_daemon_resource resource);
        Log.printf1 "** resource_map has %i bindings\n" (List.length resource_map#to_list);
        resource_map#remove_key_value_or_fail client resource;
        (* resource_map#remove_key_value client resource; *)
        Log.printf1 "** resource_map has %i bindings\n" (List.length resource_map#to_list);
        destroy_system_resource resource;
      with e -> begin
        Log.printf3 "WARNING: failed (%s) when destroying %s for %s.\n"
          (Printexc.to_string e)
          (Language.string_of_daemon_resource resource)
          (string_of_client client);
        raise e;
      end)

let destroy_all_client_resources client =
  Recursive_mutex.with_mutex (the_daemon_mutex)
    (fun () ->
      try
        Log.printf1 "Removing all %s's resources:\n" (string_of_client client);
        (* --- *)
        List.iter
          (fun resource -> destroy_resource client resource)
          (resource_map#lookup client);
        (* --- *)
        let () =  uid_map#remove ~all:true client in
        (* --- *)
        Log.printf1 "All %s's resources were removed with success.\n" (string_of_client client);
      with e -> begin
        Log.printf2 "Failed (%s) when removing %s's resources; continuing anyway.\n"
          (Printexc.to_string e)
          (string_of_client client);
      end)

let destroy_all_resources () =
  Recursive_mutex.with_mutex (the_daemon_mutex)
    (fun () ->
       List.iter
         (fun (client, _) ->
            try
              destroy_all_client_resources client
            with e -> begin
              Log.printf2 "Failed (%s) when removing %s's resources (while removing *all* resources); continuing anyway.\n"
                (Printexc.to_string e)
                (string_of_client client);
            end)
         client_death_time_map#to_list)

let keep_alive_client client =
  Recursive_mutex.with_mutex (the_daemon_mutex)
    (fun () ->
      try
        (* Immediately raise an exception if the client is not alive: *)
        let _ = client_death_time_map#lookup client in
        let current_time = Unix.time () in
        let death_time = current_time +. timeout_interval in
        client_death_time_map#add client death_time;
        Log.printf3
          "I will not kill %s until %f (it's now %f)\n"
          (string_of_client client)
          death_time
          current_time;
        flush_all ();
      with Not_found -> begin
        Log.printf1
          "keep_client_alive failed because the client %s is not alive.\n"
          (string_of_client client);
        failwith ("keep_alive_client: " ^ (string_of_client client) ^ " is not alive.");
      end);;

(** Some resources [well, none as of now] are global, i.e. shared by all
    clients whenever there is at least one. We use a reference-counter to keep
    track of the number of currently existing clients; global resources are
    created when the counter raises from 0 to 1, and destroyed when it drops
    from 1 to 0. *)
let client_no = ref 0;;
let the_resources_if_any = ref None;;
let global_resources () =
  Recursive_mutex.with_mutex (the_daemon_mutex)
    (fun () ->
      match !the_resources_if_any with
      | None ->
          failwith "the global resources do not exist; this should never happen"
      | Some resources ->
          resources);;

let make_global_resources_unlocked_ () =
  let () = assert(!the_resources_if_any = None) in
  (* To do: actually create something, if needed. *)
  the_resources_if_any := Some ()

let destroy_global_resources_unlocked_ () =
  match !the_resources_if_any with
  | None -> assert false
  | Some resources -> begin
      (* To do: actually destroy something, if needed. *)
      the_resources_if_any := None;
      flush_all ();
      end

let increment_client_no () =
  Recursive_mutex.with_mutex (the_daemon_mutex)
    (fun () ->
      (if !client_no = 0 then begin
        Log.printf "There is at least one client now. Creating global resources...\n";
        make_global_resources_unlocked_ ();
        Log.printf "Global resources were created with success.\n";
      end);
      client_no := !client_no + 1)

let decrement_client_no () =
  Recursive_mutex.with_mutex (the_daemon_mutex)
    (fun () ->
      client_no := !client_no - 1;
      (if !client_no = 0 then begin
        Log.printf "There are no more clients now. Destroying global resources...\n";
        destroy_global_resources_unlocked_ ();
        Log.printf "Global resources were destroyed with success.\n";
      end))

(** Create a new client on which we're going to interact with the given socket,
    and return its identifier: *)
let make_client =
  let next_client_no = ref 1 in
  fun socket ->
    Recursive_mutex.with_mutex (the_daemon_mutex)
      (fun () ->
        (* Generate a new unique identifier: *)
        let result = !next_client_no in
        next_client_no := !next_client_no + 1;
        (* First add any number to the data structure, then call keep_alive_client to make
           the death time correct: *)
        Log.printf1 "Creating %s.\n" (string_of_client result);
        client_death_time_map#add result 42.42;
        socket_map#add result socket;
        keep_alive_client result;
        increment_client_no ();
        Log.printf1 "Created %s.\n" (string_of_client result);
        result)

let destroy_client client =
  Recursive_mutex.with_mutex (the_daemon_mutex)
    (fun () ->
      Log.printf1 "Killing %s.\n" (string_of_client client);
      (try client_death_time_map#remove client with _ -> ());
      (try destroy_all_client_resources client with _ -> ());
      decrement_client_no ();
      (try
        Unix.close (socket_map#lookup client);
        Log.printf1 "The socket serving the client %i was closed with success.\n" client;
      with e -> begin
        Log.printf2
          "Closing the socket serving the client %i failed (%s).\n"
          client (Printexc.to_string e);
      end);
      (try socket_map#remove client with _ -> ());
      Log.printf1 "%s was killed.\n" (string_of_client client))

let debugging_thread_thunk () =
  while true do
    Thread.delay debug_interval;
    Recursive_mutex.with_mutex (the_daemon_mutex)
      (fun () ->
        Log.printf "--------------------------------------------\nCurrently existing non-global resources are:\n";
        List.iter
          (fun (client, resource) ->
            Log.printf2 "* %s (owned by %s)\n" (Language.string_of_daemon_resource resource) (string_of_client client))
          (resource_map#to_list);
        Log.printf "--------------------------------------------\n";
        );
  done

(** The 'timeout thread' wakes up every timeout_interval seconds and kills
    all clients whose death time is past. *)
let timeout_thread_thunk () =
  while true do
    (* Sleep: *)
    Thread.delay timeout_interval;

    (* Some variables are shared, so we have to synchronize this block; it's not
       a problem as this should be very quick: *)
    Recursive_mutex.with_mutex (the_daemon_mutex)
      (fun () ->
        (* Get up-to-date death time information for all clients: *)
        let current_time = Unix.time () in
        let client_death_times = client_death_time_map#to_list in
        (* Kill all clients whose death time is past: *)
        List.iter
          (fun (client, death_time) ->
            if current_time >= death_time then begin
              Log.printf1 "Client %s didn't send enough keep-alive's.\n" (string_of_client client);
              destroy_client client;
            end)
          client_death_times);
  done

(** Serve the given single request from the given client, and return the
    response. This does not include the keep-alive. *)
let serve_request request client =
  match request with
  | Language.IAmAlive              -> Language.Success
  | Language.Make resource_pattern -> Language.Created (make_resource client resource_pattern)
  | Language.Destroy resource      -> begin destroy_resource client resource; Language.Success; end
  | Language.DestroyAllMyResources -> begin destroy_all_client_resources client; Language.Success; end


(** This thread serves *one* client whose socket is given and is assumed
    to be open: *)
let connection_server_thread (client, socket) =
  try
    Log.printf1 "This is the connection server thread for client %i.\n" client;
    while true do
      Log.printf "Beginning of the iteration.\n";
      (* We want the message to be initially invalid, at every iteration, to
         avoid the risk of not seeing a receive error. Just to play it extra safe: *)
      let buffer = Bytes.make (Language.message_length) 'x' in
      (* We don't want to block indefinitely on read() because the socket could
         be closed by another thread; so we simply select() with a timeout: *)
      let (ready_for_read, _, failed) =
        try
          Unix.select [socket] [] [socket] select_timeout
        with _ -> begin
          Log.printf "!!!!FAILED IN select (connection_server_thread)!!!!\n";
          failwith "select() failed";
          (* ([], [], []); *)
        end
      in
      (* --- *)
      (* Unix.select [socket] [] [socket] select_timeout in *)
      if (List.length failed) > 0 then
        failwith "select() reported failure with the socket"
      else if (List.length ready_for_read) > 0 then begin
        let received_byte_no =
          Unix.read socket buffer 0 Language.message_length
        in
        if received_byte_no < Language.message_length then
          failwith "recv() failed, or the message is ill-formed"
        else begin
          (* --- *)
          let request : Language.secure_daemon_request =
            Language.parse_request
              ~ownership:(ownership client)
              ~uid_consistency:(uid_consistency client)
              ~accepted_address_prefix:"172.23."   (* tap adresses are in this range *)
              ~accepted_tap_prefixes               (* defined above: ["tap"; "wbtap"] *)
              (Bytes.to_string buffer)
          in
          keep_alive_client client;
          (* --- *)
          let response =
            match request with
            | Either.Right error_msg ->
                let () = Log.printf1 "Invalid request: %s\n" error_msg in
                Language.Error (error_msg)
            (* --- *)
            | Either.Left request ->
                let () = Log.printf1 "The request is\n  %s\n" (Language.string_of_daemon_request request) in
                (try
                   serve_request request client
                 with e ->
                   Language.Error (Printexc.to_string e))
          in
          (* --- *)
          Log.printf1 "My response is\n  %s\n" (Language.string_of_daemon_response response);
          let sent_byte_no = Unix.send (socket) ((Language.print_response response) |> Bytes.of_string) (0) (Language.message_length) [] in
          (if not (sent_byte_no == sent_byte_no) then failwith "send() failed");
          (* --- *)
        end; (* inner else *)
      end else begin
        (* If we arrived here select() returned due to the timeout, and we
           didn't receive anything: loop again. *)
      end;
    done;
  with e -> begin
    Log.printf2
      "Failed in connection_server_thread (%s) for client %i.\nBailing out.\n"
      (Printexc.to_string e)
      client;
    destroy_client client; (* This also closes the socket *)
    Log.printf1 "Exiting from the thread which was serving client %i\n" client;
  end

(** Remove an old socket file, remained from an old instance or from ours
    (when we're about to exit). Do nothing if there is no such file: *)
let remove_socket_file_if_any () =
  try
    Unix.unlink socket_name;
    Log.printf1 "[Removed the old socket file %s]\n" socket_name;
  with _ ->
    Log.printf1 "[There was no need to remove the socket file %s]\n" socket_name

(** Destroy all resources, destroy the socket and exit on either SIGINT and SIGTERM: *)
let signal_handler signal = begin
  Log.printf1 "=========================\nI received the signal %i!\n=========================\nDestroying all resources...\n" signal;
  destroy_all_resources ();
  Log.printf "Ok, all resources were destroyed.\nRemoving the socket file...\n";
  remove_socket_file_if_any ();
  Log.printf "Ok, the socket file was removed.\n";
  raise Exit
  end

(** Strangely, without calling this the program is uninterruptable from the
    console: *)
let () = Sys.catch_break false;;
let () = Sys.set_signal Sys.sigint (Sys.Signal_handle signal_handler);;
let () = Sys.set_signal Sys.sigterm (Sys.Signal_handle signal_handler);;

(* --- *)
let check_that_we_are_root () =
  if (Unix.getuid ()) != 0 then begin
    Log.printf "\n*********************************************\n";
    Log.printf "* The Marionnet daemon must be run as root. *\n";
    Log.printf "* Bailing out.                              *\n";
    Log.printf "*********************************************\n\n";
    raise Exit;
  end

(* --- *)
let the_server_main_thread = begin
  check_that_we_are_root ();
  ignore (Thread.create timeout_thread_thunk ());
  ignore (Thread.create debugging_thread_thunk ());
  let connection_no_limit = 10 in
  let accepting_socket = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  let sock_addr = Unix.ADDR_UNIX socket_name in
  (* Remove the socket file, if it already exists: *)
  remove_socket_file_if_any ();
  (* Bind the file to the socket; this creates the file, or fails if there
     are permission or disk space problems: *)
  Unix.bind accepting_socket sock_addr;
  (* Everybody must be able to send messages to us: *)
  Unix.chmod socket_name 438 (* a+rw *);
  Log.printf1 "I am waiting on %s.\n" socket_name;
  Unix.listen accepting_socket connection_no_limit;
  while true do
    try
      Log.printf "Waiting for the next connection...\n";
      let (socket_to_client, socket_to_client_address) = Unix.accept accepting_socket in
      let client_id = make_client socket_to_client in
      Log.printf1 "A new connection was accepted; the new client id is %i\n" client_id;
      ignore (Thread.create connection_server_thread (client_id, socket_to_client));
    with e -> begin
      Log.printf1 "Failed in the main thread (%s). Bailing out.\n" (Printexc.to_string e);
      raise e;
      end;
  done
end (* the_server_main_thread *)
