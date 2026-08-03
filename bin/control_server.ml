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

(** Script control server: a line-oriented control channel on a unix socket, served
    in-process by a dedicated thread, so that Marionnet may be driven by a script (or by
    an agent) while its GUI stays alive and observable. Opt-in: without the option
    [--control-socket PATH] no socket exists, hence no attack surface.

    A request is a plain text line; an answer is exactly one JSON line. We only ever
    *emit* JSON and never parse it, so no dependency is added to the project.

    Design constraints inherited from the audit of [Ocamlbricks.Network]
    (docs/pilotage-par-script.md § 7.5), each honoured below:
    - N7  : on the line channel, use *only* #input_line / #output_line (the stdlib buffer
            and Unix.recv would not see the same bytes);
    - N9  : a peer closing its end is a normal end of session, not an error;
    - N10 : bound the number of concurrent sessions (each one costs a thread);
    - N12 : a stale socket file left behind by a brutal exit must not prevent a restart;
    - N16 : never use fresh_socketname (TOCTOU); the parent directory is ours, mode 0700;
    - N17 : never #peek.
    N18 (SIGPIPE) is neutralised in marionnet.ml: a global signal disposition belongs to
    the program, not to a module. *)

(* --- *)
module Log = Marionnet_log
(* Note: [Either] is the stdlib one here, as in gMain_actor.mli, *not* Ocamlbricks.Either. *)
module Future = Ocamlbricks.Future
module Network = Ocamlbricks.Network

(* ---------------------------------------------------------------- *)
(*                      JSON encoding (output only)                 *)
(* ---------------------------------------------------------------- *)

(* Bytes >= 0x80 are passed through: the payload is UTF-8, which JSON accepts as is. *)
let json_escape (s:string) : string =
  let b = Buffer.create (String.length s + 8) in
  let () =
    String.iter
      (function
        | '"'  -> Buffer.add_string b "\\\""
        | '\\' -> Buffer.add_string b "\\\\"
        | '\n' -> Buffer.add_string b "\\n"
        | '\r' -> Buffer.add_string b "\\r"
        | '\t' -> Buffer.add_string b "\\t"
        | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
        | c -> Buffer.add_char b c)
      s
  in
  Buffer.contents b

let jstr  (s:string) : string = Printf.sprintf "\"%s\"" (json_escape s)
let jbool (b:bool)   : string = if b then "true" else "false"
let jint  (i:int)    : string = string_of_int i
let jnull : string = "null"
let jopt  : string option -> string = function None -> jnull | Some s -> jstr s
let jlist (xs: string list) : string = Printf.sprintf "[%s]" (String.concat "," xs)

let jobj (fields : (string * string) list) : string =
  let field (k,v) = Printf.sprintf "%s:%s" (jstr k) v in
  Printf.sprintf "{%s}" (String.concat "," (List.map field fields))

let reply_ok (fields : (string * string) list) : string =
  jobj (("ok", jbool true) :: fields)

(* Normalised error codes (docs/pilotage-par-script.md § 4.1): unknown_command,
   bad_argument, no_active_project, unknown_node, forbidden_transition, timeout,
   internal. *)
let reply_error ~(code:string) ~(detail:string) : string =
  jobj [ ("ok", jbool false); ("error", jstr code); ("detail", jstr detail) ]

(* ---------------------------------------------------------------- *)
(*                          Request parsing                         *)
(* ---------------------------------------------------------------- *)

type request = {
  verb : string;
  arg  : string;                  (* positional part, see the note below *)
  opts : (string * string) list;  (* --key=value, or --key alone (empty value) *)
}

(* Positional tokens are joined back with a single space, so that a path containing
   spaces needs no quoting: every command of this episode takes at most one positional
   argument. Commands taking several arguments (episode 4: connect, ifconfig...) will
   need a real tokenisation, and possibly quoting. *)
let parse_request (line:string) : request option =
  let tokens = List.filter (fun s -> s <> "") (String.split_on_char ' ' (String.trim line)) in
  match tokens with
  | [] -> None
  | verb :: rest ->
      let is_option t = (String.length t > 2) && (String.sub t 0 2 = "--") in
      let option_tokens, argument_tokens = List.partition is_option rest in
      let parse_option t =
        let t = String.sub t 2 (String.length t - 2) in
        match String.index_opt t '=' with
        | None   -> (t, "")
        | Some i -> (String.sub t 0 i, String.sub t (i+1) (String.length t - i - 1))
      in
      Some {
        verb;
        arg  = String.concat " " argument_tokens;
        opts = List.map parse_option option_tokens;
      }

