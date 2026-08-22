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

(* In a driven session (script_mode.ml) a window nobody closes stays there forever, and
   what it says is lost to the script — a failed project loading reports its cause here and
   nowhere else (control_server.ml, cmd_open). So capture first, then let the window close
   itself after a delay: the session is meant to stay observable, hence the delay rather
   than an immediate destroy. Attached to whatever widget the caller built. *)
let capture_and_dismiss ~(kind:Script_mode.kind) ~(title:string) ?items (body:string) (destroy : unit -> unit) : unit =
  if not (Script_mode.enabled ()) then () else
  let () = Script_mode.notify ~kind ~title ?items body in
  ignore
    (GMain.Timeout.add
       ~ms:(Script_mode.auto_dismiss_ms ())
       (* The user (or an earlier dismissal) may have destroyed the widget already: firing
          on a destroyed widget raises, and this callback runs in the GTK main loop, where
          an escaping exception is nobody's business. *)
       ~callback:(fun () -> (try destroy () with _ -> ()); false))
;;

(** Generic constructor for message dialog.
    ---
    [actions] adds buttons that DO something, to the left of the Close button of the glade: a
    message that tells the user to run a command can then offer to run it. Each one closes the
    dialog and calls its callback -- which must not block, since it runs in the GTK main loop
    (see bin/marionnet.ml, where the callbacks of the startup warning about run directories
    hand the work to a thread). They are packed into the action area exposed by the generated
    bin/gui.ml, so the glade file is not touched: an added widget only has to be shown
    explicitly, the dialog being mapped already. *)
let message win_title ?modal ?(kind=`Info) ?(actions : (string * (unit -> unit)) list = []) (msg_title) (msg_content) (img_file) () =
  GMain_actor.apply_extract (fun () ->
  let d = new Gui.dialog_MESSAGE () in
  (* The dialog is deliberately left NON resizable, as dialog_QUESTION is. The glade marks it
     visible, so the builder maps it while it is still empty, and the labels below are filled
     afterwards: Gtk+ 3 does grow an already mapped window to its new NATURAL size when the
     window is not resizable, but only to its new MINIMUM size when it is. The
     [set_resizable true] that stood here since the lablgtk3 port therefore gave every message
     the minimum width of a wrapping label -- the width of its longest word -- hence the narrow
     column measured before this episode on the real application: 398x512 pixels for a single
     paragraph, and 398x2672 for a long one, which puts the Close button off any classroom
     screen. Nothing is clipped by the loss of resizability: the
     body now lives in a height-capped scrolled window (see gui_glade3.xml). *)
  Option.iter (d#toplevel#set_modal) modal;
  let _ = d#closebutton_MESSAGE#connect#clicked ~callback:(d#toplevel#destroy) in
  (* --- *)
  List.iteri
    (fun i (label, callback) ->
       let button = GButton.button ~label ~show:true ~packing:(d#dialog_action_area3#add) () in
       (* #add appends, i.e. after Close: put them back in front, in the given order. *)
       let () = d#dialog_action_area3#reorder_child (button#coerce) ~pos:i in
       ignore
         (button#connect#clicked
            ~callback:(fun () -> d#toplevel#destroy (); callback ())))
    actions;
  (* The keyboard must not be able to fire an action by accident: a dialog that has just appeared
     under the pointer, and a Return typed at the wrong moment, would otherwise run whatever the
     first button does -- and one of them removes directories. Close keeps the focus, so Return
     and space close the window, as they did before there were any buttons. *)
  (if actions <> [] then d#closebutton_MESSAGE#misc#grab_focus ());
  d#toplevel#set_icon (Some Icon.icon_pixbuf);
  d#toplevel#set_title (utf8 win_title);
  d#title#set_use_markup true;
  d#title#set_label ("<b>"^msg_title^"</b>");
  d#title#set_selectable true;
  d#content#set_label msg_content;
  d#content#set_selectable true;
  d#image#set_file (Initialization.Path.images ^ img_file);
  (* One point of passage for help/error/warning/info, hence for the ~50 call sites. *)
  capture_and_dismiss ~kind ~title:msg_title msg_content (fun () -> d#toplevel#destroy ());
  ()) ()
;;

(** Specific constructor for help messages *)
let help ?modal title msg () =
  message ?modal ~kind:`Help (s_ "Help") title msg "ico.help.orig.png" ();;

(** Specific constructor for error messages *)
let error ?modal title msg () =
  message ?modal ~kind:`Error (s_ "Error") title msg "ico.error.orig.png" ();;

(** Specific constructor for warning messages. [actions] (see [message]) is what makes a
    warning actionable: the startup notice about the run directories left behind offers to
    recover and to clean, instead of only naming the tool. *)
let warning ?modal ?actions title msg () =
  message ?modal ?actions ~kind:`Warning (s_ "Warning") title msg "ico.warning.orig.png" ();;

(** Specific constructor for info messages *)
let info ?modal title msg () =
  message ?modal ~kind:`Info (s_ "Information") title msg "ico.info.orig.png" ();;

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
  let () =
    let l =
      GMisc.label
        ~markup:("<b>" ^ Glib.Markup.escape_text header ^ "</b>")
        ~xalign:0.0 ~line_wrap:true
        ~packing:(header_box#pack ~expand:true ~fill:true) ()
    in
    (* Same cure as in ask_password below, and for the same reason: the ~width:640 of the window
       is only a MINIMUM request, while a wrapping label still asks for its longest paragraph as
       its natural width -- and this window, unlike a message dialog, is shown once it is fully
       built, so that natural width is what it gets. Measured on a structural replica: 3840
       pixels wide (the whole screen) without the cap, 877 with it. *)
    l#set_max_width_chars 72
  in
  (* Optional preamble: a longer sentence introducing the list, full width below the
     headline. *)
  let () =
    match preamble with
    | None -> ()
    | Some text ->
        let l =
          GMisc.label ~text ~xalign:0.0 ~line_wrap:true
            ~packing:(outer#pack ~expand:false) ()
        in
        l#set_max_width_chars 72
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
       let l =
         GMisc.label
           ~text:detail
           ~xalign:0.0 ~xpad:18 ~line_wrap:true ~selectable:true
           ~packing:expander#add ()
       in
       l#set_max_width_chars 72)
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
  window#show ();
  (* The archetypal case of this work-stream: the list of adaptations applied to an old
     project (remapped kernels and distributions) is exactly what a script wants to read
     back. It goes into the capture *structured*, item by item, not flattened into a
     paragraph. *)
  capture_and_dismiss ~kind:`Recap ~title:header
    ~items:(List.map
              (fun (summary, detail, severity) ->
                 { Script_mode.summary; detail; severity })
              items)
    (match preamble with None -> "" | Some text -> text)
    (fun () -> window#destroy ())) ()
;;

(** Show a new dialog displaying a progress bar *)
let make_progress_bar_dialog =
  Progress_bar.make_progress_bar_dialog;;

(** Destroy a dialog which was previously created by make_progress_bar_dialog *)
let destroy_progress_bar_dialog dialog =
  Progress_bar.destroy_progress_bar_dialog dialog;;

(* --- *)
(* [script_answer] is the answer to give when the question is asked while the control
   server is serving a command (script_mode.ml, [must_auto_answer]): showing the dialog
   there would freeze the command until a human decides — and this dialog refuses to be
   closed. It is deliberately *not* a global "yes to everything": the human is still in
   front of the screen during a driven session, and their own confirmations must keep
   being asked. Omitting it means None, i.e. cancel, i.e. do nothing — the conservative
   default. Reaching this branch also means a GUI callback was called from the server,
   which docs/pilotage-par-script.md § 3.3 forbids: hence the loud log line. *)
let confirm_dialog ~question ?script_answer ?(cancel = false) () =
  if Script_mode.must_auto_answer () then begin
    let answer = match script_answer with
      | Some true  -> "yes"
      | Some false -> "no"
      | None       -> "cancel"
    in
    Log.printf2
      "Simple_dialogs.confirm_dialog: a question was asked while serving a control-server command; answering %S by default. Question was: %s\n"
      answer question;
    Script_mode.notify ~kind:`Question ~title:question
      (Printf.sprintf "auto-answered %s (no human was asked)" answer);
    script_answer
  end else
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

(* --- *)
(** Ask for the user's own password, in order to elevate a privilege with `sudo -S'
    (work-stream [modernisation-world-bridge], episode 6: activating a scoped sudoers
    block from the GUI, at the moment the privilege is needed). [header] says what the
    password is going to be used for -- a password dialog that does not say what it
    unlocks teaches the user to type it anywhere. [again] is for a retry, after sudo
    refused the previous attempt. Returns [None] when the user cancels.
    ---
    On the secret itself: the string comes back as an ordinary immutable OCaml string,
    which we cannot wipe; what we can do, and do, is keep it out of every place it would
    OUTLIVE the call -- never logged, never captured by the script mode, never passed
    through argv (see privileges.ml, which writes it on sudo's stdin).
    ---
    In a driven session there is nobody to type it: asking would freeze the calling
    thread behind a modal window that nothing will ever close. The guard is therefore
    [Script_mode.enabled] and NOT [must_auto_answer], which is [confirm_dialog]'s: the
    latter is only true while a command is being served, and this dialog is opened from
    a task-runner thread, long after the command that started the component answered.
    Measured, not supposed (episode 6, first run of the bench): with the narrower guard
    the password window really did pop up in the middle of a driven session and the
    task waited for a human. A password is also the one answer no default can stand in
    for, so we refuse, loudly, and the caller reports a plain failure. *)
let ask_password ?(again=false) ~title ~header () : string option =
  if Script_mode.enabled () then begin
    Log.printf1
      "Simple_dialogs.ask_password: a password was requested in a driven session; NOT asking (no human is there). It was needed for: %s\n"
      header;
    Script_mode.notify ~kind:`Question ~title
      "a password was requested but nobody was asked (driven session)";
    None
  end else
  GMain_actor.apply_extract (fun () ->
  let dialog =
    GWindow.dialog
      ~title
      ~modal:true
      ~position:`CENTER
      ~icon:Icon.icon_pixbuf
      ~resizable:false
      ()
  in
  let outer = GPack.hbox ~packing:(dialog#vbox#pack ~expand:true ~fill:true) ~border_width:12 ~spacing:12 () in
  let () =
    let img = GMisc.image ~packing:(outer#pack ~expand:false) () in
    img#set_file (Initialization.Path.images ^ "ico.warning.orig.png")
  in
  let vbox = GPack.vbox ~packing:(outer#pack ~expand:true ~fill:true) ~spacing:8 () in
  let () =
    let l =
      GMisc.label ~text:header ~xalign:0.0 ~line_wrap:true ~width:420
        ~packing:(vbox#pack ~expand:false) ()
    in
    (* Gtk+ 3: ~width is only the *minimum* request; a wrapping label still asks for
       its longest paragraph as its natural width, and the dialog obeys (measured:
       2019 pixels wide with the LAN bridge header). Capping the natural width is
       what makes the text wrap, in every language. *)
    l#set_max_width_chars 72
  in
  let () =
    if again then
      let _ =
        GMisc.label
          ~markup:("<b>" ^ Glib.Markup.escape_text (s_ "Sorry, try again.") ^ "</b>")
          ~xalign:0.0 ~line_wrap:true
          ~packing:(vbox#pack ~expand:false) ()
      in ()
  in
  let entry =
    GEdit.entry
      ~visibility:false          (* what makes it a password entry *)
      ~activates_default:true    (* Return = OK, as in every password prompt *)
      ~packing:(vbox#pack ~expand:false) ()
  in
  dialog#add_button_stock `CANCEL `CANCEL;
  dialog#add_button_stock `OK `OK;
  dialog#set_default_response `OK;
  dialog#show ();
  entry#misc#grab_focus ();
  let answer =
    match dialog#run () with
    | `OK -> (match entry#text with "" -> None | password -> Some password)
    | _ -> None      (* CANCEL, or the window was closed *)
  in
  (* Whether something was typed, never what: the log of a password dialog that
     was cancelled is the only trace left of a failed elevation. *)
  Log.printf1 "Simple_dialogs.ask_password: the dialog was %s\n"
    (match answer with None -> "cancelled" | Some _ -> "answered");
  (* The widget is about to die anyway; clearing it first is cheap and means the
     secret is not sitting in a GtkEntry buffer while GTK gets round to freeing it. *)
  entry#set_text "";
  dialog#destroy ();
  answer) ()
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
  let () =
    let l = GMisc.label ~text:label ~packing:vbox#add ~line_wrap:true () in
    (* Non resizable window, hence natural sizing: without a cap on the natural width a long
       instruction would take the whole screen. Same value as everywhere else. *)
    l#set_max_width_chars 72
  in
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
