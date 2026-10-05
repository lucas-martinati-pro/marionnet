(* GPL-2.0-or-later. Select and act on the components actually drawn by Graphviz. *)
module Log = Marionnet_log
module Cortex = Ocamlbricks.Cortex
open Gettext

module Make (State : sig val st : State.globalState end)
    (Canvas : sig val canvas : GPack.box end) = struct
  let st = State.st
  let w = st#mainwin
  let box = GBin.event_box ~show:true
    ~packing:(Canvas.canvas#pack ~expand:true ~fill:true) ()
  let selected : Sketch_hit_map.target option ref = ref None
  let popup : GMenu.menu option ref = ref None
  let base_image : GdkPixbuf.pixbuf option ref = ref None
  let zoom = ref 1.

  let component = function
    | Sketch_hit_map.Node id ->
        Option.map (fun n -> `Node, (n :> User_level.component))
          (List.find_opt (fun n -> n#id = id) st#network#get_node_list)
    | Sketch_hit_map.Cable id ->
        Option.map (fun c -> `Cable, (c :> User_level.component))
          (List.find_opt (fun c -> c#id = id) st#network#get_cable_list)

  let image_origin () =
    match !base_image with
    | None -> 0., 0.
    | Some pixbuf ->
        (float_of_int box#misc#allocated_width -. float_of_int (GdkPixbuf.get_width pixbuf) *. !zoom) /. 2.,
        (float_of_int box#misc#allocated_height -. float_of_int (GdkPixbuf.get_height pixbuf) *. !zoom) /. 2.

  let hit x y =
    let ox, oy = image_origin () in
    match Sketch_hit_map.hit st#sketch_hit_map ~x:((x -. ox) /. !zoom) ~y:((y -. oy) /. !zoom) with
    | Some target when component target <> None -> Some target
    | _ -> None

  let update_selection () =
    let text = match !selected with
      | Some target -> (match component target with
          | Some (_, c) -> c#get_name ^ (if c#get_label = "" then "" else " · " ^ c#get_label)
          | None -> selected := None; s_ "Virtual network")
      | None -> s_ "Virtual network" in
    w#label_VIRTUAL_NETWORK#set_text text;
    box#misc#queue_draw ()

  let select target =
    selected := target;
    box#misc#grab_focus ();
    update_selection ();
    Log.printf1 "Drawing selection: %s\n"
      (match target with Some target -> (match component target with Some (_, c) -> c#get_name | _ -> "none")
       | None -> "none")

  let run target name action =
    match component target with
    | Some (_, c) when c#get_name = name && action.Gui_component_actions.enabled () -> action.Gui_component_actions.run ()
    | _ -> st#flash (s_ "sketch.action_unavailable")

  let perform stock = match !selected with
    | None -> ()
    | Some target -> (match component target with
        | None -> select None
        | Some (kind, c) ->
            match List.find_opt (fun a -> a.Gui_component_actions.stock = stock)
              (Gui_component_actions.actions kind c#get_name) with
            | Some action -> run target c#get_name action
            | None -> ())

  let show_menu ~button ~time target =
    match component target with
    | None -> ()
    | Some (kind, c) ->
        Option.iter (fun menu -> menu#destroy ()) !popup;
        let menu = GMenu.menu () in
        (* GTK derives the popup's transient parent from its attached widget.
           Wayland cannot position an unattached temporary window. *)
        GtkMenu.Menu.attach_to_widget menu#as_menu box#as_widget;
        popup := Some menu;
        let heading = GMenu.menu_item ~label:c#get_name ~packing:menu#append () in
        heading#misc#set_sensitive false;
        ignore (GMenu.separator_item ~packing:menu#append ());
        let actions = Gui_component_actions.actions kind c#get_name in
        List.iteri (fun index action ->
          if index = 2 then ignore (GMenu.separator_item ~packing:menu#append ());
          let item = Menu_factory.Image_menu_item.make
            ~stock:action.Gui_component_actions.stock ~text:action.Gui_component_actions.label () in
          menu#append item;
          item#misc#set_sensitive (action.Gui_component_actions.enabled ());
          ignore (item#connect#activate ~callback:(fun () -> run target c#get_name action))) actions;
        menu#misc#show_all ();
        menu#popup ~button ~time

  let set_zoom value =
    match !base_image with
    | None -> ()
    | Some pixbuf ->
        zoom := max 0.25 (min 3. value);
        let width = max 1 (int_of_float (float_of_int (GdkPixbuf.get_width pixbuf) *. !zoom)) in
        let height = max 1 (int_of_float (float_of_int (GdkPixbuf.get_height pixbuf) *. !zoom)) in
        let scaled = GdkPixbuf.create ~width ~height ~has_alpha:(GdkPixbuf.get_has_alpha pixbuf) () in
        GdkPixbuf.scale pixbuf ~dest:scaled ~width ~height
          ~scale_x:(float_of_int width /. float_of_int (GdkPixbuf.get_width pixbuf))
          ~scale_y:(float_of_int height /. float_of_int (GdkPixbuf.get_height pixbuf)) ~interp:`BILINEAR;
        w#sketch#set_pixbuf scaled;
        box#misc#queue_draw ()

  let () =
    box#add w#sketch#coerce;
    w#sketch#set_xalign 0.5; w#sketch#set_yalign 0.5;
    box#misc#set_can_focus true;
    box#event#add [`BUTTON_PRESS; `POINTER_MOTION; `KEY_PRESS; `SCROLL];
    ignore (w#sketch#misc#connect#show ~callback:(fun () -> box#misc#show ()));
    ignore (w#sketch#misc#connect#hide ~callback:(fun () -> box#misc#hide ()));
    ignore (box#event#connect#button_press ~callback:(fun ev ->
      let target = hit (GdkEvent.Button.x ev) (GdkEvent.Button.y ev) in
      match GdkEvent.Button.button ev, GdkEvent.get_type ev, target with
      | 1, `TWO_BUTTON_PRESS, Some target -> select (Some target); perform `PROPERTIES; true
      | 1, _, _ -> select target; true
      | 3, _, Some target -> select (Some target);
          show_menu ~button:3 ~time:(GdkEvent.Button.time ev) target; true
      | _ -> false));
    ignore (box#event#connect#key_press ~callback:(fun ev ->
      let key = GdkEvent.Key.keyval ev in
      if key = GdkKeysyms._Escape then (select None; true)
      else if key = GdkKeysyms._Return then (perform `PROPERTIES; true)
      else if key = GdkKeysyms._Delete then (perform `REMOVE; true)
      else if key = GdkKeysyms._Menu || (key = GdkKeysyms._F10 &&
        List.mem `SHIFT (GdkEvent.Key.state ev)) then
        (Option.iter (show_menu ~button:0 ~time:(GdkEvent.Key.time ev)) !selected; true)
      else false));
    ignore (box#event#connect#scroll ~callback:(fun ev ->
      if List.mem `CONTROL (Gdk.Convert.modifier (GdkEvent.Scroll.state ev)) then begin
        (match GdkEvent.Scroll.direction ev with
         | `UP -> set_zoom (!zoom *. 1.15)
         | `DOWN -> set_zoom (!zoom /. 1.15)
         | _ -> ()); true
      end else false));
    ignore (box#misc#connect#query_tooltip ~callback:(fun ~x ~y ~kbd tooltip ->
      let target = if kbd then !selected else hit (float_of_int x) (float_of_int y) in
      match Option.bind target component with
      | None -> false
      | Some (_, c) -> GtkBase.Tooltip.set_text tooltip (c#get_name ^ "\n" ^ s_ "sketch.gestures"); true));
    box#misc#set_has_tooltip true;
    ignore (box#misc#connect#after#draw ~callback:(fun cr ->
      (match !selected with
       | None -> ()
       | Some target ->
           let ox, oy = image_origin () in
           Cairo.save cr;
           Cairo.translate cr ox oy;
           Cairo.scale cr !zoom !zoom;
           Cairo.set_source_rgba cr 0.16 0.45 0.88 0.9;
           Cairo.set_line_width cr (2. /. !zoom);
           List.iter (fun area -> if area.Sketch_hit_map.target = target then begin
             (match area.Sketch_hit_map.shape with
              | Sketch_hit_map.Rect (x1, y1, x2, y2) ->
                  Cairo.rectangle cr (x1 -. 3.) (y1 -. 3.) ~w:(x2 -. x1 +. 6.) ~h:(y2 -. y1 +. 6.)
              | Sketch_hit_map.Circle (x, y, radius) -> Cairo.arc cr x y ~r:radius ~a1:0. ~a2:(2. *. Float.pi)
              | Sketch_hit_map.Poly points ->
                  Array.iteri (fun index (x, y) ->
                    if index = 0 then Cairo.move_to cr x y else Cairo.line_to cr x y) points;
                  Cairo.Path.close cr);
             Cairo.stroke cr
           end) st#sketch_hit_map;
           Cairo.restore cr);
      false));
    let update_map () = GMain_actor.delegate (fun () ->
      if st#sketch_hit_map <> [] then begin
        base_image := Some (GdkPixbuf.from_file st#project_paths#pngSketchFile);
        set_zoom !zoom
      end;
      update_selection ()) ()
    in
    ignore (Cortex.on_commit_append st#sketch_map_counter (fun _ _ -> update_map ()));
    ignore (Cortex.on_commit_append st#project_paths#filename (fun _ _ ->
      GMain_actor.delegate (fun () ->
        selected := None; zoom := 1.; base_image := None; update_selection ()) ()))
end
