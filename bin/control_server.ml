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
module Forest = Ocamlbricks.Forest
module Future = Ocamlbricks.Future
module Network = Ocamlbricks.Network
module StrExtra = Ocamlbricks.StrExtra
module UnixExtra = Ocamlbricks.UnixExtra
module Xforest = Ocamlbricks.Xforest

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
  args : string list;             (* positional arguments, checked against the arity below *)
  opts : (string * string) list;  (* --key=value, or --key alone (empty value) *)
}

(* § 4.1. Until episode 4d the parser joined every non "--" token with a space, so that a path
   containing spaces needed no quoting; that convenience held only as long as a command took at
   most *one* positional argument, which is no longer true (connect c1 m1:eth0 m2:eth0, set m1 label
   ...). The alternative — shell-like quoting — would buy a state machine, one more error code
   and, on the client side, a second level of escaping on top of the one Bash already did, to
   solve a problem this channel does not have: a component name is an *identifier*
   (user_level.ml:521, StrExtra.Class.identifierp), hence never contains a space. Only a path or
   a free text value does, and either is always the *last* argument.

   So each command declares how many positional arguments it takes and whether its last one may
   contain spaces. [free_tail] joins the surplus tokens back into that last argument — which is
   exactly what the old parser did for the whole line, so [open] behaves as before — while a
   strict command now *reports* the surplus instead of silently swallowing it (ls foo used to be
   accepted and ignored). Known limitation, inherited: consecutive spaces inside a free tail are
   normalised to one, the tokens being joined rather than cut out of the raw line. *)
type arity = {
  min_args  : int;
  max_args  : int;
  free_tail : bool;    (* may the last argument contain spaces? *)
  syntax    : string;  (* quoted in the error, so that a refusal also teaches the syntax *)
}

let no_arg             syntax = { min_args = 0; max_args = 0; free_tail = false; syntax }
let one_component      syntax = { min_args = 1; max_args = 1; free_tail = false; syntax }
let optional_component syntax = { min_args = 0; max_args = 1; free_tail = false; syntax }
let one_path           syntax = { min_args = 1; max_args = 1; free_tail = true;  syntax }
(* Two identifiers (a kind and a name), or a component and one of its field names: both are
   identifiers, hence strict. Only a *value* may contain spaces, and only in last position. *)
let two_identifiers           syntax = { min_args = 2; max_args = 2; free_tail = false; syntax }
(* A cable name and its two endpoints: three tokens, none of which may contain a space, an
   endpoint being made of two identifiers and a colon. *)
let three_identifiers         syntax = { min_args = 3; max_args = 3; free_tail = false; syntax }
let component_and_field       syntax = { min_args = 1; max_args = 2; free_tail = false; syntax }
let component_field_and_value syntax = { min_args = 3; max_args = 3; free_tail = true;  syntax }
(* A component and, optionally, a free text: the one-line form of rc-set. Which field it writes
   is said by --field, the second position being taken by the content itself. *)
let component_and_free_text   syntax = { min_args = 1; max_args = 2; free_tail = true;  syntax }
(* A treeview cell: node, port, field, and the value — which is *optional*, because that is how a
   cell is emptied, the way a human clears it in the GUI (every ifconfig column predicate accepts
   the empty string, treeview_ifconfig.ml:407-468). Free tail all the same: an address never holds
   a space, but nothing here should decide that for a column added later. *)
let node_port_field_and_value syntax = { min_args = 3; max_args = 4; free_tail = true;  syntax }

(* The per-component transitions of § 4.4. Their names are those of [known_actions] minus
   "set"/"del", which are not transitions and belong to a later episode. *)
let transition_commands = [ "start"; "stop"; "suspend"; "resume"; "poweroff"; "restart" ]
let transition_all_commands = [ "start-all"; "shutdown-all"; "poweroff-all" ]

(* The single vocabulary of the channel: what a command is called, what it takes, and how it is
   spelled. [dispatch] and the [unknown_command] answer both read this list. *)
let arity_of_command : (string * arity) list =
  [ ("status",        no_arg "status");
    ("ls",            no_arg "ls [--kind=<kind>] [--can=<action>]");
    ("can",           optional_component "can [<component>]");
    ("add",           two_identifiers "add <kind> <name> [--ports=<n>] [--<field>=<value>]…");
    ("del",           one_component "del <component>");
    ("get",           component_and_field "get <component> [<field>]");
    ("set",           component_field_and_value "set <component> <field> <value>");
    ("rename",        two_identifiers "rename <component> <new name>");
    ("connect",       three_identifiers
                        "connect <cable> <node>:<port> <node>:<port> [--crossover]");
    ("rc-get",        component_and_field "rc-get <component> [<field>|--field=<field>]");
    ("rc-set",        component_and_free_text
                        "rc-set <component> [<one-line content>] [--from=<absolute path>] \
                         [--enable|--disable] [--field=<field>]");
    (* § 4.6. The optional argument filters the *roots* by their Name column. documents takes
       none: unlike the three others it has no Name column at all (it inherits the bare
       Treeview.t), so there would be nothing to match. *)
    ("ifconfig",      optional_component "ifconfig [<node>]");
    ("defects",       optional_component "defects [<node>]");
    ("history",       optional_component "history [<node>]");
    ("documents",     no_arg "documents");
    (* The write side (episode 5b). One field at a time, like [set]: a refusal then names the
       field it is about. --restart/--no-restart is required only when the node is running. *)
    ("ifconfig-set",  node_port_field_and_value
                        "ifconfig-set <node> <port> <field> [<value>] [--restart|--no-restart]");
    ("open",          one_path "open <absolute path>");
    ("new",           one_path "new <absolute path> [--save|--no-save]");
    ("save",          no_arg "save");
    ("save-as",       one_path "save-as <absolute path>");
    ("close",         no_arg "close [--save|--no-save]");
    ("notifications", no_arg "notifications [--since=<n>] [--clear]");
    ("wait",          one_component
                        "wait <component> (--state=on|off|sleeping | --ready) [--timeout=<s>]");
    ("wait-all",      no_arg "wait-all --state=on|off|sleeping [--timeout=<s>]");
    ("quit",          no_arg "quit");
    ]
  @ (List.map (fun v -> (v, one_component (v ^ " <component>"))) transition_commands)
  @ (List.map (fun v -> (v, no_arg v)) transition_all_commands)

let known_commands = List.map fst arity_of_command

(* An unknown verb is let through untouched: [dispatch] answering [unknown_command] is more
   useful than a complaint about the arity of a command that does not exist. *)
let check_arity ~(verb:string) (args:string list) : (string list, string) result =
  match List.assoc_opt verb arity_of_command with
  | None -> Ok args
  | Some a ->
      let n = List.length args in
      let plural k = if k = 1 then "" else "s" in
      if n < a.min_args then
        Error (Printf.sprintf "%s expects %d positional argument%s, got %d — usage: %s"
                 verb a.min_args (plural a.min_args) n a.syntax)
      else if n <= a.max_args then Ok args
      else if a.free_tail then
        (* The surplus belongs to the last argument: a path, or a free text value. *)
        let head = List.filteri (fun i _ -> i <  a.max_args - 1) args
        and tail = List.filteri (fun i _ -> i >= a.max_args - 1) args in
        Ok (head @ [ String.concat " " tail ])
      else if a.max_args = 0 then
        Error (Printf.sprintf "%s takes no positional argument, got %d — usage: %s"
                 verb n a.syntax)
      else
        Error (Printf.sprintf "%s accepts at most %d positional argument%s, got %d — usage: %s"
                 verb a.max_args (plural a.max_args) n a.syntax)

(* [None] is the empty line; [Some (Error detail)] a request whose shape is already wrong. *)
let parse_request (line:string) : (request, string) result option =
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
      (match check_arity ~verb argument_tokens with
       | Error detail -> Some (Error detail)
       | Ok args      -> Some (Ok { verb; args; opts = List.map parse_option option_tokens }))

let option_value (r:request) (key:string) : string option = List.assoc_opt key r.opts

(* The first positional argument, or "" when the command takes none: the arity has already
   guaranteed that it is there when the command requires it. *)
let arg0 (r:request) : string = match r.args with x :: _ -> x | [] -> ""

