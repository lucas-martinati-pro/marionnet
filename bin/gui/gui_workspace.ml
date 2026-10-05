(* This file is part of Marionnet, GPL-2.0-or-later.
   Copyright (C) 2026 Marionnet contributors. *)

module Cortex = Ocamlbricks.Cortex
open Gettext

module Make (State : sig val st : State.globalState end) = struct
  let st = State.st
  let w = st#mainwin

  let bar = w#box_WORKSPACE_ACTIONS
  let () =
    let width = min 1024 (max 640 (Gdk.Screen.width () - 48)) in
    let height = min 680 (max 480 (Gdk.Screen.height () - 80)) in
    w#window_MARIONNET#set_default_size ~width ~height;
    (* The Glade window is already visible. Apply its initial size once the
       remaining palette and treeviews have been installed, before user gestures. *)
    ignore (GMain.Idle.add (fun () -> w#window_MARIONNET#resize ~width ~height; false));
    w#vbox1#remove w#menubar_MARIONNET#coerce;
    bar#pack ~expand:false w#menubar_MARIONNET#coerce

  let project_name = w#label_WORKSPACE_TITLE
  let () =
    let toggle = w#toggle_COMPONENT_LABELS in
    w#hbox_COMPONENTS#reorder_child toggle#coerce ~pos:0;
    let update_labels () =
      Marionnet_log.printf1 "Palette labels visible: %b\n" toggle#active;
      Gui_toolbar_COMPONENTS_layouts.Toolbar.set_labels_visible w#toolbar_COMPONENTS toggle#active;
      GtkBase.Widget.Tooltip.set_text toggle#as_widget
        (s_ (if toggle#active then "workspace.hide_component_labels"
             else "workspace.show_component_labels"))
    in
    ignore (toggle#connect#toggled ~callback:update_labels);
    update_labels ()

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
    w#sketch#clear ()
  module Drawing = Gui_network_canvas.Make (State) (struct let canvas = canvas end)

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
      | None -> Initialization.window_title
      | Some path -> Filename.basename path in
    let marker = if active && not saved then "• " else "" in
    let visible_name = if active && Initialization.are_we_in_exam_mode then
      Initialization.window_title ^ " - " ^ name else name in
    project_name#set_text (marker ^ visible_name);
    GtkBase.Widget.Tooltip.set_text project_name#as_widget
      (match filename with None -> name | Some path ->
        path ^ "\n" ^ s_ (if saved then "workspace.saved" else "workspace.unsaved"));
    let title = if not active then Initialization.window_title else
      Printf.sprintf "%s%s - %s" marker Initialization.window_title name in
    if title <> !previous_title then begin
      previous_title := title; w#window_MARIONNET#set_title title
    end;
    let text = if not active then s_ "workspace.shortcuts" else
      Printf.sprintf (f_key "message.nodes_cables_active" "%d nodes · %d cables · %d active")
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
      provider#load_from_data "menubar { background: transparent; box-shadow: none; border: none; }";
      w#menubar_MARIONNET#misc#style_context#add_provider provider 600;
      let title_style = GObj.css_provider () in
      title_style#load_from_data "label { font-size: 18px; font-weight: bold; }";
      empty_title#misc#style_context#add_provider title_style 600;
      let muted = GObj.css_provider () in
      muted#load_from_data "label { color: alpha(@theme_fg_color, 0.65); }";
      empty_help#misc#style_context#add_provider muted 600
    with e -> Marionnet_log.printf1 "Cannot style workspace: %s\n" (Printexc.to_string e)
end
