(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008  Luca Saiu
   Copyright (C) 2009, 2010  Jean-Vincent Loddo
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
module Ocamlbricks_log = Ocamlbricks.Ocamlbricks_log
module Argv = Ocamlbricks.Argv
module Option = Ocamlbricks.Option
module PervasivesExtra = Ocamlbricks.PervasivesExtra
module StrExtra = Ocamlbricks.StrExtra
module StringExtra = Ocamlbricks.StringExtra
module FilenameExtra = Ocamlbricks.FilenameExtra
module Thunk = Ocamlbricks.Thunk
module Ipv4 = Ocamlbricks.Ipv4
module Ipv6 = Ocamlbricks.Ipv6
(* --- *)

open Gettext

(* ***************************************** *
             Get basic infos
 * ***************************************** *)

let user_intelligible_version, released =
 match StrExtra.First.matchingp (Str.regexp "^[0-9]+[.][0-9]+[.][0-9]+$") Version.version with
 | true  ->
     (* it's a released version *)
     (Version.version, true)
 | false ->
     (* It's just the name of the branch *)
     let str = Printf.sprintf "%s revno %s" Version.version Meta.revision in
     (str, false)
;;

(* ***************************************** *
               Parse argv
 * ***************************************** *)

let () =
  Argv.register_usage_msg
    (Printf.sprintf "Usage: %s [OPTIONS] [FILE]\nOptions:" Sys.argv.(0))
;;

(* Registering options: *)
let option_v      = Argv.register_unit_option "v" ~aliases:["-version"] ~doc:"print version and exit" () ;;
let option_debug  = Argv.register_unit_option "d" ~aliases:["-debug"]   ~doc:"activate messages for debugging" () ;;
let option_splash = Argv.register_unit_option "-splash" ~doc:"print splash message and exit" () ;;
let option_exam   = Argv.register_unit_option "-exam"   ~doc:"switch to student exam mode" () ;;
(* Exam locks (journalisation-profonde, episode 22): in exam mode a component which has already
   run cannot be removed, because removing it throws away its states, its hostfs and its
   journals. This option gives that gesture back to whoever runs the session. *)
let option_exam_allow_delete =
  Argv.register_unit_option "-exam-allow-delete"
    ~doc:"in exam mode, allow removing components which have already run"
    () ;;
let option_paths  = Argv.register_unit_option "-paths"  ~doc:"print paths (filesystems, kernels, ..) and exit" () ;;
(* Console recording (journalisation-profonde, episode 6): opt-in, and implied by --exam.
   Recording a session in silence outside an exam would be surveillance (decision D5). *)
let option_console_log =
  Argv.register_unit_option "-console-log"
    ~doc:"record each virtual machine's console into <project>/<name>-console.log (implied by --exam)"
    () ;;
(* Terminal recording (journalisation-profonde, episode 8): a distinct option, not a mode of the
   one above, because the two streams are distinct and so are their stakes — the console carries
   what the kernel says, this one carries what a person types. *)
let option_terminal_log =
  Argv.register_unit_option "-terminal-log"
    ~doc:"record each virtual machine's terminal into <project>/<name>-terminal.log (implied by --exam)"
    () ;;
let option_r      = Argv.register_unit_option "r" ~aliases:["-run"] ~doc:"immediately run the specified project (if any)" () ;;
(* Opt-in scripting channel (control_server.ml): without this option no socket is created. *)
let option_control_socket =
  Argv.register_string_option "-control-socket"
    ~arg_name_in_help:"PATH"
    ~doc:"serve the scripting control channel on the unix socket PATH (absolute)"
    () ;;
(* Script mode (script_mode.ml) is implied by --control-socket: a driven session has nobody
   to close the windows Marionnet opens by itself. These two options tune it; the second is
   also what makes a driven session observable by a human watching the screen. *)
let option_keep_dialogs =
  Argv.register_unit_option "-keep-dialogs"
    ~doc:"in a driven session (--control-socket), leave self-opening windows on screen as usual"
    () ;;
let option_dialog_timeout =
  Argv.register_int_option "-dialog-timeout"
    ~arg_name_in_help:"MS"
    ~doc:"in a driven session, how long a captured window stays visible before closing itself (default: 2000)"
    () ;;
let () = Argv.register_h_option_as_help () ;;

(* Registering arguments: *)
let optional_file_to_open =
  let error_msg =
    Printf.sprintf
      (f_ "%s: expected a readable regular file containing the marionnet project (.mar)")
      Sys.argv.(0)
  in
  Argv.register_filename_optional_argument ~r:() ~f:() ~error_msg () ;;

(* Argv.parse tuning: *)
let () = Argv.tuning
  ~no_error_location_parsing_arguments:()
  ~no_usage_on_error_parsing_arguments:()
  () ;;

(* Parse now (except if we are debugging with the toplevel): *)
let () =
  if not !Sys.interactive then Argv.parse ()
;;

(* Now we may inspect the references: *)

(* ***************************************** *
    --control-socket: bounded by sun_path
 * ***************************************** *)

(* The unix address of a socket carries its path in a fixed-size field, [sun_path], of 108
   bytes including the terminating NUL: 107 usable. A longer path is not truncated, the
   [bind] simply fails. Checked here, where the option is read, because it is a property of
   the argument and needs no side effect; control_server.ml calls this same function again
   just before binding, so the bound has a single source. *)
let sun_path_usable_bytes = 107

let check_control_socket_path (path:string) : (unit, string) result =
  if Filename.is_relative path then
    Error (Printf.sprintf "an absolute path is required (got %S)" path)
  else
  let length = String.length path in
  if length > sun_path_usable_bytes then
    Error
      (Printf.sprintf
         "the path is %d bytes long, more than the %d bytes a unix socket address (sun_path) can hold"
         length sun_path_usable_bytes)
  else
    Ok ()
;;

(* A driven session which cannot be driven has no reason to run: --control-socket implies
   script mode (script_mode.ml), and it is a bench, not a human, which launches it. Hence a
   refusal to start, on stderr, with the exit code Argv.parse itself uses for a bad argument
   (lib/BASE/argv.ml). Failures which can only be seen later (permissions, a socket already
   served) are refused in the same spirit by Control_server.start_if_requested. *)
let () =
  match !option_control_socket with
  | None -> ()
  | Some path ->
      (match check_control_socket_path path with
       | Ok () -> ()
       | Error detail ->
           Printf.kfprintf flush stderr "%s: --control-socket: %s\n" Sys.argv.(0) detail;
           exit 1)
;;

let () = if !option_v = Some () then begin
  Printf.kfprintf flush stdout "marionnet version %s\n" (user_intelligible_version);
  exit 0;
 end;;

let do_not_print_splash_message =
  (!option_paths = Some ())
;;

(* else continue: *)
let () = if do_not_print_splash_message = false then
Log.printf6 ~v:0 ~banner:false
  "=======================================================
 Welcome to %s
 Version              : %s
 Source revision      : %s
 Ocaml version        : %s

 Built in date %s on system:

%s

 For bug reporting, please get a launchpad account and
 either:
  - report bugs at https://bugs.launchpad.net/marionnet
 or do *all* the following:
  - add yourself to the marionnet-dev team
  - add yourself to the marionnet-dev mailing list
  - write to marionnet-dev@lists.launchpad.net
=======================================================\n"
  Meta.name
  Meta.version
  (Printf.sprintf "%s - %s" Meta.revision Meta.source_date)
  Meta.ocaml_version
  Meta.build_date
  (StringExtra.fmt ~tab:8 ~width:40 Meta.uname)
;;

(* Behaviour for option --splash *)
let () = if !option_splash = Some () then exit 0;;

(* else continue: *)

(* Seed the random number generator: *)
Random.self_init ();;

(** Remember the cwd directory at startup time: *)
let cwd_at_startup_time =
  Unix.getcwd ();;

(** Workaround for Ubuntu with Unity.
    Ugly: it's a pain to write code depending to the GNU/Linux distribution!
    I accept because the workaround is very simple. J.V. Loddo *)
let () = Unix.putenv "UBUNTU_MENUPROXY" "0" ;;

(** Firstly read if the debug mode must be activated.
    In this way the variable parsing can be monitored. *)
module Debug_level = struct

  let of_bool = function
    | false -> 0
    | true  -> 1

  let default_level =
    of_bool ((!option_debug=Some()) ||
             (Configuration.extract_bool_variable_or ~default:false "MARIONNET_DEBUG"))

  let current = ref default_level
  let set x = (current := x)
  let get () = !current

  let are_we_debugging () = ((get ())>0)
  let set_from_bool b = set (of_bool b)

  (** Interpret the current state as suffix to append to shell commands. *)
  let redirection () =
    if are_we_debugging () then "" else " 1>/dev/null 2>/dev/null "

end (* Initialization.Debug_level *)

(** Link the function used by the marionnet's and the ocamlbricks's logs with Debug_mode.get: *)
let () =
  Log.Tuning.Set.debug_level Debug_level.get;
  Ocamlbricks_log.Tuning.Set.debug_level Debug_level.get
;;

let () = Log.printf2
  "MARIONNET_DEBUG is %b (debug level %d)\n"
  (Debug_level.are_we_debugging ()) (* is true iff you read the message *)
  (Debug_level.get ())
;;

(* Now, and not before, the catalogue's cascade may tell what it decided: it ran while this
   module was still being linked, when the log's level was the constant 0 of marionnet_log.ml.
   Cf. Gettext.log_diagnosis (episode 15 of `marionnet-todo-transverse'). *)
let () = Gettext.log_diagnosis () ;;

(* Same reason, same moment: the cascade of configuration files ran even earlier than the
   catalogue's -- Configuration is what reads MARIONNET_PREFIX (episode 25). *)
let () = Configuration.log_diagnosis () ;;

(* Student exam mode: *)
let are_we_in_exam_mode = (!option_exam = Some ()) ;;
let () = Log.printf1 "Student exam mode: %b\n" are_we_in_exam_mode ;;
let window_title = match are_we_in_exam_mode with
 | false -> "Marionnet"
 | true  -> "Marionnet (EXAM)"
;;

(* Console recording (journalisation-profonde, episode 6). The only probe out of the guest's
   reach: the two journals of episodes 1-2 live in a hostfs the student may rewrite, whereas
   this one is written by the host, and it is the only one that sees a boot which never reaches
   the relay (a panic, a broken init). Hence: opt-in, but implied by the exam mode, whose whole
   point is a defensible record. No persisted attribute is involved (decision D5): this is a
   property of the *session*, not of the project. *)
let are_we_recording_consoles =
  (!option_console_log = Some ()) || are_we_in_exam_mode
;;
let () = Log.printf1 "Console recording: %b\n" are_we_recording_consoles ;;

(* Terminal recording (journalisation-profonde, episode 8). The console above is what the kernel
   prints; this is what crosses the window a student works in — their commands AND the answers,
   as they saw them. Recorded host-side, hence out of the guest's reach (decision D2), and never
   in silence: opt-in, implied by the exam mode alone. *)
let are_we_recording_terminals =
  (!option_terminal_log = Some ()) || are_we_in_exam_mode
;;
let () = Log.printf1 "Terminal recording: %b\n" are_we_recording_terminals ;;

(* Exam locks (journalisation-profonde, episode 22). The exam mode archives what a session left
   behind (report, command history, console, terminal) at ONE point only: the graceful shutdown
   of a machine or a router. Every other way of stopping a guest bypasses that archiving, so it
   destroys the copy the teacher is supposed to grade — and the most accessible of them, the
   "Power-off all" button, sits right next to the good one in the bottom toolbar. Hence: in exam
   mode a brutal power cut is not offered at all. *)
let are_we_allowed_to_poweroff = not are_we_in_exam_mode ;;
let () = Log.printf1 "Poweroff allowed: %b\n" are_we_allowed_to_poweroff ;;

(* Removing a component destroys its states, its hostfs and therefore its journals. In exam mode
   this is refused for a component which has left a trace — one which has run at least once —
   while a component which was never started stays removable: it has produced nothing, and a
   student building their own topology must be able to undo a mistake. The option below lifts the
   restriction altogether, for a teacher who wants the plain behaviour back. *)
let are_we_allowed_to_delete =
  (not are_we_in_exam_mode) || (!option_exam_allow_delete = Some ())
;;
let () = Log.printf1 "Deletion allowed (even of components which ran): %b\n" are_we_allowed_to_delete ;;

(* Used as continuation (~k) calling `extract_string_variable_or': *)
let append_slash x = x ^ "/" ;;

(* What is terminal that Marionnet must use to lanch a virtual host *)
let marionnet_terminal =
  let default = "xterm,-T,-e" in
  Configuration.extract_string_variable_or ~default "MARIONNET_TERMINAL" ;;

let router_filesystem_default_epithet =
  let default = "default" in
  Configuration.extract_string_variable_or ~default "MARIONNET_ROUTER_FILESYSTEM"

let router_kernel_default_epithet =
  let default = "default" in
  Configuration.extract_string_variable_or ~default "MARIONNET_ROUTER_KERNEL"

let machine_filesystem_default_epithet =
  let default = "default" in
  Configuration.extract_string_variable_or ~default "MARIONNET_MACHINE_FILESYSTEM"

let machine_kernel_default_epithet =
  let default = "default" in
  Configuration.extract_string_variable_or ~default "MARIONNET_MACHINE_KERNEL"

(* The host kernel version, for instance (6,8), read once from /proc/sys/kernel/osrelease: *)
let host_kernel_version : (int * int) option =
  try
    let ic = open_in "/proc/sys/kernel/osrelease" in
    let line = (try input_line ic with e -> (close_in ic; raise e)) in
    let () = close_in ic in
    Scanf.sscanf line "%d.%d" (fun a b -> Some (a, b))
  with _ -> None

(* Old UML kernels (the 2.6.x/3.2.x "-ghost" series) have a SKAS0 stub that segfaults on
   modern hosts: proven broken on 6.8, presumed broken since the 5.15 series (the exact
   breaking host version could not be established). On such hosts, projects referencing
   these kernels are automatically switched at loading time to a modern i386 UML kernel,
   when available (see the remapping methods in User_level.virtual_machine_with_history_and_ifconfig): *)
let old_uml_breaking_host_version = (5, 15)

let host_kernel_breaks_old_uml_stubs : bool =
  match host_kernel_version with
  | Some v -> (v >= old_uml_breaking_host_version)
  | None   -> false

(* Whether the UML kernel named by the given epithet can boot on this host: the 2.6.x/3.2.x
   "-ghost" series segfaults (SKAS0 stub) on hosts >= old_uml_breaking_host_version, and a
   machine coupled to one only loops on "can't run '/sbin/getty': Input/output error", with
   no hint about the cause. Every creation path must therefore prefer a bootable kernel
   (Disk.bootable_supported_kernels_of) and speak up when none is available (GUI dialog,
   control server) instead of building an unbootable component: *)
let uml_kernel_broken_on_this_host (k:string) : bool =
  host_kernel_breaks_old_uml_stubs &&
  (match String.split_on_char '.' k with
   | s :: _ -> (match int_of_string_opt s with Some major -> major < 4 | None -> false)
   | []     -> false)

let () = Log.printf2
  "Host kernel version: %s (obsolete UML kernels remapped at project loading: %b)\n"
  (match host_kernel_version with Some (a,b) -> Printf.sprintf "%d.%d" a b | None -> "unknown")
  (host_kernel_breaks_old_uml_stubs)

(* Path related configuration variables.
   TODO: make it more robust and logged *)
module Path = struct

 let marionnet_home =
   let default = (Meta.prefix ^ "/share/" ^ Meta.name) in
   Configuration.extract_string_variable_or ~k:append_slash ~default "MARIONNET_PREFIX"

 let filesystems =
   let default = (marionnet_home^"filesystems/") in
   Configuration.extract_string_variable_or ~k:append_slash ~default "MARIONNET_FILESYSTEMS_PATH"

 let kernels =
   let default = (marionnet_home^"kernels/") in
   Configuration.extract_string_variable_or ~k:append_slash ~default "MARIONNET_KERNELS_PATH"

 (* --- *)
 (* Where the data VERSIONED in this repository (the glade, the images) are read from.
    This is not the same question as `marionnet_home', and that is the whole point: the
    prefix that `dune build' produces holds the versioned data, but an EMPTY `filesystems/'
    and NO `kernels/' at all (measured 2026-08-22). Switching the prefix as a whole would
    therefore deprive a development run of its guest filesystems and of its kernels. Hence a
    choice made directory by directory: versioned data from this repository when we run from
    the build tree, installed data (`filesystems/', `kernels/') from the installation prefix
    as before.
    ---
    Before this (episode 22 of the work-stream `marionnet-todo-transverse'), a binary of
    `_build' read the `gui/gui_glade3.xml' and the `images/' of ANOTHER Marionnet -- the one
    installed on this machine, possibly years old -- so that a modification of the glade
    stayed invisible until `make install'. Same defect, one notch higher, as the catalogue
    one of episode 15 (bin/gettext.ml).
    ---
    MARIONNET_PREFIX comes first: an explicit override must win over an inference, exactly as
    MARIONNET_LOCALEPREFIX does for the catalogues. And a directory of the development tree
    is retained only if it really holds the glade -- a build tree on which `dune build' has
    not run yet holds nothing, and there the installed prefix is still the best we have. *)
 let versioned_data_home =
   let from_the_development_tree () =
     match Development_tree.share_directory () with
     | Some dir when Sys.file_exists (Filename.concat dir "gui/gui_glade3.xml") -> Some (append_slash dir)
     | _ -> None
   in
   match Configuration.get_string_variable "MARIONNET_PREFIX" with
   | Some _ ->
       Log.printf1 "Path: glade and images taken from MARIONNET_PREFIX: %s\n" marionnet_home;
       marionnet_home
   | None ->
      (match from_the_development_tree () with
       | Some dir ->
           Log.printf1 "Path: glade and images taken from the development tree (_build): %s\n" dir;
           dir
       | None ->
           Log.printf1 "Path: glade and images taken from the installation prefix: %s\n" marionnet_home;
           marionnet_home
       )

 (* --- *)
 let marionnet_home_gui = versioned_data_home^"gui/"
 (* --- *)
 let images = versioned_data_home^"images/"
 let leds   = versioned_data_home^"images/leds/"

 (* The prefix to prepend to VDE executables; this allows us to install
    patched versions in an easy way, before our changes are integrated
    into VDE's mainline... *)
 let vde_prefix =
   Configuration.extract_string_variable_or ~default:"" "MARIONNET_VDE_PREFIX";;

 (* User installation: *)

 let user_home =
   try (Sys.getenv "HOME") with Not_found ->
   try ("/home/"^(Sys.getenv "USER")) with Not_found ->
   try ("/home/"^(Sys.getenv "LOGNAME")) with Not_found ->
   try (Sys.getenv "PWD") with Not_found ->
   "."

 let user_filesystems = user_home^"/.marionnet/filesystems"
 let user_kernels = user_home^"/.marionnet/kernels"

 let marionnet_tmpdir : string option =
   Configuration.get_string_variable "MARIONNET_TMPDIR"

end (* Path *)
;;

(* Timezone (useful to configure the guest time) *)
let marionnet_timezone : string option =
 let attempt1 () = Configuration.get_string_variable "MARIONNET_TIMEZONE" in
 let attempt2 () = try Some(Sys.getenv "TZ") with Not_found -> None in
 let attempt3 () = PervasivesExtra.get_first_line_of_file "/etc/timezone" in
 (* A simple safety check: *)
 let check timezone =
   Sys.file_exists (Filename.concat "/usr/share/zoneinfo" timezone)
 in
 Thunk.first_attempt check [attempt1; attempt2; attempt3]
;;

(* Behaviour for option --paths *)
let () = if !option_paths = Some () then
  let prettify =
    FilenameExtra.remove_trailing_slashes_and_dots
  in
  let filesystems      = prettify Path.filesystems in
  let kernels          = prettify Path.kernels in
  let binaries         = Filename.concat Meta.prefix "bin" in
  let gui              = prettify Path.marionnet_home_gui in
  let images           = prettify Path.images in
  let user_filesystems = prettify Path.user_filesystems in
  let user_kernels     = prettify Path.user_kernels in
  let tmpdir           = prettify (Option.extract_or Path.marionnet_tmpdir "") in
  begin
    Printf.printf "filesystems      : %s\n" filesystems;
    Printf.printf "kernels          : %s\n" kernels;
    Printf.printf "binaries         : %s\n" binaries;
    Printf.printf "gui              : %s\n" gui;
    Printf.printf "images           : %s\n" images;
    Printf.printf "user-filesystems : %s\n" user_filesystems;
    Printf.printf "user-kernels     : %s\n" user_kernels;
    Printf.printf "tmpdir           : %s\n" tmpdir;
    exit 0;
  end;;

(* Warnings related configuration variables. *)
module Disable_warnings = struct

let temporary_working_directory_automatically_set =
  Configuration.extract_bool_variable_or
    ~default:false
    "MARIONNET_DISABLE_WARNING_TEMPORARY_WORKING_DIRECTORY_AUTOMATICALLY_SET"

(* The startup notice about the run directories left behind by past sessions
   (marionnet.ml). Provided for the same reason as the one above: a warning that
   cannot be turned off becomes a warning nobody reads. *)
let orphan_run_directories =
  Configuration.extract_bool_variable_or
    ~default:false
    "MARIONNET_DISABLE_WARNING_ORPHAN_RUN_DIRECTORIES"

(* The two notices about another Marionnet running at the same time (marionnet.ml at
   start-up, simulation_level.ml when a tap collision actually happens). A single flag
   for both: they say the same thing at two moments, and somebody who knows why two
   sessions coexist wants neither. *)
let other_marionnet_sessions =
  Configuration.extract_bool_variable_or
    ~default:false
    "MARIONNET_DISABLE_WARNING_OTHER_MARIONNET_SESSIONS"

end (* Warnings *)

(* Default for the factory-set configuration address for routers.
   The result is a couple (ip,nm) where ip is the 4-tuple IPv4 and nm is the CIDR netmask. *)
let router_port0_default_ipv4_config : Ipv4.config =
 let variable_name = "MARIONNET_ROUTER_PORT0_DEFAULT_IPV4_CONFIG" in
 let default = "192.168.1.254/24" in
 let value = Configuration.extract_string_variable_or ~default variable_name in
 let parse arg = Ipv4.config_of_string arg in
 try parse value
 with _ -> begin
   Log.printf1 ~force:true "Warning: ill-formed value for %s\n" variable_name;
   parse default
   end
;;

let router_port0_default_ipv6_config : Ipv6.config option =
 let variable_name = "MARIONNET_ROUTER_PORT0_DEFAULT_IPV6_CONFIG" in
 let ovalue = Configuration.get_string_variable variable_name in
 let parse arg = Ipv6.config_of_string arg in
 let parsed_value =
   try Option.map parse ovalue
   with _ -> begin
     Log.printf1 ~force:true "Warning: ill-formed value for %s\n" variable_name;
     None
   end
 in
 parsed_value
;;

let keep_all_snapshots_when_saving =
  Configuration.extract_bool_variable_or
    ~default:false
    "MARIONNET_KEEP_ALL_SNAPSHOTS_WHEN_SAVING"

