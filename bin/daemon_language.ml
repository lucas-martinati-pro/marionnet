(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2008  Luca Saiu
   Copyright (C) 2010  Jean-Vincent Loddo
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


(** The Marionnet daemon is controlled by a simple command language. Messages
    are passed as strings over sockets, which are printed from [parsed to]
    very simple abstract syntax terms. *)

(* --- *)
module Log = Marionnet_log
module Ipv4 = Ocamlbricks.Ipv4
module UnixExtra = Ocamlbricks.UnixExtra
module StringExtra = Ocamlbricks.StringExtra
(* --- *)

(** Tap names and bridge names are just strings: *)
type tap_name    = string
 and bridge_name = string
 and ip_address  = string
 and uid         = int

(** The abstract syntax of requests, responses and parameters: *)
type resource_pattern =
  | AnyTap of uid * ip_address
  | AnySocketTap of uid * bridge_name

type resource =
  | Tap of tap_name
  | SocketTap of tap_name * uid * bridge_name
 (* --- *)
 and daemon_request =
  | IAmAlive
  | Make of resource_pattern
  | Destroy of resource
  | DestroyAllMyResources
 (* --- *)
 and daemon_response =
  | Success
  | Error of string
  | Created of resource
  | SorryIThoughtYouWereDead;;

(* Checked daemon request: *)
type secure_daemon_request = (daemon_request, error_string) Either.t
 and error_string = string

(** Printer: this is useful for debugging. *)
let string_of_daemon_resource resource =
  match resource with
  | Tap tap_name ->
      Printf.sprintf "(tap %s)" tap_name
  | SocketTap(tap_name, uid, bridge_name) ->
      Printf.sprintf "(socket-tap %s %i %s)" tap_name uid bridge_name

let rec string_of_daemon_resource_pattern resource_pattern =
  match resource_pattern with
  | AnyTap(uid, ip_address) ->
      Printf.sprintf "(any-tap %i %s)" uid ip_address
  | AnySocketTap(uid, bridge_name) ->
      Printf.sprintf "(any-socket-tap %i %s)" uid bridge_name
(* --- *)
and string_of_daemon_request request =
  match request with
  | IAmAlive ->
      "i-am-alive"
  | Make resource_pattern ->
      Printf.sprintf "(make %s)" (string_of_daemon_resource_pattern resource_pattern)
  | Destroy resource ->
      Printf.sprintf "(destroy %s)" (string_of_daemon_resource resource)
  | DestroyAllMyResources ->
      "destroy-all-my-resources"
(* --- *)
and string_of_daemon_response response =
  match response with
  | Success ->
      "success"
  | SorryIThoughtYouWereDead ->
      "sorry-i-thought-you-were-dead"
  | Error message ->
      Printf.sprintf "(error \"%s\")" message
  | Created resource ->
      Printf.sprintf "(created %s)" (string_of_daemon_resource resource);;

(** The length of all requests and responses in our protocol: *)
let message_length = 128;;

(** Return a fixed-length string of exactly message_length bytes, where the first
    character is the given opcode, the following characters are the given parameters,
    and the remaining characters, if any, are filled with spaces. The length of the
    parameter is checked: *)
let make_fixed_length_message opcode parameter =
  let parameter =
    if ((String.length parameter) + 1) > message_length then begin
      Log.printf1 "Warning: the parameter \"%s\" is too long. Truncating...\n" parameter;
      String.sub parameter 0 ((String.length parameter) - 1)
    end else
      parameter in
  (Printf.sprintf "%c" opcode) ^
  parameter ^
  (String.make (message_length - (String.length parameter) - 1) ' ');;

(** Request printer (this is for the actually communication language, not for
    debugging): *)
let print_request request =
  match request with
  | IAmAlive ->
      make_fixed_length_message 'i' ""
  | Make AnyTap(uid, ip_address) ->
      make_fixed_length_message 'c' (Printf.sprintf "%i %s" uid ip_address)
  | Make (AnySocketTap(uid, bridge_name)) ->
      make_fixed_length_message 'g' (Printf.sprintf "%i %s" uid bridge_name)
  | Destroy (Tap tap_name) ->
      make_fixed_length_message 'd' tap_name
  | Destroy (SocketTap(tap_name, uid, bridge_name)) ->
      make_fixed_length_message 'D' (Printf.sprintf "%s %i %s" tap_name uid bridge_name)
  | DestroyAllMyResources ->
      make_fixed_length_message '!' "";;

(** Response printer (this is for the actually communication language, not for
    debugging): *)
let print_response response =
  match response with
  | Success ->
      make_fixed_length_message 's' ""
  | Error message ->
      make_fixed_length_message 'e' message
  | Created (Tap tap_name) ->
      make_fixed_length_message 'c' tap_name
  | Created (SocketTap(tap_name, uid, bridge_name)) ->
      make_fixed_length_message
        'C'
        (Printf.sprintf "%s %i %s" tap_name uid bridge_name)
  | SorryIThoughtYouWereDead ->
      make_fixed_length_message '!' "";;

let remove_trailing_spaces string =
  let rec index_of_the_last_nonblank string index =
    (* We return -1 if the string is completely made of spaces. This is
       coherent with the way we use this local funcion below. *)
    if index = -1 then
      -1
    else if String.get string index = ' ' then
      index_of_the_last_nonblank string (index - 1)
    else
      index
  in
  String.sub
    string
    0
    (1 + (index_of_the_last_nonblank string ((String.length string) - 1)));;

(** Return the opcode and parameter of the given message: *)
let split_message message =
  assert((String.length message) = message_length);
  let opcode = String.get message 0 in
  let rest = String.sub message 1 (message_length - 1) in
  let parameter = remove_trailing_spaces rest in
  opcode, parameter;;

(* The function is the identity function if the argument is correct.
   Otherwise it raises an exception. *)
let checked_address ?accepted_address_prefix x =
  let () = Log.printf1 "Checking string IPv4 address '%s'\n" x in
  let validated_prefix =
    match accepted_address_prefix with
    | None -> true
    | Some p ->
        let lp = (String.length p) in
        let lx = (String.length x) in
        (lp <= lx) && ((String.sub x 0 lp) = p)  (* is p a prefix of x? *)
  in
  if validated_prefix && (Ipv4.String.is_valid_ipv4 x)
    then x
    else failwith ("Invalid IPv4 address: "^x)

(* The function is the identity function if the bridge name appears as word in the
   output of the command `brctl show'. Otherwise it raises an exception. *)
let existing_bridge_name x =
  let () = Log.printf1 "Checking bridge name '%s'\n" x in
  let (code, s, _) = UnixExtra.create_process_and_wait_then_get_result "brctl" ["show"] in
  if code <> 0 then failwith ("The command `brctl show' failed") else (* continue: *)
  let s = StringExtra.map (function '\n' -> ' ' | '\t' -> ' ' | c -> c) s in
  let xs = StringExtra.split s in  (* ["bridge"; "name\tbridge"; "id\t\tSTP"; "enabled\tinterfaces\n"; ... ] *)
  if List.exists ((=)x) xs then x else failwith ("Unknown bridge name: "^x)

(* The function is the identity function if the argument is correct.
   Otherwise it raises an exception. *)
let checked_tap_name (accepted_tap_prefixes) (tap_name) =
  let is_prefix_and_rest_is_int x =
    try
      let lx = (String.length x) in
      let lt = (String.length tap_name) in
         (lt > lx)
      && ((String.sub tap_name 0 lx) = x)                       (* is x a prefix of tap_name? *)
      && (int_of_string (String.sub tap_name lx (lt-lx)) >= 0)  (* is the rest a positive integer? *)
    with _ -> false
  in
  if List.exists (is_prefix_and_rest_is_int) accepted_tap_prefixes
    then (tap_name)
    else failwith ("Invalid tap name: "^tap_name)

(* Either.t injections renamed for code documentation: *)
let checked = Either.left
let error   = Either.right

(* Called by server (marionnet-daemon). *)
let parse_request
  ?accepted_address_prefix
  ?(accepted_tap_prefixes=[])
  ~(ownership: resource -> bool)
  ~(uid_consistency: uid -> bool)
  (request)
  : secure_daemon_request
  =
  let (opcode, parameter) = split_message request in
  try begin
    match opcode with
    | 'i' -> checked IAmAlive
    (* --- *)
    | 'c' ->
        Scanf.sscanf parameter "%i %s"
          (fun uid ip_address ->
            let ip_address = checked_address ?accepted_address_prefix (ip_address) in
            checked (Make (AnyTap(uid, ip_address))))
    (* --- *)
    | 'g' ->
        Scanf.sscanf parameter "%i %s"
          (fun uid bridge_name ->
            let bridge_name = existing_bridge_name (bridge_name) in
            checked (Make (AnySocketTap(uid, bridge_name))))
    (* --- *)
    | 'd' ->
        let resource = (Tap parameter) in
        if ownership resource
          then checked (Destroy resource)
          else error ("You are not the owner of "^parameter)
    (* --- *)
    | 'D' ->
        (* Note that the default accepted_tap_prefixes=[] implies that any tap_name has no chances to be accepted.
           Thus, the caller (marionnet-daemon) has to define a non empty list of prefixes: *)
        Scanf.sscanf parameter "%s %i %s"
          (fun tap_name uid bridge_name ->
            (* Values checking: *)
            let tap_name = checked_tap_name (accepted_tap_prefixes) (tap_name) in
            let bridge_name = existing_bridge_name (bridge_name) in
            (* --- *)
            let resource = SocketTap(tap_name, uid, bridge_name) in
            if (ownership resource) && (uid_consistency uid)
              then checked (Destroy resource)
              else error ("You are not the owner or yours references are not consistent about the ressource "^parameter))
    (* --- *)
    | '!' ->
        checked DestroyAllMyResources
    (* --- *)
    | _ ->
        failwith ("Could not parse the request \"" ^ request ^ "\"")
  end (* try *)
  with
    | Failure msg -> error msg
    | e           -> error (Printexc.to_string e)

(* Called by client (marionnet): *)
let parse_response response  =
  let (opcode, parameter) = split_message response in
  match opcode with
  | 's' -> Success
  | 'e' -> Error parameter
  | 'c' -> Created (Tap parameter)
  | 'C' ->
      Scanf.sscanf
        parameter
        "%s %i %s"
        (fun tap_name uid bridge_name ->
          Created (SocketTap(tap_name, uid, bridge_name)))
  | '!' -> SorryIThoughtYouWereDead
  | _ -> failwith ("Could not parse the response \"" ^ response ^ "\"");;

(** We need to handle SIGPIPE when working with sockets, as a SIGPIPE
    is the visible effect of an interrupted primitive at the OCaml level.
    Not doing this leads to extremely nasty bugs, very hard to reproduce.
    This may not the "correct" module to implement this, but in this way
    I'm sure that every process, both Marionnet (client) and the daemon
    (server) always handle the signal. *)
let signal_handler =
  fun signal ->
    Log.printf1 "=========================\nI received the signal %i!\n=========================\n" signal;
    (* Raise an exception instead of silently killing a process... *)
    failwith (Printf.sprintf "got the signal %i" signal);;

let _ =
  Sys.set_signal Sys.sigpipe (Sys.Signal_handle signal_handler)
;;
