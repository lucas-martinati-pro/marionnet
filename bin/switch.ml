(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2010  Jean-Vincent Loddo
   Copyright (C) 2010  Université Paris 13

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


(** "Switch" component implementation. *)

#load "where_p4.cmo"
;;

(* --- *)
module Log = Marionnet_log
module StringExtra = Ocamlbricks.StringExtra
module Option = Ocamlbricks.Option
module Either = Ocamlbricks.Either
module OoExtra = Ocamlbricks.OoExtra
module Forest = Ocamlbricks.Forest
module Xforest = Ocamlbricks.Xforest
module Network = Ocamlbricks.Network
(* --- *)
open Gettext

(* Switch related constants: *)
(* TODO: make it configurable! *)
module Const = struct
 let port_no_default = 4
 let port_no_min = 4
 let port_no_max = 16

 let initial_content_for_rcfiles =
"# ===== FAST SPANNING TREE COMMANDS
# fstp/setfstp 0/1             Fast spanning tree protocol 1=ON 0=OFF
# fstp/setedge VLAN PORT 1/0   Define an edge port for a vlan 1=Y 0=N
# fstp/bonus   VLAN PORT COST  set the port bonus for a vlan
# ===== PORT STATUS COMMANDS
# port/sethub  0/1             1=HUB 0=switch
# port/setvlan PORT VLAN       assign PORT to VLAN (untagged port)
# ===== VLAN MANAGEMENT COMMANDS
# vlan/create  VLAN            create the vlan VLAN
# vlan/remove  VLAN            remove the vlan VLAN
# vlan/addport VLAN PORT       add PORT to the VLAN's trunk (tagged)
# vlan/delport VLAN PORT       remove PORT from the VLAN's trunk
" ;;

end

(* The type of data exchanged with the dialog: *)
module Data = struct
type t = {
  name              : string;
  label             : string;
  port_no           : int;
  auto_mdix         : bool;
  show_vde_terminal : bool;
  activate_fstp     : bool;
  rc_config         : bool * string; (* run commands (rc) file configuration *)
  old_name          : string;
  }

let to_string t = "<obj>" (* TODO? *)
end (* Data *)

module Make_menus (Params : sig
  val st      : State.globalState
  val packing : [ `toolbar of GButton.toolbar | `menu_parent of Menu_factory.menu_parent ]
 end) = struct

  open Params

  module Toolbar_entry = struct
   let imagefile = "ico.switch.palette.png"
   let tooltip   = (s_ "Switch")
   let packing   = Params.packing
  end

  module Add = struct
    include Data

    let key = Some GdkKeysyms._S

    let ok_callback t = Gui_bricks.Ok_callback.check_name t.name t.old_name st#network#name_exists t

    let dialog () =
      let name = st#network#suggestedName "S" in
      Dialog_add_or_update.make ~title:(s_ "Add switch") ~name ~ok_callback ()

    let reaction
       { name = name; label = label; port_no = port_no; auto_mdix = auto_mdix;
         show_vde_terminal = show_vde_terminal; activate_fstp = activate_fstp;
         rc_config = rc_config; _ }
      =
      let action () =
        ignore
          (new User_level_switch.switch
                 ~network:st#network ~name ~label ~port_no ~auto_mdix ~show_vde_terminal ~activate_fstp ~rc_config ())
      in
      st#network_change action ();

  end

  module Properties = struct
    include Data
    let dynlist () = st#network#get_node_names_that_can_modify ~devkind:`Switch ()

    let dialog name () =
     let d = (st#network#get_node_by_name name) in
     let s = ((Obj.magic d):> User_level_switch.switch) in
     let title = (s_ "Modify switch")^" "^name in
     let label = s#get_label in
     let port_no = s#get_port_no in
     let port_no_min = st#network#port_no_lower_of (s :> User_level.node) in
     let auto_mdix = s#get_auto_mdix in
     let show_vde_terminal = s#get_show_vde_terminal in
     let activate_fstp = s#get_activate_fstp in
     let rc_config = s#get_rc_config in
     Dialog_add_or_update.make
       ~title ~name ~label ~port_no ~port_no_min ~auto_mdix
       ~show_vde_terminal ~activate_fstp ~rc_config
       ~ok_callback:Add.ok_callback ()

    let reaction { name = name; label = label; port_no = port_no;
                   old_name = old_name;
                   auto_mdix = auto_mdix;
                   show_vde_terminal = show_vde_terminal;
                   activate_fstp = activate_fstp;
                   rc_config = rc_config }
      =
      let d = (st#network#get_node_by_name old_name) in
      let s = ((Obj.magic d):> User_level_switch.switch) in
      let action () = s#update_switch_with ~name ~label ~port_no ~auto_mdix ~show_vde_terminal ~activate_fstp ~rc_config in
      st#network_change action ();

  end

  module Remove = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")

    let dynlist () = st#network#get_node_names_that_can_destroy ~devkind:`Switch ()

    let dialog name () =
      Gui_bricks.Dialog.yes_or_cancel_question
        ~title:(s_ "Remove")
        ~markup:(Printf.sprintf (f_ "Are you sure that you want to remove %s\nand all the cables connected to this %s?") name (s_ "switch"))
        ~context:name
        ()

    let reaction name =
      let d = (st#network#get_node_by_name name) in
      let h = ((Obj.magic d):> User_level_switch.switch) in
      let action () = h#destroy in
      st#network_change action ();

  end

  module Startup = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    (* Not an alias of Properties.dynlist: each menu reads its own guard (user_level.ml). *)
    let dynlist () = st#network#get_node_names_that_can_startup ~devkind:`Switch ()
    let dialog     = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#startup

  end

  module Stop = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_gracefully_shutdown ~devkind:`Switch ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#gracefully_shutdown

  end

  module Suspend = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_suspend ~devkind:`Switch ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#suspend

  end

  module Resume = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_resume ~devkind:`Switch ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#resume

  end

 module Create_entries =
  Gui_toolbar_COMPONENTS_layouts.Layout_for_network_node (Params) (Toolbar_entry) (Add) (Properties) (Remove) (Startup) (Stop) (Suspend) (Resume)

 (* Subscribe this kind of component to the network club: *)
 st#network#subscribe_a_try_to_add_procedure Eval_forest_child.try_to_add_switch;

end

(*-----*)
  WHERE
(*-----*)

module Dialog_add_or_update = struct

(* This function may be useful for testing the widget creation without
   recompiling the whole project. *)
let make
 ?(title="Add switch")
 ?(name="")
 ?label
 ?(port_no=Const.port_no_default)
 ?(port_no_min=Const.port_no_min)
 ?(port_no_max=Const.port_no_max)
 ?(auto_mdix=false)
 ?(show_vde_terminal=false)
 ?(activate_fstp=false)
 ?(rc_config=(false, Const.initial_content_for_rcfiles))
 ?(help_callback=help_callback) (* defined backward with "WHERE" *)
 ?(ok_callback=(fun data -> Some data))
 ?(dialog_image_file=Initialization.Path.images^"ico.switch.dialog.png")
 () :'result option =
  let old_name = name in
  let (dialog_switch,_,name,label) =
    Gui_bricks.Dialog_add_or_update.make_window_image_name_and_label
      ~title
      ~image_file:dialog_image_file
      ~image_tooltip:(s_ "Switch")
      ~name
      ~name_tooltip:(s_ "Switch name. This name must be unique in the virtual network. Suggested: S1, S2, ...")
      ?label
      ()
  in
  let (port_no, auto_mdix, show_vde_terminal, activate_fstp, rc_config) =
    let vbox = GPack.vbox ~homogeneous:false ~border_width:20 ~spacing:10 ~packing:dialog_switch#vbox#add () in
    let form =
      Gui_bricks.make_form_with_labels
        ~packing:vbox#add
        [(s_ "Ports number");
         (* Not translated on purpose: "Auto MDI-X" is the IEEE acronym printed as such on
            real hardware and in datasheets, in every language we support. The meaning is
            carried by the tooltip, which *is* translated. *)
         ("Auto MDI-X");
         (s_ "Show VDE terminal");
         (s_ "Activate FSTP");
         (s_ "Startup configuration");
         ]
    in
    let port_no =
      Gui_bricks.spin_byte
        ~packing:(form#add_with_tooltip (s_ "Switch ports number"))
        ~lower:port_no_min ~upper:port_no_max ~step_incr:2
        port_no
    in
    let auto_mdix =
      GButton.check_button
        ~active:auto_mdix
        ~packing:(form#add_with_tooltip
                    (s_ "Check to let the switch accept, on all its ports, any kind of cable, straight or crossover"))
        ()
    in
    let show_vde_terminal =
      GButton.check_button
        ~active:show_vde_terminal
        ~packing:(form#add_with_tooltip (s_ "Check to access the switch through a terminal" ))
        ()
    in
    let activate_fstp =
      GButton.check_button
        ~active:activate_fstp
        ~packing:(form#add_with_tooltip (s_ "Check to activate the FSTP (Fast Spanning Tree Protocol)" ))
        ()
    in
    let rc_config =
       Gui_bricks.make_rc_config_widget
         ~filter_names:[`CONF; `RC; `ALL]
         ~parent:(dialog_switch :> GWindow.window_skel)
         ~packing:(form#add_with_tooltip (s_ "Check to activate a startup configuration" ))
         ~active:(fst rc_config)
         ~content:(snd rc_config)
         ~device_name:(old_name)
         ~language:("vde_switch") (* special syntax *)
         ()
    in
    (port_no, auto_mdix, show_vde_terminal, activate_fstp, rc_config)
  in
  (* --- *)
  let get_widget_data () :'result =
    let name = name#text in
    let label = label#text in
    let port_no = int_of_float port_no#value in
    let auto_mdix = auto_mdix#active in
    let show_vde_terminal = show_vde_terminal#active in
    let rc_config = (rc_config#active, rc_config#content) in
    let activate_fstp = activate_fstp#active in
      { Data.name = name;
        Data.label = label;
        Data.port_no = port_no;
        Data.auto_mdix = auto_mdix;
        Data.show_vde_terminal = show_vde_terminal;
        Data.activate_fstp = activate_fstp;
        Data.rc_config = rc_config;
        Data.old_name = old_name;
        }
  in
  (* The result of make is the result of the dialog loop (of type 'result option): *)
  Gui_bricks.Dialog_run.ok_or_cancel (dialog_switch) ~ok_callback ~help_callback ~get_widget_data ()

(*-----*)
  WHERE
(*-----*)

 let help_callback =
   let title = (s_ "ADD OR MODIFY A SWITCH") in
   let msg   = (s_ "\
In this dialog window you can define the name of an Ethernet switch \
and set parameters for it:\n\n\
- Label: a string appearing near the switch icon in the network graph; it may \
allow, for example, to know at a glance the Ethernet network realized by the device; \
this field is exclusively for graphic purposes, is not taken in consideration \
for the configuration.\n\n\
- Nb of Ports: the number of ports of the switch (default 4); this number must \
not be increased without a reason, because the number of processes needed for the \
device emulation is proportional to his ports number.")
   in Simple_dialogs.help title msg

end

(*-----*)
  WHERE
(*-----*)

module Eval_forest_child = struct

 let try_to_add_switch (network:User_level.network) ((root,children):Xforest.tree) =
  try
   (match root with
    | ("switch", attrs) ->
    	let name  = List.assoc "name" attrs in
	let port_no = int_of_string (List.assoc "port_no" attrs) in
        Log.printf2 "Importing switch \"%s\" with %d ports...\n" name port_no;
	let x = new User_level_switch.switch ~network ~name ~port_no () in
	x#from_tree ("switch", attrs) children;
        Log.printf1 "Switch \"%s\" successfully imported.\n" name;
        true

    (* backward compatibility *)
    | ("device", attrs) ->
	let name  = List.assoc "name" attrs in
	let port_no = try int_of_string (List.assoc "eth" attrs) with _ -> Const.port_no_default in
	let kind = List.assoc "kind" attrs in
	(match kind with
	| "switch" ->
            Log.printf2 "Importing switch \"%s\" with %d ports...\n" name port_no;
	    let x = new User_level_switch.switch ~network ~name ~port_no () in
	    x#from_tree ("device", attrs) children; (* Just for the label... *)
            Log.printf "This is an old project: we set the user port offset to 1...\n";
	    network#defects#change_port_user_offset ~device_name:name ~user_port_offset:1;
	    Log.printf1 "Switch \"%s\" successfully imported.\n" name;
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


module User_level_switch = struct

class switch =

 fun ~network
     ~name
     ?label
     ~port_no
     ?(auto_mdix=false)
     ?(show_vde_terminal=false)
     ?(activate_fstp=false)
     ?(rc_config=(false,""))
     () ->
  object (self) inherit OoExtra.destroy_methods ()

  inherit
    User_level.node_with_ledgrid_and_defects
      ~network
      ~name ?label ~devkind:`Switch
      ~port_no
      ~port_no_min:Const.port_no_min
      ~port_no_max:Const.port_no_max
      ~user_port_offset:1 (* in order to have a perfect mapping with VDE *)
      ~port_prefix:"port"
      ()
    as self_as_node_with_ledgrid_and_defects

  method ledgrid_label = "Switch"
  method defects_device_type = "switch"
  method string_of_devkind = "switch"

  (* "Auto MDI-X": a real switch with intelligent ports detects the wiring by itself, so no
     cable is ever wrong. Marionnet models this as a polarity (user_level.ml), and the three
     components which own an implicit switch (cloud, world_gateway and both bridges, through
     bridge_common) already answer [MDI_Auto] silently. Here the user decides, port by port
     being meaningless: the flag holds for the whole device. Read as a method, hence re-read
     at every [cable#is_correct] (cable.ml), not frozen at startup. *)
  val mutable auto_mdix : bool = auto_mdix
  method get_auto_mdix = auto_mdix
  method set_auto_mdix x = auto_mdix <- x
  method polarity = if auto_mdix then User_level.MDI_Auto else User_level.MDI_X

  val mutable show_vde_terminal : bool = show_vde_terminal
  method get_show_vde_terminal = show_vde_terminal
  method set_show_vde_terminal x = show_vde_terminal <- x

  val mutable activate_fstp : bool = activate_fstp
  method get_activate_fstp  = activate_fstp
  method set_activate_fstp x = activate_fstp <- x

  val mutable rc_config : bool * string  = rc_config
  method get_rc_config = rc_config
  method set_rc_config x = rc_config <- x

  (* Same as in machine.ml: since `v3 the content lives in states/rc_config.XXXXXXXXX and the
     forest carries only its basename (work-stream `migration-marshal-to-text', episode 5).
     A switch's rc file is a set of vdeterm commands (simulation_level.ml:398-409), which makes
     it just as much a script as a machine's. *)
  val mutable rc_config_file : string = User_level.Rc_files.fresh_basename ()
  method get_rc_config_file = rc_config_file

  method! rc_contents = [ (rc_config_file, snd rc_config) ]

  (* Episode 4 of `journalisation-profonde'. A switch has no guest, hence no hostfs, hence nobody
     inside to write what its rc did; Marionnet is the one who talks to vde_switch, so Marionnet
     is the one who writes it down. The path does not depend on the simulation being up — the
     journal is read after the switch was stopped, exactly like a guest's — and it is the same
     expression the simulation level uses to write it. *)
  method! rc_journal_file_if_any =
    Some (Simulation_level_switch.rc_journal_path
            ~working_directory:(network#project_working_directory)
            ~name:(self#get_name))

  (* Episode 5 of `journalisation-profonde' asks the counterpart of the journal above, and its
     opposite in every respect: that one is a file, written once, readable long after the switch
     was stopped; the tables of vde_switch live on a socket, and only while it runs. No method
     is redefined here for them — [management_socket_if_running] (user_level.ml) is written once,
     where the automaton state is, and [get_management_socket_name] (simulation_level.ml) already
     answers [None] for every kind but this one. *)

  method! set_rc_content ~basename ~content =
    if basename <> rc_config_file then false else
    let () = self#set_rc_config ((fst rc_config), content) in
    true

  method dotImg iconsize =
   let imgDir = Initialization.Path.images in
   (imgDir^"ico.switch."^(self#icon_suffix_of_state)^"."^iconsize^".png")

  method update_switch_with ~name ~label ~port_no
   ~auto_mdix ~show_vde_terminal ~activate_fstp ~rc_config
   =
   (* The following call ensure that the simulated device will be destroyed: *)
   self_as_node_with_ledgrid_and_defects#update_with ~name ~label ~port_no;
   self#set_auto_mdix (auto_mdix);
   self#set_show_vde_terminal (show_vde_terminal);
   self#set_activate_fstp (activate_fstp);
   self#set_rc_config (rc_config);

  (** Create the simulated device *)
  method private make_simulated_device =
    let hublet_no = self#get_port_no in
    let show_vde_terminal = self#get_show_vde_terminal in
    let fstp = Option.of_bool (self#get_activate_fstp) in
    let rcfile_content =
      match self#get_rc_config with
      | false, _ -> None
      | true, content -> Some content
    in
    let unexpected_death_callback = self#destroy_because_of_unexpected_death in
    ((new Simulation_level_switch.switch
       ~parent:self
       ~hublet_no          (* TODO: why not accessible from parent? *)
       ~show_vde_terminal  (* TODO: why not accessible from parent? *)
       ?fstp
       ?rcfile_content
       ~working_directory:(network#project_working_directory)
       ~unexpected_death_callback
       ()) :> User_level.node Simulation_level.device)

  method to_tree =
   Forest.tree_of_leaf ("switch", [
      ("name"     ,  self#get_name );
      ("label"    ,  self#get_label);
      ("port_no"  ,  (string_of_int self#get_port_no))  ;
      ("auto_mdix" , string_of_bool (self#get_auto_mdix));
      ("show_vde_terminal" , string_of_bool (self#get_show_vde_terminal));
      ("activate_fstp"     , string_of_bool (self#get_activate_fstp));
      (* Since `v3: the flag in clear, the script in its own file (episode 5). *)
      ("rc_config_active"  , string_of_bool (fst self#get_rc_config));
      ("rc_config_file"    , rc_config_file);
      ])

  method! eval_forest_attribute = function
  | ("name"     , x ) -> self#set_name x
  | ("label"    , x ) -> self#set_label x
  | ("port_no"  , x ) -> self#set_port_no (int_of_string x)
  (* Absent from a project older than this feature: the default (false) then stands, which is
     exactly the historical behaviour (MDI_X). *)
  | ("auto_mdix", x )         -> self#set_auto_mdix (bool_of_string x)
  | ("show_vde_terminal", x ) -> self#set_show_vde_terminal (bool_of_string x)
  | ("activate_fstp", x )     -> self#set_activate_fstp (bool_of_string x)
  (* `v0/`v1/`v2: the pair, marshalled into the attribute. Kept, and kept first. *)
  | ("rc_config", x )         -> self#set_rc_config (Marshal.from_string x 0)
  (* `v3: the two halves, independently and in any order (episode 5). *)
  | ("rc_config_active", x )  -> self#set_rc_config ((bool_of_string x), (snd rc_config))
  | ("rc_config_file"  , x )  ->
      let () = rc_config_file <- x in
      let content =
        User_level.Rc_files.read ~states_directory:(self#states_directory) ~basename:x
      in
      self#set_rc_config ((fst rc_config), content)
  | _ -> () (* Forward-comp. *)

end (* class switch *)

end (* module User_level *)

(*-----*)
  WHERE
(*-----*)

module Simulation_level_switch = struct

(* The question is "port/print" *)
let scan_vde_switch_answer_to_port_print (ch:Network.stream_channel) : int =
  let rec loop n =
    let answer = ch#input_line () in
    try (Scanf.sscanf answer "Port %d %s ACTIVE") (fun i _ -> ()); loop (n+1) with _ ->
    try (Scanf.sscanf answer ".") (); n with _ -> loop n
  in
  loop 0

let ask_vde_switch_for_current_active_ports ~socketfile () =
  let protocol (ch:Network.stream_channel) =
    ch#output_line "port/print";
    scan_vde_switch_answer_to_port_print ch
  in
  Network.stream_client ~target:(`unix socketfile) ~protocol ()

let wait_vde_switch_until_ports_will_be_allocated ~numports ~socketfile () =
  let rec protocol (ch:Network.stream_channel) =
    ch#output_line "port/print";
    let active_ports = scan_vde_switch_answer_to_port_print ch in
    if active_ports >= numports then active_ports else (Thread.delay 0.2; (protocol ch))
  in
  Network.stream_client ~target:(`unix socketfile) ~protocol ()

(*let send_commands_to_vde_switch ~socketfile ~commands () =
  Log.printf "Sending commands to a switch:\n---\n%s\n---\n" commands;
  let protocol (ch:Network.stream_channel) = ch#send commands in
  Network.stream_unix_client ~socketfile ~protocol ()*)

let get_lines_removing_comments (commands:string) : string list =
  let t = StringExtra.Text.of_string commands in
  let result = StringExtra.Text.grep (Str.regexp "^[^#]") t in
  result

(* --------------------------------------------------------------------------------------- *)
(* Episode 4 of `journalisation-profonde': the rc of a switch stops failing in silence.       *)
(* --------------------------------------------------------------------------------------- *)

(* What a `vde_switch' 2.3.2 answers on its management socket. Measured — not read — before this
   parser was written, by talking to a real switch:

     vde$ 0000 DATA END WITH '.'      <- optional: an answer which carries data opens with this
     VLAN 0000                        <- ... the data lines ...
     .                                <- ... closed by a lone dot
     1000 Success                     <- the status line: always, and always last
                                      <- an empty line
     vde$                             <- the prompt, WITHOUT a trailing newline

   Status codes met while probing: 1000 Success, 1022 Invalid argument (vlan/create 4999),
   1006 No such device or address (a port which does not exist), 1038 Function not implemented
   (a command which does not exist). A failure is therefore anything but 1000, and it comes with
   the switch's own words — which is all the journal below has to carry.

   Two consequences for a line-oriented reader, and together they are why the boolean reader this
   replaces ([get_vde_switch_boolean_answer], "currently unused, but useful for testing") could
   not have worked in production: the prompt has no newline of its own, so it is *prepended* to
   the first line of the next answer ("vde$ 1000 Success") — every line has to be read modulo that
   prefix; and the status line of an answer which carries data is *not* prefixed, so a reader
   which only knows "vde$ 1000 Success" walks straight past the terminator of every command that
   prints something, and swallows the next answer looking for it. *)

type vde_answer = {
  va_data    : string list;  (* the data lines, if the command printed any *)
  va_code    : int;          (* 1000 is the only success *)
  va_message : string;       (* the switch's own words *)
  }

let vde_prompt = "vde$ "
let vde_data_header = "0000 DATA END WITH '.'"
let vde_status_line = Str.regexp "^\\([0-9][0-9][0-9][0-9]\\) \\(.*\\)$"

(* The prompt is a prefix, not a line: strip as many as have piled up. *)
let rec strip_vde_prompt line =
  let n = String.length vde_prompt in
  if String.starts_with ~prefix:vde_prompt line
  then strip_vde_prompt (String.sub line n (String.length line - n))
  else line

(* Bounded in lines, for the same reason the control server bounds its reader: what arrives here
   is written by a process we do not control. The receive timeout set by the caller bounds the
   *time*; this bounds the *memory*. *)
let max_vde_answer_lines = 4096

let read_vde_switch_answer (ch:Network.stream_channel) : vde_answer =
  let rec loop n data =
    if n > max_vde_answer_lines then
      { va_data = List.rev data; va_code = (-1);
        va_message = Printf.sprintf "answer longer than %d lines, giving up" max_vde_answer_lines }
    else
    let line = strip_vde_prompt (ch#input_line ()) in
    if line = vde_data_header then read_data (n+1) data else
    if Str.string_match vde_status_line line 0 then
      match int_of_string_opt (Str.matched_group 1 line) with
      | Some code -> { va_data = List.rev data; va_code = code;
                       va_message = Str.matched_group 2 line }
      | None      -> loop (n+1) data
    else
      (* The greeting of the connection, and the empty line which precedes each prompt. *)
      loop (n+1) data
  and read_data n data =
    if n > max_vde_answer_lines then loop n data else
    let line = ch#input_line () in
    if String.trim line = "." then loop (n+1) data else read_data (n+1) (line :: data)
  in
  loop 0 []

(* Long enough that a switch busy allocating ports still answers, short enough that a switch which
   never will does not keep this thread (and its connection) forever. *)
let vde_answer_timeout = 5.0

let rc_journal_basename_suffix = "-rc_config.log"

(* Where the journal of a switch's rc lives. Not in a hostfs — a switch has no guest to mount one
   — but in the project's working directory, which is what makes it a *living* journal in the
   sense of decision D3: it outlives the process (a script reads it after the switch was stopped)
   and it goes away with the project. Computed from the name, hence usable at user level, where
   the control server asks for it, as well as here (bin/user_level.ml, [rc_journal_file_if_any]). *)
let rc_journal_path ~working_directory ~name =
  Filename.concat working_directory (name ^ rc_journal_basename_suffix)

let journal_header ~(name:string) ~(commands:int) : string =
  let t = Unix.localtime (Unix.time ()) in
  Printf.sprintf
    "# marionnet: journal of the rc of switch %S (journalisation-profonde, episode 4)\n\
     # date: %04d-%02d-%02d %02d:%02d:%02d\n\
     # what follows is what marionnet said to vde_switch, and what vde_switch answered\n\
     # %d command(s) to send\n"
    name (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1) t.Unix.tm_mday
    t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec commands

(* Never raises: this runs at spawning time, in a thread nobody joins. A journal which cannot be
   written is a line in Marionnet's own log, not a failed start. *)
let with_journal ~(journal:string) (f : out_channel -> unit) : unit =
  match (try Some (open_out journal) with e -> Log.print_exn ~prefix:"switch journal: " e; None) with
  | None    -> ()
  | Some oc -> (try Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> f oc)
                with e -> Log.print_exn ~prefix:"switch journal: " e)

(* A switch with no rc has a journal too, and it says so. Same reason as decision D5 on the guest
   side: a script must find the journal of a component without knowing whether anyone configured
   it — an empty journal is an answer ("this switch ran, it had nothing to say"), a missing file
   is a question. *)
let write_rc_journal_without_rc ~(journal:string) ~(name:string) () : unit =
  with_journal ~journal
    (fun oc ->
       output_string oc (journal_header ~name ~commands:0);
       output_string oc "# no rc: this switch has no startup configuration to send\n")

(* The former [send_commands_to_vde_switch_ignoring_answers], which the name said it all about:
   it spawned a thread whose only job was to read the answers and drop them, and paced the sending
   with a 1/100 s delay. Reading the answer *is* the pacing — it is the proof that the previous
   command was consumed — so the delay goes with the dropping. *)
let send_commands_to_vde_switch_and_journal ~socketfile ~commands ~name ~journal () : unit =
  let lines = get_lines_removing_comments commands in
  with_journal ~journal
    (fun oc ->
       output_string oc (journal_header ~name ~commands:(List.length lines));
       flush oc;
       let failed = ref 0 in
       let sent   = ref 0 in
       let protocol (ch:Network.stream_channel) =
         (* A blocking read on a switch which never answers would hold this thread and this
            connection for the whole life of the project. SO_RCVTIMEO turns that into an
            exception, which the journal then reports as such. *)
         let (fd, _) = ch#get_IO_file_descriptors in
         let () = try Unix.setsockopt_float fd Unix.SO_RCVTIMEO vde_answer_timeout with _ -> () in
         List.iter
           (fun line ->
              Log.printf1 "Sending line to a switch: %s\n" line;
              Printf.fprintf oc "> %s\n" line;
              ch#output_line line;
              incr sent;
              match (try Ok (read_vde_switch_answer ch) with e -> Error e) with
              | Error e ->
                  incr failed;
                  Printf.fprintf oc "!! FAILED (no answer within %.1fs): %s\n" vde_answer_timeout line;
                  Printf.fprintf oc "#  %s\n" (Printexc.to_string e);
                  flush oc;
                  (* Resynchronising on a stream we have lost track of would only produce a
                     journal of fiction: stop here, and say so. *)
                  raise e
              | Ok a ->
                  List.iter (fun l -> Printf.fprintf oc "%s\n" l) a.va_data;
                  Printf.fprintf oc "%d %s\n" a.va_code a.va_message;
                  (if a.va_code <> 1000 then begin
                     incr failed;
                     (* The same shape as the guest-side journals of episodes 1 and 2, so that one
                        grep on "^!! FAILED" answers "what went wrong in my scenario?" for a
                        machine, a router and a switch alike. *)
                     Printf.fprintf oc "!! FAILED (status %d): %s\n" a.va_code line
                     end);
                  flush oc)
           lines
       in
       let outcome = Network.stream_client ~target:(`unix socketfile) ~protocol () in
       (match outcome with
        | Either.Right () -> ()
        | Either.Left e ->
            Printf.fprintf oc "# the exchange with vde_switch was interrupted: %s\n"
              (Printexc.to_string e));
       Printf.fprintf oc "# done: %d command(s) sent, %d failed\n" !sent !failed)


(* --------------------------------------------------------------------------------------- *)
(* Episode 5 of `journalisation-profonde': what the switch knows *now*.                      *)
(* --------------------------------------------------------------------------------------- *)

(* Same socket, same reader, same two bounds as the episode above — what changes is the
   direction. A journal says what *we* did; these tables say what the switch *learnt*, and no
   file anywhere receives them: they exist only while it runs, and only inside it.

   The four tables, and the question each one answers:

     ports  port/print  who is plugged where, and how much went through
     macs   hash/print  which MAC was learnt on which port — "is m1 seen where it is cabled?"
     vlans  vlan/print  which VLAN exists, and which port belongs to it (tagged or not)
     fstp   fstp/print  the spanning tree — or the plain fact that it is disabled

   The short names are ours (they are what [help] publishes and what a client types), the
   commands are vde's. The pairing is stated here, and only here, because this is the only place
   which speaks both languages: the control server owns the JSON, this file owns the protocol. *)
let snapshot_tables = [
  ("ports", "port/print");
  ("macs",  "hash/print");
  ("vlans", "vlan/print");
  ("fstp",  "fstp/print");
  ]

let snapshot_table_names = List.map fst snapshot_tables

(* A parsed row, in the only shape the two sides have to agree upon. Deliberately not a JSON
   type: this file would then have to know how a string is escaped, which is the control
   server's business — and the control server would have to know what a vde table looks like,
   which is this file's. Five constructors are the whole contract. *)
type vde_value =
  | Vstr  of string
  | Vint  of int
  | Vbool of bool
  | Vobj  of (string * vde_value) list
  | Vlist of vde_value list

type vde_table = {
  vt_name    : string;                          (* ours: "macs" *)
  vt_command : string;                          (* vde's: "hash/print" *)
  vt_code    : int;                             (* 1000, or what the switch refused with *)
  vt_message : string;                          (* the switch's own words *)
  vt_lines   : string list;                     (* what it said, word for word *)
  vt_entries : (string * vde_value) list list;  (* ... and what we could make of it *)
  }

(* The parsers below read *tokens*, not regexps, and that is not a matter of taste: Str keeps
   its last match in a global, which a reader running in a connection's own thread has no
   business relying on. Every line of these tables is a sequence of words, half of them already
   spelled "key=value" by vde itself. *)
let split_on_blanks (s:string) : string list =
  let s = String.map (function '\t' -> ' ' | c -> c) s in
  List.filter (fun t -> t <> "") (String.split_on_char ' ' s)

(* Numbers arrive zero-padded ("VLAN 0000", "port: 001"): [int_of_string] reads them as decimal,
   and what is not a number (a MAC, a role) stays a string. *)
let vde_value_of_string (s:string) : vde_value =
  match int_of_string_opt s with Some i -> Vint i | None -> Vstr s

(* "tagged=0" -> ("tagged", Vint 0). [None] on a token which is not a field at all. *)
let field_of_token (t:string) : (string * vde_value) option =
  match String.index_opt t '=' with
  | None   -> None
  | Some 0 -> None
  | Some i ->
      Some (String.sub t 0 i,
            vde_value_of_string (String.sub t (i+1) (String.length t - i - 1)))

(* vde spells its flags 0/1; a script reading JSON expects true/false. The keys are named
   because only the keys can tell: nothing in "tagged=0" says it is a flag. *)
let boolean_keys = [ "tagged"; "active" ]

let booleanise (fields : (string * vde_value) list) : (string * vde_value) list =
  List.map
    (function
     | (k, Vint n) when List.mem k boolean_keys -> (k, Vbool (n <> 0))
     | field -> field)
    fields

(* "... age 3 secs" -> the value which follows the word [key]. *)
let value_after (key:string) (tokens:string list) : vde_value option =
  let rec loop = function
    | k :: v :: _ when k = key -> Some (vde_value_of_string v)
    | _ :: rest                -> loop rest
    | []                       -> None
  in
  loop tokens

(* "rootport 0000 cost 0 age 48 bonusport 0000 bonuscost 0": key, value, key, value... *)
let rec pairs_of_tokens = function
  | k :: v :: rest -> (k, vde_value_of_string v) :: pairs_of_tokens rest
  | _              -> []

(* port/print — one entry per port, spread over several lines:

     Port 0001 untagged_vlan=0000 ACTIVE - Unnamed Allocatable
      Current User: jean Access Control: (User: NONE - Group: NONE)
      IN:  pkts          3          bytes                  180
      OUT: pkts          2          bytes                  106
       -- endpoint ID 0003 module unix prog   : vdeplug: user=jean pid=1793216

   The [Current User] line is left to [lines]: it says who owns the *host* process, which is not
   a question anyone asks a switch. The endpoints are the interesting part — that is where the
   cable of a running machine shows up. *)
let parse_ports (lines : string list) : (string * vde_value) list list =
  let entries = ref [] and fields = ref [] and endpoints = ref [] in
  let flush () =
    (match !fields with
     | [] -> ()
     | fs -> entries := (fs @ [ ("endpoints", Vlist (List.rev !endpoints)) ]) :: !entries);
    fields := []; endpoints := []
  in
  let counters prefix tokens =
    List.filter_map
      (fun key ->
         match value_after key tokens with
         | Some v -> Some (prefix ^ "_" ^ key, v)
         | None   -> None)
      [ "pkts"; "bytes" ]
  in
  (* "ID 0003 module unix prog   : vdeplug: user=jean pid=1793216" *)
  let endpoint_of tokens =
    let rec after_colon = function
      | ":" :: rest -> Some (String.concat " " rest)
      | _   :: rest -> after_colon rest
      | []          -> None
    in
    let field k = match value_after k tokens with Some v -> [ (String.lowercase_ascii k, v) ] | None -> [] in
    Vobj ((field "ID") @ (field "module")
          @ (match after_colon tokens with Some d -> [ ("description", Vstr d) ] | None -> []))
  in
  List.iter
    (fun line ->
       match split_on_blanks line with
       | "Port" :: n :: tail ->
           flush ();
           (* Whatever is neither a field nor the separator is a flag: ACTIVE, Unnamed,
              Allocatable. Kept as they are — a list we do not interpret cannot go stale. *)
           let flags = List.filter (fun t -> t <> "-" && field_of_token t = None) tail in
           fields :=
             [ ("port",   vde_value_of_string n);
               ("active", Vbool (List.mem "ACTIVE" flags)) ]
             @ (List.filter_map field_of_token tail)
             @ [ ("flags", Vlist (List.map (fun f -> Vstr f) flags)) ]
       | "IN:"  :: tail -> fields := !fields @ (counters "in"  tail)
       | "OUT:" :: tail -> fields := !fields @ (counters "out" tail)
       | "--" :: "endpoint" :: tail -> endpoints := (endpoint_of tail) :: !endpoints
       | _ -> ())
    lines;
  flush ();
  List.rev !entries

(* hash/print — one line per learnt address, and this is the table the episode is about:

     Hash: 0086 Addr: 02:00:00:00:00:11 VLAN 0000 to port: 001  age 3 secs

   The bucket number is dropped: it is an implementation detail of the hash table, and keeping
   it would invite a script to believe it means something. *)
let parse_macs (lines : string list) : (string * vde_value) list list =
  List.filter_map
    (fun line ->
       let tokens = split_on_blanks line in
       match tokens with
       | "Hash:" :: _ ->
           (match value_after "Addr:" tokens with
            | None     -> None
            | Some mac ->
                let field name key =
                  match value_after key tokens with Some v -> [ (name, v) ] | None -> []
                in
                Some ([ ("mac", mac) ] @ (field "vlan" "VLAN") @ (field "port" "port:")
                      @ (field "age" "age")))
       | _ -> None)
    lines

(* vlan/print — the VLANs which exist, and the ports which belong to them:

     VLAN 0000
      -- Port 0001 tagged=0 active=1 status=Forwarding

   This is the table which says whether the rc of episode 4 took effect: `vlan/create 5' shows
   up here, and so does every port the scenario added to it. *)
let parse_vlans (lines : string list) : (string * vde_value) list list =
  let entries = ref [] and fields = ref [] and ports = ref [] in
  let flush () =
    (match !fields with
     | [] -> ()
     | fs -> entries := (fs @ [ ("ports", Vlist (List.rev !ports)) ]) :: !entries);
    fields := []; ports := []
  in
  List.iter
    (fun line ->
       match split_on_blanks line with
       | "VLAN" :: n :: _ ->
           flush ();
           fields := [ ("vlan", vde_value_of_string n) ]
       | "--" :: "Port" :: n :: tail ->
           ports := Vobj ([ ("port", vde_value_of_string n) ]
                          @ (booleanise (List.filter_map field_of_token tail))) :: !ports
       | _ -> ())
    lines;
  flush ();
  List.rev !entries

(* fstp/print — the spanning tree, per VLAN:

     FST DATA VLAN 0000 ROOTSWITCH [FSTP IS DISABLED]
      ++ root 80:00:00:ff:0b:14:0f:3e
      ++ designated ff:ff:ff:ff:ff:ff:ff:ff
      ++ rootport 0000 cost 0 age 48 bonusport 0000 bonuscost 0
      -- Port 0001 tagged=0 portcost=20000000 role=Designated

   The header carries two facts a script would otherwise have to guess: whether this switch is
   the root, and whether the protocol is running at all — measured, that second one only shows
   up as the words FSTP IS DISABLED at the end of the very same line. The [++] lines are plain
   key/value sequences, which is why they need no parser of their own. *)
let parse_fstp (lines : string list) : (string * vde_value) list list =
  let entries = ref [] and fields = ref [] and ports = ref [] in
  let flush () =
    (match !fields with
     | [] -> ()
     | fs -> entries := (fs @ [ ("ports", Vlist (List.rev !ports)) ]) :: !entries);
    fields := []; ports := []
  in
  List.iter
    (fun line ->
       match split_on_blanks line with
       | "FST" :: "DATA" :: "VLAN" :: n :: flags ->
           flush ();
           fields := [ ("vlan",         vde_value_of_string n);
                       ("rootswitch",   Vbool (List.mem "ROOTSWITCH" flags));
                       ("fstp_enabled", Vbool (not (List.mem "DISABLED" flags))) ]
       | "++" :: tail ->
           fields := !fields @ (pairs_of_tokens tail)
       | "--" :: "Port" :: n :: tail ->
           ports := Vobj ([ ("port", vde_value_of_string n) ]
                          @ (booleanise (List.filter_map field_of_token tail))) :: !ports
       | _ -> ())
    lines;
  flush ();
  List.rev !entries

let snapshot_parser (table:string) : string list -> (string * vde_value) list list =
  match table with
  | "ports" -> parse_ports
  | "macs"  -> parse_macs
  | "vlans" -> parse_vlans
  | "fstp"  -> parse_fstp
  | _       -> (fun _ -> [])   (* an unknown name never gets here: the server checks it first *)

(* Asks the switch, and keeps both what it said and what we made of it. Nothing is written to
   disk: a snapshot is *now* — the living journal decision D3 speaks of is the file the previous
   episode writes, and it is a different thing.

   An interrupted exchange is [Error], not a shorter list: the answers of vde are only
   separable by their status lines, so having lost track of one is having lost track of all the
   ones after it. Same reason the journal of episode 4 stops instead of resynchronising. *)
let ask_vde_switch_snapshot ~(socketfile:string) ~(tables : string list)
  : (vde_table list, exn) result
  =
  let commands =
    List.filter_map
      (fun name ->
         match List.assoc_opt name snapshot_tables with
         | Some command -> Some (name, command)
         | None         -> None)
      tables
  in
  let collected = ref [] in
  let protocol (ch:Network.stream_channel) =
    let (fd, _) = ch#get_IO_file_descriptors in
    let () = try Unix.setsockopt_float fd Unix.SO_RCVTIMEO vde_answer_timeout with _ -> () in
    List.iter
      (fun (name, command) ->
         Log.printf1 "Asking a switch for its %s\n" command;
         ch#output_line command;
         let a = read_vde_switch_answer ch in
         collected :=
           { vt_name    = name;
             vt_command = command;
             vt_code    = a.va_code;
             vt_message = a.va_message;
             vt_lines   = a.va_data;
             (* A refusal has no table to parse — and pretending otherwise would publish an
                empty list where the truth is "the switch said no". *)
             vt_entries = (if a.va_code = 1000 then (snapshot_parser name) a.va_data else []) }
           :: !collected)
      commands
  in
  match Network.stream_client ~target:(`unix socketfile) ~protocol () with
  | Either.Right () -> Ok (List.rev !collected)
  | Either.Left e   -> Error e


(** A switch: just a [hub_or_switch] with [hub = false] *)
class ['parent] switch =
  fun ~(parent:'parent)
      ~hublet_no
      ?(last_user_visible_port_index:int option)
      ?(show_vde_terminal=false)
      ?fstp
      ?rcfile (* Unused: vde_switch doesn't interpret correctly commands provided in this way! *)
      ?rcfile_content
      ~working_directory
      ~unexpected_death_callback
      () ->
object(self)
  inherit ['parent] Simulation_level.hub_or_switch
      ~parent
      ~hublet_no
      ?last_user_visible_port_index
      ~hub:false
      ~management_socket:()
      ?fstp
      ?rcfile
      ~working_directory
      ~unexpected_death_callback
      ()
      as super
  method device_type = "switch"

  (* Episode 4: where what we say to vde_switch is written down. The path is the one the user
     level publishes to the control server, and it is computed from the name on both sides. *)
  method private rc_journal =
    rc_journal_path ~working_directory ~name:(parent#get_name)

  method! spawn_internal_cables =
    match show_vde_terminal || (rcfile_content <> None) with
    | false ->
        write_rc_journal_without_rc ~journal:(self#rc_journal) ~name:(parent#get_name) ();
        super#spawn_internal_cables
    | true ->
        (* If the user want to configure VLANs etc, we must be sure that
           the port numbering will be the same for marionnet and vde_switch: *)
        let socketfile = Option.extract self#get_management_socket_name in
        let numports = ref (Either.extract (ask_vde_switch_for_current_active_ports ~socketfile ())) in
        let name = parent#get_name in
        Log.printf2 "The vde_switch %s has currently %d active ports.\n" name !numports;
        Log.printf1 "Spawning internal cables for switch %s...\n" name;
	List.iter (fun thunk -> thunk ())
	  (List.map (* Here map returns a list of thunks *)
	     begin fun internal_cable_process () ->
	       (* The protocol implemented here should ensure that vde_switch will not be solicited
	          before having accepted the previously asked connection. However, for safety we add
	          a little delay in order to give to vde_switch the time to allocate the previous port: *)
	       Thread.delay 0.1;
	       (* Now we launch the process that will ask vde_switch to obtain a new port: *)
	       internal_cable_process#spawn;
	       incr numports;
	       let answer =
	         Either.extract (wait_vde_switch_until_ports_will_be_allocated ~numports:(!numports) ~socketfile ())
	       in
	       (if answer <> !numports then
	          Log.printf3 "Unexpected vde_switch %s answer: %d instead of the expected value %d. Ignoring.\n" name answer !numports
	        );
	       Log.printf2 "Ok, the vde_switch %s has now %d allocated ports.\n" name !numports;
	       end
 	     self#get_internal_cable_processes);
 	(* Now send rc commands to the switch, and write down what it answers (episode 4 of
	   `journalisation-profonde'): the exchange still happens in a thread of its own, because
	   it must not delay the spawning, but its answers are no longer dropped. *)
        let journal = self#rc_journal in
        match rcfile_content with
        | None -> write_rc_journal_without_rc ~journal ~name ()
        | Some commands ->
            ignore
              (Thread.create
                 (send_commands_to_vde_switch_and_journal ~socketfile ~commands ~name ~journal) ())


  initializer

  match show_vde_terminal with
  | false -> ()
  | true ->
    let name = parent#get_name in
    self#add_accessory_process
      (new Simulation_level.unixterm_process
        ~xterm_title:(name^" terminal")
        ~management_socket_name:(Option.extract self#get_management_socket_name)
 	~unexpected_death_callback:
 	   (fun i _ ->
 	      Death_monitor.stop_monitoring i;
 	      Log.printf2 "Terminal of switch %s closed (pid %d).\n" name i)
	())

end;;

end (* module Simulation_level_switch *)

(** Just for testing: *)
let test = Dialog_add_or_update.make
