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

(* Interface documentation is in privileges.mli (single source). What follows are
   implementation notes only. *)

(* --- *)
module Log = Marionnet_log
(* --- *)
module UnixExtra = Ocamlbricks.UnixExtra
(* --- *)

open Gettext

(* --- Where the script is
   ---
   `sudo' resolves a bare command name against its own secure_path, not against
   ours, and share/marionnet/scripts/ is not in it: what we hand to sudo must
   therefore be an ABSOLUTE path. The name itself comes from Tap_provider, so
   that MARIONNET_SUDOERS_SCRIPT keeps being read in exactly one place. *)
let script_path () : (string, string) result =
  let name = Tap_provider.sudoers_script () in
  if String.contains name '/' then
    Ok (if Filename.is_relative name then Filename.concat (Sys.getcwd ()) name else name)
  else
    (* `command -v' searches OUR PATH, which is where the installed script lives. *)
    match UnixExtra.run (Printf.sprintf "command -v %s" (Filename.quote name)) with
    | (output, Unix.WEXITED 0) when String.trim output <> "" -> Ok (String.trim output)
    | _ ->
        Error (Printf.sprintf (f_ "the command `%s' cannot be found") name)

(* --- Running it as root
   ---
   The password goes on sudo's STDIN and nowhere else: not in argv (`ps' shows
   argv to every account on the machine), not in a file, not in the environment.
   Output — the script's own diagnostic — is collected in a temporary file rather
   than in a second pipe: with two pipes and a single reader, a talkative command
   filling one of them while we read the other is a deadlock waiting for its day.
   ---
   The exit code is kept, not just a boolean: 1 is what sudo returns when it
   refuses an authentication, and it is the (imperfect, but language-independent)
   signal that asking again makes sense. The script's own failures are 2 (usage)
   and 3 (a block that is not available yet). *)
let run_as_root ?password (arguments : string list) (script : string) : (unit, int * string) result =
  let trace = Filename.temp_file "marionnet-sudoers-" ".log" in
  let command =
    Printf.sprintf "sudo %s -- %s %s >%s 2>&1"
      (match password with None -> "-n" | Some _ -> "-S -p ''")
      (Filename.quote script)
      (String.concat " " (List.map Filename.quote arguments))
      (Filename.quote trace)
  in
  let channel = Unix.open_process_out command in
  let () =
    match password with
    | None -> ()
    | Some password ->
        (* SIGPIPE is ignored process-wide (marionnet.ml), so a sudo that died
           before reading gives us a Sys_error here instead of killing us. *)
        (try output_string channel (password ^ "\n"); flush channel with Sys_error _ -> ())
  in
  (* close_process_out closes the pipe — sudo's stdin then hits EOF, which is
     exactly what stops it from waiting for a second attempt — and waits. *)
  let status = Unix.close_process_out channel in
  let output = (try String.trim (UnixExtra.cat trace) with _ -> "") in
  let () = try Sys.remove trace with _ -> () in
  match status with
  | Unix.WEXITED 0 -> Ok ()
  | Unix.WEXITED code -> Error (code, output)
  | _ -> Error (-1, output)

(* --- The one block this episode activates *)

let max_attempts = 3

(* --enable-natbridge selects block (b), --only keeps block (a) out of the
   selection: the file the administrator wrote must not be rewritten by, and for,
   whoever happens to be running the GUI. *)
let natbridge_arguments = ["install"; "--only"; "--enable-natbridge"]

