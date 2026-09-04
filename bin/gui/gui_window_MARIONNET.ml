(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2009, 2010  Jean-Vincent Loddo
   Copyright (C) 2009  Luca Saiu
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


module Log = Marionnet_log

open Gettext;;

(** Gui completion for the widget window_MARIONNET (main window) defined with glade. *)

module Make (State : sig val st:State.globalState end) = struct

open State
let w = st#mainwin

(* Labels in main window *)
let () = begin
 w#label_VIRTUAL_NETWORK#set_label (s_ "Virtual network");
 w#label_TAB_DOCUMENTS#set_label   (s_ "Project documents")
end

(* ***************************************** *
             Gui motherboard
 * ***************************************** *)

module Motherboard = Motherboard_builder. Make (State)


(* ***************************************** *
         MENUS Project, Options, ...
 * ***************************************** *)

module Created_menubar_MARIONNET = Gui_menubar_MARIONNET.Make (State)


(* ***************************************** *
             notebook_CENTRAL
 * ***************************************** *)

(* Tool -> ocamlbricks widget.ml ? *)
let get_tab_labels_of notebook =
  let mill widget = (GMisc.label_cast (notebook#get_tab_label widget)) in
  List.map mill notebook#children

let tuple2_of_list = function [l1;l2]       -> (l1,l2)       | _ -> assert false
let tuple4_of_list = function [l1;l2;l3;l4] -> (l1,l2,l3,l4) | _ -> assert false

let () = begin
 let labels = get_tab_labels_of w#notebook_CENTRAL in
 let (l1,l2) = tuple2_of_list labels in
 List.iter (fun l -> l#set_use_markup true) labels ;
 l1#set_label (s_ "<i>Components</i>");
 l2#set_label (s_ "<i>Documents</i>");
end

(* ***************************************** *
             notebook_INTERNAL
 * ***************************************** *)

let () = begin
 let labels = get_tab_labels_of w#notebook_INTERNAL in
 let (l1,l2,l3,l4) = tuple4_of_list labels in
 List.iter (fun l -> l#set_use_markup true) labels ;
 let set l text = l#set_label ("<i>"^text^"</i>") in
 set l1 (s_ "Image")       ;
 set l2 (s_ "Interfaces")  ;
 set l3 (s_ "Defects")     ;
 set l4 (s_ "Disks")       ;
end

(* ***************************************** *
             toolbar_DOT_TUNING
 * ***************************************** *)

module Created_toolbar_DOT_TUNING = Gui_toolbar_DOT_TUNING. Make (State)

(* ***************************************** *
                BASE BUTTONS
 * ***************************************** *)

let () = begin
    w#hbox_BASE#set_homogeneous true;
    w#hbox_BASE#set_spacing 5;
    w#hbox_BASE#set_border_width 0;
  end

let button_BASE_STARTUP_EVERYTHING =
  Gui_bricks.button_image ~label:(s_ "Start all") ~stock:`MEDIA_PLAY
    ~tooltip:(s_ "Start the virtual network (machines, switch, hub, etc) locally on this machine")
    ~label_position:`BOTTOM ~stock_size:`LARGE_TOOLBAR ~packing:w#hbox_BASE#add ()

let (menu_BASE_PAUSE_SOMETHING, button_BASE_PAUSE_SOMETHING, box_BASE_PAUSE_SOMETHING) =
  let renewer =
    let get_label_active_callback_list () =
      let name_kind_suspended_list : (string * [`Node|`Cable] * bool) list =
        st#network#get_component_names_that_can_suspend_or_resume ()
      in
      List.map
        (fun (name, kind, suspended) ->
           let callback b =
             if b = suspended then () else
             match suspended with
             | true  -> (st#network#get_component_by_name ~kind name)#resume
             | false -> (st#network#get_component_by_name ~kind name)#suspend
           in
           (name, suspended, callback)
        )
        name_kind_suspended_list
    in
    Gui_bricks.make_check_items_renewer_v1 ~get_label_active_callback_list ()
    (* end of renewer () *)
  in
  Gui_bricks.button_image_popuping_a_menu ~label:(s_ "Suspend") ~stock:`MEDIA_PAUSE
    ~renewer
    ~tooltip:(s_ "Suspend the activity of a network component")
    ~label_position:`BOTTOM ~stock_size:`LARGE_TOOLBAR ~packing:w#hbox_BASE#add ()

let button_BASE_SHUTDOWN_EVERYTHING =
  Gui_bricks.button_image ~label:(s_ "Shutdown all") ~stock:`MEDIA_STOP
    ~tooltip:(s_ "Gracefully stop every element of the network")
    ~label_position:`BOTTOM ~stock_size:`LARGE_TOOLBAR ~packing:w#hbox_BASE#add ()

(* Exam locks (journalisation-profonde, episode 22). This button sits right next to "Shutdown
   all" and does the opposite of what an exam needs: the session is archived — report, command
   history, console, terminal into the [documents] treeview, hence into the .mar handed in — by
   the *graceful* shutdown only (machine.ml, router.ml). A power cut therefore throws the copy
   away, in one click, next to the right one. In exam mode the button is made insensitive and
   says why: it is disabled rather than hidden so that a student who looks for it understands
   that the tool refuses, instead of believing the interface has changed. *)
let button_BASE_POWEROFF_EVERYTHING =
  let allowed = Initialization.are_we_allowed_to_poweroff in
  let tooltip =
    if allowed
    then (s_ "(Ungracefully) shutdown every element of the network, as in a power-off")
    (* One physical line, deliberately: a `\' continuation inside a translatable string is a trap.
       OCaml strips the newline and the leading blanks, the POT extractor does not — the catalogue
       would then hold a msgid nothing ever looks up, and the string would stay in English in the
       twelve languages, silently. *)
    else (s_ "Disabled in exam mode: a power cut would throw the exam copy away. Use \"Shutdown all\".")
  in
  let button =
    Gui_bricks.button_image ~label:(s_ "Power-off all")
      ~file:"ico.poweroff.24x24.png"
      ~tooltip
      ~label_position:`BOTTOM ~packing:w#hbox_BASE#add ()
  in
  let () = if not allowed then button#misc#set_sensitive false in
  button

(* Just a thunk, the button is not really built. We leave this code
   in order to not remove the gettext key associated to this `tooltip'
   and this `label': *)
let button_BASE_BROADCAST () =
  Gui_bricks.button_image ~label:(s_ "Broadcast")
    ~tooltip:(s_ "Broadcast the specification of the virtual network on a real network")
    ~file:"ico.diffuser.orig.png"
    ~label_position:`BOTTOM ~packing:w#hbox_BASE#add ()

(* Connections *)
let () =

  let _ = button_BASE_STARTUP_EVERYTHING#connect#clicked ~callback:(fun () -> st#startup_everything ()) in

  let _ = button_BASE_SHUTDOWN_EVERYTHING#connect#clicked
    ~callback:(fun () ->
      (* ~script_answer: were this callback ever reached while the control server serves a
         command, the intent would not be ambiguous — the caller asked for the shutdown. It
         is not reachable that way today (the server calls the model, never a GUI callback),
         so this is a net, not a feature. *)
      match Simple_dialogs.confirm_dialog
          ~question:(s_ "Are you sure that you want to stop\nall the running components?")
          ~script_answer:true
          () with
        Some true  -> st#shutdown_everything ()
      | Some false -> ()
      | None -> ()) in

  let _ = button_BASE_POWEROFF_EVERYTHING#connect#clicked
    ~callback:(fun () ->
      match Simple_dialogs.confirm_dialog
          ~question:(s_ "Are you sure that you want to power off\nall the running components? It is also possible to shut them down graciously...")
          ~script_answer:true
          () with
        Some true -> st#poweroff_everything ()
      | Some false -> ()
      | None -> () ) in

  let _ =
    let callback = (fun _ -> Created_menubar_MARIONNET.Created_entry_project_quit.callback (); true) in
    w#toplevel#event#connect#delete ~callback

  in ()

(* ***************************************** *
     The height the components palette needs
 * ***************************************** *)

(* The window used to open at a height written by hand in the glade file (860, after 840
   before it). No constant can be right: what the palette needs depends on the theme and on
   the icon size of the machine that runs Marionnet. Measured on a bare ubuntu:24.04, the
   eighth icon of the palette (the planet) was cut below 780, while 860 left 80 px of empty
   space under it -- the constant was at once too tall here and too short elsewhere, which is
   what already made it grow from 840 to 860 once.
   Two things had to be understood, and only the measurement gave them:
   (1) the palette does not scroll when it is too short, it OVERFLOWS. A GtkToolbar hands the
       items that do not fit to an arrow menu, so its minimum height stays small and it never
       asks its GtkScrolledWindow for anything -- which is why the window opened at 583 with
       the last icons gone, why `propagate-natural-height' on that scrolled window changed
       nothing, and why the height had to be guessed in the first place. That overflow menu
       buys nothing here anyway: measured, no arrow is ever drawn and the hidden components
       are simply out of reach. Hence `show-arrow' is False in the glade file;
   (2) the toolbar being then unable to shrink, the GtkViewport allocates it the height it
       asks for: its allocation IS what the palette demands, and the scrolled window's
       allocation is what it was given. The difference is what the window is short of.
   Measured on ubuntu:24.04, 1920x1080: demanded 623, granted 428, window 583 -> 778, the
   whole palette visible with no empty space; on a 1024x600 screen the window stops at 600.
   Residual defect, pre-existing and not introduced here: on a screen shorter than the
   palette, the last components stay out of reach (docs/TODO.md). *)
let () =
  let attempts = ref 0 in
  let adjust_height_to_palette () =
    let window   = w#window_MARIONNET in
    let demanded = w#toolbar_COMPONENTS#misc#allocated_height in
    let granted  = w#scrolledwindow2#misc#allocated_height in
    let current  = window#misc#allocated_height in
    (* A widget that is not allocated yet answers 1: measuring then would shrink the window
       instead of growing it. Try again -- the window may not be mapped yet. *)
    if demanded <= 1 || granted <= 1 || current <= 1 then false else
    let screen  = Gdk.Screen.height () in
    let missing = demanded - granted in
    let wanted  = min (current + missing) screen in
    let () =
      Log.printf4
        "Main window: the palette demands %d px and got %d px; the window is %d px high (screen %d)\n"
        demanded granted current screen
    in
    let () =
      if missing > 0 && wanted > current then begin
        Log.printf2
          "Main window: growing from %d to %d px, so that the whole palette is visible\n"
          current wanted;
        window#resize ~width:(window#misc#allocated_width) ~height:wanted
        end
    in
    true
  in
  let _ =
    GMain.Timeout.add ~ms:400
      ~callback:(fun () ->
         incr attempts;
         if adjust_height_to_palette ()
         then false                 (* done, once *)
         else !attempts < 25        (* ten seconds, then give up quietly *))
  in
  ()

end
