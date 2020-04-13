(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007-2012  Jean-Vincent Loddo, Luca Saiu

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

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

IFNDEF OCAML4_04_OR_LATER THEN
let lowercase = String.lowercase
ELSE
let lowercase = String.lowercase_ascii
ENDIF

(** More sophisticated version of [Sys.getenv].
The result is None if and only if something goes wrong in retrieving
and converting the value from the environment
(key not present, or associated to the empty string, or associated
to a value which hasn't the expected type or doesn't verify the condition
implicitely denoted by the method name).

{b Examples}:
{[# (meaningful_getenv "HOME")#existing_directory ;;
  : string option = Some "/home/foo"

# (meaningful_getenv "TMPDIR")#existing_directory ;;
  : string option = None

# (meaningful_getenv "TMPDIR")#non_empty_string ;;
  : string option = None
]}
**)
let meaningful_getenv x =
  let ov =
    try
      (match Sys.getenv x with
      | "" -> None
      | v  -> Some v
      )
    with Not_found -> None
  in
  object
    method non_empty_string = ov
    method int   = try Option.map int_of_string ov with _ -> None
    method float = try Option.map float_of_string ov with _ -> None
    method bool  = try Option.map (fun v -> bool_of_string (lowercase v)) ov with _ -> None
    method existing_file = Option.filter (Sys.file_exists) ov
    method existing_directory = try Option.filter (Sys.is_directory) ov with _ -> None
  end


(** Reads a given directory, thus select and convert names. Returns the list of formatted names. *)
let readdir_as_list
  ?only_directories
  ?only_not_directories
  ?(name_filter:(string->bool)=(fun x -> true))
  ?(name_converter:(string->string)=(fun x->x))
  (dir:string) =
  try begin
    let filelist  = (Array.to_list (Sys.readdir dir)) in
    let first_filter =
      match only_directories, only_not_directories with
      | None, None    -> (fun x -> true)
      | Some (), None -> Sys.is_directory
      | None, Some () -> (fun x -> not (Sys.is_directory x))
      | Some (), Some () -> invalid_arg "SystExtra.readdir_as_list: ?only_directories and ?only_not_directories both set."
    in
    let safe_name_filter = (fun name -> (try (name_filter name) with _ -> false)) in
    let selected_items =
      List.filter (fun x -> (first_filter (dir^"/"^x)) && (safe_name_filter x)) filelist
    in
    List.map name_converter selected_items
  end with
  | (Invalid_argument msg) as e -> raise e
  |  _ -> []

(** [put content filename] rewrite [filename] with the given [content] string.
    An optional [~callback] may be provided in order to catch the
    exception [(Sys_error msg)]. By default, the callback
    print the [msg] on [stderr] and exit from program with the exit code [1]. *)
let put =
 let std_callback msg = ((Printf.eprintf "%s" msg); exit 1) in
 fun ?(callback=std_callback) (content:string) (filename:string) ->
 (try
  let out_channel = open_out filename in
  (Printf.fprintf out_channel "%s" content);
  (close_out out_channel);
 with Sys_error msg -> callback msg)


(* Note: list built using "kill -l" on a GNU/Linux: *)
let signal_list = [
  (1,"SIGHUP");        (2,"SIGINT");       (3,"SIGQUIT");      (4,"SIGILL");
  (5,"SIGTRAP");       (6,"SIGABRT");      (7,"SIGBUS");       (8,"SIGFPE");
  (9,"SIGKILL");      (10,"SIGUSR1");     (11,"SIGSEGV");     (12,"SIGUSR2");
  (13,"SIGPIPE");     (14,"SIGALRM");     (15,"SIGTERM");     (16,"SIGSTKFLT");
  (17,"SIGCHLD");     (18,"SIGCONT");     (19,"SIGSTOP");     (20,"SIGTSTP");
  (21,"SIGTTIN");     (22,"SIGTTOU");     (23,"SIGURG");      (24,"SIGXCPU");
  (25,"SIGXFSZ");     (26,"SIGVTALRM");   (27,"SIGPROF");     (28,"SIGWINCH");
  (29,"SIGIO");       (30,"SIGPWR");      (31,"SIGSYS");      (34,"SIGRTMIN");
  (35,"SIGRTMIN+1");  (36,"SIGRTMIN+2");  (37,"SIGRTMIN+3");  (38,"SIGRTMIN+4");
  (39,"SIGRTMIN+5");  (40,"SIGRTMIN+6");  (41,"SIGRTMIN+7");  (42,"SIGRTMIN+8");
  (43,"SIGRTMIN+9");  (44,"SIGRTMIN+10"); (45,"SIGRTMIN+11"); (46,"SIGRTMIN+12");
  (47,"SIGRTMIN+13"); (48,"SIGRTMIN+14"); (49,"SIGRTMIN+15"); (50,"SIGRTMAX-14");
  (51,"SIGRTMAX-13"); (52,"SIGRTMAX-12"); (53,"SIGRTMAX-11"); (54,"SIGRTMAX-10");
  (55,"SIGRTMAX-9");  (56,"SIGRTMAX-8");  (57,"SIGRTMAX-7");  (58,"SIGRTMAX-6");
  (59,"SIGRTMAX-5");  (60,"SIGRTMAX-4");  (61,"SIGRTMAX-3");  (62,"SIGRTMAX-2");
  (63,"SIGRTMAX-1");  (64,"SIGRTMAX");
];;

let the_SIGRTMIN_and_SIGRTMAX_descr = "Real-time signal for application-defined purposes"
;;

type default_actions = Term | Core | Stop | Cont | Ign  ;;
let string_of_default_action = function
 | Term -> "Term" | Core -> "Core" | Stop -> "Stop" | Cont -> "Cont" | Ign -> "Ign"
;;

(* Source: http://www.kernel.org/doc/man-pages/online/pages/man7/signal.7.html *)
let signal_description_list = [
  ("SIGHUP",      ("POSIX.1-1990", Term, "Hangup detected on controlling terminal or death of controlling process"));
  ("SIGINT",      ("POSIX.1-1990", Term, "Interrupt from keyboard"));
  ("SIGQUIT",     ("POSIX.1-1990", Core, "Quit from keyboard"));
  ("SIGILL",      ("POSIX.1-1990", Core, "Illegal Instruction"));
  ("SIGABRT",     ("POSIX.1-1990", Core, "Abort signal from abort(3)"));
  ("SIGFPE",      ("POSIX.1-1990", Core, "Floating point exception"));
  ("SIGKILL",     ("POSIX.1-1990", Term, "Kill signal"));
  ("SIGSEGV",     ("POSIX.1-1990", Core, "Invalid memory reference"));
  ("SIGPIPE",     ("POSIX.1-1990", Term, "Broken pipe: write to pipe with no readers"));
  ("SIGALRM",     ("POSIX.1-1990", Term, "Timer signal from alarm(2)"));
  ("SIGTERM",     ("POSIX.1-1990", Term, "Termination signal"));
  ("SIGUSR1",     ("POSIX.1-1990", Term, "User-defined signal 1"));
  ("SIGUSR2",     ("POSIX.1-1990", Term, "User-defined signal 2"));
  ("SIGCHLD",     ("POSIX.1-1990", Ign,  "Child stopped or terminated"));
  ("SIGCONT",     ("POSIX.1-1990", Cont, "Continue if stopped"));
  ("SIGSTOP",     ("POSIX.1-1990", Stop, "Stop process"));
  ("SIGTSTP",     ("POSIX.1-1990", Stop, "Stop typed at tty"));
  ("SIGTTIN",     ("POSIX.1-1990", Stop, "tty input for background process"));
  ("SIGTTOU",     ("POSIX.1-1990", Stop, "tty output for background process"));
  ("SIGBUS",      ("POSIX.1-2001", Core, "Bus error (bad memory access)"));
  ("SIGPOLL",     ("POSIX.1-2001", Term, "Pollable event (Sys V). Synonym for SIGIO"));
  ("SIGPROF",     ("POSIX.1-2001", Term, "Profiling timer expired"));
  ("SIGSYS",      ("POSIX.1-2001", Core, "Bad argument to routine (SVr4)"));
  ("SIGTRAP",     ("POSIX.1-2001", Core, "Trace/breakpoint trap"));
  ("SIGURG",      ("POSIX.1-2001", Ign,  "Urgent condition on socket (4.2BSD)"));
  ("SIGVTALRM",   ("POSIX.1-2001", Term, "Virtual alarm clock (4.2BSD)"));
  ("SIGXCPU",     ("POSIX.1-2001", Core, "CPU time limit exceeded (4.2BSD)"));
  ("SIGXFSZ",     ("POSIX.1-2001", Core, "File size limit exceeded (4.2BSD)"));
  ("SIGIOT",      ("NOT-IN-POSIX", Core, "IOT trap. A synonym for SIGABRT"));
  ("SIGEMT",      ("NOT-IN-POSIX", Term, ""));
  ("SIGSTKFLT",   ("NOT-IN-POSIX", Term, "Stack fault on coprocessor (unused)"));
  ("SIGIO",       ("NOT-IN-POSIX", Term, "I/O now possible (4.2BSD)"));
  ("SIGCLD",      ("NOT-IN-POSIX", Ign,  "A synonym for SIGCHLD"));
  ("SIGPWR",      ("NOT-IN-POSIX", Term, "Power failure (System V)"));
  ("SIGINFO",     ("NOT-IN-POSIX", Term, "A synonym for SIGPWR"));
  ("SIGLOST",     ("NOT-IN-POSIX", Term, "File lock lost"));
  ("SIGWINCH",    ("NOT-IN-POSIX", Ign,  "Window resize signal (4.3BSD, Sun)"));
  ("SIGUNUSED",   ("NOT-IN-POSIX", Core, "Synonymous with SIGSYS"));
  ("SIGRTMIN",    ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+1",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+2",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+3",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+4",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+5",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+6",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+7",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+8",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+9",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+10", ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+11", ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+12", ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+13", ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+14", ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMIN+15", ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-14", ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-13", ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-12", ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-11", ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-10", ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-9",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-8",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-7",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-6",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-5",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-4",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-3",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-2",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX-1",  ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
  ("SIGRTMAX",    ("POSIX.1-2001", Term, the_SIGRTMIN_and_SIGRTMAX_descr));
];;

(* A global structures for rapid access to signal informations: *)
let name_of_signal =
  let module Map = MapExtra.Destructive.Int_map in
  let m = Map.create () in
  let () = List.iter (fun (i,n) -> Map.add i n m) signal_list in
  fun i -> Map.find i m

let description_of_signal =
  let module Map = MapExtra.Destructive.String_map in
  let m = Map.create () in
  let () = List.iter (fun (i,n) -> Map.add i n m) signal_description_list in
  fun i -> Map.find i m

(** Convert the signal in an integer as indicated by [kill -l] on a GNU/Linux. *)
let int_of_signal = function
 | x when x=Sys.sigabrt   -> 6
 | x when x=Sys.sigalrm   -> 14
 | x when x=Sys.sigfpe    -> 8
 | x when x=Sys.sighup    -> 1
 | x when x=Sys.sigill    -> 4
 | x when x=Sys.sigint    -> 2
 | x when x=Sys.sigkill   -> 9
 | x when x=Sys.sigpipe   -> 13
 | x when x=Sys.sigquit   -> 3
 | x when x=Sys.sigsegv   -> 11
 | x when x=Sys.sigterm   -> 15
 | x when x=Sys.sigusr1   -> 10
 | x when x=Sys.sigusr2   -> 12
 | x when x=Sys.sigchld   -> 17
 | x when x=Sys.sigcont   -> 18
 | x when x=Sys.sigstop   -> 19
 | x when x=Sys.sigtstp   -> 20
 | x when x=Sys.sigttin   -> 21
 | x when x=Sys.sigttou   -> 22
 | x when x=Sys.sigvtalrm -> 26
 | x when x=Sys.sigprof   -> 27
 | x -> x


(** Convert the signal in a string as indicated by [kill -l] on a GNU/Linux. *)
let name_of_signal = function
 | x when x=Sys.sigabrt -> "SIGABRT"
 | x when x=Sys.sigalrm -> "SIGALRM"
 | x when x=Sys.sigfpe  -> "SIGFPE"
 | x when x=Sys.sighup  -> "SIGHUP"
 | x when x=Sys.sigill  -> "SIGILL"
 | x when x=Sys.sigint  -> "SIGINT"
 | x when x=Sys.sigkill -> "SIGKILL"
 | x when x=Sys.sigpipe -> "SIGPIPE"
 | x when x=Sys.sigquit -> "SIGQUIT"
 | x when x=Sys.sigsegv -> "SIGSEGV"
 | x when x=Sys.sigterm -> "SIGTERM"
 | x when x=Sys.sigusr1 -> "SIGUSR1"
 | x when x=Sys.sigusr2 -> "SIGUSR2"
 | x when x=Sys.sigchld -> "SIGCHLD"
 | x when x=Sys.sigcont -> "SIGCONT"
 | x when x=Sys.sigstop -> "SIGSTOP"
 | x when x=Sys.sigtstp -> "SIGTSTP"
 | x when x=Sys.sigttin -> "SIGTTIN"
 | x when x=Sys.sigttou -> "SIGTTOU"
 | x when x=Sys.sigvtalrm -> "SIGVTALRM"
 | x when x=Sys.sigprof -> "SIGPROF"
 | x ->
    (try
       name_of_signal x
     with Not_found -> (string_of_int (int_of_signal x)))

let signal_behavior i =
  let result = Sys.signal i Sys.Signal_default in
  let () = Sys.set_signal i result in
  result

(* We don't synchronize with other threads in order to prevent possible (even if quite improbable) deadlocks.
   Actually there is a possible perverse situation: a thread may be interrupted by a signal exactly when it
   was printing using the module Log, and exactly during the short critical section of the ordinary mutex used
   to implement the recursive mutex used in Log... *)
module Log = Ocamlbricks_log.Unprotected

let fold_on_signals ?(except=[]) ?(caller="fold_on_signals") f s =
  let rec loop s i =
    if i > 64 then s else
    if i = 32 then loop s (i+2) else (* 32 and 33 are meaningless *)
    if List.mem i except then loop s (i+1) else
    let s' = try
      let b = signal_behavior i in
      f s i b
      with Sys_error _ ->
        let n = name_of_signal i in
        Log.printf "%s: skipping to apply the function to signal %2d (%s)\n" caller i n;
        s
    in
    loop s' (i+1)
  in loop s 1

let iter_on_signals ?except f =
  fold_on_signals ?except ~caller:"iter_on_signals" (fun () i b -> f i b) ()

let wrap_signal_receptions ?except ?also_ignored ?also_core_dumped wrapper =
  let simulated_handler_of_default_action = function
  | Ign  when also_ignored<>None ->
      Some ignore
  | Term ->
      Some (fun i -> exit (128+(int_of_signal i)))
  | Core when also_core_dumped<>None ->
      Some (fun i -> Sys.set_signal i Sys.Signal_default; Unix.kill (Unix.getpid ()) i)
  | _ -> None
  in
  iter_on_signals ?except begin
    fun i behavior ->
       let signo = int_of_signal i in
       let name  = name_of_signal signo in
       let (_, action, descr) = description_of_signal name in
       match behavior with
       | Sys.Signal_handle current_handler -> Sys.set_signal i (wrapper ~signo ~name ~descr ~current_handler)
       | Sys.Signal_ignore                 -> Sys.set_signal i (wrapper ~signo ~name ~descr ~current_handler:ignore)
       | Sys.Signal_default ->
           (match simulated_handler_of_default_action action with
           | None -> ()
           | Some current_handler -> Sys.set_signal i (wrapper ~signo ~name ~descr ~current_handler)
           )
    end

let log_signal_reception ?except () =
  let wrapper ~signo ~name ~descr ~current_handler =
    Sys.Signal_handle
      (fun i ->
	 Log.printf "Received signal %d (%s): %s\n" signo name descr;
         current_handler i)
  in
  wrap_signal_receptions ?except ~also_core_dumped:() ~also_ignored:() wrapper


let description_of_name name =
  let (posix, action, descr) = description_of_signal name in
  (posix, (string_of_default_action action), descr)

(* Redefined in order to have an integer as input and only strings in the result: *)
let description_of_signal i =
  let signo = int_of_signal i in
  let name  = name_of_signal signo in
  let (posix, action, descr) = description_of_signal name in
  (name, posix, (string_of_default_action action), descr)

(* Redefined in order to remove the ?caller parameter: *)
let fold_on_signals ?except f s = fold_on_signals ?except f s

(* For 64-bits architectures is 8 (bytes), for 32-bits ones is 4 (bytes).
   Calculated at loading time: *)
IFDEF OCAML4_03_OR_LATER THEN
let bytes_per_int =
  let dpi = int_of_float ((log (float_of_int max_int)) /. (log 2.)) in
  let k = dpi / 8 in
  if dpi mod 8 = 0 then k else (k+1)
ELSE
let bytes_per_int =
  let dpi = Sys.int_size in
  let k = dpi / 8 in
  if dpi mod 8 = 0 then k else (k+1)
ENDIF


IFDEF DOCUMENTATION_OR_DEBUGGING THEN
module Test = struct
(* May be tested from the shell:
$ make test \<\<\<"SysExtra.Test.log_signal_reception () ;;" 2>/tmp/test.log
$ grep Received /tmp/test.log
*)
let log_signal_reception () =
  iter_on_signals begin fun i b ->
    let _ =
      ThreadExtra.fork_with_tutor
	~before_waiting:(fun ~pid ->
	  Log.printf "Trying to send the signal No. %d to %d\n" i pid;
          ThreadExtra.delay 0.5; (* cannot be interrupted by a signal *)
	  Unix.kill pid i)
	(fun () ->
           log_signal_reception ();
	   Log.printf "In pause...\n";
	   Thread.delay 1.)
	()
    in
    ThreadExtra.delay 1.;
    Log.printf "=======================================\n";
    ()
    end

end (* module Test *)
ENDIF
