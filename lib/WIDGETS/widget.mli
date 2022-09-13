(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Jean-Vincent Loddo

   Trivial change in 2008 by Luca Saiu

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

(** Some generic tools for building GUIs *)

module Image :
  sig
    val scaleTo        : int * int -> GdkPixbuf.pixbuf -> GdkPixbuf.pixbuf
    val zoom           : float -> GdkPixbuf.pixbuf -> GdkPixbuf.pixbuf
    val inch_of_pixels : ?ppi:float -> int -> float
  end

module DynamicSubmenu :
  sig
    val make :
      ?set_active:(string -> bool) ->
      submenu:GMenu.menu ->
(*       menu:GMenu.image_menu_item -> *)
      menu:GMenu.menu_item ->
      dynList:(unit -> string list) ->
      action:(string -> unit -> unit) ->
      unit -> unit
  end

module ComboTextTree :
  sig

    class comboTextTree :
      generator:(string Environments.string_env -> string list) ->
      msg:string Environments.string_env ->
      key:string ->
      callback:(string -> unit) option ->
      packing:(GObj.widget -> unit) option ->
      object
        method add_child : comboTextTree -> unit
        method box : GEdit.combo_box
        method callback : string -> unit
        method changedAndGetActive : (string -> unit) -> unit
        method child : int -> comboTextTree
        method children : comboTextTree list
        method children_rebuild : unit -> unit
        method choices : string list
        method col : string GTree.column
        method env : string Environments.string_env
        method generator : string Environments.string_env -> string list
        method initialize_callbacks : unit
        method key : string
        method packing : GObj.widget -> unit
        method rebuild : string Environments.string_env -> unit
        method selected : string
        method set_active_value : string -> unit
        method set_box : GEdit.combo_box -> unit
        method set_children : comboTextTree list -> unit
        method set_choices : string list -> unit
        method set_col : string GTree.column -> unit
        method set_env : string Environments.string_env -> unit
        method slave : comboTextTree
        method slave0 : comboTextTree
        method slave1 : comboTextTree
        method slave2 : comboTextTree
        method slave3 : comboTextTree
        method slave4 : comboTextTree
        method slave5 : comboTextTree
      end

    type choice = string
    type choices = choice list

    val make :
      generator:(choice Environments.string_env -> choice list) ->
      msg:choice Environments.string_env ->
      key:string ->
      callback:(choice -> unit) option ->
      packing:(GObj.widget -> unit) option -> comboTextTree

    val fromList :
      ?key:string ->
      ?callback:(choice -> unit) option ->
      ?packing:(GObj.widget -> unit) option -> choices -> comboTextTree

    val fromListWithSlave :
      ?masterCallback:(choice -> unit) option ->
      ?masterPacking:(GObj.widget -> unit) option ->
      choices ->
      ?slaveCallback:(choice -> unit) option ->
      ?slavePacking:(GObj.widget -> unit) option ->
      (choice -> choices) -> comboTextTree

    val fromListWithSlaveWithSlave :
      ?masterCallback:(choice -> unit) option ->
      ?masterPacking:(GObj.widget -> unit) option ->
      choices ->
      ?slaveCallback:(choice -> unit) option ->
      ?slavePacking:(GObj.widget -> unit) option ->
      (choice -> choices) ->
      ?slaveSlaveCallback:(choice -> unit) option ->
      ?slaveSlavePacking:(GObj.widget -> unit) option ->
      (choice -> choice -> choices) -> comboTextTree

    val fromListWithSlaveWithSlaveWithSlave :
      ?masterCallback:(choice -> unit) option ->
      ?masterPacking:(GObj.widget -> unit) option ->
      choices ->
      ?slaveCallback:(choice -> unit) option ->
      ?slavePacking:(GObj.widget -> unit) option ->
      (choice -> choices) ->
      ?slaveSlaveCallback:(choice -> unit) option ->
      ?slaveSlavePacking:(GObj.widget -> unit) option ->
      (choice -> choice -> choices) ->
      ?slaveSlaveSlaveCallback:(choice -> unit) option ->
      ?slaveSlaveSlavePacking:(GObj.widget -> unit) option ->
      (choice -> choice -> choice -> choices) -> comboTextTree

    val fromListWithTwoSlaves :
      ?masterCallback:(choice -> unit) option ->
      ?masterPacking:(GObj.widget -> unit) option ->
      choices ->
      ?slave0Callback:(choice -> unit) option ->
      ?slave0Packing:(GObj.widget -> unit) option ->
      (choice -> choices) ->
      ?slave1Callback:(choice -> unit) option ->
      ?slave1Packing:(GObj.widget -> unit) option ->
      (choice -> choices) -> comboTextTree

    val fromListWithThreeSlaves :
      ?masterCallback:(choice -> unit) option ->
      ?masterPacking:(GObj.widget -> unit) option ->
      choices ->
      ?slave0Callback:(choice -> unit) option ->
      ?slave0Packing:(GObj.widget -> unit) option ->
      (choice -> choices) ->
      ?slave1Callback:(choice -> unit) option ->
      ?slave1Packing:(GObj.widget -> unit) option ->
      (choice -> choices) ->
      ?slave2Callback:(choice -> unit) option ->
      ?slave2Packing:(GObj.widget -> unit) option ->
      (choice -> choices) -> comboTextTree
  end

class textview :
  ?view:GText.view ->
  unit ->
  object
    method append : ?tags:string list -> string -> unit
    method append_image : ?scale:(int * int) option -> string -> unit
    (* method private create_tags : unit -> unit *)
    method delete : unit -> unit
    method refresh : unit -> unit
    method rewrite : ?tags:string list -> string -> unit
    method view : GText.view
  end
