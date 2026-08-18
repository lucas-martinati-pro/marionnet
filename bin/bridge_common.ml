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


(** What the two bridge components have in common (work-stream
    [modernisation-world-bridge], episode 7a.3).

    A bridge component is a network node whose simulated device is a vde switch
    having a host tun/tap on its first port and the component's hublets on the
    others (a single one, for the LAN bridge; as many as the user asked for, for
    the NAT bridge since episode 10b). That mechanism is the same whether the
    tap is attached to a bridge built by an administrator (the LAN bridge, the
    historical [world_bridge]) or to the private NAT bridge Marionnet builds for
    itself ([Nat_bridge_host]). The one thing that differs is {b which bridge},
    and that is a function this trunk receives rather than a mode it inspects.

    What is deliberately {e not} here: the [Make_menus] skeleton and the dialogs.
    Every component of this program repeats them, and none of the words of the
    two bridges are the same — a functor taking a dozen strings would align text
    that has no reason to be aligned. *)

(* --- *)
module Log = Marionnet_log
module Option = Ocamlbricks.Option
module OoExtra = Ocamlbricks.OoExtra
module Forest = Ocamlbricks.Forest
module Xforest = Ocamlbricks.Xforest
(* --- *)

(* What a bridge has when it says nothing: exactly one port, named as an interface
   ("eth0"). That is the LAN bridge, and it was both bridges until episode 10b; the
   NAT bridge now says otherwise (a switch with N ports, named "port1"..."portN"). *)
module Const = struct
 let port_no_default = 1
 let port_no_min = 1
 let port_no_max = 1
 (* --- *)
 let port_prefix = "eth"
 let user_port_offset = 0
end

(* The type of data exchanged with the dialogs (the same for both natures): *)
module Data = struct
type t = {
  name        : string;
  label       : string;
  old_name    : string;
  }

let to_string _t = "<obj>" (* TODO? *)
end (* Data *)


module User_level_bridge = struct

(** The user-level part shared by the two bridges. It is virtual because the
    simulated device is precisely what tells them apart: each component defines
    its own [make_simulated_device].
    ---
    [kind_name] is the single name from which the identity of the nature is
    derived: the root of its subtree in the project file and the [device_type] of
    its defects row. It is {e not} a label: it is written into the [.mar] files,
    so it must never change once a project has been saved with it.
    ---
    [icon_prefix] is the only part of that identity a component may name apart
    ([ico.<icon_prefix>.<state>.<size>.png]), and there is one reason to: the LAN
    bridge answers to [kind_name = "world_bridge"] forever, while its drawing had
    to stop being the one of "the" bridge once a second bridge existed. It
    defaults to [kind_name].
    ---
    The port-related parameters all default to what both bridges were until
    episode 10b — a single port called ["eth0"] — so a nature which does not
    mention them (the LAN bridge) keeps exactly its behaviour of yesterday. *)
