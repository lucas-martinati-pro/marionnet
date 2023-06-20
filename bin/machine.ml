(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2010-2017  Jean-Vincent Loddo
   Copyright (C) 2010-2017  Université Paris 13

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


(** User-level component "machine" implementation. *)

(* The module containing the add/update dialog is defined later,
   using the syntax extension "where" *)
#load "where_p4.cmo"
;;

(* --- *)
module Log = Marionnet_log
module Option = Ocamlbricks.Option
module Either = Ocamlbricks.Either
module Misc = Ocamlbricks.Misc
module Flip = Ocamlbricks.Flip
module PervasivesExtra = Ocamlbricks.PervasivesExtra
module ListExtra = Ocamlbricks.ListExtra
module StrExtra = Ocamlbricks.StrExtra
module Lazy_perishable = Ocamlbricks.Lazy_perishable
module OoExtra = Ocamlbricks.OoExtra
module Future = Ocamlbricks.Future
module Forest = Ocamlbricks.Forest
module Linux = Ocamlbricks.Linux
module Network = Ocamlbricks.Network
module Widget = Ocamlbricks.Widget
module Xforest = Ocamlbricks.Xforest
(* --- *)
open Gettext
let spr fmt = Printf.sprintf fmt

type filename = string
(* type pid = int *)

(* Machine component related constants: *)
(* TODO: make it configurable! *)
module Const = struct
 let port_no_default = 1
 let port_no_min = 1
 let port_no_max = 8

 let memory_default = 48
 let memory_min = 8
 (* let memory_max = 256 *)
 (* In order to test with selinux: *)
 let memory_max = 1024

 let initial_content_for_rcfiles =
"#!/bin/bash
# ---
# This script will be executed (sourced) as final step
# of the virtual machine bootstrap process.
# ---
# Several variables are set at this point.
# Examples: (some values depend on your settings)
# ---
# hostname='m5'
# mem='80M'
# virtualfs_kind='machine'
# virtualfs_name='machine-debian-wheezy-08367'
# mac_address_eth0='02:04:06:15:ad:0a'
# mtu_eth0='1500'
# mit_magic_cookie_1='e33a9778b5b4d71059c83760473211bb'
# PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
# ---
# Your effective user and group IDs are uid=0 (root), gid=0 (root),
# and the current working directory is '/', that is to say PWD='/'
# ---
" ;;

end

(* The type of data returned by the dialog: *)
module Data = struct
type t = {
  name               : string;
  label              : string;
  memory             : int;
  port_no            : int;
  distribution       : string;          (* epithet *)
  variant            : string option;
  kernel             : string;          (* epithet *)
  rc_config          : bool * string;   (* run commands (rc) file configuration *)
  console_no         : int;
  terminal           : string;
  old_name           : string;
  }

let to_string t = "<obj>" (* TODO? *)
end (* Data *)

module Make_menus (Params : sig
  val st      : State.globalState
  val packing : [ `toolbar of GButton.toolbar | `menu_parent of Menu_factory.menu_parent ]
 end) = struct

  open Params

  module Toolbar_entry = struct
   let imagefile = "ico.machine.palette.png"
   let tooltip   = (s_ "Machine")
   let packing   = Params.packing
  end

  module Add = struct
    include Data

    let key = Some GdkKeysyms._M

    let ok_callback t = Gui_bricks.Ok_callback.check_name t.name t.old_name st#network#name_exists t

    let dialog () =
      let name = st#network#suggestedName "m" in
      Dialog_add_or_update.make
        ~title:(s_ "Add machine") ~name ~ok_callback ()

    let reaction {
         name = name;
         label = label;
         memory = memory;
         port_no = port_no;
         distribution = distribution;
         variant = variant;
	 kernel = kernel;
         rc_config = rc_config;
	 console_no = console_no;
         terminal = terminal;
         old_name = _ ;
         }
      =
      let action () = ignore (
        new User_level_machine.machine (* defined later with WHERE *)
          ~network:st#network
          ~name
          ~label
	  ~memory
	  ~port_no
          ~epithet:distribution
          ?variant:variant
          ~kernel
          ~rc_config
          ~console_no
 	  ~terminal
          ())
      in
      st#network_change action ();

  end (* Add *)

  module Properties = struct
    include Data
    let dynlist () = st#network#get_node_names_that_can_startup ~devkind:`Machine ()

    let dialog name () =
     let m = (st#network#get_node_by_name name) in
     let m = ((Obj.magic m):> User_level_machine.machine) in
     let title = (s_ "Modify machine")^" "^name in
     let label = m#get_label in
     let memory = m#get_memory in
     let port_no = m#get_port_no in
     let distribution = m#get_epithet in
     let variant = m#get_variant in
     let kernel = m#get_kernel in
     let rc_config = m#get_rc_config in
     let console_no = m#get_console_no in
     let terminal = m#get_terminal in
     (* The user cannot remove receptacles used by a cable. *)
     let port_no_min = st#network#port_no_lower_of (m :> User_level.node)
     in
     Dialog_add_or_update.make
       ~title ~name ~label
       ~memory ~port_no ~port_no_min
       ~distribution ?variant
       ~kernel
       ~rc_config
       ~console_no
       ~terminal
       ~updating:() (* the user cannot change the distrib & variant *)
       ~ok_callback:Add.ok_callback  ()


    let reaction {
         name = name;
         label = label;
         memory = memory;
         port_no = port_no;
         distribution = distribution;
         variant = variant;
	 kernel = kernel;
         rc_config = rc_config;
	 console_no = console_no;
         terminal = terminal;
         old_name = old_name;
         }
      =
      let d = (st#network#get_node_by_name old_name) in
      let m = ((Obj.magic d):> User_level_machine.machine) in
      let action () =
        m#update_machine_with
          ~name ~label
          ~memory ~port_no
	  ~kernel
          ~rc_config
	  ~console_no ~terminal
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
        ~markup:(Printf.sprintf (f_ "Are you sure that you want to remove %s\nand all the cables connected to this %s?") name (s_ "machine"))
        ~context:name
        ()

    let reaction name =
      let d = (st#network#get_node_by_name name) in
      let m = ((Obj.magic d):> User_level_machine.machine) in
      let action () = m#destroy in
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
    let dynlist () = st#network#get_node_names_that_can_gracefully_shutdown ~devkind:`Machine ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#gracefully_shutdown

  end

  module Suspend = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_suspend ~devkind:`Machine ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#suspend

  end

  module Resume = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_resume ~devkind:`Machine ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#resume

  end

 module Create_entries =
  Gui_toolbar_COMPONENTS_layouts.Layout_for_network_node (Params) (Toolbar_entry) (Add) (Properties) (Remove) (Startup) (Stop) (Suspend) (Resume)

 (* Subscribe this kind of component to the network club: *)
 st#network#subscribe_a_try_to_add_procedure Eval_forest_child.try_to_add_machine;

end

(*-----*)
  WHERE
(*-----*)

module Dialog_add_or_update = struct

(* This function may be useful for testing the widget creation without
   recompiling the whole project. *)
let make
 ?(title="Add a machine")
 ?(name="")
 ?label
 ?(memory=Const.memory_default)
 ?(memory_min=Const.memory_min)
 ?(memory_max=Const.memory_max)
 ?(port_no=Const.port_no_default)
 ?(port_no_min=Const.port_no_min)
 ?(port_no_max=Const.port_no_max)
 ?distribution
 ?variant
 ?kernel
 ?(rc_config=(false, Const.initial_content_for_rcfiles))
 ?(updating:unit option)
 ?(console_no=1)
 ?terminal
 ?(help_callback=help_callback) (* defined backward with "WHERE" *)
 ?(ok_callback=(fun data -> Some data))
 ?(dialog_image_file=Initialization.Path.images^"ico.machine.dialog.png")
 () :'result option =
  let old_name = name in
  let vm_installations =  Lazy_perishable.force (Disk.get_machine_installations) in
  let (dialog_machine, _, name,label) =
    Gui_bricks.Dialog_add_or_update.make_window_image_name_and_label
      ~title
      ~image_file:dialog_image_file
      ~image_tooltip:(s_ "Virtual machine")
      ~name
      ~name_tooltip:(s_ "Virtual machine name. This name must be unique in the virtual network.")
      ?label
      ()
  in
  let (memory, port_no, distribution_variant_kernel, rc_config, console_no, terminal) =
    let vbox = GPack.vbox ~homogeneous:false ~border_width:20 ~spacing:10 ~packing:dialog_machine#vbox#add () in
    let form =
      Gui_bricks.make_form_with_labels
        ~packing:vbox#add
        [(s_ "Memory <tt>(Mb)</tt>");
         (s_ "Ethernet cards");
         (s_ "Distribution");
         (s_ "Variant");
         (s_ "Kernel");
         (s_ "Startup configuration");
         (s_ "Consoles");
         (* (s_ "Terminal"); *)
         ]
    in
    form#add_section ~no_line:() "Hardware";
    (* --- *)
    let on_distrib_change = ref [] (* a list of callbacks *) in
    (* --- *)
    (* memory widget: *)
    let memory =
      Gui_bricks.spin_byte ~lower:memory_min ~upper:memory_max ~step_incr:8
      ~packing:(form#add_with_tooltip (s_ "Amount of RAM to be reserved for this machine.")) memory
    in
    (* port_no widget: *)
    let port_no =
      Gui_bricks.spin_byte ~lower:port_no_min ~upper:port_no_max ~step_incr:1
      ~packing:(form#add_with_tooltip (s_ "Number of ethernet cards (eth0, eth1 ...) of the virtual machine")) port_no
    in
    form#add_section "Software";
    let (distribution_variant_kernel) =
      let packing_distribution =
        form#add_with_tooltip
          (s_ "GNU/Linux distribution installed on the virtual machine.")
      in
      let packing_variant =
        form#add_with_tooltip
          (s_ "Initial hard disk state. The virtual machine will start by default with this variant of the chosen distribution.")
      in
      let packing_kernel =
        form#add_with_tooltip
          (s_ "Linux kernel version used for this virtual machine.")
      in
      let packing = (packing_distribution, packing_variant, packing_kernel) in
      Gui_bricks.make_combo_boxes_of_vm_installations
        ~on_distrib_change:(fun distrib -> List.iter (fun f -> f distrib) !on_distrib_change)
        ?distribution ?variant ?kernel ?updating
        ~packing
        vm_installations
    in
    (* --- *)
    let rc_config =
       Gui_bricks.make_rc_config_widget
         ~width:800
         ~filter_names:[`BASH; `RC; `ALL]
         ~parent:(dialog_machine :> GWindow.window_skel)
         ~packing:(form#add_with_tooltip (s_ "Check to activate a startup configuration" ))
         ~active:(fst rc_config)
         ~content:(snd rc_config)
         ~device_name:(old_name)
         ~language:("sh")
         ()
    in
    (* --- *)
    (* Register and call the "Startup configuration" callback according to current distribution:  *)
    let () =
      let callback (d: [`distrib] Disk.epithet (* i.e. string *)) =
        let sensitive = (vm_installations#marionnet_relay_supported_by d) in
        form#set_sensitive ~label_text:(s_ "Startup configuration") (sensitive)
      in
      on_distrib_change := (callback)::!on_distrib_change;
      let current = distribution_variant_kernel#selected in
      callback (current)
    in
    (* --- *)
    form#add_section "Access";
    (* console_no widget and callback: *)
    let console_no =
      Gui_bricks.spin_byte ~lower:1 ~upper:8 ~step_incr:1
      ~packing:(form#add_with_tooltip (s_ "Number of consoles (tty0, tty1 ...) of the virtual machine")) console_no
    in
    (* Register and call the "Consoles" callback and set it according to current distribution:  *)
    let () =
      let callback (d: [`distrib] Disk.epithet (* i.e. string *)) =
        let sensitive = (vm_installations#multiple_consoles_supported_by d) in
        form#set_sensitive ~label_text:(s_ "Consoles") (sensitive);
        (* console_no#misc#set_sensitive (sensitive); *)
        (if not sensitive then console_no#set_value 1.);
      in
      on_distrib_change := (callback)::!on_distrib_change;
      let current = distribution_variant_kernel#selected in
      callback (current)
    in
    (* Register `memory' callback and set it according to current distribution:  *)
    let () =
      let callback (d: [`distrib] Disk.epithet (* i.e. string *)) =
        let memory_min = (vm_installations#memory_min_size_of d) in
        let () = Option.iter (fun x -> memory#adjustment#set_bounds ~lower:(float_of_int x) ()) memory_min in
        let memory_suggested = (vm_installations#memory_suggested_size_of d) in
        let () = Option.iter (fun x -> memory#set_value (float_of_int x)) memory_suggested in
        ()
      in
      on_distrib_change := (callback)::!on_distrib_change;
      let current = distribution_variant_kernel#selected in
      if updating = None then callback (current) else ()
    in
    (* Terminal type: *)
    let _terminal =
      let _tooltip = (s_ "Type of terminal to use to control the virtual machine. Possible choices are: X HOST terminal (providing the possibility to launch graphical applications on the host X server) and X NEST (an independent graphic server displaying all the X windows of a virtual machines).")
      in
      let result =
        Widget.ComboTextTree.fromList
          ~callback:None
          (* ~packing:(Some (form#add_with_tooltip tooltip)) *)
          ((vm_installations#terminal_manager_of "unused epithet")#get_choice_list)
      in
      Option.iter (fun v -> result#set_active_value v) terminal;
      result
    in
    (* --- *)
    (* TODO: to be fully implemented or removed: *)
    (* let () = form#set_sensitive ~label_text:(s_ "Terminal") (false) in *)
    let () = form#add_section ~no_line:() "" in (* Just leave an empty row in place of the `terminal' widget *)
    (* terminal#box#misc#set_sensitive false; *)
    (* --- *)
    (memory, port_no, distribution_variant_kernel, rc_config, console_no, _terminal)
  in
  (* --- *)
  let get_widget_data () :'result =
    let name = name#text in
    let label = label#text in
    let memory = int_of_float memory#value in
    let port_no = int_of_float port_no#value in
    let distribution  = distribution_variant_kernel#selected in
    let variant       = distribution_variant_kernel#slave0#selected in
    let kernel        = distribution_variant_kernel#slave1#selected in
    let rc_config = (rc_config#active, rc_config#content) in
    let variant = match variant with
    | "none" -> None
    | x      -> Some x
    in
    let console_no = int_of_float console_no#value in
    let terminal = terminal#selected in
      { Data.name = name;
        Data.label = label;
	Data.memory = memory;
        Data.port_no = port_no;
        Data.distribution = distribution;
        Data.variant = variant;
        Data.kernel = kernel;
        Data.rc_config = rc_config;
        Data.console_no = console_no;
        Data.terminal = terminal;
        Data.old_name = old_name;
        }

  in
  (* The result of make is the result of the dialog loop (of type 'result option): *)
  Gui_bricks.Dialog_run.ok_or_cancel (dialog_machine) ~ok_callback ~help_callback ~get_widget_data ()


(*-----*)
  WHERE
(*-----*)

let help_callback =
   let title = (s_ "ADD OR MODIFY A VIRTUAL MACHINE") in
   let msg   = (s_ "\
In this dialog window you can define the name of the virtual \
machine and set several hardware and software parameters.\n\n\
SECTION 'Hardware'\n\
- Memory: amount of memory (RAM) that will be reserved on \
the host for this virtual machine (default 48 Mb)\n\n\
- Ethernet Card: number of Ethernet cards (defalut 1)\n\n\
SECTION 'Software':\n\n\
- Distribution: the GNU/Linux distribution (Debian, Mandriva, Gentoo,..), \
chosen among those available in the filesystem directory\n\n\
- Variant: a variant (or patch) of the given distribution; a variant is a \
COW (Copy On Write) file that represents a small update of the used distribution.\
Available variants are in the variants/ subdirectory of the filesystem directory. \
You can make your own variants by exporting any virtual machine state in the 'Disks' \
tab.\n\n\
- Kernel: the Linux kernel version, chosen among the ones available in the kernels/ \
subdirectory\n\n\
SECTION 'UML':\n\n\
- Terminal: the possible choices are 'X HOST' and 'X NEST'; the first one \
allows the user to run graphic applications from a text terminal where the user \
can operate the virtual machine (with user 'root' and password 'root'); \
the second allows the user to have a real graphic server reserved for the virtual \
machine, with independent windows manager and desktops environments.")
   in Simple_dialogs.help title msg ;;

end

(*-----*)
  WHERE
(*-----*)

module Eval_forest_child = struct

 let try_to_add_machine (network:User_level.network) ((root,children):Xforest.tree) =
  try
   (match root with
    | ("machine", attrs) ->
    	let name  = List.assoc "name" attrs in
	(* The key "eth" is also tried for backward-compatibility: *)
	let port_no = int_of_string (ListExtra.Assoc.find_first ["port_no"; "eth"] attrs) in
        Log.printf2 "Importing machine \"%s\" with %d ethernet cards...\n" name port_no;
	let x = new User_level_machine.machine ~network ~name ~port_no () in
	x#from_tree ("machine", attrs) children;
        Log.printf1 "Machine \"%s\" successfully imported.\n" name;
        true
   | _ -> false
   )
  with _ -> false
end (* module Eval_forest_child *)

(*-----*)
  WHERE
(*-----*)


module User_level_machine = struct

class machine
  ~(network:User_level.network)
  ~name
  ?label
  ?(memory=Const.memory_default)
  ?epithet
  ?variant
  ?kernel
  ?(rc_config=(false,""))
  ?(console_no=1)
  ?terminal
  ~port_no
  ()
  =
  let vm_installations = Lazy_perishable.force (Disk.get_machine_installations) in
  let network_alias = network in

  object (self) inherit OoExtra.destroy_methods ()

  inherit User_level.node_with_defects
    ~network
    ~name
    ?label
    ~devkind:`Machine
    ~port_no
    ~port_no_min:Const.port_no_min
    ~port_no_max:Const.port_no_max
    ~port_prefix:"eth"
    ~user_port_offset:0
    ()
    as self_as_node_with_defects

  inherit User_level.virtual_machine_with_history_and_ifconfig
    ~network:network_alias
    ?epithet ?variant ?kernel ?terminal
    ~history_icon:"machine"
    ~ifconfig_device_type:"machine"
    ~vm_installations
    ()
    as self_as_virtual_machine_with_history_and_ifconfig

  method polarity = User_level.MDI
  method string_of_devkind = "machine"

  (* Redefinition: *)
  method! dot_fontsize_statement = ""

  (** A machine will be started with a certain amount of memory *)
  val mutable memory : int = memory
  initializer ignore (self#check_memory memory)
  method get_memory = memory
  method set_memory x = memory <- self#check_memory x
  method private check_memory x =
    match (x>=Const.memory_min) && (x<=Const.memory_max) with
    | true  -> x
    | false ->
        self#logged_failwith "%s" (Printf.sprintf "value %d not in the memory range [%d,%d]" x Const.memory_min Const.memory_max)

  val mutable rc_config : bool * string  = rc_config
  method get_rc_config = rc_config
  method set_rc_config x = rc_config <- x

  val mutable console_no : int = console_no
  initializer ignore (self#check_console_no console_no)
  method get_console_no = console_no
  method set_console_no x = console_no <- self#check_console_no x
  method private check_console_no x =
    match (x>=1) && (x<=8) with
    | true  -> x
    | false ->
        self#logged_failwith "%s" (spr "value %d not in the console no. range [%d,%d]" x 1 8)

  (** Show for debugging *)
  method show = name

  method defects_device_type = "machine"

  method dotImg iconsize =
   let imgDir = Initialization.Path.images in
   (imgDir^"ico.machine."^(self#string_of_simulated_device_state)^"."^iconsize^".png")

  method to_tree =
   Forest.tree_of_leaf ("machine", [
      ("name"     ,  self#get_name );
      ("label"    ,  self#get_label );
      ("memory"   ,  (string_of_int self#get_memory));
      ("distrib"  ,  self#get_epithet  );
      ("variant"  ,  self#get_variant_as_string);
      ("kernel"   ,  self#get_kernel   );
      ("rc_config",  Marshal.to_string self#get_rc_config []);
      ("console_no", (string_of_int self#get_console_no));
      ("terminal" ,  self#get_terminal );
      ("port_no"  ,  (string_of_int self#get_port_no))  ;
      ])

 (** A machine has just attributes (no children) in this version. *)
 method! eval_forest_attribute = function
  | ("name"     , x ) -> self#set_name x
  | ("label"    , x ) -> self#set_label x
  | ("memory"   , x ) -> self#set_memory (int_of_string x)
  | ("distrib"  , x ) -> self#set_epithet x
  | ("variant"  , "aucune" ) -> self#set_variant None (* backward-compatibility *)
  | ("variant"  , "" )-> self#set_variant None
  | ("variant"  , x ) -> self#set_variant (Some x)
  | ("kernel"   , x ) -> self#set_kernel x
  | ("rc_config", x ) -> self#set_rc_config (Marshal.from_string x 0)
  | ("console_no" , x ) -> self#set_console_no (int_of_string x)
  | ("terminal" , x ) -> self#set_terminal x
  | ("eth"      , x ) (* backward-compatibility *)
  | ("port_no"  , x ) -> self#set_port_no  (int_of_string x)
  | _ -> () (* Forward-comp. *)


 (** Create the simulated device *)
 method private make_simulated_device =
    let id = self#id in
    let cow_file_name, get_the_cow_file_name_source =
      self#create_cow_file_name_and_thunk_to_get_the_source
    in
    let rcfile_content =
      match self#get_rc_config with
      | false, _ -> None
      | true, content -> Some content
    in
    let () =
     Log.printf5
       "About to start the machine %s\n  with filesystem: %s\n  cow file: %s\n  kernel: %s\n  xnest: %b\n"
       self#name
       self#get_filesystem_file_name
       cow_file_name
       self#get_kernel_file_name
       self#is_xnest_enabled
    in
    let device =
      new Simulation_level.machine
        ~parent:self
        ~kernel_file_name:self#get_kernel_file_name
        ?kernel_console_arguments:self#get_kernel_console_arguments
        ?filesystem_relay_script:self#get_filesystem_relay_script
        ?rcfile_content
        ~filesystem_file_name:self#get_filesystem_file_name
        ~get_the_cow_file_name_source
        ~cow_file_name
        ~states_directory:(self#get_states_directory)
        ~hostfs_directory:(self#get_hostfs_directory ())
        ~ethernet_interface_no:self#get_port_no
        ~memory:self#get_memory
        ~console_no:self#get_console_no
        ~umid:self#get_name
        ~id
        ~xnest:self#is_xnest_enabled
        ~working_directory:(network#project_working_directory)
        ~unexpected_death_callback:self#destroy_because_of_unexpected_death
        ()
    in
    (device :> User_level.node_with_ports_card Simulation_level.device)

 (** Here we also have to manage cow files... *)
 method! private gracefully_shutdown_right_now =
    Log.printf1 "Calling hostfs_directory on %s...\n" self#name;
    let hostfs_directory = self#get_hostfs_directory () in
    Log.printf "Ok, we're still alive\n";
    (* Do as usual... *)
    self_as_node_with_defects#gracefully_shutdown_right_now;
    (* If we're in exam mode then make the report available in the texts treeview: *)
    (if Initialization.are_we_in_exam_mode then begin
      let treeview_documents = Treeview_documents.extract () in
      Log.printf1 "Adding the report on %s to the texts interface\n" self#name;
      treeview_documents#import_report
        ~machine_or_router_name:self#name
        ~pathname:(hostfs_directory ^ "/report.html")
        ();
      Log.printf1 "Added the report on %s to the texts interface\n" self#name;
      Log.printf1 "Adding the history on %s to the texts interface\n" self#name;
      treeview_documents#import_history
        ~machine_or_router_name:self#name
        ~pathname:(hostfs_directory ^ "/bash_history.text")
        ();
      Log.printf1 "Added the history on %s to the texts interface\n" self#name;
    end);
    (* ...And destroy, so that the next time we have to re-create the process command line
       can use a new cow file (see the make_simulated_device method) *)
    self#destroy_right_now

 (** Here we also have to manage cow files... *)
 method! private poweroff_right_now =
    (* Do as usual... *)
    self_as_node_with_defects#poweroff_right_now;
    (* ...And destroy, so that the next time we have to re-create the process command line
       can use a new cow file (see the make_simulated_device method) *)
    self#destroy_right_now

 method update_machine_with ~name ~label ~memory ~port_no ~kernel ~rc_config ~console_no ~terminal =
   (* first action: *)
   self_as_virtual_machine_with_history_and_ifconfig#update_virtual_machine_with ~name ~port_no kernel;
   (* then we can set the object property "name" (read by #get_name): *)
   self_as_node_with_defects#update_with ~name ~label ~port_no;
   self#set_memory memory;
   self#set_rc_config (rc_config);
   self#set_console_no console_no;
   self#set_terminal terminal;

 (* ---------------------------------------------------------------------
        Code section about X11-forwarding based on pseudo-terminals:
    --------------------------------------------------------------------- *)
 (*
                    HOST SIDE                  |          GUEST SIDE
                                               |
  [] <======-marionnet-fork-or-thread-======>[]|[]<=========-socat-=========>[]
  unix/inet                     pseudo-terminal|serial port    /tmp/.X11-uix/X0
  X11 server socket            Ex:"/dev/pts/29"|Ex:"/dev/ttyS4"     unix socket
  Ex:(inet 127.0.0.1:6010)                     |

  The marionnet-dummy-xserver, running on guest side, accepts connections from the Unix socket "/tmp/.X11-unix/Xd"
  (corresponding to DISPLAY=:d.0) and, for an accepted connexion, starts the script marionnet-dummy-xservice that do the job.
  Basically, this job is nothing more than a "socat" service (/usr/bin/socat, see "man socat") connecting this socket to an
  available (simulated) serial port in the range /dev/ttySx. The UML kernel will be kind enough to provide an associated
  pseudo-terminal (/dev/pts/x) on host side, and marionnet.native, running on host side, will provide the rest of connection
  from the good pseudo-terminal to the real X11 server. The marionnet-dummy-xserver is itself implemented with /usr/bin/socat
  (instead of another "native-program" of this repository) in order to facilitate the installation of all the necessary stuff
  in the guest GNU/Linux systems.
  ---
  The little script "uml/guest/make-tarball-for-guest-system.sh" builds easily a tarball, with all the stuff
  (/etc/init.d/marionnet-{relay,dummy-xserver}, /usr/bin/marionnet-dummy-xservice), ready to be extracted in the
  root directory of the guest filesystem.
 *)

 (* Watching thread as future (may be tasted): *)
 val mutable hostfs_watching_thread : (unit Future.t) option = None
 (* --- *)
 (* Most of them are probably not active: *)
 val mutable pts_relays : (filename * (((exn, unit) Either.t Future.t) * Future.Control.t)) list = []
 (* --- *)
 method private stop_pts_relays ?host_pts ?all () =
   let try_to_kill (ctrl) =
     let (pid, tid, kill_method) = ctrl in
     let () = Log.printf3 "machine[%s]#stop_pts_relay: about to break relay %d.%d\n" (self#name) (pid) (tid) in
     kill_method ()
   in
   let () =
     match host_pts, all with
     (* --- *)
     | Some pts, _ ->
         ListExtra.search (fun (fname, (prm, ctrl)) -> fname=pts) (pts_relays) |> Option.iter (fun (fname, (prm, ctrl)) -> begin
              try_to_kill (ctrl)
            end)
     (* --- *)
     | _,  Some () ->
         Flip.flip (List.iter) (pts_relays) (fun (fname, (prm, ctrl)) -> begin
              try_to_kill (ctrl)
            end)
     | _, _ -> ()
   in
   (* --- *)
   (* Remove non active futures (threads or forks) and prevent zombies, if any: *)
   let garbage_collection () =
     pts_relays <- Flip.flip (List.filter) (pts_relays) (fun (fname, (prm, ctrl)) -> begin
        let to_be_removed = (Future.terminated prm) in
        (* --- *)
        let () = if (to_be_removed) then
          let (pid, tid, kill_method) = ctrl in
          try Unix.waitpid [Unix.WNOHANG] (pid) |> ignore with _ -> ()
        in
        not (to_be_removed)
       end)
   in
   (* Leave a time to process forks to exit: *)
   let () = Thread.delay 0.1 in
   (* Do it: *)
   let () = garbage_collection () in
   ()
 (* --- *)
 (* Launch, a bit of garbage collection, then register the new relay: *)
 method private start_pts_relay ?no_fork ~host_pts () =
  try
    (* --- *)
    (* Check existence and delay twice: *)
    let () = if Sys.file_exists (host_pts) then () else Thread.delay 1. in (* N°1 *)
    let () = if Sys.file_exists (host_pts) then () else Thread.delay 2. in (* N°2 *)
    let () = if Sys.file_exists (host_pts) then () else
      let () = Log.printf2 "machine[%s]#start_pts_relay: file %s NOT FOUND\n" (self#name) (host_pts) in
      assert false
    in
    if X.xserver_address = None then failwith "X server not available" else (* continue: *)
    let target : Network.server_address = Option.extract (X.xserver_address) in
    (* --- *)
    let () = Log.printf4 "machine[%s]#start_pts_relay: about to start a pts relay (%s) %s -> %s\n"
      (self#name) (if no_fork=None then "fork" else "thread") (host_pts) (Network.string_of_server_address target)
    in
    let (prm, ctrl) : ((exn, unit) Either.t Future.t) * (Future.Control.t) =
      Network.Socat.pts_of_stream_server ?no_fork ~filename:(host_pts) ~target ()
    in
    let (pid, tid, _) = ctrl in
    let () =
      Log.printf3 "machine[%s]#start_pts_relay: future (pid %d.%d) started to deserve an X11 application\n" (self#name) (pid) (tid) ;
      Flip.flip Option.iter (Future.taste prm) (function
        | Either.Left  e  -> Log.printf2 "machine[%s]#start_pts_relay: exception: %s\n" (self#name) (Printexc.to_string e)
        | Either.Right () -> Log.printf2 "machine[%s]#start_pts_relay: fork %d strangely exited!\n" (self#name) (pid)
        )
    in
    (* --- *)
    let () = pts_relays <- (host_pts, (prm, ctrl)) :: pts_relays in
    ()
  with e ->
    let () = Log.print_exn ~prefix:"machine[%s]#start_pts_relay: FAILED with: " e in
    ()

 (* --- *)
 (* Called at initialization-time. The thread will be automatically stopped
    when the instance wil be destroyed. *)
 method private start_hostfs_x11_directory_watching_thread () : unit Future.t =
     (* --- *)
   let hostfs_x11_directory = Filename.concat (self#get_hostfs_directory ()) ".X11-unix" in
   let () = Misc.protect2 Unix.mkdir (hostfs_x11_directory) 0o777 in
   let () = Misc.protect2 Unix.chmod (hostfs_x11_directory) 0o777 in
   (* --- *)
   let callback =
     (* --- *)
     let ropened = Str.regexp "^ttyS[1-9][0-9]*[-]pts[1-9][0-9]*.opened$" in
     let rclosed = Str.regexp "^ttyS[1-9][0-9]*[-]pts[1-9][0-9]*.closed$" in
     (* --- *)
     fun ((wd, ks, _, opath) as _event) ->
       if opath = None then true (* return *) else (* continue: *)
       (* --- *)
       let path     = Option.extract opath in
       let fullpath = Filename.concat (hostfs_x11_directory) (path) in
       let host_pts = String.trim (PervasivesExtra.get_file_content (fullpath)) in (* Ex: "/dev/pts/10" *)
       (* --- *)
       if StrExtra.First.matchingp (ropened) (path) then
         let () = self#start_pts_relay (**) (*~no_fork:()*) (**) ~host_pts () in
         true (* continue watching directory (to serve other guest's X11 connections) *)
       (* --- *)
       else (* elif: *)
       if StrExtra.First.matchingp (rclosed) (path) then
         let () = self#stop_pts_relays ~host_pts () in
         true
       else
         (* do nothing and continue watching: *)
         true
   (* --- end callback *)
   in
   let exit_door = ".break_watching" in
   (* --- *)
   let break_watching () : unit =
     let filename = Filename.concat (hostfs_x11_directory) (exit_door) in
     PervasivesExtra.put_file_content ~filename "Bye"
   in
   (* --- *)
   let action () =
     Linux.watch_directory ~verbose:()
         ~exit_door:".break_watching"
         ~selector:[Inotify.S_Close_write]
         ~pathfilter:(Str.regexp "^ttyS[1-9][0-9]*[-]pts[1-9][0-9]*.[oc][pl][eo][ns]ed$")
         ~callback
         (hostfs_x11_directory)
   in
   let result = Future.thread action () in
   let () = Log.printf1 "machine[%s]#start_hostfs_x11_directory_watching_thread: STARTED a watching thread\n" (self#name) in
   (* --- *)
   let () = self#add_destroy_callback (lazy (break_watching ())) in
   let () = self#add_destroy_callback (lazy (self#stop_pts_relays ~all:() ())) in
   (* --- *)
   let () = hostfs_watching_thread <- Some (result) in
   result

 (* -------------- *)
 initializer begin
   (* Should depend on "X11_SUPPORT": *)
   let flag = (vm_installations#terminal_manager_of self#get_epithet)#is_hostxserver (self#get_terminal) in
   (* BUG!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! *)
   (* flag is always true!!! and (self#get_epithet) is not correct when a project is load: *)
   (* [22983.8]: machine[m1]#start_hostfs_x11_directory_watching_thread: CONDITION=true EPITHET='default' <= opened project KO (debian-wheezy-08367) *)
   (* [22983.0]: machine[m2]#start_hostfs_x11_directory_watching_thread: CONDITION=true EPITHET='guignol-18474' <= new machine OK *)
   (* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! *)
   let () = Log.printf3 "machine[%s]#start_hostfs_x11_directory_watching_thread: CONDITION=%b EPITHET='%s'\n" (self#name) (flag) (self#get_epithet) in
   let () = if flag then ignore (self#start_hostfs_x11_directory_watching_thread ()) in
   ()
   end
  (* -------------- *)

end;; (* class machine *)

end (* module User_level_machine *)

(*-----*)
  WHERE
(*-----*)

module Simulation_level = struct

class virtual ['parent] device = ['parent] Simulation_level.device

(** A machine: just a [machine_or_router] with [router = false] *)
class ['parent] machine =
  fun ~(parent:'parent)
      ~(filesystem_file_name)
      ~(kernel_file_name)
      ?(kernel_console_arguments)
      ?(filesystem_relay_script)
      (* ?(rcfile_content) *)
      ?(rcfile_content="# Nothing to do this time\n")
      ~get_the_cow_file_name_source
      ~(cow_file_name)
      ~states_directory
      ~hostfs_directory
      ~(ethernet_interface_no)
      ?(memory=40) (* in megabytes *)
      ?umid
      ?(xnest=false)
      ?(console_no=1)
      ~id
      ~working_directory
      ~unexpected_death_callback
      () ->
(* --- *)
object(self)
  inherit ['parent] Simulation_level.machine_or_router
      ~parent
      ~router:false
      ~filesystem_file_name
      ~get_the_cow_file_name_source
      ~cow_file_name
      ~states_directory
      ~hostfs_directory
      ~kernel_file_name
      ?kernel_console_arguments
      ?filesystem_relay_script
      ~rcfile_content
      ~ethernet_interface_no
      ~memory
      ?umid
      ~console:"xterm"
      ~console_no
      ~id
      ~xnest
      ~working_directory
      ~unexpected_death_callback
      ()
      (* as self_as_machine_or_router *)
  method device_type = "computer"
end;;

end (* module Simulation_level *)


(** For testing: *)
let test = Dialog_add_or_update.make
(*
val test :
  ?title:string ->
  ?name:string ->
  ?label:string ->
  ?memory:int ->
  ?memory_min:int ->
  ?memory_max:int ->
  ?port_no:int ->
  ?port_no_min:int ->
  ?port_no_max:int ->
  ?distribution:string ->
  ?variant:string ->
  ?kernel:string ->
  ?rc_config:bool * string ->
  ?updating:unit ->
  ?console_no:int ->
  ?terminal:string ->
  ?help_callback:(unit -> unit) ->
  ?ok_callback:(Data.t -> Data.t option) ->
  ?dialog_image_file:string -> unit -> Data.t option*)
