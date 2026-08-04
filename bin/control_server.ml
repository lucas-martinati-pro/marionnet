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
(* Epoch seconds, millisecond resolution: enough to order messages and to feed `date -d @`,
   without dragging in a date formatting dependency. *)
let jfloat (x:float) : string = Printf.sprintf "%.3f" x
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
   internal. [extra] carries the fields a failing command still wants to report — typically
   the messages captured while it ran, which is where the actual cause is to be found.
   Two functions rather than an ?extra parameter: with only labelled arguments after it, an
   optional one is never eliminated, and every call site would have to end with a (). *)
let reply_error_with ~(extra:(string * string) list) ~(code:string) ~(detail:string) : string =
  jobj ([ ("ok", jbool false); ("error", jstr code); ("detail", jstr detail) ] @ extra)

let reply_error ~(code:string) ~(detail:string) : string =
  reply_error_with ~extra:[] ~code ~detail

(* ---------------------------------------------------------------- *)
(*                    Messages captured from the GUI                *)
(* ---------------------------------------------------------------- *)

(* script_mode.ml captures what Marionnet would have *shown*: the windows it opens by
   itself have no one to read them in a driven session. Rendering them here is what turns
   a lost dialog into an answer. *)
let json_of_item (i : Script_mode.item) : string =
  jobj [
    ("summary",  jstr i.Script_mode.summary);
    ("detail",   jstr i.Script_mode.detail);
    ("severity", jstr (Script_mode.string_of_severity i.Script_mode.severity));
    ]

let json_of_notification (n : Script_mode.notification) : string =
  jobj [
    ("seq",   jint  n.Script_mode.seq);
    ("time",  jfloat n.Script_mode.time);
    ("kind",  jstr  (Script_mode.string_of_kind n.Script_mode.kind));
    ("title", jstr  n.Script_mode.title);
    ("body",  jstr  n.Script_mode.body);
    ("items", jlist (List.map json_of_item n.Script_mode.items));
    ]

let jnotifications (ns : Script_mode.notification list) : string =
  jlist (List.map json_of_notification ns)

(* ---------------------------------------------------------------- *)
(*                    The state, as a script sees it                *)
(* ---------------------------------------------------------------- *)

(* Rule 2 of § 4.10: never expose the raw state. [No_device] and [Off] both project onto "off";
   the difference is an implementation detail — machines and routers chain a destroy after the
   shutdown so as to restart from a fresh COW file and end up in No_device, the other components
   stay in Off — and a script seeing two states where the user sees one would be led to write false
   conditions. The projection goes through the historical strings of [Simulated_device.to_string]
   (user_level.ml:95) rather than through its constructors, which the interface does not export.
   An unrecognised string is passed through rather than folded into "off": a state added later must
   show up as unknown, not masquerade as a known one. *)
let script_state_of_raw : string -> string = function
  | "NoDevice" | "DeviceOff" -> "off"
  | "DeviceOn"               -> "on"
  | "DeviceSleeping"         -> "sleeping"
  | other                    -> other

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