class virtual bridge =

 fun ~network
     ~name
     ?label
     ~(devkind : User_level.devkind)
     ~(kind_name : string)
     ?(icon_prefix : string option)
     ?(port_no = Const.port_no_default)
     ?(port_no_min = Const.port_no_min)
     ?(port_no_max = Const.port_no_max)
     ?(port_prefix = Const.port_prefix)
     ?(user_port_offset = Const.user_port_offset)
     () ->
  object (self) inherit OoExtra.destroy_methods ()

  inherit
    User_level.node_with_defects
      ~network
      ~name ?label ~devkind
      ~port_no
      ~port_no_min
      ~port_no_max
      ~user_port_offset
      ~port_prefix
      ()
    as self_as_node_with_defects

  method defects_device_type = kind_name
  method polarity = User_level.MDI_Auto (* Because is not pedagogic anyway. *)
  method string_of_devkind = kind_name

  method dotImg iconsize =
   let imgDir = Initialization.Path.images in
   let icon_prefix = match icon_prefix with Some x -> x | None -> kind_name in
   (imgDir^"ico."^icon_prefix^"."^(self#icon_suffix_of_state)^"."^iconsize^".png")

  (* [port_no] is explicit rather than implicitly 1: a nature whose number of ports is
     fixed passes its own constant (the LAN bridge passes 1), a nature which lets the
     user choose passes what the dialog returned. Calling [update_with] is also what
     destroys the simulated device, hence what makes a modification effective on the
     next start-up. *)
  method update_bridge_with ~name ~label ~port_no =
   self_as_node_with_defects#update_with ~name ~label ~port_no;

  (** What a nature writes into the project file {e beyond} the two attributes
      every bridge has. A method rather than a parameter of this class: what it
      returns is read from the mutable fields of the sub-class, which the
      arguments of an [inherit] clause cannot see. The reader side needs nothing
      here — [eval_forest_attribute] below already ignores what it does not know,
      so a sub-class only has to intercept its own attributes and forward the
      rest. *)
  method extra_tree_attributes : (string * string) list = []

  method to_tree =
   Forest.tree_of_leaf (kind_name, [
     ("name"     ,  self#get_name );
     ("label"    ,  self#get_label);
     ] @ self#extra_tree_attributes)

  method! eval_forest_attribute = function
  | ("name"     , x ) -> self#set_name x
  | ("label"    , x ) -> self#set_label x
  | _ -> () (* Forward-comp. *)

end (* class bridge *)

end (* module User_level_bridge *)


module Simulation_level_bridge = struct

(** The vde process at the heart of a bridge component: a switch whose first port is
    connected to the given host tun/tap interface, and whose [port_no - 1] remaining
    ports receive the hublets of the component.
    ---
    A switch and not a hub (it was a hub while there were only two ports, where the
    distinction is void): what the user is offered is an integrated switch, and the
    Linux bridge on the other side of the tap learns addresses anyway. *)
class bridge_hub_process =
  fun ~(port_no : int)
      ~tap_name
      ~socket_name_prefix
      ~working_directory
      ~unexpected_death_callback
      () ->
object(self)
  inherit Simulation_level.vde_switch_process
      ~port_no
      ~hub:false
      ~tap_name
      ~socket_name_prefix
      ~working_directory
      ~unexpected_death_callback
      ()
      (* as self_as_vde_switch_process *)
end

(** The simulated device shared by the two bridges.
    ---
    [resolve_bridge_name] is called {e at start-up time}, not at initialisation
    time, and this deferral is the whole point: the name of a bridge Marionnet
    builds for itself is only known once it has been built. It is also where a
    component may ask the user for the rights it needs, at the moment they serve.
    ---
    [after_terminate] is called once the tap has been destroyed, and is how a
    component gives back what its bridge holds (the NAT bridge releases its
    instance number there). The LAN bridge has nothing to give back.
    ---
    [hublet_no] is the number of ports the component offers to the virtual network
    (episode 10b). It defaults to 1, which is the LAN bridge and was both bridges. *)
class ['parent] bridge_device =
  fun (* ~id *)
      ~(parent:'parent)
      ~(device_type : string)
      ~(resolve_bridge_name : unit -> string)
      ?(after_terminate : (unit -> unit) = fun () -> ())
      ?(hublet_no : int = Const.port_no_default)
      ~(socket_name_prefix : string)
      ~working_directory
      ~unexpected_death_callback
      () ->
object(self)
  inherit ['parent] Simulation_level.device
      ~parent
      ~hublet_no
      ~working_directory
      ~unexpected_death_callback
      ()
      (* as self_as_device *)

  method device_type = device_type

  val mutable the_hub_process = None
  val mutable the_tap_name = None
  val mutable internal_cable_processes = []

  (** Create the tap with Tap_provider (sudo + iproute2), attached to the
      bridge resolved by the component, and return its name: *)
  method private make_the_tap : string option =
    match the_tap_name with
    | None ->
        let bridge_name = resolve_bridge_name () in
        let tap_name_option =
          (match Tap_provider.make_bridge_tap ~uid:(Unix.getuid ()) ~bridge:bridge_name with
           | Ok tap_name ->
               Some tap_name
           | Error error_message ->
               let () = Log.printf2 "Failed to create a tap on the %s: %s\n" device_type error_message in
               None (* "non-existing-tap" *)
           )
        in
        let () = the_tap_name <- tap_name_option in
        tap_name_option
    (* --- *)
    | Some tap_name ->
        let () = Log.printf2 "A tap for the %s already exists: %s\n" device_type tap_name in
        Some tap_name

  method private destroy_the_tap =
    Option.iter
      (fun tap_name ->
          let () = Tap_provider.destroy_tap tap_name in
          (the_tap_name <- None))
      (the_tap_name)

  (* --- *)
  initializer
    begin
      assert ((List.length self#get_hublet_process_list) = hublet_no);
      (* --- *)
      the_hub_process <- self#make_the_hub_process
    end
  (* --- *)


  method private make_the_hub_process : (bridge_hub_process option) =
    let () =
      if the_hub_process <> None then () else (* continue: *)
      Option.iter
        (fun tap_name ->
          let result =
            new bridge_hub_process
              (* One port for the tap, and one per hublet: *)
              ~port_no:(hublet_no + 1)
              ~tap_name
              ~socket_name_prefix
              ~working_directory
              ~unexpected_death_callback:self#execute_the_unexpected_death_callback
              ()
            in
            the_hub_process <- Some result)
        (* --- *)
        (self#make_the_tap)
    in
    the_hub_process

  method spawn_processes =
   Option.iter
     (* --- *)
     (fun the_hub_process ->
        (* Spawn the hub process, and wait to be sure it's started: *)
        let () = the_hub_process#spawn in
        (* Create the internal cable processes, from each hublet to the switch: *)
        let () =
          internal_cable_processes <-
            List.mapi
              (fun i hublet_process ->
                 Simulation_level.make_ethernet_cable_process
                   ~left_end:the_hub_process
                   ~right_end:hublet_process
                   ~leftward_defects:(parent#ports_card#get_my_inward_defects_by_index i)
                   ~rightward_defects:(parent#ports_card#get_my_outward_defects_by_index i)
                   ~unexpected_death_callback:self#execute_the_unexpected_death_callback
                   ())
              (self#get_hublet_process_list)
        in
        (* WARNING (same reason as Simulation_level.main_process_with_n_hublets_and_cables):
           the cables must be spawned SEQUENTIALLY, in the order of the ports, because
           that order is what maps the vde port numbering onto the Marionnet one. *)
        List.iter (fun cable -> cable#spawn) internal_cable_processes)
     (* --- *)
     self#make_the_hub_process

  method terminate_processes = begin
    let () =
      Log.printf4 "%s %s#terminate_processes:  internal_cable_processes=%s  hub_process=%s\n"
        device_type (parent#name)
        (string_of_int (List.length internal_cable_processes))
        (Option.to_string the_hub_process)
    in
    (* Terminate the internal cable processes and the hub process: *)
    let () =
      Task_runner.do_in_parallel
        ((fun () -> Option.iter (fun obj -> obj#terminate) the_hub_process) ::
         (List.map (fun cable () -> cable#terminate) internal_cable_processes))
    in
    (* Destroy the tap, via Tap_provider: *)
    self#destroy_the_tap;
    (* Give back what the component holds beyond the tap (nothing, for a LAN bridge): *)
    let () = after_terminate () in
    (* Unreference everything: *)
    internal_cable_processes <- [];
    the_hub_process <- None;
    end

  (** As bridges are stateless from the point of view of the user, stop/continue
      aren't distinguishable from terminate/spawn: *)
  method stop_processes = self#terminate_processes
  method continue_processes = self#spawn_processes
end

end (* module Simulation_level_bridge *)
