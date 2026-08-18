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

    let ok_callback t = Gui_bricks.Ok_callback.check_name t.name t.old_name st#network#name_exists t

    let dialog () =
      let name = st#network#suggestedName "N" in
      let network_config =
        Tool.network_config_of_network_address (Tool.first_free_network_address st#network)
      in
      Dialog_add_or_update.make ~title:(s_ "Add NAT bridge") ~name ~network_config ~ok_callback ()

    let reaction { name = name; label = label; network_config = network_config; port_no = port_no; _ } =
      let action () = ignore (
        new User_level_nat_bridge.nat_bridge
          ~network:st#network
          ~name
          ~label
          ~network_address:(Tool.network_address_of_config network_config)
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
     let port_no = h#get_port_no in
     (* Not Const.port_no_min: the smallest number of ports which still holds every
        cable already connected to this component (as for a world gateway): *)
     let port_no_min = st#network#port_no_lower_of (h :> User_level.node) in
     Dialog_add_or_update.make
       ~title ~name ~label ~network_config ~port_no ~port_no_min ~ok_callback:Add.ok_callback ()

    let reaction { name = name; label = label; network_config = network_config; port_no = port_no; old_name = old_name } =
      let d = (st#network#get_node_by_name old_name) in
      let h = ((Obj.magic d):> User_level_nat_bridge.nat_bridge) in
      let action () =
        h#update_nat_bridge_with ~name ~label ~port_no
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
 ?(port_no=Const.port_no_default)
 ?(port_no_min=Const.port_no_min)
 ?(port_no_max=Const.port_no_max)
 ?(help_callback=help_callback) (* defined backward with "WHERE" *)
 ?(ok_callback=(fun data -> Some data))
 ?(dialog_image_file=Initialization.Path.images^"ico.nat_bridge.dialog.png")
 () :'result option =
  let old_name = name in
  let ((b1,b2,b3,b4),b5) = network_config in
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
  let ((s1,s2,s3,s4,s5), port_no) =
    let vbox = GPack.vbox ~homogeneous:false ~border_width:20 ~spacing:10 ~packing:w#vbox#add () in
    let form =
      Gui_bricks.make_form_with_labels
        ~packing:vbox#add
        [ (s_ "IPv4 address"); (s_ "Integrated switch ports") ]
    in
    let network_config =
      Gui_bricks.spin_ipv4_address_with_cidr_netmask
        ~packing:(form#add_with_tooltip ~just_for_label:()
                    (s_ "IPv4 address of the bridge, which is the default gateway of the virtual machines connected to it"))
        b1 b2 b3 b4 b5
    in
    (* The two labels of this form are the ones a world gateway already uses, word
       for word, hence already translated: the same thing must be called by the same
       name, and this costs no new msgid. Step 1 and not 2 (the gateway's step): the
       minimum here is 1, so a step of 2 would only ever offer odd numbers. *)
    let port_no =
      Gui_bricks.spin_byte
        ~packing:(form#add_with_tooltip (s_ "The number of ports of the integrated switch"))
        ~lower:port_no_min ~upper:port_no_max ~step_incr:1
        port_no
    in
    (network_config, port_no)
  in
  s4#misc#set_sensitive false;
  s5#misc#set_sensitive false;

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
    let port_no = int_of_float port_no#value in
      { Data.name = name;
        Data.label = label;
        Data.network_config = network_config;
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
- Integrated switch ports: the number of virtual machines that may be plugged \
DIRECTLY into this component. They are all in the same network, they see each \
other, and they all reach the Internet through the bridge.\n\n\
The guests must be configured in that network. There is no DHCP server: give \
the virtual machines a static address.\n\n\
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

  method! extra_tree_attributes = [
    ("network_address", self#get_network_address);
    ("port_no", string_of_int self#get_port_no);
    ]

  method! eval_forest_attribute = function
  | ("network_address", x) -> self#set_network_address x
  | ("port_no", x) -> self#set_port_no (int_of_string x)
  | a -> self_as_bridge#eval_forest_attribute a

  (** Redefined: the drawing says which network this bridge offers, exactly as the
      one of a world gateway does. *)
  method! label_for_dot =
    let ip_gw = Ipv4.string_of_config (Tool.network_config_of_network_address self#get_network_address) in
    match self#get_label with
    | "" -> ip_gw
    | _  -> Printf.sprintf "%s <br/> %s" ip_gw self#get_label

  method update_nat_bridge_with ~name ~label ~port_no ~network_address =
    (* The following call ensures that the simulated device will be destroyed, hence
       that the bridge is given back before another one is built on another network: *)
    self#update_bridge_with ~name ~label ~port_no;
    self#set_network_address network_address;

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
        (match Nat_bridge_host.ensure ~subnet:(subnet ()) ~instance:n () with
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