let reply_of_outcome ?(extra=[]) (render : 'a -> string) : 'a outcome -> string = function
  | Done v      -> render v
  | Failed e    -> reply_error_with ~extra ~code:"internal" ~detail:(Printexc.to_string e)
  | Timed_out t ->
      reply_error_with ~extra ~code:"timeout"
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

(* --- eligibility: what a component allows right now -------------- *)

(* One record, read by the two views of the same truth: [can] is the "per component" view (the
   scriptable equivalent of the contextual menu), [ls --can=...] the "per action" one. The point
   is that a script has nothing to reimplement — it asks what is permitted now, instead of
   deducing it from a state machine it would have to keep in sync with ours (§ 4.10).

   The predicates read below are the model's own. Since episode 4b they include [can_modify] and
   [can_destroy], which used to exist only as a GUI menu filter: without them a script would have
   destroyed a running component, together with its live Unix processes.

   [poweroff] and [restart] are published although no *per component* menu offers them: poweroff
   exists only globally ("power off everything", state.ml:962) and restart only through a treeview
   edit (marionnet.ml:169-175). The action does exist in the application, only its granularity
   differs, and a test script needs to simulate a brutal power cut on *one* machine. They are named
   in the [beyond_gui] field so that a client can tell them apart from what a human can click.
   [restart] reads can_gracefully_shutdown, which is the guard marionnet.ml itself applies. *)

type eligibility = {
  e_name  : string;
  e_kind  : string;
  e_state : string;                (* raw; projected when rendering *)
  e_can   : (string * bool) list;  (* action -> allowed, in menu order *)
}

let beyond_gui_actions = [ "poweroff"; "restart" ]

(* The whole vocabulary of actions, and the only one: the names below are those of the commands
   of § 4.4, so that a client never has to translate between a predicate name and a command name
   (which is why [ls --can=] takes "start" and not "startup"). *)
let known_actions = [ "set"; "del"; "start"; "stop"; "suspend"; "resume"; "poweroff"; "restart" ]

let eligibility_of_node n =
  { e_name  = n#get_name;
    e_kind  = n#string_of_devkind;
    e_state = n#state_as_string;
    e_can   = [ ("set",      n#can_modify);
                ("del",      n#can_destroy);
                ("start",    n#can_startup);
                ("stop",     n#can_gracefully_shutdown);
                ("suspend",  n#can_suspend);
                ("resume",   n#can_resume);
                ("poweroff", n#can_poweroff);
                ("restart",  n#can_gracefully_shutdown);
                ] }

(* A cable publishes four actions, and the four others are not omitted by accident:
   start/stop/poweroff/restart are meaningless for a wire, whose process is driven by a
   reference counter and never by the user (cable.ml, comment B5). Worse, the inherited
   [can_startup] would answer *true* for a cable whose process is not running, so publishing
   it would advertise an action that does not exist. Its can_suspend/can_resume, on the
   contrary, have a proper meaning here: unplugged / plugged back. *)
let eligibility_of_cable c =
  { e_name  = c#get_name;
    e_kind  = "cable";
    e_state = c#state_as_string;
    e_can   = [ ("set",     c#can_modify);
                ("del",     c#can_destroy);
                ("suspend", c#can_suspend);
                ("resume",  c#can_resume);
                ] }

let allowed_actions (e : eligibility) : string list =
  List.filter_map (fun (a, ok) -> if ok then Some a else None) e.e_can

let fields_of_eligibility (e : eligibility) : (string * string) list =
  let allowed = allowed_actions e in
  [ ("name",       jstr e.e_name);
    ("kind",       jstr e.e_kind);
    ("state",      jstr (script_state_of_raw e.e_state));
    ("can",        jlist (List.map jstr allowed));
    ("beyond_gui", jlist (List.map jstr (List.filter (fun a -> List.mem a beyond_gui_actions) allowed)));
    ]

let json_of_eligibility (e : eligibility) : string = jobj (fields_of_eligibility e)

(* Both filters are applied outside the GTK main thread, on the extracted records: nothing but
   the extraction itself needs to run there. [ls] lists nodes only — the view that also covers
   cables is [can] (§ 4.3). An unknown action is refused rather than answered with an empty list,
   because a typo in a script must be diagnosed and not read as "nothing is allowed"; an unknown
   [--kind], on the contrary, keeps its historical behaviour (an empty list), the set of kinds
   being open to whatever a future component adds. *)
let cmd_ls (st : State.globalState) ~(timeout:float) ~(kind:string option) ~(can:string option)
  : string
  =
  match can with
  | Some a when not (List.mem a known_actions) ->
      reply_error ~code:"unknown_can"
        ~detail:(Printf.sprintf "no such action %S (expected one of: %s)"
                   a (String.concat ", " known_actions))
  | _ ->
  ask ~timeout
    (fun () -> List.map eligibility_of_node (st#network#get_node_list))
  |> reply_of_outcome
       (fun components ->
          let keep p l = List.filter p l in
          let components =
            match kind with None -> components | Some k -> keep (fun e -> e.e_kind = k) components
          in
          let components =
            match can with
            | None   -> components
            | Some a -> keep (fun e -> List.mem a (allowed_actions e)) components
          in
          let node_of_eligibility e =
            jobj [ ("name", jstr e.e_name); ("kind", jstr e.e_kind);
                   ("state", jstr (script_state_of_raw e.e_state)) ]
          in
          reply_ok [
            ("count", jint (List.length components));
            ("nodes", jlist (List.map node_of_eligibility components));
            ])

(* --- can: the same truth, per component -------------------------- *)

let cmd_can (st : State.globalState) ~(timeout:float) ~(name:string) : string =
  ask ~timeout
    (fun () ->
       let nodes  = List.map eligibility_of_node  (st#network#get_node_list)
       and cables = List.map eligibility_of_cable (st#network#get_cable_list) in
       nodes @ cables)
  |> reply_of_outcome
       (fun components ->
          if name = "" then
            reply_ok [
              ("count",      jint (List.length components));
              ("components", jlist (List.map json_of_eligibility components));
              ]
          else
            match List.find_opt (fun e -> e.e_name = name) components with
            | Some e -> reply_ok (fields_of_eligibility e)
            (* The normalised code of § 4.1; it covers cables too, the channel having a single
               namespace of component names. *)
            | None ->
                reply_error ~code:"unknown_node"
                  ~detail:(Printf.sprintf "no component named %S" name))

(* ---------------------------------------------------------------- *)
(*                           Transitions                            *)
(* ---------------------------------------------------------------- *)

(* § 4.4 and § 4.10. Three rules govern everything below, and each one comes from a measured
   fact rather than from taste:

   1. TEST THE PREDICATE FIRST. The transition methods of the model are *guarded but silent*
      (user_level.ml:211-237: [if self#can_startup then ...] with no else), so calling
      [#startup] on a running component does nothing and says nothing. A channel that
      answered "ok" there would be lying: we read the same [can_*] the GUI menus read, and
      answer [forbidden_transition] when it says no.

   2. CALL THE GUI METHODS, NEVER THE [..._right_now] ONES. [#startup] & co. *enqueue* a task
      on the task runner, with its progress bar (user_level.ml:175-200); the [..._right_now]
      variants perform the transition in the calling thread — here the GTK main thread, which
      would freeze the whole interface for the duration of a UML boot.

   3. HENCE "ACCEPTED", NEVER "DONE". By the time we answer, the task is queued, usually not
      finished. Saying otherwise would push every script into the trap of acting on a state
      that does not exist yet; that is what [wait] below is for.

   The lookup and the call both happen inside the GTK main thread (one [ask]): the predicate
   and the enqueueing then belong to the same slot, so no other GTK callback can slip between
   "it is allowed" and "go". Since episode 4c this costs nothing, the [can_*] no longer taking
   any mutex. *)

type transition_result =
  | Tr_accepted
  | Tr_forbidden   of string   (* raw state, projected when rendering *)
  | Tr_unknown
  | Tr_unsupported of string   (* kind: the action makes no sense for this component *)

(* A node accepts the six actions of § 4.4. [restart] reads can_gracefully_shutdown because
   that is the guard marionnet.ml:169-175 itself applies, and because [#gracefully_restart]
   starts by shutting down. *)
let transition_of_node (action:string) n : (bool * (unit -> unit)) option =
  match action with
  | "start"    -> Some (n#can_startup,             (fun () -> n#startup))
  | "stop"     -> Some (n#can_gracefully_shutdown, (fun () -> n#gracefully_shutdown))
  | "suspend"  -> Some (n#can_suspend,             (fun () -> n#suspend))
  | "resume"   -> Some (n#can_resume,              (fun () -> n#resume))
  | "poweroff" -> Some (n#can_poweroff,            (fun () -> n#poweroff))
  | "restart"  -> Some (n#can_gracefully_shutdown, (fun () -> n#gracefully_restart))
  | _          -> None

(* A cable accepts two, the same two [can] publishes for it: its process is driven by a
   reference counter, never by the user (cable.ml, comment B5), so start/stop/poweroff/restart
   are not "forbidden" for a wire — they are meaningless, which is a different answer. *)
let transition_of_cable (action:string) c : (bool * (unit -> unit)) option =
  match action with
  | "suspend" -> Some (c#can_suspend, (fun () -> c#suspend))
  | "resume"  -> Some (c#can_resume,  (fun () -> c#resume))
  | _         -> None

let cmd_transition (st : State.globalState) ~(timeout:float) ~(action:string) ~(name:string)
  : string
  =
  if name = "" then
    reply_error ~code:"bad_argument"
      ~detail:(Printf.sprintf "%s expects the name of a component" action)
  else
  ask ~timeout
    (fun () ->
       match List.find_opt (fun n -> n#get_name = name) (st#network#get_node_list) with
       | Some n ->
           (match transition_of_node action n with
            | None            -> Tr_unsupported n#string_of_devkind
            | Some (true,  f) -> let () = f () in Tr_accepted
            | Some (false, _) -> Tr_forbidden n#state_as_string)
       | None ->
       match List.find_opt (fun c -> c#get_name = name) (st#network#get_cable_list) with
       | Some c ->
           (match transition_of_cable action c with
            | None            -> Tr_unsupported "cable"
            | Some (true,  f) -> let () = f () in Tr_accepted
            | Some (false, _) -> Tr_forbidden c#state_as_string)
       | None -> Tr_unknown)
  |> reply_of_outcome
       (function
         | Tr_accepted ->
             reply_ok [
               ("component", jstr name);
               ("action",    jstr action);
               (* Never "done": the task is queued. See rule 3 above. *)
               ("accepted",  jbool true);
               (* Same warning as in [can]: this action is reachable from no per-component
                  menu (§ 4.4). A client may want to refuse it in "GUI equivalence" mode. *)
               ("beyond_gui", jbool (List.mem action beyond_gui_actions));
               ]
         | Tr_forbidden raw ->
             reply_error ~code:"forbidden_transition"
               ~detail:(Printf.sprintf "%S cannot %s from state %S"
                          name action (script_state_of_raw raw))
         | Tr_unsupported kind ->
             reply_error ~code:"bad_argument"
               ~detail:(Printf.sprintf "the action %S does not apply to %S (kind %s)"
                          action name kind)
         | Tr_unknown ->
             reply_error ~code:"unknown_node"
               ~detail:(Printf.sprintf "no component named %S" name))

(* The collective actions of the bottom toolbar (state.ml:951-966). They are *not* a loop over
   the per-component command: [startup_everything] enqueues its nodes in sequence while the two
   others go in parallel, which is the application's own choice and not ours to second-guess.
   They are silently empty when nothing is eligible, so we report how many components the model
   selected — an answer of 0 is the honest way to say "nothing to do", and it is the number a
   bench must assert on. *)
let cmd_transition_all (st : State.globalState) ~(timeout:float) ~(action:string) : string =
  ask ~timeout
    (fun () ->
       let selected =
         match action with
         | "start-all" -> List.length (st#network#get_nodes_that_can_startup ())
         (* Both shutdown-all and poweroff-all select on can_gracefully_shutdown: poweroff_everything
            does exactly that (state.ml:962-966), a brutal cut being applicable to whatever is up. *)
         | _           -> List.length (st#network#get_nodes_that_can_gracefully_shutdown ())
       in
       let () =
         match action with
         | "start-all"    -> st#startup_everything ()
         | "shutdown-all" -> st#shutdown_everything ()
         | "poweroff-all" -> st#poweroff_everything ()
         | _              -> ()
       in
       selected)
  |> reply_of_outcome
       (fun selected ->
          reply_ok [
            ("action",   jstr action);
            ("accepted", jbool true);
            ("count",    jint selected);
            ])

(* ---------------------------------------------------------------- *)
(*                          Synchronisation                         *)
(* ---------------------------------------------------------------- *)

(* § 4.7. [wait] is the counterpart of rule 3 above: transitions are accepted, not done, so a
   script needs one primitive to rejoin the model's timeline.

   Two decisions worth stating:
   - the polling loop runs in THIS thread (the session thread), never in the GTK main thread:
     each round trip is a short [ask], so the GUI keeps its slot and the other sessions keep
     being served. The price is that a waiting client holds one of the [max_sessions] slots
     for the whole wait, which is why the default is generous but finite;
   - [--timeout] here means "how long to wait for the state", not "how long to wait for the
     GTK main thread" — waiting for a UML to boot legitimately takes far more than the 5s
     deadline of the other commands. The GTK deadline of each poll stays [default_timeout],
     so a frozen interface is still reported as such instead of being hidden by a long wait. *)

let known_script_states = [ "on"; "off"; "sleeping" ]
let default_wait_timeout = 60.0
let wait_poll_interval = 0.2

(* Shared by [wait] and [wait-all]: check the argument, then poll [observe] until [reached]
   holds or the deadline expires. [observe] runs in the GTK main thread. *)
let poll_until ~(wait_timeout:float) ~(observe: unit -> 'a outcome)
               ~(reached: 'a -> bool) ~(on_reached: 'a -> float -> string)
               ~(on_expiry: 'a -> float -> string) : string
  =
  let t0 = Unix.gettimeofday () in
  let deadline = t0 +. wait_timeout in
  let rec poll () =
    match observe () with
    | Failed e    -> reply_error ~code:"internal" ~detail:(Printexc.to_string e)
    | Timed_out t ->
        reply_error ~code:"timeout"
          ~detail:(Printf.sprintf
                     "the GTK main thread did not answer within %.1fs while waiting (busy: modal dialog, pulled-down menu or long operation)"
                     t)
    | Done v ->
        let elapsed = Unix.gettimeofday () -. t0 in
        if reached v then on_reached v elapsed
        else if Unix.gettimeofday () >= deadline then on_expiry v elapsed
        else let () = Thread.delay wait_poll_interval in poll ()
  in
  poll ()

let check_state (state : string option) : (string, string) result =
  match state with
  | None   -> Error (Printf.sprintf "--state is required (one of: %s)"
                       (String.concat ", " known_script_states))
  | Some s when List.mem s known_script_states -> Ok s
  | Some s -> Error (Printf.sprintf "no such state %S (expected one of: %s)"
                       s (String.concat ", " known_script_states))

let cmd_wait (st : State.globalState) ~(gtk_timeout:float) ~(wait_timeout:float)
             ~(name:string) ~(state:string option) : string
  =
  match check_state state with
  | Error detail -> reply_error ~code:"bad_argument" ~detail
  | Ok target ->
  if name = "" then
    reply_error ~code:"bad_argument" ~detail:"wait expects the name of a component"
  else
  (* [None] = no such component. Looked up at every poll on purpose: a component may be
     destroyed while we wait, and the script must be told rather than time out. *)
  let observe () =
    ask ~timeout:gtk_timeout
      (fun () ->
         match List.find_opt (fun n -> n#get_name = name) (st#network#get_node_list) with
         | Some n -> Some n#state_as_string
         | None ->
         match List.find_opt (fun c -> c#get_name = name) (st#network#get_cable_list) with
         | Some c -> Some c#state_as_string
         | None   -> None)
  in
  poll_until ~wait_timeout ~observe
    ~reached:(function None -> true | Some raw -> script_state_of_raw raw = target)
    ~on_reached:(fun v elapsed ->
       match v with
       | None -> reply_error ~code:"unknown_node"
                   ~detail:(Printf.sprintf "no component named %S" name)
       | Some raw ->
           reply_ok [
             ("component", jstr name);
             ("state",     jstr (script_state_of_raw raw));
             ("waited",    jfloat elapsed);
             ])
    ~on_expiry:(fun v elapsed ->
       let current = match v with None -> "?" | Some raw -> script_state_of_raw raw in
       reply_error ~code:"timeout"
         ~detail:(Printf.sprintf "%S was still %S after %.1fs (expected %S)"
                    name current elapsed target))

(* Nodes only, like [ls] and like the collective buttons of the toolbar: a cable's state
   follows its endpoints' and is not something a script waits for (§ 4.7). *)
let cmd_wait_all (st : State.globalState) ~(gtk_timeout:float) ~(wait_timeout:float)
                 ~(state:string option) : string
  =
  match check_state state with
  | Error detail -> reply_error ~code:"bad_argument" ~detail
  | Ok target ->
  let observe () =
    ask ~timeout:gtk_timeout
      (fun () ->
         List.map (fun n -> (n#get_name, script_state_of_raw n#state_as_string))
           (st#network#get_node_list))
  in
  let pending l = List.filter (fun (_, s) -> s <> target) l in
  poll_until ~wait_timeout ~observe
    ~reached:(fun l -> pending l = [])
    ~on_reached:(fun l elapsed ->
       reply_ok [
         ("state",  jstr target);
         ("count",  jint (List.length l));
         ("waited", jfloat elapsed);
         ])
    ~on_expiry:(fun l elapsed ->
       let late = pending l in
       reply_error_with
         ~extra:[ ("pending",
                   jlist (List.map (fun (n, s) -> jobj [ ("name", jstr n); ("state", jstr s) ]) late)) ]
         ~code:"timeout"
         ~detail:(Printf.sprintf "%d of %d nodes were still not %S after %.1fs"
                    (List.length late) (List.length l) target elapsed))

(* Opening a project is *not* delegated to the GTK main thread, and this is deliberate:
   called from a thread which is not gtk_main, [open_project_async] performs the whole
   loading in the calling thread (state.ml:594-596) — the very case that test provides
   for, and the same code path the GUI menu takes in its own thread. Delegating it would
   instead spawn yet another thread and return immediately, i.e. lose the result.

   The loading swallows its own failures: they are reported by a (non-modal) dialog and a
   log line, and the exception never reaches us (state.ml:537-547, 567-580). So we do not
   pretend to know whether it succeeded: we report the state that *is*, read afterwards.

   Since episode 3c that dialog is no longer lost: everything Marionnet showed while the
   project was loading comes back in the [notifications] field of this very answer — the
   cause of a failure, and, for an old project, the list of adaptations it had to apply
   (remapped kernels and distributions). No second round trip, because these messages
   belong to the command that provoked them. *)
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
  (* Everything captured from now on belongs to this command. *)
  let since = Script_mode.last_seq () in
  (* No Thread.join here: on this path the method returns Thread.self (), joining it would
     deadlock. *)
  let _ : Thread.t = st#open_project_async ~filename in
  let outcome =
    ask ~timeout
      (fun () ->
         (st#project_paths#get_filename,
          st#active_project,
          st#runnable_project,
          st#project_already_saved,
          List.length (st#network#get_node_names)))
  in
  let extra = [ ("notifications", jnotifications (Script_mode.notifications ~since ())) ] in
  outcome |> reply_of_outcome ~extra
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
              reply_ok ([
                ("file",     jstr f);
                ("nodes",    jint nodes);
                ("runnable", jbool runnable);
                ] @ extra)
          | true, Some f when f = filename ->
              reply_error_with ~extra ~code:"internal"
                ~detail:(Printf.sprintf
                           "loading %S did not complete: the project is flagged as unsaved right after opening (malformed file? see the log)"
                           filename)
          | true, Some f ->
              (* Loading failed and a previously opened project is still the active one. *)
              reply_error_with ~extra ~code:"internal"
                ~detail:(Printf.sprintf "the active project is still %S: loading %S failed (see the log)" f filename)
          | _ ->
              reply_error_with ~extra ~code:"internal"
                ~detail:(Printf.sprintf "no active project after opening %S (see the log)" filename))

(* Reading the capture needs neither the GTK main thread nor a deadline — which is exactly
   the point: when the GUI is stuck behind a modal dialog and every other command times
   out, this one still answers, and says what the dialog was. *)
let cmd_notifications ~(since:string option) ~(clear:bool) : string =
  match (match since with None -> Some 0 | Some s -> int_of_string_opt s) with
  | None ->
      reply_error ~code:"bad_argument"
        ~detail:(Printf.sprintf "--since expects an integer sequence number, got %S"
                   (match since with Some s -> s | None -> ""))
  | Some since ->
      let ns = Script_mode.notifications ~since () in
      let () = if clear then Script_mode.clear () in
      reply_ok [
        ("enabled",       jbool (Script_mode.enabled ()));
        ("count",         jint (List.length ns));
        (* The client passes this back as --since to get only what is new. It is the global
           counter, not the last one served, so it stays meaningful after a --clear. *)
        ("last_seq",      jint (Script_mode.last_seq ()));
        ("notifications", jnotifications ns);
        ]

(* ---------------------------------------------------------------- *)
(*                             Dispatch                             *)
(* ---------------------------------------------------------------- *)

(* The per-component transitions of § 4.4. Their names are those of [known_actions] minus
   "set"/"del", which are not transitions and belong to a later episode. *)
let transition_commands = [ "start"; "stop"; "suspend"; "resume"; "poweroff"; "restart" ]
let transition_all_commands = [ "start-all"; "shutdown-all"; "poweroff-all" ]

let known_commands =
  [ "status"; "ls"; "can"; "open"; "notifications" ]
  @ transition_commands @ transition_all_commands
  @ [ "wait"; "wait-all"; "quit" ]

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
           (* Script_mode.in_command marks *this* thread as serving a command, which is what
              allows a question dialog raised on this path — and only there — to be answered
              by default instead of freezing us (script_mode.ml). *)
           Script_mode.in_command @@ fun () ->
           (match r.verb with
            | "status" -> (cmd_status st ~timeout, `Continue)
            | "ls"     -> (cmd_ls st ~timeout ~kind:(option_value r "kind")
                                                ~can:(option_value r "can"), `Continue)
            | "can"    -> (cmd_can st ~timeout ~name:r.arg, `Continue)
            | "open"   -> (cmd_open st ~timeout ~filename:r.arg, `Continue)
            | "notifications" ->
                (cmd_notifications
                   ~since:(option_value r "since")
                   ~clear:(option_value r "clear" <> None),
                 `Continue)
            | verb when List.mem verb transition_commands ->
                (cmd_transition st ~timeout ~action:verb ~name:r.arg, `Continue)
            | verb when List.mem verb transition_all_commands ->
                (cmd_transition_all st ~timeout ~action:verb, `Continue)
            (* [--timeout] changes meaning for these two (see the comment above [cmd_wait]):
               it bounds the wait, not the round trip to the GTK main thread. Hence the
               distinct default, and hence [timeout] being reused only when the client did
               name it. *)
            | "wait" | "wait-all" ->
                let wait_timeout =
                  match option_value r "timeout" with None -> default_wait_timeout | Some _ -> timeout
                in
                let state = option_value r "state" in
                ((if r.verb = "wait" then
                    cmd_wait st ~gtk_timeout:default_timeout ~wait_timeout ~name:r.arg ~state
                  else
                    cmd_wait_all st ~gtk_timeout:default_timeout ~wait_timeout ~state),
                 `Continue)
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
