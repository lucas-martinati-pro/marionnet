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

(* --- *)
module Log = Marionnet_log
module Option = Ocamlbricks.Option
module StackExtra = Ocamlbricks.StackExtra
module Dot = Ocamlbricks.Dot
module Dot_widget = Ocamlbricks.Dot_widget
module Environments = Ocamlbricks.Environments
module UnixExtra = Ocamlbricks.UnixExtra
(* --- *)
open Gettext;;

(** Gui completion for the menubar_MARIONNET widget defined with glade. *)

(* Shortcuts *)
module EDialog = Talking.EDialog
module Msg = Talking.Msg
let mkenv = Environments.make_string_env

open GdkKeysyms
(*open GtkStock*)

module Make (State:sig val st:State.globalState end) = struct

open State

(* Create the factory linked to the menubar. *)
module F = Menu_factory.Make (struct
  let parent = Menu_factory.Menubar st#mainwin#menubar_MARIONNET
  let window = st#mainwin#window_MARIONNET
end)
include F

(* **************************************** *
                Menu "Project"
 * **************************************** *)

let project = add_menu (s_ "_Project" )

module Common_dialogs = struct

 (* Exam locks (journalisation-profonde, episode 23). FOUR gestures leave a project — Close, New,
    Open, Quit (and the window manager's (x), which calls the Quit entry) — and three of them used
    to ask "do you want to save the current project?". That question has a wrong answer, and its
    cost is not symmetric: what a session archived at shutdown (report, command history, console,
    terminal) lives in the .mar ONLY if the project is saved, so a student clicking "no" by reflex
    loses their whole copy. In exam mode the question is therefore not asked at all — leaving means
    saving, and the four gestures answer the same way.

    Outside an exam the question stays: discarding an experiment is a legitimate gesture, and often
    the very point of a rehearsal. But it now says what would be lost, and only when there is
    something to lose — [has_left_traces] is the model's own predicate (user_level.ml, episode 22),
    the same one which decides whether a component may be removed. *)

 let something_has_run () =
   List.exists (fun n -> n#has_left_traces) (st#network#get_node_list)

 (* [gen_id] is the field the caller reads back ("answer" for Close and Quit, "save_current" for
    New and Open, which chain this dialog with a file chooser). [script_answer] keeps the contract
    of a driven session: a question raised while the control server serves a command is answered
    by default instead of freezing it (talking.ml). *)
 let ask_to_save_current_project ?(gen_id="answer") ?(title=(s_ "Close")) ?script_answer () =
   if not st#active_project then (Some (mkenv [(gen_id, "no")])) else
   if Initialization.are_we_in_exam_mode then (Some (mkenv [(gen_id, "yes")])) else
   let question =
     let question = (s_ "Do you want to save the current project?") in
     if not (something_has_run ()) then question else
     question ^ "\n\n" ^
     (s_ "Careful: some components have run in this session. Answering \"no\" discards their disk states, and every document archived into the project.")
   in
   EDialog.ask_question ~help:None ~cancel:true ~gen_id ~title ~question ?script_answer ()

 (* Dialog used both for "New" and "Open" *)
 let save_current () = ask_to_save_current_project ~gen_id:"save_current" ()

 (* Leaving a project, in the right ORDER — the other half of episode 23, and the one which makes
    the forced save worth anything. [shutdown_everything] only *schedules* its tasks on the task
    runner (state.ml) and returns at once, while the exam archiving is the very LAST thing each
    graceful shutdown does. Saving right after the call therefore wrote a .mar without the very
    documents the save was for: a race, won by the guest only when it went down fast enough.
    Waiting for the task runner in between is what closes it — and it MUST NOT happen in the GTK
    main thread (task_runner.ml warns about it, and the archiving itself goes through
    GMain_actor.apply_extract since episode 12, so blocking that thread would deadlock).
    Every caller below therefore runs this in a thread of its own. *)
 let shutdown_then_save ~(must_be_saved:bool) () =
   if st#active_project then begin
     let () = st#shutdown_everything () in
     let () = Task_runner.the_task_runner#wait_for_all_currently_scheduled_tasks in
     if must_be_saved then st#save_project
     end

end

type env  = string Environments.string_env
let env_to_string (t:env) = t#to_string (fun s->s)

module Created_entry_project_new = Menu_factory.Make_entry(struct
   type t = env
   let to_string = env_to_string
   let text  = (s_ "New" )
   let stock = `NEW
   let key   = (Some _N)

   let dialog =
     let filename () =
       EDialog.ask_for_fresh_writable_filename
         ~title:(s_ "Name of the new project" )
         ~filter_names:[`MAR;`ALL]
         ~help:(Some Msg.help_nom_pour_le_projet) ()
     in
     (EDialog.sequence [Common_dialogs.save_current; filename])

   let reaction r =
     begin
      let must_be_saved  = ((r#get "save_current")="yes") in
      let filename = Talking.check_filename_validity_and_add_extension_if_needed (r#get "filename") in
      (* --- *)
      let actions () =
         let () = Log.printf "About to react to Gui_menubar_MARIONNET.new_project\n" in
         let active_project = st#active_project in
         let () = Common_dialogs.shutdown_then_save ~must_be_saved () in
         let () = if (active_project) then st#close_project in
         st#new_project filename
      in
      (* --- *)
      (* Task_runner.the_task_runner#schedule ~name:"Gui_menubar_MARIONNET.new_project" actions *)
      let _ = Thread.create (actions) () in
      ()
      (* --- *)
     end

  end) (F)
let project_new = Created_entry_project_new.item


module Created_entry_project_open = Menu_factory.Make_entry(struct
   type t = env
   let to_string = env_to_string
   let text  = (s_ "Open" )
   let stock = `OPEN
   let key   = (Some _O)

   let dialog =
     let filename_dialog () =
       EDialog.ask_for_existing_rw_filename
         ~title:(s_ "Open an existing Marionnet project" )
         ~filter_names:[`MAR; `ALL]
         ~help:(Some Msg.help_nom_pour_le_projet) ()
     in
     (EDialog.sequence [Common_dialogs.save_current; filename_dialog])

   let reaction r =
     begin
      let must_be_saved = ((r#get "save_current")="yes") in
      let filename      = (r#get "filename") in
      (* --- *)
      let actions () =
         let () = Log.printf "About to react to Gui_menubar_MARIONNET.open_project\n" in
         let active_project = st#active_project in
         let () = Common_dialogs.shutdown_then_save ~must_be_saved () in
         let () = if (active_project) then st#close_project in
         (* --- *)
         try st#open_project_async filename
         with e -> ((Simple_dialogs.error (s_ "Open a project") ((s_ "Failed to open the file ")^filename) ()); raise e)
      in
      (* --- *)
      (* Task_runner.the_task_runner#schedule ~name:"Gui_menubar_MARIONNET.open_project" actions *)
      let _ = Thread.create (actions) () in
      ()
      (* --- *)
     end

  end) (F)
(* --- *)
let project_open = Created_entry_project_open.item

(* --- *)
let project_save =
  add_stock_item (s_ "Save" )
    ~stock:`SAVE
    ~callback:(fun () ->
      if st#is_there_something_on_or_sleeping ()
	then Msg.error_saving_while_something_up ()
        else st#save_project)
    ()

(* --- *)
module Created_entry_project_save_as = Menu_factory.Make_entry(struct
   type t = env
   let to_string = env_to_string
   let text  = (s_ "Save as" )
   let stock = `SAVE_AS
   let key   = None

   (* --- *)
   let dialog () =
     EDialog.ask_for_fresh_writable_filename
       ~title:(s_ "Save as" )
       ~filter_names:[`MAR; `ALL]
       ~help:(Some Msg.help_nom_pour_le_projet) ()

   (* --- *)
   let reaction r =
     let active_project = st#active_project in
     if not active_project then () else (* continue: *)
     begin
       (* --- *)
       if st#is_there_something_on_or_sleeping () then Msg.error_saving_while_something_up () else (* continue: *)
       (* --- *)
       let filename = Talking.check_filename_validity_and_add_extension_if_needed ~extension:"mar" (r#get "filename") in
       (* --- *)
       let actions () =
         let () = Log.printf "About to react to Gui_menubar_MARIONNET.save_as_project\n" in
         try st#save_project_as ~filename ()
         with _ -> (Simple_dialogs.error (s_ "Save project as") ((s_ "Failed to save the project into the file ")^filename) ())
       in
       (* --- *)
       (* Task_runner.the_task_runner#schedule ~name:"Gui_menubar_MARIONNET.save_as_project" actions *)
       let _ = Thread.create (actions) () in
       ()
       (* --- *)
     end

  end) (F)
(* --- *)
let project_save_as = Created_entry_project_save_as.item

(* --- *)
module Created_entry_project_copy_to = Menu_factory.Make_entry(struct
   type t = env
   let to_string = env_to_string
   let text  = (s_ "Copy to" )
   let stock = `SAVE_AS
   let key   = None

   (* --- *)
   let dialog () =
     EDialog.ask_for_fresh_writable_filename
       ~title:(s_ "Copy to" )
       ~filter_names:[`MAR; `ALL]
       ~help:(Some Msg.help_nom_pour_le_projet) ()

   (* --- *)
   let reaction r =
     let active_project = st#active_project in
     if not active_project then () else (* continue: *)
     begin
       (* --- *)
       if st#is_there_something_on_or_sleeping () then Msg.error_saving_while_something_up () else (* continue: *)
       (* --- *)
       let filename = Talking.check_filename_validity_and_add_extension_if_needed ~extension:"mar" (r#get "filename") in
       let actions () =
         let () = Log.printf "About to react to Gui_menubar_MARIONNET.copy_to_project\n" in
         try st#copy_project_into ~filename ()
         with _ -> (Simple_dialogs.error (s_ "Project copy to" ) ((s_ "Failed to copy the project into the file ")^filename) ())
       in
       (* --- *)
       (* Task_runner.the_task_runner#schedule ~name:"Gui_menubar_MARIONNET.copy_to_project" actions *)
       let _ = Thread.create (actions) () in
       ()
       (* --- *)
     end

  end) (F)
(* --- *)
let project_copy_to = Created_entry_project_copy_to.item

(* --- *)
module Created_entry_project_close = Menu_factory.Make_entry
 (struct
   type t = env
   let to_string = env_to_string
   let text  = (s_ "Close" )
   let stock = `CLOSE
   let key   = (Some _W)

   (* --- *)
   (* Episode 23: the same dialog as New and Open — and in exam mode, no dialog at all. *)
   let dialog () = Common_dialogs.ask_to_save_current_project ~title:(s_ "Close") ()

   (* --- *)
   let reaction r =
     begin
      let must_be_saved  = ((r#get "answer")="yes") in
      (* --- *)
      let actions () =
         let () = Log.printf "About to react to Gui_menubar_MARIONNET.close_project\n" in
         let () = Common_dialogs.shutdown_then_save ~must_be_saved () in
         st#close_project
      in
      (* --- *)
      (* Task_runner.the_task_runner#schedule ~name:"Gui_menubar_MARIONNET.close_project" actions *)
      let _ = Thread.create (actions) () in
      ()
      (* --- *)
     end

  end) (F)
let project_close = Created_entry_project_close.item

(* --- *)
let separator = project#add_separator ()

(* --- *)
module Created_entry_project_export = Menu_factory.Make_entry
 (struct
   type t = env
   let to_string = env_to_string
   let text  = (s_ "Export image" )
   let stock = `CONVERT
   let key   = None

   let dialog () =
     let extra_widget =
       let (combo_box, get_selected) = Dot_widget.combo_of_working_output_formats ~active:`png () in
       let widget_reader () =
	 let frm = get_selected () in
	 Dot.string_of_output_format frm
       in
       let table = GPack.table ~rows:2 ~columns:1 ~row_spacings:10 ~homogeneous:false () in
       let _ = GMisc.label
         ~xalign:0.5
         ~markup:("<b>"^(s_ "Output format")^"</b>")
         ~packing:(table#attach ~left:0 ~top:0) ()
       in
       (table#attach ~left:0 ~top:1 combo_box#coerce);
       (table#coerce, widget_reader)
     in
     EDialog.ask_for_fresh_writable_filename
       ~title:(s_ "Export network image" )
       ~filters:(Dot_widget.make_all_working_filters ())
       ~filter_names:[`ALL]
       ~extra_widget
       ~help:None ()

   let reaction r =
     let output_format = (r#get "extra_widget") in
     let filename = Talking.check_filename_validity_and_add_extension_if_needed ~extension:output_format (r#get "filename") in
     let command = Printf.sprintf "dot -T%s -o '%s' '%s'" output_format filename st#project_paths#dotSketchFile in
     let on_error () =
	Simple_dialogs.error
	  "Export network image"
	  ((s_ "Failed to export network image to the file ")^filename^" (format "^output_format^")")
	  ()
     in
     try
       Log.system_or_fail command;
       st#flash ~delay:8000 ((s_ "Network image correctly exported to the file ")^filename)
     with _ -> on_error ()

  end) (F)
let project_export = Created_entry_project_export.item

(* --- *)
module Created_entry_project_quit = Menu_factory.Make_entry
 (struct
   type t = env
   let to_string = env_to_string
   let text  = (s_ "Quit")
   let stock = `QUIT
   let key   = (Some _Q)

   (* Exam locks (journalisation-profonde, episode 22). Quitting was the *quiet* way of losing an
      exam copy, and it lost it twice over: answering "no" to the question below powered every
      running guest off — the archiving happens in the graceful shutdown only — and then quit
      without saving, so even what had already been archived into the [documents] treeview never
      reached the .mar. In exam mode the question is therefore not asked at all: as long as a
      project is open, quitting means shutting down gracefully and saving. It is not a dialog a
      student should have to get right under time pressure.

      Episode 23: the same dialog as Close, New and Open, so that the four gestures which leave a
      project answer alike — including the (x) of the window manager, which calls this very entry
      (gui_window_MARIONNET.ml). The guard below survives, and it is not a shortcut: MEASURED
      (2026-08-14) that the exam archiving does mark the project as modified — three documents
      archived, [project_already_saved] false right after — so "already saved" really does mean
      "nothing to lose", and asking there would be asking for nothing. *)
   let dialog () =
    if (st#active_project && st#project_already_saved)
     then (Some (mkenv [("answer","no")]))
     else
       Common_dialogs.ask_to_save_current_project
         ~title:(s_ "Quit")
         (* A driven session quits without saving behind the script's back. A script that wants
            its project saved says so. *)
         ~script_answer:"no"
         ()

   (* --- *)
   (* Episode 23. The whole sequence now runs in a THREAD OF ITS OWN, like the three other
      gestures which leave a project, and for a reason measured rather than guessed: this
      reaction used to run in the GTK main thread, where [shutdown_everything] can only be
      *scheduled* — so the save, and worse [destroy_process_before_quitting] right below, went
      ahead while the guests were still going down. In exam mode that is the copy: the archiving
      is the last thing a graceful shutdown does. Off the main thread, the wait inside
      [shutdown_then_save] is legitimate and the GTK thread stays free to serve the archiving
      (GMain_actor.apply_extract, episode 12). *)
   let reaction r =
    (* At this point the user really wants to quit the application. *)
    let must_be_saved = (st#active_project) && ((r#get "answer") = "yes") in
    (* --- *)
    let actions () =
      let () =
        match st#is_there_something_on_or_sleeping (), must_be_saved with
        | true,  true  -> Common_dialogs.shutdown_then_save ~must_be_saved:true ()
        | true,  false ->
            (* Unreachable in exam mode — the dialog answers "yes" there, and the model would
               refuse this anyway (state.ml, [poweroff_everything], episode 22). Outside an exam
               it is the right gesture and it is kept: nothing is going to be saved, so waiting
               for a graceful shutdown would make someone who wants to leave wait for nothing. *)
            st#poweroff_everything ()
        | false, true  -> st#save_project
        | false, false -> ()
      in
      (* --- *)
      Log.printf "Killing the death monitor thread...\n";
      Death_monitor.stop_polling_loop ();
      st#network#destroy_process_before_quitting ();
      st#close_project;
      st#quit_async ()
    in
    (* --- *)
    let _ = Thread.create (actions) () in
    ()

  end) (F)
let project_quit = Created_entry_project_quit.item


(* **************************************** *
                Menu "Options"
 * **************************************** *)

(* --- *)
let options = add_menu (s_ "_Options")

(* --- *)
module Created_entry_options_cwd = Menu_factory.Make_entry
 (struct
   type t = env
   let to_string = env_to_string
   let text  = (s_ "Change the temporary working directory")
   let stock = `DIRECTORY
   let key   = None
   let dialog () =
    Talking.EDialog.ask_for_existing_writable_folder_pathname_supporting_sparse_files
       ~title:(s_ "Choose the temporary working directory")
       ~help:(Some Msg.help_repertoire_de_travail) ()
   let reaction r =
     let pathname = (r#get "foldername") in
     let realpath = Option.extract (UnixExtra.realpath pathname) in
     st#project_paths#set_temporary_directory (realpath)
  end) (F)
(* --- *)
let options_cwd = Created_entry_options_cwd.item

(* --- *)
(* Hidden to user in this version. *)
let options_autogenerate_ip_addresses =
 add_check_item (s_ "Auto-generation of IP address" )
  ~active:Global_options.autogenerate_ip_addresses_default
  ~callback:(fun active ->
         Log.printf "You toggled the option (IP)\n";
         Global_options.set_autogenerate_ip_addresses active)
   ()
(* --- *)
let () = options_autogenerate_ip_addresses#coerce#misc#hide ()

(* --- *)
let options_debug_mode =
 add_check_item (s_ "Debug mode")
  ~active:(Global_options.Debug_level.are_we_debugging ())
  ~callback:(fun active ->
         Log.printf1 ~force:true "You toggled the option (debug), now to %b\n" active;
         let level = if active then 1 else 0 in
         Global_options.Debug_level.set level)
 ()

(* --- *)
(* Exam locks (journalisation-profonde, episode 22). A witness, not a command: in exam mode the
   "Remove" dynlists of the components are empty for whatever has already run, and without this
   line nothing on screen would say why. Hence a check item which is insensitive — a student must
   not be able to lift the lock in two clicks — and which is simply not there outside the exam
   mode, where removing a component is nobody's business but the user's. The state it shows is
   the one the model reads ([can_destroy], user_level.ml); the option which flips it is
   --exam-allow-delete, on the command line. *)
let options_exam_delete_lock =
 add_check_item (s_ "Exam mode: forbid removing components which have run")
  ~active:(not Initialization.are_we_allowed_to_delete)
  ~callback:(fun _ -> ())
 ()
(* --- *)
let () =
  if Initialization.are_we_in_exam_mode
  then options_exam_delete_lock#coerce#misc#set_sensitive false
  else options_exam_delete_lock#coerce#misc#hide ()

(* --- *)
let options_keep_all_snapshots_when_saving =
 add_check_item (s_ "Keep all snapshots when saving (not only the most recent ones)")
  ~active:(Global_options.Keep_all_snapshots_when_saving.extract ())
  ~callback:(fun active ->
         Log.printf "You toggled the option (keep al snapshots)\n";
         Global_options.Keep_all_snapshots_when_saving.set active)
 ()

(* --- *)
(* Hidden to user in this version. *)
let workaround_wirefilter_problem =
 add_check_item "Workaround wirefilter problem"
  ~active:Global_options.workaround_wirefilter_problem_default
  ~callback:(fun active ->
         Log.printf "You toggled the option (wirefilter)\n";
         Global_options.set_workaround_wirefilter_problem active)
 ()
(* --- *)
let () = workaround_wirefilter_problem#coerce#misc#hide ()

(* **************************************** *
                Menu "Help"
 * **************************************** *)

let help         = add_menu (s_ "_Help")
let help_apropos =
 let module D = Gui_dialog_A_PROPOS.Make (State) in
 let callback () =
   let dialog = D.dialog () in
   let _ = dialog#closebutton_A_PROPOS#connect#clicked ~callback:(dialog#toplevel#destroy) in ()
 in add_stock_item (s_ "Help") ~stock:`ABOUT ~callback ()


(* **************************************** *
                Sensitiveness
 * **************************************** *)

let () = List.iter (* when a project is active *)
          (fun w -> StackExtra.push (w#coerce) st#sensitive_when_Active)
          [project_close; project_export]

(* The three entries which write the project are not merely conditioned by an active project:
   their callbacks refuse the action as soon as something is on or sleeping (see above,
   Msg.error_saving_while_something_up). Being in this fourth stack, the forbidding is now read
   *before* the gesture -- "Save as" and "Copy to" no longer ask for a filename in order to
   refuse afterwards. The run-time guards stay where they are: neither the control channel nor
   a keyboard shortcut goes through the sensitiveness of a widget. *)
let () = List.iter (* when a project is active and nothing is running *)
          (fun w -> StackExtra.push (w#coerce) st#sensitive_when_Saveable)
          [project_save; project_save_as; project_copy_to]

let () = List.iter (* when no project is active *)
          (fun w -> StackExtra.push (w#coerce) st#sensitive_when_NoActive)
          [options_cwd]

end
