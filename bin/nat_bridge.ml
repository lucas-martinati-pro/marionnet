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


(** "NAT bridge" component implementation: a bridge Marionnet builds for itself,
    on the host but beside it, and takes down when it is done with it (work-stream
    modernisation-world-bridge, episode 7a.3.b).

    Same mechanism as the LAN bridge -- a tap in a two-port hub, see [Bridge_common] --
    and one difference, which is the whole point: the host bridge its tap joins does
    not have to exist beforehand. This component asks [Nat_bridge_host] for one, gets
    a private /24 of its own, and gives it back when it stops. *)

#load "where_p4.cmo"
;;

(* --- *)
module Log = Marionnet_log
module Xforest = Ocamlbricks.Xforest
module Ipv4 = Ocamlbricks.Ipv4
module Ipv6 = Ocamlbricks.Ipv6
(* --- *)
open Gettext

(* --- Choosing the private network
   ---
   The host script picks, by itself, the first /24 free of the host's routes among
   its candidate list (192.168.101 ... 192.168.110). Since episode 10a the user may
   choose instead, exactly as for a world gateway -- and the two must agree, so the
   default offered by the dialog is taken from the SAME list. Only the third byte
   really varies: the netmask is a /24 (the script knows no other) and the host side
   of the bridge is always <subnet>.1 (see Nat_bridge_host.t.host_address), hence the
   last two spin buttons of the dialog are shown but insensitive. *)
module Const = struct
 let first_candidate_third_byte = 101
 let last_candidate_third_byte  = 110
 (* --- *)
 let cidr = 24
 let host_byte = 1
 (* --- *)
 (* The ports of the integrated switch (episode 10b). Same default as a world
    gateway, but a minimum of 1: a NAT bridge serving a single machine is a
    legitimate thing to build, and it is what every NAT bridge was until now. *)
 let port_no_default = 4
 let port_no_min = 1
 let port_no_max = 16
 (* --- *)
 (* The DHCP service (episode 10c.2), on by default as a world gateway's is: the
    same question deserves the same answer, and a component whose guests get their
    addresses by themselves is what one expects of a bridge that already gives them
    the Internet. A project saved before this episode gets that default too -- so a
    host without dnsmasq refuses to build the bridge (E_NO_DNSMASQ) where it used
    to build one; the remedy is the package, or this very check button. *)
 let dhcp_enabled_default = true
 (* --- *)
 (* IPv6 (episode 11), and the two defaults do NOT follow the same rule:
    - [ipv6_enabled] is OFF, deliberately. Unlike DHCP -- which a world gateway
      already offered, so that offering it here only removed a difference -- IPv6
      is something no NAT bridge ever did. A project saved before this episode must
      behave exactly as it did, and turning the host into an IPv6 router is not a
      thing to do to somebody who did not ask. The user ticks the box.
    - [radvd_enabled] is ON, because whoever ticks that box asks for
      autoconfiguration: handing out the prefix is the point, not the extra.
    Both are moot on a host with no IPv6 uplink: the dialog greys the three fields
    out and the host script skips its IPv6 legs (E_NO_IPV6_UPLINK). *)
 let ipv6_enabled_default = false
 let radvd_enabled_default = true
 (* SLAAC works on a /64 and on nothing else, which is why this is a constant and
    not a choice, exactly as [cidr] is for IPv4. *)
 let ipv6_cidr = 64
 (* --- *)
 let network_config_of_third_byte b3 = ((192, 168, b3, host_byte), cidr)
 let network_config_default = network_config_of_third_byte first_candidate_third_byte
end

(* The type of data exchanged with the dialog. Not [Bridge_common.Data] any more (the
   LAN bridge still uses it): a NAT bridge carries its own network. *)
module Data = struct
type t = {
  name           : string;
  label          : string;
  network_config : Ipv4.config;
  dhcp_enabled   : bool;
  ipv6_enabled   : bool;
  ipv6_address   : string;
  radvd_enabled  : bool;
  port_no        : int;
  old_name       : string;
  }

let to_string _t = "<obj>" (* TODO? *)
end (* Data *)

