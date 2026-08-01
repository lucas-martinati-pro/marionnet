(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008, 2009  Luca Saiu
   Copyright (C) 2007, 2009, 2010  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2009, 2010  Université Paris 13

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
module Log = Marionnet_log

open Gettext;;

(** Convert ocaml (ISO-8859-1) string in UTF-8 format *)
(* let utf8 x = Glib.Convert.convert x "UTF-8" "ISO-8859-1";;  *)
let utf8 x = x;; (* We currently don't use this. It works better :-) *)

(* Every dialog built here runs inside GMain_actor.apply_extract, because these functions are
   called from threads that are NOT the GTK main thread — and building a widget from another
   thread is the same violation that froze the whole process at episodes 9 and 10 (see the long
   comment in treeview.ml). The callers that matter are not exotic: the death monitor thread
   warns the user when a process dies unexpectedly (simulation_level.ml), a failing task runner
   task pops a warning (user_level.ml), the open/save/close threads report their errors
   (state.ml), and so do the menu action threads (gui_menubar_MARIONNET.ml) — i.e. precisely the
   paths that fire when something has already gone wrong. apply_extract runs the body on the spot
   when the caller already is the GTK main thread, so the many call sites that were correct all
   along pay nothing and keep their exact semantics, exceptions included. This wrapping is what
   Progress_bar has been doing since the beginning; these dialogs simply never got it. *)

(** Generic constructor for message dialog *)
let message win_title ?modal (msg_title) (msg_content) (img_file) () =
  GMain_actor.apply_extract (fun () ->
  let d = new Gui.dialog_MESSAGE () in
  d#toplevel#set_resizable true;
  Option.iter (d#toplevel#set_modal) modal;
  let _ = d#closebutton_MESSAGE#connect#clicked ~callback:(d#toplevel#destroy) in
  d#toplevel#set_icon (Some Icon.icon_pixbuf);
  d#toplevel#set_title (utf8 win_title);
  d#title#set_use_markup true;
  d#title#set_label ("<b>"^msg_title^"</b>");
  d#title#set_selectable true;
  d#content#set_label msg_content;
  d#content#set_selectable true;
  d#image#set_file (Initialization.Path.images ^ img_file);
  ()) ()
;;

(** Specific constructor for help messages *)
let help ?modal title msg () =
  message ?modal (s_ "Help") title msg "ico.help.orig.png" ();;

(** Specific constructor for error messages *)
let error ?modal title msg () =
  message ?modal (s_ "Error") title msg "ico.error.orig.png" ();;

(** Specific constructor for warning messages *)
let warning ?modal title msg () =
  message ?modal (s_ "Warning") title msg "ico.warning.orig.png" ();;

(** Specific constructor for info messages *)
let info ?modal title msg () =
  message ?modal (s_ "Information") title msg "ico.info.orig.png" ();;

(** Recapitulative dialog for a list of adjustments applied while loading an old project.
    Unlike the generic [message] dialog (a single label that grows without bound and no
    scrollbar, whose CLOSE button ends up pushed off-screen when there are many lines),
    this one keeps a fixed, always-visible action area and puts the — possibly long — list
    of items inside a height-capped scrolled window. Each item shows a one-line summary
    (always visible) and reveals its detail on demand through an expander; items flagged
    [`Warning] (a lossy drop/removal) get a warning marker, [`Info] ones (a harmless
    switch) none. [header] is a short bold headline shown next to the icon; the optional
    [preamble] is a longer wrapped sentence introducing the list just above it. *)
let recapitulative ?(modal=false) ~title ~header ?preamble (items : (string * string * [`Info | `Warning]) list) () =
  GMain_actor.apply_extract (fun () ->
  let window =
    GWindow.window
      ~title
      ~modal
      ~position:`CENTER
      ~type_hint:`DIALOG
      ~icon:Icon.icon_pixbuf
      ~resizable:true
      ~width:640
      ()
  in
  let outer = GPack.vbox ~packing:window#add ~border_width:12 ~spacing:12 () in
  (* Header: warning icon + short bold headline. Packed non-expanding, so it stays put. *)
  let header_box = GPack.hbox ~packing:(outer#pack ~expand:false) ~spacing:10 () in
  let () =
    let img = GMisc.image ~packing:(header_box#pack ~expand:false) () in
    img#set_file (Initialization.Path.images ^ "ico.warning.orig.png")
  in
  let _ =
    GMisc.label
      ~markup:("<b>" ^ Glib.Markup.escape_text header ^ "</b>")
      ~xalign:0.0 ~line_wrap:true
      ~packing:(header_box#pack ~expand:true ~fill:true) ()
  in
  (* Optional preamble: a longer sentence introducing the list, full width below the
     headline. *)
  let () =
    match preamble with
    | None -> ()
    | Some text ->
        let _ =
          GMisc.label ~text ~xalign:0.0 ~line_wrap:true
            ~packing:(outer#pack ~expand:false) ()
        in ()
  in
  (* Height-capped scrollable list: this is what keeps CLOSE reachable no matter how many
     items there are. *)
  let scrolled =
    GBin.scrolled_window
      ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC
      ~shadow_type:`IN
      ~packing:(outer#pack ~expand:true ~fill:true) ()
  in
  scrolled#misc#set_size_request ~height:320 ();
  let list_box = GPack.vbox ~spacing:6 ~border_width:6 () in
  scrolled#add_with_viewport list_box#coerce;
  List.iter
    (fun (summary, detail, severity) ->
       (* GBin.expander labels are plain text (no markup in this lablgtk3 binding), so the
          summary is passed verbatim; the marker is a literal UTF-8 glyph. *)
       let marker = match severity with `Warning -> "\xE2\x9A\xA0  " | `Info -> "" in
       let expander =
         GBin.expander
           ~label:(marker ^ summary)
           ~packing:(list_box#pack ~expand:false) ()
       in
       let _ =
         GMisc.label
           ~text:detail
           ~xalign:0.0 ~xpad:18 ~line_wrap:true ~selectable:true
           ~packing:expander#add ()
       in
       ())
    items;
  (* Fixed action area (outside the scrolled window): CLOSE is always visible. *)
  let action = GPack.button_box `HORIZONTAL ~layout:`END ~packing:(outer#pack ~expand:false) () in
  let close = GButton.button ~stock:`CLOSE ~packing:action#add () in
  ignore (close#connect#clicked ~callback:window#destroy);
  let _ = window#event#connect#key_press ~callback:begin fun ev ->
    let k = GdkEvent.Key.keyval ev in
    if k = GdkKeysyms._Escape || k = GdkKeysyms._Return
    then (window#destroy (); true)
    else false
  end in
  close#misc#set_can_default true;
  close#misc#grab_default ();
  window#show ()) ()
;;

(** Show a new dialog displaying a progress bar *)
let make_progress_bar_dialog =
  Progress_bar.make_progress_bar_dialog;;

(** Destroy a dialog which was previously created by make_progress_bar_dialog *)
let destroy_progress_bar_dialog dialog =
  Progress_bar.destroy_progress_bar_dialog dialog;;

(* --- *)
let confirm_dialog ~question ?(cancel = false) () =
  (* Note for this one: #run() enters a nested main loop, which does go back through ml_poll and
     therefore does release the master lock — so it was not a freeze candidate by itself. It is
     wrapped all the same, because building the dialog beforehand is, and because a nested main
     loop spun by a secondary thread while the main thread runs its own is a race we do not want
     to reason about twice. *)
  GMain_actor.apply_extract (fun () ->
  let dialog = new Gui.dialog_QUESTION () in
  dialog#toplevel#set_icon (Some Icon.icon_pixbuf);
  dialog#toplevel#set_title (utf8 "Confirmation");
  dialog#title_QUESTION#set_use_markup true;
  dialog#title_QUESTION#set_label question;
  ignore
    (dialog#toplevel#event#connect#delete
       ~callback:(fun _ ->
         Log.printf "Sorry, no, you can't close the dialog. Please make a decision.\n";
         true));
  (if cancel then dialog#toplevel#add_button_stock `CANCEL `CANCEL);
  let result = (ref None) in
  let cont   = ref true in
  while (!cont = true) do
    begin match dialog#toplevel#run () with
    | `YES    -> (cont := false; result := Some true)
    | `NO     -> (cont := false; result := Some false)
    | `CANCEL -> (cont := false; result := None)
    |  _ -> () (* the user tried to close the dialog. No, we refuse: let him/her try again *)
    end
  done;
  dialog#toplevel#destroy ();
  !result) ()
;;

(** Only internally used: *)
exception TheUserCanceled;;

(** Show a modal dialog prompting the user for a text, and return the text as entered
    by the user. A predicate checking that the text supplied by the user is valid and a
    callback to be automatically invoked at each text update can be optionally supplied.
    Two callbacks should be supplied, to be called in case of success or cancel. *)
let ask_text_dialog
    ~title
    ~label
    ?(initial_text="")
    ?(constraint_predicate=(fun _ -> true))
    ?(invalid_text_message=(s_ "Sorry, the size is invalid."))
    ?(changed_callback=(fun _ -> ()))
    ?max_length
    ?(enable_cancel=false)
    ?(cancel_callback=(fun () -> ()))
    ?(border_width=40)
    ?(spacing=20)
    ~ok_callback
    () =
  GMain_actor.apply_extract (fun () ->
  let window =
    GWindow.window
      ~title
      ~modal:true
      ~position:`CENTER
      ~type_hint:`DIALOG
      ~icon:Icon.icon_pixbuf
      ~resizable:false
      () in
  let vbox = GPack.vbox ~packing:window#add ~border_width ~spacing () in
  let _ = GMisc.label ~text:label ~packing:vbox#add ~line_wrap:true () in
  let entry = GEdit.entry ~text:initial_text ?max_length ~packing:vbox#add () in
  ignore (entry#connect#changed
            ~callback:(fun () -> changed_callback entry#text));
  let hbox = GPack.hbox ~packing:vbox#add ~homogeneous:true () in
  let button_ok = GButton.button ~stock:`OK ~packing:hbox#add () in
  (if enable_cancel then
    let button_cancel = GButton.button ~stock:`CANCEL ~packing:hbox#add () in
    ignore
      (button_cancel#connect#clicked
         ~callback:(fun () ->
                      window#destroy ();
                      cancel_callback ())));
  let ok_callback window entry () =
    let text = entry#text in
    if constraint_predicate text then begin
      window#destroy ();
      ok_callback text
    end
    else begin
      error (s_ "Invalid size") invalid_text_message ()
    end
  in
  ignore (button_ok#connect#clicked ~callback:(ok_callback window entry));
  let _ = window#event#connect#key_press ~callback:
  begin fun ev ->
   (if GdkEvent.Key.keyval ev = GdkKeysyms._Return then ok_callback window entry ());
   false
  end in
  button_ok#misc#set_can_default true;
  button_ok#misc#grab_default ();
  window#show ()) ()
;;
