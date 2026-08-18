(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008, 2009  Luca Saiu
   Copyright (C) 2007, 2009, 2010, 2013  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2009, 2010, 2013  Université Paris 13

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


(** Some modules for managing the virtual network *)

(* --- *)
module Log = Marionnet_log
module Option = Ocamlbricks.Option
module ListExtra = Ocamlbricks.ListExtra
module StringExtra = Ocamlbricks.StringExtra
module StrExtra = Ocamlbricks.StrExtra
module QueueExtra = Ocamlbricks.QueueExtra
module UnixExtra = Ocamlbricks.UnixExtra
module MutexExtra = Ocamlbricks.MutexExtra
module Recursive_mutex = MutexExtra.Recursive
module Oomarshal = Ocamlbricks.Oomarshal
module Cortex = Ocamlbricks.Cortex
module Counter = Ocamlbricks.Counter
module Forest = Ocamlbricks.Forest
module Xforest = Ocamlbricks.Xforest
(* --- *)
open Gettext;;
let spr fmt = Printf.sprintf fmt
(* --- *)

(* `World_bridge is the LAN bridge (its internal name is kept: it is written in the .mar
   files), `Nat_bridge the private bridge Marionnet builds for itself (work-stream
   modernisation-world-bridge, episode 7a.3.b). *)
type devkind = [ `Machine | `Hub | `Switch | `Router | `World_gateway | `World_bridge | `Nat_bridge | `Cloud ] ;;

type nodename   = string ;;

(** Examples: "eth0", "port3" *)
type receptname = string ;;

type name   = string ;;
type label  = string ;;
let nolabel = "";;

(** iconsize may be "small", "med", "large" or "xxl". *)
type iconsize = string ;;

(** A structured record for an adjustment automatically applied while deserializing an
    old project (see the [remap_*_at_import] methods and [state#open_project_async]): a
    short [summary] line, always shown, a longer [detail] revealed on demand, and a
    [severity] telling a harmless switch (`Info) apart from a lossy drop/removal
    (`Warning). *)
type import_warning = {
  iw_summary  : string;
  iw_detail   : string;
  iw_severity : [ `Info | `Warning ];
}
;;

(** Flatten a structured import warning into a single human-readable line. Used on the
    project-loading error path, where warnings are appended to the exception message,
    and for logging. *)
let string_of_import_warning (w:import_warning) : string =
  match w.iw_detail with
  | "" -> w.iw_summary
  | d  -> Printf.sprintf "%s (%s)" w.iw_summary d
;;

(** {2 Classes} *)

(** The automaton state of a component. The invariant "no active state without a simulation
    object, no simulation object without an active state" is carried by the type itself:
    [DeviceOn] with no device is not representable. *)
module Simulated_device = struct

  type 'parent state =
    | No_device                                       (** *)
    | Off      of 'parent Simulation_level.device     (** *)
    | On       of 'parent Simulation_level.device     (** *)
    | Sleeping of 'parent Simulation_level.device     (** *)
    (* Inherited from Simulation_level.device (simulation_level.mli:265): it must be stated
       explicitly here, otherwise the .mli would declare a less constrained type: *)
    constraint 'parent = < get_name : string; .. >

  (** For debugging. Faithful translation of constructors. The strings are the historical
      ones, so that logs remain comparable with the ones of previous episodes: *)
  let to_string = function
    | No_device   -> "NoDevice"
    | Off      _  -> "DeviceOff"
    | On       _  -> "DeviceOn"
    | Sleeping _  -> "DeviceSleeping"

  (** Not a faithful conversion but the icon file name suffix, as in
      [ico.<kind>.<suffix>.<size>.png]. [No_device] maps to "off" because the sketch is
      sometimes built in this state (this reproduces the former catch-all case): *)
  let icon_suffix = function
    | On       _ -> "on"
    | Sleeping _ -> "pause"
    | Off _ | No_device -> "off"

  (** The simulation object, if any: *)
  let device_opt = function
    | No_device -> None
    | Off d | On d | Sleeping d -> Some d

end

exception ForbiddenTransition;;
let raise_forbidden_transition msg =
 Log.printf1 "ForbiddenTransition raised in %s\n" msg;
 raise ForbiddenTransition
;;

(** This represents the current state of a simulated device (as per
    network_simulation.ml) and enables easy high-level state transitions which
    conveniently hide the complexity of managing switches and cables; when the
    user tries to invoke any forbidden state transition an exception is
    raised. *)
class virtual ['parent] simulated_device () = object(self)

  method virtual add_destroy_callback : unit Lazy.t -> unit

  initializer
    self#add_destroy_callback (lazy self#destroy_my_simulated_device);

  (** We have critical sections here: *)
  val mutex = Recursive_mutex.create ()

  (** The current automaton state. It carries the device implementing the object in the
      simulated network, when there is one: this single field replaces the former pair
      (automaton_state, simulated_device), whose invariant was only maintained by hand. *)
  val state : 'parent Simulated_device.state ref = ref Simulated_device.No_device

  (** Has this component been started at least once since Marionnet was launched? Written by
      [startup_right_now] and never reset — powering off a device does not un-run it. Read by
      [has_left_traces] below (exam locks, journalisation-profonde episode 22): a switch or a hub
      keeps no disk state at all, so the states treeview cannot answer for them, yet a switch
      which has run has written its <name>-rc_config.log in the project directory (episode 4). *)
  val mutable ever_started : bool = false

  (* Note: no public accessor returns [!state] itself. Its type mentions ['parent], and
     [cable.ml] instantiates ['parent] with its own (recursively defined) object type: an
     exposed method of type ['parent Simulated_device.state] would make that type recursive
     in a way the [let rec ... and cable = ...] of cable.ml cannot solve. The state is
     therefore only readable through the projections below and the [can_*] methods. *)

  (** This string will be used to select the good icon for the dot sketch. *)
  method icon_suffix_of_state = Simulated_device.icon_suffix !state

  (** For debugging. Failthful translation of constructors: *)
  method state_as_string = Simulated_device.to_string !state

  method virtual get_name : string

  method get_hublet_process_of_port index =
    match Simulated_device.device_opt !state with
    | Some (sd) -> sd#get_hublet_process_of_port index
    | None      -> failwith "looking for a hublet when its device is non-existing"

  (* Where a script can ask this component what it knows *now*, as opposed to what it wrote down
     ([hostfs_directory_if_any] and [rc_journal_file_if_any] on [component] below). Episode 5 of
     `journalisation-profonde': a switch keeps tables no file ever receives — which ports are up,
     which MAC it learnt on which one, which VLAN is forwarding — and vde_switch publishes them
     on its management socket. Every other kind answers [None], and so does a switch in every
     state but [On]: the socket exists only while the process runs, and a suspended one
     (SIGSTOP'ed) would not answer at all — the reader would simply time out. Hence the name,
     [_if_running] rather than [_if_any], and hence the match on the state rather than on
     [Simulated_device.device_opt]: the device object is there while the component is Off too.
     It lives here, and not on [component] where its two cousins are, because *here* is where
     the state is: [component] does not inherit this class, and the instance variable is not
     part of the interface (user_level.mli), so no subclass in another module could read it.
     No kind redefines it: [get_management_socket_name] already answers [None] for all of them
     but the switch (simulation_level.ml). *)
  method management_socket_if_running : string option =
    let open Simulated_device in
    match !state with
    | On d -> d#get_management_socket_name
    | No_device | Off _ | Sleeping _ -> None

  (** Create a new simulated device according to the current status *)
  method virtual make_simulated_device : 'parent Simulation_level.device

  (** Return the list of cables directly linked to a port of self as an endpoint.
      This is needed so that simulated cables can be automatically started/destroyed
      as soon as both their endpoints are created/destroyed *)
  method private get_involved_cables = []

  (** Return true iff hublet processes are currently existing. This is only meaningful
      for devices which can actually have hublets *)
  method has_hublet_processes =
    let open Simulated_device in
    match !state with No_device -> false | Off _ | On _ | Sleeping _ -> true

  method private enqueue_task_with_progress_bar verb thunk =
    let text = verb ^ " " ^ self#get_name in
    let progress_bar = ref None in
    Task_runner.the_task_runner#schedule
      ~name:text
      (fun () ->
        (try
          progress_bar := Some (Simple_dialogs.make_progress_bar_dialog ~title:text ());
          thunk ();
        with e -> begin
          Log.printf "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n";
          let message =
            Printf.sprintf "enqueue_task_with_progress_bar: %s %s failed (%s)"
              verb self#get_name (Printexc.to_string e) in
          Log.printf1 "%s\n" message;
          Simple_dialogs.warning message message ();
          Log.printf "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n";
        end));
    Task_runner.the_task_runner#schedule
      ~name:("Destroy the progress bar for \"" ^ text ^ "\"")
      (fun () ->
        match !progress_bar with
          Some progress_bar ->
            Simple_dialogs.destroy_progress_bar_dialog progress_bar
        | None ->
            assert false)

  method create =
    (* This is invisible for the user: no progress bar here *)
    Task_runner.the_task_runner#schedule ~name:("create "^self#get_name) (fun () -> self#create_right_now)

  method (*private*) destroy_my_simulated_device =
    Log.printf1 "component \"%s\": destroying my simulated device.\n" self#get_name;
    (* This is invisible for the user: no progress bar here *)
    Task_runner.the_task_runner#schedule ~name:("destroy "^self#get_name)(fun () -> self#destroy_right_now)

  method startup =
    self#enqueue_task_with_progress_bar (s_ "Starting") (fun () -> if self#can_startup then    self#startup_right_now)

  method suspend =
    self#enqueue_task_with_progress_bar (s_ "Suspending") (fun () -> if self#can_suspend then self#suspend_right_now)

  method resume =
    self#enqueue_task_with_progress_bar (s_ "Resuming") (fun () -> if self#can_resume then self#resume_right_now)

  method gracefully_shutdown =
    self#enqueue_task_with_progress_bar (s_ "Stopping") (fun () -> if self#can_gracefully_shutdown then self#gracefully_shutdown_right_now)

  method gracefully_restart =
    (* The [begin…end] is required: [;] binds less tightly than [if/then/else], so without
       it the guard would only protect [self#gracefully_shutdown] and the "Restarting" task
       would be scheduled even on an already stopped component. *)
    if not self#can_gracefully_shutdown then () else begin (* continue *)
    self#gracefully_shutdown;
    self#enqueue_task_with_progress_bar
      (s_ "Restarting")
      (fun () ->
         Thread.delay 7.; (* Ugly: to prevent a killer signal (all this part must be rewritten with Cortex_lib as soon as possible!!) *)
         if self#can_startup then self#startup_right_now)
    end

  method poweroff =
    self#enqueue_task_with_progress_bar (s_ "Shutting down") (fun () -> if self#can_poweroff then self#poweroff_right_now)

  method (*private*) create_right_now =
    Recursive_mutex.with_mutex mutex
      (fun () ->
        Log.printf2 "About to create the simulated device %s: it's connected to %d cables.\n"
          self#get_name
          (List.length (self#get_involved_cables));

        let open Simulated_device in
        match !state with
        | No_device ->
	    ( state := Off (self#make_simulated_device);
	      Sketch.refresh_sketch (); (* the device icon switches from "no device" to "off" *)
	      (* An endpoint for cables linked to self was just added; we need to start some cables. *)
	      ignore (List.map
			(fun cable ->
			   Log.printf1 "Working on cable %s\n" (cable#show "");
			   let () = cable#increment_alive_endpoint_no in ())
			(self#get_involved_cables)))

        | (Off _ | On _ | Sleeping _) as s ->
            raise_forbidden_transition
              (Printf.sprintf "create_right_now: from %s" (to_string s)))

  (** The unit parameter is needed: see how it's used in simulated_network: *)
  method private destroy_because_of_unexpected_death () =
    Log.printf1 "You don't deadlock here %s, do you? -1\n" self#get_name;
    Recursive_mutex.with_mutex mutex
      (fun () ->
        Log.printf1 "You don't deadlock here %s, do you? 0\n" self#get_name;
        (try
          self#destroy_right_now
        with e -> begin
          Log.printf1 "WARNING: destroy_because_of_unexpected_death: failed (%s)\n"
            (Printexc.to_string e);
        end;
          Sketch.refresh_sketch ())); (* the state may have changed, successfully or not *)

  method (*private*) destroy_right_now =
    Recursive_mutex.with_mutex mutex
      (fun () ->
        Log.printf1 "About to destroy the simulated device %s \n" self#get_name;
        let open Simulated_device in
        match !state with
        | On _ | Sleeping _ ->
             Log.printf1
               "  (destroying the on/sleeping device %s. Powering it off first...)\n"
               self#get_name;
             self#poweroff_right_now; (* non-gracefully *)
             self#destroy_right_now
        | No_device ->
            Log.printf1
             "  (destroying the already 'no-device' device %s. Doing nothing...)\n"
             self#get_name;
            () (* Do nothing, but don't fail. *)
        | Off d ->
            ((* An endpoint for cables linked to self was just added; we
                may need to start some cables. *)
             Log.printf1
               "  (destroying the off device %s: decrementing its cables rc...)\n"
               self#get_name;
             List.iter
               (fun cable ->
                 Log.printf1 "Unpinning the cable %s " (cable#show "");
                 let () = cable#decrement_alive_endpoint_no in
                 Log.printf1 ("The cable %s was unpinned with success\n") (cable#show "");
                 )
               self#get_involved_cables;
             Log.printf1 "  (destroying the simulated device implementing %s...)\n" self#get_name;
             d#destroy; (* This is the a method from some object in Simulation_level *)
             state := No_device;
             Sketch.refresh_sketch ();
             Log.printf1 "We're not deadlocked yet (%s). Great.\n" self#get_name)
        );
    Log.printf1 "The simulated device %s was destroyed with success\n" self#get_name


  method (*private*) startup_right_now =
    Recursive_mutex.with_mutex mutex
      (fun () ->
        (* Don't startup ``incorrect'' devices. This is currently limited to cables of the
           wrong crossoverness which the user has defined by mistake: *)
        if self#is_correct then begin
          Log.printf1 "Starting up the device %s...\n" self#get_name;
          let open Simulated_device in
          match !state with
          | No_device ->
             (Log.printf1 "Creating processes for %s first...\n" self#get_name;
              self#create_right_now;
              Log.printf1 "Processes for %s were created...\n" self#get_name;
              self#startup_right_now
              )

          | Off d ->
             (d#startup;  (* This is the a method from some object in Simulation_level *)
              state := On d;
              ever_started <- true;
              Sketch.refresh_sketch ();
              Log.printf1 "The device %s was started up\n" self#get_name
              )

          | On _ ->
              Log.printf1 "startup_right_now: called in state %s: nothing to do.\n" (self#state_as_string)

          | Sleeping _ as s ->
              raise_forbidden_transition
                (Printf.sprintf "startup_right_now: from %s" (to_string s))
        end else begin
          Log.printf1 "REFUSING TO START UP the ``incorrect'' device %s!!!\n" self#get_name
        end)

  method (*private*) suspend_right_now =
    Recursive_mutex.with_mutex mutex
      (fun () ->
        Log.printf1 "Suspending up the device %s...\n" self#get_name;
        let open Simulated_device in
        match !state with
        | On d ->
           (d#suspend; (* This is the a method from some object in Simulation_level *)
            state := Sleeping d;
            Sketch.refresh_sketch ())
        | (No_device | Off _ | Sleeping _) as s ->
            raise_forbidden_transition
              (Printf.sprintf "suspend_right_now: from %s" (to_string s)))

  method (*private*) resume_right_now =
    Recursive_mutex.with_mutex mutex
      (fun () ->
        Log.printf1 "Resuming the device %s...\n" self#get_name;
        let open Simulated_device in
        match !state with
        | Sleeping d ->
           (d#resume; (* This is the a method from some object in Simulation_level *)
            state := On d;
            Sketch.refresh_sketch ())

        | (No_device | Off _ | On _) as s ->
            raise_forbidden_transition
              (Printf.sprintf "resume_right_now: from %s" (to_string s)))

  method (*private*) gracefully_shutdown_right_now =
    Recursive_mutex.with_mutex mutex
      (fun () ->
        let current_state = self#state_as_string in
        (Log.printf2 "* Gracefully shutting down the device %s (from state: %s)...\n"
          self#get_name
          current_state);
        let open Simulated_device in
        match !state with
        | On d ->
           (d#gracefully_shutdown; (* This is the a method from some object in Simulation_level *)
            state := Off d;
            Sketch.refresh_sketch ())

        | Sleeping _ ->
           (self#resume_right_now;
            self#gracefully_shutdown_right_now)

        | No_device | Off _ ->
            Log.printf1 "gracefully_shutdown_right_now: called in state %s: nothing to do.\n" (self#state_as_string))

  method (*private*) poweroff_right_now =
    Recursive_mutex.with_mutex mutex
      (fun () ->
        Log.printf1 "Powering off the device %s...\n" self#get_name;
        let open Simulated_device in
        match !state with
        | On d ->
           (d#shutdown; (* non-gracefully *)
            state := Off d;
            Sketch.refresh_sketch ())

        | Sleeping _ ->
            (self#resume_right_now;
             self#poweroff_right_now)

        | No_device | Off _ ->
            Log.printf1 "poweroff_right_now: called in state %s: nothing to do.\n" (self#state_as_string))

  (* ==== THE PREDICATES BELOW ARE READ *WITHOUT* THE MUTEX, ON PURPOSE ====
     Rule (episode 4c of docs/pilotage-par-script.md): THE GTK MAIN THREAD NEVER TAKES A
     COMPONENT MUTEX. Every reader of these predicates runs in that thread — the "Modify",
     "Remove", "Startup"... dynlists of the eight components, the control server
     (control_server.ml, [eligibility_of_node]), the global dialogs of state.ml, the treeview
     of marionnet.ml — and they all read a boolean to fill a menu or an answer.

     Until episode 4c each of them was wrapped in [Recursive_mutex.with_mutex mutex], which
     closed a deadlock cycle, captured twice under gdb and reproduced deterministically:
       - the `task_runner' thread holds this mutex in [startup_right_now] below and waits for
         the GTK thread ([show_device_ledgrid] is a GMain_actor.apply_extract, and
         [Sketch.refresh_sketch] goes to the same place);
       - meanwhile the GTK thread evaluates one of these predicates and waits for the mutex.
     Each waits for what the other holds; the freeze is permanent, and the control channel was
     not the only way in — unrolling a per-component menu during a startup did it too.

     Removing the mutex here loses nothing, because it was never protecting anything:
       (a) the body is a single read of [!state] (one reference cell, an atomic read: Marionnet
           runs threads, not domains) followed by a match on its constructor. There is no
           compound invariant to keep — nothing else is read alongside;
       (b) the serialisation it seemed to give was an illusion anyway: the mutex is released
           before the caller acts on the answer, so [can_startup] answering true has always
           been a hint, never a promise (which is precisely why the transition methods of the
           model are themselves guarded, and why the control server answers `accepted', never
           `done').
     In short: an interlock that guaranteed nothing, at the price of freezing the application.
     The dual rule — never call the GTK thread synchronously while holding a component mutex —
     remains the right discipline for new code, but it is not what makes this safe: the GTK
     thread no longer takes the mutex at all, so it can no longer be part of a cycle. Same
     reasoning as ledgrid_manager.ml (episode 15 of docs/refonte-automate-composants.md),
     applied the other way round: there the mutex became the main thread's alone, here it
     becomes everyone's but the main thread's. *)

  (** Return true iff the current state allows the user to 'startup' the device from the GUI. *)
  method can_startup =
    let open Simulated_device in
    (match !state with No_device | Off _ -> true | On _ | Sleeping _ -> false)

  (** Return true iff the current state allows the user to 'shutdown' a device from the GUI. *)
  method can_gracefully_shutdown =
    let open Simulated_device in
    (match !state with On _ | Sleeping _ -> true | No_device | Off _ -> false)

  (** Return true iff the current state allows the user to 'power off' a device from the GUI.
      Exam locks (journalisation-profonde, episode 22): a brutal power cut is not offered at all
      in exam mode. The exam archiving of a session — report, command history, console, terminal
      into the [documents] treeview, hence into the .mar handed in — hangs on ONE path,
      [gracefully_shutdown_right_now] (machine.ml, router.ml); a poweroff bypasses it, so it
      throws the copy away. Nothing is lost by refusing it: the graceful shutdown remains, and
      the internal paths which really need a brutal cut ([destroy_right_now], the fallback of an
      aborted shutdown) call [poweroff_right_now] directly, without consulting this predicate. *)
  method can_poweroff =
    let open Simulated_device in
    Initialization.are_we_allowed_to_poweroff &&
    (match !state with No_device | Off _ -> false | On _ | Sleeping _ -> true)

  (** Return true iff the current state allows the user to 'suspend' a device from the GUI. *)
  method can_suspend =
    let open Simulated_device in
    (match !state with On _ -> true | No_device | Off _ | Sleeping _ -> false)

  (** Return true iff the current state allows the user to 'resume' a device from the GUI. *)
  method can_resume =
    let open Simulated_device in
    (match !state with Sleeping _ -> true | No_device | Off _ | On _ -> false)

  (** Return true iff the current state allows the user to 'modify' (edit the properties of) a
      device. Same condition as [can_startup], and for a concrete reason: the number of ports, the
      kernel or the distribution of a device whose Unix processes are alive cannot be changed under
      its feet. *)
  method can_modify =
    let open Simulated_device in
    (match !state with No_device | Off _ -> true | On _ | Sleeping _ -> false)

  (** Return true iff the current state allows the user to 'destroy' a device.
      Until episode 4b of docs/pilotage-par-script.md this rule lived in the GUI *only* — on the
      seven node components, without exception, "Remove" and "Modify" filtered the menu on
      [can_startup] — and the model had no predicate at all. Anything calling #destroy directly,
      typically a script driving the model through the control server, would therefore have
      destroyed a running device together with its live Unix processes. The guard now belongs to
      the model, and the GUI reads it like everybody else (§ 4.10).
      Kept distinct from [can_modify] although the two conditions coincide here: they denote two
      different permissions, and cables (cable.ml) already override both to a constant true while
      the very notion of [can_startup] has no reader left for them. *)
  method can_destroy =
    let open Simulated_device in
    (Initialization.are_we_allowed_to_delete || not self#has_left_traces) &&
    (match !state with No_device | Off _ -> true | On _ | Sleeping _ -> false)

  (** Has this component produced anything a corrector could want to read? Exam locks
      (journalisation-profonde, episode 22): removing a component destroys its disk states, its
      hostfs and therefore its journals, so in exam mode it is refused — but only for a component
      which has actually run. One which was never started has produced nothing, and a student
      building their own topology must be able to undo a mistake.

      Two sources, because neither answers alone:
      - the states treeview is *persisted* in the .mar, so it still answers after the project has
        been closed and reopened, which no in-memory flag can do. The threshold is [> 1] and not
        [> 0] because [add_device] (treeview_history.ml) inserts a blank root row as soon as the
        component is created — measured, not assumed;
      - [ever_started] covers the current session and, above all, the kinds which keep no disk
        state at all (switch, hub, cloud, gateways): the states treeview knows nothing about them
        although a switch which has run has written its rc journal.
      Cables are out of this: [cable.ml] overrides [can_destroy] to a constant true, on purpose —
      unplugging a wire while the network runs is a legitimate gesture, often the exercise itself. *)
  method has_left_traces =
    ever_started ||
    (try ((Treeview_history.extract ())#number_of_states_with_name self#get_name) > 1
     with _ -> false)

  (** 'Correctness' support: this is needed so that we can refuse to start incorrectly
      placed components such as Ethernet cables of the wrong crossoverness, which the user
      may have created by mistake: *)
  method is_correct = true (* redefined in cables *)

end;;


(* *************************** *
      class common
 * *************************** *)

(** The shared generator for all unique ids: *)
let generator = Counter.make_int_generator ();;

(** General-purpose class with common fields as
    - an automatically generated identifier
    - a (mutable) name; i.e. valid string identifier
    - a (mutable) label (string) not containing '<' and '>' (for prevent conflict with dot)
*)
class id_name_label = fun ?(name="noname") ?(label="") () ->

  (* Some checks over used name and label *)
  let wellFormedLabel x = not (StrExtra.First.matchingp (Str.regexp ".*[><].*") x) in

  let check_name  x =
  	if not (StrExtra.Class.identifierp x)
       	then failwith ("Setting component "^name^": invalid name")
        else x in

  let check_label x =
  	if not (wellFormedLabel x)
        then failwith ("Setting component "^name^": invalid label")
        else (StringExtra.strip x) in

  object (self)

  (** A component has an immutable identifier. *)
  val id : int = generator ()
  method id = id

  (** A component has a mutable name. *)
  val mutable name : string = check_name name

  method get_name   = name
  method set_name x = name <- check_name x

  (* A shortcut for get_name *)
  method      name  = name

  (** A component has a label, usually used by dot drawing the network graph. *)
  val mutable label : string = check_label label

  method get_label : string = label
  method set_label x = label <- check_label x

end;;

(* *************************** *
        class component
 * *************************** *)

(* *************************** *
      Run-commands (rc) files
 * *************************** *)

(** Work-stream `migration-marshal-to-text', episode 5.

    The startup configuration of a machine, a switch or a router — its "rc" file — is a shell
    script: arbitrary bytes, frequently long and multi-line. Until `v3 the field travelled
    [Marshal]ed *inside* a forest attribute, because an attribute is a [string] while the field
    is a pair. Undoing that nesting by putting the script itself in the attribute would only
    trade one opacity for another: a wall of escaped text, turning into a base64 blob for the
    *whole* script as soon as one byte is not UTF-8.

    So the script goes to a file of its own under states/, exactly as the documents of
    treeview_documents.ml do (states/document-XXXXXXXXX), and the forest carries its basename
    next to the boolean. What the user wrote stays readable, diffable and editable with an
    ordinary text editor, which is the point of the whole work-stream.

    Two properties this module exists to hold:

    - the basename is allocated at *construction* time and without any I/O, because [#to_tree]
      must stay pure: the control server calls it on every [get] (control_server.ml:892), and a
      [to_tree] that created a file would leak one per query;
    - writing therefore happens once per save, in [network#save_rc_files], which the caller runs
      just before serializing the forest. That same pass sweeps the files no live component
      claims any more — a component destroyed since the last save would otherwise leave its
      script behind, and the .mar is built from the working directory as it stands. *)
module Rc_files = struct

 let prefix = "rc_config."

 (* Unique within the process, which is all that is needed: a project is written by a single
    Marionnet, and [remove_orphans] below sweeps whatever another one may have left. *)
 let fresh_basename : unit -> string =
   let counter = ref 0 in
   fun () ->
     let () = incr counter in
     Printf.sprintf "%s%05d%04d" prefix (Random.int 100000) !counter

 let pathname ~states_directory ~basename = Filename.concat (states_directory) (basename)

 (* Failures are logged, not raised: a save must not be aborted by one unwritable script, and
    the caller (a [#save_rc_files]) has nothing better to do with the exception. The loss is
    visible — an empty or missing file — where a raised exception would abort the whole save. *)
 let write ~states_directory ~basename ~content =
   let file = pathname ~states_directory ~basename in
   try UnixExtra.put file content with e ->
     Log.printf2 "Rc_files.write: cannot write %s: %s\n" file (Printexc.to_string e)

 (* The empty string on failure, for the same reason and with the same visibility: the field
    keeps the value a fresh component would have. *)
 let read ~states_directory ~basename =
   let file = pathname ~states_directory ~basename in
   try UnixExtra.cat file with e ->
     let () = Log.printf2 "Rc_files.read: cannot read %s: %s\n" file (Printexc.to_string e) in
     ""

 let remove_orphans ~states_directory ~(alive : string list) =
   try
     Array.iter
       (fun basename ->
          if (String.starts_with ~prefix basename) && not (List.mem basename alive) then begin
            let file = pathname ~states_directory ~basename in
            let () = Log.printf1 "Rc_files.remove_orphans: removing %s\n" file in
            try Unix.unlink file with _ -> ()
            end)
       (Sys.readdir states_directory)
   with e ->
     Log.printf1 "Rc_files.remove_orphans: %s\n" (Printexc.to_string e)

end (* module Rc_files *)


(** A component may be a node (machine or device) or a cable (direct, crossover or nullmodem).
    It's simply a thing with a name and an associated (mutable) label. *)
class virtual component =
fun ~(network:< .. >)
    ?(name="noname")
    ?(label="") () ->

  object (self)
  inherit id_name_label ~name ~label ()
  inherit Xforest.interpreter ()

  (** The global network. It's a pain to have to access this via a global variable
      defined in Marionnet *)
  val network = network

  method virtual can_suspend : bool
  method virtual can_resume  : bool

  method virtual suspend : unit
  method virtual resume  : unit

  (* Where the host can read what the guest writes. The hostfs directory is a *host* directory
     mounted as /mnt/hostfs in the guest (simulation_level.ml:1235-1251), which makes it the
     return channel of a startup configuration (rc_config): a scenario that logs into
     /mnt/hostfs/ is readable from here without touching the guest images. Only machines and
     routers have one — a switch's rc file is a set of vdeterm commands handed to vde_switch
     (simulation_level.ml:398-409), and nothing comes back from it — hence the option, and hence
     its declaration on the common ancestor: the control server (rc-get/rc-set) asks any
     component without knowing its kind, and [None] is an answer, not a hole.
     REDEFINED in machine.ml and router.ml, the two kinds that own a hostfs directory. It is
     redefined *there* rather than in [virtual_machine_with_history_and_ifconfig], where the
     method would have been at home: that mixin does not inherit [component], so defining it
     there makes the two definitions meet by multiple inheritance in machine/router — which is
     warning 7, an error in this build. Two explicit [method!] cost less than silencing it. *)
  method hostfs_directory_if_any : string option = None

  (* Where *Marionnet itself* writes what it did with the rc of this component, for the kinds
     which have an rc but no guest to write it down. Episode 4 of `journalisation-profonde': a
     switch's rc is a set of vdeterm commands sent to vde_switch over its management socket, and
     until that episode the answers were thrown away — a faulty VLAN command failed in complete
     silence. Now they are journalled, and since a switch has no hostfs the file has to live
     somewhere else: the project's working directory (see switch.ml, [rc_journal_path]).
     [None] here means "this kind writes no such journal", which is an answer, not a hole: the
     control server ([log]) asks any component without knowing its kind, exactly as it does for
     [hostfs_directory_if_any] above. The two are mutually exclusive by construction — a machine
     has a guest which writes its own journal, a switch has us. REDEFINED in switch.ml only. *)
  method rc_journal_file_if_any : string option = None

  (* Which kernels the component's filesystem declares as supported (SUPPORTED_KERNELS in its
     .conf, read by Disk.virtual_machine_installations#supported_kernels_of). Only machines and
     routers have a filesystem, hence the option — [None] means "this kind has no kernel", which
     is an answer, not a hole. Same reason as above for declaring it here and REDEFINING it in
     machine.ml and router.ml (multiple inheritance, warning 7).
     Read-only on purpose: the model still accepts any *installed* kernel (check_kernel below),
     because a .mar may legitimately reference a kernel that escapes SUPPORTED_KERNELS and
     tightening the setter would make such a project unloadable. The refusal lives in the control
     server, which owns the message; this method is what lets it speak. *)
  method supported_kernels_if_any : string list option = None

  (* Where this component's rc files live (see [Rc_files] above): the states/ subdirectory of
     the project, the very one treeview_documents.ml writes its documents into. Taken from the
     network rather than from [Treeview_history], which only machines and routers reach — a
     switch has an rc file too. *)
  method states_directory : string =
    Filename.concat (network#project_root_pathname) "states"

  (* The rc scripts this component owns, as (basename, content) pairs: the basename is what the
     forest publishes, the content is what lives in the model. Nothing to do for the kinds which
     have none, hence the empty default; REDEFINED in machine.ml, switch.ml and router.ml, with
     [#set_rc_content] below — the two others derive from this one, so the files a component
     WRITES and the basenames it PUBLISHES can no longer come from two separate walks and drift
     apart. No I/O here: [#to_tree] and the control server both call it (episode 6 of
     `migration-marshal-to-text'), the latter on every rc-get. *)
  method rc_contents : (string * string) list = []

  (* Replace the content of one of them, addressed by the basename the forest publishes. Answers
     [false] when the basename is none of this component's: a caller which asked for a write must
     be able to tell that nothing happened, where a [unit] would have lost the refusal. This is
     how the control server writes a startup configuration since episode 6 — the content is no
     longer an attribute, so [#eval_forest_attribute] cannot carry it. REDEFINED alongside
     [#rc_contents]. *)
  method set_rc_content ~(basename:string) ~(content:string) : bool =
    let _ = (basename, content) in false

  (* Write the rc files this component owns. Called by [network#save_rc_files] just before the
     forest is serialized, never by [#to_tree]. *)
  method save_rc_files : unit =
    List.iter
      (fun (basename, content) ->
         Rc_files.write ~states_directory:(self#states_directory) ~basename ~content)
      self#rc_contents

  (* The basenames [#save_rc_files] has just written, i.e. the files states/ must keep. *)
  method rc_file_basenames : string list = List.map fst self#rc_contents

end;;


(* *************************** *
          class port
 * *************************** *)

(** Essentially a triple (user_name, user_index, internal_index) *)
class port
  ~port_prefix      (* ex: "eth" or "port" *)
  ~internal_index   (* 0-based numbering *)
  ~user_port_offset
  ()
  =
  let user_index = (internal_index + user_port_offset) in
  let user_name = Printf.sprintf "%s%d" port_prefix user_index
  in
  object
    method user_name      = user_name       (* ex: port1 *)
    method user_index     = user_index      (* ex: 1 *)
    method internal_index = internal_index  (* ex: 0 *)
end;;

type defects = < duplication: float;  flip: float;  loss: float;  max_delay: float;  min_delay: float >

(** Just a container of ports: *)
class ['parent] ports_card
  ~network
  ~(parent:'parent)
  ~port_no
  ~port_prefix
  ?(user_port_offset=0)
  () =
 let () = assert (port_no >= 0) in
 let port_array =
   Array.init
     port_no
     (fun i -> new port ~port_prefix ~internal_index:i ~user_port_offset ())
 in
 let port_list = Array.to_list port_array
 in
 object (self)
  method port_no = port_no
  method port_prefix = port_prefix
  method user_port_offset = user_port_offset

  (* A project saved before a nature changed the way it names its ports still names
     them the old way, and its cables say so: the receptacle of a cable travels in the
     .mar as a NAME ("leftreceptname", cable.ml), which is resolved right here. The LAN
     bridge is the case that made this necessary (work-stream modernisation-world-bridge,
     episode 12): its single port was called "eth0" and is now the "port1" of an
     integrated switch, so the name written in an old project would be found nowhere --
     and the import of a cable swallows the exception (with _ -> false), so the cable
     would simply VANISH, in silence, from a project that used to work.
     ---
     Hence this fallback, and its two limits: it is tried only AFTER the exact lookup
     has failed (a card whose names are the ones asked for behaves exactly as before),
     and it only ever translates the old interface-like naming towards the convention
     of THIS card. Nothing is written back: the next save writes the current names, so
     the project migrates by being saved once. *)
  method private port_of_user_port_name x =
    try List.find (fun p -> p#user_name = x) port_list
    with Not_found ->
      let legacy_name =
        try Scanf.sscanf x "eth%d%!" (fun i -> Some (Printf.sprintf "%s%d" port_prefix (i + user_port_offset)))
        with _ -> None
      in
      (match legacy_name with
       | Some y when y <> x -> List.find (fun p -> p#user_name = y) port_list
       | Some _ | None -> raise Not_found)

  method internal_index_of_user_port_name x =
    (self#port_of_user_port_name x)#internal_index

  method user_port_index_of_user_port_name x =
    (self#port_of_user_port_name x)#user_index

  method user_port_name_of_internal_index i =
    (Array.get port_array i)#user_name

  method user_port_index_of_internal_index i =
    (Array.get port_array i)#user_index

  method user_port_name_list = List.map (fun x->x#user_name) port_list

  method private get_my_defects_by_index
   (port_index:int)
   (port_direction:Treeview_defects.port_direction)
   =
    let get column_header = network#defects#get_port_attribute_of
      ~device_name:((parent#get_name):string)
      ~port_prefix
      ~port_index
      ~user_port_offset
      ~port_direction
      ~column_header
      ()
    in
    object
      method loss        : float = get "Loss %"
      method duplication : float = get "Duplication %"
      method flip        : float = get "Flipped bits %"
      method min_delay   : float = get "Minimum delay (ms)"
      method max_delay   : float = get "Maximum delay (ms)"
    end

  method get_my_inward_defects_by_index (port_index:int) =
    self#get_my_defects_by_index port_index Treeview_defects.OutToIn

  method get_my_outward_defects_by_index (port_index:int) =
    self#get_my_defects_by_index port_index Treeview_defects.InToOut

end (** class ports_card *)

(** Check a candidate name for a component that already belongs to the network, i.e. a *renaming*.
    These are the two tests the GUI dialogs perform with [Gui_bricks.Ok_callback.check_name] before
    calling any [update_<kind>_with]; they are repeated here so that the *model* itself refuses a
    name before having written anything. The renaming path is destructive from its very first
    statement — it renames the defects, ifconfig and history rows and the hostfs directory — while
    the [check_name] of [id_name_label#set_name] only runs at the very end: a name refused half-way
    used to leave the rows under the new name and the component under the old one (measured
    2026-08-06, episode 4d-2b of marionnet-pilotage-par-script). Uniqueness, for its part, had no
    guard at all on this path: [network#name_exists] is read by [add_node]/[add_cable] only, and a
    renaming goes through neither, so renaming a node onto an existing name silently produced two
    homonyms — indistinguishable to anything that addresses components by name.
    Callers that can phrase a better refusal are still expected to test first (the dialogs loop on
    themselves, the control server answers a motivated error): this is their net, not their
    replacement. *)
let check_new_name ~network ~old_name new_name =
  if new_name = old_name then () else
  if not (StrExtra.Class.identifierp new_name)
    then failwith ("Renaming component "^old_name^": invalid name "^new_name)
    else
  if network#name_exists new_name
    then failwith ("Renaming component "^old_name^": the name "^new_name^" is already used in the network")
    else ()

(* *************************** *
          class node
 * *************************** *)

(** Machines and routers have MDI ports, switches and hubs have MDI_X a priori.
    Currently, devices are sold with "intelligent" ports, i.e. MDI/MDI-X. *)
type polarity = MDI | MDI_X | MDI_Auto ;;

(** A node of the network is essentially a container of ports.
    Defects may be added after the creation, using the related method. *)
class virtual node_with_ports_card = fun
   ~network
   ~name
   ?label
   ~(devkind:devkind)
   ~port_no
   ~port_prefix
   ~port_no_min
   ~port_no_max
   ?(user_port_offset=0)
   ?(has_ledgrid=false)
   () ->
   let make_ports_card ~parent ~port_no =
     new ports_card ~network ~parent ~port_no ~port_prefix ~user_port_offset ()
   in
   object (self)
   inherit component ~network ~name ?label ()
   inherit (*the parent:*) [node_with_ports_card] simulated_device ()

   (* Building constant parameters: *)
   method user_port_offset = user_port_offset
   method port_prefix = port_prefix

   val mutable ports_card = None
   initializer ports_card <- Some (make_ports_card ~parent:self ~port_no)
   method ports_card = Option.extract ports_card
   method get_port_no = self#ports_card#port_no
   method set_port_no new_port_no =
     if (new_port_no >= port_no_min) && (new_port_no <= port_no_max)
     then
       ports_card <- Some (make_ports_card ~parent:self ~port_no:new_port_no)
     else invalid_arg "node_with_ports_card#set_port_no"

   method port_no_min = port_no_min
   method port_no_max = port_no_max

   method has_ledgrid = has_ledgrid

   method virtual destroy : unit

  (** Set the two *structural* fields of a node, i.e. those that no setter alone can change:
      renaming a node also renames its treeview rows (defects for every node, ifconfig and history
      for virtual machines) and its hostfs directory, and changing the number of ports rebuilds the
      ports card and the defects sub-tree. This is the structural part of the eight
      [update_<kind>_with] methods called by the GUI dialogs, factored out so that a caller which
      knows nothing about the kind of the node (the control server) still takes the very same path
      the GUI takes. Callers are expected to check [can_modify] and the port bounds first
      ([port_no_min], [port_no_max] and [network#port_no_lower_of]). *)
   method virtual update_structural_with : name:string -> port_no:int -> unit

  (** 'Static' methods (in the sense of C++/Java). Polarity is used to decide the correct
      kind of Ethernet cable needed to connect a pair of devices: the cable should be
      crossover iff both endpoints have the same polarity: *)
   method virtual polarity : polarity

  (** The kind of the device (if the node is a device). *)
   method devkind = devkind

   method virtual string_of_devkind : string

   (* This is a default, but could be redefined: *)
   method leds_relative_subdir = self#string_of_devkind

   (** Returns an image representig the node with the given iconsize. *)
   method virtual dotImg : iconsize -> string

   (** Returns the label to use for cable representation.
       This method may be redefined (for instance in [world_bridge]). *)
   method dotLabelForEdges (receptname:string) = self#get_label

   (** Returns the port to use for cable representation.
       This method may be redefined (for instance in [world_bridge]). *)
   method dotPortForEdges (receptname:string)  = receptname

  (** A node is represented in dot with an HTML label which is a table
      with a first line containing the name, with a second line containing the node associated image (method [dotImg]),
      and, if the node has a label, a third line containing the label. With the [nodeoptions] parameter one can force,
      for example, the fontsize or fontname for both name and label :
      [ dotTrad ~nodeoptions="fontsize=8" "large" ] *)
   method dotTrad ?(nodeoptions="") (z:iconsize) =
    let label = self#label_for_dot in
    let label_line =
      if label=""
       then ""
       else "<TR><TD><FONT COLOR=\"#3a3936\">"^label^"</FONT></TD></TR>"
    in
    let fontsize   = self#dot_fontsize_statement in
    let nodeoptions = if nodeoptions = "" then "" else (nodeoptions^",") in
    begin
    self#get_name^" ["^fontsize^nodeoptions^"shape=plaintext,label=<
<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\">
  <TR><TD>"^self#get_name^"</TD></TR>
  <TR><TD PORT=\"img\"><IMG SRC=\""^(self#dotImg z)^"\"></IMG></TD></TR>
"^label_line^"
</TABLE>>];"
    end

   (* Redefined in User_level_machine as "": *)
   method dot_fontsize_statement = "fontsize=8,"

   (** Could be redefined. *)
   method label_for_dot = self#get_label

   (** make_simulated_device is defined in subclasses, not here  *)

   (* TODO: move it in the network class
     Return the list of cables of which a port of self is an endpoint: *)
   method! private get_involved_cables =
     network#get_cables_involved_by_node_name (self#get_name)
(*      List.filter (fun c->c#is_node_involved self#get_name) network#get_cable_list *)

end;; (* class node_with_ports_card *)

(* Justa an alias: *)
class type virtual node = node_with_ports_card


class virtual node_with_defects_zone ~network () =
object (self)

  method virtual defects_device_type : string
  method virtual get_name : string
  method virtual get_port_no : int
  method virtual port_prefix : string
  method virtual user_port_offset : int
  method virtual add_destroy_callback : unit Lazy.t -> unit

  (* B6 (episode 6): see the twin method of cable.ml — the existence of a row bearing the name of
     the component says nothing of the presence of its port rows, and a component silently
     inheriting a truncated entry is what made a startup fail on a component nobody had touched. *)
  method private add_my_defects =
   (network#defects:Treeview_defects.t)#ensure_device_entry
     ~device_name:self#get_name
     ~device_type:self#defects_device_type
     ~port_no:self#get_port_no
     ~port_prefix:self#port_prefix
     ~user_port_offset:self#user_port_offset
     ()

  method private destroy_my_defects =
    Log.printf1 "component \"%s\": destroying my defects.\n" self#get_name;
    network#defects#remove_subtree_by_name self#get_name;

  method private defects_update_port_no new_port_no =
    network#defects#update_port_no
      ~device_name:self#get_name
      ~port_no:new_port_no
      ~port_prefix:self#port_prefix
      ~user_port_offset:self#user_port_offset
      ()

  initializer
    self#add_my_defects;
    self#add_destroy_callback (lazy self#destroy_my_defects);

end

class virtual node_with_defects
  ~network
  ~name
  ?(label="")
  ~devkind
  ~port_no
  ~port_no_min
  ~port_no_max
  ?user_port_offset
  ~port_prefix
  ()
  =
  let network_alias = network in
  object (self)

  inherit node_with_ports_card
    ~network
    ~name
    ~label
    ~devkind
    ~port_no
    ~port_no_min
    ~port_no_max
    ~port_prefix
    ?user_port_offset
    ()
  as self_as_node_with_ports_card

  initializer
    (* TODO: the following line must be moved the a node initializer: *)
    let () = network#add_node (self :> node) in
    self#add_destroy_callback (lazy (network#del_node_by_name self#get_name));

  inherit node_with_defects_zone ~network:network_alias () as node_with_defects_zone

  method virtual dotImg : iconsize -> string

  (** Returns the label to use for cable representation.
      For devices, the port X is represented by the string "[X]". *)
  method! dotLabelForEdges (receptname:string) =
    let user_index = self#ports_card#user_port_index_of_user_port_name receptname in
    ("["^string_of_int user_index^"]")

  (** Return the string representing the port in cable representation. *
      Ignore the receptname and returns the empty string. *)
  method! dotPortForEdges (receptname:string) = ""

  (* REDEFINED: *)
  (* TODO: duplicated code *)
  method! set_name new_name =
    let old_name = self#get_name in
    if old_name <> new_name then begin
      (* Before the first write: the defects row is renamed here, the component only below. *)
      check_new_name ~network ~old_name new_name;
      network#defects#rename old_name new_name;
      self_as_node_with_ports_card#set_name new_name;
    end;

  (* REDEFINED: *)
  (* TODO: duplicated code *)
  method! set_port_no new_port_no =
    let old_port_no = self#get_port_no in
    if new_port_no <> old_port_no then begin
      node_with_defects_zone#defects_update_port_no new_port_no;
      self_as_node_with_ports_card#set_port_no new_port_no;
    end;

  method update_with ~name ~label ~port_no =
  (* No: force because the simulated device may be rebuilded with new values of other parameters *)
  (* if self#update_really_needed ~name ~label ~port_no then *)
    begin
      (* Before the first write: [destroy_my_simulated_device] *schedules* a task on the task
         runner (user_level.ml:206-209), which no later refusal could recall. *)
      check_new_name ~network ~old_name:self#get_name name;
      self#destroy_my_simulated_device;
      self#set_name name;
      self#set_port_no port_no;
      self#set_label label;
    end

  (* The structural part of update_with, for a caller that has no reason to know the label: *)
  method update_structural_with ~name ~port_no =
    self#update_with ~name ~label:self#get_label ~port_no

end;; (* class node_with_defects *)


(** Common class for hubs, switches and world_gateways
   (routers have a more specialized class): *)
class virtual node_with_ledgrid_and_defects
  ~network
  ~name
  ?(label="")
  ~devkind
  ~port_no
  ~port_no_min
  ~port_no_max
  ?user_port_offset
  ~(port_prefix:string) (* "port" or "eth" *)
  ()
  =
  let network_alias = network in
  object (self)

  inherit node_with_ports_card
    ~network
    ~name
    ~label
    ~devkind
    ~port_no
    ~port_no_min
    ~port_no_max
    ~port_prefix
    ~has_ledgrid:true
    ?user_port_offset
    ()
  as self_as_node_with_ports_card

  initializer
    (* TODO: the following line must be moved the a node initializer: *)
    let () = network#add_node (self :> node) in
    self#add_destroy_callback (lazy (network#del_node_by_name self#get_name));
    (* this is correct here: *)
    self#add_my_ledgrid;
    self#add_destroy_callback (lazy self#destroy_my_ledgrid);

  inherit node_with_defects_zone ~network:network_alias () as node_with_defects_zone

  (** Dot adjustments *)

  (** Returns an image representig the node with the given iconsize. *)
  method virtual dotImg : iconsize -> string

  (** Returns the label to use for cable representation.
      For nodes, the port X is represented by the string "[X]". *)
  method! dotLabelForEdges (receptname:string) =
    let user_index = self#ports_card#user_port_index_of_user_port_name receptname in
    ("["^string_of_int user_index^"]")

  (** Return the string representing the port in cable representation. *
      Ignore the receptname and returns the empty string. *)
  method! dotPortForEdges (receptname:string) = ""

  (** Here we also have to manage LED grids: *)
  method! private startup_right_now =
    (* Do as usual... *)
    self_as_node_with_ports_card#startup_right_now;
    (* ...and also show the LED grid: *)
    network#ledgrid_manager#show_device_ledgrid ~id:(self#id) ()


  method! private gracefully_shutdown_right_now =
    (* Do as usual... *)
    self_as_node_with_ports_card#gracefully_shutdown_right_now;
    (* ...and also hide the LED grid... *)
    network#ledgrid_manager#hide_device_ledgrid ~id:(self#id) ();


  (** Here we also have to manage LED grids: *)
  method! private poweroff_right_now =
    (* Do as usual... *)
    self_as_node_with_ports_card#poweroff_right_now;
    (* ...and also hide the LED grid... *)
    network#ledgrid_manager#hide_device_ledgrid ~id:(self#id) ();

  method ledgrid_image_directory =
   let leds_relative_subdir = self#leds_relative_subdir in
   (Initialization.Path.leds ^ leds_relative_subdir)

  (* may be redefined *)
  method ledgrid_title = self#get_name
  method virtual ledgrid_label : string

  method add_my_ledgrid =
     (* Make a new device LEDgrid: *)
     (network#ledgrid_manager:Ledgrid_manager.ledgrid_manager)#make_device_ledgrid
       ~id:(self#id)
       ~title:(self#get_name)
       ~label:(self#ledgrid_label)
       ~port_no:(self#get_port_no)
       ?port_labelling_offset:user_port_offset
       ~image_directory:self#ledgrid_image_directory
       ();
     (* Set port connection state: *)
     let busy_ports_indexes =
       network#busy_port_indexes_of_node (self :> node_with_ports_card)
     in
     ignore (List.map
               (fun port_index ->
                  (network#ledgrid_manager#set_port_connection_state
                     ~id:self#id
                     ~port:port_index
                     ~value:true
                     ()))
               busy_ports_indexes)

  method destroy_my_ledgrid : unit =
    Log.printf1 "component \"%s\": destroying my ledgrid.\n" self#get_name;
    (network#ledgrid_manager:Ledgrid_manager.ledgrid_manager)#destroy_device_ledgrid
      ~id:(self#id)
      ()

  (* REDEFINED: *)
  method! set_name new_name =
    let old_name = self#get_name in
    if old_name <> new_name then begin
      (* Before the first write: the defects row is renamed here, the component only below. *)
      check_new_name ~network ~old_name new_name;
      network#defects#rename old_name new_name;
      self_as_node_with_ports_card#set_name new_name;
    end;

  (* REDEFINED: *)
  method! set_port_no new_port_no =
    let old_port_no = self#get_port_no in
    if new_port_no <> old_port_no then begin
      node_with_defects_zone#defects_update_port_no new_port_no;
      self_as_node_with_ports_card#set_port_no new_port_no;
    end;

(*  method private update_really_needed ~(name:string) ~(label:string) ~(port_no:int) : bool =
   ((name    <> self#get_name)  ||
    (label   <> self#get_label) ||
    (port_no <> self#get_port_no))*)

  method update_with ~name ~label ~port_no =
  (* No: force because the simulated device may be rebuilded with new values of other parameters *)
  (* if self#update_really_needed ~name ~label ~port_no then *)
    begin
      (* Before the first write: [destroy_my_simulated_device] *schedules* a task on the task
         runner (user_level.ml:206-209), which no later refusal could recall. *)
      check_new_name ~network ~old_name:self#get_name name;
      self#destroy_my_simulated_device;
      self#destroy_my_ledgrid;
      self#set_name name;
      self#set_port_no port_no;
      self#set_label label;
      self#add_my_ledgrid; (* may use all previous properties (including the label) *)
    end

  (* The structural part of update_with, for a caller that has no reason to know the label: *)
  method update_structural_with ~name ~port_no =
    self#update_with ~name ~label:self#get_label ~port_no

end;;


(* ************************************* *
          class virtual_machine
   (common class for machine and router)
 * ************************************* *)

class virtual virtual_machine_with_history_and_ifconfig
  ~network
  ?epithet   (* An epithet, for instance "debian-lenny-42178" *)
  ?variant
  ?kernel    (* Again an epithet, for instance "2.6.18-ghost" *)
  ?terminal
  ~(history_icon:string)
  ~(ifconfig_device_type:string)
  ?(ifconfig_port_row_completions:Treeview_ifconfig.port_row_completions option)
  ~(vm_installations:Disk.virtual_machine_installations)
  ()
  =
  let epithet = match epithet with
   | Some x -> x
   | None   -> Option.extract vm_installations#filesystems#get_default_epithet
  in
  (* The kernel default follows the *filesystem*, exactly as the GUI dialog does
     (Gui_bricks.make_combo_boxes_of_vm_installations, gui_bricks.ml:520-522): the first kernel
     declared by the filesystem's .conf (SUPPORTED_KERNELS). The global default epithet ignores
     the distribution, so it used to build unbootable couples — a machine created without an
     explicit kernel (the control server's `add', control_server.ml) got "3.2.64-ghost" whatever
     its filesystem, and the guest never booted. The fallback keeps the old behaviour for a
     filesystem declaring no supported kernel at all. *)
  let kernel = match kernel with
   | Some x -> x
   | None   ->
       (match vm_installations#supported_kernels_of epithet with
        | (k, _) :: _ -> k
        | []          -> Option.extract vm_installations#kernels#get_default_epithet)
  in
  let terminal = match terminal with
   | Some x -> x
   | None   -> (vm_installations#terminal_manager_of epithet)#get_default
  in

  object (self)

  method virtual get_name : string
  method virtual get_port_no : int
  method virtual add_destroy_callback : unit Lazy.t -> unit

  (* -------------- *)
  initializer begin
    self#add_my_ifconfig ?port_row_completions:ifconfig_port_row_completions self#get_port_no;
    self#add_destroy_callback (lazy self#destroy_my_ifconfig);
    self#add_my_history;
    self#add_destroy_callback (lazy self#destroy_my_history);
    end
  (* -------------- *)

  (* Parameters *)
  method history_icon = history_icon
  method ifconfig_device_type = ifconfig_device_type

  method private banner =
    (Printf.sprintf "User_level.virtual_machine: setting %s: " self#get_name)

  method sprintf : 'a. ('a, unit, string, string) format4 -> 'a =
    Printf.ksprintf (fun x->self#banner^x)

  method logged_failwith : 'a 'b. ('a -> string, unit, string, string, string, string) format6 -> 'a -> 'b =
    fun fmt x ->
      let msg = Printf.sprintf ("%s" ^^ fmt) (self#banner) x in
      let () = Log.printf1 "%s\n" msg in
      failwith msg

  (** A machine has a Linux filesystem *)
  val mutable epithet : string = epithet
  initializer ignore (self#check_epithet epithet)
  method get_epithet = epithet
  method set_epithet x = (epithet <- self#check_epithet x)
  method private check_epithet x =
    match (vm_installations#filesystems#epithet_exists x) with
    | true  -> x
    | false -> self#logged_failwith "unknown filesystem %s" x

  (** A machine may have an associated initial variant: *)
  val mutable variant : string option = variant
  initializer ignore (Option.map (self#check_variant) variant)
  method get_variant = variant
  method get_variant_as_string = match variant with None -> "" | Some x -> x
  method set_variant (x:string option) = variant <- (Option.map (self#check_variant) x)
  method private check_variant x =
   let v = vm_installations#variants_of epithet in
   match v#epithet_exists x with
   | true -> x
   | false -> self#logged_failwith "the variant \"%s\" is not available" x

 method get_variant_realpath : string option =
   Option.map (vm_installations#variants_of self#get_epithet)#realpath_of_epithet self#get_variant

  (** A machine has an associated linux kernel, expressed by an epithet: *)
  val mutable kernel : string = kernel
  initializer ignore (self#check_kernel kernel)
  method get_kernel   = kernel
  method set_kernel x = kernel <- self#check_kernel x
  method private check_kernel x =
    match (vm_installations#kernels#epithet_exists x) with
    | true -> x
    | false -> self#logged_failwith "unknown kernel \"%s\"" x

  (* --- Automatic remapping at project loading. ---
     Called ONLY from the deserialization code (eval_forest_attribute in machine.ml and
     router.ml). Old projects (.mar) may reference kernels of the 2.6.x/3.2.x "-ghost"
     series, whose SKAS0 stub segfaults on modern hosts, as well as filesystem builds
     that are not installed. These methods try to remap such references to something
     bootable, informing the user via network#add_import_warning (the warnings are
     displayed in a recapitulative dialog at the end of the project loading). *)

  method private add_import_warning_and_log ?(severity=`Warning) ~(summary:string) ~(detail:string) () : unit =
    let w = { iw_summary = summary; iw_detail = detail; iw_severity = severity } in
    let () = Log.printf1 "import remapping: %s\n" (string_of_import_warning w) in
    network#add_import_warning w

  (* The build-number-less family of a filesystem epithet: "guignol-18474" -> "guignol-".
     Epithets without a dash-separated trailing build number ("default", "mandriva20100215")
     have no family and are thus never remapped (abandoned distributions). *)
  method private family_of_epithet (e:string) : string option =
    match Str.string_match (Str.regexp "^\\(.*-\\)[0-9]+$") e 0 with
    | true  -> Some (Str.matched_group 1 e)
    | false -> None

  (* A distribution remap is sound iff the project carries no actual COW state for this
     device: a COW references the exact backing filesystem (MTIME included), so remapping
     under existing states would corrupt them. Without states the device boots a pristine
     disk from the remapped filesystem instead. *)
  method private without_cow_states_in_project : bool =
    let history = (network#history:Treeview_history.t) in
    let states_directory = history#directory in
    List.for_all
      (fun row_id ->
         let cow_file_name = history#get_row_filename row_id in
         not (Cow_files.cow_file_exists ~states_directory ~cow_file_name ()))
      (history#row_ids_of_name self#get_name)

  (* Keep the (already loaded) history rows of this device consistent with a remapped
     filesystem: *)
  method private redirect_history_rows_to_distrib (e:string) : unit =
    let history = (network#history:Treeview_history.t) in
    let prefixed = (vm_installations#prefix ^ e) in
    history#redirect_device_to_prefixed_filesystem ~name:self#get_name ~prefixed_filesystem:prefixed

  (* Plain substring test on an epithet (distribution names are lowercase ASCII, so a raw
     substring search is enough). *)
  method private epithet_contains ~(sub:string) (e:string) : bool =
    let le = String.length e and ls = String.length sub in
    ls = 0 ||
    (let rec loop i = i + ls <= le && (String.sub e i ls = sub || loop (i + 1)) in loop 0)

  (* First installed filesystem epithet whose name contains [sub] (e.g. "wheezy" ->
     "debian-wheezy-08367"), if any. *)
  method private find_installed_filesystem_containing (sub:string) : string option =
    List.find_opt (self#epithet_contains ~sub) (vm_installations#filesystems#get_epithet_list)

  (* Cross-distribution remap target for a source epithet [x] that has no installed
     same-family build (abandoned distributions like mandriva/lenny/pinocchio, or the
     built-in "default"). The choice reflects the two historical guest-image categories:
     X11/wireshark-capable images (wheezy, then trixie) vs text-terminal-only images
     (guignol). For a plain "default" component it also depends on the kind (routers are
     text-only) and, for a machine, on the RAM planned for it ([memory]); the 96 MB pivot
     is wheezy's suggested size. Each target resolves through a fallback chain so that a
     bootable filesystem is picked even when the preferred family is not installed. Returns
     None only if not even a default filesystem exists. *)
  method private choose_cross_distro_target ?memory (x:string) : string option =
    let trixie () =
      match self#find_installed_filesystem_containing "trixie" with
      | Some _ as r -> r
      | None        -> vm_installations#filesystems#get_default_epithet
    in
    let wheezy () =
      match self#find_installed_filesystem_containing "wheezy" with
      | Some _ as r -> r
      | None        -> trixie ()
    in
    let guignol () =
      match self#find_installed_filesystem_containing "guignol" with
      | Some _ as r -> r
      | None        -> wheezy ()
    in
    let is_router = (vm_installations#prefix = "router-") in
    if (self#epithet_contains ~sub:"mandriva" x) || (self#epithet_contains ~sub:"lenny" x)
    then wheezy ()
    else if self#epithet_contains ~sub:"pinocchio" x
    then guignol ()
    else if x = "default"
    then
      (if is_router then guignol () else
       match memory with
       | Some m when m >= 96 -> trixie ()
       | Some _              -> wheezy ()
       | None                -> trixie ())
    else vm_installations#filesystems#get_default_epithet

  (* If the given filesystem epithet is not installed, try to remap it to an installed
     build of the same family (e.g. "guignol-21852" -> "guignol-18474") or, failing that
     (abandoned distributions like "mandriva20100215" or "pinocchio-14787", or the built-in
     "default"), to a sensible cross-distribution target chosen by choose_cross_distro_target
     from the source distribution, the component kind and the RAM ([memory], machines only).
     Both remaps require the project to carry no COW state for this device (see above);
     otherwise the original epithet is kept, the subsequent set_epithet fails, and the
     component is silently dropped by the try_to_add_* machinery (network#eval_forest_child)
     — the emitted warning is then the only user-visible trace of the lost component. *)
  method remap_absent_distrib_at_import ?memory (x:string) : string =
    if vm_installations#filesystems#epithet_exists x then x else (* continue: *)
    let candidate =
      let family_member =
        Option.bind (self#family_of_epithet x) (fun family ->
          List.find_opt
            (fun e -> self#family_of_epithet e = Some family)
            (vm_installations#filesystems#get_epithet_list))
      in
      match family_member with
      | Some e -> Some e
      | None   -> self#choose_cross_distro_target ?memory x
    in
    match candidate with
    | Some e when self#without_cow_states_in_project ->
        let () = self#add_import_warning_and_log ~severity:`Info
          ~summary:(Printf.sprintf (f_ "%s \"%s\": filesystem \"%s\" \xE2\x86\x92 \"%s\"")
             (self#ifconfig_device_type) (self#get_name) (x) (e))
          ~detail:(Printf.sprintf (f_ "The filesystem \"%s\" is not installed; switched to \"%s\". This is safe because the project carries no saved disk state for this component.")
             (x) (e))
          ()
        in
        let () = self#redirect_history_rows_to_distrib e in
        e
    | Some e ->
        let () = self#add_import_warning_and_log ~severity:`Warning
          ~summary:(Printf.sprintf (f_ "%s \"%s\": filesystem \"%s\" not installed \xE2\x80\x94 component dropped")
             (self#ifconfig_device_type) (self#get_name) (x))
          ~detail:(Printf.sprintf (f_ "Cannot switch to \"%s\" because the project carries saved disk states bound to \"%s\". The component is dropped from the loaded project. Do not save this project on this system, or the component will be lost permanently.")
             (e) (x))
          ()
        in
        x
    | None -> x

  (* A variant may have disappeared with its filesystem, in particular when the distrib
     has just been remapped by the previous method: in this case the component simply
     loses its variant (it will boot the pristine filesystem). *)
  method remap_absent_variant_at_import (x:string) : string option =
    let v = vm_installations#variants_of self#get_epithet in
    if v#epithet_exists x then Some x else
    let () = self#add_import_warning_and_log ~severity:`Info
      ~summary:(Printf.sprintf (f_ "%s \"%s\": variant \"%s\" removed")
         (self#ifconfig_device_type) (self#get_name) (x))
      ~detail:(Printf.sprintf (f_ "The variant \"%s\" is not available for the filesystem \"%s\"; the component boots the pristine filesystem.")
         (x) (self#get_epithet))
      ()
    in
    None

  (* Remap an obsolete kernel epithet (2.6.x/3.2.x "-ghost" series, whose SKAS0 stub is
     broken by modern hosts) or a not installed one, to a kernel supported by the
     (possibly just remapped) filesystem, preferring an i386 build when available (the
     old images are i386 userlands): e.g. "3.2.64-ghost" -> "6.12.95-i386" for wheezy or
     guignol, "2.6.18-ghost" -> "6.12.95" for a filesystem remapped to a modern distrib. *)
  method remap_obsolete_kernel_at_import (k:string) : string =
    let is_broken_old_series =
      (Initialization.host_kernel_breaks_old_uml_stubs) &&
      (match String.split_on_char '.' k with
       | s :: _ -> (match int_of_string_opt s with Some major -> major < 4 | None -> false)
       | []     -> false)
    in
    if (vm_installations#kernels#epithet_exists k) && (not is_broken_old_series) then k else (* continue: *)
    let supported_kernels = List.map fst (vm_installations#supported_kernels_of self#get_epithet) in
    let candidate =
      match List.find_opt (fun e -> Filename.check_suffix e "-i386") supported_kernels with
      | Some e -> Some e
      | None   -> (match supported_kernels with e :: _ -> Some e | [] -> None)
    in
    match candidate with
    | Some e when e <> k ->
        let detail_fmt =
          if is_broken_old_series
          then (f_ "The kernel \"%s\" is unusable on this host; switched to \"%s\".")
          else (f_ "The kernel \"%s\" is not installed; switched to \"%s\".")
        in
        let () = self#add_import_warning_and_log ~severity:`Info
          ~summary:(Printf.sprintf (f_ "%s \"%s\": kernel \"%s\" \xE2\x86\x92 \"%s\"")
             (self#ifconfig_device_type) (self#get_name) (k) (e))
          ~detail:(Printf.sprintf detail_fmt (k) (e))
          ()
        in e
    | _ ->
        let () = self#add_import_warning_and_log ~severity:`Warning
          ~summary:(Printf.sprintf (f_ "%s \"%s\": kernel \"%s\" kept \xE2\x80\x94 no replacement")
             (self#ifconfig_device_type) (self#get_name) (k))
          ~detail:(Printf.sprintf (f_ "The kernel \"%s\" is unusable on this host or not installed, and no replacement is available for the filesystem \"%s\". The component may fail to boot.")
             (k) (self#get_epithet))
          ()
        in k

  (** A machine can be used accessed in a specific terminal mode. *)
  val mutable terminal : string = terminal
  initializer ignore (self#check_terminal terminal)
  method get_terminal   = terminal
  method set_terminal x = terminal <- self#check_terminal x
  method private check_terminal x =
    match (vm_installations#terminal_manager_of epithet)#is_valid_choice x with
    | true  -> x
    | false -> self#logged_failwith "invalid terminal choice \"%s\"" x

  method get_filesystem_file_name =
      vm_installations#filesystems#realpath_of_epithet (self#get_epithet)

  method get_kernel_file_name =
      vm_installations#kernels#realpath_of_epithet (self#get_kernel)

  method get_kernel_console_arguments : string option =
      vm_installations#get_kernel_console_arguments (self#get_epithet) (self#get_kernel)

  method get_filesystem_relay_script : string option =
      vm_installations#relay_script_of (self#get_epithet)

  (* "sysv" or "systemd", read from the filesystem's .conf (INIT_SYSTEM),
     default "sysv" for filesystems without the marker: *)
  method get_init_system : string =
      vm_installations#init_system_of (self#get_epithet)

  method get_ghostification : string =
      vm_installations#ghostification_of (self#get_epithet)

  method is_xnest_enabled =
      (vm_installations#terminal_manager_of self#get_epithet)#is_xnest (self#get_terminal)

  (* Used only to add a filesystem history device: *)
  method private prefixed_epithet = (vm_installations#prefix ^ self#get_epithet)

  method add_my_history =
   let icon = self#history_icon in
   let name = self#get_name in
   match ((network#history:Treeview_history.t)#number_of_states_with_name name) > 0 with
   | true -> Log.printf1 "The virtual machine %s has already history defined...\n" name
   | false ->
      network#history#add_device
          ~name
          ~prefixed_filesystem:self#prefixed_epithet
          ?variant:self#get_variant
          ~icon
          ()

  method add_my_ifconfig
    ?(port_row_completions:Treeview_ifconfig.port_row_completions option)
    (port_no:int) : unit
   =
   match
     (network#ifconfig:Treeview_ifconfig.t)#unique_row_exists_with_binding
        "Name"
        self#get_name
   with
   | true  -> Log.printf2 "The %s %s has already ifconfig defined...\n" self#ifconfig_device_type self#get_name
   | false ->
      begin
      network#ifconfig#add_device
        ?port_row_completions
        self#get_name
        ifconfig_device_type
        self#get_port_no
      end

  method destroy_my_ifconfig =
    Log.printf1 "component \"%s\": destroying my ifconfig.\n" self#get_name;
    network#ifconfig#remove_subtree_by_name self#get_name;

  method destroy_my_history =
    Log.printf1 "component \"%s\": destroying my history.\n" self#get_name;
    network#history#remove_device_tree self#get_name;

  method update_virtual_machine_with ~name ~port_no kernel =
    begin
      (* Before the first write: the three renamings below all precede the [set_name] that used to
         be the only place where the name could still be refused. *)
      check_new_name ~network ~old_name:self#get_name name;
      network#ifconfig#update_port_no self#get_name port_no;
      network#ifconfig#rename self#get_name name;
      network#history#rename  self#get_name name;
      self#rename_hostfs_directory ~to_name:(name) ();
      self#set_kernel kernel;
    end

  method get_states_directory =
    let history = (network#history:Treeview_history.t) in
    history#directory

  (* Define the hostfs_directory.
     Dinamically dependent from the project pathname and the name of the machine/router: *)
  method get_hostfs_directory ?(name=self#get_name) () =
    Printf.sprintf "%s/hostfs/%s" (network#project_root_pathname) (name)

  (* Make the hostfs sub-directory related to the machine/router: *)
  method private create_hostfs_directory_if_needed =
    (* Modalities are "a+rwx"; To do: this should be made slightly more restrictive... *)
    try Unix.mkdir (self#get_hostfs_directory ()) 0o777
    with _ ->
      Log.printf1 "component \"%s\": failed to create the hostfs_directory\n" (self#get_name)


  (* Make the hostfs sub-directory related to the machine/router: *)
  method private remove_hostfs_directory =
    (* ignore (Unix.system (Printf.sprintf "rm -rf '%s'" self#get_hostfs_directory)); *)
    if UnixExtra.Dir.remove_recursively (self#get_hostfs_directory ())
    then ()
    else Log.printf1 "component \"%s\": failed to remove the hostfs_directory\n" (self#get_name)

  (* Rename the hostfs sub-directory after the renaming of the machine/router: *)
  method private rename_hostfs_directory ~to_name () =
    let from_name = self#get_hostfs_directory () in
    let   to_name = self#get_hostfs_directory ~name:(to_name) () in
    try Unix.rename (from_name) (to_name)
    with _ ->
       Log.printf3 "component \"%s\": failed to rename from '%s' to '%s'\n" (self#get_name) (from_name) (to_name)

  (* -------------- *)
  initializer begin
    self#create_hostfs_directory_if_needed;
    self#add_destroy_callback (lazy self#remove_hostfs_directory);
    end
  (* -------------- *)

  method create_cow_file_name_and_thunk_to_get_the_source =
    let history = (network#history:Treeview_history.t) in
    let cow_file_name =
      Filename.concat (history#directory) (history#add_state_for_device self#get_name)
    in
    (* Thunk that will be used by the simulation level to retreive
       the source cow file to be copied (if needed). The procedure
       looks backward in the tree searching the first ancestor with
       a cow_file_name corresponding to an existing file. If there
       are no existing files, it looks for the optional variant_realpath.*)
    let get_the_cow_file_name_source =
      let rec find_first_existing_ancestor cow_file_name =
        match history#get_parent_cow_file_name ~cow_file_name () with
          (* The state hasn't a parent with an existing cow_file_name: its a root.
             The are now two subcases according to the presence of a variant:
             if there is no variant, there is nothing to copy; otherwise the
             file to copy is precisely the variant (its realpath): *)
	  | None ->
	      self#get_variant_realpath

	   (* The state has a parent, but its cow_file_name could be fictive,
	      so we have to distinguish two subcases: *)
	  | Some cow_file_name_parent ->
	      if Cow_files.cow_file_exists
		  ~states_directory:(self#get_states_directory)
		  ~cow_file_name:cow_file_name_parent
		  ()
		then (Some cow_file_name_parent)
		else find_first_existing_ancestor cow_file_name_parent
      in
      fun () -> find_first_existing_ancestor cow_file_name
    in
    (cow_file_name, get_the_cow_file_name_source)

end;; (* class virtual_machine_with_history_and_ifconfig *)


(* *************************** *
        class network
* *************************** *)

class type endpoint = object
  method node : node
  method port_index : int
  method user_port_name : string
  method user_port_index : int
  method involved_node_and_port_index : node * int
end

class type virtual cable = object
(*  inherit OoExtra.destroy_methods *)
 inherit component
 inherit [component] simulated_device
 method destroy : unit
 method get_left  : endpoint
 method get_right : endpoint
 method involved_node_and_port_index_list : (node * int) list
 method is_node_involved : string -> bool
 method crossover : bool
 method is_reversed : bool
 method set_reversed : bool -> unit
 method show : string -> string
 method dot_traduction : curved_lines:bool -> labeldistance:float -> string
 method decrement_alive_endpoint_no : unit
 method increment_alive_endpoint_no : unit
 method is_connected : bool
end

(** Class modelling the user-level network *)
class network
   ~(project_working_directory: unit -> string option)
   ~(project_root_pathname    : unit -> string option)
   ()
 =
 let ledgrid_manager = Ledgrid_manager.the_one_and_only_ledgrid_manager in
 (* --- *)
 (* A network is essentially a graph, i.e. a set of nodes and a set of edges (cables).
    Both these sets will be implemented by Queue.t encapsulated in a Cortex.t, in order
    to be able to program in a reactive style.
    For this kind of cortex, the default equality is not suitable because the inner value
    is a Queue.t, that is to say an *immutable* reference. Thus, we have to redefine it.
    Note that we exploit the partial application to define the equality correctly.
    Actually, when the cortex will be solicited for an evaluation, it will call this
    function on its current value to obtain a *predicate* for committed values. *)
 let queue_equality =
   fun xs -> (* just an argument after the lambda! but we can exploit it to define a predicate: *)
     let xs' = (QueueExtra.to_list xs) in
     fun ys -> (QueueExtra.to_list ys) = xs'
 in
 (* --- *)
 object (self)
 inherit Xforest.interpreter ()

 (* TODO: remove these pointers, we have access to these informations
    by ports_card and endpoint: *)
 method defects  = Treeview_defects.extract ()
 method ifconfig = Treeview_ifconfig.extract ()
 method history  = Treeview_history.extract ()

 method project_working_directory = Option.extract (project_working_directory ())
 method project_root_pathname     = Option.extract (project_root_pathname ())

 (* Warnings collected while deserializing a project (see the remap_*_at_import methods
    of virtual_machine_with_history_and_ifconfig); displayed by state#open_project_async
    in a recapitulative dialog, then reset: *)
 val mutable import_warnings : import_warning list = []
 method add_import_warning (w:import_warning) : unit = import_warnings <- w :: import_warnings
 method get_and_reset_import_warnings : import_warning list =
   let xs = List.rev import_warnings in
   let () = import_warnings <- [] in
   xs

 (* Immutable field. See the previous comment about the equality: *)
 val nodes : (node Queue.t) Cortex.t =
   Cortex.return ~equality:(queue_equality) (Queue.create ())
 (* --- *)
 method nodes = nodes
 method private nodes_append x = Cortex.apply nodes (Queue.push x)
 method private nodes_remove x = Cortex.apply nodes (QueueExtra.filter ((<>)x))
 method get_node_list          = Cortex.apply nodes (QueueExtra.to_list)
 method set_node_list xs       = Cortex.set   nodes (QueueExtra.of_list xs)
 method is_node_list_empty     = Cortex.apply nodes (Queue.is_empty)

 (* Immutable field. See the previous comment about the equality: *)
 val cables : (cable Queue.t) Cortex.t =
   Cortex.return ~equality:(queue_equality) (Queue.create ())
 (* --- *)
 method cables = cables
 method private cables_append x = Cortex.apply cables (Queue.push x)
 method private cables_remove x = Cortex.apply cables (QueueExtra.filter ((<>)x))
 method get_cable_list          = Cortex.apply cables (QueueExtra.to_list)
 method set_cable_list xs       = Cortex.set   cables (QueueExtra.of_list xs)
 method is_cable_list_empty     = Cortex.apply cables (Queue.is_empty)

 (** Buffers to backup/restore data. *)
 val mutable nodes_buffer  : (node  list) = []
 val mutable cables_buffer : (cable list) = []

 (** Accessors *)
 method ledgrid_manager = ledgrid_manager

 (** Related dot options fro drawing this virtual network.
     This pointer is shared with the project instance. *)
 val mutable dotoptions : (Sketch.tuning option) = None
 method dotoptions   = match dotoptions with Some x -> x | None -> raise (Failure "network#dotoptions")
 method private set_dotoptions x = dotoptions <- Some x

 method components : (component list) =
   List.append
     (self#get_node_list  :> component list)
     (self#get_cable_list :> component list) (* CABLES MUST BE AT THE FINAL POSITION for marshaling !!!! *)

 method components_of_kind ?(kind:[`Node | `Cable] option) () =
   match kind with
   | None        -> self#components
   | Some `Node  -> (self#get_node_list  :> (component list))
   | Some `Cable -> (self#get_cable_list :> (component list))

 method disjoint_union_of_nodes_and_cables : ((component * [`Node | `Cable]) list) =
   let xs = List.map (fun x -> x,`Node ) (self#get_node_list  :> component list)  in
   let ys = List.map (fun x -> x,`Cable) (self#get_cable_list :> component list)  in
   List.append xs ys

 (** Setter *)

 (* The optional parameter [scheduled=true] means that this method is called
    in a task managed by the Task_runner. In this case, we have not to call
    the task runner method [wait_for_all_currently_scheduled_tasks]. *)
 method reset ?(scheduled=false) () =
  begin
   Log.printf "---\n";
   Log.printf "network#reset: BEGIN\n";
   Log.printf "network#reset: Destroying all cables...\n";
   (List.iter
      (fun cable ->
         try cable#destroy with e ->
           (* Do not fail, but do not swallow it either: a component failing to die here
              leaves its processes orphaned while disappearing from the model. *)
           Log.printf2 "network#reset: WARNING: cable %s failed to be destroyed (%s)\n"
             cable#get_name (Printexc.to_string e))
      self#get_cable_list);
   Log.printf "network#reset: Destroying all nodes (machines, switchs, hubs, routers, etc)...\n";
   (List.iter
      (fun node ->
         try node#destroy with e ->
           Log.printf2 "network#reset: WARNING: node %s failed to be destroyed (%s)\n"
             node#get_name (Printexc.to_string e))
      (self#get_node_list));
   Log.printf "network#reset: Synchronously wait that everything terminates...\n";
   (* --- *)
   let () =
     if (not scheduled) && (not (GMain_actor.am_I_the_GTK_main_thread ())) then
       Task_runner.the_task_runner#wait_for_all_currently_scheduled_tasks
   in
   (* --- *)
   Log.printf "network#reset: Making the network graph empty...\n";
   (self#set_node_list  []);
   (self#set_cable_list []);
   Log.printf "network#reset: Wait for all devices to terminate...\n";
   (** Make sure that all devices have actually been terminated before going
       on: we don't want them to lose filesystem access: *)
   Log.printf "network#reset: All devices did terminate.\n";
   Log.printf "network#reset: END. Success.\n---\n";
  end

 method destroy_process_before_quitting () =
  begin
   Log.printf "destroy_process_before_quitting: BEGIN\n";
   (* Failures are tolerated (we are quitting anyway) but must be traced: see
      docs/refonte-automate-composants.md § C5 and docs/bug-critique-crash-host.md. *)
   (List.iter
      (fun cable ->
         try cable#destroy_right_now with e ->
           Log.printf2 "destroy_process_before_quitting: WARNING: cable %s failed to be destroyed (%s)\n"
             cable#get_name (Printexc.to_string e))
      (self#get_cable_list));
   (List.iter
      (fun device ->
         try device#destroy_right_now with e ->
           Log.printf2 "destroy_process_before_quitting: WARNING: node %s failed to be destroyed (%s)\n"
             device#get_name (Printexc.to_string e))
      (self#get_node_list));
   Log.printf "destroy_process_before_quitting: END (success)\n";
  end

 method restore_from_buffers =
  begin
   self#reset ();
   (self#set_node_list  nodes_buffer);
   (self#set_cable_list cables_buffer);
  end

 method save_to_buffers =
  begin
   nodes_buffer  <- self#get_node_list;
   cables_buffer <- self#get_cable_list;
  end

 (* Work-stream `migration-marshal-to-text', episode 5. Write the rc scripts of every component
    into states/, then remove the ones no component claims any more. To be called just before
    [#to_tree] / [#to_forest], and only from there: the basenames [#to_tree] publishes are the
    ones this pass has just written. See [Rc_files]. *)
 method save_rc_files : unit =
   let components = self#components in
   let () = List.iter (fun c -> c#save_rc_files) components in
   let alive = List.concat_map (fun c -> c#rc_file_basenames) components in
   Rc_files.remove_orphans
     ~states_directory:(Filename.concat (self#project_root_pathname) "states")
     ~alive

 method to_tree =
   let l = List.map (fun x->x#to_tree) self#components in
   let root = ("network",[]) in
   let children = Forest.of_treelist l in
   (root, children)

 method! to_forest =
   Forest.of_tree self#to_tree

 val try_to_add_procedure_list= ref []
 method subscribe_a_try_to_add_procedure p =
   try_to_add_procedure_list := p::(!try_to_add_procedure_list)

 (** We redefine just the interpretation of a children.
     We ignore (in this version) network attributes. *)
 method! eval_forest_child (f:Xforest.tree) : unit =
  let xs = List.rev !try_to_add_procedure_list in
  let result = List.exists (fun p -> p self f) xs in
  match result with
  | true -> ()
  | false ->
      let ((nodename, attrs), _) = f in
        let name  = List.assoc "name" attrs in
        (Log.printf2 "network#eval_forest_child: I can't interpret this \"%s\" name \"%s\".\n" nodename name)
        (* Forward-compatibility *)

 method names = (List.map (fun x->x#get_name) self#components)

 method suggestedName prefix =
   let rec tip prefix k =
     begin
     let prop = (prefix^(string_of_int k)) in
     if self#name_exists prop then tip prefix (k+1) else prop
     end in tip prefix 1

 method get_node_by_name n =
   try List.find (fun x->x#get_name=n) (self#get_node_list)  with _ -> failwith ("get_node_by_name "^n)

 method get_cable_by_name n =
   try List.find (fun x->x#get_name=n) self#get_cable_list with _ -> failwith ("get_cable_by_name "^n)

 method get_component_by_name ?kind n =
   let components = self#components_of_kind ?kind () in
   try List.find (fun x->x#get_name=n) components with _ -> failwith ("get_component_by_name "^n)

 method involved_node_and_port_index_list =
   List.flatten (List.map (fun c->c#involved_node_and_port_index_list) self#get_cable_list)

 method get_cables_involved_by_node_name (node_name) =
   List.filter (fun c->c#is_node_involved node_name) self#get_cable_list

 method busy_port_indexes_of_node (node:node) =
   let node_name = node#get_name in
   let related_busy_pairs =
     List.filter
       (fun (node, port_index) -> node#get_name = node_name)
        self#involved_node_and_port_index_list
   in
   List.map snd related_busy_pairs

 method free_port_indexes_of_node ?(force_to_be_included:(int list)=[]) (node:node) =
   let node_port_indexes = ListExtra.range 0 (node#get_port_no-1) in
   let busy_port_indexes =
     ListExtra.substract (self#busy_port_indexes_of_node node) force_to_be_included
   in
   ListExtra.substract node_port_indexes busy_port_indexes

 method free_user_port_names_of_node ?(force_to_be_included=[]) node =
   (* force_to_be_included expressed now by indexes: *)
   let force_to_be_included =
      List.map (node#ports_card#internal_index_of_user_port_name) force_to_be_included
   in
   List.map
     (node#ports_card#user_port_name_of_internal_index)
     (self#free_port_indexes_of_node ~force_to_be_included node)

 method free_endpoint_list_humanly_speaking
  ?(force_to_be_included:((string*string) list)=[])
  : (string * string) list
  =
  let npss =
    List.map
      (fun node ->
	  let n = node#get_name in
	  let force_to_be_included =
	    List.map snd (List.filter (fun (n0,p0) -> n0=n) force_to_be_included)
	  in
	  (List.map (fun p -> (n,p)) (self#free_user_port_names_of_node ~force_to_be_included node))
	)
	(self#get_node_list)
  in List.concat npss

 (* Unused...*)
(* method is_endpoint_free endpoint =
   let busy_pairs = self#involved_node_and_port_index_list in
   List.iter (function (n,p) -> Log.printf "Involved: (%s,%d)\n" n#get_name p) busy_pairs;
   not (List.mem (endpoint#involved_node_and_port_index) busy_pairs)*)

 (* The total number of endpoints in the network: *)
 method private endpoint_no =
   let sum xs = List.fold_left (+) 0 xs in
   sum (List.map (fun node -> node#get_port_no) (self#get_node_list))

 method are_there_almost_2_free_endpoints : bool =
    let busy_no = List.length (self#involved_node_and_port_index_list) in
    ((self#endpoint_no - busy_no) >= 2)

 (** The max index among busy receptacles of a given kind of a given node.
     The user cannot change the number of receptacle of the given node to a number less than this index+1.
     For instance, if the (max_busy_receptacle_index "rome" Eth) = 2 then the user can change
     the number of receptacle of rome but only with a number >= 3.  *)
 method max_busy_port_index_of_node node =
   let indexes = self#busy_port_indexes_of_node node in
   if indexes=[] then -1 else ListExtra.max indexes

  (** Useful updating a device: *)
 method port_no_lower_of node =
  let port_no_lower = node#port_no_min in
  let min_port_no = (self#max_busy_port_index_of_node node + 1) in
  let k = float_of_int port_no_lower in
  (* minimum multiple of k containing min_port_no: *)
  let min_multiple = (ceil ((float_of_int min_port_no) /. k)) *. k in
  int_of_float (max min_multiple k)

 method node_exists  n = let f=(fun x->x#get_name=n) in (List.exists f (self#get_node_list))
 method cable_exists n = let f=(fun x->x#get_name=n) in (List.exists f (self#get_cable_list))
 method name_exists  n = List.mem n self#names

 (** Adding components *)

 (** Nodes must have a unique name in the network *)
 method add_node (node:node) : unit =
    if (self#name_exists node#get_name) then
      failwith "User_level.network#add_node: name already used in the network"
    else
      self#nodes_append (node)

 (** Remove a node from the network. Remove it from the node list
     and remove all related cables. TODO: change this behaviour! *)
 method del_node_by_name (node_name:string) : unit =
     let node = self#get_node_by_name (node_name) in
     (* Destroy cables first: they refer what we're removing... *)
     let cables_to_destroy = List.filter (fun c->c#is_node_involved node_name) self#get_cable_list in
     (* The cable#destroy will call itself the network#del_cable_by_name: *)
     let () = List.iter (fun cable -> cable#destroy) cables_to_destroy in
     self#nodes_remove (node)

 (** Cable must connect free ports: *)
 (* TODO: manage ledgrid with a reactive system!!!*)
 method add_cable (cable:cable) : unit =
    if (self#name_exists cable#get_name)
    then failwith "User_level.network#add_cable: name already used in the network"
    else self#cables_append (cable)

 (** Remove a cable from network. Called by cable#destroy. *)
 method del_cable_by_name (cable_name) : unit =
     let cable = self#get_cable_by_name (cable_name) in
     self#cables_remove (cable)

 method change_node_name (old_name) (new_name) =
   if old_name = new_name then () else
   let node = self#get_node_by_name (old_name) in
   node#set_name (new_name)

 (** Facilities *)

 (** List of node names in the network *)
 method get_node_names  =
   List.map (fun x->x#get_name) (self#get_node_list)

 method private predicate_of_optional_devkind ?devkind () =
  match devkind with
  | Some devkind -> (fun x -> x#devkind = devkind)
  | None         -> (fun x -> true)

 method get_nodes_such_that ?devkind (predicate) =
  let devkindp = self#predicate_of_optional_devkind ?devkind () in
  List.filter (fun x -> (devkindp x) && (predicate x)) (self#get_node_list)

 (* --- can_startup --- *)

 method get_nodes_that_can_startup ?devkind () =
  self#get_nodes_such_that ?devkind (fun x -> x#can_startup)

 method get_node_names_that_can_startup ?devkind () =
  List.map (fun x -> x#get_name) (self#get_nodes_that_can_startup ?devkind ())

 (* --- can_gracefully_shutdown --- *)

 method get_nodes_that_can_gracefully_shutdown ?devkind () =
  self#get_nodes_such_that ?devkind (fun x -> x#can_gracefully_shutdown)

 method get_node_names_that_can_gracefully_shutdown ?devkind () =
  List.map (fun x -> x#get_name) (self#get_nodes_that_can_gracefully_shutdown ?devkind ())

 (* --- can_suspend --- *)

 method get_nodes_that_can_suspend ?devkind () =
  self#get_nodes_such_that ?devkind (fun x -> x#can_suspend)

 method get_node_names_that_can_suspend ?devkind () =
  List.map (fun x -> x#get_name) (self#get_nodes_that_can_suspend ?devkind ())

 (* --- can_resume --- *)

 method get_nodes_that_can_resume ?devkind () =
  self#get_nodes_such_that ?devkind (fun x -> x#can_resume)

 method get_node_names_that_can_resume ?devkind () =
  List.map (fun x -> x#get_name) (self#get_nodes_that_can_resume ?devkind ())

 (* --- can_modify --- *)

 method get_nodes_that_can_modify ?devkind () =
  self#get_nodes_such_that ?devkind (fun x -> x#can_modify)

 method get_node_names_that_can_modify ?devkind () =
  List.map (fun x -> x#get_name) (self#get_nodes_that_can_modify ?devkind ())

 (* --- can_destroy --- *)

 method get_nodes_that_can_destroy ?devkind () =
  self#get_nodes_such_that ?devkind (fun x -> x#can_destroy)

 method get_node_names_that_can_destroy ?devkind () =
  List.map (fun x -> x#get_name) (self#get_nodes_that_can_destroy ?devkind ())

 (* Including cables (suspend=disconnect, resume=reconnect). The boolean in the result
    indicates if the component is suspended (sleeping): *)
 method get_component_names_that_can_suspend_or_resume () : (string * [`Node|`Cable] * bool) list =
  ListExtra.filter_map
    (fun (x, node_or_cable) ->
       let can_suspend = x#can_suspend in
       let can_resume  = lazy x#can_resume in
       if  can_suspend || (Lazy.force can_resume)
         then Some (x#get_name, node_or_cable, (Lazy.force can_resume))
         else None)
    self#disjoint_union_of_nodes_and_cables

 (** List of direct cable names in the network *)
 method get_direct_cable_names  =
   let clist = List.filter (fun x->x#crossover=false) self#get_cable_list in
   List.map (fun x->x#get_name) clist

 (** List of crossover cable names in the network *)
 method get_crossover_cable_names =
   let clist= List.filter (fun x->x#crossover=true) self#get_cable_list in
   List.map (fun x->x#get_name) clist

 method get_direct_cables =
   List.filter (fun x->x#crossover=false) self#get_cable_list

 method get_crossover_cables  =
   List.filter (fun x->x#crossover=true) self#get_cable_list

 (* The "Modify" and "Remove" dynlists of cable.ml read the two methods below, exactly as the seven
    node components read get_node_names_that_can_{modify,destroy}: one truth about what is allowed,
    read by the GUI and by the control server alike (docs/pilotage-par-script.md § 4.10). The
    ~crossover filter is the one already applied by get_direct_cable_names and
    get_crossover_cable_names, straight and crossover cables having separate menus. Note that both
    predicates are overridden to a constant true in cable.ml: a wire is unplugged, moved and plugged
    back while the machines keep running. *)
 method get_cables_such_that ~crossover (predicate) =
   List.filter (fun x -> (x#crossover = crossover) && (predicate x)) (self#get_cable_list)

 method get_cable_names_that_can_modify ~crossover () =
   List.map (fun x -> x#get_name) (self#get_cables_such_that ~crossover (fun x -> x#can_modify))

 method get_cable_names_that_can_destroy ~crossover () =
   List.map (fun x -> x#get_name) (self#get_cables_such_that ~crossover (fun x -> x#can_destroy))

 (** Starting and showing the network *)

 (** List of reversed cables (used only for drawing network) *)
 method reversed_cables : (string list) =
   let clist= List.filter (fun x->x#is_reversed) self#get_cable_list in
   List.map (fun x->x#get_name) clist

 (** Set the reversed dotoptions field of a cable of the network (identified by name) *)
 method reversed_cable_set (x:bool) (cname:string) =
   (self#get_cable_by_name cname)#set_reversed x

 (** Show network topology *)
 method show =
   Log.printf "========== NETWORK STATUS ===========\n";
   (* show nodes *)
   let msg= try
        (String.concat " , "
        (List.map (fun d->d#get_name^" ("^(d#string_of_devkind)^")") (self#get_node_list)))
        with _ -> ""
   in Log.printf1 "Nodes \r\t\t: %s\n" msg;
  (* show links *)
   let msg=try
        (String.concat "\n" (List.map (fun c->(c#show "\r\t\t  ")) self#get_cable_list))
        with _ -> ""
   in Log.printf1 "Cables \r\t\t: %s\n" msg


 (** {b Consider cable as Edge.edges} *)

 (** Network translation into the dot language *)
 method dotTrad () =
 let opt = self#dotoptions in
 let labeldistance = Cortex.get (opt#labeldistance) in
 let curved_lines  = Cortex.get (opt#curved_lines) in
 try begin
"digraph plan {

"(*^opt#ratio*)^"
"^opt#rankdir_for_dot^"
"^opt#nodesep_for_dot^";"^"

/* ***************
        NODES
   *************** */

"^
(StringExtra.Text.to_string
   (List.map
     (fun (n:node)->n#dotTrad opt#iconsize_for_dot)
     (ListExtra.permute opt#shuffler_as_function (self#get_node_list))
   ))
^"
/* ***********************
      DIRECT CABLE EDGES
   *********************** */


edge [dir=none,color=\""^self#dotoptions#direct_cable_color^"\",fontsize=8,labelfontsize=8,minlen=1.6,"^
opt#labeldistance_for_dot^",tailclip=true];

"^
(StringExtra.Text.to_string
   (List.map (fun c->c#dot_traduction ~curved_lines ~labeldistance) self#get_direct_cables))
^"
/* *********************************
      CROSSOVER/SERIAL CABLE EDGES
   ********************************* */

edge [headclip=true,minlen=1.6,color=\""^self#dotoptions#crossover_cable_color^"\",weight=1];

"^
(StringExtra.Text.to_string
   (List.map (fun c->c#dot_traduction ~curved_lines ~labeldistance) self#get_crossover_cables))

^"} //END of digraph\n"
 end (* method dotTrad *)
 with e ->
    (Log.printf1
       "Warning: exception raised in network#dotTrad:\n%s\nRe-raising.\n"
       (Printexc.to_string e);
     raise e)

initializer

 self#set_dotoptions (new Sketch.tuning ~network:(self) ());

end


(** {2 Saving and loading a Netmodel.network } *)

(** Pseudo XML now! (using xforest instead of ocamlduce) *)
module Xml = struct

 let network_marshaller = new Oomarshal.marshaller ;;

 (** Parse the file containing an xforest representation of the network.
     The given network is updated during the parsing. *)
 let load_network ~(project_version: [`v0|`v1|`v2|`v3]) (net:network) (fname:string) =
  let (forest:Xforest.t) =
    match project_version with
    (* Since `v3 the file is JSON (work-stream `migration-marshal-to-text'). A decoding failure
       is turned into an exception right here: the caller (state#import_network) already restores
       the network from its buffers and reports the failure to the user. *)
    | `v3       -> (match Xforest.of_JSON_file (fname) with
                    | Ok forest -> forest
                    | Error msg -> failwith (Printf.sprintf "Netmodel.Xml.load_network: %s" msg))
    | `v2 | `v1 -> network_marshaller#from_file (fname)
    | `v0       -> Forest_backward_compatibility.load_from_old_file (fname)
  in
  (* we are manually setting the verbosity 3 *)
  (if (Global_options.Debug_level.get ()) >= 3 then Xforest.print_xforest ~channel:stderr forest);
  match Forest.to_tree forest with
  | (("network", attrs), children) -> net#from_tree ("network", attrs) children
  | _ -> assert false
 ;;

(** Save the xforest representation of the network. *)
let save_network (net:network) (fname:string) =
 Log.printf "Netmodel.Xml.save_network: begin\n";
 (* we are manually setting the verbosity 3 *)
 (if (Global_options.Debug_level.get ()) >= 3 then Xforest.print_xforest ~channel:stderr net#to_forest);
 (* Written as JSON since `v3, under the name the caller provides (netmodel/network.json): *)
 Xforest.to_JSON_file (net#to_forest) fname;
 Log.printf "Netmodel.Xml.save_network: end (success)\n";;

end;; (* module Netmodel.Xml *)
