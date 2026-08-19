(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008, 2009  Luca Saiu
   Copyright (C) 2008, 2009, 2010  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2009, 2010  Université Paris 13

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
module UnixExtra = Ocamlbricks.UnixExtra
module Hashmap = Ocamlbricks.Hashmap
(* --- *)

IFNDEF OCAML4_02_OR_LATER THEN
module Bytes = struct  let create = String.create  let set = String.set  end
ENDIF

let blinker_thread_socket_file_name =
  let result = UnixExtra.temp_file ~prefix:".marionnet-blinker-server-socket-" () in
  Log.printf1 "ledgrid_manager: The blinker server socket is %s\n" result;
  result;;

class ledgrid_manager =
object (self)
  (** Synchornization is automatically managed by methods, thus making
      ledgrid_manager a monitor *)
  val mutex = Mutex.create ()
  method private lock   = Mutex.lock mutex
  method private unlock = Mutex.unlock mutex

  (** Run the thunk holding the monitor's mutex, releasing it even when the thunk raises.
      The plain `self#lock; body; self#unlock' sequence used until episode 15 left the mutex
      locked forever as soon as the body raised — and `make_widget' does build Gtk+ widgets —
      after which the permanent blinker thread (`flash', called on every datagram received)
      would block for good. *)
  method private with_lock : 'a. (unit -> 'a) -> 'a =
    fun thunk ->
      let () = self#lock in
      Fun.protect ~finally:(fun () -> self#unlock) thunk

  val id_to_data = Hashmap.make ()

  method blinker_thread_socket_file_name =
    blinker_thread_socket_file_name

  (** Return a tuple (window, device, name, connected_port_indices). This is {e unlocked}! *)
  method private lookup (id : int) =
    try
      Hashmap.lookup id_to_data id
    with _ -> begin
      failwith ("id_to_device: No device has id " ^ (string_of_int id))
    end

  (** This is {e unlocked}! *)
  method private id_to_device (id : int) =
    let _, device, _, _ = self#lookup id in
    device

  (** This is {e unlocked}! *)
  method private id_to_window (id : int) =
    let window, _, _, _ = self#lookup id in
    window

  (** This is {e unlocked}! *)
  method private id_to_name (id : int) =
    let _, _, name, _ = self#lookup id in
    name

  (** This is {e unlocked}! *)
  method private id_to_connected_ports (id : int) =
    let _, _, _, connected_ports = self#lookup id in
    connected_ports

  method get_connected_ports ~id () =
    self#with_lock (fun () -> self#id_to_connected_ports id)

  (** This is {e unlocked}! *)
  method private update_connected_ports (id : int) new_connected_ports =
    let window, device, name, _ = self#lookup id in
    Hashmap.replace id_to_data id (window, device, name, new_connected_ports)

  (** Make the given ledgrid window always on top, and visible (this is a harmless side
      effect of the implementation; we always need the window to be visible anyway when
      calling this method) *)
  method private set_always_on_top id value : unit =
    let window = self#id_to_window id in
(*     window#misc#set_property "keep-above" (`BOOL true); *)
    let is_window_visible = true (*window#misc#hidden*) in
    (if is_window_visible then
      window#misc#hide ());
(*     window#misc#set_property "keep-above" (`BOOL true); *)
    window#set_type_hint
      (if value then `DIALOG else `NORMAL);
    window#set_position `MOUSE;
    (if is_window_visible then
      window#misc#show ());

  (** This is {e unlocked}! *)
  method private make_widget ~id ~port_no ?port_labelling_offset ~title ~label ~image_directory () =
    let window =
      GWindow.window
        ~icon:Icon.icon_pixbuf
        ~title
        ~border_width:0
        ~resizable:false
        ()
    in
    (* 230 pixels seems a minimum with a 2-letters title: *)
    let () = window#set_width_request 230 in
    (* --- *)
    let frame = GBin.frame ~label (* ~shadow_type:`ETCHED_OUT *) ~packing:window#add () in
    (* let box = GPack.box `HORIZONTAL ~packing:frame#add () in  *)
    let vbox = GPack.box `VERTICAL ~packing:frame#add () in
    let box = GPack.box `HORIZONTAL ~packing:vbox#add () in
    let always_on_top_box = GPack.box `HORIZONTAL ~packing:vbox#add () in
    let check_button =
      GButton.check_button (*~stock:`CUT*) ~label:"Always on top" ~packing:always_on_top_box#add ()
    in
    ignore (check_button#connect#clicked
              ~callback:(fun () ->
                let state = check_button#active in
                self#set_always_on_top id state));
    (* Make a label which we don't need to name: *)
    ignore (GMisc.label ~text:"Activity" ~packing:box#add ());
    ignore (window#event#connect#delete
             ~callback:(fun _ -> Log.printf "ledgrid_manager: Sorry, no, you can't\n"; true));
    let device =
      new Ledgrid.device_led_grid
        ~packing:box#add ~ports:port_no ~show_100_mbs:false
        ~lines:(if port_no > 8 then 2 else 1)
        ~angle:(if port_no > 8 then 90.0 else 0.0)
        ~off_xpm_file_name:(image_directory^"/off.xpm")
        ~on_xpm_file_name:(image_directory^"/on.xpm")
        ?port_labelling_offset
        ~nothing_xpm_file_name:(image_directory^"/nothing.xpm")
        ()
    in
      (* Note how the window is {e not} shown by default: it's appropriate
         to show it only when the device is started up. *)
      window, device

  method make_device_ledgrid ~id ~title ~label ~port_no ?port_labelling_offset ~image_directory
      ?connected_ports:(connected_ports=[])() =
    (* Widgets from the GTK main thread only — see the comment above `reset' below. *)
    GMain_actor.apply_extract (fun () ->
    self#with_lock (fun () ->
    Log.printf3 "ledgrid_manager: Making a ledgrid with title %s (id=%d) with %d ports.\n" title id port_no;
    (* `make_widget' returns the window first, the ledgrid device second, which is also the order
       expected by `lookup': (window, device, name, connected_port_indices). *)
    let window_widget, ledgrid_widget =
      self#make_widget ~id ~port_no ?port_labelling_offset ~title ~label ~image_directory () in
    Hashmap.add id_to_data id (window_widget, ledgrid_widget, title, connected_ports);
    (* The *unlocked* variant on purpose: we already hold the mutex, and Mutex.lock is not
       recursive (episode 15). *)
    List.iter
      (fun port -> self#set_port_connection_state_unlocked ~id ~port ~value:true)
      connected_ports;
    Log.printf ~v:2 "ledgrid_manager: Ok, done.\n";
    Log.printf1 ~v:2 "ledgrid_manager: Testing (1): is id=%d present in the table?...\n" id;
    (try
      let _ = self#id_to_device id in
      Log.printf ~v:2 "ledgrid_manager: Ok, passed.\n";
    with _ ->
      Log.printf ~v:2 "ledgrid_manager: FAILED.\n");
    Log.printf1 ~v:2 "ledgrid_manager: Testing (2): is id=%d present in the table?...\n" id;
    (try
      let _ = self#lookup id in
      Log.printf ~v:2 "ledgrid_manager: Ok, passed.\n";
    with _ ->
      Log.printf ~v:2 "ledgrid_manager: FAILED.\n"))) ()

  method show_device_ledgrid ~id () =
    GMain_actor.apply_extract (fun () ->
    self#with_lock (fun () ->
    (try
      (self#id_to_window id)#show ();
    with _ ->
      Log.printf1 "ledgrid_manager: Warning: id %d unknown in show_device_ledgrid\n" id))) ()

  method hide_device_ledgrid ~id () =
    GMain_actor.apply_extract (fun () ->
    self#with_lock (fun () ->
    (try
      (self#id_to_window id)#misc#hide ();
    with _ ->
      Log.printf1 "ledgrid_manager: Warning: id %d unknown in show_device_ledgrid\n" id))) ()

  method destroy_device_ledgrid ~id () =
    GMain_actor.apply_extract (fun () ->
    self#with_lock (fun () ->
    Log.printf1 "ledgrid_manager: Destroying the ledgrid with id %d\n" id;
    (try
      (self#id_to_window id)#misc#hide ();
      (self#id_to_window id)#destroy ();
      Hashmap.remove id_to_data id
     with _ ->
      Log.printf1 "ledgrid_manager: WARNING: failed in destroy_device_ledgrid: id is %d\n" id
    ))) ()

  (** This is {e unlocked}! *)
  method private set_port_connection_state_unlocked ~id ~port ~value =
    Log.printf3
      "ledgrid_manager: Making the port %d of device %d %s\n"
       port id (if value then " connected" else " disconnected");
    (try
      (self#id_to_device id)#set port value;
      let new_connected_ports =
        if value then
          port :: (self#id_to_connected_ports id)
        else
          List.filter (fun p -> p != port) (self#id_to_connected_ports id) in
      self#update_connected_ports id new_connected_ports;
    with _ ->
      Log.printf2 "ledgrid_manager: WARNING: failed in set_port_connection_state: id=%d port=%d\n" id port
    )

  method set_port_connection_state ~id ~port ~value () =
    GMain_actor.apply_extract (fun () ->
    self#with_lock (fun () ->
    self#set_port_connection_state_unlocked ~id ~port ~value)) ()

  (* Hot path: the blinker thread hands over here everything it has read since the previous
     delivery. Until now this was a per-datagram [flash ~id ~port], kept SYNCHRONOUS
     (apply_extract) in the name of backpressure. The backpressure was real, but it pushed back
     on the wrong side: while the blinker waits for the main thread it does not read its datagram
     socket, so the socket fills, and then

       - `wirefilter' blocks in its own sendto, which stops the SIMULATED NETWORK -- measured, a
         ping through a switch goes from 1.4 ms to 2441 ms with 22% loss;

       - at exit, [kill_blinker_thread] sends "please-die" on that saturated socket FROM the main
         thread, the very thread the blinker is waiting for -- measured, the main thread parks in
         the kernel (unix_wait_for_peer) and the application can no longer be quit.

     Hence the three properties this method must keep: ASYNCHRONOUS (the blinker never waits, so
     it always gives the socket back to the kernel), COALESCED (one delegation per batch instead
     of one per packet, so the main loop is not flooded either -- that was the legitimate half of
     the backpressure argument), and holding the mutex exactly ONCE for the whole batch. LED
     blinking is cosmetic -- this very file says so below -- and cosmetics must never be able to
     stop anything. *)
  method flash_many (batch : (int * int) list) =
    if batch = [] then () else
    (* TWO guards, because a batch can fail on either side of the actor and both failures would
       otherwise leave no trace whatsoever -- and a silent failure on this path is exactly what
       made the bug this method comes from so expensive to instruct.

         (1) the caller's side: [delegate ~async:()] does not wait, but it still POSTS the idle
             callback from the blinker thread. An exception there would escape into the blinker
             loop and kill that thread for good -- LEDs, and socket draining, with it.

         (2) the actor's side: [delegate ~async:()] discards whatever its closure raises. Anything
             escaping [with_lock] -- the mutex itself, notably -- would be swallowed in silence.

       The per-LED failure below stays silent on purpose, and it is the only one which may: a LED
       grid destroyed while packets are still in flight is the normal course of things and says
       nothing about anything. *)
    try
      GMain_actor.delegate ~async:() (fun () ->
      try
      self#with_lock (fun () ->
      List.iter
        (fun (id, port) ->
(* Annoying for the world_gateway *)
(*       Log.print_string ("Flashing port " ^ (string_of_int port) ^ " of device " ^ *)
(*                     (self#id_to_name id) ^ "\n"); *)
           try (self#id_to_device id)#flash port with _ -> ())
        batch)
      with e ->
        Log.printf2
          "ledgrid_manager: WARNING: flashing a batch of %d LED(s) failed in the GTK main thread: %s\n"
          (List.length batch) (Printexc.to_string e)) ()
    with e ->
      Log.printf2
        "ledgrid_manager: WARNING: handing a batch of %d LED(s) over to the GTK main thread failed: %s\n"
        (List.length batch) (Printexc.to_string e)

  (** Destroy all currently existing widgets and their data, so that we can start
      afresh with a new network: *)
  (* Every method of this class that touches a widget runs inside GMain_actor.apply_extract, for
     the reason spelled out at length in treeview.ml (episodes 9 and 10): touching Gtk+ from a
     thread other than the main one can make lablgtk re-enter OCaml and ask for a master lock the
     calling thread already holds, freezing the whole process. Here the callers are the closing
     thread (state.ml calls #reset), task runner tasks (component destruction), and above all the
     permanent blinker thread, which flashes LEDs for the entire life of a simulation.
     The wrapping deliberately encloses the mutex too: were only the widget calls delegated, a
     thread would hold this mutex WHILE waiting for the main thread, which is the deadlock shape
     rejected at episode 5. Enclosing lock and unlock means the mutex is only ever taken by the
     main thread, so it can no longer be part of a cycle.
     Hence the shape every public method of this class must keep (episode 15):
       GMain_actor.apply_extract (fun () -> self#with_lock (fun () -> ...)) ()
     and every *internal* call goes to an `_unlocked' variant instead of to the public method,
     since Mutex.lock is not recursive: make_device_ledgrid used to call
     set_port_connection_state, so a non-empty ~connected_ports would have self-deadlocked. *)
  method reset =
    GMain_actor.apply_extract (fun () ->
    (* Log.print_string "\n\n*************** LEDgrid_manager: reset was called.\n\n"; *)
    let hashmap_as_alist = Hashmap.to_list id_to_data in
    ignore (List.map
              (fun (id, _) ->
                self#destroy_device_ledgrid ~id ();
                Hashmap.remove id_to_data id)
              hashmap_as_alist)) ();

  val blinker_thread = ref None;

  method blinker_thread =
    match !blinker_thread with
      (Some blinker_thread) -> blinker_thread
    | None -> assert false

  method private make_blinker_thread =
    Log.printf ("ledgrid_manager: Making a blinker thread\n");
    Thread.create
      (fun () ->
        Log.printf ("ledgrid_manager: Making the socket\n");
        let socket = Unix.socket Unix.PF_UNIX Unix.SOCK_DGRAM 0 in
        let _ = try Unix.unlink blinker_thread_socket_file_name with _ -> () in
        Log.printf ("ledgrid_manager: Binding the socket\n");
        let _ = Unix.bind socket (Unix.ADDR_UNIX blinker_thread_socket_file_name) in
        Log.printf ("ledgrid_manager: Still alive\n");
        let maximum_message_size = 1000 in
        let buffer = Bytes.create maximum_message_size in
        Log.printf ("ledgrid_manager: Ok, entering the thread main loop\n");
        (* Set by the "please-die" branch below to leave the loop. Since OCaml 5.0
           `Thread.exit ()' no longer terminates the thread: it raises `Thread.Exit',
           which the catch-all handler of this very loop would swallow, spinning
           forever on an already closed socket. *)
        let finished = ref false in
        (* Coalescing, the blinker's half of what [flash_many] documents above. The one duty of
           this thread is to give the socket back to the kernel as fast as it can; what it has
           read is remembered here and handed over to the main thread at most every
           [flush_interval] seconds. 50 ms sits below the 80 ms a LED stays lit
           ([Ledgrid.flash_duration]), so nothing visible is lost, and it caps the main loop at
           twenty delegations per second whatever the packet rate is. *)
        let flush_interval = 0.050 in
        let pending : (int * int) list ref = ref [] in
        let last_flush = ref (Unix.gettimeofday ()) in
        let flush_pending () =
          if !pending = [] then () else begin
            let batch = List.rev !pending in
            pending := [];
            last_flush := Unix.gettimeofday ();
            self#flash_many batch
          end
        in
        (* An endpoint with no LED grid is announced as (id: -1; port: -1) by simulation_level.ml.
           Remembering it would buy nothing but a lookup guaranteed to fail, once per packet --
           and, before this was a batch, a whole round trip to the main thread for it. *)
        let remember (id, port) =
          if id >= 0 && not (List.mem (id, port) !pending) then pending := (id, port) :: !pending
        in
        while not !finished do
          (* ==== Beginning of the reasonable version ==== *)
(** This commented-out version was absolutely reasonable and it worked with the old
    patched VDE, but for some strange reason I can't understand now recvfrom() fails,
    always receiving the correct message. The VDE code looks correct.
    Oh, well. This functionality is not critical anyway, and even one wrong blink
    every now and then would not be serious. Anyway, this seems to work perfectly.
    Go figure. *)
(*           Log.print_string ("\nWaiting for a string...\n"); *)
          (* let length =  *)
          (*   try *)
          (*     let (length, _) = recvfrom socket buffer 0 maximum_message_size [] in length *)
          (*   with Unix.Unix_error(error, string1, string2) -> begin *)
          (*     Log.printf "SSSSSS recvfrom() failed: %s (\"%s\", \"%s\").\n" (Unix.error_message error) string1 string2; flush_all ();               *)
          (*     let message = String.sub buffer 0 (maximum_message_size - 1) in *)
          (*     Log.printf "SSSSSS the possibly invalid message is >%s<\n" message; *)
          (*     0; *)
          (*   end *)
          (*   | e -> begin *)
          (*     Log.printf "SSSSSS recvfrom() failed with a non-unix error: %s.\n" (Printexc.to_string e); flush_all (); *)
          (*     0; *)
          (*   end in *)
          (* try *)
          (*   let (id, port) =  *)
          (*     Scanf.sscanf message "%i %i" (fun id port -> (id, port)) *)
          (*   in *)
          (*   self#flash ~id ~port (); *)
          (* ==== End of the reasonable version ==== *)
          (* ==== Beginning of the unreasonable version ==== *)
          (* Wait for a datagram, but never longer than what is left of the current flush
             period: a burst which stops must still get its last LED lit. Nothing pending means
             nothing to wake up for, hence the unbounded wait (negative timeout). *)
          let waiting_time =
            if !pending = [] then (-1.0) else
            let left = flush_interval -. ((Unix.gettimeofday ()) -. !last_flush) in
            if left > 0.0 then left else 0.0
          in
          let readable =
            try (match Unix.select [socket] [] [] waiting_time with ([], _, _) -> false | _ -> true)
            with _ -> false
          in
          if not readable then flush_pending () else begin
          (try
            ignore (Unix.recvfrom socket buffer 0 maximum_message_size [])
          with _ -> ());
          let length = try Bytes.index buffer '\n' with _ -> 0 in
          let message = (Bytes.sub buffer 0 length) |> Bytes.to_string in
          (* Since episode 11 this [try] enclosed the two flashes as well as the parsing, so any
             failure of theirs was reported as "can't understand the message" -- 433 lines of it
             in the bug report which led here, all of them lying about where the problem was.
             It now guards the parsing, and nothing but the parsing: [remember] cannot raise. *)
          (try
            let id1, port1, id2, port2 =
              (** This long formatted string is passed to VDE as a cable identifier. This allows us
                  to easily understand which LEDs to work on when we receive a blinking command. *)
              Scanf.sscanf message "((id: %i; port: %i)(id: %i; port: %i))" (fun id1 port1 id2 port2 -> (id1, port1, id2, port2))
            in
            remember (id1, port1);
            remember (id2, port2)
          (* ==== End of the unreasonable version ==== *)
          with _ ->
            try
              let () = assert (Scanf.sscanf message "please-die" true) in
              (* --- *)
              Log.printf ("ledgrid_manager: Exiting the LEDgrid manager blinker thread\n");
              (* Set before closing anything: whatever happens next, the loop ends. *)
              finished := true;
              Unix.close socket;
              let _ = try Unix.unlink blinker_thread_socket_file_name with _ -> () in
              ();
            with _ ->
              Log.printf1 "ledgrid_manager: Warning: can't understand the message '%s'\n" message);
          (* --- *)
          if ((Unix.gettimeofday ()) -. !last_flush) >= flush_interval then flush_pending ()
          end
        done)
      ()

  initializer
    blinker_thread := Some self#make_blinker_thread

  (** This should be called before termination *)
  method kill_blinker_thread =
    let client_socket =
      Unix.socket Unix.PF_UNIX Unix.SOCK_DGRAM 0 in
    let client_socket_file_name =
      Filename.temp_file "blinker-killer-client-socket-" "" in
    (try Unix.unlink client_socket_file_name with _ -> ());
    Unix.bind client_socket (Unix.ADDR_UNIX client_socket_file_name);
    (* NON-BLOCKING, and this is not a micro-optimisation. This method runs in the GTK main
       thread, and the destination is a datagram socket whose only reader is the blinker thread:
       a blocking sendto on a full receive queue parks the main thread in the kernel
       (unix_wait_for_peer) with nobody left to wake it up, since the blinker is itself waiting
       for the main thread. That is, measured, how an application became impossible to quit --
       the last line of its log being the one printed just below. The coalescing installed in
       the blinker loop is what keeps that queue drained; this is the belt to its braces, and a
       "please-die" which never arrives costs nothing: the process is exiting anyway. *)
    let () = try Unix.set_nonblock client_socket with _ -> () in
    Log.printf "ledgrid_manager: Sending the message \"please-die\" to the blinker thread...\n";
    let message = Bytes.of_string "please-die" in
    let rec try_to_send attempts_left =
      let outcome =
        try
          let () =
            ignore (Unix.sendto
                      client_socket
                      message
                      0
                      ((Bytes.length message))
                      []
                      (Unix.ADDR_UNIX blinker_thread_socket_file_name))
          in
          None
        with e -> Some e
      in
      match outcome with
      | None -> Log.printf "ledgrid_manager:   Ok.\n"
      | Some _ when attempts_left > 0 ->
          let () = Thread.delay 0.02 in
          try_to_send (attempts_left - 1)
      | Some e ->
          Log.printf1
            "ledgrid_manager: the message \"please-die\" could not be delivered (%s); the blinker thread is left to die with the process.\n"
            (Printexc.to_string e)
    in
    (* Ten attempts, 20 ms apart: 200 ms at the very worst, and never an unbounded wait. *)
    let () = try_to_send 10 in
    (* Make sure this arrives right now: *)
(*     flush_all (); *)
(*     Thread.join (self#blinker_thread); *)
    Log.printf "ledgrid_manager: Ok, the blinker thread has exited now.\n";
    (try Unix.unlink client_socket_file_name with _ -> ());
    (try Unix.unlink blinker_thread_socket_file_name with _ -> ());
(*     Thread.kill self#blinker_thread *)
end;;

(** There must be exactly one instance of ledgrid_manager: *)
let the_one_and_only_ledgrid_manager =
  new ledgrid_manager;;
