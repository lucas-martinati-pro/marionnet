(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2009-2017  Jean-Vincent Loddo
   Copyright (C) 2009-2017  Université Paris 13

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
module Either = Ocamlbricks.Either
module ListExtra = Ocamlbricks.ListExtra
module ArrayExtra = Ocamlbricks.ArrayExtra
module Lazy_perishable = Ocamlbricks.Lazy_perishable
module OoExtra = Ocamlbricks.OoExtra
module Forest = Ocamlbricks.Forest
module Xforest = Ocamlbricks.Xforest
module Ipv4 = Ocamlbricks.Ipv4
module Ipv6 = Ocamlbricks.Ipv6

(* --- *)
open Gettext;;

IFNDEF OCAML4_04_OR_LATER THEN
let lowercase  = String.lowercase
let uppercase  = String.uppercase
ELSE
let lowercase  = String.lowercase_ascii
let uppercase  = String.uppercase_ascii
ENDIF

(** Gui-related stuff for the user-level component "router". *)

(* The module containing the add/update dialog is defined later,
   using the syntax extension "where" *)
#load "where_p4.cmo"
;;

type port_number = int

(* Router related constants: *)
(* TODO: make it configurable! *)
module Const = struct
 let port_no_default = 4
 let port_no_min = 4
 let port_no_max = 16

 let port_0_ipv4_config_default : Ipv4.config        = Initialization.router_port0_default_ipv4_config
 let port_0_ipv6_config_default : Ipv6.config option = Initialization.router_port0_default_ipv6_config
 let memory_default = 128

 (* Unix-related configuration (not Quagga-related!) *)
 let initial_content_for_rcfiles_UNIX =
"#!/bin/bash
# ---
# This script will be executed (sourced) as final step
# of the virtual machine bootstrap process.
# ---
# Several variables are set at this point.
# Examples: (some values depend on your settings)
# ---
# hostname='R1'
# mem='128M'
# virtualfs_kind='router'
# virtualfs_name='router-guignol-45228'
# mac_address_eth0='02:04:06:15:ad:0a'
# mtu_eth0='1500'
# PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
# ---
# Your effective user and group IDs are uid=0 (root), gid=0 (root),
# and the current working directory is '/', that is to say PWD='/'
# ---
" ;;

 let initial_content_for_rcfiles_ZEBRA =
"!---
! ZEBRA configuration file (Quagga port 2601)
!---
! IP routing manager
! See: http://www.nongnu.org/quagga/docs/quagga.html
!---
! Note: leave passwords unchanged or change them in the same way for
! all selected services (zebra, rip, ripng, ospf, bgp, ospf6, isis)
password zebra
enable password zebra
!log file /var/quagga/zebra.log
!
!=== INTERFACE CONFIGURATION ===
!interface IFNAME
!  ip   address ADDRESS/PREFIX
!  ipv6 address ADDRESS/PREFIX
!  ..
!exit
!=== STATIC ROUTING ===
!ip   forwarding
!ipv6 forwarding
!ip   route ADDRESS/PREFIX GATEWAY
!ipv6 route ADDRESS/PREFIX GATEWAY
!
!=== EXAMPLES (tip: uncomment and adapt) ===
!interface eth1
!  ip   address 10.10.0.5/16
!  ipv6 address 2001:db9::5/64
!exit
!ip   route 11.11.11.0/24 10.10.255.254
!ipv6 route 2001:db8::/64 2001:db9::ff
!---
" ;;

 let initial_content_for_rcfiles_RIP =
"!---
! RIP configuration file (Quagga port 2602)
!---
! RFC2453, RFC1058 (RIP is Routing Information Protocol v.2)
! See: http://www.nongnu.org/quagga/docs/quagga.html
!---
! Note: leave passwords unchanged or change them in the same way for
! all selected services (zebra, rip, ripng, ospf, bgp, ospf6, isis)
password zebra
enable password zebra
router rip
!log file /var/quagga/ripd.log
!
!  network ADDRESS/PREFIX
!  network IFNAME
!
!=== EXAMPLES (tip: uncomment and adapt) ===
!
!  network 10.0.0.0/8
!  network eth0
!
" ;;

 let initial_content_for_rcfiles_RIPNG =
"!---
! RIPNG configuration file (Quagga port 2603)
!---
! RFC2080 (RIP protocol for IPv6)
! See: http://www.nongnu.org/quagga/docs/quagga.html
!---
! Note: leave passwords unchanged or change them in the same way for
! all selected services (zebra, rip, ripng, ospf, bgp, ospf6, isis)
password zebra
enable password zebra
router ripng
!log file /var/quagga/ripngd.log
!
!  network ADDRESS/PREFIX
!  network IFNAME
!  route ADDRESS/PREFIX
!
" ;;

 let initial_content_for_rcfiles_OSPF =
"!---
! OSPF configuration file (Quagga port 2604)
!---
! RFC2328 (OSPF is Open Shortest Path First v.2)
! See: http://www.nongnu.org/quagga/docs/quagga.html
!---
! Note: leave passwords unchanged or change them in the same way for
! all selected services (zebra, rip, ripng, ospf, bgp, ospf6, isis)
password zebra
enable password zebra
router ospf
!log file /var/quagga/ospfd.log
!
!  network ADDRESS/PREFIX area ADDRESS
!  area ADDRESS range ADDRESS/PREFIX [substitute ADDRESS/PREFIX]
!
!=== EXAMPLES (tip: uncomment and adapt) ===
!
!  network 192.168.1.0/24 area 0.0.0.0
!  network 10.0.0.0/8 area 0.0.0.10
!  area 0.0.0.10 range 10.0.0.0/8 substitute 11.0.0.0/8
!
" ;;

 let initial_content_for_rcfiles_OSPF6 =
"!---
! OSPF6 configuration file (Quagga port 2606)
!---
! RFC2740 (OSPF6 is Open Shortest Path First v.3 for IPv6)
! See: http://www.nongnu.org/quagga/docs/quagga.html
!---
! Note: leave passwords unchanged or change them in the same way for
! all selected services (zebra, rip, ripng, ospf, bgp, ospf6, isis)
password zebra
enable password zebra
router ospf6
!log file /var/quagga/ospf6d.log
!
!=== EXAMPLES (tip: uncomment and adapt) ===
!
!! Example of for one interface and area:
!
!  interface eth0
!    ipv6 ospf6 instance-id 0
!
!  router ospf6
!    router-id 212.17.55.53
!    area 0.0.0.0 range 2001:770:105:2::/64
!    interface eth0 area 0.0.0.0
!
" ;;

 let initial_content_for_rcfiles_BGP =
"!---
! BGP configuration file (Quagga port 2605)
!---
! RFC1771, RFC2858 (BGP is Border Gateway Protocol v.4)
! See: http://www.nongnu.org/quagga/docs/quagga.html
!---
! Note: leave passwords unchanged or change them in the same way for
! all selected services (zebra, rip, ripng, ospf, bgp, ospf6, isis)
password zebra
enable password zebra
!log file /var/quagga/bgpd.log
!
!=== EXAMPLES (tip: uncomment and adapt) ===
!
!! Example of a session to an upstream, advertising
!! only one prefix to it:
!
!  router bgp 64512
!  bgp router-id 10.236.87.1
!  network 10.236.87.0/24
!  neighbor upstream peer-group
!  neighbor upstream remote-as 64515
!  neighbor upstream capability dynamic
!  neighbor upstream prefix-list pl-allowed-adv out
!  neighbor 10.1.1.1 peer-group upstream
!  neighbor 10.1.1.1 description ACME ISP
!
!  ip prefix-list pl-allowed-adv seq 5 permit 82.195.133.0/25
!  ip prefix-list pl-allowed-adv seq 10 deny any
!
" ;;

 let initial_content_for_rcfiles_ISIS =
"!---
! ISIS configuration file (Quagga port 2608)
!---
! ISIS is Intermediate System to Intermediate System
! ISO10589, RFC1195, RFC5308
! See: http://www.nongnu.org/quagga/docs/quagga.html
!---
! Note: leave passwords unchanged or change them in the same way for
! all selected services (zebra, rip, ripng, ospf, bgp, ospf6, isis)
password zebra
enable password zebra
!log file /var/quagga/isisd.log
!
!=== EXAMPLES (tip: uncomment and adapt) ===
!
!! A simple example, with MD5 authentication enabled:
!
!  interface eth0
!  ip router isis FOO
!  isis network point-to-point
!  isis circuit-type level-2-only
!
!  router isis FOO
!  net 47.0023.0000.0000.0000.0000.0000.0000.1900.0004.00
!  metric-style wide
!  is-type level-2-only
!
" ;;

 (* Will be used as key: "zebra" "rip" "ripng" "ospf" "bgp" "ospf6" "isis" *)
 type quagga_lowercase_acronym = string

 (* A simple constant data structure (object), with some methods to deal about alternatives, indexes and related port numbers: *)
 let quagga_alternatives
   : < message_list            : string list;  (* [  "ZEBRA (port 2601)";          ...              ; "ISIS (port 2608)" ] *)
       uppercase_acronym_array : string array; (* [| "ZEBRA"; "RIP"; "RIPNG"; "OSPF"; "BGP"; "OSPF6"; "ISIS"; |] *)
       lowercase_acronym_array : string array; (* [| "zebra"; "rip"; "ripng"; "ospf"; "bgp"; "ospf6"; "isis"; |] *)
       lowercase_acronym_list  : string list;
       (* --- *)
       index_of_message : string -> int;
       index_of_lowercase_acronym : string -> int;
       index_of_port    : port_number -> int;
       valid_port       : port_number -> bool;
       (* --- *)
       port_of_message           : string -> port_number;
       uppercase_acronym_of_port : port_number -> string;
       (* --- *)
       initial_content_for_rcfiles : string array;
       rc_config_initialization : (string * (bool * string)) list;
       config_file_of_lowercase_acronym    : string -> string; (* "zebra" -> "/etc/quagga/zebra.conf" *)
       config_content_of_lowercase_acronym : string -> string; (* "zebra" -> "!ZEBRA configuration file\n..." *)
       port_of_lowercase_acronym        : string -> port_number
       (* --- *)
       >
       =
   let initial_content_for_rcfiles =
      [| initial_content_for_rcfiles_ZEBRA;
         initial_content_for_rcfiles_RIP;
         initial_content_for_rcfiles_RIPNG;
         initial_content_for_rcfiles_OSPF;
         initial_content_for_rcfiles_BGP;
         initial_content_for_rcfiles_OSPF6;
         initial_content_for_rcfiles_ISIS; |]
   in
   let message_port_list =
      [ ("ZEBRA (port 2601)", 2601);
        ("RIP (port 2602)"  , 2602);
        ("RIPNG (port 2603)", 2603);
        ("OSPF (port 2604)" , 2604);
        ("BGP (port 2605)"  , 2605);
        ("OSPF6 (port 2606)", 2606);
        ("ISIS (port 2608)" , 2608); ]
   in
   let config_files =
      [| "zebra.conf";
         "ripd.conf";
         "ripngd.conf";
         "ospfd.conf";
         "bgpd.conf";
         "ospf6d.conf";
         "isisd.conf"; |]
   in
   let message_list, port_list =
     List.split message_port_list
   in
   let message_array, port_array =
     (Array.of_list message_list, Array.of_list port_list)
   in
   let uppercase_acronym_array =
     Array.map (fun m -> Scanf.sscanf m "%s" (fun s->s)) message_array
   in
   let lowercase_acronym_array =
     Array.map (lowercase) uppercase_acronym_array
   in
   let lowercase_acronym_list =
     Array.to_list (lowercase_acronym_array)
   in
   (* "zebra" -> content; .. ; "isis" -> content  *)
   let initial_content_for_rcfiles_assoc_list =
     List.combine (Array.to_list lowercase_acronym_array) (Array.to_list initial_content_for_rcfiles)
   in
   (* ---*)
   object (self)
     (* ---*)
     method message_list = message_list
     method uppercase_acronym_array = uppercase_acronym_array
     method lowercase_acronym_array = lowercase_acronym_array
     method lowercase_acronym_list  = lowercase_acronym_list
     method initial_content_for_rcfiles = initial_content_for_rcfiles (* array => index -> content *)
     (* ---*)
     method index_of_port p =
       fst (ListExtra.findi ((=)p) (port_list))
     (* ---*)
     method index_of_message msg =
       fst (ListExtra.findi ((=)msg) (message_list))
     (* ---*)
     method index_of_lowercase_acronym k =
       fst (ArrayExtra.findi ((=)k) (lowercase_acronym_array))
     (* ---*)
     method port_of_message msg =
       let index =  self#index_of_message msg in
       port_array.(index)
     (* ---*)
     method uppercase_acronym_of_port p =
       let index =  self#index_of_port p in
       uppercase_acronym_array.(index)
     (* ---*)
     method valid_port x = not (x<2601 || x>2608 || x=2607)
     (* ---*)
     method rc_config_initialization = (* here false means "unselected" *)
       List.map (fun (key, content) -> (key, (false, content))) (initial_content_for_rcfiles_assoc_list)
     (* ---*)
     method config_file_of_lowercase_acronym (acronym) =
       let index =  self#index_of_lowercase_acronym (acronym) in
       Printf.sprintf "/etc/quagga/%s" config_files.(index)
     (* ---*)
     method config_content_of_lowercase_acronym (acronym) =
       let index =  self#index_of_lowercase_acronym (acronym) in
       initial_content_for_rcfiles.(index)
     (* ---*)
     method port_of_lowercase_acronym (acronym) =
       let index =  self#index_of_lowercase_acronym (acronym) in
       port_array.(index)
     (* ---*)
 end (* object `quagga_alternatives' *)

end

(* The type of data returned by the dialog: *)
module Data = struct
type t = {
  name                 : string;
  label                : string;
  port_0_ipv4_config   : Ipv4.config;
  port_0_ipv6_config   : Ipv6.config option;
  port_no              : int;
  distribution         : string;          (* epithet *)
  variant              : string option;
  kernel               : string;          (* epithet *)
  (* --- *)
  show_unix_terminal   : bool;
  rc_config_unix       : bool * string;   (* run commands (rc) file configuration *)
  (* --- *)
  quagga_selected_srvs : (Const.quagga_lowercase_acronym list);
  show_quagga_terminal : (Const.quagga_lowercase_acronym list);
  rc_config_quagga     : (Const.quagga_lowercase_acronym * (bool * string)) list; (* run commands (rc) file configuration *)
  (* --- *)
  old_name             : string;
  }

let to_string t = "<obj>" (* TODO? *)
end (* Data *)

module Make_menus (Params : sig
  val st      : State.globalState
  val packing : [ `toolbar of GButton.toolbar | `menu_parent of Menu_factory.menu_parent ]
 end) = struct

  open Params

  module Toolbar_entry = struct
   let imagefile = "ico.router.palette.png"
   let tooltip   = (s_ "Router")
   let packing   = Params.packing
  end

  module Add = struct
    include Data

    let key = Some GdkKeysyms._R

    let ok_callback t = Gui_bricks.Ok_callback.check_name t.name t.old_name st#network#name_exists t

    let dialog () =
      let name = st#network#suggestedName "R" in
      Dialog_add_or_update.make
        ~title:(s_ "Add router") ~name ~ok_callback ()

    let reaction {
         name = name;
         label = label;
         port_0_ipv4_config = port_0_ipv4_config;
         port_0_ipv6_config = port_0_ipv6_config;
         port_no = port_no;
         distribution = distribution;
         variant = variant;
	 kernel = kernel;
         show_unix_terminal = show_unix_terminal;
         rc_config_unix = rc_config_unix;
         quagga_selected_srvs = quagga_selected_srvs;
         show_quagga_terminal = show_quagga_terminal;
         rc_config_quagga = rc_config_quagga;
         old_name = _ ;
         }
      =
      let action () = ignore (
        new User_level_router.router (* defined later with WHERE *)
          ~network:st#network
          ~name
          ~label
          ~port_0_ipv4_config
          ~port_0_ipv6_config
          ~epithet:distribution
          ?variant:variant
          ~kernel
          ~port_no
          ~show_unix_terminal
          ~rc_config_unix
          ~quagga_selected_srvs
          ~show_quagga_terminal
          ~rc_config_quagga
          ())
      in
      st#network_change action ();

  end (* Add *)

  module Properties = struct
    include Data
    let dynlist () = st#network#get_node_names_that_can_startup ~devkind:`Router ()

    let dialog name () =
     let r = (st#network#get_node_by_name name) in
     let r = ((Obj.magic r):> User_level_router.router) in
     let title = (s_ "Modify router")^" "^name in
     let label = r#get_label in
     let distribution = r#get_epithet in
     let variant = r#get_variant in
     let kernel = r#get_kernel in
     let show_unix_terminal = r#get_show_unix_terminal in
     let rc_config_unix = r#get_rc_config_unix in
     let quagga_selected_srvs = r#get_quagga_selected_srvs in
     let show_quagga_terminal = r#get_show_quagga_terminal in
     let rc_config_quagga = r#get_rc_config_quagga in
     let port_no = r#get_port_no in
     let port_0_ipv4_config = r#get_port_0_ipv4_config in
     let port_0_ipv6_config = r#get_port_0_ipv6_config in
     (* The user cannot remove receptacles used by a cable. *)
     let port_no_min = st#network#port_no_lower_of (r :> User_level.node)
     in
     Dialog_add_or_update.make
       ~title ~name ~label ~distribution ?variant
       ~show_unix_terminal ~rc_config_unix
       ~quagga_selected_srvs ~show_quagga_terminal ~rc_config_quagga
       ~port_no ~port_no_min
       ~port_0_ipv4_config
       ~port_0_ipv6_config
       ~kernel
       ~updating:() (* the user cannot change the distrib & variant *)
       ~ok_callback:Add.ok_callback  ()

    let reaction {
         name = name;
         label = label;
         port_0_ipv4_config = port_0_ipv4_config;
         port_0_ipv6_config = port_0_ipv6_config;
         port_no = port_no;
	 kernel = kernel;
         show_unix_terminal = show_unix_terminal;
         rc_config_unix = rc_config_unix;
         quagga_selected_srvs = quagga_selected_srvs;
         show_quagga_terminal = show_quagga_terminal;
         rc_config_quagga = rc_config_quagga;
         old_name = old_name;
         _
         }
      =
      let d = (st#network#get_node_by_name old_name) in
      let r = ((Obj.magic d):> User_level_router.router) in
      let action () =
        r#update_router_with
          ~name ~label ~port_0_ipv4_config ?port_0_ipv6_config ~port_no ~kernel
          ~show_unix_terminal ~rc_config_unix
          ~quagga_selected_srvs ~show_quagga_terminal ~rc_config_quagga
          ()
      in
      st#network_change action ();

  end (* Properties *)

  module Remove = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")

    let dynlist = Properties.dynlist

    let dialog name () =
      Gui_bricks.Dialog.yes_or_cancel_question
        ~title:(s_ "Remove")
        ~markup:(Printf.sprintf (f_ "Are you sure that you want to remove %s\nand all the cables connected to this %s?") name (s_ "router"))
        ~context:name
        ()

    let reaction name =
      let d = (st#network#get_node_by_name name) in
      let r = ((Obj.magic d):> User_level_router.router) in
      let action () = r#destroy in
      st#network_change action ();

  end

  module Startup = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist    = Properties.dynlist
    let dialog     = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#startup

  end

  module Stop = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_gracefully_shutdown ~devkind:`Router ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#gracefully_shutdown

  end

  module Suspend = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_suspend ~devkind:`Router ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#suspend

  end

  module Resume = struct
    type t = string (* just the name *)

    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_resume ~devkind:`Router ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#resume

  end

 module Create_entries =
  Gui_toolbar_COMPONENTS_layouts.Layout_for_network_node (Params) (Toolbar_entry) (Add) (Properties) (Remove) (Startup) (Stop) (Suspend) (Resume)

 (* Subscribe this kind of component to the network club: *)
 st#network#subscribe_a_try_to_add_procedure Eval_forest_child.try_to_add_router;

end

(*-----*)
  WHERE
(*-----*)

module Dialog_add_or_update = struct

(* This function may be useful for testing the widget creation without
   recompiling the whole project. *)
let make
 ?(title="Add a router")
 ?(name="")
 ?label
 ?(port_0_ipv4_config=Const.port_0_ipv4_config_default)
 ?(port_0_ipv6_config=Const.port_0_ipv6_config_default)
 ?(port_no=Const.port_no_default)
 ?(port_no_min=Const.port_no_min)
 ?(port_no_max=Const.port_no_max)
 ?distribution
 ?variant
 ?kernel
 ?(updating:unit option)
 (* --- *)
 ?(show_unix_terminal=false)
 ?(rc_config_unix=(false, Const.initial_content_for_rcfiles_UNIX))
 (* --- *)
 ?(quagga_selected_srvs=Const.quagga_alternatives#lowercase_acronym_list)
 ?(show_quagga_terminal=[])
 ?(rc_config_quagga=Const.quagga_alternatives#rc_config_initialization)
 (* --- *)
 ?(help_callback=help_callback) (* defined backward with "WHERE" *)
 ?(ok_callback=(fun data -> Some data))
 ?(dialog_image_file=Initialization.Path.images^"ico.router.dialog.png")
 () :'result option =
  let old_name = name in
  let ((b1,b2,b3,b4),b5) = port_0_ipv4_config  in
  let port_0_ipv6_config : bool * string (* User representation *) =
    match port_0_ipv6_config with
    | None   -> (false, "2001:db9::ff/32")
    | Some v -> (true, Ipv6.string_of_config v)
  in
  let vm_installations = Lazy_perishable.force (Disk.get_router_installations) in
  let (dialog_router,_,name,label) =
    Gui_bricks.Dialog_add_or_update.make_window_image_name_and_label
      ~title
      ~image_file:dialog_image_file
      ~image_tooltip:(s_ "Router")
      ~name
      ~name_tooltip:(s_ "Router name. This name must be unique in the virtual network. Suggested: R1, R2, ...")
      ?label
      ()
  in
  let ((s1,s2,s3,s4,s5), port_0_ipv6_config_obj, port_no, distribution_variant_kernel, rc_config_unix, show_unix_terminal, quagga_widgets) =
    let vbox = GPack.vbox ~homogeneous:false ~border_width:20 ~spacing:10 ~packing:dialog_router#vbox#add () in
    let form =
      Gui_bricks.make_form_with_labels
        ~packing:vbox#add
        [(s_ "Ports number");
         (s_ "Port 0 IPv4 address");
         (s_ "Port 0 Ipv6 address");
         (s_ "Distribution");
         (s_ "Variant");
         (s_ "Kernel");
         (s_ "Startup configuration");
         (s_ "Show Unix terminal");
         (s_ "Services");
         ]
    in
    form#add_section ~no_line:() "Hardware";
    (* --- *)
    let on_distrib_change = ref [] (* a list of callbacks *) in
    (* --- *)
    let port_no =
      Gui_bricks.spin_byte ~lower:port_no_min ~upper:port_no_max ~step_incr:2
      ~packing:(form#add_with_tooltip (s_ "Number of router ports" )) port_no
    in
    (* --- *)
    let port_0_ipv4_config =
      Gui_bricks.spin_ipv4_address_with_cidr_netmask
        ~packing:(form#add_with_tooltip
                    ~just_for_label:()
                    (s_ "IPv4 configuration of the first router port (0)"))
        b1 b2 b3 b4 b5
    in
    (* --- *)
    let port_0_ipv6_config_obj : < active : bool;  content : string;  hbox : GPack.box;  check_button : GButton.toggle_button;  entry : GEdit.entry > =
      let (active, text) = port_0_ipv6_config in
      Gui_bricks.activable_entry
        ~packing:(form#add_with_tooltip (s_ "Optional IPv6 configuration of the first router port (0). For instance 2001:db9::ff/32"))
        ~active
        ~text
        ~red_text_condition:(fun x -> not (Ipv6.String.is_valid_config x))
        ()
    in
    (* --- *)
    form#add_section "Software";
    (* --- *)
    let distribution_variant_kernel =
      let packing_distribution =
        form#add_with_tooltip
          (s_ "GNU/Linux distribution installed on the router." )
      in
      let packing_variant      =
        form#add_with_tooltip
          (s_ "Initial hard disk state. The router will start by default with this variant of the chosen distribution." )
      in
      let packing_kernel =
        form#add_with_tooltip
          (s_ "Linux kernel version used for this router." )
      in
      let packing = (packing_distribution, packing_variant, packing_kernel) in
      Gui_bricks.make_combo_boxes_of_vm_installations
        ~on_distrib_change:(fun distrib -> List.iter (fun f -> f distrib) !on_distrib_change)
        ?distribution ?variant ?kernel ?updating
        ~packing
        vm_installations
    in
    (* --- *)
    let rc_config_unix =
       Gui_bricks.make_rc_config_widget
         ~width:800
         ~filter_names:[`BASH; `RC; `ALL]
         ~parent:(dialog_router :> GWindow.window_skel)
         ~packing:(form#add_with_tooltip (s_ "Check to activate a startup configuration" ))
         ~active:(fst rc_config_unix)
         ~content:(snd rc_config_unix)
         ~device_name:(old_name)
         ~language:("sh")
         ()
    in
    (* --- *)
    (* Register and call the "Port 0 Ipv6 address" + "Startup configuration" callback
       according to current distribution:  *)
    let () =
      let callback d =
        let sensitive = (vm_installations#marionnet_relay_supported_by d) in begin
        form#set_sensitive ~label_text:(s_ "Port 0 Ipv6 address") (sensitive);
        form#set_sensitive ~label_text:(s_ "Startup configuration") (sensitive);
        end
      in
      (* --- *)
      on_distrib_change := (callback)::!on_distrib_change;
      let current = distribution_variant_kernel#selected in
      callback (current)
    in
    (* --- *)
    form#add_section "Access";
    (* --- *)
    let show_unix_terminal =
      GButton.check_button
        ~active:show_unix_terminal
        ~packing:(form#add_with_tooltip (s_ "Do you want access the router also by a Unix terminal?" ))
        ()
    in
    (* --- *)
    let _services_label =
      GMisc.label
        ~packing:(form#add_with_tooltip (s_ "Configure Quagga's services" ))
        ()
    in
    (* --- *)
    let quagga_textkey_and_forms (* : array of (acronym, ("%s startup config.", form)) *) =
      Array.map
        (* --- *)
        (fun acronym ->
          let u = (uppercase acronym) in
          let text_startup_config : string = Printf.sprintf (f_ "%s startup config.") u in (* dynamically sensitive *)
          let text_show_terminal  : string = Printf.sprintf (f_ "Show %s terminal")   u in
          let form =
            Gui_bricks.make_form_with_labels
              [ text_startup_config;
                text_show_terminal ;
                ]
          in
          (acronym, (text_startup_config, form)))
        (* --- *)
        (Const.quagga_alternatives#lowercase_acronym_array)
    in
    (* --- *)
    let quagga_rc_config_widgets =
      Array.map
        (* --- *)
        (fun (acronym, (text_startup_config, (subform: Gui_bricks.form))) ->
          (* Make the widget: *)
          let widget =
            let rc_config = List.assoc acronym rc_config_quagga in
            Gui_bricks.make_rc_config_widget
              ~width:800 ~height:600 (* 800x600 *)
              ~filter_names:[`CONF; `RC; `TXT; `ALL]
              ~parent:(dialog_router :> GWindow.window_skel)
              ~packing:(subform#add_with_tooltip (s_ "Check to activate a startup configuration" ))
              ~active:(fst rc_config)
              ~content:(snd rc_config)
              ~device_name:(Printf.sprintf "%s (%s)" old_name (uppercase acronym))
              ~language:("quagga_zebra") (* special syntax TODO: ("quagga_"^acronym) *)
              ()
          in
          (* Register and call the "Startup configuration" callback according to current distribution:  *)
          let () =
            let callback d =
              let sensitive = (vm_installations#marionnet_relay_supported_by d) in begin
              subform#set_sensitive ~label_text:text_startup_config (sensitive); (* <=== text key (text_startup_config) used here *)
              widget#set_sensitive (sensitive);
              end
            in
            (* --- *)
            on_distrib_change := (callback)::!on_distrib_change;
            let current = distribution_variant_kernel#selected in
            callback (current)
          in
          (acronym, widget))
        (* --- *)
        quagga_textkey_and_forms
    in
    let quagga_terminal_widgets =
      Array.map
        (* --- *)
        (fun (acronym, (_text_startup_config, (subform: Gui_bricks.form))) ->
          let widget =
            GButton.check_button
              ~active:(List.mem acronym show_quagga_terminal)
              ~packing:(subform#add_with_tooltip (s_ "Do you want access the router also by a Quagga terminal (CISCO-IOS-like commands)?" ))
              ()
          in
          (acronym, widget))
        (* --- *)
        quagga_textkey_and_forms
    in
    (* --- *)
    let quagga_notebook : (Const.quagga_lowercase_acronym * GButton.toggle_button) list =
      let assoc_array =
        Array.map
          (fun (acronym, (_, form)) -> (acronym, (List.mem acronym quagga_selected_srvs), form#coerce))
          (quagga_textkey_and_forms)
      in
      let tbs : GButton.toggle_button array =
        Gui_bricks.make_notebook_of_assoc_array_with_check_buttons
          (*~homogeneous_tabs:true*)
          ~packing:vbox#add
          (assoc_array)
      in
      (* --- *)
      (* Distribution-related callback: *)
      let () =
        let callback d =
          let sensitive = (vm_installations#marionnet_relay_supported_by d) in begin
          Array.iter (fun b -> b#misc#set_sensitive (sensitive)) tbs
          end
        in
        (* --- *)
        on_distrib_change := (callback)::!on_distrib_change;
        let current = distribution_variant_kernel#selected in
        callback (current)
      in
      (* --- *)
      List.combine (Const.quagga_alternatives#lowercase_acronym_list) (Array.to_list tbs)
    in
    (* --- *)
    let quagga_widgets = (quagga_notebook, quagga_rc_config_widgets, quagga_terminal_widgets) in
    (* --- *)
    (port_0_ipv4_config, port_0_ipv6_config_obj, port_no, distribution_variant_kernel, rc_config_unix, show_unix_terminal, quagga_widgets)
  in
  (* --- *)
  let get_widget_data () :'result =
    let name = name#text in
    let label = label#text in
    let port_0_ipv4_config =
      let s1 = int_of_float s1#value in
      let s2 = int_of_float s2#value in
      let s3 = int_of_float s3#value in
      let s4 = int_of_float s4#value in
      let s5 = int_of_float s5#value in
      ((s1,s2,s3,s4),s5)
    in
    let port_0_ipv6_config =
      let obj = port_0_ipv6_config_obj in
      if not obj#active then None else
      try Some (Ipv6.config_of_string obj#content) with _ -> None
    in
    let port_no = int_of_float port_no#value in
    let distribution  = distribution_variant_kernel#selected in
    let variant       = distribution_variant_kernel#slave0#selected in
    let kernel        = distribution_variant_kernel#slave1#selected in
    let variant = match variant with
    | "none" -> None
    | x      -> Some x
    in
    (* --- *)
    let rc_config_unix = (rc_config_unix#active, rc_config_unix#content) in
    (* --- *)
    let (quagga_notebook, quagga_rc_config_widgets, quagga_terminal_widgets) = quagga_widgets in
    (* --- *)
    (* We look at the structure:  quagga_notebook : (quagga_lowercase_acronym * GButton.toggle_button) list *)
    let quagga_selected_srvs =
       ListExtra.filter_map (fun (k,b) -> if b#active then Some k else None) (quagga_notebook)
    in
    (* --- *)
    let rc_config_quagga : (Const.quagga_lowercase_acronym * (bool * string)) list =
      let xs = Array.map (fun (acronym, rc_config) -> (acronym, (rc_config#active, rc_config#content))) (quagga_rc_config_widgets) in
      Array.to_list xs (* TODO: reduce space removing values bound to false (or do it when saving project) *)
    in
    (* --- *)
    let show_quagga_terminal : Const.quagga_lowercase_acronym list =
      let xs = Array.map (fun (acronym, show_terminal) -> (acronym, show_terminal#active)) (quagga_terminal_widgets) in
      let xs = ListExtra.filter_map (fun (acronym, b) -> if b then Some acronym else None) (Array.to_list xs) in
      xs
    in
    (* --- *)
    let show_unix_terminal = show_unix_terminal#active in
    (* --- *)
    { Data.name = name;
      Data.label = label;
      Data.port_0_ipv4_config = port_0_ipv4_config;
      Data.port_0_ipv6_config = port_0_ipv6_config;
      Data.port_no = port_no;
      Data.distribution = distribution;
      Data.variant = variant;
      Data.kernel = kernel;
      Data.show_unix_terminal = show_unix_terminal;
      Data.rc_config_unix = rc_config_unix;
      Data.quagga_selected_srvs = quagga_selected_srvs;
      Data.rc_config_quagga = rc_config_quagga;
      Data.show_quagga_terminal = show_quagga_terminal;
      Data.old_name = old_name;
      }
  (* --- *)
  in
  (* The result of make is the result of the dialog loop (of type 'result option): *)
  Gui_bricks.Dialog_run.ok_or_cancel (dialog_router) ~ok_callback ~help_callback ~get_widget_data ()


(*-----*)
  WHERE
(*-----*)

 let help_callback =
   let title = (s_ "ADD OR MODIFY A ROUTER") in
   let msg   = (s_ "\
In this dialog window you can define the name of an IP router \
and set many parameters for it:\n\n\
- Label: a string appearing near the router icon in the network graph; \
this field is exclusively for graphic purposes, is not taken in consideration \
for the configuration.\n\
- Nb of Ports: the number of ports of the router (default 4); this number must \
not be increased without a reason, because the number of processes needed for the \
device emulation is proportional to his ports number.\n\n\
The emulation of this device is realised with the program 'quagga' derived from \
the project 'zebra'.\n\n\
Every interface of the router can be configured in the tab \
'Interfaces'. Once started, the router will answer to the telnet \
protocol on every configured interface, on the following tcp ports:\n\n\
zebra\t\t2601/tcp\t\t# zebra vty\n\
ripd\t\t\t2602/tcp\t\t# RIPd vty\n\
ripngd\t\t2603/tcp\t\t# RIPngd vty\n\
ospfd\t\t2604/tcp\t\t# OSPFd vty\n\
bgpd\t\t2605/tcp\t\t# BGPd vty\n\
ospf6d\t\t2606/tcp\t\t# OSPF6d vty\n\
isisd\t\t\t2608/tcp\t\t# ISISd vty\n\n\
Password: zebra")
   in Simple_dialogs.help title msg ;;

end

(*-----*)
  WHERE
(*-----*)

module Eval_forest_child = struct
 let try_to_add_router (network:User_level.network) ((root,children):Xforest.tree) =
  try
   (match root with
    | ("router", attrs) ->
    	let name  = List.assoc "name" attrs in
	let port_no = int_of_string (List.assoc "port_no" attrs) in
        Log.printf2 "Importing router \"%s\" with %d ports...\n" name port_no;
	let x = new User_level_router.router ~network ~name ~port_no () in
	x#from_tree ("router", attrs) children;
        Log.printf1 "Router \"%s\" successfully imported.\n" name;
        true

   (* backward compatibility *)
   | ("device", attrs) ->
      let name  = List.assoc "name" attrs in
      let port_no = int_of_string (List.assoc "eth" attrs) in
      let kind = List.assoc "kind" attrs in
      (match kind with
      | "router" ->
          Log.printf2 "Importing router \"%s\" with %d ports...\n" name port_no;
	  let r = new User_level_router.router ~network ~name ~port_no () in
	  let x = (r :> User_level.node_with_ledgrid_and_defects) in
	  x#from_tree ("device", attrs) children ;
          Log.printf1 "Router \"%s\" successfully imported.\n" name;
          true
      | _ -> false
      )
   | _ -> false
   )
  with _ -> false
end (* module Eval_forest_child *)


(*-----*)
  WHERE
(*-----*)


module User_level_router = struct

class router
  ~(network:User_level.network)
  ~name
  ?(port_0_ipv4_config=Const.port_0_ipv4_config_default)
  ?(port_0_ipv6_config=Const.port_0_ipv6_config_default)
  ?label
  ?epithet
  ?variant
  ?kernel
  (* --- *)
  ?(show_unix_terminal=false)
  ?(rc_config_unix=(false,""))
  (* --- *)
  ?(quagga_selected_srvs=Const.quagga_alternatives#lowercase_acronym_list)
  ?(show_quagga_terminal=[])
  ?(rc_config_quagga=Const.quagga_alternatives#rc_config_initialization)
  (* --- *)
  ?terminal
  ~port_no
  ()
  =
  let vm_installations = Lazy_perishable.force (Disk.get_router_installations) in
  let network_alias = network in
  (* The ifconfig treeview wants a port 0 configuration at creation time:*)
  let ifconfig_port_row_completions =
     let ipv4_binding =
       let ipv4_config = Ipv4.string_of_config (port_0_ipv4_config) in (* the class parameter *)
       ("IPv4 address", Treeview.Row_item.String ipv4_config)
     in
     let ipv6_binding =
       let ipv6_config = Option.extract_map_or (port_0_ipv6_config) (* the class parameter *) Ipv6.string_of_config "" in
       ("IPv6 address", Treeview.Row_item.String ipv6_config)
     in
     [ ("port0", [ipv4_binding; ipv6_binding]) ]
  in

  object (self) inherit OoExtra.destroy_methods ()

  inherit User_level.node_with_ledgrid_and_defects
    ~network
    ~name ?label ~devkind:`Router
    ~port_no
    ~port_no_min:Const.port_no_min
    ~port_no_max:Const.port_no_max
    ~port_prefix:"port"
    ()
    as self_as_node_with_ledgrid_and_defects

  inherit User_level.virtual_machine_with_history_and_ifconfig
    ~network:network_alias
    ?epithet ?variant ?kernel ?terminal
    ~history_icon:"router"
    ~ifconfig_device_type:"router"
    ~ifconfig_port_row_completions
    ~vm_installations
    ()
    as self_as_virtual_machine_with_history_and_ifconfig

  method polarity = User_level.MDI
  method string_of_devkind = "router"
  method ledgrid_label = "Router"
  method defects_device_type = "router"

  method dotImg iconsize =
   let imgDir = Initialization.Path.images in
   (imgDir^"ico.router."^(self#string_of_simulated_device_state)^"."^iconsize^".png")

  val mutable show_quagga_terminal : (Const.quagga_lowercase_acronym list) = show_quagga_terminal
  method get_show_quagga_terminal = show_quagga_terminal
  method set_show_quagga_terminal x = show_quagga_terminal <- x

  val mutable show_unix_terminal : bool = show_unix_terminal
  method get_show_unix_terminal = show_unix_terminal
  method set_show_unix_terminal x = show_unix_terminal <- x

  val mutable rc_config_unix : bool * string  = rc_config_unix
  method get_rc_config_unix = rc_config_unix
  method set_rc_config_unix x = rc_config_unix <- x

  val mutable rc_config_quagga : (Const.quagga_lowercase_acronym * (bool * string)) list = rc_config_quagga
  method get_rc_config_quagga = rc_config_quagga
  method set_rc_config_quagga x = rc_config_quagga <- x

  val mutable quagga_selected_srvs : (Const.quagga_lowercase_acronym list) = quagga_selected_srvs
  method get_quagga_selected_srvs = quagga_selected_srvs
  method set_quagga_selected_srvs x = quagga_selected_srvs <- x

  (** Create the simulated device *)
  method private make_simulated_device =
    let id = self#id in
    let cow_file_name, get_the_cow_file_name_source =
      self#create_cow_file_name_and_thunk_to_get_the_source
    in
    let rcfile_unix_content =
      match self#get_rc_config_unix with
      | false, _ -> None
      | true, content -> Some content
    in
    let rcfile_quagga_contents : (Const.quagga_lowercase_acronym * string) list =
      (* ListExtra.filter_map (fun (k,(b,c)) -> if b then Some (k,c) else None) self#get_rc_config_quagga *)
      List.map
        (fun (k,(b,c)) ->
           if b then (k,c) else (* continue: *)
           (* Get the default content (configuration) for the key `k': *)
           let c0 = Const.quagga_alternatives#config_content_of_lowercase_acronym (k) in
           (k,c0)
           )
        self#get_rc_config_quagga
    in
    let () =
     Log.printf4
       "About to start the router %s\n  with filesystem: %s\n  cow file: %s\n  kernel: %s\n"
       self#name
       self#get_filesystem_file_name
       cow_file_name
       self#get_kernel_file_name
    in
    let device =
      new Simulation_level.router
        ~parent:self
        ~kernel_file_name:self#get_kernel_file_name
        ?kernel_console_arguments:self#get_kernel_console_arguments
        ?filesystem_relay_script:self#get_filesystem_relay_script
        ~filesystem_file_name:self#get_filesystem_file_name
        ~get_the_cow_file_name_source
        ~cow_file_name
        ~states_directory:(self#get_states_directory)
        ~hostfs_directory:(self#get_hostfs_directory ())
        ~ethernet_interface_no:self#get_port_no
        ~umid:self#get_name
        ~id
        ~show_unix_terminal:self#get_show_unix_terminal
        ?rcfile_unix_content
        ~quagga_selected_srvs:self#get_quagga_selected_srvs
        ~show_quagga_terminal:self#get_show_quagga_terminal
        ~rcfile_quagga_contents
        ~working_directory:(network#project_working_directory)
        ~unexpected_death_callback:self#destroy_because_of_unexpected_death
        ()
    in
    (device :> User_level.node_with_ports_card Simulation_level.device)

  (** Here we also have to manage cow files... *)
  method! private gracefully_shutdown_right_now =
    self_as_node_with_ledgrid_and_defects#gracefully_shutdown_right_now;
    (* We have to manage the hostfs stuff (when in exam mode) and
       destroy the simulated device, so that we can use a new cow file the next time: *)
    Log.printf1 "Calling hostfs_directory on %s...\n" self#name;
    let hostfs_directory = self#get_hostfs_directory () in
    Log.printf "Ok, we're still alive\n";
    (* If we're in exam mode then make the report available in the texts treeview: *)
    (if Initialization.are_we_in_exam_mode then begin
      let treeview_documents = Treeview_documents.extract () in
      Log.printf1 "Adding the report on %s to the texts interface\n" self#name;
      treeview_documents#import_report
	~machine_or_router_name:self#name
	~pathname:(hostfs_directory ^ "/report.html")
	();
      Log.printf1 "Added the report on %s to the texts interface\n" self#name;
    end);
    (* ...And destroy, so that the next time we have to re-create the process command line
	can use a new cow file (see the make_simulated_device method) *)
    self#destroy_right_now


  (** Here we also have to manage LED grids and, for routers, cow files: *)
  method! private poweroff_right_now =
    self_as_node_with_ledgrid_and_defects#poweroff_right_now;
    (* Destroy, so that the next time we have to re-create a simulated device,
       and we start with a new cow: *)
    self#destroy_right_now

  method to_tree =
   Forest.tree_of_leaf ("router", [
      ("name"     ,  self#get_name );
      ("label"   ,   self#get_label);
      ("distrib"  ,  self#get_epithet  );
      ("variant"  ,  self#get_variant_as_string);
      ("kernel"   ,  self#get_kernel   );
      ("show_unix_terminal"  , string_of_bool (self#get_show_unix_terminal));
      ("show_quagga_terminal", Marshal.to_string (self#get_show_quagga_terminal) []);
      ("rc_config_unix",       Marshal.to_string self#get_rc_config_unix []);
      ("rc_config_quagga" ,    Marshal.to_string self#get_rc_config_quagga []);
      ("quagga_selected_srvs", Marshal.to_string self#get_quagga_selected_srvs []);
      ("terminal" ,  self#get_terminal );
      ("port_no"  ,  (string_of_int self#get_port_no))  ;
      ])

 (** A machine has just attributes (no children) in this version. *)
 method! eval_forest_attribute = function
  | ("name"     , x ) -> self#set_name x
  | ("label"    , x ) -> self#set_label x
  | ("distrib"  , x ) -> self#set_epithet x
  | ("variant"  , "") -> self#set_variant None
  | ("variant"  , x ) -> self#set_variant (Some x)
  | ("kernel"   , x ) -> self#set_kernel x
  | ("show_unix_terminal", x )   -> self#set_show_unix_terminal   (bool_of_string x)
  | ("show_quagga_terminal", x ) -> self#set_show_quagga_terminal (Marshal.from_string x 0)
  | ("rc_config_unix", x )       -> self#set_rc_config_unix (Marshal.from_string x 0)
  | ("rc_config_quagga", x )     -> self#set_rc_config_quagga (Marshal.from_string x 0)
  | ("quagga_selected_srvs", x ) -> self#set_quagga_selected_srvs (Marshal.from_string x 0)
  | ("terminal" , x ) -> self#set_terminal x
  | ("port_no"  , x ) -> self#set_port_no  (int_of_string x)
  | _ -> () (* Forward-comp. *)

 method private get_assoc_list_from_ifconfig ~key =
   List.map
     (fun i -> (i,network#ifconfig#get_port_attribute_by_index self#get_name i key))
     (ListExtra.range 0 (self#get_port_no - 1))

 method get_mac_addresses  = self#get_assoc_list_from_ifconfig ~key:"MAC address"
 method get_ipv4_addresses = self#get_assoc_list_from_ifconfig ~key:"IPv4 address"

 method get_port_0_ipv4_config : Ipv4.config =
  let name = self#get_name in
  let x = network#ifconfig#get_port_attribute_by_index name 0 "IPv4 address" in
  match (Ipv4.import x) with
  | Some (Either.Right config)  -> config
  | Some (Either.Left  address) -> (address, 24)
  | None                        -> Const.port_0_ipv4_config_default

 method get_port_0_ipv6_config : Ipv6.config option =
  let name = self#get_name in
  let x = network#ifconfig#get_port_attribute_by_index name 0 "IPv6 address" in
  try Some (Ipv6.config_of_string x) with _ -> Const.port_0_ipv6_config_default

 method set_port_0_ipv4_config (port_0_ipv4_config : Ipv4.config) =
   network#ifconfig#set_port_string_attribute_by_index
     self#get_name 0 "IPv4 address"
     (Ipv4.string_of_config port_0_ipv4_config);

 method set_port_0_ipv6_config (port_0_ipv6_config : Ipv6.config option) =
   network#ifconfig#set_port_string_attribute_by_index
     self#get_name 0 "IPv6 address"
     (Option.extract_map_or (port_0_ipv6_config) (Ipv6.string_of_config) "");

 method update_router_with
   ~name ~label ~port_0_ipv4_config ?port_0_ipv6_config ~port_no ~kernel
   ~show_unix_terminal ~show_quagga_terminal ~rc_config_unix ~rc_config_quagga ~quagga_selected_srvs
   () =
   (* first action: *)
   self_as_virtual_machine_with_history_and_ifconfig#update_virtual_machine_with ~name ~port_no kernel;
   (* then we can set the object property "name" (read by #get_name): *)
   self_as_node_with_ledgrid_and_defects#update_with ~name ~label ~port_no;
   self#set_port_0_ipv4_config (port_0_ipv4_config);
   self#set_port_0_ipv6_config (port_0_ipv6_config);
   self#set_show_quagga_terminal (show_quagga_terminal);
   self#set_show_unix_terminal (show_unix_terminal);
   self#set_rc_config_unix (rc_config_unix);
   self#set_rc_config_quagga (rc_config_quagga);
   self#set_quagga_selected_srvs (quagga_selected_srvs);

end;;

end (* module User_level_router *)

(*-----*)
  WHERE
(*-----*)

module Simulation_level = struct

class virtual ['parent] device = ['parent] Simulation_level.device

(** A router: just a [machine_or_router] with [router = true] *)
class ['parent] router =
  fun ~(parent:'parent)
      ~get_the_cow_file_name_source
      ~(cow_file_name)
      ~states_directory
      ~hostfs_directory
      ~(kernel_file_name)
      ?(kernel_console_arguments)
      ?(filesystem_relay_script)
      ~(filesystem_file_name)
      ~(ethernet_interface_no)
      ?umid
      ~id
      ~show_unix_terminal
      ?rcfile_unix_content
      ~quagga_selected_srvs
      ~show_quagga_terminal
      ~rcfile_quagga_contents
      ~working_directory
      ~unexpected_death_callback
      () ->
  (* --- *)
  (* A unique file will contain all initialization files (one per quagga protocol)
     Note that the type of rcfile_contents is (quagga_lowercase_acronym * string) list *)
  let rcfile_content =
    let xs =
      List.map
        (fun (acronym, content) ->
           (* Example "/etc/quagga/zebra.conf" => TODO: LEGGERE NEI PARAMETRI DELLA MV!! *)
           let config_file = Const.quagga_alternatives#config_file_of_lowercase_acronym (acronym) in
           match (List.mem acronym quagga_selected_srvs) with
           | true  -> Printf.sprintf "cat >%s <<EOF\n%s\nEOF" (config_file) (content)
           | false -> Printf.sprintf "if [[ -e '%s' ]]; then mv -f %s %s.backup; fi" (config_file) (config_file) (config_file)
           )
        (rcfile_quagga_contents)
    in
    (* --- *)
    (* The Unix rc-file will be executed (sourced) BEFORE the quagga settings. In this way we can define some
       Bash variables in the script and use them in the .conf files (Ex: "zebra password $PASSWORD") *)
    let xs = match rcfile_unix_content with None -> xs | Some content -> content::xs in
    (* --- *)
    if xs = [] then None else Some (String.concat "\n" xs)
  in
  (* --- *)
  object(self)

    inherit ['parent] Simulation_level.machine_or_router_with_accessory_processes
      ~parent
      ~router:true
      ~filesystem_file_name(* :"/usr/marionnet/filesystems/router.debian.lenny.sid.fs" *)
      ~kernel_file_name
      ?kernel_console_arguments
      ?filesystem_relay_script
      ?rcfile_content
      ~get_the_cow_file_name_source
      ~cow_file_name
      ~states_directory
      ~hostfs_directory
      ~ethernet_interface_no
      ~memory:Const.memory_default
      ?umid
      (* Change this when debugging the router device *)
      ~console_no:1
      ~console:"none" (* To do: this should be "none" for releases and "xterm" for debugging *)
      ~id
      ~show_unix_terminal
      ~xnest:false
      ~working_directory
      ~unexpected_death_callback
      ()
     (* as self_as_machine_or_router_with_accessory_processes *)

    method device_type = "router"

    initializer

      (* NOTE: show_quagga_terminal : (quagga_lowercase_acronym list); *)
      List.iter
        (* --- *)
        (fun acronym ->
            let name = parent#get_name in
            let host = self#ip_address_eth42 in
            let protocol = uppercase acronym in
            let port_number = Const.quagga_alternatives#port_of_lowercase_acronym (acronym) in
            let xterm_title = Printf.sprintf "%s Quagga terminal (CISCO-IOS-like %s)" name (protocol) in
            self#add_accessory_process
              (new Simulation_level.telnet_process
                ~xterm_title
                ~host
                ~port_number
                ~delay:2. (* not necessary, could be 0. *)
                ~unexpected_death_callback:
                  (fun i _ ->
                      Death_monitor.stop_monitoring i;
                      Log.printf2 "Terminal of router %s closed (pid %d).\n" name i)
                ()))
        (* --- *)
        (show_quagga_terminal)

  end (* object router *)

end (* module Simulation_level *)


(** Just for testing: *)
let test = Dialog_add_or_update.make