let option_value (r:request) (key:string) : string option = List.assoc_opt key r.opts

(* ---------------------------------------------------------------- *)
(*              Asking the GTK main thread, with a deadline         *)
(* ---------------------------------------------------------------- *)

let default_timeout = 5.0

type 'a outcome =
  | Done      of 'a
  | Failed    of exn
  | Timed_out of float

(* Delegate [f] to the GTK main thread and wait for its result at most [timeout] seconds.
   The deadline is what keeps this channel usable as an instrument: the GTK main loop is
   legitimately blocked while a menu is pulled down, while a dialog is up or during a long
   operation, and a control channel that would silently hang there could not diagnose
   anything. On expiry the future is abandoned (a GTK operation cannot be cancelled) but
   the session survives and the client is told why. *)
let ask ?(timeout=default_timeout) (f : unit -> 'a) : 'a outcome =
  let future = GMain_actor.future f () in
  let deadline = Unix.gettimeofday () +. timeout in
  let rec wait () =
    match Future.taste future with
    | Some (Either.Right v) -> Done v
    | Some (Either.Left e)  -> Failed e
    | None ->
        if Unix.gettimeofday () >= deadline then Timed_out (timeout) else
        let () = Thread.delay 0.05 in
        wait ()
  in
  wait ()

let reply_of_outcome (render : 'a -> string) : 'a outcome -> string = function
  | Done v      -> render v
  | Failed e    -> reply_error ~code:"internal" ~detail:(Printexc.to_string e)
  | Timed_out t ->
      reply_error ~code:"timeout"
        ~detail:(Printf.sprintf
                   "the GTK main thread did not answer within %.1fs (busy: modal dialog, pulled-down menu or long operation)"
                   t)

(* ---------------------------------------------------------------- *)
(*                             Commands                             *)
(* ---------------------------------------------------------------- *)

let cmd_status (st : State.globalState) ~(timeout:float) : string =
  ask ~timeout
    (fun () ->
       (st#project_paths#get_filename,
        st#active_project,
        st#runnable_project,
        st#project_already_saved,
        List.length (st#network#get_node_names)))
  |> reply_of_outcome
       (fun (file, active, runnable, saved, nodes) ->
          reply_ok [
            ("active",   jbool active);
            ("file",     jopt file);
            ("runnable", jbool runnable);
            ("saved",    jbool saved);
            ("nodes",    jint nodes);
            ])

(* The `kind' filter is applied outside the GTK main thread, on the extracted triples:
   nothing but the extraction itself needs to run there. *)
let cmd_ls (st : State.globalState) ~(timeout:float) ~(kind:string option) : string =
  ask ~timeout
    (fun () ->
       List.map
         (fun n -> (n#get_name, n#string_of_devkind, n#state_as_string))
         (st#network#get_node_list))
  |> reply_of_outcome
       (fun triples ->
          let triples =
            match kind with
            | None   -> triples
            | Some k -> List.filter (fun (_, devkind, _) -> devkind = k) triples
          in
          let node_of_triple (name, devkind, state) =
            jobj [ ("name", jstr name); ("kind", jstr devkind); ("state", jstr state) ]
          in
          reply_ok [
            ("count", jint (List.length triples));
            ("nodes", jlist (List.map node_of_triple triples));
            ])

(* Opening a project is *not* delegated to the GTK main thread, and this is deliberate:
   called from a thread which is not gtk_main, [open_project_async] performs the whole
   loading in the calling thread (state.ml:594-596) — the very case that test provides
   for, and the same code path the GUI menu takes in its own thread. Delegating it would
   instead spawn yet another thread and return immediately, i.e. lose the result.

   The loading swallows its own failures: they are reported by a (non-modal) dialog and a
   log line, and the exception never reaches us (state.ml:537-547, 567-580). So we do not
   pretend to know whether it succeeded: we report the state that *is*, read afterwards. *)
let cmd_open (st : State.globalState) ~(timeout:float) ~(filename:string) : string =
  if filename = "" then
    reply_error ~code:"bad_argument" ~detail:"open expects a file name"
  else
  (* Marionnet chdir's to its own home at startup (marionnet.ml), so a relative path would
     not mean what the client believes: require an absolute one rather than resolve it
     against a directory the client cannot see. *)
  if Filename.is_relative filename then
    reply_error ~code:"bad_argument"
      ~detail:(Printf.sprintf "an absolute path is required (got %S)" filename)
  else
  if not (Sys.file_exists filename) then
    reply_error ~code:"bad_argument" ~detail:(Printf.sprintf "no such file: %S" filename)
  else
  let () = Log.printf1 "Control_server: opening project %s\n" filename in
  (* No Thread.join here: on this path the method returns Thread.self (), joining it would
     deadlock. *)
  let _ : Thread.t = st#open_project_async ~filename in
  ask ~timeout
    (fun () ->
       (st#project_paths#get_filename,
        st#active_project,
        st#runnable_project,
        st#project_already_saved,
        List.length (st#network#get_node_names)))
  |> reply_of_outcome
       (fun (actual_file, active, runnable, saved, nodes) ->
          (* [saved] is the discriminating signal, and the reason deserves to be spelled
             out. A failed loading still leaves the file name set and the project
             "active" — measured: opening a text file this way answered active=true,
             file=<that file>, nodes=0. What it does *not* leave is a clean persistent
             state: [register_state_after_save_or_open] (state.ml:551), which clears
             project_dirty, is only reached once the loading has gone through. Hence
             success <=> the expected file is active *and* the state is registered as
             saved. An empty but legitimate project answers ok with nodes=0, as it should,
             because it went through that line too. *)
          match active, actual_file with
          | true, Some f when f = filename && saved ->
              reply_ok [
                ("file",     jstr f);
                ("nodes",    jint nodes);
                ("runnable", jbool runnable);
                ]
          | true, Some f when f = filename ->
              reply_error ~code:"internal"
                ~detail:(Printf.sprintf
                           "loading %S did not complete: the project is flagged as unsaved right after opening (malformed file? see the log)"
                           filename)
          | true, Some f ->
              (* Loading failed and a previously opened project is still the active one. *)
              reply_error ~code:"internal"
                ~detail:(Printf.sprintf "the active project is still %S: loading %S failed (see the log)" f filename)
          | _ ->
              reply_error ~code:"internal"
                ~detail:(Printf.sprintf "no active project after opening %S (see the log)" filename))

(* ---------------------------------------------------------------- *)
(*                             Dispatch                             *)
(* ---------------------------------------------------------------- *)

let known_commands = [ "status"; "ls"; "open"; "quit" ]

(* The answer must be *sent* before quitting, hence the second component: the session loop
   writes it, then triggers the shutdown. *)
let dispatch (st : State.globalState) (line:string) : string * [ `Continue | `Quit ] =
  match parse_request line with
  | None -> (reply_error ~code:"unknown_command" ~detail:"empty request", `Continue)
  | Some r ->
      let timeout =
        match option_value r "timeout" with
        | None -> Ok default_timeout
        | Some s ->
            (match float_of_string_opt s with
             | Some t when t > 0. -> Ok t
             | _ -> Error (Printf.sprintf "--timeout expects a positive number of seconds, got %S" s))
      in
      (match timeout with
       | Error detail -> (reply_error ~code:"bad_argument" ~detail, `Continue)
       | Ok timeout ->
           (match r.verb with
            | "status" -> (cmd_status st ~timeout, `Continue)
            | "ls"     -> (cmd_ls st ~timeout ~kind:(option_value r "kind"), `Continue)
            | "open"   -> (cmd_open st ~timeout ~filename:r.arg, `Continue)
            | "quit"   -> (reply_ok [ ("quitting", jbool true) ], `Quit)
            | verb ->
                let detail =
                  Printf.sprintf "unknown command %S; known commands: %s"
                    verb (String.concat ", " known_commands)
                in
                (reply_error ~code:"unknown_command" ~detail, `Continue)))

(* ---------------------------------------------------------------- *)
(*                             Sessions                             *)
(* ---------------------------------------------------------------- *)

(* N10: Network.server spawns one thread per connection with no bound of its own
   (max_pending_requests only limits the accept backlog). A control channel needs a couple
   of sessions, not an unbounded number. *)
let max_sessions = 8
let sessions_mutex = Mutex.create ()
let sessions = ref 0

let enter_session () : bool =
  Mutex.protect sessions_mutex
    (fun () -> if !sessions >= max_sessions then false else (incr sessions; true))

let leave_session () : unit =
  Mutex.protect sessions_mutex (fun () -> if !sessions > 0 then decr sessions)

(* N7: only #input_line and #output_line are used here. #output_line flushes
   (network.ml:596), so each answer leaves as soon as it is built. *)
let session (st : State.globalState) (ch : Network.stream_channel) : unit =
  if not (enter_session ()) then
    let detail = Printf.sprintf "too many concurrent control sessions (max %d)" max_sessions in
    try ch#output_line (reply_error ~code:"internal" ~detail) with _ -> ()
  else
  let finish () = leave_session () in
  let rec loop () =
    let line = ch#input_line () in
    let (answer, action) = dispatch st line in
    let () = ch#output_line answer in
    match action with
    | `Continue -> loop ()
    | `Quit ->
        (* The answer is out; quit_async only *schedules* the real shutdown
           (state.ml:987-1005), so the client is served before we start dying. *)
        let () = Log.printf "Control_server: quit requested by a client.\n" in
        st#quit_async ()
  in
  match loop () with
  | () -> finish ()
  (* N9: a peer closing its end is the normal way a session ends. The underlying channel
     turns it into End_of_file or into Receiving/Sending — none of which is an incident. *)
  | exception End_of_file ->
      let () = Log.printf ~v:2 "Control_server: session closed by the client.\n" in
      finish ()
  | exception (Network.Receiving _ | Network.Sending _) ->
      let () = Log.printf ~v:2 "Control_server: session ended (peer gone).\n" in
      finish ()
  | exception e ->
      let () = Log.print_exn ~prefix:"Control_server: session aborted: " e in
      finish ()

(* ---------------------------------------------------------------- *)
(*                              Startup                             *)
(* ---------------------------------------------------------------- *)

(* The socket is only as private as the directory holding it: Network.server chmod's the
   socket file itself to 0777 unconditionally (network.ml:202), so the parent directory is
   what actually protects a channel able to drive the whole session (§ 3.4). We create it
   0700 when missing, and refuse to start when an existing one is writable by others. *)
let check_or_make_parent_directory (dir:string) : (unit, string) result =
  match Unix.stat dir with
  | exception Unix.Unix_error (Unix.ENOENT, _, _) ->
      (try
         let () = Unix.mkdir dir 0o700 in
         (* mkdir is subject to the umask, which can only remove bits; we insist anyway,
            so that the directory is exactly 0700: *)
         let () = Unix.chmod dir 0o700 in
         Ok ()
       with e -> Error (Printf.sprintf "cannot create %S: %s" dir (Printexc.to_string e)))
  | exception e -> Error (Printf.sprintf "cannot stat %S: %s" dir (Printexc.to_string e))
  | stats ->
      if stats.Unix.st_kind <> Unix.S_DIR then
        Error (Printf.sprintf "%S is not a directory" dir)
      else if (stats.Unix.st_perm land 0o022) <> 0 then
        Error (Printf.sprintf
                 "%S is writable by group or others (mode 0%o): refusing to put a control socket there"
                 dir stats.Unix.st_perm)
      else Ok ()

(* N12: a socket file may survive a brutal exit (SIGKILL, crash), and the bind would then
   fail with EADDRINUSE. Distinguish the two cases by connecting: someone answering means
   a live Marionnet is already serving there. *)
let someone_is_listening (path:string) : bool =
  let fd = Unix.socket ~cloexec:true Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  let result = try Unix.connect fd (Unix.ADDR_UNIX path); true with _ -> false in
  let () = try Unix.close fd with _ -> () in
  result

let prepare_socketfile (path:string) : (unit, string) result =
  if Filename.is_relative path then
    Error (Printf.sprintf "an absolute path is required (got %S)" path)
  else
  match check_or_make_parent_directory (Filename.dirname path) with
  | Error _ as e -> e
  | Ok () ->
      if not (Sys.file_exists path) then Ok () else
      if someone_is_listening path then
        Error (Printf.sprintf "%S is already served by a live process" path)
      else
        (try
           let () = Unix.unlink path in
           let () = Log.printf1 "Control_server: removed the stale socket file %s\n" path in
           Ok ()
         with e -> Error (Printf.sprintf "cannot remove the stale %S: %s" path (Printexc.to_string e)))

(* ~no_fork:() is mandatory: the default behaviour of Network.server is to fork per
   connection (network.ml:231), which in a GTK process owning UML children would be
   catastrophic. The bind happens in the calling thread (network.ml:223), so a failure is
   reported here and now, and Marionnet goes on without a control channel. *)
let start (st : State.globalState) ~(socketfile:string) : unit =
  match prepare_socketfile socketfile with
  | Error detail ->
      Log.printf1 "Control_server: NOT started: %s\n" detail
  | Ok () ->
      (try
         let (_thread, socketfile) =
           Network.stream_unix_server
             ~no_fork:()
             ~socketfile
             ~protocol:(session st)
             ()
         in
         Log.printf1 "Control_server: listening on %s\n" socketfile
       with e ->
         Log.print_exn ~prefix:"Control_server: NOT started: " e)

let start_if_requested (st : State.globalState) : unit =
  match !Initialization.option_control_socket with
  | None -> ()
  | Some socketfile -> start st ~socketfile
