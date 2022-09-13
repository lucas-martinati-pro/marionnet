(* This file is part of Marionnet
   Copyright (C) 2010-2020  Jean-Vincent Loddo
   Copyright (C) 2010-2020  Université Sorbonne Paris Nord

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

exception ProcessIsntInTheRightState of string

type process_name = string
type pid = int

class virtual process :
  process_name ->
  process_name list ->
  ?stdin:Unix.file_descr ->
  ?stdout:Unix.file_descr ->
  ?stderr:Unix.file_descr ->
  unexpected_death_callback:(int -> string -> unit) ->
  unit ->
  object
    method append_arguments : process_name list -> unit
    (* --- *)
    method spawn     : unit
    method stop      : unit
    method continue  : unit
    method gracefully_terminate : unit
    method terminate : unit
    (* --- *)
    method is_alive  : bool
    method get_pid   : pid
    (* --- *)
  end

class xnest_process :
  ?host_name_as_client:string ->
  ?display_as_client:string ->
  ?screen_as_client:string ->
  ?display_number_as_server:process_name ->
  unexpected_death_callback:(int -> process_name -> unit) ->
  title:'a ->
  unit ->
  object
    inherit process
    method display_number_as_server : process_name
    method display_string_as_client : string
  end

class virtual process_which_creates_a_socket_at_spawning_time :
  process_name ->
  process_name list ->
  ?stdin:Unix.file_descr ->
  ?stdout:Unix.file_descr ->
  ?stderr:Unix.file_descr ->
  ?socket_name_prefix:string ->
  ?management_socket:unit ->
  working_directory:string ->
  unexpected_death_callback:(int -> process_name -> unit) ->
  unit ->
  object
    inherit process
    method get_socket_name            : string
    method get_management_socket_name : string option
  end

class vde_switch_process :
  ?hub:bool ->
  ?port_no:int ->
  ?tap_name:process_name ->
  ?socket_name_prefix:string ->
  ?management_socket:unit ->
  ?fstp:unit ->
  ?rcfile:string ->
  working_directory:string ->
  unexpected_death_callback:(int -> process_name -> unit) ->
  unit ->
  object
    inherit process_which_creates_a_socket_at_spawning_time
  end

class switch_process :
  port_no:int ->
  ?socket_name_prefix:string ->
  ?management_socket:unit ->
  working_directory:string ->
  unexpected_death_callback:(int -> process_name -> unit) ->
  unit ->
  object
    inherit process_which_creates_a_socket_at_spawning_time
  end

class hub_process :
  port_no:int ->
  ?socket_name_prefix:string ->
  ?management_socket:unit ->
  working_directory:string ->
  unexpected_death_callback:(int -> process_name -> unit) ->
  unit ->
  object
    inherit process_which_creates_a_socket_at_spawning_time
  end

class hublet_process :
  ?index:int ->
  working_directory:string ->
  unexpected_death_callback:(int -> process_name -> unit) ->
  unit ->
  object
    inherit process_which_creates_a_socket_at_spawning_time
  end

class slirpvde_process :
  ?network:process_name ->
  ?dhcp:unit ->
  existing_socket_name:process_name ->
  unexpected_death_callback:(int -> process_name -> unit) ->
  unit ->
  object
    inherit process
  end

class unixterm_process :
  ?xterm_title:string ->
  management_socket_name:string ->
  unexpected_death_callback:(int -> process_name -> unit) ->
  unit ->
  object
    inherit process
  end

class telnet_process :
  ?xterm_title:string ->
  ?host:string ->
  ?port_number:int -> (* 2601 *)
  ?delay:float ->     (* 0. *)
  unexpected_death_callback:(int -> process_name -> unit) ->
  unit ->
  object
    inherit process
  end

val defects_to_command_line_options :
  ?rightward_loss:float ->
  ?rightward_duplication:float ->
  ?rightward_flip:float ->
  ?rightward_min_delay:float ->
  ?rightward_max_delay:float ->
  ?leftward_loss:float ->
  ?leftward_duplication:float ->
  ?leftward_flip:float ->
  ?leftward_min_delay:float ->
  ?leftward_max_delay:float ->
  (* --- *)
  unit -> string list

class ethernet_cable_process :
  left_end:< get_socket_name : string; .. > ->
  right_end:< get_socket_name : string; .. > ->
  ?blinker_thread_socket_file_name:process_name option ->
  ?left_blink_command:string option ->
  ?right_blink_command:string option ->
  ?rightward_loss:float ->
  ?rightward_duplication:float ->
  ?rightward_flip:float ->
  ?rightward_min_delay:float ->
  ?rightward_max_delay:float ->
  ?leftward_loss:float ->
  ?leftward_duplication:float ->
  ?leftward_flip:float ->
  ?leftward_min_delay:float ->
  ?leftward_max_delay:float ->
  unexpected_death_callback:(int -> process_name -> unit) ->
  (* --- *)
  unit ->
    object
      inherit process
    end

type defects_object =
       < duplication : float;
         flip        : float;
         loss        : float;
         max_delay   : float;
         min_delay   : float >

val make_ethernet_cable_process :
  left_end:< get_socket_name : string; .. > ->
  right_end:< get_socket_name : string; .. > ->
  ?blinker_thread_socket_file_name:process_name option ->
  ?left_blink_command:string option ->
  ?right_blink_command:string option ->
  leftward_defects: defects_object ->
  rightward_defects: defects_object ->
  unexpected_death_callback:(int -> process_name -> unit) ->
  (* --- *)
  unit -> ethernet_cable_process

val ethernet_interface_to_boot_parameters_bindings :
  string -> int -> 'a -> (string * string) list

val ethernet_interface_to_uml_command_line_argument :
  string -> int -> < get_socket_name : string; .. > -> string

val random_mac_address : unit -> string

class uml_process :
  kernel_file_name:process_name ->
  ?kernel_console_arguments:string ->
  filesystem_file_name:string ->
  ?filesystem_relay_script:string ->
  ?rcfile_content:string ->
  get_the_cow_file_name_source:(unit -> string option) ->
  cow_file_name:string ->
  states_directory:string ->
  hostfs_directory:string ->
  ?swap_file_name:string ->
  ethernet_interface_no:int ->
  hublet_processes:< get_socket_name : string; .. > list ->
  memory:int ->
  console_no:int ->
  console:string ->
  ?umid:string ->
  id:int ->
  ?show_unix_terminal:bool ->
  ?xnest_display_number:string ->
  ?guestkind:string ->
  working_directory:string ->
  unexpected_death_callback:(int -> process_name -> unit) ->
  unit ->
  object
    inherit process
   (* --- *)
    method ip_address_eth42 : string (* "172.23.%i.%i" *)
    method tap_name : string
   (* --- *)
    method create_swap_file : unit
    method delete_swap_file : unit
    method swap_file_name   : string
   (* --- *)
  end

type device_state = Off | On | Sleeping | Destroyed
val device_state_to_string : device_state -> string
exception CantGoFromStateToState of device_state * device_state

class virtual ['parent] device :
  parent:'parent ->
  hublet_no:int ->
  working_directory:string ->
  unexpected_death_callback:(unit -> unit) ->
  unit ->
  object
    constraint 'parent = < get_name : string; .. > as 'b
    (* --- *)
    method virtual device_type : string
    (* --- *)
    method virtual spawn_processes     : unit
    method virtual stop_processes      : unit
    method virtual continue_processes  : unit
    method virtual terminate_processes : unit
    (* --- *)
    method get_hublet_no              : int
    method get_hublet_process_list    : hublet_process list
    method get_hublet_process_of_port : int -> hublet_process
    (* --- *)
    method startup             : unit
    method suspend             : unit
    method resume              : unit
    method shutdown            : unit
    method destroy             : unit
    method gracefully_shutdown : unit
    (* --- *)
    method gracefully_terminate_processes : unit
    method execute_the_unexpected_death_callback : int -> string -> unit
  end

class virtual ['parent] main_process_with_n_hublets_and_cables_and_accessory_processes :
  parent:'parent ->
  hublet_no:int ->
  ?last_user_visible_port_index:int ->
  working_directory:string ->
  unexpected_death_callback:(unit -> unit) ->
  unit ->
  object
    (* --- *)
    constraint 'parent = <
      get_name : string;
      ports_card : <
	get_my_inward_defects_by_index  : int -> defects_object;
	get_my_outward_defects_by_index : int -> defects_object;
        .. >;
      .. >
    (* --- *)
    inherit ['parent] device
    (* --- *)
    method spawn_internal_cables        : unit
    method get_internal_cable_processes : ethernet_cable_process list
    (* --- *)
    method add_accessory_process : process -> unit
  end

class virtual ['parent] hub_or_switch :
  parent:'parent ->
  hublet_no:int ->
  ?last_user_visible_port_index:int ->
  hub:bool ->
  ?management_socket:unit ->
  ?fstp:unit ->
  ?rcfile:string ->
  working_directory:string ->
  unexpected_death_callback:(unit -> unit) ->
  unit ->
  object
    (* --- *)
    inherit ['parent] main_process_with_n_hublets_and_cables_and_accessory_processes
    (* --- *)
    method virtual device_type : string
    (* --- *)
    method spawn_processes     : unit
    method stop_processes      : unit
    method continue_processes  : unit
    method terminate_processes : unit
    (* --- *)
    method get_management_socket_name   : string option
    (* --- *)
  end


class virtual ['parent] machine_or_router :
  parent:'parent ->
  router:bool ->
  kernel_file_name:process_name ->
  ?kernel_console_arguments:string ->
  ?filesystem_relay_script:string ->
  ?rcfile_content:string ->
  filesystem_file_name:string ->
  get_the_cow_file_name_source:(unit -> string option) ->
  cow_file_name:string ->
  states_directory:string ->
  hostfs_directory:string ->
  ethernet_interface_no:int ->
  memory:int ->
  console_no:int ->
  console:string ->
  xnest:bool ->
  ?umid:string ->
  id:int ->
  ?show_unix_terminal:bool ->
  working_directory:string ->
  unexpected_death_callback:(unit -> unit) ->
  unit ->
  object
    (* --- *)
    constraint 'parent = <
      get_name : string;
      ports_card : <
	get_my_inward_defects_by_index  : int -> defects_object;
	get_my_outward_defects_by_index : int -> defects_object;
        .. >;
      .. >
    (* --- *)
    inherit ['parent] device
    (* --- *)
    method virtual device_type : string
    (* --- *)
    method spawn_processes     : unit
    method stop_processes      : unit
    method continue_processes  : unit
    method terminate_processes : unit
    (* --- *)
    method ip_address_eth42 : string
  end

class virtual ['parent] machine_or_router_with_accessory_processes :
  parent:'parent ->
  router:bool ->
  kernel_file_name:process_name ->
  ?kernel_console_arguments:string ->
  ?filesystem_relay_script:string ->
  ?rcfile_content:string ->
  filesystem_file_name:string ->
  get_the_cow_file_name_source:(unit -> string option) ->
  cow_file_name:string ->
  states_directory:string ->
  hostfs_directory:string ->
  ethernet_interface_no:int ->
  memory:int ->
  console_no:int ->
  console:string ->
  xnest:bool ->
  ?umid:string ->
  id:int ->
  ?show_unix_terminal:bool ->
  working_directory:string ->
  unexpected_death_callback:(unit -> unit) ->
  unit ->
  object
    inherit ['parent] machine_or_router
    (* --- *)
    method add_accessory_process : process -> unit
  end
