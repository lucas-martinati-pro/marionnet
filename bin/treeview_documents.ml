(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008, 2009  Luca Saiu
   Copyright (C) 2009, 2010  Jean-Vincent Loddo
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

(* Authors:
 * - Luca Saiu: initial version
 * - Jean-Vincent Loddo: Unix.system calls replaced by UnixExtra's functions
     calls, and some other minor changes
 *)

(* --- *)
module Log = Marionnet_log
module Option = Ocamlbricks.Option
module UnixExtra = Ocamlbricks.UnixExtra
module StringExtra = Ocamlbricks.StringExtra
module FilenameExtra = Ocamlbricks.FilenameExtra
module Stateful_modules = Ocamlbricks.Stateful_modules
module Egg = Ocamlbricks.Egg
(* --- *)

open Gettext
module Row_item = Treeview.Row_item

(* --- *)
(* Ex: Some "Jean-Vincent Loddo" *)
let get_full_user_name () : string option =
  let user = Sys.getenv "USER" in
  let cmd = Printf.sprintf "getent passwd %s | cut -d: -f 5 | cut -d, -f 1" user in
  match UnixExtra.run cmd with
  | (full_name, Unix.WEXITED 0) -> Some (StringExtra.chop full_name)
  | _ -> None
(* --- *)

(* Deep logging, episode 8: turning a typescript into something a corrector can read.

   What script(1) records is what the terminal RECEIVED, escape sequences included: colours,
   cursor moves, the erasures a shell performs while the student edits a line. Replayed by
   scriptreplay(1) it is exactly the session; opened in a text editor it is unreadable. So the
   raw file stays where it is — the channel serves it, and the timing file beside it makes the
   replay possible — and what the exam mode archives is this filtered copy.

   Deliberately a filter and not a terminal emulator: erasures are NOT applied (a line the
   student retyped appears twice rather than once). Reconstructing the final screen would mean
   emulating a terminal, and would silently delete what a corrector may precisely want to see. *)
module Terminal_recording = struct

  (* ESC [ ... <final byte in 0x40..0x7e> (CSI), ESC ] ... BEL|ST (OSC), and the two-character
     escapes. A lone '\r' becomes a newline (progress bars), the '\r' of a "\r\n" pair goes. *)
  let strip (s : string) : string =
    let n = String.length s in
    let b = Buffer.create n in
    let i = ref 0 in
    while !i < n do
      let c = s.[!i] in
      if c = '\027' && !i + 1 < n then begin
        match s.[!i + 1] with
        | '[' ->
            let j = ref (!i + 2) in
            while !j < n && (s.[!j] < '\064' || s.[!j] > '\126') do incr j done;
            i := (if !j < n then !j + 1 else n)
        | ']' ->
            let j = ref (!i + 2) in
            let stop = ref false in
            while not !stop && !j < n do
              if s.[!j] = '\007' then (incr j; stop := true)
              else if s.[!j] = '\027' && !j + 1 < n && s.[!j + 1] = '\\' then (j := !j + 2; stop := true)
              else incr j
            done;
            i := !j
        | _ -> i := !i + 2
      end
      else if c = '\r' then begin
        if !i + 1 < n && s.[!i + 1] = '\n' then incr i    (* the CR of a CRLF pair *)
        else (Buffer.add_char b '\n'; incr i)
      end
      else (Buffer.add_char b c; incr i)
    done;
    Buffer.contents b

  (* The readable copy sits beside the raw file, with the extension the documents treeview knows
     (`.text'). Returning the raw path on failure is on purpose: archiving an unreadable session
     beats archiving nothing at all, and the exam mode must never raise at shutdown. *)
  let readable_copy_of ~(pathname:string) : string =
    let destination = (Filename.remove_extension pathname) ^ ".text" in
    try
      UnixExtra.rewrite destination (strip (UnixExtra.cat pathname));
      destination
    with e ->
      Log.printf2 "Treeview_documents: cannot make a readable copy of %s: %s\n"
        pathname (Printexc.to_string e);
      pathname

end (* module Terminal_recording *)

(* Deep logging, episode 10: reading the report the guest wrote.

   The end-of-session report is Markdown (episode 7: its producer is plain Bash inside a minimal
   guest, where an unescaped `<' would silently break an HTML page), and until now a double-click
   opened it in MARIONNET_TEXT_EDITOR -- readable, not rendered.

   WHY THE CONVERSION IS IN-PROCESS (cmarkit) and not delegated to whichever converter the host
   happens to have. Two properties, and both of them matter for a document which may be GRADED:

   - the rendering is THE SAME EVERYWHERE. The student, the teacher and the corrector open the
     same archive and see the same page. A chain of external candidates (pandoc, cmark, ...)
     would make the page depend on the machine which opens it, and nothing on that page would
     say which converter produced it.

   - `~safe:true' NEUTRALIZES raw HTML. report.md is written INSIDE the guest, i.e. on a machine
     the student controls; without this, a `<script>' dropped into the report would run in the
     page the corrector opens.

   The operator keeps an explicit way out: MARIONNET_MARKDOWN_TO_HTML, when set, receives the
   Markdown on its standard input and its output is used instead (`pandoc -f markdown -t html'
   and its richer rendering, typically). It is then a DECISION, not a side effect of what happens
   to be installed -- and it gives up the two properties above, which is why the configuration
   file says so. *)
module Markdown_rendering = struct

  let is_markdown (pathname:string) : bool =
    List.mem (String.lowercase_ascii (Filename.extension pathname)) [".md"; ".markdown"]

  (* Deliberately minimal: a report is read, not browsed. Monospace where the guest wrote command
     outputs, visible borders (the report of episode 7 has tables), and a width which does not
     force the eye to travel across a maximized window. *)
  let stylesheet = "\
body { max-width: 50em; margin: 2em auto; padding: 0 1em; line-height: 1.5;
       font-family: sans-serif; }
h1, h2, h3 { line-height: 1.2; margin-top: 1.5em; }
h1, h2 { border-bottom: 1px solid #ccc; padding-bottom: .2em; }
code, pre { font-family: monospace, monospace; }
pre { background: #f6f6f6; border: 1px solid #ddd; padding: .6em; overflow-x: auto; }
table { border-collapse: collapse; }
th, td { border: 1px solid #bbb; padding: .2em .6em; text-align: left; }
blockquote { border-left: 3px solid #ccc; margin-left: 0; padding-left: 1em; color: #555; }
p.omitted { color: #a00; font-style: italic; }
"

  let escape (s:string) : string =
    let b = Buffer.create (String.length s) in
    String.iter
      (function
       | '&' -> Buffer.add_string b "&amp;"
       | '<' -> Buffer.add_string b "&lt;"
       | '>' -> Buffer.add_string b "&gt;"
       | '"' -> Buffer.add_string b "&quot;"
       | c   -> Buffer.add_char b c)
      s;
    Buffer.contents b

  (* The envelope is OURS whatever the converter, hence `pandoc' without `-s': one page layout,
     one charset declaration, one stylesheet -- and a converter which forgets the charset (most
     of them emit a fragment) cannot turn the accents of a French report into mojibake. *)
  let page ~(title:string) ~(fragment:string) : string =
    Printf.sprintf
      "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n<title>%s</title>\n<style>\n%s</style>\n</head>\n<body>\n%s</body>\n</html>\n"
      (escape title) stylesheet fragment

  (* MEASURED, and it changes what the reader sees: `~safe:true' does not ESCAPE raw HTML, it
     DROPS it, leaving `<!-- CommonMark HTML block omitted -->' -- a comment, hence invisible in a
     browser. A corrector would read a report with a silent hole in it. So the hole is made
     visible; and what the guest actually wrote stays reachable, one gesture away, through "show
     the source" of this same episode.

     The pattern follows the renderer, whose output the library documents as unstable: should a
     future cmarkit change its wording, this stops matching and we are back to the invisible
     comment -- a degradation, not a breakage -- and the bench of the episode turns red, which is
     the point of asserting on the visible marker rather than on the comment. *)
  let omission = Str.regexp "<!-- CommonMark \\([A-Za-z ]+\\) omitted -->"
  let omission_marker =
    "<p class=\"omitted\">[ raw HTML written by the guest, omitted here: see the source ]</p>"

  let by_cmarkit (markdown:string) : string =
    (* ~strict:false enables the non-strict extensions, tables among them: the report of episode 7
       is written with tables, and strict CommonMark would render them as paragraphs. *)
    let fragment = Cmarkit_html.of_doc ~safe:true (Cmarkit.Doc.of_string ~strict:false markdown) in
    Str.global_replace omission omission_marker fragment

  (* Failure is never fatal here: whatever goes wrong we fall back on cmarkit, and the user gets
     a page instead of an explanation. The command is run through a shell, so an absent program
     is just a non-zero status (127) -- no need to look for it in the PATH ourselves. *)
  let by_external_command ~(command:string) ~(markdown:string) : string option =
    try
      match UnixExtra.run ~input:markdown command with
      | (output, Unix.WEXITED 0) when String.trim output <> "" -> Some output
      | (_, _) ->
          Log.printf1 "Markdown_rendering: MARIONNET_MARKDOWN_TO_HTML (%s) failed: using cmarkit\n"
            command;
          None
    with e ->
      Log.printf2 "Markdown_rendering: MARIONNET_MARKDOWN_TO_HTML (%s) raised %s: using cmarkit\n"
        command (Printexc.to_string e);
      None

  let fragment_of ~(markdown:string) : string =
    match Configuration.get_string_variable "MARIONNET_MARKDOWN_TO_HTML" with
    | None -> by_cmarkit markdown
    | Some command ->
        (match by_external_command ~command ~markdown with
         | Some fragment -> fragment
         | None -> by_cmarkit markdown)

  (* The rendered page is written OUTSIDE the project: the documents directory is what goes into
     the .mar, and a rendering is not a document -- it is recomputed at every reading. Returning
     [None] on failure is what keeps the historical behaviour reachable (the text editor). *)
  let html_copy_of ~(title:string) ~(pathname:string) : string option =
    try
      let markdown = UnixExtra.cat pathname in
      let content = page ~title ~fragment:(fragment_of ~markdown) in
      Some (UnixExtra.temp_file
              ~parent:(Filename.get_temp_dir_name ())
              ~prefix:"marionnet-document-" ~suffix:".html" ~content ())
    with e ->
      Log.printf2 "Markdown_rendering: cannot render %s: %s\n" pathname (Printexc.to_string e);
      None

end (* module Markdown_rendering *)

class t =
fun ~packing
    ~method_directory
    ~method_filename
    ~after_user_edit_callback
    () ->
object(self)
  inherit
    Treeview.t
      ~packing
      ~method_directory
      ~method_filename
      ~hide_reserved_fields:true
      ()
  (* as super *)

  val icon_header = "Icon"
  method get_row_icon = self#get_Icon_field (icon_header)
  method set_row_icon = self#set_Icon_field (icon_header)

  val title_header = "Title"
  method get_row_title = self#get_String_field (title_header)
  method set_row_title = self#set_String_field (title_header)

  val author_header = "Author"
  method get_row_author = self#get_String_field (author_header)
  method set_row_author = self#set_String_field (author_header)

  val type_header = "Type"
  method get_row_type = self#get_String_field (type_header)
  method set_row_type = self#set_String_field (type_header)

  val comment_header = "Comment"
  method get_row_comment = self#get_String_field (comment_header)
  method set_row_comment = self#set_String_field (comment_header)

  val filename_header = "FileName"
  method get_row_filename = self#get_String_field (filename_header)
  method set_row_filename = self#set_String_field (filename_header)

  val format_header = "Format"
  method get_row_format = self#get_String_field (format_header)
  method set_row_format = self#set_String_field (format_header)

  (** Display the document at the given row, in an asynchronous process: *)
  method private display row_id =
    let frmt = self#get_row_format (row_id) in
    let pathname = Filename.concat (self#directory) (self#get_row_filename row_id) in
    (* Deep logging, episode 10: a Markdown document is shown RENDERED. It is recognized by its
       name, not by the `Format' column, which stays "text" on purpose (episode 7): no format
       value which an older Marionnet could not read ever reaches a .mar file. The counterpart is
       that a document imported BEFORE this episode has no extension at all (see [import_file]),
       and keeps opening in the text editor -- the behaviour it had. *)
    let (reader, pathname) =
      if frmt = "text" && Markdown_rendering.is_markdown pathname then
        match Markdown_rendering.html_copy_of ~title:(self#get_row_title row_id) ~pathname with
        | Some html_pathname -> (self#format_to_reader "html", html_pathname)
        | None               -> (self#format_to_reader frmt, pathname)
      else
        (self#format_to_reader frmt, pathname)
    in
    let command_line =
      Printf.sprintf "%s '%s'&" reader pathname in
    (* Here ~force:true would be useless, because of '&' (the shell well exit in any case). *)
    Log.system_or_ignore command_line

  (* Deep logging, episode 10: show the SOURCE of a Markdown document, and let it be edited. The
     rendered page answers "what does the report say", this answers "what exactly did the guest
     write" -- and gives the corrector a place to annotate it.

     Modifying a document of a .mar which serves as evidence takes nothing away: the archive is in
     the student's hands anyway, and `exam-mode.md' has been saying since episode 9 which journals
     are falsifiable. What this adds is the annotation of a report BY THE CORRECTOR.

     Threads: the window is created here, i.e. in the callback of the contextual menu, so from the
     main thread. [Egg.wait] blocks, hence the separate thread -- which writes a file (no Gtk+
     call) and then goes back through the actor for the treeview callback, which touches widgets
     (work-stream `refonte-automate-composants'). Same pattern as gui_bricks.ml:990. *)
  method private edit_source row_id =
    let pathname = Filename.concat (self#directory) (self#get_row_filename row_id) in
    (* Concatenation rather than a format string, like the [import_*] methods below: a translated
       format string with a wrong arity breaks at run time, in silence (work-stream i18n). *)
    let title = (s_ "Source of ") ^ (self#get_row_title row_id) in
    let content = try UnixExtra.cat pathname with _ -> "" in
    let result : (string option) Egg.t = Egg.create () in
    let () =
      Gui_source_editing.window
        ~title
        ~language:(`id "markdown")
        ~content
        ~result
        ~draw_spaces:[]
        (* Closing the window discards: unlike the configuration editor this one WRITES a file of
           the project, and a window closed by mistake must not commit anything. *)
        ~close_means_cancel:()
        ()
    in
    ignore (Thread.create
      (fun () ->
         match Egg.wait result with
         | None -> ()
         | Some text when text = content -> ()
         | Some text ->
             (try
                (* Imported documents are deposited read-only (see [import_file]), so saving means
                   opening the file, writing it, and closing it again. *)
                UnixExtra.set_perm ~u:() ~w:true pathname;
                UnixExtra.rewrite pathname text;
                UnixExtra.set_perm ~a:() ~w:false pathname;
                Log.printf1 "Treeview_documents: %s has been edited\n" pathname;
                (* Marks the project as not already saved (marionnet.ml:124). *)
                GMain_actor.apply_extract self#run_after_update_callback row_id
              with e ->
                Log.printf2 "Treeview_documents: cannot save %s: %s\n"
                  pathname (Printexc.to_string e)))
      ())

  val error_message =
    (s_ "You should select an existing document in PDF, Postscript, DVI, HTML or text format.")

  (** Ask the user to choose a file, and return its pathname. Fail if the user doesn't
      choose a file or cancels: *)
  method (* private *) ask_file : string option =
    let dialog = GWindow.file_chooser_dialog
        ~icon:Icon.icon_pixbuf
        ~action:`OPEN
        ~title:((*utf8*)(s_ "Choose the document to import"))
        ~modal:true ()
    in
    dialog#add_button_stock `CANCEL `CANCEL;
    dialog#add_button_stock `OK `OK;
    dialog#unselect_all;
    dialog#add_filter
      (GFile.filter
         ~name:(s_ "Texts (PDF, PostScript, DVI, HTML, text)")
         ~patterns:["*.pdf"; "*.ps"; "*.dvi"; "*.text"; "*.txt"; "*.html"; "*.htm"; "README";
                    (s_ "README") (* it's nice to also support something like LISEZMOI... *)]
         ());
    dialog#set_default_response `OK;
    (* --- *)
    (match dialog#run () with
      `OK ->
        (match dialog#filename with
          Some result ->
            dialog#destroy ();
            Log.printf1 "* Ok: \"%s\"\n" result;
            Some result
        | None -> begin
            dialog#destroy ();
            Log.printf "* No document was selected\n";
            None
          end)
    | _ ->
        dialog#destroy ();
        Log.printf "* You cancelled\n";
        None)

  method private file_to_format pathname =
    if Filename.check_suffix pathname ".html" ||
      Filename.check_suffix pathname ".htm" ||
      Filename.check_suffix pathname ".HTML" ||
      Filename.check_suffix pathname ".HTM" then
      "html"
    else if Filename.check_suffix pathname ".md" ||
      Filename.check_suffix pathname ".MD" ||
      Filename.check_suffix pathname ".markdown" then
      (* Deep logging, episode 7: the end-of-session report of a guest is Markdown, because its
         producer is plain Bash inside a minimal guest (an unescaped '<' would silently break an
         HTML page, a fenced block cannot break). Mapped onto the EXISTING "text" format on
         purpose: no new format value reaches a .mar file, and [format_to_reader] keeps its five
         cases. Reading it as rendered Markdown from the GUI is a work-stream episode of its own. *)
      "text"
    else if Filename.check_suffix pathname ".text" ||
      Filename.check_suffix pathname ".txt" ||
      (* Deep logging, episode 7: the console journal Marionnet records for a guest is
         <name>-console.log, and the exam mode archives it. Text it is. *)
      Filename.check_suffix pathname ".log" ||
      Filename.check_suffix pathname ".LOG" ||
      Filename.check_suffix pathname "readme" ||
      Filename.check_suffix pathname "lisezmoi" ||
      Filename.check_suffix pathname ".TEXT" ||
      Filename.check_suffix pathname ".TXT" ||
      Filename.check_suffix pathname "README" ||
      Filename.check_suffix pathname "LISEZMOI" then
      "text"
    else if Filename.check_suffix pathname ".ps" ||
      Filename.check_suffix pathname ".eps" ||
      Filename.check_suffix pathname ".PS" ||
      Filename.check_suffix pathname ".EPS" then
      "ps"
    else if Filename.check_suffix pathname ".dvi" ||
      Filename.check_suffix pathname ".DVI" then
      "dvi"
    else if Filename.check_suffix pathname ".pdf" ||
      Filename.check_suffix pathname ".PDF" then
      "pdf"
    else
      failwith ("I cannot recognize the file type of " ^ pathname);

  (* Deep logging, episode 10: a reader which is not installed used to mean that NOTHING happened
     at all. [display] appends `&', so the shell exits 0 whatever the command was, and
     [Log.system_or_ignore] has nothing to report. The historical default of MARIONNET_HTML_READER
     is `galeon', a browser dead since ~2010 and absent from any current distribution: the page
     rendered by this episode would have opened nowhere. So the configured reader is now CHECKED,
     and a list of candidates takes over when it is absent -- which also repairs the installed
     marionnet.conf of a user who never touched it.

     The configured value may carry options (`firefox --new-window'), hence the test on its first
     word only, the value itself being passed on unchanged. *)
  method private resolve_reader ~(configured:string) ~(candidates:string list) : string =
    let program_of command =
      match String.split_on_char ' ' (String.trim command) with
      | program :: _ -> program
      | []           -> ""
    in
    if UnixExtra.is_executable (program_of configured) then configured else
    match List.find_opt UnixExtra.is_executable candidates with
    | Some fallback ->
        Log.printf2 "Treeview_documents: the reader \"%s\" is not installed: using \"%s\"\n"
          configured fallback;
        fallback
    | None ->
        Log.printf1
          "Treeview_documents: the reader \"%s\" is not installed, and no candidate either\n"
          configured;
        configured

  method private format_to_reader format =
    let configured ~default varname = Configuration.extract_string_variable_or ~default varname in
    (* `xdg-open' comes first in every list: it is what a desktop session actually honours. *)
    let document_candidates = ["xdg-open"; "evince"; "okular"; "atril"; "mupdf"] in
    let browser_candidates  = ["xdg-open"; "sensible-browser"; "x-www-browser"; "firefox"; "chromium"] in
    (* Never a terminal editor here: it would open no window at all. *)
    let editor_candidates   = ["xdg-open"; "sensible-editor"; "gedit"; "kate"; "emacs"] in
    match format with
    | "pdf"  -> self#resolve_reader ~candidates:document_candidates
                  ~configured:(configured ~default:"evince" "MARIONNET_PDF_READER")
    | "ps"   -> self#resolve_reader ~candidates:document_candidates
                  ~configured:(configured ~default:"evince" "MARIONNET_POSTSCRIPT_READER")
    | "dvi"  -> self#resolve_reader ~candidates:document_candidates
                  ~configured:(configured ~default:"evince" "MARIONNET_DVI_READER")
      (* 'file' may recognize (X)HTML as XML... *)
    | "html" -> self#resolve_reader ~candidates:browser_candidates
                  ~configured:(configured ~default:"xdg-open" "MARIONNET_HTML_READER")
    | "text" -> self#resolve_reader ~candidates:editor_candidates
                  ~configured:(configured ~default:"emacs"  "MARIONNET_TEXT_EDITOR")
      (* the file type in unknown: web browsers can open most everything... *)
    | "auto" -> self#resolve_reader ~candidates:browser_candidates
                  ~configured:(configured ~default:"xdg-open" "MARIONNET_HTML_READER")
    | _ ->
      failwith ("The format \"" ^ format ^ "\" is not supported");

  (** Import the given file, copying it into the appropriate directory with a fresh name;
      return the fresh name (just the file name, not a complete pathname) and the name
      of an application suitable to read it, as a pair. In case of failure show an error
      message and raise an exception. If ~move is true then the file is moved instead of
      copied. *)
  method private import_file ?(move=false) pathname =
    try
      let file_format    = self#file_to_format pathname in
      let parent         = self#directory in
      (* Deep logging, episode 10: the imported copy KEEPS the extension of its source. Until now
         it was named `document-XXXXXX', so nothing at display time could tell a Markdown report
         from any other text -- and the `Format' column deliberately says "text" for both
         (episode 7). Kept conservative: an extension which is not a plain word is dropped, since
         this name ends up in a shell command line ([display]). *)
      let suffix =
        let e = String.lowercase_ascii (Filename.extension pathname) in
        let plain c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || (c = '.') in
        if e <> "" && String.length e <= 12 && String.for_all plain e then e else ""
      in
      let fresh_pathname = UnixExtra.temp_file ~parent ~prefix:"document-" ~suffix () in
      let fresh_name     = Filename.basename fresh_pathname in
      let result         = (fresh_name, file_format) in
     (try
      (match move with
      | false -> UnixExtra.file_copy pathname fresh_pathname
      | true  -> UnixExtra.file_move pathname fresh_pathname
      );
      UnixExtra.set_perm ~a:() ~w:false fresh_pathname;
      Log.Command.ll fresh_pathname;
      result
      with Unix.Unix_error (_,_, _) ->
       begin
         UnixExtra.apply_ignoring_Unix_error Unix.unlink fresh_pathname;
         let title =
           Printf.sprintf "Failed copying the file \n\"%s\"\n" pathname in
         failwith title;
       end)
     with (Failure title) as e -> begin
      Simple_dialogs.error title error_message ();
      raise e (* Re-raise *)
    end

  (* Deep logging, episode 8. Copied like the console, and for the same reason (the channel keeps
     serving the raw file under `log <c> terminal'), but through a filter: what is archived is a
     READABLE version of the session. The raw typescript, and the timing file beside it, stay in
     the project directory for scriptreplay(1). *)
  method import_terminal ~machine_or_router_name ~pathname () =
    let title = (s_ "Terminal of ") ^ machine_or_router_name in
    let readable = Terminal_recording.readable_copy_of ~pathname in
    let row_id = self#import_document ~move:true readable in
    self#set_row_title   row_id title;
    self#set_row_author  row_id "-";
    self#set_row_type    row_id (s_ "Terminal");
    self#set_row_comment row_id ((s_ "created on ") ^ (UnixExtra.date ~dot:" " ()));

  (* COPIED, not moved (episode 8, once [move] started working): the file lives in a hostfs the
     next boot recreates anyway, and taking it away would make `log <c> rc_config' — or, below,
     `log <c> commands' — answer nothing at all after a graceful shutdown in exam mode. *)
  method import_report ~machine_or_router_name ~pathname () =
    let title = (s_ "Report on ") ^ machine_or_router_name in
    let row_id = self#import_document ~move:false pathname in
    self#set_row_title   row_id title;
    self#set_row_author  row_id "-";
    self#set_row_type    row_id (s_ "Report");
    self#set_row_comment row_id ((s_ "created on ") ^ (UnixExtra.date ~dot:" " ()));

  method import_history ~machine_or_router_name ~pathname () =
    let title = (s_ "History of ") ^ machine_or_router_name in
    let row_id = self#import_document ~move:false pathname in
    self#set_row_title   row_id title;
    self#set_row_author  row_id "-";
    self#set_row_type    row_id (s_ "History");
    self#set_row_comment row_id ((s_ "created on ") ^ (UnixExtra.date ~dot:" " ()));

  (* Deep logging, episode 7. COPIED, not moved, unlike its two siblings: the console journal is
     a file of the HOST (<project>/<name>-console.log, simulation_level.ml), and the channel keeps
     serving it under `log <c> console' after the machine is off (episode 6). The other two live
     in the hostfs, which the next boot overwrites anyway. *)
  method import_console ~machine_or_router_name ~pathname () =
    let title = (s_ "Console of ") ^ machine_or_router_name in
    let row_id = self#import_document ~move:false pathname in
    self#set_row_title   row_id title;
    self#set_row_author  row_id "-";
    self#set_row_type    row_id (s_ "Console");
    self#set_row_comment row_id ((s_ "created on ") ^ (UnixExtra.date ~dot:" " ()));

  (* THE single gesture of the exam mode, called by machine.ml AND router.ml (deep logging,
     episode 7). Before this episode each of them spelled its own imports out, and they disagreed:
     a machine imported the report and the history, a router only the report -- an asymmetry with
     no technical motive, since a router has a shell too.

     Every import is guarded by the existence of the file, and that guard is the point: without
     it, shutting a machine down in exam mode raises inside [import_file] and pops up an error
     dialog, which is exactly what happened for years -- the importer was alive, the producer was
     not. A journal that a given guest does not produce (an old image whose shutdown sequence
     never runs, a session recording no console) must cost nothing at shutdown. *)
  method import_exam_documents ~machine_or_router_name ~hostfs_directory ~console_pathname
                               ~terminal_pathname () =
    let import what pathname =
      if Sys.file_exists pathname then
        try what ~machine_or_router_name ~pathname () with e ->
          Log.printf2 "Treeview_documents: exam mode: importing %s failed: %s\n"
            pathname (Printexc.to_string e)
      else
        Log.printf2 "Treeview_documents: exam mode: %s has no %s to import\n"
          machine_or_router_name pathname
    in
    (* The listing is worth its line: this archiving runs at the very end of a shutdown, when the
       project directory may already be on its way out, and "no report to import" then means two
       very different things — the guest wrote none, or there is no directory left to look into. *)
    Log.printf2 "Treeview_documents: exam mode: %s: hostfs holds [%s]\n" machine_or_router_name
      (try String.concat " " (Array.to_list (Sys.readdir hostfs_directory))
       with e -> "unreadable: " ^ (Printexc.to_string e));
    import (self#import_report)  (Filename.concat hostfs_directory "report.md");
    import (self#import_history) (Filename.concat hostfs_directory "bash_history.text");
    import (self#import_console) (console_pathname);
    import (self#import_terminal) (terminal_pathname);

  (* [move] was accepted here and DROPPED on the way down since it exists: [import_file] has the
     parameter that does the work, and this method never passed it, so every import has always
     been a copy — including the two of episode 7 which ask for a move. Fixed while measuring
     episode 8; the intentions of the callers were revised at the same time, since honouring the
     flag changes what they do (see [import_report] and its siblings). *)
  method import_document ?(move=false) user_path_name =
    let internal_file_name, format = self#import_file ~move user_path_name in
    let row_id =
      self#add_row
        [ filename_header, Row_item.String internal_file_name;
          format_header,   Row_item.String format ]
    in
    let title = Filename.chop_extension (Filename.basename user_path_name) in
    let otype = FilenameExtra.get_extension user_path_name in
    let oauth = get_full_user_name () in
    let () = self#set_row_title (row_id) title in
    let () = Option.iter (self#set_row_type   row_id) otype in
    let () = Option.iter (self#set_row_author row_id) oauth in
    row_id

  initializer
    let _ =
      self#add_icon_column
        ~header:icon_header
        ~shown_header:(s_ "Icon")
        ~strings_and_pixbufs:[ "text", Initialization.Path.images^"treeview-icons/text.xpm"; ]
        ~default:(fun () -> Row_item.Icon "text")
        () in
    let _ =
      self#add_editable_string_column
        ~header:title_header
        ~shown_header:(s_ "Title")
        ~italic:true
        ~default:(fun () -> Row_item.String "Please edit this")
        () in
    let _ =
      self#add_editable_string_column
        ~header:author_header
        ~shown_header:(s_ "Author")
        ~italic:false
        ~default:(fun () -> Row_item.String "Please edit this")
        () in
    let _ =
      self#add_editable_string_column
        ~header:type_header
        ~shown_header:(s_ "Type")
        ~italic:false
        ~default:(fun () -> Row_item.String "Please edit this")
        () in
    let _ =
      self#add_editable_string_column
        ~shown_header:(s_ "Comment")
        ~header:"Comment"
        ~italic:true
        ~default:(fun () -> Row_item.String "Please edit this")
        () in
    let _ =
      self#add_string_column
        ~header:"FileName"
        ~hidden:true
        () in
    let _ =
      self#add_string_column
        ~header:"Format"
        ~default:(fun () -> Row_item.String "auto") (* unknown format; this is usefule for
                                              backward-compatibility, as this column
                                              didn't exist in older Marionnet versions *)
        ~hidden:true
        () in
    (* Make internal data structures: no more columns can be added now: *)
    self#create_store_and_view;

    (* Setup the contextual menu: *)
    self#set_contextual_menu_title "Texts operations";
    self#add_menu_item
      (s_ "Import a document")
      (fun _ -> true)
      (fun _ ->
        ignore (Option.map self#import_document self#ask_file));

    self#add_menu_item
      (s_ "Display this document")
      Option.to_bool
      (fun selected_rowid_if_any ->
        let row_id = Option.extract selected_rowid_if_any in
        self#display row_id);
    self#set_double_click_on_row_callback (fun row_id -> self#display row_id);

    (* Deep logging, episode 10: the choice between the rendered document and its source, as two
       gestures rather than a dialog asking the question at every reading. The predicate makes
       this entry appear on Markdown rows only (an item whose predicate is false is not built at
       all, treeview.ml:853), so nothing changes for the other documents. The double-click, above,
       keeps the reading gesture: the rendered page. *)
    self#add_menu_item
      (s_ "Show and edit the source of this document")
      (function
       | Some row_id -> Markdown_rendering.is_markdown (self#get_row_filename row_id)
       | None        -> false)
      (fun selected_rowid_if_any ->
        let row_id = Option.extract selected_rowid_if_any in
        self#edit_source row_id);

    self#add_menu_item
      (s_ "Remove this document")
      Option.to_bool
      (fun selected_rowid_if_any ->
        let row_id = Option.extract selected_rowid_if_any in
        let file_name = (self#get_row_filename row_id) in
        let pathname = Filename.concat (self#directory) (file_name) in
        UnixExtra.apply_ignoring_Unix_error Unix.unlink pathname;
        self#remove_row row_id;
        );

     (* J.V. *)
     self#set_after_update_callback after_user_edit_callback;

end;;

class treeview = t
module The_unique_treeview = Stateful_modules.Variable (struct
  type t = treeview
  let name = Some "treeview_documents"
  end)
let extract = The_unique_treeview.extract


(* Add the button "Import" at right side of the treeview. *)
let add_import_button ~(window:GWindow.window) ~(hbox:GPack.box) ~(toolbar:GButton.toolbar) (treeview:t) : unit =
  (*let packing = toolbar#add in*)
  let packing = Gui_bricks.make_toolbar_packing_function (toolbar) in
  (* --- *)
  let b = Gui_bricks.button_image (*~window*) ~packing ~stock:`ADD ~stock_size:`SMALL_TOOLBAR ~tooltip:(s_ "Import a document") () in
  (* --- *)
  (* Behaviour on click: *)
  let callback () = ignore (Option.map treeview#import_document treeview#ask_file) in
  let () = ignore (b#connect#clicked ~callback) in
  ()

let make ~(window:GWindow.window) ~(hbox:GPack.box) ~after_user_edit_callback ~method_directory ~method_filename () =
  let result = new t ~packing:(hbox#add) ~after_user_edit_callback ~method_directory ~method_filename () in
  let toolbar = Treeview.add_expand_and_collapse_button ~window ~hbox (result:>Treeview.t) in
  let _import = add_import_button ~window ~hbox ~toolbar (result) in
  The_unique_treeview.set result;
  result
;;

