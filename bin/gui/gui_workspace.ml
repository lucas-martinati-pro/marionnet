(* This file is part of Marionnet, GPL-2.0-or-later.
   Copyright (C) 2026 Marionnet contributors. *)

module Cortex = Ocamlbricks.Cortex
module StackExtra = Ocamlbricks.StackExtra
open Gettext

module Make
  (State : sig val st : State.globalState end)
  (Actions : sig
    val new_project : unit -> unit
    val open_project : unit -> unit
    val save_project : unit -> unit
  end) = struct
  let st = State.st
  let w = st#mainwin

  let bar = GPack.hbox ~spacing:8 ~border_width:10 ~show:true ()
  let () =
    let width = min 1024 (max 640 (Gdk.Screen.width () - 48)) in
    let height = min 680 (max 480 (Gdk.Screen.height () - 80)) in
    w#window_MARIONNET#set_default_size ~width ~height;
    (* The Glade window is already visible. Apply its initial size once the
       remaining palette and treeviews have been installed, before user gestures. *)
    ignore (GMain.Idle.add (fun () -> w#window_MARIONNET#resize ~width ~height; false));
    w#vbox1#pack ~expand:false ~fill:true bar#coerce;
    w#vbox1#reorder_child bar#coerce ~pos:1

  let button label icon shortcut callback =
    let b = GButton.button ~label ~packing:(bar#pack ~expand:false) ~show:true () in
    let image = GMisc.image ~icon_name:icon ~icon_size:`SMALL_TOOLBAR ~show:true () in
    b#set_image image#coerce;
    GtkBase.Widget.Tooltip.set_text b#as_widget (label ^ " (" ^ shortcut ^ ")");
    ignore (b#connect#clicked ~callback);
    b

  let new_button = button (s_ "New") "document-new-symbolic" "Ctrl+N" Actions.new_project
  let open_button = button (s_ "Open") "document-open-symbolic" "Ctrl+O" Actions.open_project
  let save_button = button (s_ "Save") "document-save-symbolic" "Ctrl+S" Actions.save_project
  let () = StackExtra.push save_button#coerce st#sensitive_when_Saveable

  let project_box = GPack.vbox ~spacing:2 ~packing:(bar#pack ~expand:true) ~show:true ()
  let project_name = GMisc.label ~xalign:1. ~ellipsize:`MIDDLE
    ~packing:project_box#add ~show:true ()
  let project_status = GMisc.label ~xalign:1. ~ellipsize:`END
    ~packing:project_box#add ~show:true ()

  (* A useful empty state replaces the broken-image glyph shown by set_file "". *)
  let canvas = GPack.vbox ~spacing:16 ~border_width:20 ~show:true ()
  let () =
    w#viewport1#remove w#sketch#coerce;
    w#viewport1#add canvas#coerce
  let empty_box = GPack.vbox ~spacing:12
    ~packing:(canvas#pack ~expand:true ~fill:false) ~show:true ()
  let empty_title = GMisc.label ~packing:empty_box#add ~show:true ()
  let empty_help = GMisc.label ~line_wrap:true ~justify:`CENTER
    ~packing:empty_box#add ~show:true ()
  let () =
    empty_help#set_max_width_chars 42;
    canvas#pack ~expand:true ~fill:true w#sketch#coerce; w#sketch#clear ()

  let summary = w#statusbar#new_context "workspace"
  let previous_summary = ref ""
  let previous_title = ref ""

  let update () =
    let active = st#active_project in
    let nodes = st#network#get_node_list in
    let cables = st#network#get_cable_list in
    let saved = active && st#project_already_saved in
    let filename = st#project_paths#get_filename in
    let name = match filename with
      | None -> s_ "workspace.no_project"
      | Some path -> Filename.basename path in
    let status = if not active then s_ "workspace.ready"
      else if saved then s_ "workspace.saved" else s_ "workspace.unsaved" in
    project_name#set_text name;
    project_status#set_text status;
    GtkBase.Widget.Tooltip.set_text project_name#as_widget
      (match filename with None -> name | Some path -> path);
    let title = if not active then Initialization.window_title else
      Printf.sprintf "%s - %s%s" Initialization.window_title (if saved then "" else "• ") name in
    if title <> !previous_title then begin
      previous_title := title; w#window_MARIONNET#set_title title
    end;
    let text = if not active then s_ "workspace.shortcuts" else
      Printf.sprintf (f_ "%d nodes · %d cables · %d active")
        (List.length nodes) (List.length cables)
        (List.length (List.filter (fun n -> n#can_gracefully_shutdown) nodes)) in
    if text <> !previous_summary then begin
      summary#pop (); ignore (summary#push text); previous_summary := text
    end;
    let empty = not active || nodes = [] in
    if empty then begin
      empty_title#set_text (s_ (if active then "workspace.empty_network" else "workspace.welcome"));
      empty_help#set_text (s_ (if active then "workspace.add_hint" else "workspace.open_hint"));
      empty_box#misc#show (); w#sketch#misc#hide ()
    end else begin
      empty_box#misc#hide (); w#sketch#misc#show ()
    end

  (* Coalesce notifications instead of polling and traversing every treeview
     on each tick. Every widget mutation happens on the GTK main thread. *)
  let update_pending = ref false
  let request_update () =
    GMain_actor.delegate ~async:() (fun () ->
      if not !update_pending then begin
        update_pending := true;
        ignore (GMain.Idle.add (fun () -> update_pending := false; update (); false))
      end) ()

  let () =
    ignore (Cortex.on_commit_append st#project_paths#filename (fun _ _ -> request_update ()));
    ignore (Cortex.on_commit_append st#project_status_counter (fun _ _ -> request_update ()));
    ignore (Cortex.on_commit_append st#refresh_sketch_counter (fun _ _ -> request_update ()));
    request_update ()

  let () =
    try
      let provider = GObj.css_provider () in
      provider#load_from_data "box { border-bottom: 1px solid alpha(@theme_fg_color, 0.12); }";
      bar#misc#style_context#add_provider provider 600;
      let title_style = GObj.css_provider () in
      title_style#load_from_data "label { font-size: 18px; font-weight: bold; }";
      empty_title#misc#style_context#add_provider title_style 600;
      let muted = GObj.css_provider () in
      muted#load_from_data "label { color: alpha(@theme_fg_color, 0.65); }";
      empty_help#misc#style_context#add_provider muted 600;
      project_status#misc#style_context#add_provider muted 600
    with e -> Marionnet_log.printf1 "Cannot style workspace: %s\n" (Printexc.to_string e)
end
