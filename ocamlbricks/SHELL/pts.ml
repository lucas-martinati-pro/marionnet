(* This file is part of ocamlbricks
   Copyright (C) 2020  Jean-Vincent Loddo
   Copyright (C) 2020  Université Sorbonne Paris Nord

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


(* Support for Linux's pseudo-terminals. *)

type filename = string (* Ex: "/dev/pts/10" *)
type pid = int

module Log = Ocamlbricks_log

exception Opening   of exn
exception Receiving of exn
exception Sending   of exn
exception Closing   of exn

(* Subset of Unix.terminal_io fields and settings relevant for pseudo-terminals: *)
module Settings = struct
  (* --- *)
  let c_cread  : bool = true   (* Reception is enabled. *)
  let c_isig   : bool = false  (* Generate signal on INTR, QUIT, SUSP. *)
  let c_icanon : bool = false  (* Enable canonical processing (line buffering and editing) *)
  let c_echo   : bool = false  (* Echo input characters. *)
  let c_echoe  : bool = false  (* Echo ERASE (to erase previous character). *)
  let c_opost  : bool = false  (* Enable output processing. *)
  (* --- *)
  let c_vmin   : int  = 1      (* Minimum number of characters to read before the read request is satisfied. *)
  let c_vtime  : int  = 10     (* Maximum read wait (in 0.1s units). 0 means no timeout *)
  (* --- *)
end (* Settings *)

(* Set the status of the terminal referred to by the given file descriptor. *)
let set_attributes_for_pts ?(c_vmin=Settings.c_vmin) ?(c_vtime=Settings.c_vtime) fd =
  let attrs = Unix.tcgetattr fd in
  let attrs =
    { attrs with
        Unix.c_cread  = Settings.c_cread;
             c_isig   = Settings.c_isig;
             c_icanon = Settings.c_icanon;
             c_echo   = Settings.c_echo;
             c_echoe  = Settings.c_echoe;
             c_vmin   = c_vmin;
             c_vtime  = c_vtime;
    }
  in
  let () = Unix.tcsetattr fd (**) Unix.TCSANOW (**) attrs in (* Now please! *)
  (* Unix.read calls must be blocking: *)
  let () = Unix.clear_nonblock fd in
  attrs

let get_c_vmin_attribute fd =
  let attrs = Unix.tcgetattr fd in
  attrs.Unix.c_vmin

let set_c_vmin_attribute ?attrs (fd) (c_vmin) =
  let attrs = match attrs with None -> Unix.tcgetattr fd | Some a -> a in
  let attrs = { attrs with Unix.c_vmin = c_vmin; } in
  let () = Unix.tcsetattr fd Unix.TCSANOW attrs in
  ()

(* From module Thunk: => Misc? *)
let protect (f:'a -> unit) : 'a -> unit =
 (fun x -> try f x with _ -> ())

(* Just for debugging: => Misc? *)
let pr fmt = Printf.kfprintf flush stderr fmt

class stream_channel ?(max_input_size=1514) ?(file_perm=0o666) (ptsname) = (* "/dev/pts/10" *)
  (* --- *)
  let fd0, fd1, exit_door0, exit_door1, attrs0, in_channel, out_channel =
    try
      let fd0 = Unix.openfile ptsname [ Unix.O_RDONLY; Unix.O_NONBLOCK; ] (file_perm) in
      let fd1 = Unix.openfile ptsname [ Unix.O_WRONLY; Unix.O_NONBLOCK; Unix.O_NOCTTY ] (file_perm) in
      (* --- *)
      let (exit_door0, exit_door1) = Unix.pipe () in
      (* --- *)
      let  attrs0 = set_attributes_for_pts fd0 in
      let _attrs1 = set_attributes_for_pts fd1 in
      (* --- *)
      let in_channel  = lazy (Unix.in_channel_of_descr  fd0) in
      let out_channel = lazy (Unix.out_channel_of_descr fd1) in
      (* --- *)
      (fd0, fd1, exit_door0, exit_door1, attrs0, in_channel, out_channel)
      (* --- *)
    with e ->
      let () = Log.print_exn ~prefix:"Pts.stream_channel#constructor: FAILED: " e in
      raise e
  in
  (* --- *)
  let raise_but_also_log_it ?sending caller e =
    let prefix = Printf.sprintf "Pts.stream_channel#%s: " caller in
    let () = Log.print_exn ~prefix e in
    if sending=None then raise (Receiving e) else raise (Sending e)
  in
  (* --- *)
  let tutor0 f x caller =
    try f x with e -> raise_but_also_log_it caller e
  in
  (* --- *)
  let tutor1 f x y caller =
    try f x y; flush x with e -> raise_but_also_log_it ~sending:() caller e
  in
  (* --- *)
  let return_of_at_least (at_least) =
    let fd, attrs = fd0, attrs0 in
    match at_least with
    | None -> fun y -> y
    | Some m ->
	let previous = get_c_vmin_attribute fd in
        let () = set_c_vmin_attribute ~attrs (fd) (m) in
	fun y ->
	  (* restore the previous value and return: *)
	  let () = set_c_vmin_attribute ~attrs (fd) (previous) in
	  y
  in
  (* --- *)
  object (self)

  val input_buffer = Bytes.create max_input_size
  val max_input_size = max_input_size

  method private is_channel_active () : bool =
    let succeed f x : bool = try let _ = f x in true with _ -> false in (* DOVE METTERLA (Misc?) *)
    List.for_all (succeed Unix.fstat) [fd0; fd1; exit_door0; exit_door1]

  method receive ?at_least () : string =
    let fd = fd0 in
    let return = return_of_at_least (at_least) in
    try
      (* let n = Unix.read fd input_buffer 0 max_input_size in *)
      let n = ThreadExtra.read_with_exit_door ~exit_door:(exit_door0) fd input_buffer 0 max_input_size in
      (if n=0 then failwith "received 0 bytes (peer terminated?)");
      return (String.sub input_buffer 0 n)
    with e ->
      Log.print_exn ~prefix:"Pts.stream_channel#receive: " e;
      let _ = return "" in
      raise (Receiving e)

  method peek ?(at_least=0) () : (string, string) Either.t =
    let fd = fd0 in
    try
      Unix.set_nonblock fd;
      let n = Unix.read fd input_buffer 0 max_input_size in
      Unix.clear_nonblock fd;
      let received = (String.sub input_buffer 0 n) in
      if n>=at_least
       then
         Either.Right (received)
       else
         let () = if at_least>0 then Log.printf2 "Pts.stream_channel#peek: received %d bytes (expected at least %d)\n" n at_least in
         Either.Left (received)
    with e ->
      Unix.clear_nonblock fd;
      Log.print_exn ~prefix:"Pts.stream_channel#peek: result is empty because of exception: " e;
      (* In case of exception, we consider that we are wrong (Either.Left)
         and we have received nothing, i.e the empty string: *)
      Either.Left ("")

  method send (x:string) : unit =
    let fd = fd1 in
    let rec send_stream_loop x off len =
      if len=0 then () else
      let n = Unix.write (fd) x off len in
      if n = 0 then failwith "failed to send in a stream channel: no more than 0 bytes sent!" else
      if n<len then send_stream_loop x (off+n) (len-n) else
      ()
    in
    try
      send_stream_loop x 0 (String.length x)
    with e ->
      Log.print_exn ~prefix:"Pts.stream_channel#send: " e;
      raise (Sending e)

  (* This method causes an error on (Unix.read fd0) *)
  method walk_through_the_exit_door () =
    Either.protect Unix.close exit_door1

  method shutdown ?receive ?send () =
    (* --- *)
    let close_in_channel  () = if Lazy.is_val (in_channel)  then close_in  (Lazy.force in_channel)  else () in
    let close_out_channel () = if Lazy.is_val (out_channel) then close_out (Lazy.force out_channel) else () in
    (* --- *)
    (* Anyway close exit doors. Note that :: compose in the reverse order w.r.t. ";" or "let-in" ... *)
    let ys1 : (exn, unit) Either.t list =
      (Either.protect Unix.close exit_door0) ::
      (Either.protect Unix.close exit_door1) :: (* ... so this descriptor is the first closed *)
      []
    in
    (* --- *)
    let ys2 : (exn, unit) Either.t list =
     (match receive, send with
      | Some (), None -> (Either.protect Unix.close fd0) :: (Either.protect close_in_channel  ()) :: []
      | None, Some () -> (Either.protect Unix.close fd1) :: (Either.protect close_out_channel ()) :: []
      | _ , _         -> (Either.protect Unix.close fd1) :: (Either.protect Unix.close fd0) ::
                         (Either.protect close_out_channel ()) :: (Either.protect close_in_channel ()) :: []
      )
    in
    (* --- *)
    try
      (* Re-raise the first occurred exception, but *all* close operations have been performed: *)
      Either.raise_first_if_any (List.append ys1 ys2);
      Log.printf "Pts.stream_channel#shutdown: Done.\n"
      (* --- *)
    with e ->
      Log.printf "Pts.stream_channel#shutdown: Done (ignoring exceptions)\n";
      raise (Closing e)

  method get_IO_file_descriptors : Unix.file_descr * Unix.file_descr =
    (fd0, fd1)

  method input_char       () : char   = tutor0 Pervasives.input_char (Lazy.force in_channel) "input_char"
  (* Something goes wrong with this method => I remove it from the interface: *)
  (* method input_line       () : string = tutor0 Pervasives.input_line (Lazy.force in_channel) "input_line" *)
  method input_byte       () : int    = tutor0 Pervasives.input_byte (Lazy.force in_channel) "input_byte"
  method input_binary_int () : int    = tutor0 Pervasives.input_binary_int (Lazy.force in_channel) "input_binary_int"
  method input_value         : 'a. unit -> 'a = fun () -> tutor0 Pervasives.input_value (Lazy.force in_channel) "input_value"

  method output_char   x = tutor1 Pervasives.output_char (Lazy.force out_channel) x "output_char"
  method output_line   x = tutor1 Pervasives.output_string (Lazy.force out_channel) (x^"\n") "output_line"
  method output_byte   x = tutor1 Pervasives.output_byte (Lazy.force out_channel) x "output_byte"
  method output_binary_int x = tutor1 Pervasives.output_binary_int (Lazy.force out_channel) x "output_binary_int"
  method output_value : 'a. 'a -> unit =
    fun x -> tutor1 Pervasives.output_value (Lazy.force out_channel) x "output_value"

end (* class stream_channel *)


module Apply_protocol = struct

(* val as_call   : ?max_input_size:int -> ?file_perm:int -> filename:string -> protocol:(stream_channel -> 'a) -> unit ->  (exn,'a) Either.t *)
let as_call ?max_input_size ?file_perm ~filename ~protocol () =
  try
  (* --- *)
    let ch = new stream_channel ?max_input_size ?file_perm (filename) in
    (* --- *)
    Log.printf1 "Pts.Apply_protocol.as_call: about to running protocol for connection on %s\n" filename;
    let result = Either.protect (protocol) (ch) in
    let () = protect ch#shutdown () in
    result
  (* --- *)
  with e ->
    let () = Log.printf1 "Pts.Apply_protocol.as_call: FAILED creating new stream_channel for %s\n" filename in
    Either.Left (Opening e)

  (* val as_thread : ?max_input_size:int -> ?file_perm -> protocol:(stream_channel -> 'a) -> filename -> (exn,'a) Either.t Future.t *)
  let as_thread ?max_input_size ?file_perm ~filename ~protocol () =
    Future.thread (as_call ?max_input_size ?file_perm ~filename ~protocol) ()

  (* val as_fork   : ?max_input_size:int -> ?file_perm:int -> filename:string -> protocol:(stream_channel -> 'a) -> unit -> ((exn,'a) Either.t Future.t) * pid *)
  let as_fork ?max_input_size ?file_perm ~filename ~protocol () =
    Future.fork (as_call ?max_input_size ?file_perm ~filename ~protocol) ()

end (* Apply_protocol *)
