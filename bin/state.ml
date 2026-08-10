(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008  Luca Saiu
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

(** Provide the class modelling the global state of the application. *)

(* --- *)
module Log = Marionnet_log
module Cortex = Ocamlbricks.Cortex
module Option = Ocamlbricks.Option
module PervasivesExtra = Ocamlbricks.PervasivesExtra
module ListExtra = Ocamlbricks.ListExtra
module StringExtra = Ocamlbricks.StringExtra
module StrExtra = Ocamlbricks.StrExtra
module StackExtra = Ocamlbricks.StackExtra
module SysExtra = Ocamlbricks.SysExtra
module UnixExtra = Ocamlbricks.UnixExtra
(* --- *)
open Gettext;;

let commit_suicide signal =
  raise Exit;;

(* Raised when opening a project whose version cannot be honoured. The argument is the raw
   content of the project's `version' file, when there is one: [Some "v4"] means a tag we do
   not know (hence, in all likelihood, a project written by a *more recent* Marionnet), while
   [None] means nothing identifiable at all (no readable tag and no successful fall-back). The
   two cases deserve different words: a project from the future is perfectly well-formed, and
   telling its owner to "ensure that the file be well-formed" sends them looking for a
   corruption that isn't there (work-stream `migration-marshal-to-text', episode 8b). *)
exception Unsupported_project_version of string option
;;

type filename = string
 and pathname = string
 and basename = string
;;

(* Example of hierarchy:

/tmp/marionnet-588078453.dir/
/tmp/marionnet-588078453.dir/sparse-swap-410647109
/tmp/marionnet-588078453.dir/sparse-swap-922455527
/tmp/marionnet-588078453.dir/foo/classtest
/tmp/marionnet-588078453.dir/foo/tmp
/tmp/marionnet-588078453.dir/foo/tmp/sketch.dot
/tmp/marionnet-588078453.dir/foo/tmp/sketch.png
/tmp/marionnet-588078453.dir/foo/states
/tmp/marionnet-588078453.dir/foo/states/states-forest.json
/tmp/marionnet-588078453.dir/foo/states/ifconfig-counters.json   # previously states/ports-counters
/tmp/marionnet-588078453.dir/foo/states/ifconfig.json            # previously states/ports
/tmp/marionnet-588078453.dir/foo/states/defects.json
/tmp/marionnet-588078453.dir/foo/states/texts.json
/tmp/marionnet-588078453.dir/foo/scripts
/tmp/marionnet-588078453.dir/foo/netmodel
/tmp/marionnet-588078453.dir/foo/netmodel/dotoptions.json
/tmp/marionnet-588078453.dir/foo/netmodel/network.json

The seven data files above are JSON since the project version `v3 (work-stream
`migration-marshal-to-text', see docs/migration-marshal-to-text.md). A project saved by an older
binary has the same seven files without the .json suffix, and as Marshal dumps — including
netmodel/network.xml, which never was XML. Reading them is unchanged; nothing is written that way
any more.
/tmp/marionnet-588078453.dir/foo/hostfs
/tmp/marionnet-588078453.dir/foo/hostfs/2
/tmp/marionnet-588078453.dir/foo/hostfs/2/boot_parameters
/tmp/marionnet-588078453.dir/foo/hostfs/1
/tmp/marionnet-588078453.dir/foo/hostfs/1/boot_parameters

Here:
temporary_directory                 = "/tmp"
project_working_directory           = "/tmp/marionnet-588078453.dir"
project_root_basename               = "foo"
project_root_pathname               = "/tmp/marionnet-588078453.dir/foo"
*)

