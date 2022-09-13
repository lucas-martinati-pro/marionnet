(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009 Jean-Vincent Loddo

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

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

#load "include_type_definitions_p4.cmo";;
INCLUDE DEFINITIONS "../../../../lib/STRUCTURES/ipv4.mli"
;;

(** Example: [23 -> (255,255,254,0)] *)
let netmask_of_cidr x =
  let invalid_arg () =
    invalid_arg
      (Printf.sprintf
         "Ipv4.netmask_of_cidr: netmask in CIDR notation %d out of the range 0..32" x)
  in
  (* Return a byte from a cidr in the range [0..8]. Example: 1 -> 128 *)
  let byte_of_cidr x =
    let rec loop c = if c=0. then 0. else (loop (c -. 1.)) +. (2. ** (8. -. c))
    in int_of_float (loop (float_of_int x))
  in
  if not ((x>=0) && (x<=32))
   then invalid_arg ()
   else
   let rec loop i acc c =
    if i > 4 then acc else
    if c>8 then (loop (i+1) (255::acc) (c-8))
           else (loop (i+1) ((byte_of_cidr c)::acc) 0)
   in
   match (loop 1 [] x) with
   | [n4;n3;n2;n1] -> (n1,n2,n3,n4)
   | _ -> assert false


(** Example: [(255,255,254,0) -> 23] *)
let cidr_of_netmask (n1,n2,n3,n4) =
  let invalid_arg () =
    invalid_arg
      (Printf.sprintf "Ipv4.cidr_of_netmask: ill-formed netmask %i.%i.%i.%i" n1 n2 n3 n4)
  in
  (* Return a cidr in the range [0..8] from a byte. Example: 128 -> 1. *)
  let cidr_of_byte = function
  | 0   -> 0 | 128 -> 1 | 192 -> 2 | 224 -> 3
  | 240 -> 4 | 248 -> 5 | 252 -> 6 | 254 -> 7
  | 255 -> 8
  | x   -> invalid_arg ()
  in
  let xs = List.map cidr_of_byte [n1;n2;n3;n4] in
  match xs with
  | [_;0;0;0] | [8;_;0;0] | [8;8;_;0] | [8;8;8;_] -> List.fold_left (+) 0 xs
  | _ -> invalid_arg ()


(** Example: ["255.255.248.0" -> (255, 255, 248, 0)] *)
let netmask_of_string s =
  let invalid_arg () =
    invalid_arg
      (Printf.sprintf "Ipv4.netmask_of_string: ill-formed netmask %s" s)
  in
  try begin
    let netmask = Scanf.sscanf s "%i.%i.%i.%i%s" (fun b1 b2 b3 b4 r ->  (assert (r="")); (b1, b2, b3, b4)) in
    let _ = cidr_of_netmask netmask in (* verify *)
    netmask
  end with _ -> invalid_arg ()


(** Example: ["192.168.1.42" -> (192,168,1,42)] *)
let of_string s =
  let invalid_arg () =
    invalid_arg
      (Printf.sprintf "Ipv4.of_string: ill-formed ipv4 address %s" s)
  in
  (** A valid ipv4 has each byte in the range [0..255]. *)
  let is_valid (b1,b2,b3,b4) =
    List.for_all (fun x->(x>=0) && (x<=255)) [b1; b2; b3; b4]
  in
  try
    let result = Scanf.sscanf s "%i.%i.%i.%i%s" (fun b1 b2 b3 b4 r -> (assert (r="")); (b1, b2, b3, b4)) in
    if is_valid result then result else invalid_arg ()
   with _ -> invalid_arg ()

(** Example: ["192.168.1.42" -> (192,168,1,42)] *)
let to_string (b1, b2, b3, b4) =
  Printf.sprintf "%i.%i.%i.%i" b1 b2 b3 b4

let string_of_config ((b1, b2, b3, b4), cidr) =
  Printf.sprintf "%i.%i.%i.%i/%i" b1 b2 b3 b4 cidr

let string_of_socket ((b1, b2, b3, b4), port) =
  Printf.sprintf "%i.%i.%i.%i:%i" b1 b2 b3 b4 port

(** Convert a string in the form ["xx.xx.xx.xx/<cidr>"] into its internal representation. *)
let config_of_string (config:string) =
  match Option.apply_or_catch (Scanf.sscanf config "%s@/%i%s") (fun s i r ->  (assert (r="")); (s,i)) with
  | None -> invalid_arg ("Ipv4.config_of_string: ill-formed <address>/<cidr> : "^config)
  | Some (s, cidr) ->
      if cidr < 0 || cidr > 32
        then invalid_arg ("Ipv4.config_of_string: invalid cidr: "^(string_of_int cidr))
        else begin
          match Option.apply_or_catch of_string s with
          | None -> invalid_arg ("Ipv4.config_of_string: ill-formed address: "^s)
          | Some t -> (t, cidr)
        end

(** Convert a string in the form ["xx.xx.xx.xx:<port>"] into its internal representation. *)
let socket_of_string (socket:string) =
  match Option.apply_or_catch (Scanf.sscanf socket "%s@:%i%s") (fun s i r ->  (assert (r="")); (s,i)) with
  | None -> invalid_arg ("Ipv4.socket_of_string: ill-formed <address>:<port> : "^socket)
  | Some (s, port) ->
      if port < 0 || port > 65535
        then invalid_arg ("Ipv4.socket_of_string: invalid port number: "^(string_of_int port))
        else begin
          match Option.apply_or_catch of_string s with
          | None -> invalid_arg ("Ipv4.socket_of_string: ill-formed address: "^s)
          | Some t -> (t, port)
        end

(** Try to complete an Ipv4 address using historical classes (as performed for instance by the Unix command `ifconfig') *)
let to_config ((b1, b2, b3, b4) as t) : config option =
  let b5 =
    if b1 < 128 then Some 8  (* class A *) else
    if b1 < 192 then Some 16 (* class B *) else
    if b1 < 224 then Some 24 (* class C *) else
    None
  in
  Option.map (fun b5 -> (t,b5)) b5

(** Try to import a string as config or simple address (when the CIDR is not specified neither deductible). *)
let import (s:string) : (t, config) Either.t option =
  try begin
    let config = config_of_string s in
    Some (Either.Right config)
  end with _ ->
  try begin
    let t = of_string s in
    match to_config t with
    | Some config -> Some (Either.Right config)
    | None        -> Some (Either.Left t)
  end with _ -> None


(* ********************************************
                 ipcalc
   ******************************************** *)

let ipcalc ((i1,i2,i3,i4) as ip) cidr =
  let (n1,n2,n3,n4) as netmask   = netmask_of_cidr cidr in
  let (a1,a2,a3,a4) as network   = (i1  land n1, i2  land n2, i3  land n3, i4  land n4) in (* network address *)
  let (d1,d2,d3,d4)              = (255 lxor n1, 255 lxor n2, 255 lxor n3, 255 lxor n4) in (* capacity delta *)
  let (b1,b2,b3,b4) as broadcast = (a1+d1, a2+d2, a3+d3, a4+d4) in
  let hostmin = (a1,a2,a3,a4+1) in
  let hostmax = (b1,b2,b3,b4-1) in
  let hostmin = max (min hostmin hostmax) network
  and hostmax = min (max hostmin hostmax) broadcast in
  let contains x = (x >= hostmin && x <= hostmax) in
  let hosts = match cidr with
   | 32 -> 1
   | 31 -> 2
   | _ -> (int_of_float (2. ** (float_of_int (32-cidr)))) - 2
  in
  let s = to_string in
  let s_ip        = lazy (s ip) in
  let s_cidr      = lazy (string_of_int cidr) in
  let s_config    = lazy (string_of_config (ip,cidr)) in
  let s_netmask   = lazy (s netmask) in
  let s_network   = lazy (s network) in
  let s_hostmin   = lazy (s hostmin) in
  let s_hostmax   = lazy (s hostmax) in
  let s_broadcast = lazy (s broadcast)
  in
  object
    method ip = ip
    method cidr = cidr
    method config = (ip,cidr)
    method netmask = netmask
    method network = network
    method broadcast = broadcast
    method hostmin = hostmin
    method hostmax = hostmax
    method hosts = hosts
    method contains = contains
    method contains_socket (t, _port) = contains t
    method print = Printf.kfprintf flush stdout
"Address:   %s
Netmask:   %s = %d
=>
Network:   %s/%d
HostMin:   %s
HostMax:   %s
Broadcast: %s
Hosts:     %d
" (Lazy.force s_ip) (Lazy.force s_netmask) cidr (Lazy.force s_network) cidr (Lazy.force s_hostmin) (Lazy.force s_hostmax) (Lazy.force s_broadcast) hosts

    method to_string =
      object
	method ip = (Lazy.force s_ip)
        method cidr = (Lazy.force s_cidr)
        method config = (Lazy.force s_config)
	method netmask = (Lazy.force s_netmask)
	method network = (Lazy.force s_network)
	method broadcast = (Lazy.force s_broadcast)
	method hostmax = (Lazy.force s_hostmax)
	method hostmin = (Lazy.force s_hostmin)
      end

  end
;;


(** Similar tools working on strings and producing strings. *)
module String = struct

 type t = string (* alias *)

 let is_valid_ipv4 x =
   try let _ = of_string x in true with _ -> false

 let is_valid_netmask x =
   try let _ = netmask_of_string x in true with _ -> false

 let is_valid_config x =
   try let _ = config_of_string x in true with _ -> false

 let ipcalc ~config:config =
    match Option.apply_or_catch config_of_string config with
    | None -> invalid_arg ("Ipv4.String.ipcalc: ill-formed address/cidr: "^config)
    | Some (t, cidr) ->
        begin
	  let x = ipcalc t cidr in
	  object
	      method ip = x#to_string#ip
	      method cidr = string_of_int (x#cidr)
	      method netmask = x#to_string#netmask
	      method network = x#to_string#network
	      method broadcast = x#to_string#broadcast
	      method hostmax = x#to_string#hostmax
	      method hostmin = x#to_string#hostmin
	      method contains ~ip = x#contains (of_string ip)
	      method contains_socket ~socket = x#contains_socket (socket_of_string socket)
	      method print = x#print
	  end (* object *)
	end

end
