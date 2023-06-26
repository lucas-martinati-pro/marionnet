(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008  Luca Saiu
   Copyright (C) 2011  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2011  Université Paris 13

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
module Option = Ocamlbricks.Option
module StringExtra = Ocamlbricks.StringExtra
module UnixExtra = Ocamlbricks.UnixExtra
module Network = Ocamlbricks.Network
(* --- *)
let pr = Ocamlbricks.Misc.pr
(* --- *)

type display_number = int

(* For desperate cases: *)
let try_to_fix_DISPLAY () : display_number option =
  let rec loop n =
    if n>=1000 then None else (* continue *)
    let cmd = Printf.sprintf "DISPLAY=:%d.0 xset -q 2>/dev/null 1>/dev/null" n in
    match (Unix.system cmd) with
    | Unix.WEXITED 127 -> None (* xset probably not installed *)
    | Unix.WEXITED 0 ->
        let () = Log.printf1 "DISPLAY fixed to value :%d.0\n" n in
        let () = Unix.putenv "DISPLAY" (Printf.sprintf ":%d.0" n) in
        Some n
    | _ -> loop (n+1)
  in
  loop 0

(** The syntax of $DISPLAY is: [host]:display[.screen] *)
let get_host_display_screen_from_string =
 let fail x = failwith (Printf.sprintf "Ill-formed DISPLAY string: '%s'" x) in
 fun x ->
  let split_rigth_part y =
    match (StringExtra.split ~d:'.' y) with
    | [ display; screen ] -> (display, screen)
    | [ display ]         -> (display, "0")
    | _ -> fail x
  in
  let host, (display, screen) =
    match (StringExtra.split ~d:':' x) with
    | [ host; right_part ] -> host, (split_rigth_part right_part)
    | [ right_part ]       -> "localhost", (split_rigth_part right_part)
    | _ -> fail x
  in
  let strip_and_use_default_if_empty ~default x=
    let x = StringExtra.strip x in
    if x = "" then default else x
  in
  let host    = strip_and_use_default_if_empty ~default:"localhost" host in
  let screen  = strip_and_use_default_if_empty ~default:"0" screen in
  let display = StringExtra.strip display in
  (host, display, screen)

(* --- *)
let get_host_display_screen () =
  try
    let x = Sys.getenv "DISPLAY" in
    let x =
      if x<>"" then x else
      match try_to_fix_DISPLAY () with
      | None   -> raise Not_found (* It's just like it weren't defined... *)
      | Some n -> Sys.getenv "DISPLAY"
    in
    get_host_display_screen_from_string x
  (* --- *)
  with Not_found ->
    failwith "The environment variable DISPLAY is not defined or empty, and Marionnet requires X.\nBailing out...";;

(* Redefinition: *)
let get_host_display_screen () =
 try  get_host_display_screen ()
 with _ -> begin
   ignore (try_to_fix_DISPLAY ());
   get_host_display_screen ()
   end

(* Global variables: *)
let host, display, screen =
  get_host_display_screen ()

(* --- *)
let get_cookie_by_xauth ?(display="0") ?(screen="0") () : string option =
  let command = Printf.sprintf "xauth list :%s.%s" display screen in
  let result, code = UnixExtra.run (command) in
  if code <> Unix.WEXITED 0 then None else (* continue: *)
  let xss = StringExtra.Text.Matrix.of_string result in (* [["socrates/unix:12"; "MIT-MAGIC-COOKIE-1"; "0fca956092856af8f4cfae3951f837e7"]] *)
  match xss with
  | [hostname; "MIT-MAGIC-COOKIE-1"; cookie]::_ -> Some cookie
  | _ -> None

(* Global variable set to the MIT-MAGIC-COOKIE-1 of the current display and screen: *)
let mit_magic_cookie_1 : string option =
  get_cookie_by_xauth ~display ~screen ()

(* Just an alias: *)
let cookie = mit_magic_cookie_1

let socket_file_of_index (index) =
  Printf.sprintf "/tmp/.X11-unix/X%i" (index)

(* Useful for xnest: *)
let get_unused_local_display =
  let _last_used_local_display_index = ref 0 in
  let mutex = Mutex.create () in
  fun () ->
    Mutex.lock mutex;
    let exists pathname =
      try
        ignore (Unix.stat pathname);
        true;
      with _ ->
        false in
    let i = ref (!_last_used_local_display_index + 1) in
    while exists (socket_file_of_index !i) do
      i := !i + 1;
    done;
    _last_used_local_display_index := !i;
    Mutex.unlock mutex;
    Printf.sprintf ":%i" !i

(* --- *)
let get_unused_local_display_number ?(starting_from=0) () : display_number =
  let rec loop i =
    if Sys.file_exists (socket_file_of_index i) then loop (i+1) else i
  in
  loop (starting_from)

(* ---------------------------------------------------------------------------*)
module Settings_at_loading_time : sig
(* ---------------------------------------------------------------------------*)
   val guest_display   : int ref
   val xserver_address : Network.server_address option ref
  end
(* --------------------------------------------------------*)
= struct

(* Note that this function really tries to establish a connection (which is immediately closed).
   Do not use with a one-shot service (it must accept more than one connection): *)
let is_local_AF_INET_service_open ?(host_addr:string option) ~(port:int) () =
  let host_addr = match host_addr with
    | None     -> Unix.inet_addr_loopback
    | Some str -> Unix.inet_addr_of_string str
  in
  try
    let (in_channel, out_channel) = Unix.open_connection (Unix.ADDR_INET(host_addr, port)) in
    Unix.shutdown_connection in_channel;
    true
  with
   | Unix.Unix_error (Unix.ECONNREFUSED, _,_) -> false
   | _ -> false

type port_number = int
(* --- *)
let get_unused_local_AF_INET_port_number ?(starting_from=6000) () : port_number =
  let rec loop i =
    if is_local_AF_INET_service_open ~port:i () then loop (i+1) else i
  in
  loop (starting_from)

(* Global variables: *)
let host_addr = Unix.string_of_inet_addr ((Unix.gethostbyname host).Unix.h_addr_list.(0))
and port = 6000 + (try (int_of_string display) with _ -> 0)
(* --- *)
(* TODO: after several crashes debugging marionnet.native, a new call stucks here: *)
let () = Log.printf2 "x.ml: trying to connect to connect to host %s on port %d ...\n" host_addr port
(* --- *)
(* Global variable: *)
let is_X_server_listening_TCP_connections =
  is_local_AF_INET_service_open ~host_addr ~port ()
(* --- *)
let () =
  Log.printf7
    "---\nHost X data from $DISPLAY:\nHost: %s\nHost address: %s\nDisplay: %s\nScreen: %s\nCookie: %s\nListening on port %d: %b\n---\n"
    host host_addr
    display
    screen
    (Ocamlbricks.Option.extract_or cookie "None")
    port
    is_X_server_listening_TCP_connections

(* exception No_problem *)
(* exception No_listening_server *)

let ignore_but_notify ?do_not_fail (thunk) () =
 try ignore (thunk ())
 with e ->
   begin
     Log.printf1 "Exception raised: %s\n" (Printexc.to_string e);
     Log.printf  "*** Are there many instances of marionnet running on the same host? ***\n";
     if do_not_fail = None then raise e else ();
   end

(* By default the display number for the guest is the same of the host: *)
let guest_display = ref (port - 6000)

(* This reference is initialized here as first approximation.
   May be changed by the section `fix_X_problems': *)
let xserver_address = ref (Some (`inet (host_addr, port)))

