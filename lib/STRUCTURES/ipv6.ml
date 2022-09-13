(* This file is part of ocamlbricks
   Copyright (C) 2012 Jean-Vincent Loddo

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
INCLUDE DEFINITIONS "../../../../lib/STRUCTURES/ipv6.mli"
;;

(** Convert a string into the ipv6 addresses internal representation.
    Raise [Invalid_argument] if the string is not in the valid standard format. *)
let of_string s =
  if s = ":::" then (Array.make 8 0) else
  let scan_group group =
    let (i,rest) = Scanf.sscanf group "%4x%s" (fun i rest -> (i,rest)) in
    (assert (rest=""));
    i
  in
  try
    let xs = Str.split_delim (Str.regexp "::") s in
    let (ys,zs) =
      match List.map (Str.split_delim (Str.regexp ":")) xs with
      | [ys]    -> (ys,[])
      | [ys;zs] -> (ys,zs)
      | _       -> assert false
    in
    let ys = List.map scan_group ys in
    let zs = List.map scan_group zs in
    let ys = Array.of_list ys in
    let zs = Array.of_list zs in
    let n1 = Array.length ys in
    let n2 = Array.length zs in
    (assert (n1+n2 <= 8));
    let zeros = Array.make (8-n1-n2) 0 in
    let result = Array.concat [ys; zeros; zs] in
    result
  with _ -> invalid_arg ("Ipv6.of_string: ill-formed ipv6 address "^s)


(** Convert the internal representation of an ipv6 addresses into a string. *)
let to_string ?uncompress t =
  (assert (Array.length t = 8));
  if (ArrayExtra.for_all (fun _ -> (=) 0) t) then ":::" else
  let search_longest_sequence_of_zeros ?leftmost =
    ArrayExtra.search_longest_sequence ?leftmost ((=)0)
  in
  let to_string_list y =
    if Array.length y = 0 then [""] else
    Array.to_list (Array.map (Printf.sprintf "%x") y)
  in
  let xs =
    if uncompress = Some () then to_string_list t else
    match search_longest_sequence_of_zeros t with
    | Some (j,n) when n>1 ->
	let x1,_,x3 =
	  match ArrayExtra.cut ~lengths:[j;n;(8-j-n)] t with
          | [x1;x2;x3] -> (x1,x2,x3)
          | _ -> assert false
	in
        let x1 = to_string_list x1 in
        let x2 = [""] in
        let x3 = to_string_list x3 in
        List.concat [x1;x2;x3]
    | _ -> to_string_list t
  in
  String.concat ":" xs


(** Convert a string in the form ["xxxx:xxxx:..:xxxx/<cidr>"] into its internal representation. *)
let config_of_string (config:string) =
  match Option.apply_or_catch (Scanf.sscanf config "%s@/%i%s") (fun s i r ->  (assert (r="")); (s,i)) with
  | None -> invalid_arg ("Ipv6.config_of_string: ill-formed address/cidr: "^config)
  | Some (s, cidr) ->
      if cidr < 0 || cidr > 128
        then invalid_arg ("Ipv6.config_of_string: invalid cidr: "^(string_of_int cidr))
        else begin
          match Option.apply_or_catch of_string s with
          | None -> invalid_arg ("Ipv6.config_of_string: ill-formed address: "^s)
          | Some t -> (t, cidr)
        end

(** Convert the internal representation [(t,cidr)] into a string. *)
let string_of_config ?uncompress (t,cidr) =
  let s = to_string ?uncompress t in
  Printf.sprintf "%s/%d" s cidr


(** Determine all derived informations from the ipv6 address and cidr.

{b Example}:
{[# (Ipv6.ipcalc (Ipv6.of_string "abcd::7:8:9") 120)#print ;;
Address:   abcd::7:8:9
Netmask:   ffff:ffff:ffff:ffff:ffff:ffff:ffff:ff00 = 120
=>
Network:   abcd::7:8:0/120
HostMin:   abcd::7:8:0
HostMax:   abcd::7:8:ff
  : unit = () ]} *)
let ipcalc (t as ip) cidr =
  (* Indexes of groups involved by the cidr value: *)
  let ((g1, g2), cidr4) =
    if cidr <=32 then ((0,1), cidr)    else
    if cidr <=64 then ((2,3), cidr-32) else
    if cidr <=96 then ((4,5), cidr-64) else ((6,7), cidr-96)
  in
  let ipv4_of_two_groups x y =
    let x1,x2 = (x / 256), (x mod 256) in
    let y1,y2 = (y / 256), (y mod 256) in
    (x1,x2,y1,y2)
  in
  let group_of_semi_ipv4 x y = x*256 + y in
  let ipcalc4 = Ipv4.ipcalc (ipv4_of_two_groups t.(g1) t.(g2)) cidr4 in
  let netmask =
    let (i1,i2,i3,i4) = ipcalc4#netmask in
    Array.mapi
      (fun i group ->
         if i<g1 then 65535 else
         if i>g2 then 0 else
         if i=g1 then group_of_semi_ipv4 i1 i2 else
         group_of_semi_ipv4 i3 i4)
      t
  in
  let network =
    let (i1,i2,i3,i4) = ipcalc4#network in
    Array.mapi
      (fun i group ->
         if i<g1 then group else
         if i>g2 then 0 else
         if i=g1 then group_of_semi_ipv4 i1 i2 else
         group_of_semi_ipv4 i3 i4)
      t
  in
  let hostmin = network in
  let hostmax =
    let (i1,i2,i3,i4) = ipcalc4#broadcast in
    Array.mapi
      (fun i group ->
         if i<g1 then group else
         if i>g2 then 65535 else(** IPv6 parsing and printing. *)

         if i=g1 then group_of_semi_ipv4 i1 i2 else
         group_of_semi_ipv4 i3 i4)
      t
  in
  let contains x = (x >= hostmin && x <= hostmax) in
  let s = to_string in
  let s_ip        = lazy (s ip) in
  let s_cidr      = lazy (string_of_int cidr) in
  let s_config    = lazy (string_of_config (ip,cidr)) in
  let s_netmask   = lazy (s netmask) in
  let s_network   = lazy (s network) in
  let s_hostmin   = lazy (s hostmin) in
  let s_hostmax   = lazy (s hostmax)
  in
  object
    method ip = ip
    method cidr = cidr (** the provided cidr *)
    method config = (ip, cidr)
    method netmask = netmask
    method network = network
    method hostmax = hostmax
    method hostmin = hostmin
    method contains = contains
    method print = Printf.kfprintf flush stdout
"Address:   %s
Netmask:   %s = %d
=>
Network:   %s/%d
HostMin:   %s
HostMax:   %s
" (Lazy.force s_ip) (Lazy.force s_netmask) cidr (Lazy.force s_network) cidr (Lazy.force s_hostmin) (Lazy.force s_hostmax)

    method to_string =
      object
	method ip      = (Lazy.force s_ip)
	method cidr    = (Lazy.force s_cidr)
	method config  = (Lazy.force s_config)
	method netmask = (Lazy.force s_netmask)
	method network = (Lazy.force s_network)
	method hostmax = (Lazy.force s_hostmax)
	method hostmin = (Lazy.force s_hostmin)
      end

  end
;;


(** Similar tools working on strings and producing strings. *)
module String = struct

 type t = string (* alias *)

 let is_valid_ipv6 x =
   try let _ = of_string x in true with _ -> false

 let is_valid_config x =
   try let _ = config_of_string x in true with _ -> false

(** Determine all derived informations from the ipv6 address and cidr provided in a unique
    string in the form ["xxxx:xxxx:..:xxxx/<cidr>"].
{b Example}:
 {[ # (Ipv6.String.ipcalc "abcd::7:8:9/120")#print ;;
Address:   abcd::7:8:9
Netmask:   ffff:ffff:ffff:ffff:ffff:ffff:ffff:ff00 = 120
=>
Network:   abcd::7:8:0/120
HostMin:   abcd::7:8:0
HostMax:   abcd::7:8:ff
  : unit = () ]} *)
  let ipcalc ~config:config =
    match Option.apply_or_catch config_of_string config with
    | None -> invalid_arg ("Ipv6.String.ipcalc: ill-formed address/cidr: "^config)
    | Some (t, cidr) ->
        begin
	  let x = ipcalc t cidr in
	  object
	      method ip = x#to_string#ip
	      method cidr = x#to_string#cidr
	      method netmask = x#to_string#netmask
	      method network = x#to_string#network
	      method hostmax = x#to_string#hostmax
	      method hostmin = x#to_string#hostmin
	      method contains = fun ~ip -> x#contains (of_string ip)
	      method print = x#print
	  end (* object *)
	end

end (* module String *)