module Tool = struct

 (* The dialog speaks of an address, the .mar of a network address ("192.168.101.0",
    as for a world gateway) and the host script of a /24 prefix ("192.168.101"). *)

 let network_address_of_config (config : Ipv4.config) =
   let ((i1,i2,i3,_),_) = config in
   Printf.sprintf "%i.%i.%i.0" i1 i2 i3

 let subnet_of_network_address (network_address : string) =
   let (i1,i2,i3,_) = Ipv4.of_string network_address in
   Printf.sprintf "%i.%i.%i" i1 i2 i3

 let network_config_of_network_address (network_address : string) : Ipv4.config =
   let (i1,i2,i3,_) = Ipv4.of_string network_address in
   ((i1, i2, i3, Const.host_byte), Const.cidr)

 let network_address_default = network_address_of_config Const.network_config_default

 (* The IPv6 address of the bridge, derived from its IPv4 network (episode 11):
    "192.168.101.0" gives "fd00:192:168:101::1/64". Three consequences worth
    stating, because none of them is obvious:
    - it is a ULA prefix (fd00::/8), the IPv6 equivalent of a private network: it
      is masqueraded on the way out, as the /24 is;
    - there is NO second allocator to keep in step. The /24 of a component is
      already unique in the project (see [first_free_network_address]), so the /64
      derived from it is too -- the collision cannot happen twice;
    - the hexadecimal groups are made to READ like the decimal bytes, so that a
      student can put the two networks side by side. That is a mnemonic and not an
      encoding: 0x192 is not 192, and nothing here pretends otherwise. *)
 let ipv6_address_of_network_address (network_address : string) : string =
   let (i1,i2,i3,_) = Ipv4.of_string network_address in
   Printf.sprintf "fd00:%i:%i:%i::1/%i" i1 i2 i3 Const.ipv6_cidr

 let ipv6_address_default = ipv6_address_of_network_address network_address_default

 (* What the dialog accepts. The shape is narrower than "a valid IPv6 config", and
    on purpose -- it is the shape the host script validates in root, and the shape
    SLAAC needs: <prefix>::1/64, the bridge taking ::1 of its /64 exactly as it
    takes .1 of its /24. Written here as a predicate on the STRING, because that is
    what a Gtk+ entry gives us and what travels in the .mar. *)
 let is_valid_ipv6_address (x : string) : bool =
   Ipv6.String.is_valid_config x
   && (let (address, cidr) = Ipv6.config_of_string x in
       (* [Ipv6.t] is the eight 16-bit groups, so the interface identifier is read
          off the array rather than out of a string: "fd00:1::1" and
          "fd00:1:0:0:0:0:0:1" are the same address, and both must pass. *)
       cidr = Const.ipv6_cidr
       && (match Array.to_list address with
           | [g1; g2; g3; g4; 0; 0; 0; 1] ->
               (* Three prefixes are not networks one announces, and the host script
                  refuses all three in root: link-local (fe80::/10), multicast
                  (ff00::/8) and the loopback. Measured the hard way -- without this,
                  "fe80::1/64" was accepted by the model and refused only at start-up,
                  far from the gesture. The bound covers the deprecated site-local
                  range too; nothing legitimate lives at or above fe80. *)
               g1 < 0xfe80 && (g1, g2, g3, g4) <> (0, 0, 0, 0)
           | _ -> false))

 (* The canonical spelling of an IPv6 address: lower case, and the longest run of
    zeros compressed. It matters because the guard of the host script -- the one that
    runs in root -- accepts only that spelling, deliberately (it derives the prefix
    to advertise by removing a fixed suffix, instead of parsing an address). A user
    typing "FD00::1/64" is not making a mistake, and neither is one writing
    "fd00:0:0:0:0:0:0:1/64": normalising is what keeps the model and that guard from
    ever disagreeing. Measured the hard way -- uppercase passed the model and was
    refused at start-up, in root, far from the gesture.
    ---
    Total on purpose: what it cannot parse it returns unchanged, the refusal being
    the business of [is_valid_ipv6_address] and of the guard itself. *)
 let canonical_ipv6_address (x : string) : string =
   if not (Ipv6.String.is_valid_config x) then x else
   let (address, cidr) = Ipv6.config_of_string x in
   Printf.sprintf "%s/%i" (Ipv6.to_string address) cidr

 (* The networks already held by the NAT bridges of this project. Read from their
    [to_tree] rather than from a cast to the class defined below: the answer is the
    same, and this way the function may be called from the class's own default
    argument. *)
 let network_addresses_in_use (network : User_level.network) : string list =
   List.filter_map
     (fun n -> let ((_, attrs), _) = n#to_tree in List.assoc_opt "network_address" attrs)
     (network#get_nodes_such_that ~devkind:`Nat_bridge (fun _ -> true))

 (** The network a NEW component takes when nobody says which one: the first
     candidate of the host script's own list which no other NAT bridge of this
     project already holds. This is what keeps the behaviour of yesterday, when the
     script chose alone -- two components posted one after the other get two separate
     /24 -- and it holds for every door: the dialog, the control channel, and the
     re-reading of a project saved before this attribute existed. *)
 let first_free_network_address (network : User_level.network) : string =
   let taken = network_addresses_in_use network in
   let rec search b3 =
     if b3 > Const.last_candidate_third_byte then network_address_default else
     let candidate = network_address_of_config (Const.network_config_of_third_byte b3) in
     if List.mem candidate taken then search (b3 + 1) else candidate
   in
   search Const.first_candidate_third_byte

end (* module Tool *)


module Make_menus (Params : sig
  val st      : State.globalState
  val packing : [ `toolbar of GButton.toolbar | `menu_parent of Menu_factory.menu_parent ]
 end) = struct

  open Params

  module Toolbar_entry = struct
   let imagefile = "ico.nat_bridge.palette.png"
   let tooltip   = (s_ "NAT bridge (give the virtual machines access to the Internet through a private bridge that Marionnet builds by itself: no host configuration, and it also works when the host is on Wi-Fi)")
   let packing   = Params.packing
  end

  module Add = struct
    include Data

    let key = Some GdkKeysyms._N

    (* Two questions, in that order: the name, as everywhere else, and -- when IPv6
       is enabled -- the address. The red text of the entry is a hint, not a
       refusal: without this check an ill-formed prefix would reach the host script,
       which validates it in root and would refuse it at START-UP time, far from the
       gesture that caused it. *)
    let ok_callback t =
      match Gui_bricks.Ok_callback.check_name t.name t.old_name st#network#name_exists t with
      | None -> None
      | Some t ->
          if (not t.ipv6_enabled) || Tool.is_valid_ipv6_address t.ipv6_address then Some t else
          let () =
            Simple_dialogs.error
              (s_ "Ill-formed IPv6 address")
              (Printf.sprintf
                 (f_ "\"%s\" is not an address of the expected shape. The bridge takes the first address of a /64, so it must be written <prefix>::1/64 -- for instance fd00:192:168:101::1/64.")
                 t.ipv6_address)
              ()
          in
          None

    let dialog () =
      let name = st#network#suggestedName "N" in
      let network_config =
        Tool.network_config_of_network_address (Tool.first_free_network_address st#network)
      in
      Dialog_add_or_update.make ~title:(s_ "Add NAT bridge") ~name ~network_config ~ok_callback ()

    let reaction { name = name; label = label; network_config = network_config;
                   dhcp_enabled = dhcp_enabled; ipv6_enabled = ipv6_enabled;
                   ipv6_address = ipv6_address; radvd_enabled = radvd_enabled;
                   port_no = port_no; _ } =
      let action () = ignore (
        new User_level_nat_bridge.nat_bridge
          ~network:st#network
          ~name
          ~label
          ~network_address:(Tool.network_address_of_config network_config)
          ~dhcp_enabled
          ~ipv6_enabled
          ~ipv6_address
          ~radvd_enabled
          ~port_no
          ())
      in
      st#network_change action ();

  end

  module Properties = struct
    include Data
    let dynlist () = st#network#get_node_names_that_can_modify ~devkind:`Nat_bridge ()

    let dialog name () =
     let d = (st#network#get_node_by_name name) in
     let h = ((Obj.magic d):> User_level_nat_bridge.nat_bridge) in
     let title = (s_ "Modify NAT bridge")^" "^name in
     let label = d#get_label in
     let network_config = Tool.network_config_of_network_address h#get_network_address in
     let dhcp_enabled = h#get_dhcp_enabled in
     let ipv6_enabled = h#get_ipv6_enabled in
     let ipv6_address = h#get_ipv6_address in
     let radvd_enabled = h#get_radvd_enabled in
     let port_no = h#get_port_no in
     (* Not Const.port_no_min: the smallest number of ports which still holds every
        cable already connected to this component (as for a world gateway): *)
     let port_no_min = st#network#port_no_lower_of (h :> User_level.node) in
     Dialog_add_or_update.make
       ~title ~name ~label ~network_config ~dhcp_enabled
       ~ipv6_enabled ~ipv6_address ~radvd_enabled
       ~port_no ~port_no_min
       ~ok_callback:Add.ok_callback ()

    let reaction { name = name; label = label; network_config = network_config;
                   dhcp_enabled = dhcp_enabled; ipv6_enabled = ipv6_enabled;
                   ipv6_address = ipv6_address; radvd_enabled = radvd_enabled;
                   port_no = port_no; old_name = old_name } =
      let d = (st#network#get_node_by_name old_name) in
      let h = ((Obj.magic d):> User_level_nat_bridge.nat_bridge) in
      let action () =
        h#update_nat_bridge_with ~name ~label ~port_no ~dhcp_enabled
          ~ipv6_enabled ~ipv6_address ~radvd_enabled
          ~network_address:(Tool.network_address_of_config network_config)
      in
      st#network_change action ();

  end

  module Remove = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")

    let dynlist () = st#network#get_node_names_that_can_destroy ~devkind:`Nat_bridge ()

    let dialog name () =
      Gui_bricks.Dialog.yes_or_cancel_question
        ~title:(s_ "Remove")
        ~markup:(Printf.sprintf (f_ "Are you sure that you want to remove %s\nand all the cables connected to this %s?") name (s_ "NAT bridge"))
        ~context:name
        ()

    let reaction name =
      let d = (st#network#get_node_by_name name) in
      let h = ((Obj.magic d):> User_level_nat_bridge.nat_bridge) in
      let action () = h#destroy in
      st#network_change action ();

  end

  module Startup = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    (* Not an alias of Properties.dynlist: each menu reads its own guard (user_level.ml). *)
    let dynlist () = st#network#get_node_names_that_can_startup ~devkind:`Nat_bridge ()
    let dialog     = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#startup

  end

  module Stop = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_gracefully_shutdown ~devkind:`Nat_bridge ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#gracefully_shutdown

  end

  module Suspend = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_suspend ~devkind:`Nat_bridge ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#suspend

  end

  module Resume = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_resume ~devkind:`Nat_bridge ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#resume

  end

 module Create_entries =
  Gui_toolbar_COMPONENTS_layouts.Layout_for_network_node (Params) (Toolbar_entry) (Add) (Properties) (Remove) (Startup) (Stop) (Suspend) (Resume)

 (* Subscribe this kind of component to the network club. Beware: this is also what
    makes a saved project readable -- without it a `nat_bridge' subtree of a .mar is
    silently skipped at loading time (work-stream modernisation-world-bridge, ep. 7a.3): *)
 st#network#subscribe_a_try_to_add_procedure Eval_forest_child.try_to_add_nat_bridge;

end

(*-----*)
  WHERE
(*-----*)

module Dialog_add_or_update = struct

(* This function may be useful for testing the widget creation without
   recompiling the whole project. *)
let make
 ?(title="Add NAT bridge")
 ?(name="")
 ?label
 ?(network_config=Const.network_config_default)
 ?(dhcp_enabled=Const.dhcp_enabled_default)
 ?(ipv6_enabled=Const.ipv6_enabled_default)
 ?ipv6_address
 ?(radvd_enabled=Const.radvd_enabled_default)
 ?(port_no=Const.port_no_default)
 ?(port_no_min=Const.port_no_min)
 ?(port_no_max=Const.port_no_max)
 ?(help_callback=help_callback) (* defined backward with "WHERE" *)
 ?(ok_callback=(fun data -> Some data))
 ?(dialog_image_file=Initialization.Path.images^"ico.nat_bridge.dialog.png")
 () :'result option =
  let old_name = name in
  let ((b1,b2,b3,b4),b5) = network_config in
  (* Not a constant default: the IPv6 prefix is DERIVED from the IPv4 network of
     this very component (episode 11), so the dialog of a new bridge offers the
     /64 that matches the /24 it is about to take. *)
  let ipv6_address =
    match ipv6_address with
    | Some x -> x
    | None   -> Tool.ipv6_address_of_network_address (Tool.network_address_of_config network_config)
  in
  let (w,_,name,label) =
    Gui_bricks.Dialog_add_or_update.make_window_image_name_and_label
      ~title
      ~image_file:dialog_image_file
      ~image_tooltip:(s_ "NAT bridge: a private bridge that Marionnet builds on the host, with its own network, from which the virtual machines reach the Internet (see the help button)")
      ~name
      ~name_tooltip:(s_ "NAT bridge name. This name must be unique in the virtual network. Suggested: N1, N2, ...")
      ?label
      ()
  in

  (* The private network of this bridge, chosen as for a world gateway. The last byte
     and the netmask are shown but insensitive: the host side of the bridge is always
     <subnet>.1 and the script knows no netmask but /24. *)
  let ((s1,s2,s3,s4,s5), dhcp_enabled, ipv6, radvd_enabled, port_no) =
    let vbox = GPack.vbox ~homogeneous:false ~border_width:20 ~spacing:10 ~packing:w#vbox#add () in
    let form =
      Gui_bricks.make_form_with_labels
        ~packing:vbox#add
        [ (s_ "IPv4 address"); (s_ "DHCP service");
          (* Episode 11. Four of these five labels cost nothing: they are the ones a
             world gateway and a router already use, word for word -- "IPv6 address"
             comes from the router dialog and is translated in all fourteen
             catalogues. The same thing must be called by the same name anyway. *)
          (s_ "IPv6 address"); (s_ "RADVD service");
          (s_ "Integrated switch ports") ]
    in
    let network_config =
      Gui_bricks.spin_ipv4_address_with_cidr_netmask
        ~packing:(form#add_with_tooltip ~just_for_label:()
                    (s_ "IPv4 address of the bridge, which is the default gateway of the virtual machines connected to it"))
        b1 b2 b3 b4 b5
    in
    (* The DHCP server is left on the bridge by the host script (episode 10c.1); the
       component only says whether it wants one. Same label as a world gateway --
       the tooltip cannot be the same, since that one names the gateway. *)
    let dhcp_enabled =
      GButton.check_button
        ~active:dhcp_enabled
        ~packing:(form#add_with_tooltip
                    (s_ "Should the bridge provide a DHCP service to the virtual machines connected to it?")) ()
    in
    (* The IPv6 half (episode 11). ONE widget carries two things, and that is the
       existing idiom of this program (Gui_bricks.activable_entry, as the router
       dialog uses for its own optional IPv6 configuration): the check button is the
       master switch -- off by default -- and it is what makes the address entry
       sensitive. The entry turns red on anything that is not <prefix>::1/64, the
       shape SLAAC needs and the shape the host script validates in root. *)
    let ipv6 : < active : bool;  content : string;  hbox : GPack.box;
                 check_button : GButton.toggle_button;  entry : GEdit.entry > =
      Gui_bricks.activable_entry
        ~packing:(form#add_with_tooltip
                    (s_ "Should the virtual machines connected to the bridge also get an IPv6 address by themselves? The address is the one of the bridge, of the shape <prefix>::1/64: its /64 is announced to the guests, and translated (NAT66) on the way out. This needs the host itself to have IPv6."))
        ~active:ipv6_enabled
        ~text:ipv6_address
        ~red_text_condition:(fun x -> not (Tool.is_valid_ipv6_address x))
        ()
    in
    (* The entry showed about half of an address. 32 characters leave real margin
       around what it must hold: [fd00:192:168:101::1/64] is 22 and a hand-written
       prefix such as [2001:db8:1234:5678::1/64] is 25, so nothing a user types ends up
       half hidden. In Gtk+ 3 this is a MINIMUM request, so a wider dialog simply gives
       the entry more; it stays well below the width of the IPv4 row.
       ---
       The width is set HERE because it is a property of what THIS field holds. The
       spacing that used to sit beside it is not: it was the same defect in the two
       dialogs using [activable_entry], so it now lives in the helper. *)
    let () = ipv6#entry#set_width_chars 32 in
    let radvd_enabled =
      GButton.check_button
        ~active:radvd_enabled
        ~packing:(form#add_with_tooltip
                    (s_ "Should the bridge announce its IPv6 network (Router Advertisements), so that the virtual machines configure themselves without any DHCP? Without it they have an IPv6 network but must be numbered by hand.")) ()
    in
    (* The labels of this form are the ones a world gateway already uses, word
       for word, hence already translated: the same thing must be called by the same
       name, and this costs no new msgid. Step 1 and not 2 (the gateway's step): the
       minimum here is 1, so a step of 2 would only ever offer odd numbers. *)
    let port_no =
      Gui_bricks.spin_byte
        ~packing:(form#add_with_tooltip (s_ "The number of ports of the integrated switch"))
        ~lower:port_no_min ~upper:port_no_max ~step_incr:1
        port_no
    in
    (network_config, dhcp_enabled, ipv6, radvd_enabled, port_no)
  in
  s4#misc#set_sensitive false;
  s5#misc#set_sensitive false;

  (* --- The IPv6 fields, and the one question that decides whether they mean
     anything (episode 11)
     ---
     On a host with no global IPv6 address and no IPv6 default route, nothing here
     can work: announcing a default router that cannot route anywhere is a lie, and
     the host script skips its IPv6 legs for exactly that reason. So the two widgets
     are shown -- hiding them would leave the user wondering -- but insensitive, and
     a note says why. The predicate is the host command's own (`check-ipv6', no
     privilege needed), asked EVERY time this dialog opens: tethering a phone or
     joining a VPN changes the answer, and a stale one would be worse than none.
     ---
     Values already stored are NOT overwritten when the fields are greyed: a project
     configured at the university keeps its IPv6 settings when it is opened at home,
     and gets them back where they work. *)
  let host_has_ipv6 = Nat_bridge_host.has_ipv6_uplink () in
  let refresh_radvd_sensitiveness () =
    radvd_enabled#misc#set_sensitive (host_has_ipv6 && ipv6#active)
  in
  let () = ignore (ipv6#check_button#connect#toggled (fun () -> refresh_radvd_sensitiveness ())) in
  let () = if not host_has_ipv6 then ipv6#hbox#misc#set_sensitive false in
  let () = refresh_radvd_sensitiveness () in
  let () =
    if not host_has_ipv6 then
      let note =
        GMisc.label
          ~markup:("<i>" ^ Glib.Markup.escape_text
                     (s_ "Note: the IPv6 fields are disabled because this host has no IPv6 address and no IPv6 route of its own. A bridge cannot give the virtual machines an IPv6 access it does not have itself.")
                   ^ "</i>")
          ~xalign:0.0 ~line_wrap:true ~width:420 ~xpad:20 ~ypad:5
          ~packing:w#vbox#add ()
      in
      (* Gtk+ 3: ~width is a minimum, not a cap -- see the note below. *)
      note#set_max_width_chars 72
  in

  (* The IPv6 default is derived from the IPv4 network, so it follows that network
     when the user changes it -- but ONLY while it is still the derived value.
     Overwriting a prefix somebody typed by hand would be worse than leaving a
     default that no longer matches. *)
  let () =
    let derived_now () =
      Tool.ipv6_address_of_network_address
        (Printf.sprintf "%i.%i.%i.0"
           (int_of_float s1#value) (int_of_float s2#value) (int_of_float s3#value))
    in
    let last_derived = ref ipv6_address in
    let follow () =
      if ipv6#content = !last_derived then begin
        let fresh = derived_now () in
        last_derived := fresh;
        ipv6#entry#set_text fresh
      end
    in
    (* Three separate connections rather than a list: putting the spin buttons in one
       makes the type checker unify their (closed, very large) object types, which is
       a lot of noise for no gain. *)
    ignore (s1#connect#value_changed (fun () -> follow ()));
    ignore (s2#connect#value_changed (fun () -> follow ()));
    ignore (s3#connect#value_changed (fun () -> follow ()))
  in

  (* Said at the moment of the gesture, not as an unexplained failure at start-up
     time: this component asks for administrator rights the first time it runs
     (work-stream modernisation-world-bridge, episode 6). Once the rule is installed
     the probe answers `true' and the notice goes away by itself. *)
  let () =
    if not (Nat_bridge_host.is_usable ()) then
      let note =
        GMisc.label
          ~markup:("<i>" ^ Glib.Markup.escape_text
                     (s_ "Note: the first time this component is started, Marionnet will ask for your password, once, in order to grant itself the right to build its own private bridge.")
                   ^ "</i>")
          ~xalign:0.0 ~line_wrap:true ~width:420 ~xpad:20 ~ypad:5
          ~packing:w#vbox#add ()
      in
      (* Gtk+ 3: ~width is only the *minimum* request; a wrapping label still asks
         for the whole sentence as its natural width, and the dialog obeys. Capping
         the natural width is what makes the text wrap, in every language. *)
      note#set_max_width_chars 72
  in

  let get_widget_data () :'result =
    let name = name#text in
    let label = label#text in
    let network_config =
      let s1 = int_of_float s1#value in
      let s2 = int_of_float s2#value in
      let s3 = int_of_float s3#value in
      let s4 = int_of_float s4#value in
      let s5 = int_of_float s5#value in
      ((s1,s2,s3,s4),s5)
    in
    let dhcp_enabled = dhcp_enabled#active in
    (* Read from the widgets even when they are greyed out: they then still hold the
       values this dialog was given, which is precisely what must survive being
       opened on a host without IPv6. *)
    let ipv6_enabled = ipv6#active in
    let ipv6_address = ipv6#content in
    let radvd_enabled = radvd_enabled#active in
    let port_no = int_of_float port_no#value in
      { Data.name = name;
        Data.label = label;
        Data.network_config = network_config;
        Data.dhcp_enabled = dhcp_enabled;
        Data.ipv6_enabled = ipv6_enabled;
        Data.ipv6_address = ipv6_address;
        Data.radvd_enabled = radvd_enabled;
        Data.port_no = port_no;
        Data.old_name = old_name;
        }
  in
  (* The result of make is the result of the dialog loop (of type 'result option): *)
  Gui_bricks.Dialog_run.ok_or_cancel w ~ok_callback ~help_callback ~get_widget_data ()

(*-----*)
  WHERE
(*-----*)

 let help_callback =
   let title = (s_ "ADD OR MODIFY A NAT BRIDGE") in
   let msg   = (s_ "\
A NAT bridge gives the virtual machines access to the real network of the host, \
and through it to the Internet, WITHOUT touching the host configuration in any \
way. Marionnet builds, on the host, a bridge of its own, gives it a private \
network (a /24 of addresses free of the host routes) and translates the \
addresses (NAT) of everything leaving it. When the component is stopped, or \
when Marionnet exits, that bridge and its rules are removed: the host is left \
exactly as it was found.\n\n\
Each NAT bridge of the project has its OWN private network: two of these \
components are two separate networks, not two doors onto the same one.\n\n\
- IPv4 address: the address of the bridge itself, which is the default gateway \
of the virtual machines connected to it. Only the first three bytes can be \
chosen: the network is a /24, the bridge takes its first address, and the \
guests may use the rest of it (from .2 to .254). A network the host already \
routes is refused rather than stolen -- the proposed value is one Marionnet \
knows to be free.\n\n\
- DHCP service: when it is enabled, the bridge also hands out addresses, from \
.100 to .200 of its own network, together with itself as default gateway and as \
DNS server -- so a virtual machine configured for DHCP needs nothing else. The \
addresses below .100 are left free for the machines a teacher wants to number by \
hand. Disable it to give every guest a static address, or when the host has no \
dnsmasq installed (the package is dnsmasq-base on Debian and Ubuntu): without it \
the bridge refuses to be built at all.\n\n\
- IPv6 address: when the check button beside it is enabled, the bridge also gets \
an IPv6 network -- a private (ULA) /64 whose first address it takes, just as it \
takes the first address of its /24 -- and translates it (NAT66) on the way out. \
The proposed prefix is derived from the IPv4 network, so that the two read alike, \
but any /64 may be written instead, for instance the documentation prefix of a \
lab handout. This requires the HOST to have IPv6 itself: without a global IPv6 \
address and an IPv6 route of its own, these two fields are disabled, because a \
bridge cannot hand out an access it does not have.\n\n\
- RADVD service: when it is enabled, the bridge announces its IPv6 network \
(Router Advertisements), and the virtual machines configure themselves from it -- \
address, default route and DNS server -- with no DHCP involved at all. This is \
stateless autoconfiguration (SLAAC), and it is why a /64 is imposed: nothing \
else works. Disable it to number the guests by hand while keeping the IPv6 \
network.\n\n\
- Integrated switch ports: the number of virtual machines that may be plugged \
DIRECTLY into this component. They are all in the same network, they see each \
other, and they all reach the Internet through the bridge.\n\n\
NAT bridge, LAN bridge or gateway? Use a NAT BRIDGE to reach the Internet with \
real network performance and no host configuration -- it is also the only one \
of the three bridges that works when the host is connected over Wi-Fi. Use a \
LAN BRIDGE when the virtual machines must appear DIRECTLY on the physical \
network of the host (its DHCP, its DNS, its other machines), or to link \
Marionnet instances running on different computers: that one needs a Linux \
bridge on the host side. Use a WORLD GATEWAY for a self-contained NAT router \
that needs no privilege at all.\n\n\
The first time a NAT bridge is started, Marionnet asks for your password, once, \
in order to grant itself a narrow and permanent right: to build and take down \
bridges named after its own process, and the translation rules that go with \
them. Nothing else.")
   in Simple_dialogs.help title msg ;;

end

(*-----*)
  WHERE
(*-----*)

module Eval_forest_child = struct

 let try_to_add_nat_bridge (network:User_level.network) ((root,children):Xforest.tree) =
  try
   (match root with
    | ("nat_bridge", attrs) ->
    	let name  = List.assoc "name"  attrs in
        (* Read here and given to the CONSTRUCTOR, not left to eval_forest_attribute:
           the number of ports decides how many hublets the node is built with. A
           project saved before episode 10b has no such attribute, and gets the
           default -- as a world gateway does (world_gateway.ml). *)
        let port_no =
          try int_of_string (List.assoc "port_no" attrs) with _ -> Const.port_no_default
        in
        Log.printf2 "Importing NAT bridge \"%s\" with %d ports...\n" name port_no;
        let x = new User_level_nat_bridge.nat_bridge ~network ~name ~port_no () in
	x#from_tree ("nat_bridge", attrs) children  ;
        Log.printf1 "NAT bridge \"%s\" successfully imported.\n" name;
        true
   | _ ->
        false
   )
  with _ -> false

end (* module Eval_forest_child *)


(*-----*)
  WHERE
(*-----*)


module User_level_nat_bridge = struct

class nat_bridge =

 fun ~network
     ~name
     ?label
     ?network_address
     ?(dhcp_enabled=Const.dhcp_enabled_default)
     ?(ipv6_enabled=Const.ipv6_enabled_default)
     ?ipv6_address
     ?(radvd_enabled=Const.radvd_enabled_default)
     ?(port_no=Const.port_no_default)
     () ->
  (* Not a constant default: a component created without an explicit network takes
     the first one this project has left free (see [Tool.first_free_network_address]),
     so that two of them never collide, wherever they are created from. *)
  let network_address =
    match network_address with
    | Some x -> x
    | None   -> Tool.first_free_network_address (network :> User_level.network)
  in
  (* Derived from the network above, and therefore computed AFTER it: a component
     created without an explicit prefix gets the /64 that matches its own /24, so the
     two networks of one bridge read alike and neither can collide. *)
  let ipv6_address =
    (* Normalised here too: the initial value of an instance variable does NOT go
       through its setter, and this one may come straight from a dialog entry. *)
    match ipv6_address with
    | Some x -> Tool.canonical_ipv6_address x
    | None   -> Tool.ipv6_address_of_network_address network_address
  in
  object (self)

  inherit
    Bridge_common.User_level_bridge.bridge
      ~network
      ~name ?label
      ~devkind:`Nat_bridge
      ~kind_name:"nat_bridge"
      (* Unlike the LAN bridge, this component offers the ports of an integrated
         switch, and names them as a switch does (episode 10b): *)
      ~port_no
      ~port_no_min:Const.port_no_min
      ~port_no_max:Const.port_no_max
      ~port_prefix:"port"
      ~user_port_offset:1
      ()
    as self_as_bridge

  (** The private network of this component, as ["192.168.101.0"] -- the same shape
      as the one of a world gateway, and the shape written into the project file.
      What the host script wants is its /24 prefix, and what the guests need is its
      first address: both are derived, never stored twice. *)
  val mutable network_address : string = network_address
  method get_network_address = network_address
  method set_network_address x = network_address <- x

  (** Whether the host script is asked to leave a DHCP/DNS server on this bridge
      (episode 10c.2). Absent from a project saved before that episode, which
      therefore reads back the default -- [true], as for a world gateway. *)
  val mutable dhcp_enabled : bool = dhcp_enabled
  method get_dhcp_enabled = dhcp_enabled
  method set_dhcp_enabled x = dhcp_enabled <- x

  (** Whether this bridge also gives its guests an IPv6 network (episode 11).
      Absent from a project saved before that episode, which therefore reads back
      the default -- [false] here, unlike [dhcp_enabled]: IPv6 is something no NAT
      bridge used to do, so an old project must keep behaving as it did. *)
  val mutable ipv6_enabled : bool = ipv6_enabled
  method get_ipv6_enabled = ipv6_enabled
  method set_ipv6_enabled x = ipv6_enabled <- x

  (** The IPv6 address of the bridge, of the shape ["fd00:192:168:101::1/64"]: the
      bridge takes the first address of its /64 exactly as it takes the first of its
      /24, and that /64 is what the guests configure themselves from. Stored (and not
      derived on the fly from [network_address]) because the user may choose it --
      typically the documentation prefix of a lab handout. *)
  val mutable ipv6_address : string = ipv6_address
  method get_ipv6_address = ipv6_address
  (* Normalised on the way in, once, for every door at once: the dialog, the control
     channel, the project file and the constructor all go through here. *)
  method set_ipv6_address x = ipv6_address <- Tool.canonical_ipv6_address x

  (** Whether the bridge ANNOUNCES that network (Router Advertisements), which is
      what lets the guests configure themselves without any DHCP. On by default:
      whoever enables IPv6 wants autoconfiguration -- doing without it is the
      special case, not the other way round. *)
  val mutable radvd_enabled : bool = radvd_enabled
  method get_radvd_enabled = radvd_enabled
  method set_radvd_enabled x = radvd_enabled <- x

  method! extra_tree_attributes = [
    ("network_address", self#get_network_address);
    ("dhcp_enabled", string_of_bool self#get_dhcp_enabled);
    ("ipv6_enabled", string_of_bool self#get_ipv6_enabled);
    ("ipv6_address", self#get_ipv6_address);
    ("radvd_enabled", string_of_bool self#get_radvd_enabled);
    ("port_no", string_of_int self#get_port_no);
    ]

  method! eval_forest_attribute = function
  | ("network_address", x) ->
      (* The IPv6 prefix follows the IPv4 network while it is still the DERIVED one --
         the same rule the dialog applies to its entry (episode 11). It matters when
         reading a project saved BEFORE that episode: its network arrives here, after
         the constructor has already derived a prefix from the network it allocated.
         An [ipv6_address] written in the file is applied just after this, and wins,
         because [extra_tree_attributes] lists it after [network_address]. *)
      let () =
        if self#get_ipv6_address = Tool.ipv6_address_of_network_address self#get_network_address
        then self#set_ipv6_address (Tool.ipv6_address_of_network_address x)
      in
      self#set_network_address x
  | ("dhcp_enabled", x) -> self#set_dhcp_enabled (bool_of_string x)
  | ("ipv6_enabled", x) -> self#set_ipv6_enabled (bool_of_string x)
  | ("ipv6_address", x) ->
      (* Validated HERE, and not only in the dialog: this is also the path the control
         channel writes through, and it turns an exception into a refusal that names
         the value (control_server.ml, `the model refused ...'). Accepting an
         ill-formed prefix here would postpone the refusal to start-up time, in root,
         far from the gesture that caused it -- and the same guard covers a
         hand-written .mar. *)
      if Tool.is_valid_ipv6_address x then self#set_ipv6_address x else
      failwith (Printf.sprintf "%S is not of the shape <prefix>::1/64 (e.g. fd00:192:168:101::1/64)" x)
  | ("radvd_enabled", x) -> self#set_radvd_enabled (bool_of_string x)
  | ("port_no", x) -> self#set_port_no (int_of_string x)
  | a -> self_as_bridge#eval_forest_attribute a

  (** Redefined: the drawing says which network this bridge offers, exactly as the
      one of a world gateway does. *)
  method! label_for_dot =
    let ip_gw = Ipv4.string_of_config (Tool.network_config_of_network_address self#get_network_address) in
    match self#get_label with
    | "" -> ip_gw
    | _  -> Printf.sprintf "%s <br/> %s" ip_gw self#get_label

  method update_nat_bridge_with ~name ~label ~port_no ~network_address ~dhcp_enabled
                                ~ipv6_enabled ~ipv6_address ~radvd_enabled =
    (* The following call ensures that the simulated device will be destroyed, hence
       that the bridge is given back before another one is built on another network: *)
    self#update_bridge_with ~name ~label ~port_no;
    self#set_network_address network_address;
    self#set_dhcp_enabled dhcp_enabled;
    self#set_ipv6_enabled ipv6_enabled;
    self#set_ipv6_address ipv6_address;
    self#set_radvd_enabled radvd_enabled;

  (** Create the simulated device *)
  method private make_simulated_device =
   ((new Simulation_level_nat_bridge.nat_bridge
        ~parent:self
        (* A function, not a value, and for the same reason the trunk defers
           [resolve_bridge_name]: the network may be changed between the moment this
           object is built and the moment it is started. Through the GUI the point is
           moot (a modification destroys the simulated device), but the control
           channel writes the field in place -- and a component restarted after its
           address was corrected must use the NEW one. *)
        ~subnet:(fun () -> Tool.subnet_of_network_address self#get_network_address)
        (* A function too, and for the same reason: the check button of the dialog
           destroys this object, but a `set' through the control channel does not. *)
        ~get_dhcp:(fun () -> self#get_dhcp_enabled)
        (* Functions again, and for the same reason (episode 11). The option is
           built here rather than in the simulated object so that "IPv6 is off" and
           "IPv6 is on with this address" are ONE value, impossible to get out of
           step -- and so that a `set' of either field through the control channel is
           honoured by the next start-up. *)
        ~get_ipv6:(fun () -> if self#get_ipv6_enabled then Some self#get_ipv6_address else None)
        ~get_radvd:(fun () -> self#get_radvd_enabled)
        (* By value, this one: a change of the number of ports goes through
           [update_with], which destroys this very object (control channel
           included -- port_no is one of its two structural fields). *)
        ~hublet_no:self#get_port_no
        ~working_directory:(network#project_working_directory)
        ~unexpected_death_callback:self#destroy_because_of_unexpected_death
        ()) :> User_level.node Simulation_level.device)

end (* class nat_bridge *)

end (* module User_level_nat_bridge *)

(*-----*)
  WHERE
(*-----*)

module Simulation_level_nat_bridge = struct

(* --- Allocating the instance numbers
   ---
   One bridge per component means one number per component, and the numbers are
   allocated HERE because this is where the components are: `Nat_bridge_host' only
   uses them as a key (see its interface).
   ---
   The numbers in use are read from the host itself -- the bridges named after our
   pid -- so a crashed run leaves nothing behind to confuse a later one and there is
   no state file to keep in step with reality.
   ---
   Reading them and creating the bridge must be ONE atomic gesture: two components
   started in parallel by the task runner would otherwise read the same list and
   choose the same number, the second `up' landing on a bridge that already exists.
   Lock order (this mutex, then the one of Nat_bridge_host) is the same everywhere
   below, hence no deadlock. *)

let allocation_mutex = Mutex.create ()

let taken_instances () : int list =
  match Nat_bridge_host.status () with
  | Ok bridges ->
      let my_pid = Unix.getpid () in
      List.filter_map
        (fun (t : Nat_bridge_host.t) ->
           if t.Nat_bridge_host.owner_pid = my_pid then t.Nat_bridge_host.instance else None)
        bridges
  | Error e ->
      (* Not fatal: at worst we choose a number that is already taken, and the
         script refuses to build a bridge that exists with another subnet. *)
      let () = Log.printf1 "nat_bridge: cannot read the bridges of this process (%s)\n" (Nat_bridge_host.string_of_error e) in
      []

let smallest_free (taken : int list) : int =
  let rec search n = if List.mem n taken then search (n + 1) else n in
  search 1

(* Deliberately impossible as a bridge name (a device name is at most 15 characters
   and this one is longer): when we could not build a bridge, the tap has to fail to
   join it, loudly, exactly as a LAN bridge fails when its host bridge is missing.
   Returning something plausible would be worse -- it might exist. *)
let no_bridge_at_all = "marionnet-no-such-bridge"

(** The mechanism itself -- the tap, the two-port hub, the internal cable and their
    life cycle -- is the one shared with the LAN bridge (see [Bridge_common]). What
    this component adds is a bridge of its own: one that does not exist until it is
    asked for, and that is given back when the component stops. *)
class ['parent] nat_bridge =
  fun (* ~id *)
      ~(parent:'parent)
      ~(subnet : unit -> string)  (* the /24 prefix chosen by the user, e.g. "192.168.101" *)
      ~(get_dhcp : unit -> bool)  (* whether the bridge serves DHCP (episode 10c.2) *)
      ~(get_ipv6 : unit -> string option) (* the IPv6 address of the bridge, if any (episode 11) *)
      ~(get_radvd : unit -> bool)         (* whether that /64 is announced (episode 11) *)
      ~(hublet_no : int)          (* the ports of the integrated switch (episode 10b) *)
      ~working_directory
      ~unexpected_death_callback
      () ->
  (* The number this component holds, WHILE it holds it. It is not a property of the
     component (a project saved and reloaded may well get another one), it is a
     property of the run, hence a reference and not a field of the .mar: *)
  let instance = ref None in
  (* --- *)
  (* Whether the user has already been told that this start-up got no bridge. Two
     reasons for it: a start-up resolves its bridge TWICE (the simulated object is
     built, then started), and a warning shown twice for one gesture is a bug of its
     own; and the same component may be started again after the cause is fixed, hence
     the re-arming in `after_terminate' below. *)
  let already_warned = ref false in
  (* --- *)
  (* Called at start-up time, and possibly twice for a single gesture (the simulated
     object is built, then started): the number is therefore reused when we already
     have one, and `ensure' hands back the bridge it built the first time. *)
  let resolve_bridge_name () : string =
    (* The scoped sudoers block of the NAT bridge is granted by the user, not by the
       administrator (docs/modernisation-world-bridge.md § 1 bis.3), and this is the
       moment it is needed. Privileges asks for the password and installs it; it also
       tells the user itself when it fails, exactly once per session, so here we only
       leave a trace in the log and carry on. *)
    let () =
      match Privileges.ensure_natbridge () with
      | Ok () -> ()
      | Error message -> Log.printf1 "nat_bridge: no administrator rights for the NAT bridge: %s\n" message
    in
    let () = Mutex.lock allocation_mutex in
    let result =
      try
        let n = match !instance with Some n -> n | None -> smallest_free (taken_instances ()) in
        (* [?ipv6] absent means "no IPv6 at all", which is why an option travels here
           rather than a string plus a boolean: the two could not disagree. On a host
           with no IPv6 uplink the script ignores it and warns -- it is not our place
           to second-guess that, and asking the host twice would be one predicate too
           many (see Nat_bridge_host.has_ipv6_uplink). *)
        (match Nat_bridge_host.ensure ~subnet:(subnet ()) ~dhcp:(get_dhcp ())
                 ?ipv6:(get_ipv6 ()) ~radvd:(get_radvd ()) ~instance:n () with
         | Ok info ->
             let () = instance := Some n in
             let () =
               Log.printf3
                 "nat_bridge: using the private bridge %s (guests: %s, gateway %s)\n"
                 info.Nat_bridge_host.bridge info.Nat_bridge_host.guest_range info.Nat_bridge_host.gateway
             in
             info.Nat_bridge_host.bridge
         | Error e ->
             let () =
               Log.printf1 "nat_bridge: no private bridge could be built (%s)\n" (Nat_bridge_host.string_of_error e)
             in
             (* Said, and not only written in a log nobody reads: since episode 10a the
                network is the user's own choice, so a refusal is an answer owed to a
                question that was asked. Without this the component reaches the state
                `on' with no bridge behind it, in complete silence. `warning' is safe
                from this thread (it goes through GMain_actor) and does not block a
                scripted session (it becomes a notification). *)
             let () =
               if !already_warned then () else
               let () = already_warned := true in
               let title = Printf.sprintf (f_ "NAT bridge \"%s\": no private network") (parent#get_name) in
               let message =
                 Printf.sprintf
                   (f_ "Marionnet could not build the private bridge of \"%s\", which therefore has \
                        no network at all: the virtual machines connected to it will reach nothing.\n\n\
                        <tt><small>%s</small></tt>\n\n\
                        If the network of this component is already used by the host itself (or by \
                        another NAT bridge), stop the component and choose another IPv4 address in \
                        its dialog.")
                   (parent#get_name) (Glib.Markup.escape_text (Nat_bridge_host.string_of_error e))
               in
               Simple_dialogs.warning title message ()
             in
             no_bridge_at_all)
      with e -> Mutex.unlock allocation_mutex; raise e
    in
    let () = Mutex.unlock allocation_mutex in
    result
  in
  (* --- *)
  (* Called once the tap has been destroyed: the bridge and its translation rules go
     away with the component, and its number becomes available again. *)
  let after_terminate () : unit =
    let () = already_warned := false in
    let () = Mutex.lock allocation_mutex in
    let () =
      try
        match !instance with
        | None -> ()
        | Some n ->
            let () =
              match Nat_bridge_host.release ~instance:n () with
              | Ok () -> ()
              | Error e -> Log.printf1 "nat_bridge: %s\n" (Nat_bridge_host.string_of_error e)
            in
            instance := None
      with e -> Mutex.unlock allocation_mutex; raise e
    in
    Mutex.unlock allocation_mutex
  in
  (* --- *)
object(_self)
  inherit ['parent] Bridge_common.Simulation_level_bridge.bridge_device
      ~parent
      ~device_type:"nat_bridge"
      ~resolve_bridge_name
      ~after_terminate
      ~hublet_no
      ~socket_name_prefix:"nat_bridge_hub-socket-"
      ~working_directory
      ~unexpected_death_callback
      ()
end

end (* module Simulation_level_nat_bridge *)

(** Just for testing: *)
let test = Dialog_add_or_update.make