(* Try to fix problems defining at the same time the good value for `guest_display'.
   If required and possible, we will try to launch a pseudo X server running on port 6000.
   In this way, the *old* virtual machines (debian-lenny, pinocchio, ...) which suppose
   DISPLAY=172.23.0.254:0 will to be able to connect to the host X server.
   Instead, new machines will be able even when guest_display<>0.
*)
let fix_X_problems : unit =
  (* --- *)
  let socketfile = Printf.sprintf "/tmp/.X11-unix/X%s" display in
  let socketfile_exists = Sys.file_exists socketfile in
  (* --- *)
  let no_fork = None (* Yes fork, i.e. create a process for each connection *) in
  (* let no_fork = Some () (* use Marionnet's threads *) in *)
  (* --- *)
  (* let range4 = "172.23.0.0/24" in *)
  let range4 = "0.0.0.0/0" in
  let range6 = "fe80::/64" in
  (* --- *)
  let warning (available_port) (case) =
    if available_port <> 6000 then
      match mit_magic_cookie_1 with
      (*--- *)
      | None ->
          Log.printf3
            "%s WARNING: to enable X on old virtual machines set: DISPLAY=172.23.0.254:%d.%s\n"
            case (!guest_display) (screen)
      (*--- *)
      | Some mit_magic_cookie_1 ->
          Log.printf5
            "%s WARNING: to enable X on old virtual machines set:\n---\nDISPLAY=172.23.0.254:%d.%s\nxauth add 172.23.0.254:%d . %s\n---\n"
            case (!guest_display) (screen) (!guest_display) (mit_magic_cookie_1)
  in
  (* --- *)
  match is_X_server_listening_TCP_connections, host_addr with

  (* Case n°1: an X server runs on localhost:0 and accepts TCP connection: *)
  | true,  "127.0.0.1" when port=6000 ->
      Log.printf "(case 1) No X problems have to be fixed: connection seems working fine. Ok.\n"

  (* Case n°2: an X server runs on localhost and accepts TCP connection,
      but on a display Y<>0. We morally set up a PAT (Port Address Translation)
      172.23.0.254:6000 -> 127.0.0.1:(6000+Y) simply using the unix socket.
      If 6000 is busy by another process (X server), we will find a free port number.
      Supposing 6042 be the first port number free after 6000, the PAT will be:
      172.23.0.254:6042 -> 127.0.0.1:(6000+Y) and guest_display=42  *)
  | true,  "127.0.0.1" when port<>6000 && socketfile_exists ->
      (* Equivalent to: socat TCP-LISTEN:6000,fork,reuseaddr UNIX-CONNECT:/tmp/.X11-unix/X? *)
      let available_port = get_unused_local_AF_INET_port_number ~starting_from:6000 () in
      let () = guest_display := (available_port - 6000) in
      let () = Log.printf2 "(case 2) Starting a socat service: 0.0.0.0:%d -> %s\n" available_port socketfile in
      let () = warning (available_port) "(case 2)" in
      (* --- *)
      let target = (`unix socketfile) in
      let () = xserver_address := Some target in
      (* --- *)
      ignore_but_notify
        ~do_not_fail:()
        (Network.Socat.dual_inet_of_stream_server ?no_fork ~range4 ~range6 ~port:available_port ~target) ()

  (* Case n°3: an X server seems to run on localhost accepting TCP connection,
      but the display is Y<>0 and there isn't a corresponding unix socket.
      This is quite unusual: we are probably in a ssh -X connection.
      We have to pay attention to the fact that processes asking for a connexion
      are not from the machine 127.0.0.1 but are from the virtual machines 172.23.0.0/24.
      Note that the following command doesn't solve completely the problem: we have also to
      provide the X cookies in ~/.Xauthority to the virtual machines. *)
  | true,  "127.0.0.1" when port<>6000 && (not socketfile_exists) ->
      (* Equivalent to: socat TCP-LISTEN:6000,fork,reuseaddr TCP:host_addr:port *)
      let available_port = get_unused_local_AF_INET_port_number ~starting_from:6000 () in
      let () = guest_display := (available_port - 6000) in
      let () = Log.printf3 "(case 3) Starting a socat service: 0.0.0.0:%d -> %s:%d\n" available_port host_addr port in
      let () = warning (available_port) "(case 3)" in
      (* --- *)
      let target = `inet(host_addr,port) in
      let () = xserver_address := Some target in
      (* --- *)
      ignore_but_notify
        ~do_not_fail:()
        (Network.Socat.dual_inet_of_stream_server ?no_fork ~range4 ~range6 ~port:available_port ~target) ()

  (* Case n°4: probably a telnet or a ssh -X connection.
      Idem: the following command doesn't solve completely the problem: we have also to
      provide the X cookies in ~/.Xauthority to the virtual machines.    *)
  | true,  _  (* when host_addr<>"127.0.0.1" *) ->
      (* Equivalent to: socat TCP-LISTEN:6000,fork,reuseaddr TCP:host_addr:port *)
      let available_port = get_unused_local_AF_INET_port_number ~starting_from:6000 () in
      let () = guest_display := (available_port - 6000) in
      Log.printf3 "(case 4) Starting a socat service: 0.0.0.0:%d -> %s:%d\n" available_port host_addr port;
      let () = warning (available_port) "(case 4)" in
      (* --- *)
      let target = `inet(host_addr,port) in
      let () = xserver_address := Some target in
      (* --- *)
      ignore_but_notify
        ~do_not_fail:()
        (Network.Socat.dual_inet_of_stream_server ?no_fork ~range4 ~range6 ~port:available_port ~target) ()

  (* Case n°5: an X server seems to run on localhost but it doesn't accept TCP connections.
      We simply redirect connection requests to the unix socket: *)
  | false, "127.0.0.1" when socketfile_exists ->
      (* Equivalent to: socat TCP-LISTEN:6000,fork,reuseaddr UNIX-CONNECT:/tmp/.X11-unix/X? *)
      let available_port = get_unused_local_AF_INET_port_number ~starting_from:6000 () in
      let () = guest_display := (available_port - 6000) in
      Log.printf2 "(case 5) Starting a socat service: 0.0.0.0:%d -> %s\n" available_port socketfile;
      let () = warning (available_port) "(case 5)" in
      (* --- *)
      let target = (`unix socketfile) in
      let () = xserver_address := Some target in
      (* --- *)
      ignore_but_notify
        ~do_not_fail:()
          (Network.Socat.dual_inet_of_stream_server ?no_fork ~range4 ~range6 ~port:available_port ~target) ()

  | false, _ ->
      let () = xserver_address := None in
      Log.printf "(case 6) Warning: X connections are not available for virtual machines.\n"
;;

(** This has to be performed *early* in the initialization process: *)
let _ = GtkMain.Main.init ();;

(** This is a workaround for some threading issues suggested by Jacques Garrigue;
    it's needed to be able to use the 'run' method in GTK and Glade objects
    without preventing other unrelated threads to run: *)
let _ =
  GMain.Timeout.add ~ms:100 ~callback:(fun () -> Thread.delay 0.001; true);;

(* ------------------------------------------*)
end (* Settings_at_loading_time *)
(* ------------------------------------------*)

let guest_display =
  string_of_int (!(Settings_at_loading_time.guest_display))

let guest_display_dot_screen =
  Printf.sprintf "%s.%s" (guest_display) (screen)

let xserver_address =
  !(Settings_at_loading_time.xserver_address)

let () =
  let v = Option.to_string ~a:(Network.string_of_server_address) (xserver_address) in
  Log.printf2 "Report on X11 diagnostics and settings:  DISPLAY: %s  XSERVER: %s\n" (guest_display_dot_screen) (v)
