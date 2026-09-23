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

(* Script control server. The contract, the invariants and the reason why this module
   exports a single value are documented in control_server.mli. Implementation note: we
   only ever *emit* JSON and never parse it, so no dependency is added to the project.

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
(* Same arity, different domain (episode 6): [help] takes the name of a *command*, not of a
   component. Sharing the constructor would make the table read "component" where it means
   "verb" — an alias costs one line and keeps the table honest. *)
let optional_identifier = optional_component
(* Same again for the history commands (episode 5d), whose single argument is the *cow file* of a
   state, not a component: in that treeview Name is not unique, the cow file is. *)
let one_identifier = one_component
(* A state, a field, and an optional free value: a history comment is a sentence, and an absent
   value clears the cell, as in ifconfig-set (episode 5b). *)
let identifier_field_and_free_value syntax =
  { min_args = 2; max_args = 3; free_tail = true; syntax }
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
(* A component and a command line, the latter REQUIRED (episode 18): [exec] with nothing to run
   is not an abbreviation of anything, unlike rc-set above, where the empty content has a
   meaning. The tail is free because a command line is made of spaces — and it is passed to the
   guest's shell exactly as it was received, quoting included: interpreting it here would mean
   holding a second, worse copy of a shell's grammar. *)
let component_and_command     syntax = { min_args = 2; max_args = 2; free_tail = true;  syntax }
(* A treeview cell: node, port, field, and the value — which is *optional*, because that is how a
   cell is emptied, the way a human clears it in the GUI (every ifconfig column predicate accepts
   the empty string, treeview_ifconfig.ml:407-468). Free tail all the same: an address never holds
   a space, but nothing here should decide that for a column added later. *)
let node_port_field_and_value syntax = { min_args = 3; max_args = 4; free_tail = true;  syntax }

(* The per-component transitions of § 4.4. Their names are those of [known_actions] minus
   "set"/"del", which are not transitions and belong to a later episode. *)
let transition_commands = [ "start"; "stop"; "suspend"; "resume"; "poweroff"; "restart" ]
let transition_all_commands = [ "start-all"; "shutdown-all"; "poweroff-all" ]

let beyond_gui_actions = [ "poweroff"; "restart" ]

(* The whole vocabulary of actions, and the only one: the names below are those of the commands
   of § 4.4, so that a client never has to translate between a predicate name and a command name
   (which is why [ls --can=] takes "start" and not "startup"). *)
let known_actions = [ "set"; "del"; "start"; "stop"; "suspend"; "resume"; "poweroff"; "restart" ]

(* The kinds a script may create (§ 4.3). These strings are the model's own
   (#string_of_devkind, redefined in the seven files) and they are also the roots of a .mar
   forest, so [ls --kind=], [add <kind>] and a saved project all speak one language. "cable" is
   absent on purpose: it takes two endpoints, hence its own command (§ 4.5). *)
let known_kinds = [ "machine"; "router"; "switch"; "hub"; "cloud"; "world_bridge"; "nat_bridge"; "world_gateway" ]

(* Episode 3 of `journalisation-profonde'. The two journals a guest leaves in its hostfs
   directory, as (what [log] calls them, what the guest named them):

     rc_config.log  what *the scenario* did, and what failed in it (the trace and the status);
     boot.log       what the boot did before the relay was reached (dmesg, and the services).

   The basenames are the decision of the two scripts which write them
   (bin/scripts/marionnet-relay.{00,zz}-journal.sh); the server only reads them, and publishes the
   short names so that no client holds a copy of this pair. The default is the first question a
   script asks — what its own scenario did; doubting the *image* comes later.

   Episode 4 gave the first of the two a second writer and a second home: a switch has no guest,
   so Marionnet itself journals what its rc did (switch.ml), in the project's working directory.
   The pair of names does not change — a switch simply has only one of them, which is why the
   answer of [log] carries an [available] field of its own.

   Episode 6 added a third, of a third nature: [console] is written by *Marionnet* for a guest —
   what its kernel says before its relay exists, hence the only journal that survives a boot
   which never reaches it (decision D2). Which of the three a given component actually has is
   the business of [journals_of] below; this list is only the vocabulary.

   Episode 7 added a fourth, [commands]: what the student TYPED, one line per command, each one
   preceded by its date (Bash writes a `#<epoch>' line when HISTTIMEFORMAT is set). Written by the
   guest into its hostfs at every prompt — not grabbed at shutdown, since an interactive Bash
   killed during a shutdown writes nothing — so it can be read while the machine runs, and it is
   already there when the exam mode archives it.

   It is NOT called `history', although that is the name of the file (bash_history.text) and the
   word Bash uses: `history' is already a VERB of this grammar (the treeview of saved states,
   § 4.6), and one word must not mean two things in one grammar. Same lesson as `--file' at
   episode 3, where the name was already taken on the client side.

   Episode 16 added a sixth, [report], and it is of a nature none of the other five has: the five
   are TRACES — what was said, appended as it was said — while this one is a STATE, rewritten
   whole at every request (the real interfaces, the routing tables, ip_forward, the firewall in
   replayable form). Episode 15 measured why it had to exist: a trace cannot answer "what is true
   at this instant", and every lab of the corpus asks exactly that.

   It shares its name with the VERB which produces it, on purpose and against the rule that
   settled [commands] above: there [history] was already a verb meaning something *else* (the
   treeview of saved states), whereas here the verb and the journal name one thing — [report]
   asks the guest to write it, [log … report] serves what was written.

   Episode 18 added a seventh, [exec], and its reason is MARKING rather than diagnosis. The verb
   [exec] runs a command inside a guest; without a trace of its own, what the channel injected
   would be indistinguishable from what the student did — worse, it would land in [commands],
   which is precisely the file a corrector reads as the student's work. Two writers, two files:
   the rule this work-stream has applied since episode 8 (console and terminal are never merged
   for the same reason). It holds the command, its date and its status, never its output: the
   output is served in the answer of [exec] itself, and one thing is served in one place. *)
let journal_files =
  [ ("rc_config", "rc_config.log"); ("boot", "boot.log");
    ("commands", "bash_history.text"); ("console", "console.log");
    ("terminal", "terminal.log"); ("report", "report.md");
    ("exec", "exec.log") ]
(* The two Marionnet writes itself, in the project's working directory rather than in a hostfs
   the student may rewrite (episodes 6 and 8): their basename above is only there to keep the
   list uniform — the path comes from simulation_level.ml. *)
let host_side_journals = [ "console"; "terminal" ]
let journal_file_names = List.map fst journal_files
let default_journal_file = "rc_config"

(* Declared here, above [cmd_help], and not beside their first user further down: episode 10
   made [help] publish them, so a Bash completion derives the values of [--kind=] and [--can=]
   instead of holding a third copy of lists the refusals already name. *)

(* The single vocabulary of the channel: what a command is called, what it takes, and how it is
   spelled. [dispatch] and the [unknown_command] answer both read this list. *)
let arity_of_command : (string * arity) list =
  [ (* The vocabulary served by the channel itself (§ 5, episode 6). First in the list because it
       is the way in: a client needs to know nothing but this verb. *)
    ("help",          optional_identifier "help [<command>]");
    ("status",        no_arg "status");
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
    (* --select/--unselect and --terminal/--no-terminal (episode 12) apply to a service
       configuration only — a Quagga tab of a router — and [cmd_rc_set] says so when they do not.
       --from= keeps its place: it is the first placeholder naming a path, which is what
       mrn2sh reads (episode 11). *)
    ("rc-set",        component_and_free_text
                        "rc-set <component> [<one-line content>] [--from=<absolute path>] \
                         [--enable|--disable] [--select|--unselect] \
                         [--terminal|--no-terminal] [--field=<field>]");
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
    (* Episode 5c. Two shapes under one verb, because the treeview has two: a node entry has one
       level per port (node → port → direction), a cable entry has none (cable → direction). Which
       one a request has is not decided by counting its arguments but by the *type* of the row it
       aims at, so the arity here is only the outer envelope — 3 to 5 — and [cmd_defects_set]
       refuses a mixture with the syntax in clear. *)
    ("defects-set",   { min_args = 3; max_args = 5; free_tail = true;
                        syntax = "defects-set <node> <port> <inward|outward> <field> [<value>] \
                                  [--restart|--no-restart]  |  defects-set <cable> \
                                  <leftward|rightward> <field> [<value>]" });
    (* Episode 5d. history by its ACTIONS: a state is named by its cow file (Name is not unique
       in this treeview), and the read side already serves that column. *)
    ("history-start", one_identifier "history-start <cow file>");
    ("history-del",   one_identifier "history-del <cow file> [--except]");
    ("history-set",   identifier_field_and_free_value
                        "history-set <cow file> <field> [<value>]");
    (* Episode 22 of `marionnet-kernel-rootfs'. The last entry of this treeview's menu the
       channel did not cover, and the only step of an image update that could not be
       driven: exporting a state as a VARIANT, which is what a new published image is made
       of. Same family, same identifier (the cow file), because it is the same menu. *)
    ("history-export", two_identifiers
                        "history-export <cow file> <variant name> [--force]");
    ("open",          one_path "open <absolute path>");
    ("new",           one_path "new <absolute path> [--save|--no-save]");
    ("save",          no_arg "save");
    ("save-as",       one_path "save-as <absolute path>");
    ("close",         no_arg "close [--save|--no-save]");
    ("notifications", no_arg "notifications [--since=<n>] [--clear]");
    (* Episode 3 of `journalisation-profonde'. Spelled like rc-get — the file positionally *or*
       through an option — because it is the same gesture: naming one of the few things a
       component keeps beside its fields. Which files there are is published by [help]. *)
    ("log",           component_and_field
                        "log <component> [<file>|--file=<file>] [--tail=<n>]");
    (* Episode 5. Same shape as [log], one letter of grammar apart, because it is the same
       gesture on the other side of the mirror: [log] serves what a component *wrote*, this
       serves what a switch *knows*. Which tables there are is published by [help]. *)
    ("switch-info",   component_and_field
                        "switch-info <switch> [<table>|--table=<table>]");
    (* Episode 16. Completes the pair above on the guest's side: [switch-info] asks a running
       switch what it knows, this asks a running machine or router the same. It answers *that*
       the report was taken — its content is a journal, hence [log <component> report]. *)
    ("report",        one_component "report <component> [--timeout=<s>]");
    (* Episode 18, and the verb which changes what this channel is: the eight above observe, this
       one COMMANDS the inside of a guest. It was left out of episode 16 on purpose and decided
       for itself, because it is the only way to answer "does m1 reach h3 *now*" — a report
       describes a state, never an accessibility. What it runs is journalled apart (see the
       seventh entry of [journal_files]) so that a corrector can always tell what the channel
       injected from what the student typed. *)
    (* `<command-line>' and not `<command>': the latter is already a placeholder of THIS grammar
       (help [<command>]), and the Bash completion derives what it offers from these very words —
       it would have offered the channel's own verbs where a guest's command line is expected.
       The same one-word-one-meaning rule which named the journal [commands] at episode 7. *)
    ("exec",          component_and_command
                        "exec <component> <command-line> [--timeout=<s>]");
    ("wait",          one_component
                        "wait <component> (--state=on|off|sleeping | --ready) [--timeout=<s>]");
    ("wait-all",      no_arg "wait-all --state=on|off|sleeping [--timeout=<s>]");
    ("quit",          no_arg "quit");
    ]
  @ (List.map (fun v -> (v, one_component (v ^ " <component>"))) transition_commands)
  @ (List.map (fun v -> (v, no_arg v)) transition_all_commands)

let known_commands = List.map fst arity_of_command

(* Said in one place because it is said twice: by [help] about the command it was asked for, and
   by [dispatch] about the command it was given. Both read [known_commands], so a verb added to
   the table above is named here without touching anything else. *)
let unknown_command_reply ~(verb:string) : string =
  reply_error ~code:"unknown_command"
    ~detail:(Printf.sprintf "unknown command %S; known commands: %s"
               verb (String.concat ", " known_commands))

(* § 5, episode 6: the channel publishes its own vocabulary. The point is not convenience but
   *unicity* — a client holding its own copy of the grammar would be a second source of truth,
   and the one to drift; that is the reason [forest] was dropped at episode 4g. The order is the
   table's, which is the order of the documentation: nothing here folds a hashtable (the lesson
   of [#column_headers], episode 5a).

   [help] reads a constant list: it touches neither the global state nor the GTK thread, hence no
   ~timeout and no [GMain_actor] on this path. *)
let json_of_command ((verb, a) : string * arity) : string =
  jobj [ ("verb",      jstr verb);
         ("syntax",    jstr a.syntax);
         ("min_args",  jint a.min_args);
         ("max_args",  jint a.max_args);
         ("free_tail", jbool a.free_tail) ]

let cmd_help ~(verb:string option) : string =
  let selected =
    match verb with
    | None   -> Ok arity_of_command
    | Some v ->
        (match List.assoc_opt v arity_of_command with
         | Some a -> Ok [ (v, a) ]
         | None   -> Error v)
  in
  match selected with
  | Error v       -> unknown_command_reply ~verb:v
  | Ok commands   ->
      (* The closed vocabularies a syntax mentions without spelling out: "<kind>" in [add] and
         [ls --kind=], "<action>" in [ls --can=], the actions no per-component menu offers, and
         "<file>" in [log]. Published only by the *whole* listing — [help <verb>] answers about
         one command and nothing else — and read by the Bash completion (episode 10), which would
         otherwise hold a third copy of lists the refusals of [add], [ls] and [log] already name. *)
      let vocabularies =
        match verb with
        | Some _ -> []
        | None   -> [ ("kinds",      jlist (List.map jstr known_kinds));
                      ("actions",    jlist (List.map jstr known_actions));
                      ("beyond_gui", jlist (List.map jstr beyond_gui_actions));
                      ("logs",       jlist (List.map jstr journal_file_names));
                      (* Episode 5 of `journalisation-profonde', 6th application of the same
                         rule: the tables of [switch-info] are named by switch.ml, which knows
                         the vde commands behind them, and published here — nowhere else. *)
                      ("switch_tables",
                         jlist (List.map jstr
                                  Switch.Simulation_level_switch.snapshot_table_names)) ]
      in
      reply_ok ([ ("count",    jint (List.length commands));
                  ("commands", jlist (List.map json_of_command commands)) ] @ vocabularies)

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

(* [None] is the empty line; [Some (Error detail)] a request whose shape is already wrong.

   The bare `--' ends the options, as it does in every Unix tool, and episode 18 is what made it
   necessary: options are recognised WHEREVER they stand in the line (rc-set puts its --field
   after the content), so `exec m1 ls --all' would have handed --all to this parser and the guest
   would have run `ls'. Silently. A command line is the one argument which may legitimately hold
   options meant for somebody else, hence the separator — and the refusal of an unknown option
   (see [exec] in the dispatch), which is what makes the separator discoverable. *)
let parse_request (line:string) : (request, string) result option =
  let tokens = List.filter (fun s -> s <> "") (String.split_on_char ' ' (String.trim line)) in
  match tokens with
  | [] -> None
  | verb :: rest ->
      let is_option t = (String.length t > 2) && (String.sub t 0 2 = "--") in
      (* Everything after the first bare `--' is an argument, whatever it looks like. The
         separator itself is dropped, and a second one is an ordinary argument. *)
      let before, after =
        match List.find_index (fun t -> t = "--") rest with
        | None   -> rest, []
        | Some i -> List.filteri (fun j _ -> j < i) rest,
                    List.filteri (fun j _ -> j > i) rest
      in
      let option_tokens, argument_tokens = List.partition is_option before in
      let argument_tokens = argument_tokens @ after in
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
            (* Exam locks (journalisation-profonde, episode 22). [can] publishes what a *component*
               allows, which is enough for [poweroff] and [del]; it says nothing about the four
               session-wide verbs the exam mode restrains (poweroff-all, new, open, close, quit).
               Published here so that a client learns the mode instead of deducing it from a
               refusal — the same reason § 4.10 gives for publishing the model's predicates. *)
            ("exam",     jbool Initialization.are_we_in_exam_mode);
            (* Episode 18 of marionnet-todo-transverse: the same handle as the one [quit]
               answers with (see there), published before there is anything to quit. A client
               which means to watch this session end should not have to end it first to learn
               what to watch — and when [quit] is refused (exam mode) this is the only source. *)
            ("pid",      jint (Unix.getpid ()));
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

(* Work-stream `migration-marshal-to-text', episode 6. Until `v3 a startup configuration was a
   [Marshal] dump inside its own attribute, and the *bytes* said so: every marshalled value
   starts with one of OCaml's three magic numbers. That form is gone — the model now publishes
   plain scalars (episode 5) — so the recognition moves from the bytes to the *keys*: a startup
   configuration is a pair of attributes "<stem>_active" and "<stem>_file", and a per-service one
   carries two more, "<stem>_selected" and "<stem>_terminal" (one per Quagga tab, router.ml).
   Nothing is listed here either — the stems come from the forest, exactly as the seven Quagga
   keys used to come from the field itself (episode 12 of `pilotage-par-script'). *)
let rc_active_suffix   = "_active"
let rc_file_suffix     = "_file"
let rc_selected_suffix = "_selected"
let rc_terminal_suffix = "_terminal"

(* The stems this component publishes, in the order [#to_tree] wrote them, each with a flag
   saying whether it is a per-service one. *)
let rc_stems (fields : (string * string) list) : (string * bool) list =
  List.filter_map
    (fun (k, _) ->
       if not (String.ends_with ~suffix:rc_active_suffix k) then None else
       let stem = String.sub k 0 ((String.length k) - (String.length rc_active_suffix)) in
       let has suffix = List.mem_assoc (stem ^ suffix) fields in
       if not (has rc_file_suffix) then None else
       Some (stem, (has rc_selected_suffix) && (has rc_terminal_suffix)))
    fields

(* The attributes naming a script file — the ones [set] and [add] must refuse. Writing one is not
   "setting a field": [#eval_forest_attribute] *reads* the file that name designates
   (machine.ml:693), so a rebinding would silently replace the script by the content of another
   file, or by nothing at all. The content is written by rc-set, through the model. *)
let rc_file_fields (fields : (string * string) list) : string list =
  List.map (fun (stem, _) -> stem ^ rc_file_suffix) (rc_stems fields)

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

(* Every attribute is served as a string since episode 5: none of them is a marshalled value any
   more, hence none is served as [null]. *)
let json_of_fields (fields : (string * string) list) : string =
  jobj (List.map (fun (k, v) -> (k, jstr v)) fields)

(* What [get] does not serve, named rather than silently dropped. Empty since episode 5 of
   `migration-marshal-to-text' — nothing is omitted any more — and kept in the answer rather than
   removed from it: a client which reads the field keeps working, and the day a component
   publishes something this channel cannot put on a JSON line, this is where it will be said. *)
let omitted_field_names (_fields : (string * string) list) : string list = []

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
  (* Exam locks (episode 22): why [can_destroy] says no — the state, or the mode. *)
  has_left_traces       : bool;
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
  (* [None] for everything but a machine and a router: the filesystems installed on this host, in
     the GUI combo's order. Read by the guard of episode 5 of `marionnet-todo-transverse' -- the
     model itself still remaps an absent epithet, which is what loading a .mar needs. *)
  installed_distribs_if_any : string list option;
  (* [None] for everything but a machine and a router: the variants installed for the filesystem
     epithet given as argument, in the GUI combo's order. Read by the two guards of episode 7 of
     `marionnet-todo-transverse' -- the model itself still drops an absent variant in silence,
     which is what loading a .mar needs. *)
  variants_of_distrib_if_any : string -> string list option;
  (* [None] for everything but a machine and a router: the memory the filesystem epithet given
     as argument asks for (MEMORY_SUGGESTED_SIZE of its .conf). Read by [add] alone, to give a
     component created here the memory its image needs -- see adjust_memory_to_distrib. *)
  memory_suggested_size_if_any : string -> int option;
  (* The startup configurations this component owns, as (basename, content) pairs, and the way
     to replace one of them (user_level.ml). Since episode 5 of `migration-marshal-to-text' the
     *content* of a script is no longer an attribute of the forest — the forest carries the
     basename of a file of states/ — so these two are the only path rc-get/rc-set have to it.
     Reading that file here instead would be wrong: it does not exist yet on a component just
     added, nor on a project opened from a `v2 .mar, where the content was demarshalled into
     memory at load time. *)
  rc_contents    : (string * string) list;
  set_rc_content : basename:string -> content:string -> bool;
  >

(* Episode 12. The two settings a Quagga tab of the router dialog carries beside the startup
   configuration itself (router.ml:780-870): whether the service is *selected* — selected means
   its .conf file is written at boot, unselected means the existing one is moved aside
   (router.ml:1339-1343), so this is what decides whether the daemon runs at all — and whether
   its telnet terminal is opened. [None] for a plain startup configuration (a machine, a switch,
   the UNIX rc of a router), which has no such neighbours. *)
type rc_service = { selected : bool; terminal : bool }

type component_outcome =
  | Co_added     of string * (string * string) list  (* kind, fields read back after creation *)
  | Co_connected of (string * string) list * bool    (* fields read back, polarity is right *)
  | Co_deleted   of string * string list             (* kind, cables destroyed along with it *)
  (* kind, field, old value, new value, and the fields this write forced along with it
     (field, old, new) — see [adjust_kernel_after_distrib_change] *)
  | Co_set       of string * string * string * string * (string * string * string) list
  | Co_read      of string * (string * string) list  (* kind, fields (all, or the one asked) *)
  (* kind, field, (enabled, content), service settings, the rc vocabulary of this component,
     hostfs *)
  | Co_rc_read   of string * string * (bool * string) * rc_service option * string list
                    * string option
  (* kind, field, before, after (each = the pair plus the service settings), hostfs *)
  | Co_rc_set    of string * string * ((bool * string) * rc_service option)
                    * ((bool * string) * rc_service option) * string option
  | Co_no_project
  | Co_unknown
  | Co_forbidden of string * string                  (* past participle, raw state *)
  (* Exam locks (journalisation-profonde, episode 22): refused because of the *mode*, not because
     of the state — the two must not be confused, [Co_forbidden] would name a state the client
     could hope to leave. *)
  | Co_exam_locked of string                         (* why, in clear *)
  | Co_bad       of string

(* Present only when the target is a service configuration, and then always the four of them:
   a client tests the presence of "selected" to know it is talking to a Quagga tab rather than
   to a plain rc file. [before] is [None] on a read, which serves the two current values only. *)
let rc_service_fields ~(before : rc_service option) ~(after : rc_service option)
  : (string * string) list
  =
  match after with
  | None   -> []
  | Some a ->
      let pair key was now =
        match was with
        | None   -> [ (key, jbool now) ]
        | Some w -> [ (key ^ "_before", jbool w); (key, jbool now) ]
      in
      pair "selected" (Option.map (fun b -> b.selected) before) a.selected
      @ pair "terminal" (Option.map (fun b -> b.terminal) before) a.terminal

let reply_of_component_outcome ~(name:string) : component_outcome -> string = function
  | Co_added (kind, fields) ->
      reply_ok [ ("component", jstr name);
                 ("kind",      jstr kind);
                 ("added",     jbool true);
                 (* Read back from the network, never assumed: try_to_add_* fails silently
                    (machine.ml:545) and the lesson holds for any creation path. *)
                 ("fields",    json_of_fields fields);
                 ("omitted",   jlist (List.map jstr (omitted_field_names fields))) ]
  (* Same shape as [Co_added] — a client adds components and connects them with one reading
     routine — plus the one field a cable has and a node has not. *)
  | Co_connected (fields, correct) ->
      reply_ok [ ("component", jstr name);
                 ("kind",      jstr "cable");
                 ("added",     jbool true);
                 ("fields",    json_of_fields fields);
                 ("omitted",   jlist (List.map jstr (omitted_field_names fields)));
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
                 ("omitted",   jlist (List.map jstr (omitted_field_names fields))) ]
  (* The content travels in clear, on one line: json_escape turns its newlines into \n, which
     is what makes a multi-line shell scenario fit the answer format of this channel. *)
  | Co_rc_read (kind, field, (enabled, content), service, available, hostfs) ->
      reply_ok ([ ("component", jstr name);
                  ("kind",      jstr kind);
                  ("field",     jstr field);
                  ("enabled",   jbool enabled);
                  ("content",   jstr content);
                  ("bytes",     jint (String.length content)) ]
                @ rc_service_fields ~before:None ~after:service
                (* Episode 10's pattern, "publish what the server already knew": the names this
                   component accepts in --field. A completion — and a script that discovers a
                   router instead of assuming one — derives them from here rather than holding a
                   second copy of a vocabulary the model owns. *)
                @ [ ("available", jlist (List.map jstr available));
                    ("hostfs",    jopt hostfs) ])
  (* Sizes, not the old content: a scenario may be long, and the client that wants it back
     asks rc-get. What matters here is *what changed*, and it is read back from the model. *)
  | Co_rc_set (kind, field, ((was_enabled, was), was_service), ((enabled, content), service),
               hostfs) ->
      reply_ok ([ ("component",      jstr name);
                  ("kind",           jstr kind);
                  ("field",          jstr field);
                  ("enabled_before", jbool was_enabled);
                  ("enabled",        jbool enabled);
                  ("old_bytes",      jint (String.length was));
                  ("bytes",          jint (String.length content)) ]
                @ rc_service_fields ~before:was_service ~after:service
                  (* Three dimensions now, and [changed] answers for all of them: a request that
                     only selects a service changes nothing of the content and must not be
                     reported as a no-op. *)
                @ [ ("changed", jbool ((was_enabled, was, was_service)
                                       <> (enabled, content, service)));
                    ("hostfs",  jopt hostfs) ])
  | Co_no_project ->
      reply_error ~code:"no_active_project" ~detail:"no project is open"
  | Co_unknown ->
      reply_error ~code:"unknown_node" ~detail:(Printf.sprintf "no component named %S" name)
  | Co_forbidden (participle, raw) ->
      reply_error ~code:"forbidden_transition"
        ~detail:(Printf.sprintf "%S cannot be %s in state %S"
                   name participle (script_state_of_raw raw))
  | Co_exam_locked detail -> reply_error ~code:"forbidden_in_exam_mode" ~detail
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

(* [Some detail] when the value is a kernel this component's filesystem does not declare,
   or declares but that cannot boot on this host (it would only loop on
   "can't run '/sbin/getty'"). The second case used to pass the guard and be remapped in
   silence by eval_forest_attribute (the remap exists for imports); an explicit write now
   fails loudly instead, naming the bootable alternatives. *)
let unsupported_kernel (c : editable) (value : string) : string option =
  match supported_kernels_and_distrib c with
  | None -> None
  | Some (ks, _) when List.mem value ks ->
      if not (Initialization.uml_kernel_broken_on_this_host value) then None else
      let bootable =
        List.filter
          (fun k -> not (Initialization.uml_kernel_broken_on_this_host k))
          ks
      in
      (match bootable with
       | b :: _ ->
           Some (Printf.sprintf
                   "the kernel %S cannot boot on this host (host kernel %s); the guest would \
                    only loop on \"can't run '/sbin/getty'\". Bootable kernels for this \
                    filesystem: %s"
                   value
                   (match Initialization.host_kernel_version with
                    | Some (a, b) -> Printf.sprintf "%d.%d" a b
                    | None -> "unknown")
                   (String.concat ", " bootable))
       | [] ->
           Some (Printf.sprintf
                   "the kernel %S cannot boot on this host (host kernel %s), and the filesystem \
                    declares no bootable alternative. Update its .conf SUPPORTED_KERNELS to also \
                    accept a modern i386 UML kernel (e.g. '/-i386$/'), or install a matching kernel"
                   value
                   (match Initialization.host_kernel_version with
                    | Some (a, b) -> Printf.sprintf "%d.%d" a b
                    | None -> "unknown")))
  | Some (ks, distrib) ->
      Some (Printf.sprintf
              "the filesystem %S does not support the kernel %S; supported kernels: %s. The GUI \
               dialog offers no other one either (gui_bricks.ml:540-541); a kernel outside this \
               list produces a component that never boots"
              distrib value (String.concat ", " ks))

(* [Some detail] when the value is not the epithet of a filesystem installed here.

   The model does NOT refuse it: [eval_forest_attribute ("distrib", x)] goes through
   [remap_absent_distrib_at_import] (user_level.ml), which exists for the opposite need -- a .mar
   may name a filesystem that is not installed here, and silently switching to a neighbour of the
   same family (with an import warning) beats refusing to open the project. Applied to an explicit
   write it turns a typo into a polite no-op: [set m1 distrib pas-une-distrib] used to answer
   ok:true / changed:false. Hence this guard, symmetrical to [unsupported_kernel] above: the
   channel refuses what it cannot do, and names what it would accept. The remap itself is left
   untouched -- it is right for the import, which is its reason to exist. *)
let unknown_distrib (c : editable) (value : string) : string option =
  match c#installed_distribs_if_any with
  | None | Some [] -> None
  | Some ds when List.mem value ds -> None
  | Some ds ->
      Some (Printf.sprintf
              "no filesystem %S is installed here; installed filesystems: %s. The GUI dialog                offers no other one either (gui_bricks.ml, distribution_choices); the model would                have silently switched to a neighbour of the same family, as it does when loading                a project that names an absent filesystem"
              value (String.concat ", " ds))

(* The filesystem this component sits on, as its forest publishes it. [None] for the kinds
   which have none -- a switch carries no "distrib" attribute at all. *)
let distrib_of (c : editable) : string option =
  List.assoc_opt "distrib" (fields_of_tree c#to_tree)

(* The two values the model reads as "no variant at all" (machine.ml, eval_forest_attribute).
   Both stay acceptable: refusing them would take away the only way to REMOVE a variant. Of the
   two, only "aucune" travels through the channel: a request is split on spaces and the empty
   tokens are dropped ([parse_request] above), so [set m1 variant ""] would carry the two quote
   characters, and [set m1 variant] fails the arity of [set]. Hence the messages below name
   "aucune", the historical word a `v0 .mar may still carry, and not the empty string. *)
let no_variant_values = [""; "aucune"]

(* [Some detail] when the value is not a variant installed for the component's own filesystem.

   The same story as [unknown_distrib] above, one attribute further: [eval_forest_attribute
   ("variant", x)] goes through [remap_absent_variant_at_import] (user_level.ml), written for the
   opposite need -- a variant which disappeared with its filesystem must not make the project
   unloadable, the component simply boots the pristine filesystem, with an import warning.
   Applied to an explicit write it turned [set m1 variant typo] into ok:true / changed:false, and
   [add machine m3 --variant=typo] into a machine whose variant is "". Hence this guard, the
   third of the family (kernel, distrib, variant): the channel refuses what it cannot honour, and
   names what it would accept. The remap itself is left untouched -- it is right for the import,
   which is its reason to exist. Episode 7 of `marionnet-todo-transverse'. *)
let unknown_variant (c : editable) (value : string) : string option =
  if List.mem value no_variant_values then None else
  match distrib_of c with
  | None -> None
  | Some d ->
      (match c#variants_of_distrib_if_any d with
       | None -> None
       | Some vs when List.mem value vs -> None
       | Some [] ->
           Some (Printf.sprintf
                   "no variant is installed for the filesystem %S: the only value it accepts is \
                    %S (no variant). The model would have dropped %S in silence, as it does when \
                    loading a project which names a variant that disappeared"
                   d "aucune" value)
       | Some vs ->
           Some (Printf.sprintf
                   "no variant %S for the filesystem %S; available variants: %s (or %S for no \
                    variant). The GUI dialog offers no other one either; the model would have \
                    dropped it in silence, as it does when loading a project which names a \
                    variant that disappeared"
                   value d (String.concat ", " vs) "aucune"))

(* [Some detail] when changing the filesystem to [value] would take the variant the component
   currently carries away. The GUI never has to answer that question (it locks both combos once
   the device exists, gui_bricks.ml:529-531); the channel can be asked it, and the answer chosen
   here (episode 7) is to refuse, rather than to drop the variant in silence -- which is exactly
   the defect this episode closes, one attribute away. The order is therefore constrained, and
   the message says how to get out of it. *)
let variant_lost_by_distrib_change (c : editable) (value : string) : string option =
  match List.assoc_opt "variant" (fields_of_tree c#to_tree) with
  | None -> None
  | Some v when List.mem v no_variant_values -> None
  | Some v ->
      (match c#variants_of_distrib_if_any value with
       | None -> None
       | Some vs when List.mem v vs -> None
       | Some _ ->
           Some (Printf.sprintf
                   "the component carries the variant %S, which does not exist for the filesystem \
                    %S; remove it first (set <name> variant aucune), then change the filesystem"
                   v value))

(* Called inside the network_change that has just changed "distrib". Returns what it had to
   rewrite, in the (field, old, new) shape of [Co_set]. *)
(* The memory half of the same story, and the reason it exists: the constructor gives every
   machine memory_default = 48 MiB (machine.ml), a number that predates the filesystems we ship
   -- and `--distrib=' may have brought one which asks for four times that. MEASURED on
   2026-09-02: a trixie created through this channel and started dies of OOM
   (`Out of memory: Killed process (systemd-network)') and answers nothing more, which looks
   like a hang. The .conf has always known the number (MEMORY_SUGGESTED_SIZE = 192 there, 24 for
   guignol); until now only the GUI dialog read it, in its on_distrib_change callback
   (machine.ml). Adopting it here is that same callback, for the other creation path.
   ---
   Its name is not `..._after_distrib_change' like its kernel neighbour, and that is the point:
   it applies to the filesystem the component ENDS UP with, whether it came from `--distrib=' or
   from the default the constructor chose -- a plain `add machine' on a host whose default
   filesystem is a trixie would OOM exactly the same.
   ---
   It applies to [add] alone, and only when the caller gave no --memory=: an explicit value is
   an intention, and this channel does not undo intentions. `set <n> distrib' does NOT adopt it
   either -- the GUI does rewrite its memory box on every distribution change, but a script
   which wrote `set m1 memory 512' beforehand must not have it erased in silence. Loading a
   .mar goes through neither, so a saved memory stays sovereign. *)
let adjust_memory_to_distrib (c : editable) : (string * string * string) list =
  let fields = fields_of_tree c#to_tree in
  match List.assoc_opt "distrib" fields, List.assoc_opt "memory" fields with
  | Some distrib, Some current ->
      (match c#memory_suggested_size_if_any distrib with
       | Some suggested when string_of_int suggested <> current ->
           let () = c#eval_forest_attribute ("memory", string_of_int suggested) in
           let now =
             match List.assoc_opt "memory" (fields_of_tree c#to_tree) with
             | Some v -> v
             | None   -> string_of_int suggested
           in
           [ ("memory", current, now) ]
       | _ -> [])
  | _ -> []

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

(* Said once for the two doors of the model: [set <n> port_no N] below, and [add … --ports=N]
   (node_maker). The upper bound is the kind's own, wherever the client knocks, so the sentence
   is too — work-stream marionnet-todo-transverse, episode 4. *)
let too_many_ports ~(kind:string) ~(max:int) : string =
  Printf.sprintf "a %s cannot have more than %d ports" kind max

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
           Co_bad (too_many_ports ~kind ~max:s.st_port_no_max)
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
    | Some _ when List.mem field (rc_file_fields fields) ->
        Co_bad (Printf.sprintf
                  "the field %S names the file holding a startup configuration: writing it would \
                   replace the script by the content of another file. The script itself is \
                   written by rc-set; the neighbouring booleans (%s…) are ordinary fields"
                  field rc_active_suffix)
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
        (* The kernel, filesystem and variant guards come before the write, like every other one
           here: the model would accept the value and the component would simply never boot
           (episode 4f), or would not change at all (episodes 5 and 7 of
           `marionnet-todo-transverse'). *)
        (match (match field with
                | "kernel"  -> unsupported_kernel c value
                | "distrib" ->
                    (* Two refusals under one field: an epithet which is not installed here, and
                       one which is, but whose variants do not include the one the component
                       carries (episode 7). *)
                    (match unknown_distrib c value with
                     | Some _ as refused -> refused
                     | None              -> variant_lost_by_distrib_change c value)
                | "variant" -> unknown_variant c value
                | _         -> None) with
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
    (* Exam locks (episode 22). Two different refusals under one predicate: the state (the
       component is running, and that has always been refused) or the mode (it has run, and
       removing it would take its states, its hostfs and therefore its journals away). Only the
       second is liftable, by --exam-allow-delete, and the message says so — a client told
       "cannot be deleted in state off" would look for a state that does not exist. *)
    if not c#can_destroy then
      (if (not Initialization.are_we_allowed_to_delete) && c#has_left_traces
       then Co_exam_locked
              (Printf.sprintf
                 "%S has already run: removing it in exam mode would throw away its disk states, \
                  its hostfs and its journals. Restart Marionnet with --exam-allow-delete to \
                  allow it."
                 name)
       else Co_forbidden ("deleted", c#state_as_string))
    else
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
       each file (Const.port_no_default: machine 1, hub/switch/router/world_gateway and the
       two bridges 4, cloud 2). Calling the constructor takes that default from where it is
       defined instead of copying seven integers here.
   Cables are not in this list: they need two endpoints and a polarity, which is § 4.5
   (episode 4d-3). *)
let node_maker (st : State.globalState) ~(kind:string) ~(name:string) ~(ports:int option)
  : ((unit -> unit), string) result
  =
  let network = st#network in
  (* [--ports=N] is checked here, against the bounds of the kind, and *before* anything is built
     (work-stream marionnet-todo-transverse, episode 4). Three things make this the right place:
       - the bounds are not a second source of truth: [Const.port_no_min] / [Const.port_no_max]
         are the very values each user_level constructor is given (machine.ml:591, hub.ml:309,
         switch.ml:409, router.ml:1077, world_gateway.ml:384, cloud.ml:269, nat_bridge.ml:769,
         bridge_common.ml:105), and [n#port_no_min] — which [set] reads — only hands them back
         (user_level.ml:984). This branch already reads [Const.port_no_default] from the same
         modules;
       - building first and checking afterwards cannot refuse politely where it matters most:
         --ports=0 on a kind with a ledgrid kills the constructor on an assertion
         (gui/ledgrid.ml:320), so the client would get an Assert_failure instead of a sentence;
       - and nothing is lost by being early: a node which does not exist yet has no cable, so the
         *effective* lower bound [set] uses (network#port_no_lower_of, user_level.ml:2152) is
         exactly [port_no_min] at creation time. *)
  let with_ports ~(min:int) ~(max:int) ~(default:int) (make : port_no:int -> unit) =
    match ports with
    | Some n when n > max -> Error (too_many_ports ~kind ~max)
    | Some n when n < min ->
        (* [set] names three possible reasons for a refusal from below; only one of them can
           apply to a component which does not exist yet: nothing is cabled, and the only
           fixed-size kind (the cloud) does not take --ports at all. *)
        Error (Printf.sprintf
                 "a %s cannot have fewer than %d port(s): this is the minimum of this kind of \
                  component" kind min)
    | _ ->
        let port_no = match ports with Some n -> n | None -> default in
        Ok (fun () -> make ~port_no)
  in
  (* Only the cloud has a fixed number of ports (cloud.ml:268): accepting --ports there
     would be accepting an argument we drop. Both bridges have the ports of their
     integrated switch (episode 10b for the NAT bridge, episode 12 for the LAN one). *)
  let no_ports_here () =
    Error (Printf.sprintf "a %s has a fixed number of ports: --ports does not apply" kind)
  in
  match kind with
  | "machine" ->
      with_ports ~min:Machine.Const.port_no_min ~max:Machine.Const.port_no_max
                 ~default:Machine.Const.port_no_default
        (fun ~port_no -> ignore (new Machine.User_level_machine.machine ~network ~name ~port_no ()))
  | "router" ->
      with_ports ~min:Router.Const.port_no_min ~max:Router.Const.port_no_max
                 ~default:Router.Const.port_no_default
        (fun ~port_no -> ignore (new Router.User_level_router.router ~network ~name ~port_no ()))
  | "switch" ->
      with_ports ~min:Switch.Const.port_no_min ~max:Switch.Const.port_no_max
                 ~default:Switch.Const.port_no_default
        (fun ~port_no -> ignore (new Switch.User_level_switch.switch ~network ~name ~port_no ()))
  | "hub" ->
      with_ports ~min:Hub.Const.port_no_min ~max:Hub.Const.port_no_max
                 ~default:Hub.Const.port_no_default
        (fun ~port_no -> ignore (new Hub.User_level_hub.hub ~network ~name ~port_no ()))
  | "world_gateway" ->
      with_ports ~min:World_gateway.Const.port_no_min ~max:World_gateway.Const.port_no_max
                 ~default:World_gateway.Const.port_no_default
        (fun ~port_no -> ignore (new World_gateway.User_level_world_gateway.world_gateway
                                   ~network ~name ~port_no ()))
  | "cloud" when ports <> None -> no_ports_here ()
  | "cloud" ->
      Ok (fun () -> ignore (new Cloud.User_level_cloud.cloud ~network ~name ()))
  | "world_bridge" ->
      (* The kind is still spelled `world_bridge' in the grammar of this channel,
         and in the .mar files: only what a human reads says "LAN bridge"
         (work-stream modernisation-world-bridge, episode 7b). *)
      with_ports ~min:Bridge_common.Const.port_no_min ~max:Bridge_common.Const.port_no_max
                 ~default:Bridge_common.Const.port_no_default
        (fun ~port_no -> ignore (new Lan_bridge.User_level_lan_bridge.lan_bridge
                                   ~network ~name ~port_no ()))
  | "nat_bridge" ->
      with_ports ~min:Nat_bridge.Const.port_no_min ~max:Nat_bridge.Const.port_no_max
                 ~default:Nat_bridge.Const.port_no_default
        (fun ~port_no -> ignore (new Nat_bridge.User_level_nat_bridge.nat_bridge
                                   ~network ~name ~port_no ()))
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
           let () =
             st#network_change
               (fun () ->
                  try create () with e ->
                    let () = failure := Some e in
                    (* A node registers itself with the network inside its constructor
                       (user_level.ml:1138 and :1231), before the part which raised: without the
                       following, a component the channel refused would stay in [ls], in the
                       saved .mar, and its name taken. [destroy] plays the destroy callbacks
                       registered *so far* (a LIFO, OoExtra.destroy_methods) — exactly what the
                       half-built object got done, and nothing else; the [try] is there because
                       one of them may in turn read a field the exception left unset. Undoing it
                       here, in the same critical section as the creation, is what makes the
                       promise of [rollback] below ("a failed add means an unchanged network")
                       true of the constructor too. *)
                    (match List.find_opt (fun n -> n#get_name = name) (st#network#get_node_list) with
                     | Some n -> (try (n :> editable)#destroy with _ -> ())
                     | None   -> ()))
               ()
           in
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
                          (fun () ->
                             try
                               let () = ignore (adjust_kernel_after_distrib_change component) in
                               (* Only when the caller said nothing about the memory: see the
                                  comment on the function itself. *)
                               if not (List.mem_assoc "memory" extra) then
                                 ignore (adjust_memory_to_distrib component)
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
                  | (k, _) :: _ when List.mem k (rc_file_fields fields) ->
                      rollback (Printf.sprintf
                                  "the field %S names the file holding a startup configuration; \
                                   the script itself is written by rc-set" k)
                  | (k, v) :: rest ->
                      (* Same guards as [set]: a kernel the filesystem does not declare builds a
                         component that never boots (episode 4f), and a filesystem that is not
                         installed would be remapped in silence (episode 5 of
                         `marionnet-todo-transverse'). *)
                      (match (match k with
                              | "kernel"  -> unsupported_kernel component v
                              | "distrib" -> unknown_distrib component v
                              (* Checked against the filesystem just applied, "distrib" coming
                                 first below (episode 7). No cross guard here: the variant is
                                 still empty when "distrib" is written. *)
                              | "variant" -> unknown_variant component v
                              | _         -> None) with
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

   2. The content is no longer in the forest (episode 6 of `migration-marshal-to-text'). The
      flags of a startup configuration are ordinary attributes — "<stem>_active", plus
      "<stem>_selected" and "<stem>_terminal" for a service — while the *content* lives in a file
      of states/ whose basename the forest carries. So these two commands write in two ways, and
      each is the only right one here: the flags through the same uniform
      [#eval_forest_attribute] as [set], the content through [#set_rc_content], the model's own
      field. Neither goes near the file: it does not exist yet on a component just added, nor on
      a project opened from a `v2 .mar, where the content was demarshalled into memory at load
      time. What has not changed is what the client sees: the content still travels in clear, on
      one line, and this file still holds no list of component kinds. *)

(* A scenario is a shell script, not an image. The bound exists so that a mistyped --from does
   not load a filesystem into the project file. *)
let max_rc_bytes = 1024 * 1024

(* The model names a service "quagga_<srv>" (router.ml:1302-1310), but a request has named it
   "zebra", "rip"… since episode 12 of `pilotage-par-script', and a change of storage format is
   no reason to change a vocabulary scripts already use — so the prefix is dropped here. This is
   the one thing this file still knows by name, in the spirit of the two membership fields
   episode 12 had to name; and it is guarded, below: a shortened name another stem already
   answers to is kept whole, since a request must never be ambiguous. *)
let rc_service_prefix = "quagga_"

(* Which startup configuration a request aims at: the stem the forest uses ("rc_config",
   "rc_config_unix", "quagga_zebra"), the name the client uses ("zebra"), and whether it carries
   the two per-service booleans. *)
type rc_target = {
  rc_stem    : string;
  rc_public  : string;
  rc_service : bool;
  }

let rc_targets (fields : (string * string) list) : rc_target list =
  let stems = rc_stems fields in
  let shorten (stem, service) =
    if service && String.starts_with ~prefix:rc_service_prefix stem
    then String.sub stem
           (String.length rc_service_prefix)
           ((String.length stem) - (String.length rc_service_prefix))
    else stem
  in
  List.map
    (fun ((stem, service) as s) ->
       let short = shorten s in
       let public =
         if short = stem then stem else
         if (List.mem_assoc short stems)
            || (List.length (List.filter (fun s' -> shorten s' = short) stems)) > 1
         then stem
         else short
       in
       { rc_stem = stem; rc_public = public; rc_service = service })
    stems

(* Everything a request may name in --field on this component: this is the vocabulary the
   refusals list and [rc-get] publishes. *)
let rc_available (fields : (string * string) list) : string list =
  List.map (fun t -> t.rc_public) (rc_targets fields)

(* A boolean attribute of the forest; [false] when absent or unreadable. The flags of a startup
   configuration are written by the model itself ([string_of_bool], machine.ml:671), so anything
   else would be a forest this binary did not produce. *)
let rc_bool (fields : (string * string) list) ~(key:string) : bool =
  match List.assoc_opt key fields with
  | Some v -> (try bool_of_string v with _ -> false)
  | None   -> false

(* The basename of the file holding the script: what the forest publishes, and the address
   [#set_rc_content] answers to. *)
let rc_basename_of ~(target : rc_target) (fields : (string * string) list) : string option =
  List.assoc_opt (target.rc_stem ^ rc_file_suffix) fields

(* The state both commands read back from the model rather than from what they asked: the pair
   (enabled, content), and the two booleans of a service. The content comes from [#rc_contents],
   the forest holding only the basename which indexes it — an unknown basename yields the empty
   string, which is exactly what a fresh component would carry. *)
let rc_state_of ~(target : rc_target) ~(contents : (string * string) list)
    (fields : (string * string) list) : (bool * string) * rc_service option
  =
  let enabled = rc_bool fields ~key:(target.rc_stem ^ rc_active_suffix) in
  let content =
    match rc_basename_of ~target fields with
    | None          -> ""
    | Some basename -> (match List.assoc_opt basename contents with Some c -> c | None -> "")
  in
  let service =
    if not target.rc_service then None else
    Some { selected = rc_bool fields ~key:(target.rc_stem ^ rc_selected_suffix);
           terminal = rc_bool fields ~key:(target.rc_stem ^ rc_terminal_suffix) }
  in
  ((enabled, content), service)

(* Naming the field stays optional, and keeps meaning exactly what it meant before episode 12:
   the implicit choice considers the *plain* targets only, so [rc-set m1 …] still writes the one
   configuration a machine or a switch has, and [rc-set r1 …] still writes the UNIX rc of a
   router rather than becoming ambiguous the day the router gained seven more. A Quagga
   configuration is reached by naming it — under its short name or under its stem, both being
   unambiguous. The answers below are all the cases, and none of them is a silence; every refusal
   ends by listing the vocabulary that would have worked, which is the same list [rc-get]
   publishes. *)
let rc_target_of ~(kind:string) ~(name:string) ~(field:string option)
    (fields : (string * string) list) : (rc_target, string) result
  =
  let targets = rc_targets fields in
  let vocabulary () = String.concat ", " (List.map (fun t -> t.rc_public) targets) in
  let with_vocabulary () =
    match targets with [] -> "" | _ -> Printf.sprintf "; here they are: %s" (vocabulary ())
  in
  match field with
  | None ->
      (match List.filter (fun t -> not t.rc_service) targets with
       | [ t ] -> Ok t
       | []    ->
           Error (Printf.sprintf
                    "%S (kind %s) has no startup configuration: today a machine, a switch and a \
                     router have one%s" name kind (with_vocabulary ()))
       | several ->
           Error (Printf.sprintf
                    "%S (kind %s) has several startup configuration fields (%s): name the one \
                     you mean" name kind
                    (String.concat ", " (List.map (fun t -> t.rc_public) several))))
  | Some f ->
      (match List.find_opt (fun t -> t.rc_public = f || t.rc_stem = f) targets with
       | Some t -> Ok t
       | None ->
           (match List.assoc_opt f fields with
            | None ->
                Error (Printf.sprintf
                         "no startup configuration %S on %S (kind %s)%s"
                         f name kind (with_vocabulary ()))
            | Some _ ->
                (* The name is a field of the forest, just not one of ours: since episode 6 a
                   startup configuration is recognized by its pair of keys, so saying which one
                   is missing says more than "it is not one". *)
                Error (Printf.sprintf
                         "the field %S is not a startup configuration (no %S beside it)%s"
                         f (f ^ rc_file_suffix) (with_vocabulary ()))))

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
    let fields = fields_of_tree c#to_tree in
    match rc_target_of ~kind ~name ~field fields with
    | Error detail  -> Co_bad detail
    | Ok target ->
        let (rc, service) = rc_state_of ~target ~contents:(c#rc_contents) fields in
        Co_rc_read (kind, target.rc_public, rc, service, rc_available fields,
                    c#hostfs_directory_if_any))

let cmd_rc_set (st : State.globalState) ~(timeout:float) ~(name:string) ~(field:string option)
    ~(from:string option) ~(inline:string option) ~(enable:bool option)
    ~(select:bool option) ~(terminal:bool option) : string
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
    | None when enable = None && select = None && terminal = None ->
        Error "nothing to do: give a content (--from=<file> or an inline one) or a flag \
               (--enable|--disable, --select|--unselect, --terminal|--no-terminal)"
    | None        -> Ok None
    | Some c as x -> Result.map (fun () -> x) (rc_content_is_servable c)
  in
  match asked_content with
  | Error detail -> reply_error ~code:"bad_argument" ~detail
  | Ok content ->
  with_component st ~timeout ~name ~f:(fun ~kind ~structural:_ c ->
    let fields = fields_of_tree c#to_tree in
    match rc_target_of ~kind ~name ~field fields with
    | Error detail -> Co_bad detail
    | Ok target ->
        let ((before_rc, before_service) as before) =
          rc_state_of ~target ~contents:(c#rc_contents) fields
        in
        (* The two flags of episode 12 apply to a service, and the shape says which targets are
           one: a plain configuration has no such neighbours to write. *)
        if (not target.rc_service) && (select <> None || terminal <> None) then
          Co_bad (Printf.sprintf
                    "--select/--unselect and --terminal/--no-terminal apply to a service startup \
                     configuration (a Quagga tab of a router); %S is a plain one" target.rc_public)
        else
        (* The same guard the GUI dialog obeys — and here it is more than a rule: the field is
           read when the device is built, so writing it on a running component would change
           nothing the client could observe until the next start. *)
        if not c#can_modify then Co_forbidden ("modified", c#state_as_string) else
        let (was_enabled, was_content) = before_rc in
        let new_content = match content with Some s -> s | None -> was_content in
        (* Posting a scenario enables it, unless --disable says otherwise: a content that would
           silently never run is the surprise this channel exists to avoid. The flag alone
           leaves the content untouched. *)
        let new_enabled =
          match enable with
          | Some b -> b
          | None   -> (match content with Some _ -> true | None -> was_enabled)
        in
        (* Episode 12 applies the very same rule to the second switch a Quagga tab has: posting a
           content *selects* the service too, unless --unselect says otherwise. An unselected
           service does not even get its file — the boot moves the existing .conf aside
           (router.ml:1339-1343) — so a posted configuration would silently go nowhere. *)
        let after_service =
          match before_service with
          | None   -> None
          | Some s ->
              Some { selected = (match select with
                                 | Some b -> b
                                 | None   -> (match content with
                                              | Some _ -> true
                                              | None   -> s.selected));
                     terminal = (match terminal with Some b -> b | None -> s.terminal) }
        in
        (* One write per thing that really changes, and all of them in the same GTK slot. A no-op
           costs no write at all: network_change marks the project as modified and redraws the
           sketch (state.ml:892-903). The booleans are ordinary attributes since episode 5, so
           the canonical order of the two membership lists is no longer rebuilt here: the model
           keeps it itself, one service at a time (router.ml, update_quagga_membership). *)
        let flag key was now = if was = now then [] else [ (target.rc_stem ^ key,
                                                            string_of_bool now) ] in
        let writes =
          (flag rc_active_suffix was_enabled new_enabled)
          @ (match before_service, after_service with
             | Some b, Some a ->
                 (flag rc_selected_suffix b.selected a.selected)
                 @ (flag rc_terminal_suffix b.terminal a.terminal)
             | _ -> [])
        in
        (* The content does not travel as an attribute: it lives in a file of states/ since
           episode 5, and the model owns it. A basename the component does not know would mean
           this server and that model disagree about the forest — said, never swallowed. *)
        let content_write =
          if new_content = was_content then None else rc_basename_of ~target fields
        in
        if writes = [] && content_write = None then
          Co_rc_set (kind, target.rc_public, before, before, c#hostfs_directory_if_any)
        else
        let failure = ref None in
        let () =
          st#network_change
            (fun () ->
               try
                 let () = List.iter (fun attribute -> c#eval_forest_attribute attribute) writes in
                 match content_write with
                 | None          -> ()
                 | Some basename ->
                     if not (c#set_rc_content ~basename ~content:new_content) then
                       failure :=
                         Some (Failure (Printf.sprintf
                                          "the component does not own the file %S the forest \
                                           attributes to it" basename))
               with e -> failure := Some e)
            ()
        in
        (match !failure with
         | Some e ->
             Co_bad (Printf.sprintf "the model refused the startup configuration %S: %s"
                       target.rc_public (Printexc.to_string e))
         | None ->
             (* Read back, never assumed — the rule this file follows everywhere. *)
             let after =
               rc_state_of ~target ~contents:(c#rc_contents) (fields_of_tree c#to_tree)
             in
             Co_rc_set (kind, target.rc_public, before, after, c#hostfs_directory_if_any)))

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

(* Exam locks (journalisation-profonde, episode 22). Answering [Tr_forbidden] here would blame
   the state ("m1 cannot poweroff from state on"), which is false and sends a script looking for
   a state that would work — there is none. The refusal names the mode, and names the gesture
   which does work: the exam copy is archived by the *graceful* shutdown only (machine.ml,
   router.ml), so [stop] and [shutdown-all] are the way out. *)
let exam_refusal_of_action (action:string) : string option =
  match action with
  | "poweroff" | "poweroff-all" when not Initialization.are_we_allowed_to_poweroff ->
      Some (Printf.sprintf
              "%S is refused in exam mode: an ungraceful power cut would throw away the session \
               report, the command history and the recorded consoles, which are archived by the \
               graceful shutdown only. Use \"stop\" (or \"shutdown-all\") instead."
              action)
  | _ -> None

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
  match exam_refusal_of_action action with
  | Some detail -> reply_error ~code:"forbidden_in_exam_mode" ~detail
  | None ->
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
  match exam_refusal_of_action action with
  | Some detail -> reply_error ~code:"forbidden_in_exam_mode" ~detail
  | None ->
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
     *previous* run is ignored by two conditions, and it takes both (work-stream
     `marionnet-todo-transverse', episode 10): the component must BE RUNNING, and the marker
     must be newer than <hostfs>/boot_parameters.

     The second alone used to be the whole guard, on the strength of "boot_parameters is
     rewritten at every startup". That is true — [make_hostfs_content] runs from the
     initializer of [uml_process], and a machine or a router destroys its simulated device
     when it is powered off (machine.ml, router.ml: the next start must use a new cow file),
     so a new [uml_process] is built, and a new boot_parameters written, at every start. What
     the reasoning missed is WHEN: [start] only *queues* the startup on the task runner and
     answers immediately, so between that answer and the rewrite there is a window in which
     the hostfs still holds the pair of the PREVIOUS boot -- two files equally stale, hence a
     comparison which holds, hence `ready: true' in 50 ms on a guest which is not even
     launched. Measured: `start' then `--ready' answered in 0.050s on the previous marker
     while [wait --state=on] was still timing out.

     Requiring the state closes that window at its source rather than by luck of the clock:
     [startup_right_now] (user_level.ml) writes boot_parameters -- through
     [create_right_now] -- BEFORE it sets the state to On, so "on" already implies "the
     boot_parameters of the boot now under way". A component which is off, sleeping or gone
     is not ready, whatever it left on the disk.

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
  | Rp_not_running of string * bool               (* state, and whether it ever booted here *)
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

(* Where the guest of [name] writes and in which state Marionnet holds it: [None] if no component
   bears that name, [Some (None, _)] if it bears it but runs no guest of its own (a switch, a hub,
   a cable), [Some (Some dir, state)] otherwise. Reads the network, hence the GTK slot — and
   *only* this: the observation itself ([stat], [open_in]) is I/O and belongs to the calling
   thread. The state travels with the directory because [wait --ready] needs both in the same
   glance: asking twice would leave exactly the window this pair was made to close (episode 10). *)
let find_hostfs (st : State.globalState) ~(name:string) : (string option * string) option =
  match List.find_opt (fun n -> n#get_name = name) (st#network#get_node_list) with
  | Some n -> Some (n#hostfs_directory_if_any, script_state_of_raw n#state_as_string)
  | None ->
  match List.find_opt (fun c -> c#get_name = name) (st#network#get_cable_list) with
  | Some c -> Some (None, script_state_of_raw c#state_as_string)
  | None   -> None

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
    match ask ~timeout:gtk_timeout (fun () -> find_hostfs st ~name) with
    | Failed e         -> Failed e
    | Timed_out t      -> Timed_out t
    | Done None               -> Done (Rp_gone)
    | Done (Some (None, _))   -> Done (Rp_no_hostfs)
    (* Not running: no file on the disk may say otherwise. This is the half of the guard which
       does not depend on any clock — see the comment above the marker's name. The [stat] tells
       apart the two ways of not running, which call for two different fixes on the caller's
       side: never started at all, or started and stopped since. *)
    | Done (Some (Some dir, state)) when state <> "on" ->
        let ever_booted =
          mtime_of_regular_file (Filename.concat dir boot_parameters_basename) <> None
        in
        Done (Rp_not_running (state, ever_booted))
    | Done (Some (Some dir, _)) ->
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
    ~reached:(function Rp_waiting _ | Rp_not_running _ -> false | _ -> true)
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
       | Rp_waiting _ | Rp_not_running _ -> assert false (* [reached] said otherwise *))
    ~on_expiry:(fun v elapsed ->
       let detail =
         match v with
         (* Since episode 10 this is the defensive branch, not the ordinary one: a component
            with no boot_parameters is not "on", so it is caught above, with the state in hand.
            Kept because the two conditions are checked at two different moments -- the state in
            the GTK slot, the file in this thread -- and nothing forbids the interval. *)
         | Rp_waiting (_, None) ->
             Printf.sprintf
               "%S has no %s in its hostfs directory, hence nothing could have written %s \
                (%.1fs waited)"
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
         (* Episode 10 of `marionnet-todo-transverse'. Says the state, because that is the whole
            answer: what a stopped component left in its hostfs proves nothing about a boot which
            is not running. A script which sent [start] and lands here sent it to something which
            never came up -- and [start] answers before the startup is even attempted. *)
         | Rp_not_running (state, false) ->
             Printf.sprintf
               "%S has not been started since this project was opened (it is %S, and its hostfs \
                directory holds no %s), hence nothing could have written %s (%.1fs waited)"
               name state boot_parameters_basename ready_marker_basename elapsed
         | Rp_not_running (state, true) ->
             Printf.sprintf
               "%S is %S, not \"on\": --ready reports on the guest of a RUNNING component, and \
                what a stopped one left in its hostfs directory says nothing about a boot under \
                way. Start it (and remember that start answers before the startup is done) \
                (%.1fs waited)"
               name state elapsed
         | _ -> assert false (* [reached] said otherwise *)
       in
       reply_error ~code:"timeout" ~detail)

(* --- log: the journals of a guest, and the switch's one ------------- *)

(* Episode 3 of `journalisation-profonde'. The sibling of [wait --ready]: that one waits for the
   signal the guest writes, this one serves what it *wrote*. Since episodes 1 and 2 every machine
   and every router leaves two files in its hostfs directory, written by the prologue and the
   epilogue Marionnet drops there at every start (bin/scripts/marionnet-relay.00-journal.sh and
   marionnet-relay.zz-journal.sh, deposited by make_hostfs_content):

     rc_config.log  what *the scenario* did, and what failed in it (the trace and the status);
     boot.log       what the boot did before the relay was reached (dmesg, and the services).

   The basenames belong to those two scripts (__mrn_journal_log, __mrn_journal_boot_log). They are
   named once, with the other closed vocabularies, above [cmd_help] — which publishes them.

   Episode 4 added a third writer, and it is not a guest: a switch's rc is a set of commands sent
   to vde_switch over its management socket, and Marionnet, who sends them, is the only one in a
   position to write down what came back. Hence a source which is a *file* and not a directory,
   and a component which has [rc_config] but no [boot] — see [journal_source] below.

   Two bounds, and they are not the same bound. The line one is the answer's: 400 is the order of
   magnitude the collector already imposes on itself (dmesg 400, journalctl 500), so a whole
   journal normally passes untouched. The byte one is the *reader's*: the file is written by a
   guest, hence by nobody we control, and a scenario looping on an error can make it as large as
   it likes. Reading only the tail keeps this thread's memory bounded whatever the guest did. *)
let max_journal_lines = 400
let max_journal_bytes = 2 * 1024 * 1024

type journal_read = {
  jr_content   : string;  (* the lines served, newline-terminated as [tail] would leave them *)
  jr_lines     : int;     (* how many were served *)
  jr_total     : int;     (* how many were read, and could be served, from the file *)
  jr_dropped   : int;     (* lines this channel could not carry (see below) *)
  jr_truncated : bool;    (* the file held more than what is served *)
  jr_bytes     : int;     (* the file itself, as the channel found it *)
  jr_mtime     : float;
  }

(* A line the guest wrote in something which is not UTF-8 is *dropped and counted*, not served:
   the answer is one JSON line (the reason of [rc_content_is_servable] and of [first_line_of]).
   Counting it matters more than it looks — a journal silently missing a line would be worse than
   one which says how many it could not carry. *)
let read_journal_tail ~(path:string) ~(tail:int) : (journal_read, string) result =
  let stat = try Some (Unix.stat path) with _ -> None in
  match stat with
  | None -> Error "not found"
  | Some s when s.Unix.st_kind <> Unix.S_REG ->
      Error (Printf.sprintf "%S is not a regular file" path)
  | Some s ->
      let read () =
        let ic = open_in_bin path in
        Fun.protect ~finally:(fun () -> close_in_noerr ic)
          (fun () ->
             let len     = in_channel_length ic in
             let skipped = max 0 (len - max_journal_bytes) in
             let ()      = seek_in ic skipped in
             (len, skipped > 0, really_input_string ic (len - skipped)))
      in
      (match (try Some (read ()) with _ -> None) with
       | None -> Error (Printf.sprintf "%S could not be read" path)
       | Some (len, skipped, raw) ->
           let lines = String.split_on_char '\n' raw in
           (* The last element of the split is what follows the final newline: empty on a file
              which ends with one, which is what a journal does. The first is a *partial* line
              when we started in the middle of the file: dropped, for the same reason its bytes
              were. *)
           let lines =
             match List.rev lines with "" :: rest -> List.rev rest | _ -> lines in
           let lines = match skipped, lines with true, _ :: rest -> rest | _, l -> l in
           let (kept, unservable) = List.partition String.is_valid_utf_8 lines in
           let total  = List.length kept in
           let served =
             if total <= tail then kept
             else List.filteri (fun i _ -> i >= total - tail) kept
           in
           let content =
             match served with [] -> "" | _ -> String.concat "\n" served ^ "\n" in
           Ok { jr_content   = content;
                jr_lines     = List.length served;
                jr_total     = total;
                jr_dropped   = List.length unservable;
                jr_truncated = skipped || total > tail;
                jr_bytes     = len;
                jr_mtime     = s.Unix.st_mtime })

let journal_file_of (file : string option) : (string * string, string) result =
  let key = match file with None -> default_journal_file | Some f -> f in
  match List.assoc_opt key journal_files with
  | Some basename -> Ok (key, basename)
  | None ->
      Error (Printf.sprintf
               "no journal named %S; this channel serves %s — the files a guest writes in its \
                hostfs directory (the first of which a switch has too), and the two Marionnet \
                records host-side for a guest, its console and its terminal session (help \
                publishes them as \"logs\")"
               key (String.concat ", " journal_file_names))

let journal_tail_of (tail : string option) : (int, string) result =
  match tail with
  | None   -> Ok max_journal_lines
  | Some s ->
      (match int_of_string_opt s with
       | Some n when n > 0 -> Ok n
       | _ -> Error (Printf.sprintf "--tail expects a positive number of lines, got %S" s))

(* Where the journals of a component are to be found. The answer has broadened twice. Until
   episode 4 a journal was necessarily a *guest's*, hence a pair of files in a hostfs directory;
   a switch has no guest, but Marionnet writes down what it said to vde_switch and what came back
   — one file, in the project's working directory (switch.ml, [rc_journal_path]). Episode 6 then
   gave a guest a *third* file, of a third nature: its console, recorded by Marionnet, again in
   the project's working directory (simulation_level.ml, [console_journal_path]).

   Hence a list rather than a sum: what a component serves is now a property of the component,
   and the same code answers "this one has three, that one has one, this other none". Each entry
   also carries the sentence to say when the file is not there yet, because that sentence is
   what tells a script whether to wait, to start something, or to restart Marionnet — and it is
   never the same one twice.

   Reads the network, hence the GTK slot, and only that: the reading itself belongs to the
   calling thread, exactly as in [find_hostfs]. *)
type journal_entry = {
  jn_key     : string;  (* the name a script uses: rc_config, boot, console *)
  jn_path    : string;
  jn_missing : string;  (* why it is not there yet, in this component's own terms *)
}

type component_journals = {
  cj_entries : journal_entry list;
  cj_note    : string;  (* what this component is, so that a refusal makes sense *)
}

let journals_of (st : State.globalState) ~(name:string) : component_journals option =
  let working_directory = st#network#project_working_directory in
  (* The console is Marionnet's to write, so the channel knows where it is without asking the
     component: the path is a function of the project and of the name (episode 6). Whether the
     file exists is another matter — and the session may simply not be recording. *)
  let console_entry () =
    { jn_key  = "console";
      jn_path = Simulation_level.console_journal_path ~working_directory ~name;
      jn_missing =
        if Initialization.are_we_recording_consoles then
          "it has not been started since this project was opened"
        else
          "this session does not record consoles: restart Marionnet with --console-log \
           (implied by --exam)" }
  in
  (* Same shape, a different stream and a third reason to be missing: a guest whose terminal is
     not the one the UML kernel opens (an Xnest, or no console at all) has nothing to record —
     the channel says so rather than promising a file that will never come (episode 8). *)
  let terminal_entry () =
    { jn_key  = "terminal";
      jn_path = Simulation_level.terminal_journal_path ~working_directory ~name;
      jn_missing =
        if Initialization.are_we_recording_terminals then
          "it has not been started since this project was opened, or its console is not the one \
           the UML kernel opens (an Xnest, or a terminal set to none)"
        else
          "this session does not record terminals: restart Marionnet with --terminal-log \
           (implied by --exam)" }
  in
  (* One sentence per journal, and they do not say the same thing: the two written by the relay
     mean "wait for the boot", whereas [commands] means "nobody has typed anything yet" — a
     machine can be perfectly ready and have no command history at all (episode 7). *)
  let hostfs_entries dir =
    List.filter_map
      (fun (key, basename) ->
         if List.mem key host_side_journals then None else
         Some { jn_key  = key;
                jn_path = Filename.concat dir basename;
                jn_missing =
                  (if key = "commands" then
                     "no interactive shell of this guest has typed a command yet: the history is \
                      appended at every prompt, so it appears with the first one"
                   else if key = "report" then
                     (* The only one of the six nobody writes on its own: it exists because it was
                        asked for, hence a sentence which names the verb rather than a wait. *)
                     "nobody has asked this guest for its state yet: run report on it, or let it \
                      shut down gracefully — the same producer also runs at the end of a session"
                   else if key = "exec" then
                     (* Same nature as [report] — nothing writes it until the channel is asked to
                        — and the sentence says the one thing this journal proves: that it is
                        empty because *nobody used the channel to run anything here*. *)
                     "nothing has been run in this guest through the channel: this journal is \
                      written by exec, and by nothing else"
                   else
                     "it has not been started since this project was opened, or its guest has not \
                      reached the end of its boot — see wait --ready") })
      journal_files
  in
  match List.find_opt (fun n -> n#get_name = name) (st#network#get_node_list) with
  | Some n ->
      (match n#hostfs_directory_if_any, n#rc_journal_file_if_any with
       | Some dir, _ ->
           Some { cj_entries = hostfs_entries dir @ [ console_entry (); terminal_entry () ];
                  cj_note    = "a machine or a router serves the files its guest writes in its \
                                hostfs directory, plus the console and the terminal session \
                                Marionnet records for it" }
       | None, Some file ->
           Some { cj_entries =
                    [ { jn_key  = default_journal_file;
                        jn_path = file;
                        jn_missing =
                          "it has not been started since this project was opened" } ];
                  cj_note    = "a switch runs no guest system of its own: it boots nothing and \
                                has no console, so the only journal it has is what Marionnet \
                                sent to vde_switch as a startup configuration, and what \
                                vde_switch answered" }
       | None, None ->
           Some { cj_entries = [];
                  cj_note    = "it runs no guest system of its own and has no startup \
                                configuration either, hence no journal at all: log applies to a \
                                machine, a router or a switch" })
  | None ->
  match List.find_opt (fun c -> c#get_name = name) (st#network#get_cable_list) with
  | Some _ ->
      Some { cj_entries = [];
             cj_note    = "a cable runs no process of its own, hence writes no journal: log \
                           applies to a machine, a router or a switch" }
  | None -> None

(* The reading and the answer, shared by the two kinds of source: what differs between them is
   the path, the vocabulary the component actually has, and what to do when the file is not there
   yet — for a guest, waiting is the normal case, hence the pointer to [wait --ready]. *)
let serve_journal ~(name:string) ~(key:string) ~(path:string) ~(tail:int)
                  ~(available:string list) ~(not_found_detail:string) : string
  =
  match read_journal_tail ~path ~tail with
  | Error "not found" -> reply_error ~code:"bad_argument" ~detail:not_found_detail
  | Error detail      -> reply_error ~code:"bad_argument" ~detail
  | Ok r ->
      reply_ok [ ("component",     jstr name);
                 ("file",          jstr key);
                 ("path",          jstr path);
                 (* In clear, on one line: json_escape turns the newlines into \n,
                    exactly as it does for the content of rc-get. *)
                 ("content",       jstr r.jr_content);
                 ("lines",         jint r.jr_lines);
                 ("total_lines",   jint r.jr_total);
                 ("dropped_lines", jint r.jr_dropped);
                 ("truncated",     jbool r.jr_truncated);
                 ("bytes",         jint (String.length r.jr_content));
                 ("file_bytes",    jint r.jr_bytes);
                 ("mtime",         jfloat r.jr_mtime);
                 (* Episode 10's pattern again: the vocabulary of --file, published by the answer
                    as well as by help — and, since episode 4, the vocabulary of *this*
                    component, which is not the same for a switch as for a guest. *)
                 ("available",     jlist (List.map jstr available)) ]

let cmd_log (st : State.globalState) ~(timeout:float) ~(name:string) ~(file:string option)
            ~(tail:string option) : string
  =
  if name = "" then
    reply_error ~code:"bad_argument" ~detail:"log expects the name of a component"
  else
  match journal_file_of file with
  | Error detail -> reply_error ~code:"bad_argument" ~detail
  | Ok (key, _basename) ->
  match journal_tail_of tail with
  | Error detail -> reply_error ~code:"bad_argument" ~detail
  | Ok tail ->
      (* The GTK slot buys the location and nothing else; the reading happens here, in this
         thread, like the [stat] of [wait --ready]. *)
      reply_of_outcome
        (function
         | None ->
             reply_error ~code:"unknown_node" ~detail:(Printf.sprintf "no component named %S" name)
         | Some { cj_entries = []; cj_note } ->
             reply_error ~code:"bad_argument"
               ~detail:(Printf.sprintf "%S %s" name cj_note)
         | Some { cj_entries; cj_note } ->
             let available = List.map (fun e -> e.jn_key) cj_entries in
             (match List.find_opt (fun e -> e.jn_key = key) cj_entries with
              | None ->
                  (* The name exists in the channel's vocabulary, but not for *this* component. *)
                  reply_error ~code:"bad_argument"
                    ~detail:(Printf.sprintf
                               "%S has no journal named %S: %s (it serves %s)"
                               name key cj_note (String.concat ", " available))
              | Some e ->
                  serve_journal ~name ~key ~path:e.jn_path ~tail ~available
                    ~not_found_detail:
                      (Printf.sprintf "%S has written no %s journal yet (%s): %s"
                         name key e.jn_path e.jn_missing)))
        (ask ~timeout (fun () -> journals_of st ~name))

(* --- switch-info: what a switch knows *now* ---------------------- *)

(* Episode 5 of `journalisation-profonde'. The verb next to [log], and its opposite: [log] serves
   what was *written* — a file, which outlives the component — while this one asks what the
   switch *knows*, which exists only inside a running vde_switch and is written down nowhere.
   Hence a component which has both (a switch answers [log] after its poweroff, and [switch-info]
   only before it), and hence the refusal below naming the other verb when the switch is down.

   Spelled like [log] and [rc-get] — the table positionally *or* through an option — because it
   is the same gesture: naming one of the few things a component keeps beside its fields. The
   names of the tables, and the vde commands behind them, belong to switch.ml: this file renders
   JSON, it does not know what a hash table looks like. *)
let switch_tables_of (table : string option) : (string list, string) result =
  let known = Switch.Simulation_level_switch.snapshot_table_names in
  match table with
  (* No table named: all of them, in one round trip. Asking a running switch four questions
     costs four lines on a socket, and a script which wants "everything about sw1" — the first
     thing an agent asks — would otherwise have to know the list to loop over it. *)
  | None -> Ok known
  | Some t when List.mem t known -> Ok [ t ]
  | Some t ->
      Error (Printf.sprintf
               "no table named %S; a switch answers about %s (help publishes them as \
                \"switch_tables\")" t (String.concat ", " known))

(* What [switch-info] is aiming at, as the GTK slot finds it. Four cases and not two, because
   the three ways of failing are three different pieces of news for the script which is going to
   read them — the criterion of this work-stream since episode 3. *)
type switch_target =
  | Sw_absent                (* no component of that name at all *)
  | Sw_other  of string      (* a component, but not a switch: its kind *)
  | Sw_idle   of string      (* a switch which cannot answer: its state, in script words *)
  | Sw_socket of string      (* a running switch: the path of its management socket *)

let find_switch (st : State.globalState) ~(name:string) : switch_target =
  match List.find_opt (fun n -> n#get_name = name) (st#network#get_node_list) with
  | Some n when n#string_of_devkind <> "switch" -> Sw_other n#string_of_devkind
  | Some n ->
      (match n#management_socket_if_running with
       | Some socketfile -> Sw_socket socketfile
       | None            -> Sw_idle (script_state_of_raw n#state_as_string))
  | None ->
  match List.find_opt (fun c -> c#get_name = name) (st#network#get_cable_list) with
  | Some _ -> Sw_other "cable"
  | None   -> Sw_absent

let rec json_of_vde_value (v : Switch.Simulation_level_switch.vde_value) : string =
  let open Switch.Simulation_level_switch in
  match v with
  | Vstr  s  -> jstr s
  | Vint  i  -> jint i
  | Vbool b  -> jbool b
  | Vobj  fs -> jobj  (List.map (fun (k, v) -> (k, json_of_vde_value v)) fs)
  | Vlist l  -> jlist (List.map json_of_vde_value l)

(* Both halves of what the switch answered: [entries] for a script which knows what it wants
   (jq selects a MAC by its address), [lines] because they are the switch's own words and no
   parser of ours is a reason to lose them. A table which the switch refused carries its code
   and its message, and no entries at all — see [ask_vde_switch_snapshot]. *)
let json_of_vde_table (t : Switch.Simulation_level_switch.vde_table) : string =
  let open Switch.Simulation_level_switch in
  jobj [ ("name",    jstr t.vt_name);
         ("command", jstr t.vt_command);
         ("ok",      jbool (t.vt_code = 1000));
         ("code",    jint t.vt_code);
         ("message", jstr t.vt_message);
         ("count",   jint (List.length t.vt_entries));
         ("entries", jlist (List.map
                              (fun row -> jobj (List.map
                                                  (fun (k, v) -> (k, json_of_vde_value v)) row))
                              t.vt_entries));
         ("lines",   jlist (List.map jstr t.vt_lines)) ]

let cmd_switch_info (st : State.globalState) ~(timeout:float) ~(name:string)
                    ~(table:string option) : string
  =
  if name = "" then
    reply_error ~code:"bad_argument" ~detail:"switch-info expects the name of a switch"
  else
  match switch_tables_of table with
  | Error detail -> reply_error ~code:"bad_argument" ~detail
  | Ok tables ->
      (* The GTK slot buys the location, and only that: the exchange with vde_switch happens in
         this thread, exactly as the reading of a journal does. It has to — four commands, each
         of which may wait up to the receive timeout, is not something to run in the thread which
         draws the network. *)
      reply_of_outcome
        (function
         | Sw_absent ->
             reply_error ~code:"unknown_node" ~detail:(Printf.sprintf "no component named %S" name)
         | Sw_other kind ->
             reply_error ~code:"bad_argument"
               ~detail:(Printf.sprintf
                          "%S is a %s: switch-info applies to a switch, the only kind Marionnet \
                           gives a management socket — a hub runs the very same vde_switch \
                           without one, and a machine or a router answers by writing (see log)"
                          name kind)
         | Sw_idle state ->
             reply_error ~code:"bad_argument"
               ~detail:(Printf.sprintf
                          "%S is %s: these tables are the memory of a running vde_switch and \
                           exist nowhere else — start it (or resume it) and ask again. What it \
                           did say at startup outlives it, though: see log %s" name state name)
         | Sw_socket socketfile ->
             (match Switch.Simulation_level_switch.ask_vde_switch_snapshot ~socketfile ~tables with
              | Error (Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.ETIMEDOUT), _, _)) ->
                  reply_error ~code:"timeout"
                    ~detail:(Printf.sprintf
                               "%S did not answer on its management socket (%s) within %.1fs"
                               name socketfile
                               Switch.Simulation_level_switch.vde_answer_timeout)
              | Error e ->
                  reply_error ~code:"internal"
                    ~detail:(Printf.sprintf "the exchange with the vde_switch of %S (%s) failed: %s"
                               name socketfile (Printexc.to_string e))
              | Ok answered ->
                  reply_ok [ ("component", jstr name);
                             ("socket",    jstr socketfile);
                             ("tables",    jlist (List.map json_of_vde_table answered));
                             (* The vocabulary of this component, as [log] publishes its own. *)
                             ("available", jlist (List.map jstr
                                                    Switch.Simulation_level_switch.snapshot_table_names)) ]))
        (ask ~timeout (fun () -> find_switch st ~name))

(* --- report: the state of a running guest, on demand ---------------- *)

(* Episode 16 of `journalisation-profonde'. The third verb of the family, and the one which
   completes it: [log] serves what was written, [switch-info] asks a running switch what it
   knows, and this one asks a running *guest* the same question. Episode 15 measured the hole it
   fills — five journals, all of them traces, and not one able to say what is true at this
   instant: no address really configured, no `ip_forward', no firewall rule in force.

   NOTHING IS PRODUCED HERE. The producer is bin/scripts/marionnet-report.sh, deposited into the
   hostfs since episode 7, which already writes exactly what a corrector wants (real interfaces,
   routing tables v4 and v6, neighbours, ip_forward, `iptables-save'). It was missing a trigger:
   it only ran at shutdown. This verb is that trigger, and the answer is read back through the
   sixth journal — hence a reply which says *that* the report was taken, and never its content:
   [log <c> report] serves the content, and one thing is served in one place.

   The exchange is a file protocol, because the hostfs is the only way back into a guest (D1: no
   image is rebuilt, ever). Host: remove [report.done], then write [report.request]. Guest (the
   watcher of marionnet-watch.sh): consume the request, produce, rename onto report.md,
   write report.done. The removal is what makes the answer PROVABLY fresh: a done file which
   reappears was written after the request. *)
let report_request_basename = "report.request"
let report_done_basename    = "report.done"

(* Long on purpose, and for a reason the plan did not foresee — measured, not guessed. Two delays
   add up: the producer runs some twenty sections inside the guest, each under its own `timeout
   5'; and the watcher itself may not be up yet. Under systemd it is started by a job which
   systemd only runs once the boot is OVER, whereas [wait --ready] answers as soon as the startup
   configuration writes its marker — measured on a trixie, two minutes apart. A request posted in
   that window is not lost (the watcher serves it when it wakes up, see marionnet-watch.sh)
   but it is *waited for*, hence this default. *)
let default_report_timeout = 180.0

(* What a request is aiming at. The three refusals are three different pieces of news, as
   everywhere in this work-stream since episode 3: a switch has no guest to ask, a machine which
   is off cannot answer *now* (but its last report, if any, is still served by [log]), and a
   suspended one is frozen mid-instruction — the watcher included.

   Named after the guest and not after the report since episode 18: [exec] aims at exactly the
   same thing, refuses for exactly the same three reasons, and only the sentences differ — they
   are said by each verb, which is where they belong. *)
type guest_target =
  | Gt_absent
  | Gt_no_guest of string            (* a component, but of a kind which runs no guest: its kind *)
  | Gt_idle     of string            (* a guest which is not running: its state, in script words *)
  | Gt_hostfs   of string            (* a running guest: its hostfs directory *)

let find_guest_target (st : State.globalState) ~(name:string) : guest_target =
  match List.find_opt (fun n -> n#get_name = name) (st#network#get_node_list) with
  | Some n ->
      (match n#hostfs_directory_if_any with
       | None     -> Gt_no_guest n#string_of_devkind
       | Some dir ->
           (match script_state_of_raw n#state_as_string with
            | "on" -> Gt_hostfs dir
            | s    -> Gt_idle s))
  | None ->
  match List.find_opt (fun c -> c#get_name = name) (st#network#get_cable_list) with
  | Some _ -> Gt_no_guest "cable"
  | None   -> Gt_absent

(* One request at a time per component. Two clients asking together would each remove the other's
   done file and read the other's answer — the very freshness the protocol buys. Per name rather
   than global: asking m1 and r1 at the same time is the normal way to take a snapshot of a whole
   network, and it must stay parallel.

   Shared by [report] and [exec] rather than one table per verb, although their files do not
   collide: the guest serves the two requests in ONE loop (marionnet-watch.sh), so two overlapping
   questions to the same guest would queue there anyway — better to make the wait explicit here
   than to have a command run in the middle of a report being taken. *)
let guest_locks : (string, Mutex.t) Hashtbl.t = Hashtbl.create 8
let guest_locks_guard = Mutex.create ()

let guest_lock_of (name:string) : Mutex.t =
  Mutex.lock guest_locks_guard;
  let m =
    match Hashtbl.find_opt guest_locks name with
    | Some m -> m
    | None   -> let m = Mutex.create () in Hashtbl.add guest_locks name m; m
  in
  Mutex.unlock guest_locks_guard;
  m

(* `status=0 epoch=1786000000 lines=432', as the watcher prints it. Read as WORDS, not with a
   regexp: [Str] is not reentrant and this runs in a connection thread (the lesson of episode 5).
   An unreadable done file is not an error of the guest's making — a truncated line means we
   caught it mid-write — hence [None] rather than a refusal. *)
let done_field (line : string) (key : string) : string option =
  List.find_map
    (fun word ->
       let prefix = key ^ "=" in
       let n = String.length prefix in
       if String.length word > n && String.sub word 0 n = prefix then
         Some (String.sub word n (String.length word - n))
       else None)
    (String.split_on_char ' ' (String.trim line))

let parse_report_done (line : string) : (int * float * int) option =
  let field = done_field line in
  match field "status", field "epoch", field "lines" with
  | Some s, Some e, Some l ->
      (try Some (int_of_string s, float_of_string e, int_of_string l) with _ -> None)
  | _ -> None

type report_progress =
  | Rd_waiting                          (* no answer yet *)
  | Rd_done    of int * float * int     (* status, epoch, lines *)
  | Rd_unusable of string               (* the hostfs itself refused: nothing will ever come *)

let cmd_report (st : State.globalState) ~(gtk_timeout:float) ~(wait_timeout:float)
               ~(name:string) : string
  =
  if name = "" then
    reply_error ~code:"bad_argument" ~detail:"report expects the name of a component"
  else
  (* One round trip to the GTK thread, exactly as [log] and [switch-info] spend theirs: to find
     the component and where its guest writes. Everything after this is I/O, and belongs to this
     thread. *)
  match ask ~timeout:gtk_timeout (fun () -> find_guest_target st ~name) with
  | Failed e    -> reply_error ~code:"internal" ~detail:(Printexc.to_string e)
  | Timed_out t -> reply_error ~code:"timeout" ~detail:(gtk_busy_detail t)
  | Done Gt_absent ->
      reply_error ~code:"unknown_node" ~detail:(Printf.sprintf "no component named %S" name)
  | Done (Gt_no_guest kind) ->
      reply_error ~code:"bad_argument"
        ~detail:(Printf.sprintf
                   "%S is a %s: report applies to a machine or a router, the only kinds which run \
                    a guest system able to describe itself%s"
                   name kind
                   (* The pointer is only worth giving to something which *does* know its own
                      state; suggesting switch-info to a cable would be noise, and this
                      work-stream's rule since episode 3 is that a refusal says what to do —
                      when there is something to do. *)
                   (if kind = "switch" || kind = "hub" then
                      " — what a switch knows is asked with switch-info"
                    else ""))
  | Done (Gt_idle state) ->
      reply_error ~code:"bad_argument"
        ~detail:(Printf.sprintf
                   "%S is %s: a report is taken *inside* a running guest, so there is nobody to \
                    take it — start it (or resume it) and ask again. The report of its last \
                    session, if it had one, outlives it: see log %s report" name state name)
  | Done (Gt_hostfs dir) ->
      let lock = guest_lock_of name in
      let () = Mutex.lock lock in
      Fun.protect ~finally:(fun () -> Mutex.unlock lock)
        (fun () ->
           let request = Filename.concat dir report_request_basename in
           let answer  = Filename.concat dir report_done_basename in
           let report  = Filename.concat dir (List.assoc "report" journal_files) in
           (* The removal comes first and its failure is not fatal: a done file may simply not
              exist. What must not happen is the request going out while a stale answer is still
              lying there. *)
           let () = (try Sys.remove answer with _ -> ()) in
           match
             (try
                let out = open_out request in
                output_string out
                  (Printf.sprintf "%.0f\n" (Unix.gettimeofday ()));
                close_out out; None
              with e -> Some (Printexc.to_string e))
           with
           | Some why ->
               reply_error ~code:"internal"
                 ~detail:(Printf.sprintf
                            "could not ask %S for a report: writing %s failed (%s)"
                            name request why)
           | None ->
               let observe () =
                 Done
                   (if not (Sys.file_exists dir) then
                      Rd_unusable
                        (Printf.sprintf "the hostfs directory of %S (%s) has disappeared" name dir)
                    else
                      match mtime_of_regular_file answer with
                      | None -> Rd_waiting
                      | Some _ ->
                          (match first_line_of answer with
                           | None -> Rd_waiting   (* caught mid-write: look again *)
                           | Some line ->
                               (match parse_report_done line with
                                | None -> Rd_waiting
                                | Some (status, epoch, lines) -> Rd_done (status, epoch, lines))))
               in
               poll_until ~wait_timeout ~observe
                 ~reached:(function Rd_waiting -> false | _ -> true)
                 ~on_reached:(fun v elapsed ->
                    match v with
                    | Rd_unusable why -> reply_error ~code:"internal" ~detail:why
                    | Rd_done (status, _epoch, _lines) when status <> 0 ->
                        reply_error ~code:"internal"
                          ~detail:(Printf.sprintf
                                     "the guest of %S answered, but its report producer failed \
                                      (status %d): %s" name status report)
                    | Rd_done (_, epoch, lines) ->
                        reply_ok [ ("component", jstr name);
                                   (* The name to read it back with, published rather than
                                      spelled by the client: log <c> report. *)
                                   ("file",      jstr "report");
                                   ("path",      jstr report);
                                   ("lines",     jint lines);
                                   ("epoch",     jfloat epoch);
                                   ("waited",    jfloat elapsed) ]
                    | Rd_waiting -> assert false (* [reached] said otherwise *))
                 ~on_expiry:(fun _ elapsed ->
                    reply_error ~code:"timeout"
                      ~detail:(Printf.sprintf
                                 "%S did not answer the request for a report within %.1fs. Its \
                                  guest may still be booting (see wait --ready) — the watcher is \
                                  started at the very end of the boot, later than the marker \
                                  --ready waits for, so a request may legitimately wait for it. \
                                  Or it runs no watcher at all: a guest booted by an older \
                                  Marionnet, or one whose boot never reached its relay, has none \
                                  (see log %s boot)"
                                 name elapsed name)))

(* ---------------------------------------------------------------------------------------------
   [exec]: run a command INSIDE a guest — episode 18, and M2 of § 7.3.

   The one manque episode 16 left open, and it was left open on purpose: every other verb of this
   channel observes, this one commands. What it buys is the only thing a report cannot give — a
   report describes a state at an instant, it never says whether m1 REACHES h3 — and three of the
   five labs of the corpus (§ 7.1) are built on exactly that question.

   Same file protocol as [report], with one addition it cannot do without: an ID. Taking a report
   twice costs a report; running a command twice is a side effect, so an answer must be provably
   the answer to *this* request, not merely a fresh-looking one. The host names each request, the
   guest repeats the name, and an answer carrying another one is not an answer at all (it is a
   [Ex_waiting], i.e. keep looking).

   The output comes back HERE, unlike the report, whose content is served by [log <c> report].
   The two are not the same kind of thing: a report is a document a corrector reads whole and
   which outlives the request, an output is the value of a question just asked. What does end up
   in a journal is the COMMAND and its status — the seventh journal, [exec] — because a corrector
   must be able to tell what the channel injected from what the student typed.

   What this verb does NOT add is power: whoever runs the channel can already open a root terminal
   on the guest with a double click. What it adds is that the gesture is scriptable, and — through
   that journal — traceable, which the terminal is not. The honest limit is the one the whole
   work-stream carries: the hostfs is writable by the guest, so a determined student can forge an
   answer here just as they can forge three of the journals. Only the console (D2) escapes them. *)
let exec_request_basename = "exec.request"
let exec_done_basename    = "exec.done"
let exec_output_basename  = "exec.out"

(* Same default as [report], and for the same measured reason: the watcher which serves this is
   the very same one, started by a systemd job which only runs once the boot is over — well after
   the marker [wait --ready] answers on. A request posted in that window waits, it is not lost. *)
let default_exec_timeout = 180.0

(* Half the journals' bound, and deliberately: an output is read by whoever asked, on one line of
   JSON, whereas a journal is read to be searched. The byte bound is the journals' own
   ([max_journal_bytes], applied by [read_journal_tail]): the file is written by the guest, so a
   command looping on an error must not be able to size this thread's memory. *)
let max_exec_lines = 200

(* [--timeout] bounds the COMMAND, inside the guest; this channel waits a little longer than
   that. Measured need, not caution: bounding both with the same value means the wait expires at
   the very instant the guest kills the command, so a timed-out command could only ever be
   reported as "no answer" — the one thing the client already knows. With the grace, the guest
   has time to write its `done', and the answer says `timed_out: true' and carries whatever the
   command had produced before being killed. *)
let exec_grace = 15.0

(* Why an id at all is said above; why THIS id: the pid tells two Marionnets apart, the clock
   tells two sessions of one apart, and the counter tells two requests of one session apart. No
   secrecy is claimed — the guest writes in the same directory, so a guest which wants to lie
   about its own execution can. *)
let exec_counter = Atomic.make 0

let fresh_exec_id () : string =
  Printf.sprintf "%d.%.0f.%d"
    (Unix.getpid ()) (Unix.gettimeofday () *. 1000.) (Atomic.fetch_and_add exec_counter 1)

type exec_progress =
  | Ex_waiting                          (* no answer yet, or not the answer to our request *)
  | Ex_done     of int * float * int    (* status, epoch, seconds spent in the guest *)
  | Ex_unusable of string               (* the hostfs itself is gone: nothing will ever come *)

let parse_exec_done ~(id:string) (line : string) : exec_progress =
  let field = done_field line in
  match field "id" with
  | None -> Ex_waiting                            (* caught mid-write, or a done of episode 16 *)
  | Some answered when answered <> id -> Ex_waiting          (* an older request's answer: skip *)
  | Some _ ->
      (match field "status", field "epoch", field "seconds" with
       | Some s, Some e, Some sec ->
           (try Ex_done (int_of_string s, float_of_string e, int_of_string sec)
            with _ -> Ex_waiting)
       | _ -> Ex_waiting)

(* [command_timeout] is what the guest is told to bound the command with; the wait is that plus
   [exec_grace], for the reason written there. *)
let cmd_exec (st : State.globalState) ~(gtk_timeout:float) ~(command_timeout:float)
             ~(name:string) ~(command:string) : string
  =
  let wait_timeout = command_timeout +. exec_grace in
  if name = "" then
    reply_error ~code:"bad_argument" ~detail:"exec expects the name of a component"
  else if String.trim command = "" then
    reply_error ~code:"bad_argument"
      ~detail:"exec expects something to run: exec <component> <command>"
  else
  match ask ~timeout:gtk_timeout (fun () -> find_guest_target st ~name) with
  | Failed e    -> reply_error ~code:"internal" ~detail:(Printexc.to_string e)
  | Timed_out t -> reply_error ~code:"timeout" ~detail:(gtk_busy_detail t)
  | Done Gt_absent ->
      reply_error ~code:"unknown_node" ~detail:(Printf.sprintf "no component named %S" name)
  | Done (Gt_no_guest kind) ->
      reply_error ~code:"bad_argument"
        ~detail:(Printf.sprintf
                   "%S is a %s: exec runs a command inside a guest system, which only a machine \
                    or a router has%s"
                   name kind
                   (if kind = "switch" || kind = "hub" then
                      " — what a switch knows is asked with switch-info"
                    else ""))
  | Done (Gt_idle state) ->
      reply_error ~code:"bad_argument"
        ~detail:(Printf.sprintf
                   "%S is %s: a command runs *inside* a running guest, so there is nobody to run \
                    it — start it (or resume it) and ask again" name state)
  | Done (Gt_hostfs dir) ->
      let lock = guest_lock_of name in
      let () = Mutex.lock lock in
      Fun.protect ~finally:(fun () -> Mutex.unlock lock)
        (fun () ->
           let id      = fresh_exec_id () in
           let request = Filename.concat dir exec_request_basename in
           let answer  = Filename.concat dir exec_done_basename in
           let output  = Filename.concat dir exec_output_basename in
           let () = (try Sys.remove answer with _ -> ()) in
           match
             (try
                let out = open_out request in
                (* One header line, then the command AS RECEIVED — quoting included. Parsing it
                   here would mean holding a second copy of a shell's grammar, and a worse one:
                   the guest has a shell, and it is the one which must read this. *)
                output_string out
                  (Printf.sprintf "id=%s timeout=%.0f\n%s\n" id command_timeout command);
                close_out out; None
              with e -> Some (Printexc.to_string e))
           with
           | Some why ->
               reply_error ~code:"internal"
                 ~detail:(Printf.sprintf
                            "could not ask %S to run a command: writing %s failed (%s)"
                            name request why)
           | None ->
               let observe () =
                 Done
                   (if not (Sys.file_exists dir) then
                      Ex_unusable
                        (Printf.sprintf "the hostfs directory of %S (%s) has disappeared" name dir)
                    else
                      match first_line_of answer with
                      | None      -> Ex_waiting
                      | Some line -> parse_exec_done ~id line)
               in
               poll_until ~wait_timeout ~observe
                 ~reached:(function Ex_waiting -> false | _ -> true)
                 ~on_reached:(fun v elapsed ->
                    match v with
                    | Ex_unusable why -> reply_error ~code:"internal" ~detail:why
                    | Ex_waiting      -> assert false (* [reached] said otherwise *)
                    | Ex_done (status, epoch, seconds) ->
                        (* An unreadable output file is not a failure of the command: the guest
                           may have been unable to write it (a full COW), and the status is still
                           the truth about what ran. Hence an empty output rather than a refusal,
                           and the fields which say how much was served. *)
                        let (content, lines, total, dropped, truncated) =
                          match read_journal_tail ~path:output ~tail:max_exec_lines with
                          | Ok r    -> (r.jr_content, r.jr_lines, r.jr_total, r.jr_dropped,
                                        r.jr_truncated)
                          | Error _ -> ("", 0, 0, 0, false)
                        in
                        reply_ok [ ("component",     jstr name);
                                   ("command",       jstr command);
                                   ("status",        jint status);
                                   (* 124 is what `timeout' returns, and what this channel's own
                                      fallback returns in its place when the image has no
                                      `timeout' (marionnet-watch.sh): one thing to look at. *)
                                   ("timed_out",     jbool (status = 124));
                                   ("output",        jstr content);
                                   ("lines",         jint lines);
                                   ("total_lines",   jint total);
                                   ("dropped_lines", jint dropped);
                                   ("truncated",     jbool truncated);
                                   ("seconds",       jint seconds);
                                   ("epoch",         jfloat epoch);
                                   ("waited",        jfloat elapsed);
                                   (* Published rather than spelled by the client, as everywhere
                                      since episode 3: what was run is kept, and this is where. *)
                                   ("journal",       jstr "exec") ])
                 ~on_expiry:(fun _ elapsed ->
                    reply_error ~code:"timeout"
                      ~detail:(Printf.sprintf
                                 "%S did not answer the request to run a command within %.1fs. \
                                  The command itself was bounded by a shorter delay inside the \
                                  guest, so it has been killed there if it was still running — \
                                  log %s exec says which. Its guest may also still be booting \
                                  (see wait --ready): the watcher is started at the very end of \
                                  the boot, later than the marker --ready waits for. Or it runs \
                                  no watcher at all: a guest booted by an older Marionnet, or one \
                                  whose boot never reached its relay, has none (see log %s boot)"
                                 name elapsed name name)))

(* The two refusals [log] (episode 3) and [switch-info] (episode 5) share, because they share a
   shape: one optional choice, spelled positionally or as an option. A mistyped --tial= would
   serve 400 lines while the client believed it asked for 20, and a choice given twice would
   have one of its two answers picked in silence. Written once so that a third verb of the same
   shape cannot drift from them. *)
let optional_choice_of (r : request) ~(verb:string) ~(option_name:string) ~(what:string)
                       ~(other_options:string list) : (string option, string) result
  =
  let syntax () =
    match List.assoc_opt verb arity_of_command with Some a -> a.syntax | None -> verb in
  match List.filter (fun (k, _) -> not (List.mem k (option_name :: other_options))) r.opts with
  | (k, _) :: _ ->
      Error (Printf.sprintf "no option --%s here; syntax: %s" k (syntax ()))
  | [] ->
      (match option_value r option_name, arg_opt r 1 with
       | Some _, Some _ ->
           Error (Printf.sprintf
                    "the %s is given twice (positional argument and --%s): give it once"
                    what option_name)
       | opt, pos -> Ok (match opt with None -> pos | some -> some))

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
  (* Exam locks (journalisation-profonde, episode 22). The shutdown below is graceful, so the
     session *is* archived into the [documents] treeview — but an archive which is never written
     to the .mar is an archive nobody will read, and --no-save is precisely the order to throw it
     away. Refused rather than silently upgraded to --save: a channel which does the opposite of
     what it was told is worse than one which refuses. *)
  if Initialization.are_we_in_exam_mode && policy = Some Discard_it then
    Error (reply_error_with ~extra:(extra ()) ~code:"forbidden_in_exam_mode"
             ~detail:"--no-save is refused in exam mode: the session archives (report, command \
                      history, recorded consoles) reach the .mar through the save only. Use --save.")
  else
  if policy = None && not already_saved then
    Error (reply_error_with ~extra:(extra ()) ~code:"unsaved_changes"
             ~detail:"the project has unsaved changes: pass --save or --no-save to say what to do with them")
  else
  let want_save = (policy = Some Save_it) in
  (* Logged here and not at the entry of the commands: a refused close must not leave a line
     saying the project was being closed (N4's rule — an instrument may not lie). *)
  let () = Log.printf1 "Control_server: leaving the current project (save: %b).\n" want_save in
  (* Same order as the menu (Common_dialogs.shutdown_then_save, gui_menubar_MARIONNET.ml), and
     the waiting in between is the whole point: [shutdown_everything] only *schedules* its tasks
     (schedule_parallel, state.ml) and returns at once, so saving right after it wrote a .mar
     while the components were still going down — a tar of a working directory whose cow files
     are still being written, exactly what `save' refuses since episode 19. The wait is
     unconditional, as in the menu: without --save, close_project waited for the task runner one
     step further anyway (state.ml), so this changes the order, never the answer.
     Legitimate in this thread, and only here: [wait_for_all_currently_scheduled_tasks] must not
     run in the GTK main thread (task_runner.ml), which the header of this section establishes it
     is not. The price is written above: with --save, this command now lasts as long as the
     shutdown does. *)
  let () = st#shutdown_everything () in
  let () = Task_runner.the_task_runner#wait_for_all_currently_scheduled_tasks in
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
  (* Episode 19 of marionnet-todo-transverse: what a .mar written while things run is worth.
     The archive is a plain [tar] of the working directory (state.ml, `private_save_project'),
     and the only exclusion which touches the disks is [get_files_may_not_be_saved]
     (treeview_history.ml) whose name misleads: those are the *older* snapshots, never the
     current cow. The cow of a running guest is therefore archived WHILE its kernel writes into
     it — the restored disk is worth the one of a power cut. That is the reason, written nowhere
     until now, of the refusal the GUI has always opposed to "Save", "Save as" and "Copy to"
     (Msg.error_saving_while_something_up, talking.ml). The channel now opposes the same one:
     the answer is a refusal a client can read, not a silent .mar the GUI would never have
     written.
     The list of names *is* the predicate — empty iff [is_there_something_on_or_sleeping] is
     false, since it walks the same nodes with the same test (state.ml) — so there is no second
     source of truth to drift. Refused BEFORE anything is called: [save_project_as] changes the
     project name before saving (state.ml), and a refusal must leave even that untouched. *)
  ask_ (fun () ->
          List.filter_map
            (fun n -> if n#can_gracefully_shutdown || n#can_resume then Some n#get_name else None)
            (st#network#get_node_list))
  >>= fun running ->
  if running <> [] then
    Error (reply_error_with ~extra:(extra ()) ~code:"components_running"
             ~detail:(Printf.sprintf
                        "the project cannot be written while components are on or sleeping \
(%s): their disks would be archived in mid-flight. Stop them first, or use \"close --save\", \
which shuts everything down and then saves."
                        (String.concat ", " running)))
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

(* Exam locks (journalisation-profonde, episode 22). [quit] is the third way of losing the copy,
   and the quietest: [quit_async] destroys the processes of every running component
   (state.ml, [destroy_process_before_quitting]) — a brutal cut, hence no archiving — and saves
   nothing. In exam mode it is therefore refused while a project is open and either something is
   still up or the project carries unsaved changes; [close --save] does both jobs in the right
   order (graceful shutdown, then save), and [quit] passes right after it. Not refused outright:
   a driven exam session must still be able to end itself, which is how the teacher's guide
   closes one. *)
(* Episode 18 of marionnet-todo-transverse: the pid, and why the answer carries it. The reply
   necessarily leaves BEFORE the process does — [quit_async] only *schedules* the shutdown
   (state.ml) and one cannot answer after leaving — so when the client reads this line the
   process, its components and its taps are all still there (measured: half a second of them). The end
   of a session is therefore not something this answer can wait for: it is something the client
   must be able to WATCH, and the pid is the handle which stays true whatever kills us. Without
   it a script holds a socket and nothing else, and chaining [quit] with the launch of the next
   session makes two coexist unnoticed — which is how three marionnet.exe were once found
   together (journalisation-profonde, episode 21). The socket *file* is not that handle: it is
   unlinked on a clean exit (ocamlbricks, network.ml, at_exit of the server thread) and left
   behind by a brutal one, so its absence proves an ending while its presence proves nothing.
   Published by [cmd_status] as well, so that a client may arm its watch before quitting — and
   because the refusals below carry no pid: the contract belongs to the "quitting" answer, as
   the entry of docs/TODO.md required. *)
let cmd_quit (st : State.globalState) ~(timeout:float) : string * [ `Continue | `Quit ] =
  let quitting () =
    (reply_ok [ ("quitting", jbool true); ("pid", jint (Unix.getpid ())) ], `Quit)
  in
  if not Initialization.are_we_in_exam_mode then quitting () else
  match
    ask_or_answer ~extra:(fun () -> []) ~timeout
      (fun () -> (st#active_project,
                  st#is_there_something_on_or_sleeping (),
                  st#project_already_saved))
  with
  | Error answer -> (answer, `Continue)
  | Ok (false, _, _) -> quitting ()
  | Ok (true, running, saved) when running || not saved ->
      (reply_error ~code:"forbidden_in_exam_mode"
         ~detail:(Printf.sprintf
                    "quitting now would throw the exam copy away (%s): quitting cuts the power \
                     of every running component and saves nothing. Run \"close --save\" first, \
                     then quit."
                    (match running, saved with
                     | true,  true  -> "components are still running"
                     | true,  false -> "components are still running, and the project has unsaved changes"
                     | false, _     -> "the project has unsaved changes")),
       `Continue)
  | Ok _ -> quitting ()

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

(* A header as a script spells it. Derived, never listed — the same reason the read side publishes
   #columns: a column added to a treeview becomes writable the day it becomes readable, with no
   table here to update.

   The rule: lowercase, every non-alphanumeric run becomes a single dash, trailing dashes are
   dropped. Episode 5b only had to turn spaces into dashes, ifconfig headers being made of letters
   and spaces; the defects headers are not ("Loss %", "Minimum delay (ms)"), and a slug carrying a
   percent sign or parentheses would force every script to quote it. The five ifconfig slugs are
   unchanged by this generalisation — mac-address, mtu, ipv4-address, ipv4-gateway, ipv6-address,
   ipv6-gateway — which the bench asserts rather than assumes. *)
let slug_of_header (h:string) : string =
  let b = Buffer.create (String.length h) in
  let () =
    String.iter
      (fun c ->
         match Char.lowercase_ascii c with
         | ('a'..'z' | '0'..'9') as c -> Buffer.add_char b c
         | _ ->
             if (Buffer.length b > 0) && (Buffer.nth b (Buffer.length b - 1)) <> '-' then
               Buffer.add_char b '-')
      h
  in
  let s = Buffer.contents b in
  let n = String.length s in
  if n > 0 && s.[n-1] = '-' then String.sub s 0 (n-1) else s

(* The headers served, in the order the GUI shows them: #add_column *appends*
   (treeview.ml:908), so #columns keeps that order — whereas #column_headers is a Hashtbl.fold,
   whose order is unspecified and would make any assertion on it flaky. Reserved columns (_id,
   _uneditable, _highlight) are left out, exactly as #get_row leaves them out of a row
   (treeview.ml:1419). *)
let visible_headers (tv : Treeview.t) : string list =
  List.filter_map (fun c -> if c#is_reserved then None else Some c#header) tv#columns

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
  (* headers shown, field names a script may *write* (episode 10), roots kept *)
  | Tv_read       of string list * string list * Treeview.Row.t Forest.tree list
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
       (* Computed here, in the GTK slot, because it reads the columns of the widget: the reply
          below runs outside it and has no [tv]. *)
       let slugs = List.map slug_of_header (editable_headers tv) in
       let roots = Forest.to_treelist tv#get_forest in
       let root_name ((row, _) : Treeview.Row.t Forest.tree) =
         match List.assoc_opt treeview_name_column row with
         | Some (Treeview.Row_item.String s) -> Some s
         | _ -> None
       in
       match name with
       | None -> Tv_read (headers, slugs, roots)
       | Some wanted ->
           (match List.filter (fun t -> root_name t = Some wanted) roots with
            | []   -> Tv_unknown (List.sort_uniq compare (List.filter_map root_name roots))
            | kept -> Tv_read (headers, slugs, kept)))
  |> reply_of_outcome
       (function
        | Tv_read (headers, slugs, roots) ->
            reply_ok [ ("treeview", jstr which);
                       ("columns",  jlist (List.map jstr headers));
                       (* The field names a script may WRITE here: the very list a refusal
                          names ([editable_headers] through [slug_of_header], episode 5b), served
                          beside the headers since episode 10. A completion — or a reader
                          wondering why "IPv4 address" is refused — gets the write vocabulary
                          from the same answer as the read one, instead of recomputing the slug
                          rule on its side. Not the slugs of [columns]: Name and Type are
                          readable and not writable, and that difference is the point. *)
                       ("slugs",    jlist (List.map jstr slugs));
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

(* § 4.6, write side of defects (episode 5c). Losses, delays and noise are what makes a lab
   exercise realistic, and they are the one treeview whose writes the GUI applies to a *running*
   network. Measured, not assumed — three facts of the code shape this command, and none of them
   is a symmetry with ifconfig-set:

   (a) a defect of a CABLE applies hot, and the GUI asks nothing. after_user_edit_callback →
       shutdown_or_restart_relevant_device (marionnet.ml:154) does, for a connected cable,
       "c#suspend; c#resume" with no dialog at all. That couple destroys and rebuilds the
       simulated device (cable.ml:820-847), whose initializer (cable.ml:981) re-reads
       get_my_defects and passes the values to wirefilter on its command line
       (defects_to_command_line_options, simulation_level.ml:604). So the channel does the same,
       and reports it in [reconnected] — accepted, never finished (rule 3, § 4.4);

   (b) a defect of a NODE port falls back on episode 5b: the GUI opens the "reboot now?" dialog
       (marionnet.ml:141-152), guarded by can_gracefully_shutdown, hence --restart/--no-restart
       required of the script as soon as the node is running;

   (c) the direction is designated by its TYPE, never by its Name. Under a cable, a direction row
       is *named* "to m1 (eth0)" (cable.ml:623): it holds spaces, so it could not be a positional
       argument (§ 4.1), and it changes when an endpoint is renamed
       (#rename_cable_endpoints). Treeview_defects#get_cable_data filters by Type for the very same
       reason. Under a node port, Name and Type agree (inward/outward), so Type is uniform.

   The three levels of a node entry (node → port → direction) against the two of a cable one are
   therefore not a matter of counting arguments: the treeview says which shape a request has, and
   a request mixing the two is refused with the syntax in clear. *)

let treeview_type_column = "Type"

let icon_cell (row : Treeview.Row.t) (header:string) : string =
  match List.assoc_opt header row with
  | Some (Treeview.Row_item.Icon s) -> s
  | _ -> ""

(* What the write triggered right away. A cable is reconnected with no question asked, a node is
   restarted only if the script said so — the asymmetry of (a) and (b) above. *)
type defects_application =
  | Da_reconnected of bool
  | Da_restarted   of bool

type defects_written = {
  dw_port      : string option;
  dw_direction : string;
  dw_header    : string;
  dw_old       : string;
  dw_new       : string;
  (* The sister bound realigned by #edit_side_effects, read back like everything else. The GUI
     does this silently; a script is told, the way episode 4f reports an adjusted kernel. *)
  dw_adjusted  : (string * string) option;
  (* The title of the warning the GUI would have shown in a dialog (flipped bits above 1%). *)
  dw_warning   : string option;
  dw_applied   : defects_application;
}

type defects_outcome =
  | De_written           of defects_written
  | De_no_project
  | De_unknown_target    of string list
  | De_unknown_port      of string list
  | De_unknown_direction of string list
  | De_unknown_field     of string list
  | De_violated          of string
  | De_restart_choice    of string
  | De_bad_shape         of string

let cmd_defects_set (st : State.globalState) ~(timeout:float) ~(args:string list)
    ~(restart:bool option) : string
  =
  let target = match args with x :: _ -> x | [] -> "" in
  ask ~timeout
    (fun () ->
       if not st#active_project then De_no_project else
       let tv  = (st#treeview#defects :> Treeview.t) in
       let tvd = st#treeview#defects in
       (* The complete forest, not #get_forest: writing needs the _id of the row, which is reserved
          and therefore absent from the rows the read side serves. *)
       let roots = Forest.to_treelist tv#get_complete_forest in
       match List.find_opt (fun t -> tree_name t = Some target) roots with
       (* The names of *this* treeview: unlike ifconfig it holds the eight natures **and** the
          cables (episode 5a), so this list is wider than the addressable components. *)
       | None -> De_unknown_target (List.sort_uniq compare (List.filter_map tree_name roots))
       | Some (root_row, root_children) ->
           let is_cable =
             match icon_cell root_row treeview_type_column with
             | "straight-cable" | "crossover-cable" -> true
             | _                                    -> false
           in
           let shape =
             match is_cable, args with
             | true,  [ _; d; f ]       -> Ok (None,   d, f, "")
             | true,  [ _; d; f; v ]    -> Ok (None,   d, f, v)
             | true,  _                 ->
                 Error (Printf.sprintf
                          "%S is a cable, whose entry has no ports — usage: \
                           defects-set <cable> <leftward|rightward> <field> [<value>]" target)
             | false, [ _; p; d; f ]    -> Ok (Some p, d, f, "")
             | false, [ _; p; d; f; v ] -> Ok (Some p, d, f, v)
             | false, _                 ->
                 Error (Printf.sprintf
                          "%S is a node, whose entry has one level per port — usage: \
                           defects-set <node> <port> <inward|outward> <field> [<value>] \
                           [--restart|--no-restart]" target)
           in
           (match shape with
            | Error detail -> De_bad_shape detail
            (* Refused rather than ignored (§ 4.1): the GUI never asks anything before applying a
               cable defect, so an option that says what to do about a reboot is a script bug. *)
            | Ok _ when is_cable && restart <> None ->
                De_bad_shape
                  (Printf.sprintf
                     "%S is a cable: it is reconnected right away, as the GUI does, so neither \
                      --restart nor --no-restart applies here" target)
            | Ok (port, direction, field, value) ->
                let direction_rows =
                  match port with
                  | None   -> Ok (Forest.to_treelist root_children)
                  | Some p ->
                      let ports = Forest.to_treelist root_children in
                      (match List.find_opt (fun t -> tree_name t = Some p) ports with
                       | None -> Error (List.filter_map tree_name ports)
                       | Some (_port_row, port_children) ->
                           Ok (Forest.to_treelist port_children))
                in
                (match direction_rows with
                 | Error names -> De_unknown_port names
                 | Ok directions ->
                     let direction_type ((row, _) : Treeview.Row.t Forest.tree) =
                       icon_cell row treeview_type_column
                     in
                     (match List.find_opt (fun t -> direction_type t = direction) directions with
                      | None -> De_unknown_direction (List.map direction_type directions)
                      | Some (direction_row, _) ->
                          let headers = editable_headers tv in
                          (match List.find_opt (fun h -> slug_of_header h = field) headers with
                           | None -> De_unknown_field (List.map slug_of_header headers)
                           | Some header ->
                               let old = string_cell direction_row header in
                               let written ?adjusted ?warning ~applied v =
                                 De_written { dw_port = port; dw_direction = direction;
                                              dw_header = header; dw_old = old; dw_new = v;
                                              dw_adjusted = adjusted; dw_warning = warning;
                                              dw_applied = applied }
                               in
                               (* A write that changes nothing validates nothing and restarts
                                  nothing, exactly as the GUI fires no callback when a cell is
                                  left as it was (episode 5b). *)
                               if value = old then
                                 written old
                                   ~applied:(if is_cable then Da_reconnected false
                                             else Da_restarted false)
                               else
                               let new_row =
                                 Treeview.Row.set_field ~field:header
                                   ~value:(Treeview.Row_item.String value) direction_row
                               in
                               (match tv#constraints_verdict new_row with
                                | Some (`Row name) ->
                                    (* %s and not %S: a row constraint is named through gettext,
                                       and %S would escape its UTF-8 (episode 5b). Here it is the
                                       constraint that refuses a value typed on a device, a port or
                                       a cable row instead of one of its directions. *)
                                    De_violated
                                      (Printf.sprintf
                                         "the treeview row constraint \"%s\" refuses this write \
                                          (the GUI refuses it too)" name)
                                | Some (`Column h) ->
                                    De_violated
                                      (Printf.sprintf "the column %S does not accept %S" h value)
                                | None ->
                                    let cable =
                                      if not is_cable then None else
                                      try Some (st#network#get_cable_by_name target)
                                      with _ -> None
                                    in
                                    let running =
                                      if is_cable then None else
                                      match List.find_opt (fun n -> n#get_name = target)
                                              (st#network#get_node_list)
                                      with
                                      | Some n when n#can_gracefully_shutdown -> Some n
                                      | _ -> None
                                    in
                                    (match running, restart with
                                     | Some n, None -> De_restart_choice n#state_as_string
                                     | _ ->
                                         let row_id = Treeview.Row.get_id direction_row in
                                         let () =
                                           tv#set_row_field row_id header
                                             (Treeview.Row_item.String value)
                                         in
                                         (* The other half of the GTK cell-edited path: the sister
                                            bound, the highlighting and the warning, all of them in
                                            the treeview's own method (episode 5c). *)
                                         let (adjusted, warning) =
                                           tvd#edit_side_effects ~row_id ~header ~new_content:value
                                         in
                                         (* First half of after_user_edit_callback
                                            (marionnet.ml:178). *)
                                         let () = st#set_project_not_already_saved in
                                         let applied =
                                           match cable, running, restart with
                                           | Some c, _, _ ->
                                               if c#is_connected then
                                                 let () = c#suspend in
                                                 let () = c#resume in
                                                 Da_reconnected true
                                               else Da_reconnected false
                                           | None, Some n, Some true ->
                                               let () = n#gracefully_restart in
                                               Da_restarted true
                                           | _ -> Da_restarted false
                                         in
                                         (* Read back, never assumed — the rule of [set]
                                            (episode 4d-2a), and the only way to see that
                                            string_of_float wrote "100." where the script said
                                            "100". *)
                                         let read_back h =
                                           Treeview.Row_item.extract_String
                                             (tv#get_row_field row_id h)
                                         in
                                         written (read_back header)
                                           ?adjusted:(match adjusted with
                                                      | None        -> None
                                                      | Some (h, _) -> Some (h, read_back h))
                                           ?warning:(match warning with
                                                     | None            -> None
                                                     | Some (title, _) -> Some title)
                                           ~applied)))))))
  |> reply_of_outcome
       (function
        | De_written w ->
            reply_ok [ ("target",    jstr target);
                       ("port",      jopt w.dw_port);
                       ("direction", jstr w.dw_direction);
                       ("field",     jstr w.dw_header);
                       ("old",       jstr w.dw_old);
                       ("new",       jstr w.dw_new);
                       ("changed",   jbool (w.dw_old <> w.dw_new));
                       ("adjusted",  (match w.dw_adjusted with
                                      | None -> jnull
                                      | Some (h, v) -> jobj [ ("field", jstr (slug_of_header h));
                                                              ("new",   jstr v) ]));
                       ("warning",   jopt w.dw_warning);
                       (* Two names for two behaviours, so that a script never has to guess which
                          one it got: a cable is reconnected, a node is restarted. *)
                       (match w.dw_applied with
                        | Da_reconnected b -> ("reconnected", jbool b)
                        | Da_restarted   b -> ("restarted",   jbool b)) ]
        | De_no_project ->
            reply_error ~code:"no_active_project" ~detail:"no project is open"
        | De_unknown_target names ->
            reply_error ~code:"unknown_target"
              ~detail:(Printf.sprintf
                         "no row named %S in the defects treeview; known: %s"
                         target (String.concat ", " names))
        | De_unknown_port names ->
            reply_error ~code:"unknown_port"
              ~detail:(Printf.sprintf "%S has no port named %S; its ports are: %s"
                         target (match args with _ :: p :: _ -> p | _ -> "")
                         (String.concat ", " names))
        | De_unknown_direction names ->
            reply_error ~code:"unknown_direction"
              ~detail:(Printf.sprintf "no such direction here; available: %s"
                         (String.concat ", " names))
        | De_unknown_field slugs ->
            reply_error ~code:"unknown_field"
              ~detail:(Printf.sprintf "no writable field in defects; writable fields: %s"
                         (String.concat ", " slugs))
        | De_violated detail ->
            reply_error ~code:"constraint_violated" ~detail
        | De_bad_shape detail ->
            reply_error ~code:"bad_argument" ~detail
        | De_restart_choice raw ->
            reply_error ~code:"restart_choice_required"
              ~detail:(Printf.sprintf
                         "%S is %s: the GUI asks here whether to reboot it, so the script must \
                          say --restart or --no-restart"
                         target (script_state_of_raw raw)))

(* § 4.6, episode 5d: history by its ACTIONS, not by its cells.

   The episode was written down as "history and documents, write side", by symmetry with 5b and
   5c. Applied literally it would deliver almost nothing: history has exactly ONE editable column
   (Comment, treeview_history.ml:487) and documents four, all of them metadata — nothing that
   configures a lab, where ifconfig carried the addresses and defects the impairments. What the
   title hid is that this treeview's value is in its contextual MENU, nine entries none of which
   the channel covered, and first among them "Start in this state" (treeview_history.ml:540):
   booting a machine from a *given* disk state. That is the gesture a teacher makes to put
   students in a prepared situation, and it was the last real gap against the contract of § 4.10.

   THE IDENTIFIER IS THE COW FILE NAME, not the node name. In this treeview Name is NOT unique —
   one machine owns as many rows as it has states — while the COW file name is unique twice over:
   by construction (cow_files.ml:23-35) and within the treeview, which is why the model itself
   keys on it (get_parent_cow_file_name). It holds no space, so it is a legal positional argument
   (§ 4.1), and the read side already serves it: the "File name" column is ~hidden but NOT
   reserved, and #get_row only filters the reserved ones (the hidden ≠ reserved trap of 5a). A
   script reads `history m1`, finds the state it wants, and passes it straight back. *)

(* Only the failures are named as a type: the three commands share their prologue, hence their
   refusals, while each has its own success to report. A single sum holding both would force a
   dead branch ("error rendering called on a success") in every one of them. *)
type history_failure =
  | H_no_project
  | H_unknown_state of string list   (* the cow files that do exist *)
  | H_orphan_row    of string        (* a history row whose node is not in the network *)
  | H_forbidden     of string
  | H_unknown_field of string list
  | H_violated      of string

(* Every cow file the treeview knows, for the refusals: a name that does not exist is answered
   with the names that do — the rule the whole channel follows since episode 4d-2a. Written on
   row ids rather than on the forest because the answer needs no structure here, only a list. *)
let history_cow_files (h : Treeview_history.t) : string list =
  List.sort_uniq compare (List.map h#get_row_filename (h#row_ids_such_that (fun _ -> true)))

(* Shared prologue of the three commands: no project, or an unknown state, or the row and the
   name of the machine that owns it. *)
let history_row_of_cow (st : State.globalState) (cow:string)
  : (Treeview_history.t * string * string, history_failure) result
  =
  if not st#active_project then Error H_no_project else
  let h = st#treeview#history in
  match h#row_id_of_cow_file_name_if_any cow with
  | None        -> Error (H_unknown_state (history_cow_files h))
  | Some row_id -> Ok (h, row_id, h#get_row_name row_id)

let history_error ?(field="") ~(cow:string) : history_failure -> string = function
  | H_no_project ->
      reply_error ~code:"no_active_project" ~detail:"no project is open"
  | H_unknown_state files ->
      reply_error ~code:"unknown_state"
        ~detail:(Printf.sprintf
                   "no state %S in the history treeview; a state is named by its cow file, and \
                    these exist: %s"
                   cow (String.concat ", " files))
  | H_orphan_row name ->
      reply_error ~code:"unknown_node"
        ~detail:(Printf.sprintf
                   "the history row belongs to %S, which is not in the network" name)
  | H_forbidden detail ->
      reply_error ~code:"forbidden_transition" ~detail
  | H_unknown_field slugs ->
      reply_error ~code:"unknown_field"
        ~detail:(Printf.sprintf "no writable field %S in history; writable fields: %s"
                   field (String.concat ", " slugs))
  | H_violated detail ->
      reply_error ~code:"constraint_violated" ~detail

let cmd_history_start (st : State.globalState) ~(timeout:float) ~(cow:string) : string =
  ask ~timeout
    (fun () ->
       match history_row_of_cow st cow with
       | Error f -> Error f
       | Ok (h, row_id, name) ->
           (* The very condition the menu entry carries (treeview_history.ml:542-547): it asks
              [can_startup name] through Startup_functions, which marionnet.ml:129-141 fills with
              node#can_startup — the model method the channel already reads for `can`. So this is
              the GUI's guard, not one invented here. *)
           (match List.find_opt (fun n -> n#get_name = name) (st#network#get_node_list) with
            | None -> Error (H_orphan_row name)
            | Some n when not n#can_startup ->
                Error (H_forbidden
                         (Printf.sprintf
                            "%S is %s: the GUI greys out \"Start in this state\" here"
                            name (script_state_of_raw n#state_as_string)))
            | Some _ ->
                (* Antedates the row to now — which makes it the most recent, hence the state the
                   machine will take — starts, then restores the timestamp on the task runner.
                   Accepted, never finished (rule 3, § 4.4): #startup queues the work. *)
                let () = h#startup_in_state row_id in
                Ok name))
  |> reply_of_outcome
       (function
        | Error f  -> history_error ~cow f
        | Ok name  ->
            reply_ok [ ("node", jstr name); ("state", jstr cow); ("accepted", jbool true) ])

let cmd_history_del (st : State.globalState) ~(timeout:float) ~(cow:string) ~(except:bool)
  : string
  =
  ask ~timeout
    (fun () ->
       match history_row_of_cow st cow with
       | Error f -> Error f
       | Ok (h, row_id, name) ->
           (* Both menu entries are conditioned by number_of_states_with_name > 1
              (treeview_history.ml:558-563): a machine always keeps a state, and the last one is
              not removable. The channel refuses where the GUI greys out. *)
           if h#number_of_states_with_name name <= 1 then
             Error (H_forbidden
                      (Printf.sprintf
                         "%S has a single state: the GUI does not offer to delete it either" name))
           else
             (* What was actually removed, read from the treeview before and after:
                delete_states_except_this removes a whole subtree, and a count computed here would
                be a guess. The answer reports the difference, never an intention. *)
             let before = history_cow_files h in
             let () =
               if except then h#delete_states_except_this row_id else h#delete_state row_id
             in
             let after = history_cow_files h in
             let () = st#set_project_not_already_saved in
             Ok (name, List.filter (fun f -> not (List.mem f after)) before))
  |> reply_of_outcome
       (function
        | Error f -> history_error ~cow f
        | Ok (name, removed) ->
            reply_ok [ ("node",    jstr name);
                       ("removed", jlist (List.map jstr removed));
                       ("count",   jint (List.length removed)) ])

(* Exporting a state as a variant — the gesture an image update is made of (episode 22 of
   `marionnet-kernel-rootfs': producing machine-debian-trixie-16341 from the published 39212
   was driven entirely by this channel EXCEPT this step, which had to be done with a `cp' by
   hand).

   Nothing here decides anything the GUI does not: the guard is the one the menu entry carries
   (Startup_functions/can_startup, treeview_history.ml — a cow file of a RUNNING machine is a
   dirty filesystem), the name constraint is the one its dialog enforces
   (StrExtra.Class.identifierp ~allow_dash:()), and the copy itself is
   #export_row_as_variant, the method both callers share.

   The one divergence, and it is deliberate: the dialog OVERWRITES a variant of the same name
   without a word, this refuses unless --force. A human choosing a name sees the directory in
   front of them; a script does not, and a variant is what a published image comes from. *)
let cmd_history_export (st : State.globalState) ~(timeout:float) ~(cow:string)
    ~(variant:string) ~(force:bool) : string
  =
  ask ~timeout
    (fun () ->
       match history_row_of_cow st cow with
       | Error f -> Error f
       | Ok (h, row_id, name) ->
           if not (StrExtra.Class.identifierp ~allow_dash:() variant) then
             Error (H_violated
                      (Printf.sprintf
                         "%S is not a variant name: it must begin with a letter and hold only \
                          letters, digits, dashes and underscores (the GUI dialog refuses it too)"
                         variant))
           else
           (match List.find_opt (fun n -> n#get_name = name) (st#network#get_node_list) with
            | None -> Error (H_orphan_row name)
            | Some n when not n#can_startup ->
                Error (H_forbidden
                         (Printf.sprintf
                            "%S is %s: the GUI refuses to export the state of a running device \
                             (\"You have to shut it down first\") — its cow file is a filesystem \
                             nobody unmounted"
                            name (script_state_of_raw n#state_as_string)))
            | Some _ ->
                (match h#export_row_as_variant ~force ~row_id ~variant_name:variant () with
                 | Error detail -> Error (H_violated detail)
                 | Ok pathname ->
                     (* The APPARENT size, read from the file and never guessed — and
                        apparent is the only one Unix.stat knows (no st_blocks in OCaml's
                        stats). A variant is a sparse copy: expect a couple of megabytes on
                        disk for the gigabytes announced here, which is why the copy uses
                        --sparse=always. A caller wanting the real cost asks `du'. *)
                     let bytes = (try (Unix.stat pathname).Unix.st_size with _ -> 0) in
                     Ok (name, pathname, bytes))))
  |> reply_of_outcome
       (function
        | Error f -> history_error ~cow f
        | Ok (name, pathname, bytes) ->
            reply_ok [ ("node",    jstr name);
                       ("state",   jstr cow);
                       ("variant", jstr variant);
                       ("path",    jstr pathname);
                       ("bytes",   jint bytes) ])

(* The one editable cell, for completeness: leaving it out would be a hole a script would meet at
   once (the read side serves Comment, and it is the only thing a human may type here). Same
   pattern as 5b/5c: the verdict before the write, and the callback's own half done by hand. *)
let cmd_history_set (st : State.globalState) ~(timeout:float) ~(cow:string) ~(field:string)
    ~(value:string) : string
  =
  ask ~timeout
    (fun () ->
       match history_row_of_cow st cow with
       | Error f -> Error f
       | Ok (h, row_id, _name) ->
           let tv = (h :> Treeview.t) in
           let headers = editable_headers tv in
           (match List.find_opt (fun hd -> slug_of_header hd = field) headers with
            | None -> Error (H_unknown_field (List.map slug_of_header headers))
            | Some header ->
                let old = Treeview.Row_item.extract_String (tv#get_row_field row_id header) in
                if value = old then Ok (header, old, old) else
                (* #set_row_field validates nothing — the checks live in the GTK cell-edited path
                   (episode 5b). Replaying #constraints_verdict is the discipline of this channel
                   even where the treeview declares few constraints: a column that gains one
                   tomorrow must not find a writer that bypasses it. *)
                let new_row =
                  Treeview.Row.set_field ~field:header
                    ~value:(Treeview.Row_item.String value) (tv#get_complete_row row_id)
                in
                (match tv#constraints_verdict new_row with
                 | Some (`Row name) ->
                     (* An escaped-quote %s and not %S: a row constraint is named with a
                        translated string, and %S escapes every byte above 0x7f — the answer
                        would carry an unreadable name (lesson of episode 5b). *)
                     Error (H_violated
                              (Printf.sprintf
                                 "the treeview row constraint \"%s\" refuses this write (the GUI \
                                  refuses it too)" name))
                 | Some (`Column h) ->
                     Error (H_violated
                              (Printf.sprintf "the column %S does not accept %S" h value))
                 | None ->
                let () = tv#set_row_field row_id header (Treeview.Row_item.String value) in
                let () = st#set_project_not_already_saved in
                (* Read back, never assumed — same rule as [set] (episode 4d-2a). *)
                let written =
                  Treeview.Row_item.extract_String (tv#get_row_field row_id header)
                in
                Ok (header, old, written))))
  |> reply_of_outcome
       (function
        | Error f -> history_error ~field ~cow f
        | Ok (header, old, written) ->
            reply_ok [ ("state",   jstr cow);
                       ("field",   jstr header);
                       ("old",     jstr old);
                       ("new",     jstr written);
                       ("changed", jbool (old <> written)) ])

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
                  else [ "timeout"; "field"; "from"; "enable"; "disable";
                         "select"; "unselect"; "terminal"; "no-terminal" ]
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
                       (* Three pairs of mutually exclusive flags, refused the same way: keeping
                          one of two contradictory orders is the quiet choice this channel does
                          not make. *)
                       let flag ~yes ~no =
                         match option_value r yes <> None, option_value r no <> None with
                         | true, true   -> Error (yes, no)
                         | true, false  -> Ok (Some true)
                         | false, true  -> Ok (Some false)
                         | false, false -> Ok None
                       in
                       (match flag ~yes:"enable" ~no:"disable",
                              flag ~yes:"select" ~no:"unselect",
                              flag ~yes:"terminal" ~no:"no-terminal" with
                        | Error (a, b), _, _ | _, Error (a, b), _ | _, _, Error (a, b) ->
                            (reply_error ~code:"bad_argument"
                               ~detail:(Printf.sprintf
                                          "--%s and --%s cannot be given together" a b),
                             `Continue)
                        | Ok enable, Ok select, Ok terminal ->
                            (cmd_rc_set st ~timeout ~name:(arg0 r) ~field
                               ~from:(option_value r "from") ~inline:(arg_opt r 1) ~enable
                               ~select ~terminal,
                             `Continue)))
            (* One implementation for the four (§ 4.6): the verb only says which instance to
               read, the shape of the answer being the same. documents gets [None] by its
               arity, which takes no positional argument. *)
            | "ifconfig" | "defects" | "history" | "documents" ->
                (cmd_treeview st ~timeout ~which:r.verb ~name:(arg_opt r 0), `Continue)
            (* Same shape as --save/--no-save (episode 4d): the two options are mutually
               exclusive, and giving neither is legal — it is only refused later, and only if the
               node turns out to be running. *)
            | "ifconfig-set" | "defects-set" ->
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
                     ((if r.verb = "defects-set" then
                         (* The positional arguments are passed whole: their shape depends on the
                            treeview row aimed at, which only the GTK thread may read (episode 5c). *)
                         cmd_defects_set st ~timeout ~args:r.args ~restart
                       else
                         cmd_ifconfig_set st ~timeout ~node:(arg0 r) ~port:(arg_at r 1)
                           ~field:(arg_at r 2)
                           (* No fourth argument means the empty string: clearing a cell. *)
                           ~value:(match arg_opt r 3 with Some v -> v | None -> "")
                           ~restart),
                      `Continue))
            (* Episode 5d. No --restart/--no-restart here, and that is not an oversight: starting
               in a state IS the transition, and deleting a state or editing its comment touches
               no running device — the GUI asks nothing on these paths either. *)
            | "history-start" -> (cmd_history_start st ~timeout ~cow:(arg0 r), `Continue)
            | "history-del"   ->
                (cmd_history_del st ~timeout ~cow:(arg0 r)
                   ~except:(option_value r "except" <> None), `Continue)
            | "history-export" ->
                (cmd_history_export st ~timeout ~cow:(arg0 r) ~variant:(arg_at r 1)
                   ~force:(option_value r "force" <> None), `Continue)
            | "history-set"   ->
                (cmd_history_set st ~timeout ~cow:(arg0 r) ~field:(arg_at r 1)
                   (* No third argument means the empty string: clearing the cell. *)
                   ~value:(match arg_opt r 2 with Some v -> v | None -> ""), `Continue)
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
            (* Episode 3 of `journalisation-profonde'. Two refusals, both for the same reason a
               journal is asked for at all — to find out what went wrong; episode 5 gave them to
               [switch-info] too, hence [optional_choice_of], where they are now written. *)
            | "log" ->
                ((match optional_choice_of r ~verb:"log" ~option_name:"file" ~what:"journal"
                          ~other_options:[ "timeout"; "tail" ] with
                  | Error detail -> reply_error ~code:"bad_argument" ~detail
                  | Ok file      -> cmd_log st ~timeout ~name:(arg0 r) ~file
                                      ~tail:(option_value r "tail")),
                 `Continue)
            (* Episode 5: what the switch knows now, as opposed to what it wrote down. *)
            | "switch-info" ->
                ((match optional_choice_of r ~verb:"switch-info" ~option_name:"table"
                          ~what:"table" ~other_options:[ "timeout" ] with
                  | Error detail -> reply_error ~code:"bad_argument" ~detail
                  | Ok table     -> cmd_switch_info st ~timeout ~name:(arg0 r) ~table),
                 `Continue)
            (* Episode 16: same reading of --timeout as [wait] below — it bounds the wait for the
               guest's answer, not the round trip to the GTK main thread — and for the same
               reason: what is being waited for happens inside a guest. *)
            | "report" ->
                let wait_timeout =
                  match option_value r "timeout" with
                  | None   -> default_report_timeout
                  | Some _ -> timeout
                in
                (cmd_report st ~gtk_timeout:default_timeout ~wait_timeout ~name:(arg0 r),
                 `Continue)
            (* Episode 18: same reading of --timeout again, and here it bounds two things at once
               — the wait for the answer, and the command itself inside the guest. One option
               rather than two because they are the same promise from the client's side: "do not
               keep me longer than this", and a command still running when we stop waiting would
               be a process nobody owns. *)
            | "exec" ->
                let command_timeout =
                  match option_value r "timeout" with
                  | None   -> default_exec_timeout
                  | Some _ -> timeout
                in
                (* The one verb which MUST refuse an unknown option instead of ignoring it: an
                   option is recognised wherever it stands, so `exec m1 ls --all' would otherwise
                   run `ls' and say nothing about the --all it swallowed. The refusal is also
                   where the separator is taught — a message nobody reads is a message nobody
                   needed. *)
                ((match List.filter (fun (k, _) -> k <> "timeout") r.opts with
                  | (k, _) :: _ ->
                      reply_error ~code:"bad_argument"
                        ~detail:(Printf.sprintf
                                   "no option --%s here: exec takes only --timeout=<s>. An option \
                                    meant for the command itself must come after a bare --, as in \
                                    `exec %s -- ls --all'; without it, this channel would take \
                                    --%s for its own and run a mutilated command"
                                   k (arg0 r) k)
                  | [] ->
                      cmd_exec st ~gtk_timeout:default_timeout ~command_timeout ~name:(arg0 r)
                        ~command:(match arg_opt r 1 with Some c -> c | None -> "")),
                 `Continue)
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
            | "help"   -> (cmd_help ~verb:(arg_opt r 0), `Continue)
            | "quit"   -> cmd_quit st ~timeout
            | verb     -> (unknown_command_reply ~verb, `Continue)))

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

(* The socket is only as private as the directory holding it *as long as* the socket file
   keeps the 0777 mode Network.server gives it unconditionally (network.ml:231): a channel
   able to drive the whole session must not be reachable by anybody else (§ 3.4). We create
   the directory 0700 when missing. An existing one writable by group or others is refused
   — *unless* it carries the sticky bit (t): that is /tmp and friends, where a foreign user
   can create files but can neither unlink nor replace ours. Such a directory is a perfectly
   legitimate place for a control socket, and often the only one available before any project
   exists; what it does *not* provide is confidentiality, so there the protection moves to
   the socket file itself, which `start` tightens to 0600 right after the bind. *)
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
      else if (stats.Unix.st_perm land 0o022) <> 0 && (stats.Unix.st_perm land 0o1000) = 0 then
        Error (Printf.sprintf
                 "%S is writable by group or others without the sticky bit (mode 0%o): refusing to put a control socket there"
                 dir stats.Unix.st_perm)
      else
        let () =
          if (stats.Unix.st_perm land 0o022) <> 0 then
            Log.printf2
              "Control_server: %s is shared but sticky (mode 0%o): the socket file itself will protect the channel.\n"
              dir stats.Unix.st_perm
        in
        Ok ()

(* N12: a socket file may survive a brutal exit (SIGKILL, crash), and the bind would then
   fail with EADDRINUSE. Distinguish the two cases by connecting: someone answering means
   a live Marionnet is already serving there. *)
let someone_is_listening (path:string) : bool =
  let fd = Unix.socket ~cloexec:true Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  let result = try Unix.connect fd (Unix.ADDR_UNIX path); true with _ -> false in
  let () = try Unix.close fd with _ -> () in
  result

let prepare_socketfile (path:string) : (unit, string) result =
  (* Same check as the one already made when the option was read (initialization.ml): the
     bound of sun_path has a single source, and [start] stays correct on its own. *)
  match Initialization.check_control_socket_path path with
  | Error _ as e -> e
  | Ok () ->
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

(* Printexc.to_string alone says "Ocamlbricks.Network.Binding(_)", which tells whoever
   launched the session nothing at all: Network wraps the real cause (network.ml:190) and
   a Unix_error prints its own constructor rather than its message. Unwrap both. *)
let rec explain_failure : exn -> string = function
  | Network.Binding e -> Printf.sprintf "bind failed: %s" (explain_failure e)
  | Unix.Unix_error (code, fname, arg) ->
      Printf.sprintf "%s%s: %s"
        fname (if arg = "" then "" else Printf.sprintf " %S" arg) (Unix.error_message code)
  | e -> Printexc.to_string e

(* ~no_fork:() is mandatory: the default behaviour of Network.server is to fork per
   connection (network.ml:231), which in a GTK process owning UML children would be
   catastrophic. The bind happens in the calling thread (network.ml:223), so a failure is
   reported here and now — to the caller, which decides what to do with it. *)
let start (st : State.globalState) ~(socketfile:string) : (unit, string) result =
  match prepare_socketfile socketfile with
  | Error detail ->
      let () = Log.printf1 "Control_server: NOT started: %s\n" detail in
      Error detail
  | Ok () ->
      (try
        let () = Log.printf1 "Control_server: about to start Network.stream_unix_server on socketfile %s\n" socketfile in
        let (_thread, socketfile) =
           Network.stream_unix_server
             ~no_fork:()
             ~socketfile
             ~protocol:(session st)
             ()
         in
         (* Network.server chmod's the socket to 0777 (network.ml:231), which is harmless in
            a 0700 directory and wide open in a sticky shared one (/tmp): tighten it here.
            The clients (mrnctl, mrn-check, mrn-verify…) run as us, so 0600 costs nothing.
            The bind is already listening at this point, hence a race window of a few
            microseconds during which a local peer could connect; closing it entirely would
            mean binding in a private directory and rename(2)-ing the socket into place. *)
         let socket_mode =
           try let () = Unix.chmod socketfile 0o600 in "0600"
           with e -> Printf.sprintf "left as created (%s)" (Printexc.to_string e)
         in
         let () = Log.printf2 "Control_server: listening on %s (socket mode %s)\n" socketfile socket_mode in
         Ok ()
       with e ->
         let () = Log.print_exn ~prefix:"Control_server: NOT started: " e in
         Error (explain_failure e))

(* A driven session which cannot be driven has no reason to run (--control-socket implies
   script mode), and the failure must be seen by whoever launched it: the log is not under
   the eyes of a bench. Hence a refusal to start, on stderr, whatever the cause — a path
   we cannot write into, a socket already served by a live process, a bind failure. The
   syntax of the path itself has already been refused much earlier, before any window
   (initialization.ml).
   No attempt is made to close a project opened from the command line before leaving:
   st#close_project, called from the GTK main thread, merely spawns a thread (state.ml),
   which exit would kill before it cleans anything. A run directory left behind in that
   narrow case is the business of `bin/scripts/marionnet-cleanup.sh` and of the TODO entry
   about run directories. *)
let start_if_requested (st : State.globalState) : unit =
  match !Initialization.option_control_socket with
  | None -> ()
  | Some socketfile ->
      (match start st ~socketfile with
       | Ok () -> ()
       | Error detail ->
           Printf.kfprintf flush stderr
             "%s: --control-socket: cannot serve %s: %s\n" Sys.argv.(0) socketfile detail;
           exit 1)
