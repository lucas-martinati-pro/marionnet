(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2017  Jean-Vincent Loddo
   Copyright (C) 2017  Université Paris 13

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
open Ocamlbricks

(* Machine component related constants: *)
module Const :
  sig
    val port_no_default : int
    val port_no_min     : int
    val port_no_max     : int
    val memory_default  : int
    val memory_min      : int
    val memory_max      : int
    val initial_content_for_rcfiles : string
  end

(* The type of data returned by the dialog: *)
module Data : sig
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
end (* Data *)

module Make_menus :
  functor
    (Params : sig
                val st      : State.globalState
                val packing : [ `menu_parent of Menu_factory.menu_parent | `toolbar of GButton.toolbar ]
              end) ->
  sig
    (* This functor produces a side effect on the GUI. No code has to be exported. *)
  end

module User_level_machine : sig

  class machine :
    network     : User_level.network ->
    name        : string ->
    ?label      : string ->
    ?memory     : int ->
    ?epithet    : [ `distrib ] Disk.epithet ->
    ?variant    : string ->
    ?kernel     : [ `kernel ] Disk.epithet ->
    ?rc_config  : bool * string ->
    ?console_no : int ->
    ?terminal   : string ->
    port_no     : int ->
    unit ->
    object
      (* --- *)
      method id                              : int
      method name                            : string
      (* --- *)
      method get_name                        : string
      method set_name                        : string -> unit
      (* --- *)
      method get_label                       : string
      method set_label                       : string -> unit
      (* --- *)
      method get_memory                      : int
      method set_memory                      : int -> unit
      (* --- *)
      method get_port_no                     : int
      method set_port_no                     : int -> unit
      method polarity                        : User_level.polarity
      method ports_card                      : machine User_level.ports_card
      method port_prefix                     : string
      method port_no_min                     : int
      method port_no_max                     : int
      method user_port_offset                : int
      (* --- *)
      method get_epithet                     : [ `distrib ] Disk.epithet
      method set_epithet                     : [ `distrib ] Disk.epithet -> unit
      (* --- *)
      method get_filesystem_file_name        : Disk.realpath
      method get_filesystem_relay_script     : Disk.filename option
      (* --- *)
      method get_variant                     : [ `variant ] Disk.epithet option
      method set_variant                     : [ `variant ] Disk.epithet option -> unit
      method get_variant_as_string           : [ `variant ] Disk.epithet
      method get_variant_realpath            : Disk.realpath option
      (* --- *)
      method get_states_directory            : string
      method get_hostfs_directory            : ?name   :string (* self#get_name *) -> unit -> string
      (* --- *)
      method get_kernel                      : [ `kernel ] Disk.epithet
      method set_kernel                      : [ `kernel ] Disk.epithet -> unit
      (* --- *)
      method get_kernel_console_arguments    : string option
      method get_kernel_file_name            : Disk.realpath
      (* --- *)
      method get_rc_config                   : bool * string
      method set_rc_config                   : bool * string -> unit
      (* --- *)
      method get_terminal                    : string
      method set_terminal                    : string -> unit
      (* --- *)
      method get_console_no                  : int
      method set_console_no                  : int -> unit
      (* --- *)
      val simulated_device                   : User_level.node_with_ports_card Simulation_level.device option ref
      method make_simulated_device           : User_level.node_with_ports_card Simulation_level.device
      method simulated_device_state          : User_level.simulated_device_automaton_state
      method next_simulated_device_state     : User_level.simulated_device_automaton_state option
      method set_next_simulated_device_state : User_level.simulated_device_automaton_state option -> unit
      (* --- *)
      val automaton_state                    : User_level.simulated_device_automaton_state ref
      val next_automaton_state               : User_level.simulated_device_automaton_state option ref
      method automaton_state_as_string       : string
      (* --- *)
      method has_ledgrid                     : bool
      method has_hublet_processes            : bool
      method get_hublet_process_of_port      : int -> Simulation_level.hublet_process
      (* --- *)
      method devkind                         : User_level.devkind
      method string_of_devkind               : string
      method string_of_simulated_device_state: string
      (* --- *)
      method can_startup                     : bool
      method startup                         : unit
      method startup_right_now               : unit
      (* --- *)
      method can_suspend                     : bool
      method suspend                         : unit
      method suspend_right_now               : unit
      (* --- *)
      method can_resume                      : bool
      method resume                          : unit
      method resume_right_now                : unit
      (* --- *)
      method can_gracefully_shutdown         : bool
      method gracefully_shutdown             : unit
      method gracefully_shutdown_right_now   : unit
      method gracefully_restart              : unit
      (* --- *)
      method can_poweroff                    : bool
      method poweroff                        : unit
      method poweroff_right_now              : unit
      (* --- *)
      method add_my_history                  : unit
      method add_my_ifconfig                 : ?port_row_completions:Treeview_ifconfig.port_row_completions -> int -> unit
      method history_icon                    : Treeview.Row_item.Icon_prj_inj.a
      method ifconfig_device_type            : string
      method defects_device_type             : string
      method leds_relative_subdir            : string
      (* --- *)
      method dotImg                          : User_level.iconsize -> string
      method dotLabelForEdges                : string -> string
      method dotPortForEdges                 : string -> string
      method dotTrad                         : ?nodeoptions:string -> User_level.iconsize -> string
      method dot_fontsize_statement          : string
      method label_for_dot                   : string
      (* --- *)
      method create                          : unit
      method create_cow_file_name_and_thunk_to_get_the_source : string * (unit -> Disk.realpath option)
      method create_right_now                : unit
      (* --- *)
      method destroy                         : unit
      method destroy_my_history              : unit
      method destroy_my_ifconfig             : unit
      method destroy_my_simulated_device     : unit
      method destroy_right_now               : unit
      method add_destroy_callback            : unit Lazy.t -> unit
      (* --- *)
      method eval_forest_attribute           : Xforest.attribute -> unit
      method eval_forest_child               : Xforest.tree -> unit
      method from_tree                       : Xforest.node -> Xforest.forest -> unit
      method to_tree                         : Xforest.tree
      method to_forest                       : Xforest.forest
      (* --- *)
      method logged_failwith                 : 'a 'b. ('a -> string, unit, string, string, string, string) format6 -> 'a -> 'b
      method sprintf                         : ('a, unit, string, string) format4 -> 'a
      method show                            : string
      method mrproper                        : Ocamlbricks.Thunk.lifo_unit_protected_container
      (* --- *)
      method is_correct                      : bool
      method is_xnest_enabled                : bool
      (* --- *)
      method update_machine_with :
        name:string -> label:string -> memory:int -> port_no:int -> kernel:[ `kernel ] Disk.epithet ->
        rc_config:bool * string ->  console_no:int -> terminal:string -> unit
      (* --- *)
      method update_virtual_machine_with     : name:string -> port_no:int -> [ `kernel ] Disk.epithet -> unit
      method update_with                     : name:string -> label:string -> port_no:int -> unit
    end

end (* User_level_machine *)


module (*Machine.*)Simulation_level : sig

  class ['parent] machine :
    parent                    : 'parent ->
    filesystem_file_name      : string ->
    kernel_file_name          : string ->
    ?kernel_console_arguments : string ->
    ?filesystem_relay_script  : string ->
    ?rcfile_content           : string ->
    get_the_cow_file_name_source : (unit -> string option) ->
    cow_file_name             : string ->
    states_directory          : string ->
    hostfs_directory          : string ->
    ethernet_interface_no     : int ->
    ?memory                   : int ->
    ?umid                     : string ->
    ?xnest                    : bool ->
    ?console_no               : int ->
    id                        : int ->
    working_directory         : string ->
    unexpected_death_callback : (unit -> unit) ->
    unit ->
    object
      constraint 'parent =
        < get_name : string;
          ports_card : < get_my_inward_defects_by_index  : int -> Simulation_level.defects_object;
                         get_my_outward_defects_by_index : int -> Simulation_level.defects_object;
                          .. >;
          .. >
      method continue_processes : unit
      method destroy : unit
      method device_type : string
      (* --- *)
      method get_hublet_no : int
      method get_hublet_process_list    : Simulation_level.hublet_process list
      method get_hublet_process_of_port : int -> Simulation_level.hublet_process
      (* --- *)
      method ip_address_eth42 : string
      (* --- *)
      method spawn_processes : unit
      method stop_processes : unit
      method gracefully_shutdown : unit
      method terminate_processes : unit
      method gracefully_terminate_processes : unit
      (* --- *)
      method startup : unit
      method suspend : unit
      method resume : unit
      method shutdown : unit
      (* --- *)
      method execute_the_unexpected_death_callback : int -> string -> unit
    end

end (* Machine.Simulation_level *)