(* Why the verdict of a FAILED elevation is remembered: starting a single component
   resolves its bridge more than once (world_bridge.ml builds its simulated device,
   then starts it), so without this a user who cancels would be asked again, and told
   off again, within the same second. A refusal is an answer; asking twice for the
   same gesture is nagging. It holds for the session — to change one's mind, restart
   Marionnet, or run marionnet-sudoers.sh from a terminal. A SUCCESS needs no memory:
   Nat_bridge_host.is_usable answers `true' from then on and we return above. *)
let verdict : (unit, string) result option ref = ref None

let ensure_natbridge () : (unit, string) result =
  if Nat_bridge_host.is_usable () then Ok () else
  match !verdict with
  | Some (Error _ as remembered) ->
      let () = Log.printf "Privileges: the NAT bridge rights were already refused in this session; not asking again\n" in
      remembered
  | _ ->
  match script_path () with
  | Error _ as failure -> failure
  | Ok script ->
      let () = Log.printf1 "Privileges: the NAT bridge needs its sudoers block; calling %s\n" script in
      (* What we run, said plainly and in advance: a password dialog that does not
         say what it unlocks is how one teaches users to type it anywhere. *)
      let header =
        Printf.sprintf
          (f_ "Marionnet needs administrator rights to build the private NAT bridge that connects this component to the Internet.\n\nThe following command will be run, once:\n\n    %s %s\n\nPlease type your own password (the one you use with `sudo'):")
          (Filename.basename script) (String.concat " " natbridge_arguments)
      in
      let title = (s_ "Administrator rights required") in
      (* The verdict is memoised, and we are about to change what it answers. *)
      let succeeded () =
        Nat_bridge_host.forget_usability ();
        Nat_bridge_host.is_usable ()
      in
      (* The script said yes, so the honest question left is whether the host now
         behaves as it should: only the probe can answer that. *)
      let conclude_after_success () : (unit, string) result =
        if succeeded () then Ok () else
        Error (s_ "the sudoers rule was installed, but the host still refuses the commands the NAT bridge needs")
      in
      let conclude_after_failure ~(code : int) ~(output : string) : (unit, string) result =
        if succeeded () then Ok () else
        Error
          (Printf.sprintf (f_ "the sudoers rule could not be installed (exit code %d)%s")
             code
             (if output = "" then "" else Printf.sprintf ":\n%s" output))
      in
      (* First, without asking anything: a sudo ticket may still be valid (the
         user just started a virtual machine from a terminal, say), and in that
         case there is no reason to make them type their password again. *)
      let outcome =
        (* First, without asking anything -- see just below. *)
        match run_as_root natbridge_arguments script with
        | Ok () when succeeded () ->
            let () = Log.printf "Privileges: the NAT bridge block was installed with a live sudo ticket\n" in
            Ok ()
        | first_attempt ->
           let () =
             match first_attempt with
             | Ok () -> Log.printf "Privileges: `sudo -n' succeeded but the probe still refuses; asking for the password\n"
             | Error (code, _) -> Log.printf1 "Privileges: `sudo -n' failed (exit code %d); asking for the password\n" code
           in
           let rec attempt (n : int) : (unit, string) result =
             match Simple_dialogs.ask_password ~again:(n > 1) ~title ~header () with
             | None ->
                 Error (s_ "no administrator rights were granted: the NAT bridge cannot be built")
             | Some password ->
                 (match run_as_root ~password natbridge_arguments script with
                  | Ok () ->
                      let () = Log.printf "Privileges: the NAT bridge sudoers block is now installed\n" in
                      conclude_after_success ()
                  | Error (1, _) when n < max_attempts ->
                      (* sudo refuses an authentication with 1, and only then does
                         trying again make sense. *)
                      let () = Log.printf1 "Privileges: sudo refused the password (attempt %d)\n" n in
                      attempt (n + 1)
                  | Error (code, output) ->
                      let () = Log.printf2 "Privileges: the elevation failed (exit code %d): %s\n" code output in
                      conclude_after_failure ~code ~output)
           in
           attempt 1
      in
      (* Telling the user is done HERE, once, and not by the caller: a component is
         started through several code paths, and each of them would have shown the
         same window. The remembered verdict above is what makes "once" true. *)
      let () =
        match outcome with
        | Ok () -> ()
        | Error message ->
            verdict := Some (Error message);
            Simple_dialogs.error
              (s_ "Cannot build the private NAT bridge")
              (Printf.sprintf
                 (f_ "Marionnet could not obtain the administrator rights it needs: %s.\n\nThe components attached to this bridge will start all the same, but with no access to the real network. To grant those rights later, run in a terminal:\n\n    %s install --only --enable-natbridge")
                 message (Filename.basename script))
              ()
      in
      outcome
