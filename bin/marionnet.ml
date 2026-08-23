(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008, 2009  Luca Saiu
   Copyright (C) 2007, 2009, 2010  Jean-Vincent Loddo
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


(** The main module of the application. Here the global state is defined, all
    bindings between widgets of the main window and dialogs are created, and
    finally the GTK main loop is launched. *)

(* Force OCAMLRUNPARAM=-b *)
Printexc.record_backtrace true;

(* --- *)
module Log = Marionnet_log
module Lazy_perishable = Ocamlbricks.Lazy_perishable
module FilenameExtra = Ocamlbricks.FilenameExtra
module Linux = Ocamlbricks.Linux
module Option = Ocamlbricks.Option
module UnixExtra = Ocamlbricks.UnixExtra
module SysExtra = Ocamlbricks.SysExtra
module StringExtra = Ocamlbricks.StringExtra
module StackExtra = Ocamlbricks.StackExtra
(* --- *)
(* open StdLabels *)
(* open Gui *)
open Gettext
(* --- *)

(* Isolate Marionnet and its whole descendance in a new session, detached from the
   launching terminal / process group: a stray terminal signal (Ctrl-C) or a group-
   directed signal from the outside can no longer reach the process tree. This is
   defense-in-depth (kills are per-PID, hence session-independent) and daemon hygiene
   for the future scriptable/service direction. setsid(2) fails with EPERM when we are
   already a process-group leader (typical interactive job-control shell launch); we
   then keep the status quo. No fork -> the PID stays stable (lifecycle by PID).
   Placed here on purpose: still single-threaded, before GTK and the global state. *)
let () =
  try
    let sid = Unix.setsid () in
    Log.printf1 "marionnet: new session started (sid=%d); process tree isolated from the launching terminal/group.\n" sid
  with
  | Unix.Unix_error (Unix.EPERM, _, _) ->
      Log.printf "marionnet: setsid skipped (already a process-group leader, e.g. interactive shell); tree stays in the launcher session.\n"
  | e ->
      Log.printf1 "marionnet: setsid failed unexpectedly (%s); continuing without session isolation.\n" (Printexc.to_string e)

(* Neutralise SIGPIPE, whose default action is to *kill* the process. Marionnet writes on
   sockets whose peer may have gone away at any moment (X11 relay, vde, and now the
   scripting control channel): such a write would terminate the application without any
   exception to log, hence without any trace — this is not a conjecture, the test program
   of the control channel got killed that way (exit 141). Ignored, the same condition
   surfaces as an ordinary EPIPE exception, caught by the callers. Placed here on purpose:
   still single-threaded, before GTK and the global state. *)
let () = Sys.set_signal Sys.sigpipe Sys.Signal_ignore

(* --- *)
(* Arm script mode, if a control channel was requested. This has to happen here, before
   anything is allowed to show a window: the tap provider probe below already pops up a
   warning dialog. script_mode.ml cannot read the command line by itself without closing a
   dependency cycle (initialization -> user_level -> simple_dialogs -> script_mode), so the
   root module tells it. *)
let () =
  Script_mode.configure
    ~enabled:((!Initialization.option_control_socket <> None)
              && (!Initialization.option_keep_dialogs = None))
    ~auto_dismiss_ms:(match !Initialization.option_dialog_timeout with
                      | Some ms when ms >= 0 -> ms
                      | _ -> 2000)

(* --- *)
let () = Log.printf1 "Loading module bin/marionnet.ml: cwd: %s\n" (Sys.getcwd ())

(* Enter the right directory: the one holding the data versioned in this repository, which is
   the installation prefix for an installed binary and the build tree for a binary of `_build'
   (episode 22 of `marionnet-todo-transverse'). Nothing changes for an installed run; what this
   allows is a development run on a machine where Marionnet is NOT installed at all -- there the
   installation prefix does not exist, and this chdir used to be fatal. *)
let _enter_the_right_directory =
  let dir = Initialization.Path.versioned_data_home in
  try Sys.chdir dir
  with _ -> failwith ("Could not enter the directory (" ^ dir ^ ")")

(** The global state containing the main window (st#mainwin) and all relevant dynamic
    attributes of the application *)
let st = new State.globalState ()

(** Add a global thunk allowing to invoke the sketch refresh method,
    visible from many modules: *)
let () = Sketch.Refresh_sketch_thunk.set (fun () -> st#refresh_sketch)

(* State is not anymore state.ml but a simple module containing the reference the global state object.
   This module will be used as argument of some functors below in this source file: *)
module State = struct let st = st end

(* Complete the main menu *)
let () = Log.printf "Loading module bin/marionnet.ml: about to call Gui_window_MARIONNET.Make\n"
module Created_window_MARIONNET = Gui_window_MARIONNET.Make (State)
(* --- *)
let () = Log.printf "Loading module bin/marionnet.ml: about to call Gui_toolbar_COMPONENTS.Make\n"
module Created_toolbar_COMPONENTS = Gui_toolbar_COMPONENTS.Make (State)

(* ***************************************** *
            Make the treeview widgets
 * ***************************************** *)

(* --- *)
let window = st#mainwin#window_MARIONNET

let () = Log.printf "Loading module bin/marionnet.ml: about to call Treeview_history.make\n" ;;
(* --- *)
(** Make the states interface: *)
let filesystem_history_interface =
  Treeview_history.make
    ~window
    ~hbox:(st#mainwin#filesystem_history_viewport)
    ~after_user_edit_callback:(fun _ -> st#set_project_not_already_saved)
    ~method_directory:(fun () -> Option.extract st#project_paths#treeviewDir)
    ~method_filename: (fun () -> Option.extract st#project_paths#treeview_history_file)
    ()

(** See the comment in states_interface.ml for why we need this ugly kludge: *)
let () =
 let can_startup =
   (fun name ->
      let node = st#network#get_node_by_name name in
      node#can_startup)
 in
 let startup =
   (fun name ->
      let node = st#network#get_node_by_name name in
      node#startup)
 in
 Treeview_history.Startup_functions.set (can_startup, startup)

let dialog_confirm_device_restart ~(devkind:string) ~(device_name:string) =
  let question =
    Printf.sprintf (f_ "Your changes will be applied after the reboot of %s.\nDo you want to restart this %s now?")
      device_name
      devkind
  in
  Gui_bricks.Dialog.yes_or_cancel_question
    ~title:(s_ "Reboot")
    ~markup:question
    ~context:()
    ()

let shutdown_or_restart_relevant_device device_name =
  Log.printf1 "Shutdown or restart \"%s\"?\n" device_name;
  try
    (* Is the device a cable? If so we have to restart it (and do nothing if it
       was not connected) *)
    let c = st#network#get_cable_by_name device_name in
    if c#is_connected then begin
      c#suspend; (* disconnect *)
      c#resume;  (* re-connect *)
    end
  with _ -> begin
    (* Ok, the device is not a cable. We have to destroy it, so that its cables
       and hublets are restarted: *)
    let node = st#network#get_node_by_name device_name in
    if not node#can_gracefully_shutdown
    then Log.printf1 "No, \"%s\" doesn't need to be restarted\n" device_name
    else (* continue: *)
    let devkind = node#string_of_devkind in
    match dialog_confirm_device_restart ~devkind ~device_name with
    | None    -> ()
    | Some () -> node#gracefully_restart
  end

let after_user_edit_callback x =
  begin
    st#set_project_not_already_saved;
    shutdown_or_restart_relevant_device x
  end

(* --- *)
(** Make the ifconfig treeview: *)
(* --- *)
let () = Log.printf "Loading module bin/marionnet.ml: about to call Treeview_ifconfig.make\n"
let treeview_ifconfig =
  Treeview_ifconfig.make
    ~window
    ~hbox:(st#mainwin#ifconfig_viewport)
    ~after_user_edit_callback
    ~method_directory:(fun () -> Option.extract st#project_paths#treeviewDir)
    ~method_filename: (fun () -> Option.extract st#project_paths#treeview_ifconfig_file)
    ()

(* --- *)
(** Make the defects interface: *)
(* --- *)
let () = Log.printf "Loading module bin/marionnet.ml: about to call Treeview_defects.make\n"
let treeview_defects =
  Treeview_defects.make
    ~window
    ~hbox:(st#mainwin#defects_viewport)
    ~after_user_edit_callback
    ~method_directory:(fun () -> Option.extract st#project_paths#treeviewDir)
    ~method_filename: (fun () -> Option.extract st#project_paths#treeview_defects_file)
    ()

(* --- *)
(** Make the texts interface: *)
(* --- *)
let () = Log.printf "Loading module bin/marionnet.ml: about to call Treeview_documents.make\n"
let treeview_documents =
  Treeview_documents.make
    ~window
    ~hbox:(st#mainwin#documents_viewport)
    ~after_user_edit_callback:(fun _ -> st#set_project_not_already_saved)
    ~method_directory:(fun () -> Option.extract st#project_paths#treeviewDir)
    ~method_filename: (fun () -> Option.extract st#project_paths#treeview_documents_file)
    ()

module Just_for_testing = struct

  let get_machine_by_name name =
     let m = (st#network#get_node_by_name name) in
     let ul_m = ((Obj.magic m):> Machine.User_level_machine.machine) in
     ul_m

end (* Just_for_testing *)

(* ***************************************** *
                   M A I N
 * ***************************************** *)

(* --- *)
(** eth42 taps (guest X11, quagga terminals) now come from Tap_provider (sudo + iproute2).
    At start-up: collect the taps leaked by dead Marionnet processes, or explain how to
    install the sudoers rule when the probe fails: *)
let () = Log.printf "Loading module bin/marionnet.ml: about to probe the tap provider\n"
let () =
  if Tap_provider.is_usable () then
    let n = Tap_provider.purge_orphan_taps () in
    (if n > 0 then Log.printf1 "Tap_provider: %i orphan tap(s) collected\n" n)
  else
    Simple_dialogs.warning
      (s_ "Cannot create network interfaces (taps)")
      (Printf.sprintf
        (f_ "The sudo rule allowing Marionnet to create its taps is not installed: some features (graphics on virtual machines, router terminals) won't be available.\nTo enable them, run in a terminal:\n\n    %s install\n\nthen restart Marionnet.")
        "marionnet-sudoers.sh")
      ()

(* --- *)
(** Two Marionnet sessions running at the same time are allowed, and nobody used to say a word
    about it (chantier `marionnet-todo-transverse', episode 9): every session gives its taps the
    same host address and numbers its virtual machines from scratch, so the machines of the second
    session claim addresses already routed by the first, and boot without network. Detecting the
    other sessions costs no privilege at all (`ip -o link show'), hence this block sits OUTSIDE
    the is_usable() test above: making a diagnostic depend on a privilege probe is precisely what
    kept this defect invisible. *)
let () = Log.printf "Loading module bin/marionnet.ml: about to look for other Marionnet sessions\n"
let () =
  match Tap_provider.other_live_sessions () with
  | [] -> ()
  | sessions ->
      let session_no = List.length sessions in
      let tap_no = List.fold_left (fun total (_, taps) -> total + taps) 0 sessions in
      let pids = String.concat ", " (List.map (fun (pid, _) -> string_of_int pid) sessions) in
      let () =
        Log.printf3 ~force:true
          "marionnet: other Marionnet session(s) running right now: %d (process(es): %s), owning %d tap(s)\n"
          session_no pids tap_no
      in
      (* Unlike the housekeeping notice about the run directories, this one is NOT advice: it
         explains a failure of the user's own machines, so an exam is not a reason to hide it.
         Only the explicit flag turns it off. *)
      if Initialization.Disable_warnings.other_marionnet_sessions then () else
      Simple_dialogs.warning
        (s_ "Another Marionnet session is running")
        (Printf.sprintf
           (f_ "Marionnet is already running on this machine, in one or more other sessions. Number of other sessions: %d (processes: %s). All the sessions give their taps the same host address (%s) and number their virtual machines independently, so two machines belonging to two sessions can claim the same address: the second one to start is then left without network, although it boots normally. If a virtual machine has no network, this is the first thing to check.")
           session_no pids Tap_provider.eth42_host_address)
        ()

(* --- *)
(** Show the splash (only when there is no project to open): *)
let () = Log.printf "Loading module bin/marionnet.ml: about to show the splash screen\n"
let () =
 if !Initialization.optional_file_to_open = None
   then
     (* The splash waits for a click or a keypress, and it is modal: in a driven session
        nobody is there to dismiss it. show_splash already knows how to close itself
        (splash.ml:112, a GMain.Timeout) — the parameter just had never been used. *)
     (if Script_mode.enabled ()
        then Splash.show_splash ~timeout:(Script_mode.auto_dismiss_ms ()) ()
        else Splash.show_splash (* ~timeout:15000 *) ())
   else ()

(* --- *)
(** Choose a reasonable temporary working directory: *)
(* --- *)
let () = Log.printf "Loading module bin/marionnet.ml: about to choose a reasonable temporary working directory\n"
let () =
 let suitable_tmp pathname =
   (UnixExtra.dir_rwx_or_link_to pathname) &&
   (Talking.does_directory_support_sparse_files pathname)
 in
 let defined_and_suitable_tmp x =
    (Option.map suitable_tmp x) = Some true
 in
 let warning_tmp_automatically_set_for_you ~dir =
   if not (Initialization.Disable_warnings.temporary_working_directory_automatically_set)
   then
    Simple_dialogs.warning
      (s_ "Temporary working directory automatically set")
      (Printf.sprintf (f_ "We chose %s as the temporary working directory, because the default candidates were not suitable (file rights and sparse files support).") dir)
      ()
   else () (* do nothing *)
 in
 let set_but_warning dir =
   let () = st#project_paths#set_temporary_directory (dir) in
   warning_tmp_automatically_set_for_you dir
 in
 let marionnet_tmpdir = Initialization.Path.marionnet_tmpdir in
 let tmpdir = (SysExtra.meaningful_getenv "TMPDIR")#existing_directory in
 let home   = (SysExtra.meaningful_getenv "HOME")#existing_directory
 in
 let d1 = marionnet_tmpdir in                                    (*  ${MARIONNET_TMPDIR}  *)
 let d2 = tmpdir in                                              (*  ${TMPDIR}  *)
 let d3 = "/tmp" in                                              (*  /tmp  *)
 let d4 = "/var/tmp" in                                          (*  /var/tmp *)
 (* The following candidates will raise a warning: *)
 let d5 = Initialization.cwd_at_startup_time in                  (*  $PWD  *)
 let d6 = Option.map (fun h -> Filename.concat h "tmp") home in  (*  ~/tmp *)
 let d7 = home in                                                (*  ~/    *)
 begin
  if defined_and_suitable_tmp d1 then st#project_paths#set_temporary_directory (Option.extract d1) else
  if defined_and_suitable_tmp d2 then st#project_paths#set_temporary_directory (Option.extract d2) else
  if suitable_tmp d3             then st#project_paths#set_temporary_directory d3 else
  if suitable_tmp d4             then st#project_paths#set_temporary_directory d4 else
  if suitable_tmp d5             then set_but_warning d5 else
  if defined_and_suitable_tmp d6 then set_but_warning (Option.extract d6) else
  if defined_and_suitable_tmp d7 then set_but_warning (Option.extract d7) else
    begin
      Simple_dialogs.warning
	(s_ "Sparse files not supported!")
	(s_ "You should probably create one of /tmp, ~/tmp and ~/ into a modern filesystem supporting sparse files (ext2, ext3, ext4, reiserfs, NTFS, ...), or set another suitable temporary working directory (menu Options). Marionnet will work with the current settings, but performance will be low and disk usage very high.")
	();
      (* Set anyway the value to "/tmp": *)
      (st#project_paths#set_temporary_directory "/tmp")
    end
  end

(* Nobody sweeps the run directories `<tmp>/marionnet-<n>.dir/' of past sessions. A clean exit
   through the GUI removes its own (state.ml, [reset_and_remove_the_project_working_directory],
   called by [close_project] on the way out), but a session killed brutally leaves it behind,
   and so does a session quitted through the control channel, which does not close the project.
   Each of them holds the *unsaved* working copy of its project: that is precisely why Marionnet
   must not purge them by itself — even an old one may be the only copy that was left. So it
   counts them, names the tool, and removes nothing.
   Which ones are still in use is deliberately NOT decided here: `bin/scripts/marionnet-cleanup.sh'
   scans /proc to tell a live session from a dead one, and a second implementation of that scan
   would be a second source of truth serving a message whose whole point is to hand over to that
   script. Hence a count and no claim of death. *)
let () =
  let dir = st#project_paths#get_temporary_directory in
  (* The shape UnixExtra.temp_dir builds in state.ml (~prefix:"marionnet-" ~suffix:".dir"). *)
  let is_a_run_directory name =
    (StringExtra.is_prefix "marionnet-" name) && (Filename.check_suffix name ".dir")
  in
  (* /tmp is shared: someone else's directory is none of our business, and we could not
     remove it anyway. *)
  let is_mine name =
    try (Unix.stat (Filename.concat dir name)).Unix.st_uid = (Unix.getuid ()) with _ -> false
  in
  let n =
    try
      List.length
        (List.filter (is_mine)
           (SysExtra.readdir_as_list ~only_directories:() ~name_filter:is_a_run_directory dir))
    with _ -> 0
  in
  if n = 0 then () else
  let () =
    Log.printf2 ~force:true
      "marionnet: %d run directory(ies) of other sessions found in %s (use `marionnet-cleanup --archive-dirs <dir> --purge-dirs' to recover and remove the abandoned ones)\n"
      n dir
  in
  (* An exam is not the place for housekeeping advice, and the student cannot act on it. *)
  if Initialization.are_we_in_exam_mode || Initialization.Disable_warnings.orphan_run_directories
  then () else
  (* --- The tool, if this host has it.
     ---
     It is installed in $PREFIX/bin/ (useful-scripts/dune puts it among the scripts of the share
     section, which the Makefile mirrors into bin/), hence reachable by name -- exactly like
     marionnet-lanbridge.sh. In the source tree, where nothing is installed, set
     MARIONNET_CLEANUP_SCRIPT to its ABSOLUTE path: Marionnet chdir's to its own home at startup,
     so a relative one would no longer mean what it says. No tool, no buttons: the text alone
     then remains, and it says what to run. *)
  let cleanup_command () : string option =
    let name = try Sys.getenv "MARIONNET_CLEANUP_SCRIPT" with Not_found -> "marionnet-cleanup" in
    if String.contains name '/' then (if Sys.file_exists name then Some name else None) else
    match UnixExtra.run (Printf.sprintf "command -v %s" (Filename.quote name)) with
    | (output, Unix.WEXITED 0) when String.trim output <> "" -> Some (String.trim output)
    | _ -> None
  in
  (* Where the recovered projects are written: the folder `Project -> Save as' opens on
     (gui/talking.ml), so that a recovered project shows up where the user looks for projects. *)
  let archive_destination () =
    let candidates = [ Initialization.cwd_at_startup_time; Initialization.Path.user_home ] in
    try List.find (fun d -> (try Unix.access d [Unix.W_OK]; true with _ -> false)) candidates
    with Not_found -> Initialization.Path.user_home
  in
  (* --- Running it.
     ---
     A full /proc scan costs seconds (2.9 s measured on the development machine), so it must not
     run in the GTK main loop, where the button click lands: hence a thread. The dialogs opened
     from it are safe, every Simple_dialogs entry going back to the main thread by itself
     (GMain_actor.apply_extract).
     ---
     Two arguments say who is asking. --caller-marionnet <pid>: the script refuses --purge-dirs
     while a Marionnet is running, and rightly so -- we are that Marionnet, and it checks the pid
     rather than trusting it; any OTHER live session still forbids the purge. --spare-dir <dir>:
     our own run directory, which nothing else on this host names as long as we have started no
     component. It is read at CLICK time, not now: this dialog is not modal, and a project may
     have been created in between. *)
  let run_cleanup (script : string) (args : string list) : string * bool =
    let identity =
      (Printf.sprintf "--caller-marionnet %d" (Unix.getpid ())) ::
      (match st#project_paths#get_working_directory with
       | Some d -> [Printf.sprintf "--spare-dir %s" (Filename.quote d)]
       | None   -> [])
    in
    let command = String.concat " " ((Filename.quote script) :: args @ identity) in
    let () = Log.printf1 "marionnet: running the cleanup tool: %s\n" command in
    let (output, status) = UnixExtra.run (command ^ " 2>&1") in
    (output, status = Unix.WEXITED 0)
  in
  (* The confirmation shows what the tool sees about the DIRECTORIES, not its whole report (the
     orphan processes and the socket files are another matter, and the question dialog has no
     scrolled area). The marker is the section header the script prints, both sides of which live
     in this repository; should it ever change, the whole report is shown instead of nothing. *)
  let directories_section (report : string) : string =
    let lines = String.split_on_char '\n' report in
    let rec from_marker = function
      | [] -> lines
      | line :: rest when StringExtra.is_prefix "== Run directories" line -> line :: rest
      | _ :: rest -> from_marker rest
    in
    String.concat "\n" (from_marker lines)
  in
  (* What the tool DID, as opposed to what it saw: every line it prints about its own actions is
     prefixed with its name, the report is not. Showing the whole output would bury the two lines
     that matter under the list of orphan processes -- measured on the real dialog. Falls back to
     the whole output if nothing matches, so a change in the script cannot make the result empty. *)
  let action_lines (script : string) (output : string) : string =
    let prefix = (Filename.basename script) ^ ":" in
    match List.filter (StringExtra.is_prefix prefix) (String.split_on_char '\n' output) with
    | []    -> output
    | lines -> String.concat "\n" lines
  in
  let in_a_thread (f : unit -> unit) () =
    ignore (Thread.create (fun () ->
      try f () with e ->
        Log.printf1 "marionnet: the cleanup tool raised: %s\n" (Printexc.to_string e)) ())
  in
  let show ~script ~title (output : string) =
    Simple_dialogs.info title (Glib.Markup.escape_text (action_lines script output)) ()
  in
  (* A failure is shown whole: the reason may well be in a line the filter would drop. *)
  let failed (output : string) =
    Simple_dialogs.error (s_ "The cleanup tool failed") (Glib.Markup.escape_text output) ()
  in
  (* Recovering: one .mar per abandoned run directory, and then the directories that were really
     saved are removed -- the whole point being to end with the work kept and the disk clean. No
     confirmation is asked because nothing is lost: the tool removes ONLY what it has just written
     into an archive, and keeps whatever it could not save (see do_purge_dirs, which narrows its
     victims to ARCHIVED_DIRS as soon as --archive-dirs is given). The button says so. *)
  let recover script () =
    let destination = archive_destination () in
    let (output, ok) =
      run_cleanup script [Printf.sprintf "--archive-dirs %s" (Filename.quote destination); "--purge-dirs"]
    in
    if ok
      then show ~script
             ~title:(Printf.sprintf
                       (f_ "Projects recovered into %s, and their run directories removed")
                       (Glib.Markup.escape_text destination))
             output
      else failed output
  in
  (* Cleaning: destroys unsaved work, so the report comes first and the user answers a question
     whose text is the tool's own words. *)
  let clean script () =
    let (report, _) = run_cleanup script [] in
    let question =
      Printf.sprintf
        (f_ "About to remove the run directories that no live session is using. THE UNSAVED WORK THEY HOLD WILL BE LOST -- recover it first if you have not. This is what the cleanup tool sees:\n\n%s\n\nRemove them?")
        (Glib.Markup.escape_text (directories_section report))
    in
    match Simple_dialogs.confirm_dialog ~question ~script_answer:false () with
    | Some true ->
        let (output, ok) = run_cleanup script ["--purge-dirs"] in
        if ok then show ~script ~title:(s_ "Run directories removed") output else failed output
    | _ -> ()
  in
  let actions =
    match cleanup_command () with
    | None -> []
    | Some script ->
        [ ((s_ "Recover and clean up"), in_a_thread (recover script));
          ((s_ "Remove the directories"), in_a_thread (clean script)) ]
  in
  Simple_dialogs.warning
    ~actions
    (s_ "Run directories left behind")
    (Printf.sprintf
       (f_ "Run directories left in %s by past sessions: %d. Each holds the working copy of a project that was not saved, which is why Marionnet never removes any of them by itself; some may even belong to another Marionnet running right now. You may sort them out whenever you like, with the command:\n\nmarionnet-cleanup --archive-dirs DIRECTORY --purge-dirs\n\nwhich first saves each of those projects as a .mar file into DIRECTORY, then removes the directories it could save.%s")
       (Glib.Markup.escape_text dir) n
       (if actions = [] then "" else
          "\n\n" ^ (s_ "The buttons below do exactly that, right now.")))
    ()

(* Check that we're *not* running as root. Yes, this has been reversed
   since the last version: *)
let () = begin
  Log.printf "Loading module bin/marionnet.ml: checking whether Marionnet is running as root...\n";
  if (Unix.getuid ()) = 0 then begin
    Log.printf "
**********************************************
* Marionnet should *not* be run as root, for *
* security reasons.                          *
* Continuing anyway...                       *
**********************************************\n\n";
    Simple_dialogs.warning
      (s_ "You should not be root!")
      (s_ "Marionnet is running with UID 0; this is bad from a security point of view... Continuing anyway.")
      ();
  end
end

(* --- *)
(** Make sure that the user installed all the needed software: *)
(* --- *)
let () = Log.printf "Loading module bin/marionnet.ml: about to check dependencies\n"
let check_call ~action ~arg ~error_message =
  try
    ignore (action arg)
  with e -> (
    flush_all ();
    Simple_dialogs.error
      (s_ "Unsatisfied dependency")
      (error_message ^ (s_ "\nContinuing anyway, but *some important features will be missing*."))
      ())

let check_dependency command_line error_message =
  check_call ~action:Log.system_or_fail ~arg:command_line ~error_message

let machine_installations = Lazy_perishable.force (Disk.get_machine_installations)
let router_installations  = Lazy_perishable.force (Disk.get_router_installations)

(** Check whether we have UML computer filesystems: *)
let () =
  let error_message = (s_ "You don't have a default filesystem for virtual computers") in
  let action () = Option.extract machine_installations#filesystems#get_default_epithet  in
  check_call ~action ~arg:() ~error_message

(** Check whether we have UML router filesystems: *)
let () =
  let error_message = (s_ "You don't have a default filesystem for virtual routers") in
  let action () = Option.extract router_installations#filesystems#get_default_epithet in
  check_call ~action ~arg:() ~error_message

(** Check whether we have UML kernels: *)
let () =
  let error_message = (s_ "You don't have a default UML kernel for virtual computers") in
  let action () = Option.extract machine_installations#kernels#get_default_epithet  in
  check_call ~action ~arg:() ~error_message

(** Check whether we have (our patched) VDE: *)
let () =
  check_dependency
    ("which `basename " ^ Initialization.Path.vde_prefix ^ "vde_switch`")
    (s_ "You don't have the VDE tool vde_switch")

(** Check whether we have (our patched) VDE: *)
let () =
  check_dependency
    ("which `basename " ^ Initialization.Path.vde_prefix ^ "slirpvde`")
    (s_ "You don't have the VDE tool slirpvde")

(** Check whether we have Graphviz: *)
let () =
  check_dependency
    "which dot"
    (s_ "You don't have Graphviz")


(** Read and check filesystem's installations. Warning dialogs
    are created when something appears wrong or strange. *)
module VM_installations =
  Disk.Make_and_check_installations(struct end)

module Motherboard = Created_window_MARIONNET.Motherboard

let () = begin

(** Set the main window icon (which may be the exam icon...), and the window title: *)
st#mainwin#toplevel#set_icon (Some Icon.icon_pixbuf);
st#mainwin#window_MARIONNET#set_title Initialization.window_title;

StackExtra.push (st#mainwin#notebook_CENTRAL#coerce) (st#sensitive_when_Active);
StackExtra.push (st#mainwin#hbox_BASE#coerce)        (st#sensitive_when_Runnable);

let () = Motherboard.sensitive_widgets_initializer () in

(* Open the project specified at command line, if any: *)
let () =
  match !Initialization.optional_file_to_open with
  | None -> ()
  | Some filename ->
      begin
	let filename =
	  FilenameExtra.to_absolute
	    ~parent:Initialization.cwd_at_startup_time
	    filename
	in
	try
	  let _t : Thread.t = st#open_project_async ~filename in
	  (* --- *)
	  if !Initialization.option_r = None then () else (* continue: *) begin
  	    let _ = GMain.Timeout.add ~ms:1000 (* 1 second *) ~callback:(fun () ->
	      if st#active_project then (Thread.delay 0.1; st#startup_everything (); false) else true)
	    in ()
	    end
	with
	  _ ->
	  begin
	    Printf.kfprintf flush stderr (f_ "Error: something goes wrong opening the file %s\nExiting.\n") filename;
	    exit 2
	  end
      end
in

(* Ignore some signals: *)
(* List.iter (fun x -> (Sys.set_signal x  Sys.Signal_ignore)) [1;2;3;4;5;6;10;12;15] ;; *)

(* This is very appropriate: a signal 15 (SIGTERM) may be received by Marionnet in some very complicated cases.
   For instance when a graphical program running in background on a virtual machine is showing its
   window on the X server (by the mean of a "socat" process or thread). If the command `halt' is
   launched on the virtual machine, a signal 15 is sent to Marionnet, probably as consequence of
   the broken connection (and the death of the "socat" process or thread). *)
let () =
  let callback _ =
   try
    (* Printf.kfprintf flush stderr "******************* HERE *********************\n"; *)
    let thread_id = Thread.id (Thread.self ()) in
    if thread_id = 0
    then GtkThread.main ()
    else () (* Printf.kfprintf flush stderr "******************* IGNORING *********************\n" *)   (* ignore *)
   with _ -> ()
  in
  Sys.set_signal Sys.sigterm (Sys.Signal_handle callback)
in

(* I we receive a CTRL-C from the terminal (2) we react as if the user click on the window close button: *)
let () =
 let callback _ =
   let () = Created_window_MARIONNET.Created_menubar_MARIONNET.Created_entry_project_quit.callback () in
   if st#quit_async_called then () else GtkThread.main ()
 in
 Sys.set_signal Sys.sigint (Sys.Signal_handle callback)
in

(* (* (* let () = SysExtra.log_signal_reception ~except:[26] () in *) *) *)

(* Try to kill all remaining descendants when exiting: *)
let () =
  let marionnet_pid = Unix.getpid () in
  let kill_orphan_descendants =
    Descendants_monitor.start_monitor_and_get_kill_method ()
  in
  (*Pervasives.*)at_exit
    (fun () ->
       begin
         Log.printf "at_exit: killing all current descendants before exiting...\n";
         (* Note here that the parameter `wait_delay' is set to 0. in order to kill the whole hierarchy in the quickest way
            (and directly with the must brutal signal `Sys.sigkill'). We need to be so violent because the UML Linux kernels
            (of the series 3.2.x) react to some signals restarting immediately a port-helper. This process will be attached
            to init (1) and will remain unnecessarily in the system. Furthermore, it may busy inexplicably the port 6000
            instead of Marionnet, when Marionnet exits. Thus, when Marionnet is restarted, it believes that the port is taken
            by a real X server! *)
         Linux.Process.kill_descendants ~signal_sequence:[Sys.sigkill] ~wait_delay:0. ~node_max_retries:2 ~root_max_retries:2 ();
         (* We kill orphans of the main program (not of its forks) *)
         if (Unix.getpid () = marionnet_pid) then begin
           Log.printf "at_exit: killing all orphans before exiting...\n";
           kill_orphan_descendants ();
           end;
       end)
in

(* --- *)
(** Enter the GTK+ main loop: *)
(* --- *)
let rec main_loop () =
  try
    GtkThread.main ()
  with e ->
    begin
    Log.printf "Marionnet's main loop interrupted by the following exception:\n";
    Log.print_backtrace ();
    Thread.delay 1.;
    if st#quit_async_called then (raise e) else main_loop ()
    end
in
let () = Log.printf "Loading module bin/marionnet.ml: about to starting the application\n" in
(* --- *)
(* Scripting control channel, if --control-socket was given. Started here on purpose:
   after the global state (st) and after the main window has been built, but before the
   GTK main loop, so that the first client finds a complete application. *)
let () = Control_server.start_if_requested (st) in
(* --- *)
main_loop ()

end