(* Same guarantee for the following ones, hence the plain string: only an optional argument
   (get's field) is read through [arg_opt]. *)
let arg_at  (r:request) (i:int) : string        = match List.nth_opt r.args i with Some x -> x | None -> ""
let arg_opt (r:request) (i:int) : string option = List.nth_opt r.args i

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

let gtk_busy_detail (t:float) : string =
  Printf.sprintf
    "the GTK main thread did not answer within %.1fs (busy: modal dialog, pulled-down menu or long operation)"
    t

let reply_of_outcome ?(extra=[]) (render : 'a -> string) : 'a outcome -> string = function
  | Done v      -> render v
  | Failed e    -> reply_error_with ~extra ~code:"internal" ~detail:(Printexc.to_string e)
  | Timed_out t -> reply_error_with ~extra ~code:"timeout" ~detail:(gtk_busy_detail t)

(* Same as [ask], with the two failure cases already rendered as the answer to send. The project
   commands (§ 4.2) chain several round trips around one long non-GTK call, and would otherwise
   repeat those two branches at every step. Combined with [let*] below, a command reads as the
   sequence it is, and every early exit carries the notifications captured so far. *)
let ask_or_answer ~(extra: unit -> (string * string) list) ~(timeout:float) (f : unit -> 'a)
  : ('a, string) result
  =
  match ask ~timeout f with
  | Done v      -> Ok v
  | Failed e    -> Error (reply_error_with ~extra:(extra ()) ~code:"internal"
                            ~detail:(Printexc.to_string e))
  | Timed_out t -> Error (reply_error_with ~extra:(extra ()) ~code:"timeout"
                            ~detail:(gtk_busy_detail t))

(* Both sides carry an answer already built, so the caller ends with [answer_of_result].
   [>>=] rather than the [let*] of OCaml 4.08: camlp4 preprocesses this directory and does not
   know binding operators (it answers "Parse error: ) or module expected"). *)
let ( >>= ) = Result.bind
let answer_of_result : (string, string) result -> string = function Ok a | Error a -> a

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

(* The kinds a script may create (§ 4.3). These strings are the model's own
   (#string_of_devkind, redefined in the seven files) and they are also the roots of a .mar
   forest, so [ls --kind=], [add <kind>] and a saved project all speak one language. "cable" is
   absent on purpose: it takes two endpoints, hence its own command (§ 4.5). *)
let known_kinds = [ "machine"; "router"; "switch"; "hub"; "cloud"; "world_bridge"; "world_gateway" ]

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
(*                  Components: add, del, get, set                  *)
(* ---------------------------------------------------------------- *)

(* § 4.3. Until this episode a script could drive a network, not build one: it had to start from
   a .mar drawn by hand. Three properties of the model make these four commands uniform over the
   eight kinds, so that almost nothing here knows what a machine is:

     - [#to_tree] publishes the attributes of a component, exactly as a .mar file stores them
       (machine.ml:637, hub.ml:339, cable.ml:715, ...) — it is the single source of truth for the
       field vocabulary, used by [get], by the check [set] applies, and by the extra options
       of [add];
     - [#eval_forest_attribute] is the setter indexed by attribute name (machine.ml:652-666);
     - the constructor registers the component by itself (network#add_node, user_level.ml:854)
       and creates its ifconfig entry (l.1092), which makes [add] the [Add.reaction] of the GUI
       (machine.ml:146-161) with the dialog removed.

   Everything below runs inside a single [ask] whose thunk calls [st#network_change]: lookup,
   guard and action happen in the same GTK slot, as for transitions (§ 4.4). This is correct
   *because* GMain_actor.delegate without ~async is GMain_actor.apply (gMain_actor.ml:126), and
   [apply] executes directly when the caller already is the GTK main thread (l.82) — no queuing,
   no nested wait. Going through network_change is not optional: it is what tells the rest of the
   application that the persistent model changed (set_project_not_already_saved) and redraws the
   sketch (state.ml:892-903). That redraw is also why a big network may deserve a larger
   --timeout here than the 5s default.

   One consequence of the same fact deserves care: [apply] catches the exception of its thunk
   (EitherExtra.protect) and [delegate] then *ignores* it. An action that raises inside
   network_change would therefore look like a success. Hence the [failure] reference each command
   below carries: the exception is caught where it happens, not where it would be lost. *)

(* [#to_tree] is (tag, attributes) * children; components have no children in this version. *)
let fields_of_tree (((_tag, attrs), _children) : Xforest.tree) : (string * string) list = attrs

(* A value produced by [Marshal.to_string] (rc_config: machine.ml:645, switch.ml:455, and the
   eight of router.ml) is not text: serving it would put invalid UTF-8 in the middle of a JSON
   line, and accepting one would mean asking a shell client to forge marshalled bytes. Rather
   than listing the field names — a list that would rot the day a component adds one — the bytes
   say it themselves: every marshalled value starts with one of OCaml's three magic numbers
   (0x8495A6BD/BE/BF). Reading and writing those fields is the business of the dedicated
   rc-get/rc-set commands (§ 10, episode 4e). *)
let is_marshalled (v:string) : bool =
  (String.length v >= 4)
  && v.[0] = '\x84' && v.[1] = '\x95' && v.[2] = '\xa6'
  && (match v.[3] with '\xbd' | '\xbe' | '\xbf' -> true | _ -> false)

(* Changing one of these two is not "setting a field": renaming a component also renames its
   defects rows and — for a virtual machine — its ifconfig and history rows and its hostfs
   directory, while changing the number of ports rebuilds the ports card and the defects
   sub-tree. [eval_forest_attribute] would only call set_name / set_port_no and leave orphan
   treeview rows behind, a project corrupted in silence and discovered at the next startup only.
   Since episode 4d-2b they go through [update_structural_with], the model's own method
   (user_level.ml), which is the structural half of the eight update_<kind>_with the GUI dialogs
   call. Note that "eth" needs no entry here: it is a read-only alias kept for old .mar files
   (machine.ml:664) and is not published by #to_tree, so it is already refused as an unknown
   field, with the list of the real ones. *)
let structural_fields = [ "name"; "port_no" ]

(* What a node can do and a cable cannot. The bounds are the ones the GUI dialog itself uses:
   [port_no_lower_of] (user_level.ml:1872) is not [port_no_min] but the smallest *multiple* of it
   that still holds every busy port — measured at episode 4d-3, and it is more than a detail: a
   switch whose highest cabled port is the 9th cannot go down to 9 ports, but to 12, because it is
   sized by multiples of 4. Reducing a switch below a cabled port is refused to the script exactly
   as it is to the human (hub.ml:91). *)
type structural = {
  st_update      : name:string -> port_no:int -> unit;
  st_name        : string;
  st_port_no     : int;
  st_port_no_min : int;   (* effective: smallest multiple of the kind's minimum holding every cable *)
  st_port_no_kind_min : int;  (* the kind's own minimum, kept only to say *why* a refusal happens *)
  st_port_no_max : int;
  }

(* The options that are *not* fields: they belong to the command itself. *)
let reserved_options = [ "timeout"; "ports" ]

let json_of_fields (fields : (string * string) list) : string =
  jobj (List.map (fun (k, v) -> (k, if is_marshalled v then jnull else jstr v)) fields)

(* Named, not silently dropped: a client must see that the field exists and that this channel
   does not serve it. *)
let marshalled_field_names (fields : (string * string) list) : string list =
  List.filter_map (fun (k, v) -> if is_marshalled v then Some k else None) fields

let field_names (fields : (string * string) list) : string = String.concat ", " (List.map fst fields)

(* The common face of a node and a cable. They share [component] (hence Xforest.interpreter) and
   [simulated_device], but not their type: a cable has no [string_of_devkind], and its can_modify
   /can_destroy are overridden to true (a wire is edited and removed while the network runs,
   § 4.10). Coercing both to this closed object type gives one implementation of get/set/del
   instead of two. *)
type editable = <
  to_tree               : Xforest.tree;
  eval_forest_attribute : Xforest.attribute -> unit;
  can_modify            : bool;
  can_destroy           : bool;
  state_as_string       : string;
  get_name              : string;
  destroy               : unit;
  (* [None] for everything but a machine and a router (user_level.ml, component): the host
     directory the guest sees as /mnt/hostfs, hence where a startup configuration writes
     back. Read by rc-get/rc-set. *)
  hostfs_directory_if_any : string option;
  (* [None] for everything but a machine and a router: the kernels their filesystem declares as
     supported (SUPPORTED_KERNELS), in the same order as the GUI combo. Read by the two guards
     of episode 4f — the model itself still accepts any installed kernel. *)
  supported_kernels_if_any : string list option;
  >

type component_outcome =
  | Co_added     of string * (string * string) list  (* kind, fields read back after creation *)
  | Co_connected of (string * string) list * bool    (* fields read back, polarity is right *)
  | Co_deleted   of string * string list             (* kind, cables destroyed along with it *)
  (* kind, field, old value, new value, and the fields this write forced along with it
     (field, old, new) — see [adjust_kernel_after_distrib_change] *)
  | Co_set       of string * string * string * string * (string * string * string) list
  | Co_read      of string * (string * string) list  (* kind, fields (all, or the one asked) *)
  (* kind, field, (enabled, content), hostfs *)
  | Co_rc_read   of string * string * (bool * string) * string option
  (* kind, field, before, after, hostfs *)
  | Co_rc_set    of string * string * (bool * string) * (bool * string) * string option
  | Co_no_project
  | Co_unknown
  | Co_forbidden of string * string                  (* past participle, raw state *)
  | Co_bad       of string

let reply_of_component_outcome ~(name:string) : component_outcome -> string = function
  | Co_added (kind, fields) ->
      reply_ok [ ("component", jstr name);
                 ("kind",      jstr kind);
                 ("added",     jbool true);
                 (* Read back from the network, never assumed: try_to_add_* fails silently
                    (machine.ml:545) and the lesson holds for any creation path. *)
                 ("fields",    json_of_fields fields);
                 ("omitted",   jlist (List.map jstr (marshalled_field_names fields))) ]
  (* Same shape as [Co_added] — a client adds components and connects them with one reading
     routine — plus the one field a cable has and a node has not. *)
  | Co_connected (fields, correct) ->
      reply_ok [ ("component", jstr name);
                 ("kind",      jstr "cable");
                 ("added",     jbool true);
                 ("fields",    json_of_fields fields);
                 ("omitted",   jlist (List.map jstr (marshalled_field_names fields)));
                 (* False is not an error: the cable exists and is plugged in, but its polarity
                    does not suit the two nodes it joins (cable.ml:674). *)
                 ("correct",   jbool correct) ]
  | Co_deleted (kind, cables) ->
      reply_ok [ ("component", jstr name);
                 ("kind",      jstr kind);
                 ("deleted",   jbool true);
                 (* Removing a node removes the cables plugged into it (user_level.ml:1843).
                    Saying which ones is not a detail: the script's model of the network would
                    otherwise silently diverge from ours. *)
                 ("cables_destroyed", jlist (List.map jstr cables)) ]
  | Co_set (kind, field, old_value, new_value, adjusted) ->
      reply_ok [ ("component", jstr name);
                 ("kind",      jstr kind);
                 ("field",     jstr field);
                 ("old",       jstr old_value);
                 ("new",       jstr new_value);
                 ("changed",   jbool (old_value <> new_value));
                 (* Always present, usually empty: a write that forces another field says so,
                    exactly as [Co_deleted] says which cables went with the node. A script whose
                    model of the network silently diverges from ours is worse than a refusal. *)
                 ("adjusted",
                  jlist (List.map
                           (fun (f, o, n) -> jobj [ ("field", jstr f);
                                                    ("old",   jstr o);
                                                    ("new",   jstr n) ])
                           adjusted)) ]
  | Co_read (kind, fields) ->
      reply_ok [ ("component", jstr name);
                 ("kind",      jstr kind);
                 ("fields",    json_of_fields fields);
                 ("omitted",   jlist (List.map jstr (marshalled_field_names fields))) ]
  (* The content travels in clear, on one line: json_escape turns its newlines into \n, which
     is what makes a multi-line shell scenario fit the answer format of this channel. *)
  | Co_rc_read (kind, field, (enabled, content), hostfs) ->
      reply_ok [ ("component", jstr name);
                 ("kind",      jstr kind);
                 ("field",     jstr field);
                 ("enabled",   jbool enabled);
                 ("content",   jstr content);
                 ("bytes",     jint (String.length content));
                 ("hostfs",    jopt hostfs) ]
  (* Sizes, not the old content: a scenario may be long, and the client that wants it back
     asks rc-get. What matters here is *what changed*, and it is read back from the model. *)
  | Co_rc_set (kind, field, (was_enabled, was), (enabled, content), hostfs) ->
      reply_ok [ ("component",      jstr name);
                 ("kind",           jstr kind);
                 ("field",          jstr field);
                 ("enabled_before", jbool was_enabled);
                 ("enabled",        jbool enabled);
                 ("old_bytes",      jint (String.length was));
                 ("bytes",          jint (String.length content));
                 ("changed",        jbool ((was_enabled, was) <> (enabled, content)));
                 ("hostfs",         jopt hostfs) ]
  | Co_no_project ->
      reply_error ~code:"no_active_project" ~detail:"no project is open"
  | Co_unknown ->
      reply_error ~code:"unknown_node" ~detail:(Printf.sprintf "no component named %S" name)
  | Co_forbidden (participle, raw) ->
      reply_error ~code:"forbidden_transition"
        ~detail:(Printf.sprintf "%S cannot be %s in state %S"
                   name participle (script_state_of_raw raw))
  | Co_bad detail -> reply_error ~code:"bad_argument" ~detail

(* Lookup, guard and action, in one GTK slot. A mutation needs an open project: without one the
   network is empty but the working directories a component expects (hostfs, states) are not
   there. *)
let with_component (st : State.globalState) ~(timeout:float) ~(name:string)
    ~(f : kind:string -> structural:structural option -> editable -> component_outcome) : string
  =
  ask ~timeout
    (fun () ->
       if not st#active_project then Co_no_project else
       match List.find_opt (fun n -> n#get_name = name) (st#network#get_node_list) with
       | Some n ->
           let structural = {
             st_update      = (fun ~name ~port_no -> n#update_structural_with ~name ~port_no);
             st_name        = n#get_name;
             st_port_no     = n#get_port_no;
             st_port_no_min = st#network#port_no_lower_of n;
             st_port_no_kind_min = n#port_no_min;
             st_port_no_max = n#port_no_max;
             }
           in
           f ~kind:n#string_of_devkind ~structural:(Some structural) (n :> editable)
       | None ->
       match List.find_opt (fun c -> c#get_name = name) (st#network#get_cable_list) with
       | Some c -> f ~kind:"cable" ~structural:None (c :> editable)
       | None -> Co_unknown)
  |> reply_of_outcome (reply_of_component_outcome ~name)

(* --- get --------------------------------------------------------- *)

let cmd_get (st : State.globalState) ~(timeout:float) ~(name:string) ~(field:string option)
  : string
  =
  with_component st ~timeout ~name ~f:(fun ~kind ~structural:_ c ->
    let fields = fields_of_tree c#to_tree in
    match field with
    | None   -> Co_read (kind, fields)
    | Some f ->
        (match List.assoc_opt f fields with
         | Some v -> Co_read (kind, [ (f, v) ])
         | None   ->
             Co_bad (Printf.sprintf "no field %S on %S (kind %s); known fields: %s"
                       f name kind (field_names fields))))

(* --- set --------------------------------------------------------- *)

(* Both branches of [set] end here: run the mutation in the GTK slot we are already in, then
   report the value *read back*, never the one asked for (some setters normalise). [apply]
   swallows nothing: [GMain_actor.apply] captures the exception of its thunk, so the failure is
   caught where it happens and the model's own message is returned to the client. *)
let mutate_and_read_back (st : State.globalState) ~(kind:string) ~(field:string) ~(old:string)
    ~(refused:exn -> string) ~(action: unit -> unit)
    ?(adjust : (unit -> (string * string * string) list) = fun () -> [])
    (c : editable) : component_outcome
  =
  let failure = ref None in
  let adjusted = ref [] in
  (* [adjust] runs in the *same* network_change as the action: restoring an invariant the write
     has just broken is part of that write, not a second one — one GTK slot, one redraw, and no
     window during which the component is inconsistent. *)
  let () =
    st#network_change
      (fun () -> try action (); adjusted := adjust () with e -> failure := Some e) ()
  in
  match !failure with
  | Some e -> Co_bad (refused e)
  | None ->
      let now =
        match List.assoc_opt field (fields_of_tree c#to_tree) with
        | Some v -> v
        | None   -> old
      in
      Co_set (kind, field, old, now, !adjusted)

(* --- the (filesystem, kernel) couple, episode 4f -------------------- *)

(* Machines and routers carry two fields that are not independent: the filesystem ("distrib") and
   the kernel that boots it ("kernel"). Their .conf declares which kernels it supports
   (SUPPORTED_KERNELS, disk.ml:272-330) and the GUI dialog offers no other one: the kernel combo is
   a *slave* of the distribution combo and is repopulated at every change
   (Gui_bricks.make_combo_boxes_of_vm_installations, gui_bricks.ml:540-541). The model, on the
   contrary, accepts any installed kernel (check_kernel, user_level.ml) — deliberately, since a
   .mar may reference a kernel that escapes SUPPORTED_KERNELS and refusing it would make the
   project unloadable. So the rule of § 4.10 ("the same limits as the GUI", which includes the
   dialogs' entry guards, episode 4d-2b) is enforced here, on the two commands that write:

     - [set <n> kernel <k>] refuses a kernel the filesystem does not support, *before* writing;
     - [set <n> distrib <d>] is accepted (the GUI locks that combo once the device exists,
       gui_bricks.ml:529-531, but the model has no such limit and the code says "TODO: release
       this constraint") and the kernel is realigned when the new filesystem does not support the
       current one — reported in [adjusted], never silently.

   The kernel a component starts with is no longer a problem: since episode 4f the constructor
   takes the first kernel supported by its filesystem (user_level.ml), as the dialog does. *)

let supported_kernels_and_distrib (c : editable) : (string list * string) option =
  match c#supported_kernels_if_any with
  | None | Some [] -> None
  | Some ks ->
      let distrib =
        match List.assoc_opt "distrib" (fields_of_tree c#to_tree) with
        | Some d -> d
        | None   -> "?"
      in
      Some (ks, distrib)

(* [Some detail] when the value is a kernel this component's filesystem does not declare. *)
let unsupported_kernel (c : editable) (value : string) : string option =
  match supported_kernels_and_distrib c with
  | None -> None
  | Some (ks, _) when List.mem value ks -> None
  | Some (ks, distrib) ->
      Some (Printf.sprintf
              "the filesystem %S does not support the kernel %S; supported kernels: %s. The GUI \
               dialog offers no other one either (gui_bricks.ml:540-541); a kernel outside this \
               list produces a component that never boots"
              distrib value (String.concat ", " ks))

(* Called inside the network_change that has just changed "distrib". Returns what it had to
   rewrite, in the (field, old, new) shape of [Co_set]. *)
let adjust_kernel_after_distrib_change (c : editable) : (string * string * string) list =
  match supported_kernels_and_distrib c with
  | None -> []
  | Some (ks, _) ->
      (match List.assoc_opt "kernel" (fields_of_tree c#to_tree) with
       | None -> []
       | Some k when List.mem k ks -> []
       | Some k ->
           let () = c#eval_forest_attribute ("kernel", List.hd ks) in
           (* Read back rather than assumed, as everywhere else here: eval_forest_attribute goes
              through remap_obsolete_kernel_at_import (machine.ml:664). *)
           let now =
             match List.assoc_opt "kernel" (fields_of_tree c#to_tree) with
             | Some v -> v
             | None   -> List.hd ks
           in
           [ ("kernel", k, now) ])

(* The structural branch (episode 4d-2b). Every guard below is read from the model — none is a
   rule invented by the channel — and each one is tested *before* acting, because
   [update_structural_with] destroys the simulated device on its way: a refusal must cost
   nothing, and a no-op must not cost a rebuild either. *)
let set_structural (st : State.globalState) ~(kind:string) ~(field:string) ~(value:string)
    ~(old:string) ~(s:structural) (c : editable) : component_outcome
  =
  let apply ~name ~port_no =
    mutate_and_read_back st ~kind ~field ~old c
      ~action:(fun () -> s.st_update ~name ~port_no)
      ~refused:(fun e -> Printf.sprintf "the model refused %S = %S: %s"
                           field value (Printexc.to_string e))
  in
  match field with
  | "name" ->
      if value = s.st_name then Co_set (kind, field, old, old, []) else
      (* THE SAME TWO CHECKS THE GUI DIALOG MAKES BEFORE CALLING THE MODEL
         (Gui_bricks.Ok_callback.check_name: identifier, then uniqueness), and they must happen
         *here* rather than be left to the model, because the renaming path is NOT atomic:
         [update_virtual_machine_with] renames the ifconfig and history rows and the hostfs
         directory *before* [set_name] gets a chance to refuse the name (user_level.ml:1418-1425).
         A name refused half-way would leave exactly the orphan rows this whole episode exists to
         prevent — measured, not feared: a bench run left m1's ifconfig row named "1m".
         Uniqueness is ours to check too: only [network#add_node] tests it, and a rename does not
         go through it; two homonymous components would then be indistinguishable to every
         command of this channel, which addresses them by name. *)
      if not (StrExtra.Class.identifierp value) then
        Co_bad (Printf.sprintf
                  "%S is not a well-formed name: admissible characters are letters, digits and \
                   underscores" value)
      else if st#network#name_exists value then
        Co_bad (Printf.sprintf "the name %S is already used in this network" value)
      else apply ~name:value ~port_no:s.st_port_no
  | _ (* "port_no" *) ->
      (match int_of_string_opt value with
       | None -> Co_bad (Printf.sprintf "%S expects an integer, got %S" field value)
       | Some n when n = s.st_port_no -> Co_set (kind, field, old, old, [])
       | Some n when n < s.st_port_no_min ->
           (* Three different refusals, and the client is told which one: a fixed-size component,
              a kind whose minimum is higher, or cables occupying the ports above. *)
           Co_bad (Printf.sprintf
                     "a %s cannot have fewer than %d port(s) here: %s"
                     kind s.st_port_no_min
                     (if s.st_port_no_kind_min = s.st_port_no_max then
                        "this kind of component has a fixed number of ports"
                      else if s.st_port_no_min > s.st_port_no_kind_min then
                        Printf.sprintf
                          "cables are plugged too high for that, and this kind of component is \
                           sized by multiples of %d (user_level.ml:1872): freeing a port means \
                           removing its cable (del)" s.st_port_no_kind_min
                      else
                        "this is the minimum of this kind of component"))
       | Some n when n > s.st_port_no_max ->
           Co_bad (Printf.sprintf "a %s cannot have more than %d ports" kind s.st_port_no_max)
       | Some n -> apply ~name:s.st_name ~port_no:n)

let cmd_set (st : State.globalState) ~(timeout:float) ~(name:string) ~(field:string)
            ~(value:string) : string
  =
  with_component st ~timeout ~name ~f:(fun ~kind ~structural c ->
    let fields = fields_of_tree c#to_tree in
    match List.assoc_opt field fields with
    (* Unknown field names are refused rather than applied: eval_forest_attribute ignores what it
       does not know (| _ -> (), machine.ml:666, for forward compatibility with future .mar
       files), so a typo would be swallowed in silence. *)
    | None ->
        Co_bad (Printf.sprintf "no field %S on %S (kind %s); known fields: %s"
                  field name kind (field_names fields))
    | Some old when is_marshalled old ->
        Co_bad (Printf.sprintf
                  "the field %S holds a marshalled value; it is served by the dedicated \
                   rc-get/rc-set commands (episode 4e), not by get/set" field)
    | Some _ when not c#can_modify -> Co_forbidden ("modified", c#state_as_string)
    | Some old when List.mem field structural_fields ->
        (match structural with
         | Some s -> set_structural st ~kind ~field ~value ~old ~s c
         (* A cable, and this is not a hole in the contract but the GUI's own answer: a cable is
            never renamed, it is destroyed and built again (cable.ml:158-176), so that its
            defects entry, its endpoints and its reference counters are rebuilt from scratch.
            The channel will offer that path as del + connect (§ 4.5, episode 4d-3); renaming
            it in place here would leave its defects entry under the old name. *)
         | None ->
             Co_bad (Printf.sprintf
                       "a cable is not renamed in place: the GUI destroys it and creates it \
                        again (cable.ml:158-176). Use del + connect (§ 4.5)"))
    | Some old ->
        (* The kernel guard comes before the write, like every other one here: the model would
           accept the value and the component would simply never boot (episode 4f). *)
        (match (if field = "kernel" then unsupported_kernel c value else None) with
         | Some detail -> Co_bad detail
         | None ->
             mutate_and_read_back st ~kind ~field ~old c
               ~action:(fun () -> c#eval_forest_attribute (field, value))
               ~adjust:(fun () ->
                  if field = "distrib" then adjust_kernel_after_distrib_change c else [])
               (* int_of_string on a value that is not a number, set_port_no out of range,
                  check_label on a label carrying '<'... the model's own validation, reported
                  instead of being lost in the GTK slot. *)
               ~refused:(fun e -> Printf.sprintf "the model refused %S = %S: %s"
                                    field value (Printexc.to_string e))))

(* --- del --------------------------------------------------------- *)

let cmd_del (st : State.globalState) ~(timeout:float) ~(name:string) : string =
  with_component st ~timeout ~name ~f:(fun ~kind ~structural:_ c ->
    if not c#can_destroy then Co_forbidden ("deleted", c#state_as_string) else
    (* Computed before the destruction, and harmless for a cable: no cable involves a *node*
       named like a cable, so the list is empty there. *)
    let doomed_cables =
      List.map (fun c -> c#get_name) (st#network#get_cables_involved_by_node_name name)
    in
    let failure = ref None in
    let () = st#network_change (fun () -> try c#destroy with e -> failure := Some e) () in
    match !failure with
    | Some e -> Co_bad (Printf.sprintf "destroying %S failed: %s" name (Printexc.to_string e))
    | None   ->
        if st#network#name_exists name then
          Co_bad (Printf.sprintf "%S is still in the network after being destroyed (see the log)"
                    name)
        else Co_deleted (kind, doomed_cables))

(* --- add --------------------------------------------------------- *)

(* The only place in this file that knows the eight kinds by name, and it knows nothing else
   about them: one constructor call each. Two facts justify calling them directly instead of
   going through the try_to_add_* registry (user_level.ml:1714), which would have been uniform:
     - the registry swallows the error (with _ -> false, machine.ml:545), so a refused name or a
       malformed attribute would come back as a bare "false";
     - it requires port_no (List.assoc raises without it) while the correct default is local to
       each file (Const.port_no_default: machine 1, hub/switch/router/world_gateway 4, cloud 2,
       world_bridge 1). Calling the constructor takes that default from where it is defined
       instead of copying seven integers here.
   Cables are not in this list: they need two endpoints and a polarity, which is § 4.5
   (episode 4d-3). *)
let node_maker (st : State.globalState) ~(kind:string) ~(name:string) ~(ports:int option)
  : ((unit -> unit), string) result
  =
  let network = st#network in
  let port_no default = match ports with Some n -> n | None -> default in
  (* cloud and world_bridge have a fixed number of ports (cloud.ml:268, world_bridge.ml:289):
     accepting --ports there would be accepting an argument we drop. *)
  let no_ports_here () =
    Error (Printf.sprintf "a %s has a fixed number of ports: --ports does not apply" kind)
  in
  match kind with
  | "machine" ->
      Ok (fun () -> ignore (new Machine.User_level_machine.machine ~network ~name
                              ~port_no:(port_no Machine.Const.port_no_default) ()))
  | "router" ->
      Ok (fun () -> ignore (new Router.User_level_router.router ~network ~name
                              ~port_no:(port_no Router.Const.port_no_default) ()))
  | "switch" ->
      Ok (fun () -> ignore (new Switch.User_level_switch.switch ~network ~name
                              ~port_no:(port_no Switch.Const.port_no_default) ()))
  | "hub" ->
      Ok (fun () -> ignore (new Hub.User_level_hub.hub ~network ~name
                              ~port_no:(port_no Hub.Const.port_no_default) ()))
  | "world_gateway" ->
      Ok (fun () -> ignore (new World_gateway.User_level_world_gateway.world_gateway ~network ~name
                              ~port_no:(port_no World_gateway.Const.port_no_default) ()))
  | "cloud" when ports <> None -> no_ports_here ()
  | "cloud" ->
      Ok (fun () -> ignore (new Cloud.User_level_cloud.cloud ~network ~name ()))
  | "world_bridge" when ports <> None -> no_ports_here ()
  | "world_bridge" ->
      Ok (fun () -> ignore (new World_bridge.User_level_world_bridge.world_bridge ~network ~name ()))
  | "cable" ->
      Error "a cable is created by the connect command, which needs its two endpoints (§ 4.5)"
  | _ ->
      Error (Printf.sprintf "no such kind %S; known kinds: %s" kind (String.concat ", " known_kinds))

let cmd_add (st : State.globalState) ~(timeout:float) ~(kind:string) ~(name:string)
            ~(ports:string option) ~(extra:(string * string) list) : string
  =
  match (match ports with
         | None   -> Ok None
         | Some s -> (match int_of_string_opt s with
                      | Some n when n >= 0 -> Ok (Some n)
                      | _ -> Error (Printf.sprintf
                                      "--ports expects a non-negative integer, got %S" s)))
  with
  | Error detail -> reply_error ~code:"bad_argument" ~detail
  | Ok ports ->
  ask ~timeout
    (fun () ->
       if not st#active_project then Co_no_project else
       if st#network#name_exists name then
         Co_bad (Printf.sprintf "the name %S is already used in this network" name)
       else
       match node_maker st ~kind ~name ~ports with
       | Error detail -> Co_bad detail
       | Ok create ->
           let failure = ref None in
           let () = st#network_change (fun () -> try create () with e -> failure := Some e) () in
           (match !failure with
            (* check_name refuses anything that is not an identifier (user_level.ml:521-523);
               the constructor is the only place that knows it, so we let it speak. *)
            | Some e -> Co_bad (Printf.sprintf "creating %S failed: %s" name (Printexc.to_string e))
            | None ->
            match List.find_opt (fun n -> n#get_name = name) (st#network#get_node_list) with
            | None ->
                Co_bad (Printf.sprintf "%S was not added to the network (see the log)" name)
            | Some n ->
                let component = (n :> editable) in
                let fields = fields_of_tree component#to_tree in
                (* The remaining --<field>=<value> options are applied through the same setter as
                   [set], with the same three refusals. An invalid one leaves nothing behind: the
                   component is destroyed again, so that a failed [add] means an unchanged
                   network — the alternative being a half-configured component the script never
                   asked for. *)
                let rollback detail =
                  let () = st#network_change (fun () -> try component#destroy with _ -> ()) () in
                  Co_bad detail
                in
                let rec apply = function
                  | [] ->
                      (* --distrib= may have brought a filesystem that does not support the kernel
                         the constructor chose (it chooses the first one supported by the *default*
                         filesystem, user_level.ml). Realign before answering, so that [add] alone
                         yields a bootable component; an explicit --kernel= that got through the
                         guard below is supported by construction, so this is a no-op there. The
                         adjusted value is not announced apart: [Co_added] reports every field
                         read back from the model. *)
                      let failure = ref None in
                      let () =
                        st#network_change
                          (fun () -> try ignore (adjust_kernel_after_distrib_change component)
                                     with e -> failure := Some e) ()
                      in
                      (match !failure with
                       | Some e ->
                           rollback (Printf.sprintf
                                       "aligning the kernel with the filesystem failed: %s"
                                       (Printexc.to_string e))
                       | None -> Co_added (kind, fields_of_tree component#to_tree))
                  | (k, _) :: _ when not (List.mem_assoc k fields) ->
                      rollback (Printf.sprintf
                                  "no field %S on a %s; known fields: %s" k kind (field_names fields))
                  | (k, _) :: _ when List.mem k structural_fields ->
                      rollback (Printf.sprintf
                                  "the field %S cannot be set here: the name is the second \
                                   argument of add, and the number of ports is --ports" k)
                  | (k, _) :: _ when is_marshalled (List.assoc k fields) ->
                      rollback (Printf.sprintf
                                  "the field %S holds a marshalled value; use rc-set \
                                   (episode 4e)" k)
                  | (k, v) :: rest ->
                      (* Same guard as [set]: a kernel the filesystem does not declare builds a
                         component that never boots (episode 4f). *)
                      (match (if k = "kernel" then unsupported_kernel component v else None) with
                       | Some detail -> rollback detail
                       | None ->
                      let failure = ref None in
                      let () =
                        st#network_change
                          (fun () -> try component#eval_forest_attribute (k, v)
                                     with e -> failure := Some e) ()
                      in
                      (match !failure with
                       | Some e -> rollback (Printf.sprintf "the model refused %S = %S: %s"
                                               k v (Printexc.to_string e))
                       | None   -> apply rest))
                in
                (* "distrib" first, whatever order the client wrote its options in: it conditions
                   the others (which variants exist, which kernels are supported), so applying
                   --kernel= before --distrib= would check the kernel against the *default*
                   filesystem and refuse a couple that is in fact valid. *)
                let extra =
                  let (distrib, others) = List.partition (fun (k, _) -> k = "distrib") extra in
                  distrib @ others
                in
                apply extra))
  |> reply_of_outcome (reply_of_component_outcome ~name)

(* --- connect ----------------------------------------------------- *)

(* § 4.5. The cable is the one component [add] cannot build: it is made of two endpoints and a
   polarity instead of a kind and a number of ports (which is why [node_maker] above sends it
   here). Everything else it shares with the seven others: its constructor registers it by itself
   (network#add_cable, cable.ml:666), #to_tree publishes its fields, and [get]/[set]/[del] already
   serve it since episodes 4d-2a and 4b.

   Note what is NOT here. The "disconnect" announced by § 4.5 named two commands that already
   exist: unplugging a cable is [suspend]/[resume] — the GUI's own Disconnect/Reconnect, delivered
   at episode 4c — and removing it is [del], measured on a running network at episode 4b. A third
   spelling would have been a synonym to keep in step, not a feature. *)

type endpoint_spec = { ep_node : string; ep_port : string }

(* "m1:eth0". The separator is unambiguous: a node name is an identifier (no colon,
   user_level.ml:521) and a user port name is <prefix><digits> (user_level.ml:592). The port is
   named as the GUI and the .mar name it ("eth0", "port3"), not by index: the translation to an
   internal index is [ports_card#internal_index_of_user_port_name], the very method the cable
   constructor uses (cable.ml:645), and going through indexes here would mean copying each kind's
   [user_port_offset]. *)
let endpoint_of_string (s:string) : (endpoint_spec, string) result =
  let malformed () =
    Error (Printf.sprintf
             "%S is not an endpoint: expected <node>:<port>, as in m1:eth0" s)
  in
  match String.index_opt s ':' with
  | None -> malformed ()
  | Some i ->
      let node = String.sub s 0 i in
      let port = String.sub s (i + 1) (String.length s - i - 1) in
      if node = "" || port = "" then malformed () else
      Ok { ep_node = node; ep_port = port }

let cmd_connect (st : State.globalState) ~(timeout:float) ~(name:string)
                ~(left:string) ~(right:string) ~(crossover:bool) : string
  =
  match endpoint_of_string left with
  | Error detail -> reply_error ~code:"bad_argument" ~detail
  | Ok l ->
  match endpoint_of_string right with
  | Error detail -> reply_error ~code:"bad_argument" ~detail
  | Ok r ->
  ask ~timeout
    (fun () ->
       if not st#active_project then Co_no_project else
       (* The same two checks the GUI dialog makes (Gui_bricks.Ok_callback.check_name), for the
          same reason as everywhere else in this file: the model refuses too (check_name at
          construction, then network#add_cable on a duplicate) but says it with an exception,
          where the client deserves a motivated bad_argument. *)
       if not (StrExtra.Class.identifierp name) then
         Co_bad (Printf.sprintf
                   "%S is not a well-formed name: admissible characters are letters, digits and \
                    underscores" name)
       else if st#network#name_exists name then
         Co_bad (Printf.sprintf "the name %S is already used in this network" name)
       else
       (* Resolved here, inside the GTK slot, and not before: the node list and the busy ports
          belong to the model, and reading them from the session thread would race with the task
          runner. The third check is the guard the model does NOT have — the constructor resolves
          <node>:<port> and plugs in, whatever is already there. In the GUI it is the dialog that
          holds it, by offering free endpoints only (network#free_endpoint_list_humanly_speaking,
          user_level.ml:1833); on this channel it is us. *)
       let resolve (e : endpoint_spec) =
         match List.find_opt (fun n -> n#get_name = e.ep_node) (st#network#get_node_list) with
         | None ->
             Error (Printf.sprintf "no node named %S in this network" e.ep_node)
         | Some n ->
             let ports = n#ports_card#user_port_name_list in
             let free  = st#network#free_user_port_names_of_node n in
             if not (List.mem e.ep_port ports) then
               Error (Printf.sprintf "node %S has no port %S; its ports are: %s"
                        e.ep_node e.ep_port (String.concat ", " ports))
             else if not (List.mem e.ep_port free) then
               Error (Printf.sprintf
                        "port %s:%s is already taken by a cable; free ports of %S: %s"
                        e.ep_node e.ep_port e.ep_node
                        (match free with [] -> "none" | _ -> String.concat ", " free))
             else Ok n
       in
       match resolve l with
       | Error detail -> Co_bad detail
       | Ok _ ->
       match resolve r with
       | Error detail -> Co_bad detail
       | Ok _ ->
       (* Both ends are free, so nothing above catches the one endpoint given twice. A loop from a
          node to itself on two *distinct* ports stays legal: a wire may do that in reality, and
          the project rule is that cabling follows reality. *)
       if l.ep_node = r.ep_node && l.ep_port = r.ep_port then
         Co_bad (Printf.sprintf "a cable cannot have both ends on %s:%s" l.ep_node l.ep_port)
       else
       let failure = ref None in
       let () =
         st#network_change
           (fun () ->
              try
                ignore
                  (new Cable.User_level_cable.cable
                     ~network:st#network ~crossover ~name
                     ~left_user_endpoint:(l.ep_node, l.ep_port)
                     ~right_user_endpoint:(r.ep_node, r.ep_port) ())
              with e -> failure := Some e)
           ()
       in
       (match !failure with
        | Some e ->
            Co_bad (Printf.sprintf "connecting %S failed: %s" name (Printexc.to_string e))
        | None ->
        match List.find_opt (fun c -> c#get_name = name) (st#network#get_cable_list) with
        | None ->
            Co_bad (Printf.sprintf "%S was not added to the network (see the log)" name)
        | Some c ->
            (* [is_correct] is reported, never enforced: the GUI itself lets a human build a
               straight cable between two machines, on purpose ("allowing users to define 'wrong'
               connections may be of some pedagogical interest", cable.ml:380). The channel does
               the same — it wires what it is told to wire, and says whether the polarity works. *)
            Co_connected (fields_of_tree c#to_tree, c#is_correct)))
  |> reply_of_outcome (reply_of_component_outcome ~name)

(* ---------------------------------------------------------------- *)
(*                  The startup configuration (rc)                  *)
(* ---------------------------------------------------------------- *)

(* § 4.11, and the direction of § 10: the channel commands the *infrastructure*, the startup
   configuration commands the *inside* of the machines. The mechanism is entirely in place —
   the content is dropped into hostfs/marionnet-relay.rcfile (simulation_level.ml:1244-1251)
   and *sourced* at the end of the guest relay's start() (marionnet-relay.trixie:486-494) —
   only its programmatic access was missing.

   Two facts shape everything below:

   1. The field is read when the *device is built* (machine.ml:674-678), never while it runs:
      a scenario is posted *before* [start], and posting one on a running component is refused
      here exactly as the GUI refuses to edit it ([can_modify], § 4.10).

   2. In the forest the field is *marshalled* (machine.ml:645), which is why get/set serve it
      as null and name it in [omitted] since episode 4d-2a. The channel could not ask a shell
      client to forge marshalled bytes — so the content travels in clear and *the server
      marshals it itself*, on the way in as on the way out. That single decision is what keeps
      these two commands free of any per-kind dispatch: they go through the same uniform
      [#eval_forest_attribute] as [set]. *)

(* A scenario is a shell script, not an image. The bound exists so that a mistyped --from does
   not load a filesystem into the project file. *)
let max_rc_bytes = 1024 * 1024

(* A startup configuration is a marshalled [(bool * string)] = (enabled, content): machine and
   switch call the field "rc_config" (machine.ml:614, switch.ml:411), a router calls its own
   "rc_config_unix" (router.ml:1100). Rather than keeping that list of names — which
   [is_marshalled] above deliberately refuses to keep, "the day a component adds one" — the
   value is asked what it is: it is demarshalled into [Obj.t], which assumes *no* type at all,
   and its shape is then inspected. [Obj.obj] is applied only once the shape matches, which is
   the exact opposite of an [Obj.magic]: no cast is taken on trust.

   The router's three other marshalled fields do not have this shape (an association list and
   two string lists) and are therefore not offered here; they stay in [omitted]. *)
let rc_config_of_marshalled (v:string) : (bool * string) option =
  if not (is_marshalled v) then None else
  match (try Some (Marshal.from_string v 0 : Obj.t) with _ -> None) with
  | None -> None
  | Some o ->
      let is_bool x = Obj.is_int x && (let i : int = Obj.obj x in i = 0 || i = 1) in
      let is_string x = Obj.is_block x && Obj.tag x = Obj.string_tag in
      if Obj.is_block o && Obj.tag o = 0 && Obj.size o = 2
         && is_bool (Obj.field o 0) && is_string (Obj.field o 1)
      then Some (Obj.obj o : bool * string)
      else None

let rc_fields_of (fields : (string * string) list) : (string * (bool * string)) list =
  List.filter_map
    (fun (k, v) -> match rc_config_of_marshalled v with Some rc -> Some (k, rc) | None -> None)
    fields

(* Naming the field is optional because there is exactly one candidate on each of the three
   kinds that have one today. The three answers below are all the cases, and none of them is a
   silence: no candidate, several (a kind that would gain a second one), or a name that is not
   one. *)
let rc_field_of ~(kind:string) ~(name:string) ~(field:string option)
    (fields : (string * string) list) : ((string * (bool * string)), string) result
  =
  let candidates = rc_fields_of fields in
  match field, candidates with
  | None, [ one ] -> Ok one
  | None, [] ->
      Error (Printf.sprintf
               "%S (kind %s) has no startup configuration: today a machine, a switch and a \
                router have one" name kind)
  | None, several ->
      Error (Printf.sprintf
               "%S (kind %s) has several startup configuration fields (%s): name the one you \
                mean" name kind (String.concat ", " (List.map fst several)))
  | Some f, _ ->
      (match List.assoc_opt f candidates with
       | Some rc -> Ok (f, rc)
       | None ->
           (match List.assoc_opt f fields with
            | None ->
                Error (Printf.sprintf "no field %S on %S (kind %s); known fields: %s"
                         f name kind (field_names fields))
            | Some _ ->
                Error (Printf.sprintf
                         "the field %S is not a startup configuration (it does not hold an \
                          (enabled, content) pair)%s"
                         f
                         (match candidates with
                          | [] -> ""
                          | l  -> Printf.sprintf "; here it is: %s"
                                    (String.concat ", " (List.map fst l))))))

(* Read in the serving thread, never inside the GTK slot: a file read is I/O, and the GTK main
   loop is not the place for it. The absolute path is required for the reason [open] requires
   it (cmd_open): Marionnet chdir's to its own home at startup, so a relative path would not
   mean to us what it means to the client. *)
let rc_content_of_file (path:string) : (string, string) result =
  if Filename.is_relative path then
    Error (Printf.sprintf "--from expects an absolute path (got %S)" path)
  else
  match (try Some (Unix.stat path) with _ -> None) with
  | None -> Error (Printf.sprintf "--from: no such file: %S" path)
  | Some s when s.Unix.st_kind <> Unix.S_REG ->
      Error (Printf.sprintf "--from: %S is not a regular file" path)
  | Some s when s.Unix.st_size > max_rc_bytes ->
      Error (Printf.sprintf
               "--from: %S holds %d bytes, more than the %d allowed for a startup configuration"
               path s.Unix.st_size max_rc_bytes)
  | Some _ ->
      (try Ok (UnixExtra.cat path)
       with e -> Error (Printf.sprintf "--from: cannot read %S: %s" path (Printexc.to_string e)))

(* The answer of this channel is one JSON line, and json_escape passes bytes >= 0x80 through as
   UTF-8. A content that is not valid UTF-8 would therefore be *accepted* here and make rc-get
   emit a line no client could parse — a failure landing far from its cause. It is refused at
   the door instead. *)
let rc_content_is_servable (content:string) : (unit, string) result =
  if String.is_valid_utf_8 content then Ok () else
  Error "the content is not valid UTF-8: this channel answers in JSON, and rc-get could not \
         serve it back on a line"

let cmd_rc_get (st : State.globalState) ~(timeout:float) ~(name:string) ~(field:string option)
  : string
  =
  with_component st ~timeout ~name ~f:(fun ~kind ~structural:_ c ->
    match rc_field_of ~kind ~name ~field (fields_of_tree c#to_tree) with
    | Error detail  -> Co_bad detail
    | Ok (f, rc)    -> Co_rc_read (kind, f, rc, c#hostfs_directory_if_any))

let cmd_rc_set (st : State.globalState) ~(timeout:float) ~(name:string) ~(field:string option)
    ~(from:string option) ~(inline:string option) ~(enable:bool option) : string
  =
  let asked_content =
    match from, inline with
    | Some _, Some _ ->
        Error "--from=<file> and an inline content cannot be given together"
    | Some p, None   -> Result.map (fun s -> Some s) (rc_content_of_file p)
    | None,   Some s -> Ok (Some s)
    | None,   None   -> Ok None
  in
  let asked_content =
    asked_content >>= function
    (* Neither a content nor a flag: there is nothing this command could do, and answering "ok"
       to a request that changes nothing asked-for would hide a client bug. *)
    | None when enable = None ->
        Error "nothing to do: give a content (--from=<file> or an inline one) or a flag \
               (--enable|--disable)"
    | None        -> Ok None
    | Some c as x -> Result.map (fun () -> x) (rc_content_is_servable c)
  in
  match asked_content with
  | Error detail -> reply_error ~code:"bad_argument" ~detail
  | Ok content ->
  with_component st ~timeout ~name ~f:(fun ~kind ~structural:_ c ->
    match rc_field_of ~kind ~name ~field (fields_of_tree c#to_tree) with
    | Error detail -> Co_bad detail
    | Ok (f, before) ->
        (* The same guard the GUI dialog obeys — and here it is more than a rule: the field is
           read when the device is built, so writing it on a running component would change
           nothing the client could observe until the next start. *)
        if not c#can_modify then Co_forbidden ("modified", c#state_as_string) else
        let (was_enabled, was_content) = before in
        let new_content = match content with Some s -> s | None -> was_content in
        (* Posting a scenario enables it, unless --disable says otherwise: a content that would
           silently never run is the surprise this channel exists to avoid. The flag alone
           leaves the content untouched. *)
        let new_enabled =
          match enable with
          | Some b -> b
          | None   -> (match content with Some _ -> true | None -> was_enabled)
        in
        let asked = (new_enabled, new_content) in
        (* A no-op costs no write: network_change marks the project as modified and redraws the
           sketch (state.ml:892-903). *)
        if asked = before then Co_rc_set (kind, f, before, before, c#hostfs_directory_if_any)
        else
        let failure = ref None in
        let () =
          st#network_change
            (fun () ->
               try c#eval_forest_attribute (f, Marshal.to_string asked [])
               with e -> failure := Some e)
            ()
        in
        (match !failure with
         | Some e ->
             Co_bad (Printf.sprintf "the model refused the startup configuration %S: %s"
                       f (Printexc.to_string e))
         | None ->
             (* Read back, never assumed — the rule this file follows everywhere. *)
             let after =
               match List.assoc_opt f (fields_of_tree c#to_tree) with
               | Some v -> (match rc_config_of_marshalled v with Some rc -> rc | None -> asked)
               | None   -> asked
             in
             Co_rc_set (kind, f, before, after, c#hostfs_directory_if_any)))

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

(* --- wait --ready: the signal the guest itself writes ------------- *)

(* [--state=on] means "the UML process was launched", never "the guest has booted" (§ 2). The
   missing half is a signal only the guest can give, and episode 4e proved the whole path: a
   startup configuration runs arbitrary bash at the end of the boot, and /mnt/hostfs is a *host*
   directory. The convention, and it is the whole of it: the scenario writes
   <hostfs>/marionnet-guest-ready.

   Two properties are worth stating, because they are what makes this cheap:
   - nothing is injected. [rc-set] puts back exactly what the script gave it (episode 4e), so
     the marker is written by the scenario, by hand, from the snippet documented in § 4.7;
   - nothing is stored between polls, and [start] gains no side effect. A marker left by the
     *previous* run is ignored by comparing its mtime with the one of <hostfs>/boot_parameters,
     which [uml_process] rewrites from its initializer — hence at every device construction,
     hence at every startup (simulation_level.ml:1235, 1253-1256, 1331-1332).

   The name is deliberately not [marionnet-relay.*]: the guest relay sources
   /mnt/hostfs/{<fs>.,marionnet-}relay* at the end of its boot (marionnet-relay.trixie:486-494),
   and a marker matching that glob would be *executed* as bash. *)

let ready_marker_basename    = "marionnet-guest-ready"
let boot_parameters_basename = "boot_parameters"

(* The marker says "ready"; its first line says whatever the scenario wanted to add to it (a
   verdict, a version, a step number). Bounded, because a guest writes it. *)
let max_ready_line_bytes = 4096

type ready_probe =
  | Rp_gone                                       (* destroyed while we were waiting *)
  | Rp_no_hostfs                                  (* a switch, a hub, a cable: it cannot apply *)
  | Rp_waiting of float option * float option     (* mtimes of (marker, boot_parameters) *)
  | Rp_ready   of string * float * string option  (* marker path, its mtime, its first line *)

let mtime_of_regular_file (path:string) : float option =
  match (try Some (Unix.stat path) with _ -> None) with
  | Some s when s.Unix.st_kind = Unix.S_REG -> Some (s.Unix.st_mtime)
  | _ -> None

(* Cut at the first newline, trimmed, and served only if it is valid UTF-8 — the same reason as
   [rc_content_is_servable]: the answer is one JSON line. Anything else (empty, binary, or
   truncated because a scenario wrote in place instead of moving a temporary file) becomes
   [None]: the *signal* must never depend on what the guest chose to write. *)
let first_line_of (path:string) : string option =
  let read () =
    let ic = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic)
      (fun () -> really_input_string ic (min (max_ready_line_bytes) (in_channel_length ic)))
  in
  match (try Some (read ()) with _ -> None) with
  | None -> None
  | Some raw ->
      let line =
        match String.index_opt raw '\n' with
        | Some i -> String.sub raw 0 i
        | None   -> raw
      in
      let line = String.trim line in
      if line = "" || not (String.is_valid_utf_8 line) then None else Some line

let cmd_wait_ready (st : State.globalState) ~(gtk_timeout:float) ~(wait_timeout:float)
                   ~(name:string) : string
  =
  if name = "" then
    reply_error ~code:"bad_argument" ~detail:"wait expects the name of a component"
  else
  (* The GTK slot is spent on one thing, the same one [cmd_wait] spends it on: finding the
     component — a script must be *told* that it was destroyed instead of timing out — and
     reading where its guest writes. The observation itself is a [stat]: I/O, hence run in this
     thread, never in the GTK main loop. *)
  let observe () =
    match
      ask ~timeout:gtk_timeout
        (fun () ->
           match List.find_opt (fun n -> n#get_name = name) (st#network#get_node_list) with
           | Some n -> Some (n#hostfs_directory_if_any)
           | None ->
           match List.find_opt (fun c -> c#get_name = name) (st#network#get_cable_list) with
           | Some _ -> Some None
           | None   -> None)
    with
    | Failed e         -> Failed e
    | Timed_out t      -> Timed_out t
    | Done None        -> Done (Rp_gone)
    | Done (Some None) -> Done (Rp_no_hostfs)
    | Done (Some (Some dir)) ->
        let marker = Filename.concat dir ready_marker_basename in
        let boot   = Filename.concat dir boot_parameters_basename in
        (* [>=] and not [>]: a stale marker was written by a previous run, seconds or minutes
           before the current boot_parameters, so a strict comparison would only buy a
           theoretical case — and would lose the real one if the mtime resolution ever fell
           back to the second. *)
        (match mtime_of_regular_file marker, mtime_of_regular_file boot with
         | Some m, Some b when m >= b -> Done (Rp_ready (marker, m, first_line_of marker))
         | m, b                       -> Done (Rp_waiting (m, b)))
  in
  poll_until ~wait_timeout ~observe
    ~reached:(function Rp_waiting _ -> false | _ -> true)
    ~on_reached:(fun v elapsed ->
       match v with
       | Rp_gone ->
           reply_error ~code:"unknown_node" ~detail:(Printf.sprintf "no component named %S" name)
       | Rp_no_hostfs ->
           reply_error ~code:"bad_argument"
             ~detail:(Printf.sprintf
                        "%S runs no guest system of its own, hence has no hostfs directory: \
                         --ready applies to a machine or a router; use --state to wait for the \
                         state Marionnet knows" name)
       | Rp_ready (marker, mtime, line) ->
           reply_ok [ ("component", jstr name);
                      ("ready",     jbool true);
                      ("line",      jopt line);
                      ("marker",    jstr marker);
                      ("mtime",     jfloat mtime);
                      ("waited",    jfloat elapsed) ]
       | Rp_waiting _ -> assert false (* [reached] said otherwise *))
    ~on_expiry:(fun v elapsed ->
       let detail =
         match v with
         | Rp_waiting (_, None) ->
             Printf.sprintf
               "%S has not been started since this project was opened (no %s in its hostfs \
                directory), hence nothing could have written %s (%.1fs waited)"
               name boot_parameters_basename ready_marker_basename elapsed
         | Rp_waiting (None, Some _) ->
             Printf.sprintf
               "%S wrote no %s in its hostfs directory after %.1fs: the guest may still be \
                booting, or its startup configuration may be disabled, or may simply not write \
                the marker (see rc-get, and § 4.7)"
               name ready_marker_basename elapsed
         | Rp_waiting (Some m, Some b) ->
             Printf.sprintf
               "%S has a %s, but it was written %.1fs *before* its current boot: it was left by \
                a previous run and is ignored (%.1fs waited)"
               name ready_marker_basename (b -. m) elapsed
         | _ -> assert false (* [reached] said otherwise *)
       in
       reply_error ~code:"timeout" ~detail)

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

(* --- the project: new, save, save-as, close ---------------------- *)

(* The menu does not simply call the method bearing the name of the entry. For "New" and
   "Close" it runs, in a thread of its own (gui_menubar_MARIONNET.ml:94-105 and 262-278), the
   sequence "shut everything down, save if the human said yes, close" — and only then creates
   the new project. A script gets that same sequence, with the modal question replaced by an
   explicit option: an interactive confirmation cannot be honestly emulated, but it can be
   *demanded*. Hence [unsaved_changes] when neither --save nor --no-save is given while the
   project holds unsaved changes; quietly discarding someone's work was the only alternative.

   Everything below runs in the serving thread, never through GMain_actor: close_project and
   save_project dispatch on am_I_the_GTK_main_thread and execute in the *calling* thread when it
   is not the GTK one (state.ml:357-360, 813-816) — the very path the menu takes from its own
   thread, and the lesson [open] taught at episode 3a. These commands are therefore blocking,
   and shutting a running network down takes as long as it takes: a client needs a generous read
   timeout, not a --timeout, which only bounds each round trip to the GTK thread. *)

type save_policy = Save_it | Discard_it

let save_policy_of_options (r:request) : (save_policy option, string) result =
  match (option_value r "save" <> None), (option_value r "no-save" <> None) with
  | true,  true  -> Error "--save and --no-save cannot be given together"
  | true,  false -> Ok (Some Save_it)
  | false, true  -> Ok (Some Discard_it)
  | false, false -> Ok None

(* Leaves whatever project is open, following the menu's sequence. [Ok None]: there was nothing
   to leave. [Ok (Some saved)]: a project was left, [saved] telling whether it was saved on the
   way out. [Error answer]: the client must be told why we stopped, [answer] says it. *)
let leave_current_project (st : State.globalState) ~(timeout:float)
                          ~(policy: save_policy option)
                          ~(extra: unit -> (string * string) list)
  : (bool option, string) result
  =
  let ask_ f = ask_or_answer ~extra ~timeout f in
  ask_ (fun () -> (st#active_project, st#project_already_saved))
  >>= fun (active, already_saved) ->
  if not active then Ok None else
  if policy = None && not already_saved then
    Error (reply_error_with ~extra:(extra ()) ~code:"unsaved_changes"
             ~detail:"the project has unsaved changes: pass --save or --no-save to say what to do with them")
  else
  let want_save = (policy = Some Save_it) in
  (* Logged here and not at the entry of the commands: a refused close must not leave a line
     saying the project was being closed (N4's rule — an instrument may not lie). *)
  let () = Log.printf1 "Control_server: leaving the current project (save: %b).\n" want_save in
  (* Same order as the menu: the shutdown is only *scheduled* (schedule_parallel,
     state.ml:956-960), the saving happens while the components go down, and close_project is
     what waits for the task runner (state.ml:346). *)
  let () = st#shutdown_everything () in
  (if not want_save then Ok true else
   let () = st#save_project in
   ask_ (fun () -> st#project_already_saved))
  >>= fun saved ->
  (* --save means "save, *then* close": private_save_project catches its own failures and
     reports them by a dialog (state.ml:800-810), so a plain "no exception" proves nothing. If
     the saving failed, closing would destroy exactly what the client asked to keep — we stop
     instead. Deliberately stricter than the menu, which closes anyway. *)
  if not saved then
    Error (reply_error_with ~extra:(extra ()) ~code:"internal"
             ~detail:"saving the project failed: nothing was closed (see the log and the notifications)")
  else
  let () = st#close_project in
  ask_ (fun () -> st#active_project) >>= fun still_active ->
  if still_active then
    Error (reply_error_with ~extra:(extra ()) ~code:"internal"
             ~detail:"the project is still open after closing it (see the log)")
  else Ok (Some want_save)

let cmd_close (st : State.globalState) ~(timeout:float) ~(policy: save_policy option) : string =
  let since = Script_mode.last_seq () in
  let extra () = [ ("notifications", jnotifications (Script_mode.notifications ~since ())) ] in
  match leave_current_project st ~timeout ~policy ~extra with
  | Error answer    -> answer
  | Ok None         -> reply_error_with ~extra:(extra ()) ~code:"no_active_project"
                         ~detail:"no project is open"
  | Ok (Some saved) -> reply_ok ([ ("closed", jbool true); ("saved", jbool saved) ] @ extra ())

(* Unlike the menu, no extension is appended to the file name: Talking's helper for that opens
   dialogs of its own (talking.ml:119-131), and a script that says /tmp/tp.mar means it. *)
let cmd_new (st : State.globalState) ~(timeout:float) ~(policy: save_policy option)
            ~(filename:string) : string
  =
  (* Marionnet chdir's to its own home at startup, so a relative path would not mean what the
     client believes (same reason as [open]). *)
  if Filename.is_relative filename then
    reply_error ~code:"bad_argument"
      ~detail:(Printf.sprintf "an absolute path is required (got %S)" filename)
  else
  let since = Script_mode.last_seq () in
  let extra () = [ ("notifications", jnotifications (Script_mode.notifications ~since ())) ] in
  match leave_current_project st ~timeout ~policy ~extra with
  | Error answer -> answer
  | Ok _ ->
      let () = Log.printf1 "Control_server: creating project %s\n" filename in
      (* new_project delegates to the GTK main thread and returns at once (state.ml:325-326):
         its completion is *observed*, not returned. --timeout bounds that wait here. *)
      let () = st#new_project ~filename in
      poll_until ~wait_timeout:timeout
        ~observe:(fun () ->
           ask ~timeout:default_timeout
             (fun () -> (st#active_project, st#project_paths#get_filename)))
        ~reached:(fun (active, actual) -> active && actual = Some filename)
        ~on_reached:(fun _ elapsed ->
           reply_ok ([ ("file",    jstr filename);
                       ("created", jbool true);
                       ("waited",  jfloat elapsed) ] @ extra ()))
        ~on_expiry:(fun (active, actual) elapsed ->
           reply_error_with ~extra:(extra ()) ~code:"timeout"
             ~detail:(Printf.sprintf
                        "creating %S did not complete within %.1fs (active=%b, current file=%s; see the log)"
                        filename elapsed active
                        (match actual with None -> "none" | Some f -> Printf.sprintf "%S" f)))

(* [save] and [save-as] differ only by the file the project goes to: save_project_as sets the
   name, then calls save_project (state.ml:820-828). Success is [project_already_saved], never
   the absence of an exception — same lesson as [open] (episode 3a). *)
let cmd_save (st : State.globalState) ~(timeout:float) ~(filename: string option) : string =
  match filename with
  | Some f when Filename.is_relative f ->
      reply_error ~code:"bad_argument"
        ~detail:(Printf.sprintf "an absolute path is required (got %S)" f)
  | _ ->
  let since = Script_mode.last_seq () in
  let extra () = [ ("notifications", jnotifications (Script_mode.notifications ~since ())) ] in
  let ask_ f = ask_or_answer ~extra ~timeout f in
  answer_of_result @@
  (ask_ (fun () -> st#active_project) >>= fun active ->
  if not active then
    Error (reply_error_with ~extra:(extra ()) ~code:"no_active_project"
             ~detail:"no project is open")
  else
  (* save_project_as re-raises what change_filename_and_root_basename may throw
     (state.ml:820-828); save_project does not throw at all. *)
  (try Ok (match filename with
           | None   -> st#save_project
           | Some f -> st#save_project_as ~filename:f ())
   with e -> Error (reply_error_with ~extra:(extra ()) ~code:"internal"
                      ~detail:(Printexc.to_string e)))
  >>= fun () ->
  ask_ (fun () -> (st#project_already_saved, st#project_paths#get_filename))
  >>= fun (saved, actual) ->
  if saved then Ok (reply_ok ([ ("saved", jbool true); ("file", jopt actual) ] @ extra ()))
  else
    Error (reply_error_with ~extra:(extra ()) ~code:"internal"
             ~detail:"saving the project failed (see the log and the notifications)"))

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
(*                            Treeviews                             *)
(* ---------------------------------------------------------------- *)

(* § 4.6. The four treeviews hold what the network model does not: the addresses (ifconfig), the
   link impairments (defects), the saved states (history) and the attached documents — that is,
   where the actual configuration of a lab exercise lives. Reading them costs no new model method:
   state.ml:612-618 publishes the four instances and state.ml:620-631 already coerces them to
   [Treeview.t], the class that carries the whole reading API.

   Three facts of the code shape the contract below, rather than a symmetry we would have picked:

   (a) the four do NOT share a mother class. ifconfig and defects inherit
       [treeview_with_a_primary_key_Name_column] (a Name is unique), history inherits
       [treeview_with_a_Name_column] (a machine holds several rows, one per saved state, so a name
       matches several roots) and documents inherits the bare [Treeview.t] — it has no Name column
       at all. Hence an optional name filter on the first three and none on documents;

   (b) their hierarchies are unequal: ifconfig is node → ports, defects is node → ports →
       directions *and* cable → directions, history is a tree of COW states, documents is flat.
       Flattening all that into a table would lose it, so the forest is served as a forest, and the
       filter stays on the roots — a deeper path would promise one thing and do three;

   (c) reading is pure OCaml, not GTK: #get_forest (treeview.ml:1241) reads the [id_forest] ref and
       the [id_to_row] hashtable, a legacy of the [marionnet-automate-composants] work stream (the
       treeviews no longer read the widget). We still go through [ask], because *writes* do go
       through #set_complete_forest, wrapped in GMain_actor.apply_extract (treeview.ml:1267):
       reading in a GTK slot is what makes an answer one consistent snapshot rather than a mix. *)

let treeview_name_column = "Name"

(* No UTF-8 guard here, unlike rc-set (episode 4e): [json_escape] passes bytes >= 0x80 through,
   assuming UTF-8, and that assumption holds on this path — a treeview cell comes from a GTK
   widget or from the .mar loader, never from an arbitrary host file the way rc-set --from does. *)
let json_of_row_item : Treeview.Row_item.t -> string = function
  | Treeview.Row_item.String   s -> jstr s
  | Treeview.Row_item.Icon     s -> jstr s
  | Treeview.Row_item.CheckBox b -> jbool b

(* The headers served, in the order the GUI shows them: #add_column *appends*
   (treeview.ml:908), so #columns keeps that order — whereas #column_headers is a Hashtbl.fold,
   whose order is unspecified and would make any assertion on it flaky. Reserved columns (_id,
   _uneditable, _highlight) are left out, exactly as #get_row leaves them out of a row
   (treeview.ml:1419). *)
let visible_headers (tv : Treeview.t) : string list =
  List.filter_map (fun c -> if c#is_reserved then None else Some c#header) tv#columns

(* A column this row does not carry is *omitted*, not served as null: the treeviews do have
   partial rows (a device row has no MTU), and an absent field is not an empty one. *)
let rec json_of_row_tree ~(headers : string list)
    ((row, children) : Treeview.Row.t Forest.tree) : string
  =
  let field h =
    match List.assoc_opt h row with
    | None   -> None
    | Some v -> Some (h, json_of_row_item v)
  in
  jobj [ ("fields",   jobj (List.filter_map field headers));
         ("children", jlist (List.map (json_of_row_tree ~headers)
                               (Forest.to_treelist children))) ]

type treeview_outcome =
  | Tv_read       of string list * Treeview.Row.t Forest.tree list  (* headers, roots kept *)
  | Tv_no_project
  (* The root names, so that a refusal also says what does exist — a script mistyping a node name
     otherwise learns nothing from the answer. *)
  | Tv_unknown    of string list

let cmd_treeview (st : State.globalState) ~(timeout:float) ~(which:string) ~(name:string option)
  : string
  =
  ask ~timeout
    (fun () ->
       (* Same guard as the component commands: without an open project the treeviews are empty,
          and an empty answer would read as "this node has no ports". *)
       if not st#active_project then Tv_no_project else
       let tv : Treeview.t =
         match which with
         | "ifconfig" -> (st#treeview#ifconfig  :> Treeview.t)
         | "defects"  -> (st#treeview#defects   :> Treeview.t)
         | "history"  -> (st#treeview#history   :> Treeview.t)
         | _          -> (st#treeview#documents :> Treeview.t)
       in
       let headers = visible_headers tv in
       let roots = Forest.to_treelist tv#get_forest in
       let root_name ((row, _) : Treeview.Row.t Forest.tree) =
         match List.assoc_opt treeview_name_column row with
         | Some (Treeview.Row_item.String s) -> Some s
         | _ -> None
       in
       match name with
       | None -> Tv_read (headers, roots)
       | Some wanted ->
           (match List.filter (fun t -> root_name t = Some wanted) roots with
            | []   -> Tv_unknown (List.sort_uniq compare (List.filter_map root_name roots))
            | kept -> Tv_read (headers, kept)))
  |> reply_of_outcome
       (function
        | Tv_read (headers, roots) ->
            reply_ok [ ("treeview", jstr which);
                       ("columns",  jlist (List.map jstr headers));
                       (* The number of *roots* served, so that a bench may require a non-zero
                          cardinal: without one, jq compares empty lists and the bench applauds
                          without having measured anything (lesson (c) of episode 4b). *)
                       ("count",    jint (List.length roots));
                       ("rows",     jlist (List.map (json_of_row_tree ~headers) roots)) ]
        | Tv_no_project ->
            reply_error ~code:"no_active_project" ~detail:"no project is open"
        | Tv_unknown names ->
            reply_error ~code:"unknown_node"
              ~detail:(Printf.sprintf "no row named %S in the %s treeview; known: %s"
                         (match name with Some n -> n | None -> "") which
                         (String.concat ", " names)))

(* § 4.6, write side (episode 5b). ifconfig is where a lab exercise is actually configured — the
   read side measured that not one example project carries a single IPv4 address — and writing a
   cell costs more than calling a setter, for two reasons the code states out loud:

   (a) [#set_row_field] (treeview.ml) validates nothing and fires no callback. Both live in the
       GTK cell-edited path (editable_string_column#on_edit, l.444): the column predicate refuses
       a malformed address or an MTU above vde2's MAXPACKET, and the *row* constraints refuse what
       no single cell can tell — a value typed on a device row instead of one of its ports, or a
       router whose first port would lose its address (treeview_ifconfig.ml:472-493). Writing
       without them would put into a project what a human is not allowed to type, against § 4.10;

   (b) [#check_constraints] shows a dialog before raising. Not blocking, and captured since
       episode 3c — but a refusal of this channel is a JSON answer, not a window. Hence
       [#constraints_verdict] (episode 5b): the very same checks, reporting left to the caller.

   The other half of the GUI's after_user_edit_callback (marionnet.ml:178) is the restart
   question: "your changes will be applied after the reboot of X; restart it now?". The server
   cannot ask a human, so it asks the *script*: --restart or --no-restart, required as soon as the
   node is running, exactly as --save/--no-save became required at episode 4d. What the GUI puts
   in a dialog, the channel puts in the request. *)

(* A header as a script spells it: lowercase, spaces to dashes ("IPv4 address" → ipv4-address).
   Derived, never listed — the same reason the read side publishes #columns: a column added to a
   treeview becomes writable the day it becomes readable, with no table here to update. *)
let slug_of_header (h:string) : string =
  String.map (function ' ' -> '-' | c -> c) (String.lowercase_ascii h)

(* Which cells a human may type into. [#is_editable] (treeview.ml, episode 5b) is true of exactly
   the column class whose GTK renderer carries `EDITABLE true, so this list is the GUI's own
   answer: Name and Type are read-only, and the hidden _uneditable checkbox is not a text cell.
   The reserved filter is not redundant: _highlight-color IS an editable string column
   (treeview.ml:1825), reserved only — the same frontier the read side draws, so the write side
   draws it too. Measured, not assumed: without it the channel offered _highlight-color as a
   writable field. *)
let editable_headers (tv : Treeview.t) : string list =
  List.filter_map
    (fun c -> if c#is_editable && not c#is_reserved then Some c#header else None)
    tv#columns

let tree_name ((row, _) : Treeview.Row.t Forest.tree) : string option =
  match List.assoc_opt treeview_name_column row with
  | Some (Treeview.Row_item.String s) -> Some s
  | _ -> None

let string_cell (row : Treeview.Row.t) (header:string) : string =
  match List.assoc_opt header row with
  | Some (Treeview.Row_item.String s) -> s
  | _ -> ""

type ifconfig_outcome =
  (* header, old value, value read back, whether the node was restarted *)
  | If_written        of string * string * string * bool
  | If_no_project
  | If_unknown_node   of string list
  | If_unknown_port   of string list
  | If_unknown_field  of string list
  | If_violated       of string
  | If_restart_choice of string   (* the raw state of the running node *)

let cmd_ifconfig_set (st : State.globalState) ~(timeout:float) ~(node:string) ~(port:string)
    ~(field:string) ~(value:string) ~(restart:bool option) : string
  =
  ask ~timeout
    (fun () ->
       if not st#active_project then If_no_project else
       let tv = (st#treeview#ifconfig :> Treeview.t) in
       (* The complete forest, not #get_forest: writing needs the _id of the row, which is
          reserved and therefore absent from the rows the read side serves. *)
       let roots = Forest.to_treelist tv#get_complete_forest in
       match List.find_opt (fun t -> tree_name t = Some node) roots with
       (* The names offered are those of *this* treeview, not of the network: ifconfig only holds
          addressable components (episode 5a), so listing the network's nodes would offer a switch
          as a candidate for an address it cannot have. *)
       | None -> If_unknown_node (List.sort_uniq compare (List.filter_map tree_name roots))
       | Some (_device_row, children) ->
           let ports = Forest.to_treelist children in
           (match List.find_opt (fun t -> tree_name t = Some port) ports with
            (* Also the answer when a script aims at the device row itself (ifconfig-set m1 m1 …):
               that row is not a port, and the row constraint below would refuse it anyway. *)
            | None -> If_unknown_port (List.filter_map tree_name ports)
            | Some (port_row, _) ->
                let headers = editable_headers tv in
                (match List.find_opt (fun h -> slug_of_header h = field) headers with
                 | None -> If_unknown_field (List.map slug_of_header headers)
                 | Some header ->
                     let old = string_cell port_row header in
                     (* A write that changes nothing validates nothing and restarts nothing: the
                        GUI does not fire its callback either when a cell is left as it was. *)
                     if value = old then If_written (header, old, old, false) else
                     let new_row =
                       Treeview.Row.set_field ~field:header
                         ~value:(Treeview.Row_item.String value) port_row
                     in
                     (match tv#constraints_verdict new_row with
                      | Some (`Row name) ->
                          (* %s and not %S: a row constraint is named with a *translated* string
                             (s_ "…", treeview_ifconfig.ml:473), and OCaml's %S escapes every byte
                             above 0x7f as \195\168 — the answer would carry an unreadable name
                             where json_escape lets UTF-8 through untouched. *)
                          If_violated
                            (Printf.sprintf
                               "the treeview row constraint \"%s\" refuses this write (the GUI \
                                refuses it too)" name)
                      | Some (`Column h) ->
                          If_violated
                            (Printf.sprintf "the column %S does not accept %S" h value)
                      | None ->
                          (* The very guard marionnet.ml:169 applies before asking the human. A
                             node absent from the network (an orphan ifconfig row) is treated as
                             not running: there is nothing to restart. *)
                          let running =
                            match List.find_opt (fun n -> n#get_name = node)
                                    (st#network#get_node_list)
                            with
                            | Some n when n#can_gracefully_shutdown -> Some n
                            | _ -> None
                          in
                          (match running, restart with
                           | Some n, None -> If_restart_choice n#state_as_string
                           | _ ->
                               let row_id = Treeview.Row.get_id port_row in
                               let () =
                                 tv#set_row_field row_id header
                                   (Treeview.Row_item.String value)
                               in
                               (* First half of after_user_edit_callback (marionnet.ml:180). No
                                  network_change here: the network model did not change, and the
                                  GUI does not redraw the sketch on this path either. *)
                               let () = st#set_project_not_already_saved in
                               let restarted =
                                 match running, restart with
                                 | Some n, Some true -> let () = n#gracefully_restart in true
                                 | _ -> false
                               in
                               (* Read back, never assumed — same rule as [set] (episode 4d-2a). *)
                               let written =
                                 Treeview.Row_item.extract_String (tv#get_row_field row_id header)
                               in
                               If_written (header, old, written, restarted))))))
  |> reply_of_outcome
       (function
        | If_written (header, old, written, restarted) ->
            reply_ok [ ("node",      jstr node);
                       ("port",      jstr port);
                       ("field",     jstr header);
                       ("old",       jstr old);
                       ("new",       jstr written);
                       ("changed",   jbool (old <> written));
                       (* Never "restarted and booted": #gracefully_restart queues the work on the
                          task runner, like every transition of § 4.4 (rule 3, episode 4c). *)
                       ("restarted", jbool restarted) ]
        | If_no_project ->
            reply_error ~code:"no_active_project" ~detail:"no project is open"
        | If_unknown_node names ->
            reply_error ~code:"unknown_node"
              ~detail:(Printf.sprintf
                         "no row named %S in the ifconfig treeview; addressable components: %s"
                         node (String.concat ", " names))
        | If_unknown_port names ->
            reply_error ~code:"unknown_port"
              ~detail:(Printf.sprintf "%S has no port named %S; its ports are: %s"
                         node port (String.concat ", " names))
        | If_unknown_field slugs ->
            reply_error ~code:"unknown_field"
              ~detail:(Printf.sprintf "no writable field %S in ifconfig; writable fields: %s"
                         field (String.concat ", " slugs))
        | If_violated detail ->
            reply_error ~code:"constraint_violated" ~detail
        | If_restart_choice raw ->
            reply_error ~code:"restart_choice_required"
              ~detail:(Printf.sprintf
                         "%S is %s: the GUI asks here whether to reboot it, so the script must \
                          say --restart or --no-restart"
                         node (script_state_of_raw raw)))

(* ---------------------------------------------------------------- *)
(*                             Dispatch                             *)
(* ---------------------------------------------------------------- *)

(* The answer must be *sent* before quitting, hence the second component: the session loop
   writes it, then triggers the shutdown. *)
let dispatch (st : State.globalState) (line:string) : string * [ `Continue | `Quit ] =
  match parse_request line with
  | None -> (reply_error ~code:"unknown_command" ~detail:"empty request", `Continue)
  (* The shape of the request is checked before anything else (§ 4.1): a surplus argument is a
     script bug, and a silently ignored one is a bug that hides. *)
  | Some (Error detail) -> (reply_error ~code:"bad_argument" ~detail, `Continue)
  | Some (Ok r) ->
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
            | "can"    -> (cmd_can st ~timeout ~name:(arg0 r), `Continue)
            | "add"    ->
                (* Every option but --timeout and --ports is a field of the component: they are
                   checked against what the model publishes, never silently dropped. *)
                let extra = List.filter (fun (k, _) -> not (List.mem k reserved_options)) r.opts in
                (cmd_add st ~timeout ~kind:(arg0 r) ~name:(arg_at r 1)
                   ~ports:(option_value r "ports") ~extra, `Continue)
            | "del"    -> (cmd_del st ~timeout ~name:(arg0 r), `Continue)
            | "get"    -> (cmd_get st ~timeout ~name:(arg0 r) ~field:(arg_opt r 1), `Continue)
            | "set"    -> (cmd_set st ~timeout ~name:(arg0 r) ~field:(arg_at r 1)
                             ~value:(arg_at r 2), `Continue)
            (* A verb of its own for an operation that is not "writing a field" (it renames
               treeview rows and a directory), but strictly the same code: two ways to spell one
               thing, not two behaviours to keep in step. *)
            | "rename" -> (cmd_set st ~timeout ~name:(arg0 r) ~field:"name"
                             ~value:(arg_at r 1), `Continue)
            | "connect" ->
                (* The only command whose behaviour hangs on a bare option, hence the only one
                   that refuses an unknown one: a mistyped --crossover would otherwise build a
                   straight cable in silence. *)
                (match List.filter
                         (fun (k, _) -> not (List.mem k [ "timeout"; "crossover" ])) r.opts
                 with
                 | (k, _) :: _ ->
                     (reply_error ~code:"bad_argument"
                        ~detail:(Printf.sprintf
                                   "no option --%s here; syntax: %s" k
                                   (match List.assoc_opt "connect" arity_of_command with
                                    | Some a -> a.syntax
                                    | None   -> "connect")),
                      `Continue)
                 | [] ->
                     (cmd_connect st ~timeout ~name:(arg0 r) ~left:(arg_at r 1)
                        ~right:(arg_at r 2)
                        ~crossover:(option_value r "crossover" <> None),
                      `Continue))
            (* Like [connect], and for a sharper reason: the behaviour of rc-set hangs on its
               options, and its second argument is *free text*. An unknown option is therefore
               either a typo — a mistyped --disable would post a scenario and enable it — or a
               word of the content that [parse_request] took for an option, the known limit of
               a one-line content. Both deserve the same answer, which names the way out. *)
            | "rc-get" | "rc-set" ->
                let allowed =
                  if r.verb = "rc-get" then [ "timeout"; "field" ]
                  else [ "timeout"; "field"; "from"; "enable"; "disable" ]
                in
                (* rc-get takes the field where [get] takes it, in second position, *and*
                   through --field, so that a script may use the same variable in both
                   commands. Giving both is refused rather than arbitrated: silently keeping
                   one of two contradictory answers is the kind of quiet choice this channel
                   does not make. rc-set has only --field, its second position being the
                   content. *)
                let field =
                  match option_value r "field", (if r.verb = "rc-get" then arg_opt r 1 else None)
                  with
                  | Some f, None      -> `Field (Some f)
                  | None,   Some f    -> `Field (Some f)
                  | None,   None      -> `Field None
                  | Some _, Some _    -> `Twice
                in
                (match field with
                 | `Twice ->
                     (reply_error ~code:"bad_argument"
                        ~detail:"the field is given twice (positional argument and --field): \
                                 give it once",
                      `Continue)
                 | `Field field ->
                match List.filter (fun (k, _) -> not (List.mem k allowed)) r.opts with
                 | (k, _) :: _ ->
                     (reply_error ~code:"bad_argument"
                        ~detail:(Printf.sprintf
                                   "no option --%s here%s; syntax: %s" k
                                   (if r.verb = "rc-set" then
                                      " (a one-line content cannot hold a word starting with \
                                       --: use --from=<file>)"
                                    else "")
                                   (match List.assoc_opt r.verb arity_of_command with
                                    | Some a -> a.syntax
                                    | None   -> r.verb)),
                      `Continue)
                 | [] ->
                     if r.verb = "rc-get" then
                       (cmd_rc_get st ~timeout ~name:(arg0 r) ~field, `Continue)
                     else
                       (match (option_value r "enable" <> None),
                              (option_value r "disable" <> None) with
                        | true, true ->
                            (reply_error ~code:"bad_argument"
                               ~detail:"--enable and --disable cannot be given together",
                             `Continue)
                        | enabled, disabled ->
                            let enable =
                              if enabled then Some true
                              else if disabled then Some false
                              else None
                            in
                            (cmd_rc_set st ~timeout ~name:(arg0 r) ~field
                               ~from:(option_value r "from") ~inline:(arg_opt r 1) ~enable,
                             `Continue)))
            (* One implementation for the four (§ 4.6): the verb only says which instance to
               read, the shape of the answer being the same. documents gets [None] by its
               arity, which takes no positional argument. *)
            | "ifconfig" | "defects" | "history" | "documents" ->
                (cmd_treeview st ~timeout ~which:r.verb ~name:(arg_opt r 0), `Continue)
            (* Same shape as --save/--no-save (episode 4d): the two options are mutually
               exclusive, and giving neither is legal — it is only refused later, and only if the
               node turns out to be running. *)
            | "ifconfig-set" ->
                (match (option_value r "restart" <> None), (option_value r "no-restart" <> None) with
                 | true, true ->
                     (reply_error ~code:"bad_argument"
                        ~detail:"--restart and --no-restart cannot be given together", `Continue)
                 | restart_wanted, no_restart_wanted ->
                     let restart =
                       if restart_wanted then Some true
                       else if no_restart_wanted then Some false
                       else None
                     in
                     (cmd_ifconfig_set st ~timeout ~node:(arg0 r) ~port:(arg_at r 1)
                        ~field:(arg_at r 2)
                        (* No fourth argument means the empty string: clearing a cell. *)
                        ~value:(match arg_opt r 3 with Some v -> v | None -> "")
                        ~restart,
                      `Continue))
            | "open"   -> (cmd_open st ~timeout ~filename:(arg0 r), `Continue)
            | "new" | "close" ->
                (match save_policy_of_options r with
                 | Error detail -> (reply_error ~code:"bad_argument" ~detail, `Continue)
                 | Ok policy ->
                     ((if r.verb = "close" then cmd_close st ~timeout ~policy
                       else cmd_new st ~timeout ~policy ~filename:(arg0 r)),
                      `Continue))
            | "save"    -> (cmd_save st ~timeout ~filename:None, `Continue)
            | "save-as" -> (cmd_save st ~timeout ~filename:(Some (arg0 r)), `Continue)
            | "notifications" ->
                (cmd_notifications
                   ~since:(option_value r "since")
                   ~clear:(option_value r "clear" <> None),
                 `Continue)
            | verb when List.mem verb transition_commands ->
                (cmd_transition st ~timeout ~action:verb ~name:(arg0 r), `Continue)
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
                let ready = option_value r "ready" <> None in
                (* The four combinations are decided here, where both options are in sight;
                   [check_state] keeps saying what a state may be, not which option was meant. *)
                ((match r.verb, state, ready with
                  | _, Some _, true ->
                      reply_error ~code:"bad_argument"
                        ~detail:"--state and --ready cannot be given together: the first waits \
                                 for the state Marionnet knows, the second for the signal the \
                                 guest writes in its hostfs directory"
                  | "wait-all", _, true ->
                      reply_error ~code:"bad_argument"
                        ~detail:"--ready applies to one component at a time: wait <component> \
                                 --ready"
                  | "wait", None, false ->
                      reply_error ~code:"bad_argument"
                        ~detail:(Printf.sprintf "wait expects --state or --ready — usage: %s"
                                   (match List.assoc_opt "wait" arity_of_command with
                                    | Some a -> a.syntax
                                    | None   -> "wait <component> --state=… | --ready"))
                  | "wait", _, true ->
                      cmd_wait_ready st ~gtk_timeout:default_timeout ~wait_timeout ~name:(arg0 r)
                  | "wait", _, false ->
                      cmd_wait st ~gtk_timeout:default_timeout ~wait_timeout ~name:(arg0 r) ~state
                  | _ ->
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