class project_paths
  ?(project_filename : filename option = None)
  ?(temporary_directory : pathname = "/tmp")
  ?(project_working_directory : pathname option = None) (* Ex: Some "/tmp/marionnet-588078453.dir" *)
  ?(project_root_basename     : basename option = None) (* Ex: Some "foo" *)
  ()
  =
  let uncurry2 f (x,y) = f x y in
  let (/) = Filename.concat in
  (* --- *)
  object (self)

    (** The project filename, ex: Some "/home/donald/foo.mar" *)
    val filename    : (filename option) Cortex.t = Cortex.return (project_filename)
    method filename = filename
    method get_filename   = Cortex.get filename
    method set_filename x = Cortex.set filename x
    method unset_filename = Cortex.set filename None

    (** The parent of the project working directory, ex: "/tmp" *)
    val temporary_directory : pathname Cortex.t = Cortex.return "/tmp"
    method temporary_directory = temporary_directory
    method get_temporary_directory   = Cortex.get temporary_directory
    method set_temporary_directory x = Cortex.set temporary_directory x

    (* --- *)

    (** The project working directory is coupled with the the project root base name,
        which is the name of the root directory in the tarball containing the project.
        Examples:
          working_directory = "/tmp/marionnet-588078453.dir"
          root_basename     = "foo"
          root_pathname     = "/tmp/marionnet-588078453.dir/foo"   *)
    val data = Cortex.return (project_working_directory, project_root_basename)
    (* --- *)
    method get_working_directory   = Cortex.apply data fst
    method get_root_basename       = Cortex.apply data snd

    method set_working_directory x = ignore (Cortex.move data (fun (_,y) -> (x,y)))
    method set_root_basename     y = ignore (Cortex.move data (fun (x,_) -> (x,y)))
    method unset_root_pathname     = Cortex.set data (None, None)
    (* --- *)
    method extract_working_directory_and_root_basename =
      let x,y = Cortex.get data in ((Option.extract x), (Option.extract y))
    (* --- *)
    method root_pathname_cortex = data
    method root_pathname = Cortex.apply data (uncurry2 (Option.map2 Filename.concat))
    method extract_root_pathname     = (Option.extract self#root_pathname)
    method private extract_concat  z = (Option.extract self#root_pathname) / z
    method private possibly_concat z = (Option.map2 (/) (self#root_pathname) (Some z))
    (* --- *)
    method set_filename_and_create_the_project_working_directory (filename) : pathname =
      let () = self#set_filename (Some filename) in
      let parent = Cortex.get (temporary_directory) in
      let result = UnixExtra.temp_dir ~parent ~prefix:"marionnet-" ~suffix:".dir" () in
      let () = self#set_working_directory (Some result) in
      result
    (* --- *)
    (* The project root base name is by default the basename of the filename without
       the extension and without funny (UTF-8) chars (replaced by '_').
       In this way we prevent some troubles with UML and VDE tools. *)
    method private make_a_root_basename_from_filename (filename) : basename =
      let base = (Filename.basename filename) in
      let name = try (Filename.chop_extension base) with _ -> base in
      let result = StrExtra.Global.replace (Str.regexp "[^a-zA-Z0-9_-.]+") (fun _ -> "_") name in
      result
    (* --- *)
    (* Note that this method waits until the filename and the project working directory will be defined. *)
    method set_root_basename_from_filename : basename option =
      let obasename = Option.map (self#make_a_root_basename_from_filename) (self#get_filename) in
      let _ = Cortex.move ~guard:(fun (pwd,_) -> pwd<>None) (data) (fun (x,_) -> (x, obasename)) in
      obasename
    (* --- *)
    (* Create the skeleton of project's directories. The `root_pathname' is the catenation of the
       project-working-directory and the root_basename choosen according to the provided filename. *)
    method make_root_pathname_subdirs : unit =
      let root_pathname = Option.extract (self#root_pathname) in
      let perm = 0o755 in
      let () = Unix.mkdir (root_pathname) perm in
      let () = List.iter (fun x-> Unix.mkdir (root_pathname / x) perm) (self#subdirs) in
      ()
    (* --- *)
    (* Create the temporary subdir local to the project working directory: *)
    method make_local_temp_dir =
      let root_pathname = Option.extract (self#root_pathname) in
      let perm = 0o755 in
      let () = Unix.mkdir (root_pathname / "tmp") perm in
      ()
    (* --- *)
    method private set_filename_and_root_basename ?root_basename ~filename () = begin
      let root_basename =
        Option.extract_or_force (root_basename) (lazy (self#make_a_root_basename_from_filename filename))
      in
      let () = self#set_filename (Some filename) in
      let () = self#set_root_basename (Some root_basename) in
      ()
      end
    (* --- *)
    method change_filename_and_root_basename ?root_basename ~filename () = begin
      let old_root = Option.extract (self#root_pathname) in
      let       () = self#set_filename_and_root_basename ?root_basename ~filename () in
      let new_root = Option.extract (self#root_pathname) in
      Unix.rename (old_root) (new_root);
      end
    (* --- *)
    method reset_and_remove_the_project_working_directory =
      (* Save the value in order to remove this directory as final action: *)
      let opwd = self#get_working_directory in
      let   () = self#unset_filename in
      let   () = self#unset_root_pathname in
      (* --- *)
      let ocmd = Option.map (Printf.sprintf "rm -rf '%s'") (opwd) in
      let   () = Option.iter (Log.printf1 "project_paths#reset_and_remove_the_project_working_directory: %s\n") ocmd in
      let   () = Option.iter (Log.system_or_ignore) (ocmd) in
      ()
    (* --- *)
    method version_file            = self#extract_concat "version"
    method subdirs                 = ["classtest"; "hostfs"; "netmodel"; "scripts"; "states"; "tmp"]
    method subdirs_and_version     = "version"::(self#subdirs)
    method classtestDir            = self#extract_concat "classtest"
    method hostfsDir               = self#extract_concat "hostfs"
    (* --- *)
    method netmodelDir             = self#extract_concat "netmodel"
    method networkFile             = self#netmodelDir       / "network.xml"
    method dotoptionsFile          = self#netmodelDir       / "dotoptions.marshal"
    (* --- *)
    (* The same two files in a `v3 project (work-stream `migration-marshal-to-text'): the same
       data as JSON, under a new name. Renaming is what keeps the backward compatibility: an old
       binary does not *find* these files, hence never hands a text to Marshal.from_file — the
       very trick already used for v1 -> v2. The historical radical is kept and the two
       misleading suffixes (.xml for a Marshal dump, .marshal) disappear. *)
    method networkFile_json        = self#netmodelDir       / "network.json"
    method dotoptionsFile_json     = self#netmodelDir       / "dotoptions.json"
    (* --- *)
    method scriptsDir              = self#extract_concat "scripts"
    method patchesDir              = self#extract_concat "states"
    (* --- *)
    method treeviewDir             = self#possibly_concat "states"
    method treeview_history_file   = self#possibly_concat "states/states-forest"
    method treeview_ifconfig_file  = self#possibly_concat "states/ifconfig"      (* "ports" for bzr revno <= 460 *)
    method treeview_defects_file   = self#possibly_concat "states/defects"
    method treeview_documents_file = self#possibly_concat "states/texts"
    (* --- *)
    (* The data files of a project saved in `v2 or before, as they sit in the working directory.
       A project opened in `v2 and saved in `v3 would otherwise be archived with *both* forms,
       and the older one would be stale: an old binary reads "v3" in the version file, does not
       understand it, falls back on treeview_ifconfig#try_to_understand_..., finds states/ifconfig
       and silently opens the state of before. Hence they are removed when saving (see
       save_project below). The two `v0/`v1 names are listed as well, since a project of that age
       may still carry states/ports next to what its opening produced. *)
    method legacy_data_files : filename list =
      let states = self#extract_concat "states" in
      [ self#networkFile; self#dotoptionsFile;
        states / "states-forest";
        states / "ifconfig"; states / "ifconfig-counters";
        states / "defects";  states / "texts";
        states / "ports";    states / "ports-counters"; ]
    (* --- *)
    method tmpDir                  = self#extract_concat "tmp"
    method dotSketchFile           = self#tmpDir            / "sketch.dot"
    method pngSketchFile           = self#tmpDir            / "sketch.png"
    (* --- *)

  end (* class project_paths *)


(** The class modelling the global state of the application.
    All method with the suffix "_sync" are synchronous and they don't call the task manager.
    In other words, the caller of these methods should ensure the correct order of tasks. *)
class globalState = fun () ->
  (* --- *)
  (* Note that the project working directory will be accessible also from the network structure: *)
  let project_paths = new project_paths () in
  let win           = new Gui.window_MARIONNET () in
  let net =
    new User_level.network
          ~project_working_directory:(fun () -> project_paths#get_working_directory)
          ~project_root_pathname:(fun () -> project_paths#root_pathname)
          ()
  in
  (* --- *)
  object (self)

  (** The main window: *)
  method mainwin = win

  (** The virtual network: *)
  method network = net

  (** Manager of project-related paths: *)
  method project_paths = project_paths

  (** Access methods for the dot options, used for drawing the virtual network. *)
  method dotoptions = net#dotoptions

  (** Show something on statusbar. *)
  method flash ?(delay:int=2000) (msg:string) =
   let statusbar_ctx = win#statusbar#new_context "global" in
   statusbar_ctx#flash ~delay msg

  (** Are we working with an active project? *)
  method active_project = (self#project_paths#get_filename <> None)

  (** Are we working with an active project with some node defined? *)
  method runnable_project =
    self#active_project && (not self#network#is_node_list_empty)

  (* Containers for widgets that must be sensitive when a project is active, runnable or not active: *)
  val sensitive_when_Active   : GObj.widget StackExtra.t = StackExtra.create ()
  val sensitive_when_Runnable : GObj.widget StackExtra.t = StackExtra.create ()
  val sensitive_when_NoActive : GObj.widget StackExtra.t = StackExtra.create ()
  (* --- *)
  method sensitive_when_Active   = sensitive_when_Active
  method sensitive_when_Runnable = sensitive_when_Runnable
  method sensitive_when_NoActive = sensitive_when_NoActive

  val sensitive_cable_menu_entries : GObj.widget StackExtra.t = StackExtra.create ()
  method sensitive_cable_menu_entries = sensitive_cable_menu_entries

 (* The treeview `ifconfig' may be used to derive the informations about the project version
    if necessary. This may be done inspecting the existence and the content of its related files:
    - `v0 is the version of marionnet 0.90.x series
    - `v1 is the version of trunk revno >= 445 with ocamlbricks revno >= 387 (2013/11/17) to trunk revno 460 (included);
          the treeview `ifconfig' is saved in an incompatible (forest) format in states/ports (as in `v0)
    - `v2 is the version of trunk revno >= 461 and marionnet 1.0;
          the treeview `ifconfig' is saved in an incompatible (forest) format in states/ifconfig, in order to prevent
          seg-faults of old binaries reading a new project
    - `v3 is the first version whose data files are text (JSON) instead of Marshal dumps, and are
          named accordingly (netmodel/network.json, states/ifconfig.json, ...); work-stream
          `migration-marshal-to-text'. Same trick as above: an old binary does not find them *)
  (* The raw content of the project's `version' file, when there is one. This is the only thing
     that tells a project written by a more recent Marionnet (an unknown tag, say "v4") from a
     file we cannot identify at all (no tag) — a distinction [opening_project_version] throws
     away by design, but which the error message needs (episode 8b): *)
  method private opening_project_version_tag : string option =
    try PervasivesExtra.get_first_line_of_file (self#project_paths#version_file) with _ -> None

  method opening_project_version : [ `v0 | `v1 | `v2 | `v3 ] option = (* None stands for undefined, i.e. failed to identify *)
    try
      let version = self#opening_project_version_tag in
      match version with
      | Some "v0" -> Some `v0   (* marionnet 0.90.x *)
      | Some "v1" -> Some `v1   (* trunk revno >= 445 with ocamlbricks revno >= 387 (2013/11/17) to trunk revno 460 (included) *)
      | Some "v2" -> Some `v2   (* trunk revno >= 461 and marionnet 1.0 *)
      | Some "v3" -> Some `v3   (* the first version in JSON *)
      | _         -> self#treeview#ifconfig#try_to_understand_in_which_project_version_we_are
    with _ -> None

  (* Project are saved anymway in the newest version: *)
  method closing_project_version : [ `v0 | `v1 | `v2 | `v3 ] = `v3

  method private string_of_project_version : [ `v0 | `v1 | `v2 | `v3 ] -> string =
    function `v0 -> "v0" | `v1 -> "v1" | `v2 -> "v2" | `v3 -> "v3"

  method private project_version_of_string : string -> [ `v0 | `v1 | `v2 | `v3 ] =
    function "v0" -> `v0 | "v1" -> `v1 | "v2" -> `v2 | "v3" -> `v3 | _ -> assert false

  (** New project which will be saved into the given filename.
      This method is synchronous: the caller should ensure the correct order of tasks. *)
  method private private_new_project ~filename () =
    (* First reset the old network, waiting for all devices to terminate: *)
    let () = self#network#ledgrid_manager#reset in
    let () = self#network#reset () in
    (* --- *)
    let _  = self#project_paths#set_filename_and_create_the_project_working_directory (filename) in
    (* In a new project the root_basename is derived from the filename: *)
    let _  = self#project_paths#set_root_basename_from_filename in
    (* Create the skeleton of project's directories. The `root_pathname' is
       the catenation of the project-working-directory and the root_basename
       choosen according to the provided filename. *)
    let () = self#project_paths#make_root_pathname_subdirs in
    (* --- *)
    (* Treeview data should be saved within prefix: *)
    let () = self#clear_treeviews in
    (* Reset dotoptions *)
    let () = self#dotoptions#reset_defaults () in
    (* A brand new project has never been saved (do not inherit the flag from the
       previously opened one): *)
    let () = self#set_project_not_already_saved in
    (* Refresh the network sketch *)
    let () = self#refresh_sketch in
    ()

  (* Interface: *)
  method new_project ~filename =
    GMain_actor.delegate (self#private_new_project ~filename) ()

  (** Close the current project. The project is lost if the user hasn't saved it.
      This method is synchronous: the caller should ensure the correct order of tasks. *)
  method private private_close_project () =
    if (not self#active_project) then Log.printf "state#close_project: no project opened.\n" else (* continue: *)
    begin
      (* --- *)
      Log.printf "state#close_project: BEGIN\n";
      (* --- *)
      (* Anticipate: the user cannot do anything else during this procedure: *)
      let   () = self#project_paths#unset_filename in
      (* Destroy whatever the LEDgrid manager is managing: *)
      let () = self#network#ledgrid_manager#reset in
      let () = self#network#reset (*~scheduled:true*) () in
      (* Update the network sketch (now empty). This method runs in its own thread, so the widget
         call goes through the actor — same discipline as really_refresh_sketch below, and the
         same reason as the treeview mutations (episodes 9 and 10). *)
      let () = GMain_actor.apply_extract (fun () -> self#mainwin#sketch#set_file "") () in
      (* --- *)
      let () = Task_runner.the_task_runner#wait_for_all_currently_scheduled_tasks in
      (* --- *)
      let () = self#project_paths#reset_and_remove_the_project_working_directory in
      (* Clear all treeviews, just in case. *)
      let () = self#clear_treeviews in
      (* --- *)
      Log.printf "state#close_project: END. Success.\n";
      (* --- *)
    end (* close_project *)

  (* Interface: *)
  method close_project =
    if GMain_actor.am_I_the_GTK_main_thread ()
    then Thread.create (self#private_close_project) () |> ignore
    else (self#private_close_project ())

 (** Read the pseudo-XML file containing the network definition. *)
 method import_network
   ?(emergency:(unit->unit)=(fun x->x))
   ?(dotAction:(unit->unit)=fun x->x)
   ~project_version
   (f:filename) =
   begin
    (* Backup the network. *)
    self#network#save_to_buffers;
    (* Plan to restore the network if something goes wrong. *)
    let emergency = fun e ->
          Log.printf1 "state#import_network: emergency (%s)!!!\n" (Printexc.to_string e);
          self#network#restore_from_buffers;
          emergency ()
    in
    (* Read the given file. *)
    (if (UnixExtra.regfile_r_or_link_to f)
    then try
        let result = User_level.Xml.load_network ~project_version self#network f in
        Log.printf ("state#import_network: network imported\n");
        result
    with e -> (emergency e;  raise e)
    else begin
      emergency (Failure "file not readable");
      raise (Failure "state#import_network: cannot open the xml file")
      end
      );
    (* Undump Dot_tuning.network *)
    dotAction ();
    (* Update the network sketch *)
    self#refresh_sketch;
   end

  (** Close the current project and extract the given filename in a fresh project working directory. *)
  method private private_open_project_async ~filename () =
    let () = assert (not (GMain_actor.am_I_the_GTK_main_thread ())) in
    (* --- *)
    begin
    (* First close the current project, if necessary: *)
    let () = Log.printf2 "state#private_open_project_async:  self#project_paths#get_filename=%s  self#active_project=%b\n"
      (Option.to_string ~a:(fun x->x) (self#project_paths#get_filename)) (self#active_project)
    in
    let () = if self#active_project then self#close_project else () in
    (* Set the project filename and create the working directory: *)
    let pwd = self#project_paths#set_filename_and_create_the_project_working_directory (filename) in
    (* --- *)
    let opening_project_progress_bar =
      GMain_actor.apply_extract (fun () ->
        Progress_bar.make_progress_bar_dialog
          ~modal:true
          ~title:(s_ "Work in progress")
          ~text_on_label:(Printf.sprintf "<big><b>%s</b></big>" (s_ "Opening"))
          ~text_on_sub_label:(Printf.sprintf (f_ "<tt><small>%s</small></tt>") filename)
          ())
        ()
    in
    let _ = GMain_actor.delegate (opening_project_progress_bar#show) () in
    (* --- *)
    let synchronous_loading () = begin
      (* --- *)
      (* Extract the mar file into the pwdir *)
      let () =
        let command_line =
          Printf.sprintf "tar -xSvzf '%s' -C '%s'"
            (Option.extract (self#project_paths#get_filename))
            pwd
        in
        (* --- *)
        Log.system_or_fail command_line
      in
      (* --- *)
      (* Look for the name of the root directory of the mar file. Some checks here. *)
      let tarball_root =
	try
	  (match (SysExtra.readdir_as_list pwd) with
	  | [x] ->
              let skel = (SysExtra.readdir_as_list (Filename.concat pwd x)) in
              if ListExtra.subset skel (self#project_paths#subdirs_and_version) then x else (* continue: *)
              failwith "state#open_project_async: no expected content in the project root directory."
	  |  _  ->
	      failwith "state#open_project_async: no rootname found in the project directory."
	  )
	with e -> begin
	  self#close_project;
	  raise e;
	end;
      in
      (* --- *)
      (* In a pre-existent project the root_basename is derived from the tarball: *)
      let () = self#project_paths#set_root_basename (Some tarball_root) in
      (* --- *)
      (* Create the project's tmp subdirectory: *)
      let () = self#project_paths#make_local_temp_dir in
      (* --- *)
      (* Determine the version of the project we are opening: *)
      let project_version : [ `v0 | `v1 | `v2 | `v3 ] =
        match self#opening_project_version with
        | Some v -> v
        | None   -> raise (Unsupported_project_version (self#opening_project_version_tag))
      in
      let project_version_as_string = self#string_of_project_version project_version in
      Log.printf1 "state#open_project_async: project version is %s\n" (project_version_as_string);
      let () =
        if project_version <> self#closing_project_version then
        Simple_dialogs.warning
          (s_ "Project in old file format")
          (s_ "This project will be automatically converted in a format not compatible with previous versions of this software. If you want to preserve compatibility, don't save it or save it with another name.")
         ()
      in
      (* --- *)
      (* Dot_tuning.network will be undumped after the network,
	in order to support cable inversions. *)
      (* Restoring these options commits them, and each commit fires the reaction installed by
         Motherboard_builder, which marks the project as modified — in a thread of its own, hence
         possibly *after* register_state_after_save_or_open below. That race is what made `open`
         answer, now and then, that a correctly loaded project was unsaved (episode 7 of the
         script-driving work-stream). The reaction is therefore suspended here: what is restored
         from the project file is not a modification of it. *)
      let dotAction () =
       self#dotoptions#with_persistence_reaction_suspended (fun () ->
        let () =
	  try
	    let dotoptions_file =
	      match project_version with
	      | `v3            -> self#project_paths#dotoptionsFile_json
	      | `v0 | `v1 | `v2 -> self#project_paths#dotoptionsFile
	    in
	    let () = self#dotoptions#load_from_file ~project_version (dotoptions_file) in
	    Log.printf ("state#open_project_async: dotoptions recovered\n")
	  with e ->
	    begin
	      Log.printf ("state#open_project_async: cannot read the dotoptions file => resetting defaults\n");
	      self#dotoptions#reset_defaults ()
	    end
	in
	self#dotoptions#set_toolbar_widgets ())
      in
      (* --- *)
      Log.printf ("state#open_project_async: calling load_treeviews\n");
      (* Undump treeview's data. Doing this action now we allow components
	 to modify the treeviews according to the marionnet version: *)
      (* Since episode 15 a treeview failing to load is no longer swallowed. Report it, then carry
         on with the network import exactly as before: the point is to make the failure visible,
         not to reorganise the opening. *)
      (try
        self#load_treeviews ~project_version ()
      with e -> begin
        Log.printf1 "state#open_project_async: load_treeviews failed: %s\n" (Printexc.to_string e);
        Simple_dialogs.error
          (s_ "Failed loading the project")
          (Printexc.to_string e)
          ()
        end);
      (* --- *)
      Log.printf ("state#open_project_async: calling import_network\n");
      (* Second, read the xml file containing the network definition.
	 If something goes wrong, close the project. *)
      let import () = begin
        try
          self#import_network
            ~emergency:(fun () -> self#close_project)
            ~dotAction
            ~project_version
            (match project_version with
             | `v3             -> self#project_paths#networkFile_json
             | `v0 | `v1 | `v2 -> self#project_paths#networkFile);
          (* Old projects may have been adapted at loading time (obsolete kernels or
             absent filesystems remapped, see the remap_*_at_import methods in
             user_level.ml): recapitulate the adjustments to the user, if any: *)
          (match self#network#get_and_reset_import_warnings with
          | [] -> ()
          | ws ->
              let items =
                List.map
                  (fun w -> User_level.(w.iw_summary, w.iw_detail, w.iw_severity))
                  ws
              in
              let header =
                Printf.sprintf (f_ "%d automatic adjustment(s) were applied") (List.length ws)
              in
              let preamble =
                s_ "To make this old project loadable on the current system, Marionnet adapted it as shown below.\nClick an item to see the details."
              in
              Simple_dialogs.recapitulative
                ~title:(s_ "Project adapted at loading")
                ~header
                ~preamble
                items
                ())
        with e ->
          self#clear_treeviews;
          Log.printf1 "state#open_project_async: Failed with exception %s\n" (Printexc.to_string e);
          (* Report the failure properly, including the import warnings that may
             explain it (e.g. an abandoned distribution with saved disk states): *)
          let ws = List.map User_level.string_of_import_warning self#network#get_and_reset_import_warnings in
          Simple_dialogs.error
            (s_ "Failed loading the project")
            (String.concat "\n\n" (ws @ [Printexc.to_string e]))
            ()
        end
      in
      let () = GMain_actor.delegate import () in
      (* --- *)
      self#register_state_after_save_or_open;
      (* --- *)
      let () =
        let there_are_world_bridges =
          (self#network#get_nodes_such_that ~devkind:`World_bridge (fun _ -> true)) <> []
        in
        if (there_are_world_bridges) then Global_options.check_bridge_existence_and_warning ()
      in
      (* --- *)
      ()
    end (* function synchronous_loading *)
    in
    (* --- *)
    let _ =
(*      Task_runner.the_task_runner#schedule
        ~name:"state#open_project.synchronous_loading"*)
        (GMain_actor.delegate (fun () ->
	    try
	      synchronous_loading ()
	    with
	    (* A project we cannot open because of its *version* is not a malformed file, and must
	       not be reported as one. Note that the translated sentences below take no argument:
	       the file name and the raw tag are concatenated outside of gettext, so that no
	       translation can break the program by getting a format arity wrong (a failure mode
	       msgfmt -c does not catch). *)
	    | Unsupported_project_version tag as e ->
	      begin
		Log.printf2 "Failed loading the project `%s': unsupported project version (%s).\n"
		  filename
		  (match tag with None -> "no tag" | Some t -> Printf.sprintf "tag `%s'" t);
		let title, explanation =
		  match tag with
		  | Some _ ->
		      (s_ "Project format not supported"),
		      (s_ "This project has been written by a more recent version of Marionnet. Please upgrade Marionnet in order to open it.")
		  | None ->
		      (s_ "Project format not recognized"),
		      (s_ "The format of this project could not be identified. The file may be damaged, or it may not be a Marionnet project at all.")
		in
		let error_msg =
		  Printf.sprintf "<tt><small>%s</small></tt>\n\n%s%s"
		    filename
		    explanation
		    (match tag with None -> "" | Some t -> Printf.sprintf "\n\n<tt>version = %s</tt>" t)
		in
		Simple_dialogs.error title error_msg ();
		raise e;
	      end
	    | e ->
	      begin
		Log.printf1 "Failed loading the project `%s'. The next reported exception is harmless.\n" filename;
		let error_msg =
		  Printf.sprintf "<tt><small>%s</small></tt>\n\n%s"
		    filename
		    (s_ "Please ensure that the file be well-formed.")
		in
		Simple_dialogs.error (s_ "Failed loading the project") error_msg ();
		raise e;
	      end)) ()
    in
    (* Remove now the progress_bar: *)
    let _ =
(*      Task_runner.the_task_runner#schedule
        ~name:"destroy opening project progress bar"*)
        (fun () -> Progress_bar.destroy_progress_bar_dialog (opening_project_progress_bar)) ()
    in
    ()
    end

  (* Interface: *)
  (* NOTE: if the thread is not the gtk_main we don't create another thread: *)
  method open_project_async ~filename : Thread.t =
    if GMain_actor.am_I_the_GTK_main_thread ()
    then Thread.create (self#private_open_project_async ~filename) ()
    else (let () = self#private_open_project_async ~filename () in Thread.self ())

  (* Second version: create a new thread anyway: *)
  method open_project_async_anyway ~filename : Thread.t =
    Thread.create (self#private_open_project_async ~filename) ()


  (*** BEGIN: this part of code tries to understand if the project must be really saved before exiting. *)

  (* Does the persistent model differ from what has been saved (or opened) last time?
     Note that this flag is *not* related to the sketch refreshing: starting, stopping
     or suspending a component redraws the sketch but changes nothing persistent. *)
  val mutable project_dirty = true
  method set_project_not_already_saved =
   project_dirty <- true

  method treeview =
   object
     method ifconfig  = Treeview_ifconfig.extract ()
     method history   = Treeview_history.extract ()
     method defects   = Treeview_defects.extract ()
     method documents = Treeview_documents.extract ()
   end

  method private get_treeview_list : Treeview.t list =
   begin
    let t1 = Treeview_ifconfig.extract () in
    let t2 = Treeview_history.extract () in
    let t3 = Treeview_defects.extract () in
    let t4 = Treeview_documents.extract () in
    [ (t1 :> Treeview.t);
      (t2 :> Treeview.t);
      (t3 :> Treeview.t);
      (t4 :> Treeview.t);
      ]
   end

  (* The three methods below use apply_extract, not `delegate' (episode 15): `delegate' ignores the
     Either it gets back, so a treeview failing to load, save or clear was swallowed twice over —
     once here and once in Treeview#detach_view_in — and, worse, the List.iter silently stopped at
     the failing treeview, leaving the following ones untouched. For save_treeviews that meant a
     .mar written without up-to-date treeview files, and a project reported as saved. *)
  method private load_treeviews ~project_version () =
    GMain_actor.apply_extract
      (List.iter (fun (treeview : Treeview.t) -> treeview#load ~project_version ()))
      (self#get_treeview_list)

  method private save_treeviews =
    GMain_actor.apply_extract
      (List.iter (fun (treeview : Treeview.t) -> treeview#save ()))
      (self#get_treeview_list)

  method private clear_treeviews =
    GMain_actor.apply_extract
      (List.iter (fun (treeview : Treeview.t) -> treeview#clear))
      (self#get_treeview_list)

  method private get_treeview_complete_forest_list =
    GMain_actor.apply_extract
      (List.map (fun (treeview : Treeview.t) -> treeview#get_complete_forest))
      (self#get_treeview_list)

  val mutable treeview_forest_list_after_save = None
  method private register_state_after_save_or_open =
   begin
     project_dirty <- false;
     (* The moment the project becomes clean. Logged on purpose (episode 7 of the script-driving
        work-stream), but beware of what that line proves: Log.printf takes a global mutex before
        writing (log_builder.ml:132-136), so a thread that has already mutated may be waiting for
        it while another mutates and writes. The order of the lines is therefore NOT the order of
        the mutations; the line dates the event, it does not order it. *)
     Log.printf "state#register_state_after_save_or_open: the project is registered as saved\n";
     treeview_forest_list_after_save <- Some (self#get_treeview_complete_forest_list);
   end

  method project_already_saved =
    (* Efficient test: *)
    if project_dirty then begin
      Log.printf "The project is not already saved (the model has been changed).\n";
      false
      end
    else begin
      Log.printf "The project *seems* already saved.\n";
      (* Potentially expensive test, kept as a safety net for whatever the flag may miss: *)
      (* Do NOT "fix" the case which surprises at first sight: after merely starting and stopping
         a machine, the flag is down (nothing the user edited has changed) yet this test answers
         "modified", so Marionnet asks whether to save. That is correct and deliberate — starting
         a machine makes Treeview_history#add_substate_of add a COW disk state, which *is* part of
         what the .mar stores. The audit of episode 0 (B4) assumed the opposite; the assumption
         was wrong, and B4 was closed on that ground at episode 15. *)
      if (treeview_forest_list_after_save = (Some self#get_treeview_complete_forest_list))
      then begin
        Log.printf "The project *is* already saved.\n";
        true
      end
      else begin
        Log.printf "Something has changed in treeviews: the project must be re-saved.\n";
        false
      end
      end

  (*** END: this part of code try to understand if the project must be really saved before exiting. *)

  (** Rewrite the compressed archive prj_filename with the content of the project working directory (pwdir). *)
  method private private_save_project () =
    let () = assert (not (GMain_actor.am_I_the_GTK_main_thread ())) in
    (* --- *)
    if self#active_project then begin
    Log.printf "state#save_project BEGIN\n";
    (* --- *)
    let filename = Option.extract (self#project_paths#get_filename) in
    let project_working_directory, project_root_basename =
      (self#project_paths#extract_working_directory_and_root_basename)
    in
    (* --- *)
    (* Progress bar periodic callback. *)
    let fill =
      (* disk usage (in kb) with the unix command *)
      let du x = match UnixExtra.run (Printf.sprintf "du -sk '%s'" x) with
       | kb, (Unix.WEXITED 0) -> (try Some (float_of_string (List.hd (StringExtra.split ~d:'\t' kb))) with _ -> None)
       | _,_                  -> None
      in
      (* disk usage (in kb) with the unix library *)
      let du_file_in_kb x = try Some (float_of_int ((Unix.stat x).Unix.st_size / 1024)) with _ -> None in
      let round x = float_of_string (Printf.sprintf "%.2f" (if x<1. then x else 1.)) (* workaround strange lablgtk behaviour *) in
      match (du project_working_directory) with
      | Some kb_flatten ->
         fun () -> (match du_file_in_kb filename with
                    | Some kb_compressed -> round (0.05 +. (kb_compressed *. 8.) /. kb_flatten)
                    | None -> 0.5)
      | None -> fun () -> 0.5
    in
    (* --- *)
    let progress_bar =
      GMain_actor.apply_extract (fun () -> begin
      (* --- *)
      let text_about_saved_snapshots =
        match Global_options.Keep_all_snapshots_when_saving.extract () with
        | true  -> s_ "Project with all snapshots"
        | false -> s_ "Project with the most recent snapshots"
      in
      (* --- *)
      let saving_word = (s_ "Saving") in
      let text_on_label =
        Printf.sprintf "<big><b>%s</b></big>\n<small>%s</small>" (saving_word) (text_about_saved_snapshots)
      in
      (* --- *)
      Progress_bar.make_progress_bar_dialog
        ~modal:true
        ~title:(s_ "Work in progress")
        ~kind:(Progress_bar.Fill fill)
        ~text_on_label
        ~text_on_sub_label:(Printf.sprintf (f_ "<tt><small>%s</small></tt>") filename)
        ()
      (* --- *)
      end) ()
    in
    (* --- *)
    (* Since episode 15 `save_treeviews' propagates the failures it used to swallow (see the
       comment on it above), and so do the other steps below. Two consequences are handled here:
       (1) whatever happens, the *modal* progress bar must be destroyed, or the GUI would be left
       unusable; (2) only a save which ran to completion may register the state and report
       success — otherwise the project would be believed saved while its .mar is incomplete.
       The failure is caught right here rather than in the callers because `save_project' below
       runs this body in a thread of its own when called from the GTK main thread, where an
       escaping exception would simply kill that thread, silently. *)
    try
      Fun.protect
        ~finally:(fun () -> Progress_bar.destroy_progress_bar_dialog (progress_bar))
        (fun () -> begin
          (* --- *)
          (* Write the rc scripts of the components into states/, and sweep the ones no
             component claims any more. BEFORE the network file, which carries their basenames
             (work-stream `migration-marshal-to-text', episode 5; see User_level.Rc_files). *)
          self#network#save_rc_files;
          (* --- *)
          (* Write the network file (JSON since `v3, hence the new name) *)
          User_level.Xml.save_network (self#network) (self#project_paths#networkFile_json);
          (* --- *)
          (* Save also dotoptions for drawing image. *)
          self#dotoptions#save_to_file (self#project_paths#dotoptionsFile_json);
          (* --- *)
          (* Save treeviews (just to play it safe, because treeview files should be automatically)
             re-written at every update): *)
          self#save_treeviews;
          (* --- *)
          (* Save the project's version: *)
          let project_version_as_string = self#string_of_project_version (self#closing_project_version) in
          UnixExtra.put (self#project_paths#version_file) (project_version_as_string);
          (* --- *)
          (* A project opened in `v2 (or before) still has its old data files in the working
             directory, and they are now stale: remove them, or the archive built below would
             carry both forms and an old binary would happily open the older one (see the comment
             on `legacy_data_files'). Removing an absent file is not an error here — this is the
             ordinary case of a project which was already `v3. *)
          List.iter
            (fun file ->
               if Sys.file_exists file then begin
                 Log.printf1 "state#save_project: removing the stale v2 file %s\n" file;
                 try Unix.unlink file with e ->
                   Log.printf2 "state#save_project: cannot remove %s: %s\n" file (Printexc.to_string e)
                 end)
            (self#project_paths#legacy_data_files);
          (* --- *)
          (* (Re)write the .mar file *)
          let cmd =
            let exclude_command_section =
              let excluded_cows = self#treeview#history#get_files_may_not_be_saved in
              let excluded_items = List.map (Printf.sprintf "--exclude states/%s") excluded_cows in
              String.concat " " ("--exclude tmp"::excluded_items)
            in
            Printf.sprintf "tar -cSvzf '%s' -C '%s' %s '%s'"
              filename
              project_working_directory
              exclude_command_section
              project_root_basename
          in
          (* --- *)
          let _ =
            (*Task_runner.the_task_runner#schedule
              ~name:"tar"*)
              ((*fun () ->*) Log.system_or_ignore cmd)
          in
          (* --- *)
          ()
        end);
      (* --- *)
(*     let () = Task_runner.the_task_runner#wait_for_all_currently_scheduled_tasks in (*!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!*) *)
      self#register_state_after_save_or_open;
      Log.printf "state#save_project END. Success.\n";
      (* --- *)
    with e -> begin
      Log.printf1 "state#save_project END. FAILED: %s\n" (Printexc.to_string e);
      (* The project is deliberately left marked as modified. *)
      Simple_dialogs.error
        (s_ "Save")
        ((s_ "Failed to save the project into the file ") ^ filename)
        ()
      end
  end

  (* Interface: *)
  method save_project =
    if GMain_actor.am_I_the_GTK_main_thread ()
    then Thread.create (self#private_save_project) () |> ignore
    else (self#private_save_project ())


  (** Update the project filename to the given string, and save: *)
  method save_project_as ?root_basename ~filename () =
    if self#active_project then begin
      try
        (* Set the project filename, name and root_basename: *)
        self#project_paths#change_filename_and_root_basename ?root_basename ~filename ();
        (* Save the project *)
        self#save_project;
      with e -> (raise e)
    end

  (** Save the project into the given file, but without changing its name in the
      copy we're editing. Implemented by temporarily updating the name, saving
      then switch back to the old name. *)
  method copy_project_into ?root_basename ~filename () =
    if self#active_project then begin
      try
        let filename0      = Option.extract (self#project_paths#get_filename) in
        let root_basename0 = Option.extract (self#project_paths#get_root_basename) in
        (* Set the project filename, name and root_basename: *)
        let () = self#project_paths#change_filename_and_root_basename ?root_basename ~filename () in
        (* Save the project *)
        let () = self#save_project in
        (* Revert to the previous names: *)
        let () = self#project_paths#change_filename_and_root_basename ~root_basename:(root_basename0) ~filename:(filename0) () in
        ()
      with e -> (raise e)
    end

  method private really_refresh_sketch =
    GMain_actor.delegate (fun () -> begin
    let () = Log.printf "About to refresh the sketch\n" in
    let fs = self#project_paths#dotSketchFile in
    let ft = self#project_paths#pngSketchFile in
    try begin
      let ch = open_out fs in
      output_string ch (self#network#dotTrad ());
      close_out ch;
      let cmdline =
        let splines = string_of_bool (Cortex.get self#network#dotoptions#curved_lines) in (* Appel de methode Cortex !!!!!!!!!!!!!!! *)
        Printf.sprintf "dot -Gsplines=%s -Efontname=FreeSans -Nfontname=FreeSans -Tpng -o '%s' '%s' 2>/dev/null" splines ft fs
      in
      let exit_code = Sys.command cmdline in
      (* --- *)
      self#mainwin#sketch#set_file (self#project_paths#pngSketchFile);
      (* --- *)
      (if not (exit_code = 0) then
        Simple_dialogs.error
          (s_ "dot failed")
          (Printf.sprintf
              (f_ "Invoking dot failed. Did you install graphviz?\n\
    The command line is\n%s\nand the exit code is %i.\n\
    Marionnet will work, but you will not see the network graph picture until you fix the problem.\n\
    There is no need to restart the application.")
              cmdline
              exit_code)
          ());
        end
      with e ->
        (Log.printf1
           "Warning: exception raised in really_refresh_sketch:\n%s\nIgnoring.\n"
           (Printexc.to_string e))
    end) ()

  (* The structure (counter) for the reactive sketch refreshing. It is purely internal:
     nothing but the rendering depends on it (in particular, not `project_already_saved'). *)
  val refresh_sketch_counter = Cortex.return 0

  (* Provoke the refreshing simply incrementing the counter (the on_commit reaction is defined elsewhere) *)
  method refresh_sketch =
   let _ = Cortex.move (refresh_sketch_counter) (fun x -> x+1) in ()

  (* --- *)
  method network_change : 'a. ('a -> unit) -> 'a -> unit =
  fun action obj ->
   GMain_actor.delegate (fun () ->
   begin
    action obj;
    self#dotoptions#shuffler_reset;
    self#dotoptions#extrasize_reset;
    (* A network change (adding, removing or updating a component) is a change of the
       persistent model, unlike a mere state transition of a component: *)
    self#set_project_not_already_saved;
    self#refresh_sketch;
   end) ()

 (* Begin of methods moved from talking.ml *)
 method make_names_and_thunks ?(node_list=self#network#get_node_list) (verb) (what_to_do_with_a_node) =
  List.map
    (fun node -> (
      (verb ^ " " ^ node#get_name),
      (fun () ->
	let progress_bar =
          GMain_actor.apply_extract (fun () -> begin
            Simple_dialogs.make_progress_bar_dialog
              ~title:(verb ^ " " ^ node#get_name)
              ~text_on_bar:(s_ "Wait please...")
              ()
	    end) ()
	in
	(* B6 (work-stream "marionnet-automate-composants"): the exception used to be swallowed here,
	   hence the task runner announced that the task "succeeded" while the component had not
	   started at all — silently, with nothing on screen. It is still logged with its backtrace,
	   and the progress bar is still destroyed, but the failure is now propagated: the task runner
	   reports it as a failure and goes on with the next task, exactly as it does for any other
	   failing task. *)
	let failure =
	  try (what_to_do_with_a_node node; None)
	  with e -> begin
	    let raw_backtrace = Printexc.get_raw_backtrace () in
	    let () = Log.printf3 "Warning (q): \"%s %s\" raised an exception (%s)\n" verb node#name (Printexc.to_string e) in
	    let () = Log.print_backtrace () in
	    Some (e, raw_backtrace)
	  end
	in
	let () = GMain_actor.delegate (Simple_dialogs.destroy_progress_bar_dialog) (progress_bar) in
	(match failure with
	 | None -> ()
	 | Some (e, raw_backtrace) -> Printexc.raise_with_backtrace e raw_backtrace)
	))
    )
    node_list

 method do_something_with_every_node_in_sequence ?node_list (verb) (what_to_do_with_a_node) =
  List.iter
    (fun (name, thunk) -> Task_runner.the_task_runner#schedule ~name thunk)
    (self#make_names_and_thunks ?node_list verb what_to_do_with_a_node)

 method do_something_with_every_node_in_parallel ?node_list (verb) (what_to_do_with_a_node) =
  Task_runner.the_task_runner#schedule_parallel
    (self#make_names_and_thunks ?node_list verb what_to_do_with_a_node);;

 method startup_everything () =
  self#do_something_with_every_node_in_sequence
    ~node_list:(self#network#get_nodes_that_can_startup ())
    "Startup" (fun node -> node#startup_right_now)

 method shutdown_everything () =
  self#do_something_with_every_node_in_parallel
    ~node_list:(self#network#get_nodes_that_can_gracefully_shutdown ())
    "Shut down"
    (fun node -> node#gracefully_shutdown_right_now)

 method poweroff_everything () =
 (* self#do_something_with_every_node_in_sequence *)
  self#do_something_with_every_node_in_parallel
    ~node_list:(self#network#get_nodes_that_can_gracefully_shutdown ())
    "Power-off"
    (fun node -> node#poweroff_right_now)

(** Return true iff there is some node on or sleeping *)
 method is_there_something_on_or_sleeping () =
  let result =
    List.exists
      (fun node -> node#can_gracefully_shutdown || node#can_resume)
      (self#network#get_node_list)
  in
  begin
   Log.printf1 "is_there_something_on_or_sleeping: %s\n" (if result then "yes" else "no");
   result
  end

 (* End of functions moved from talking.ml *)

 (* When quit_async is called we have to quit really (for instance in a signal callback): *)
 val mutable quit_async_called = false
 method quit_async_called = quit_async_called

 method quit_async () =
   let quit () =
     begin
      Log.printf "Starting the last job...\n";
      self#network#destroy_process_before_quitting ();
      Log.printf "Killing the blinker thread...\n";
      self#network#ledgrid_manager#kill_blinker_thread;
      Log.printf "Ok, the blinker thread was killed.\n";
      flush_all ();
      Log.printf "Synced.\n";
      Log.printf "state#quit: done.\n";
      GtkMain.Main.quit ();
     end
   in
   begin
   quit_async_called <- true;
   Task_runner.the_task_runner#schedule ~name:"quit" (GMain_actor.delegate quit);
   Log.printf "Main thread: quit has been scheduled.\n";
   end

 initializer
    let _ = Cortex.on_commit_append (refresh_sketch_counter) (fun _ _ -> self#really_refresh_sketch) in
    ()

end;; (* class globalState *)
