(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2009, 2010  Jean-Vincent Loddo
   Copyright (C) 2009, 2010  Université Paris 13

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


#load "include_type_definitions_p4.cmo"
;;
INCLUDE DEFINITIONS "../../../../bin/motherboard_builder.mli";;

(* --- *)
module Log = Marionnet_log
module StackExtra = Ocamlbricks.StackExtra
module Thunk = Ocamlbricks.Thunk
module Cortex = Ocamlbricks.Cortex
(* --- *)
(* open Gettext;; *)

(* --- *)
module Make (S : sig val st:State.globalState end) = struct

 (*open S*)
 let w = S.st#mainwin

  (* ----------------------------------------
              Reactive window title
     ---------------------------------------- *)

  (* Reactive setting: S.st#project_filename -> w#window_MARIONNET#title *)
  let update_main_window_title : Thunk.id =
    Cortex.on_commit_append
      (S.st#project_paths#filename)
      (fun _ filename ->      (* previous and commited state *)
         let title = match filename with
         | None          ->  Initialization.window_title
         | Some filename ->  Printf.sprintf "%s - %s" (Initialization.window_title) (filename)
         in
         w#window_MARIONNET#set_title (title)
         )

  (* ----------------------------------------
            Reactive sensitiveness
     ---------------------------------------- *)

  (* --- *)
  let set_sensitive_with_opacity x = begin
    (x#misc#set_sensitive true);
    (x#coerce#set_opacity 1.);
    end
  (* --- *)
  let unset_sensitive_with_opacity x = begin
    (x#misc#set_sensitive false);
    (x#coerce#set_opacity 0.5);
    end
  (* --- *)
  let conditional_sensitive_with_opacity (cond) =
    if cond then set_sensitive_with_opacity else unset_sensitive_with_opacity
  (* --- *)

  (* Note: why the GC doesn't free this structure (and the related trigger)? *)
  let update_project_state_sensitiveness =
    (* --- *)
    Cortex.group_pair
      ~on_commit:(fun (_,_) (filename, nodes) -> (* previous and commited state *)
        GMain_actor.delegate (fun () -> begin
        (* Convenient aliases: *)
        let wa = (S.st#sensitive_when_Active) in
        let wr = (S.st#sensitive_when_Runnable) in
        let wn = (S.st#sensitive_when_NoActive) in
        (* --- *)
        let active   = (filename <> None) in
        let runnable = active && (not (Queue.is_empty nodes)) in
        let () =
          Log.printf2 "Motherboard_builder: update_project_state_sensitiveness: state project is: active=%b runnable=%b\n"
            (active) (runnable)
        in
        match active, runnable with
        | false, _ ->
            StackExtra.iter (unset_sensitive_with_opacity) (wa);
            StackExtra.iter (unset_sensitive_with_opacity) (wr);
            StackExtra.iter (set_sensitive_with_opacity)   (wn);
            (* --- *)
        | true, false ->
            StackExtra.iter (set_sensitive_with_opacity)   (wa);
            StackExtra.iter (unset_sensitive_with_opacity) (wr);
            StackExtra.iter (unset_sensitive_with_opacity) (wn);
            (* --- *)
        | true, true ->
            StackExtra.iter (set_sensitive_with_opacity)   (wa);
            StackExtra.iter (set_sensitive_with_opacity)   (wr);
            StackExtra.iter (unset_sensitive_with_opacity) (wn);
        (* --- *)
        end) ()
        ) (* end of ~on_commit *)
      (* --- *)
      (S.st#project_paths#filename)  (*  first member of the group *)
      (S.st#network#nodes)           (* second member of the group *)


  (* Reactive setting: S.st#network#nodes -> cable's menu sensitiveness.
     Forbid cable additions if there are not enough free ports; explicitly enable
     them if free ports are enough: *)
  let update_cable_menu_entries_sensitiveness : unit =
    (* The previous and commited state are ignored.
       This kind of code (on_commit) is outside a critical section,
       so we can comfortably re-call S.st#network methods: *)
    let reaction _ _ =
      GMain_actor.delegate (fun () -> begin
         let () = Log.printf1 "Motherboard_builder: update_cable_menu_entries_sensitiveness: updating %d widgets\n"
           (StackExtra.length S.st#sensitive_cable_menu_entries)
         in
         let condition = S.st#network#are_there_almost_2_free_endpoints in
         (*(StackExtra.iter (fun x->x#misc#set_sensitive condition) S.st#sensitive_cable_menu_entries)*)
         (StackExtra.iter (fun x->conditional_sensitive_with_opacity condition x) S.st#sensitive_cable_menu_entries)
         end) ()
    in
    let _ = Cortex.on_commit_append (S.st#network#nodes)  (reaction) in
    let _ = Cortex.on_commit_append (S.st#network#cables) (reaction) in
    ()

  (* Called in marionnet.ml before entering the main loop: *)
  let sensitive_widgets_initializer () =
    GMain_actor.delegate (fun () -> begin
      let () = StackExtra.iter (unset_sensitive_with_opacity) (S.st#sensitive_when_Active)   in
      let () = StackExtra.iter (unset_sensitive_with_opacity) (S.st#sensitive_when_Runnable) in
      let () = StackExtra.iter (set_sensitive_with_opacity)   (S.st#sensitive_when_NoActive) in
      (* --- *)
      let () = StackExtra.iter (unset_sensitive_with_opacity) (S.st#sensitive_cable_menu_entries) in
      ()
    end) ()

  (* ----------------------------------------
               Reactive sketch
     ---------------------------------------- *)

  (* --- *)
  let () =
   let d = S.st#network#dotoptions in
   let update = (fun _ _ -> S.st#refresh_sketch) in
   let _ = Cortex.on_commit_append (d#iconsize)      (update) in
   let _ = Cortex.on_commit_append (d#rankdir)       (update) in
   let _ = Cortex.on_commit_append (d#curved_lines)  (update) in
   let _ = Cortex.on_commit_append (d#shuffler)      (update) in
   let _ = Cortex.on_commit_append (d#nodesep)       (update) in
   let _ = Cortex.on_commit_append (d#labeldistance) (update) in
   let _ = Cortex.on_commit_append (d#extrasize)     (update) in
   ()

  (* ----------------------------------------
                  Debugging
     ---------------------------------------- *)

  (* Debugging: press F5 for immediately exiting the gtk main loop (only in the toplevel) *)
  let _ =
    if !Sys.interactive then
      let stars = "*************************************" in
      Printf.kfprintf flush stdout
        "%s\nPress F5 to switch to the toplevel.\n%s\n\n" stars stars;
      ignore (S.st#mainwin#toplevel#event#connect#key_press ~callback:(fun k ->
         (match (GdkEvent.Key.keyval k) = GdkKeysyms._F5 with
         | true ->
             Printf.kfprintf flush stdout
               "%s\nYou are now in the toplevel.\nType:\nGMain.Main.main ();;\nto come back to the Marionnet window.\n%s\n\n" stars stars;
             GtkMain.Main.quit ()
         | false -> ()
         );
         false))
    else ()

end
