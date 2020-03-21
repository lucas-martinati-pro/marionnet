(* This file is part of ocamlbricks
   Copyright (C) 2013  Jean-Vincent Loddo

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

module Process = struct

  type program = string
  type arguments = string list

  type pid = int
  type birthtime = float (* since 00:00:00 GMT, Jan. 1, 1970, in seconds *)
  type age = float (* duration, in seconds *)
  type exit_code = int
  type signal_name = string

  type mrproper = unit -> unit (* to close channels *)

  (* Process options: *)
  type options = {
    mutable stdin  : Endpoint.Source.t;
    mutable stdout : Endpoint.Sink.t;
    mutable stderr : Endpoint.Sink.t;
    mutable pseudo : string option;
    }

  let make_defaults () = {
    stdin  = Endpoint.Source.Empty;
    stdout = Endpoint.Sink.Trash;
    stderr = Endpoint.Sink.Trash;
    pseudo = None;
    }

  let make_options ?enrich ?stdin ?stdout ?stderr ?pseudo () =
    let t = match enrich with None -> make_defaults () | Some t -> t in
    Option.iter (fun x -> t.stdin  <- x) stdin;
    Option.iter (fun x -> t.stdout <- x) stdout;
    Option.iter (fun x -> t.stderr <- x) stderr;
    Option.iter (fun x -> t.pseudo <- Some x) pseudo;
    t

  type tuning = unit -> options

  module State = struct

    type running_state =
    | Running
    | Suspended

    type t =
    | Planned    of tuning * program * arguments
    | Started    of program * birthtime * pid * mrproper * running_state
    | Terminated of program * age * pid * (signal_name, exit_code) Either.t

    (* Mrproper is a pain, the standard equality will raise
       an exception (functional value), so it must be redefined: *)
    let equality x y =
      match (x,y) with
      | Started (n,d,p,_,r), Started (n',d',p',_,r') -> (n=n') && (d=d') && (p=p') && (r=r')
      | Started (_,_,_,_,_), _ | _, Started (_,_,_,_,_) -> false
      (* tuning is also a pain: *)
      | Planned (t,n,a) , Planned (t',n',a') -> (t==t') && (n=n') && (a=a')
      | x,y -> x=y

    let is_planned = function
      | Planned (_,_,_) -> true
      | _ -> false

    let is_started = function
      | Started (_,_,_,_,_) -> true
      | _ -> false

    let is_suspended = function
      | Started (_,_,_,_, Suspended) -> true
      | _ -> false

    let is_not_suspended = function
      | Started (_,_,_,_, Suspended) -> false
      | _ -> true

    let is_running = function
      | Started (_,_,_,_, Running) -> true
      | _ -> false

    let is_terminated = function
      | Terminated (_,_,_,_) -> true
      | _ -> false

    let is_terminated_and_has_been_really_executed = function
      | Terminated (program, _, pid, Either.Right (127))
          when not (UnixExtra.is_executable program) -> false
      | Terminated (_,_,_,_) -> true
      | _ -> false

    let is_terminated_aged_at_least ~seconds =
      if seconds < 0. then invalid_arg "Process.State.is_terminated_aged_at_least: negative age" else
      function
      | Terminated (_, age, _,_) -> (age >= seconds)
      | _ -> false

    let birthtime = function
      | Started (_,birthtime,_,_,_) -> Some birthtime
      | _ -> None

    let age = function
      | Terminated (_, age, _,_) -> Some age
      | _ -> None

  end (* Process.State *)

  type t = State.t Cortex.t
  type u = State.t Cortex.u

  module Open = struct

    let plan
      ?(tuning = fun () -> make_options ())
      (program:string)
      (arguments:string list)
      : u
      =
	(* Set some transitions as forbidden (for instance, when terminal states are reached): *)
	let on_proposal s0 s1 =
	  match (s0,s1) with
	  | State.Terminated (_,_,_,_)   , _ -> s0
	  | State.Started (_,_,_,_,_) , State.Planned (_,_,_) -> s0
	  | _, _ -> s1
	in
	Cortex.Open.return
	  ~equality:State.equality
	  ~on_proposal
	  (State.Planned (tuning, program, arguments))

   end (* module Open *)

  let plan ?tuning program arguments : t =
    Cortex.Open.close (Open.plan ?tuning program arguments)

  (* Is a cortex evaluation, so it propose a transition that may be accepted or not,
     as may be observable by the caller in the result: *)
  let start t : (State.t * bool) =
    let transition = function
    | State.Planned (tuning, program, arguments) ->
        let t = tuning () in
	let (stdin,  stdin_must_be_closed ) = Endpoint.Source.to_file_descr t.stdin in
	let (stdout, stdout_must_be_closed) = Endpoint.Sink.to_file_descr t.stdout  in
	let (stderr, stderr_must_be_closed) = Endpoint.Sink.to_file_descr t.stderr  in
	let name = match t.pseudo with None -> program | Some name -> name in
	let argv = (Array.of_list (name :: arguments)) in
	(* Channels' treatment: *)
        let mrproper () =
          begin
	    (if  stdin_must_be_closed then try Unix.close stdin with _ -> ());
	    (if stdout_must_be_closed then try Unix.close stdout with _ -> ());
	    (if stderr_must_be_closed then try Unix.close stderr with _ -> ());
	  end
	in
	let birthtime = Unix.time () in
        let pid = Unix.create_process program argv stdin stdout stderr in
	State.Started (program, birthtime, pid, mrproper, State.Running)
    | state -> state
    in (* end of transition() *)
    (* main of start() *)
    let (state', changed) = Cortex.move t transition in
    let () =
      if not changed then () else
      match state' with
      | State.Started (program, birthtime, pid, mrproper, State.Running) ->
	  let _thread =
	    ThreadExtra.waitpid_thread
	      (* --- *)
	      ~perform_when_suspended:
	        (fun ~pid ->
	           Cortex.set t (State.Started (program, birthtime, pid, mrproper, State.Suspended)))
	      (* --- *)
	      ~perform_when_resumed:
	        (fun ~pid ->
	           Cortex.set t (State.Started (program, birthtime, pid, mrproper, State.Running)))
	      (* --- *)
	      ~after_waiting:
		(fun ~pid status ->
		    let () = mrproper () in
		    let exiting_info =
		      match status with
		      | Unix.WSIGNALED signal -> Either.Left (SysExtra.name_of_signal signal)
		      | Unix.WEXITED code     -> Either.Right code
		      | _ -> assert false
		    in
		    let age = (Unix.time ()) -. birthtime in
		    Cortex.set t (State.Terminated (program, age, pid, exiting_info)))
	      (* --- *)
	      ()
	      ~pid
	  in
	  ()
      | _ -> ()
    in
    (state', changed)

  let suspend ?nohang t : (State.t * bool) =
    let action = function
    | State.Started (_,_,pid,_, State.Running) as state -> (Unix.kill pid Sys.sigstop; state)
    | state -> state
    in
    let state = Cortex.apply t action in
    (* Now wait until the pause will be observed: *)
    let (state, changed) =
      match (State.is_running state) && (nohang = None) with
      | true  -> (Cortex.get ~guard:State.is_suspended t, true)
      | false -> (state, false)
    in
    (state, changed)

  let resume ?nohang t : (State.t * bool) =
    let action = function
    | State.Started (_,_,pid,_, State.Suspended) as state -> (Unix.kill pid Sys.sigcont; state)
    | state -> state
    in
    let state = Cortex.apply t action in
    (* Now wait until the pause will be observed: *)
    let (state, changed) =
      match (State.is_suspended state) && (nohang = None) with
      | true  -> (Cortex.get ~guard:State.is_not_suspended t, true)
      | false -> (state, false)
    in
    (state, changed)

  let rec terminate ?nohang ?sigkill t : (State.t * bool) =
    let term =
      if sigkill = Some () then Sys.sigkill else Sys.sigterm
    in
    let action = function
    | State.Started (_,_,pid,_, State.Running) as state   -> (Unix.kill pid term; state)
    | State.Started (_,_,pid,_, State.Suspended) as state -> (List.iter (Unix.kill pid) [term; Sys.sigcont]; state)
    | state -> state
    in
    let state = Cortex.apply t action in
    let () =
      if sigkill = None
       then ignore (Thread.create (fun () -> Thread.delay 0.5; terminate ~sigkill:() t) ())
       else ()
    in
    (* Now wait until the pause will be observed: *)
    let (state, changed) =
      match (State.is_started state) && (nohang = None) with
      | true  -> (Cortex.get ~guard:State.is_terminated t, true)
      | false -> (state, false)
    in
    (state, changed)

  (* Redefinition: *)
  let terminate ?nohang t = terminate ?nohang ?sigkill:None t

  class c
    ?tuning
    (program:string)
    (arguments:string list)
    =
    let t = plan ?tuning program arguments in
    object
      inherit [State.t] Cortex.Object.with_private_interface t
      method start : unit -> State.t * bool =
        fun () -> start t

      method suspend : ?nohang:unit -> unit -> State.t * bool =
        fun ?nohang () -> suspend ?nohang t

      method resume : ?nohang:unit -> unit -> State.t * bool =
        fun ?nohang () -> resume ?nohang t

      method terminate : ?nohang:unit -> unit -> State.t * bool =
        fun ?nohang () -> terminate ?nohang t
    end

end (* module Process *)


module Service = struct

  type t = ((Process.State.t option) * Process.t) Cortex.t

  let plan ?tuning (program:string) (arguments:string list) : t =
    let creator ?previous () =
      Process.Open.plan ?tuning program arguments
    in
    let terminal = Process.State.is_terminated in
    Cortex.lifes ~creator ~terminal ()

  let start (t:t) : (Process.State.t * bool) =
    Cortex.apply t (fun (_,p) -> Process.start p)

  let status (t:t) : Process.State.t =
    Cortex.apply t (fun (_,p) -> Cortex.get p)

  let previous_status (t:t) : Process.State.t option =
    Cortex.apply t (fun (s,_) -> s)

  let previous_really_executed (t:t) : bool =
    Cortex.apply t
      (fun (s,_) ->
         match s with
         | None -> false
         | Some state -> Process.State.is_terminated_and_has_been_really_executed state
         )

  let previous_aged_at_least ~seconds (t:t) : bool =
    Cortex.apply t
      (fun (s,_) ->
         match s with
         | None -> false
         | Some state -> Process.State.is_terminated_aged_at_least ~seconds state
         )

  let previous_age (t:t) : float option =
    Cortex.apply t
      (fun (s,_) -> Option.bind s (Process.State.age))

  let status (t:t) : Process.State.t =
    Cortex.apply t (fun (_,p) -> Cortex.get p)

  let stop ?nohang (t:t) : (Process.State.t * bool) =
    Cortex.apply t (fun (_,p) -> Process.terminate ?nohang p)

  let suspend (t:t) : (Process.State.t * bool) =
    Cortex.apply t (fun (_,p) -> Process.suspend p)

  let resume ?nohang (t:t) : (Process.State.t * bool) =
    Cortex.apply t (fun (_,p) -> Process.resume ?nohang p)

(*  (* Supposing recursive mutexes here (start t) in the critical section: *)
  let restart (t:t) : (Process.State.t * bool) =
    Cortex.apply t
      (fun (_,p) ->
         let (_, changed) as stop_result = Process.terminate p in
         if not changed then stop_result else start t)*)

 (* Without recursive mutexes we can break the critical section but it's
     not the same because another thread may start the service... *)
  let restart (t:t) : (Process.State.t * bool) =
    let (_, changed) as stop_result = stop t in
    if not changed then stop_result else
    start t

  class c
    ?tuning
    (program:string)
    (arguments:string list)
    =
    let t = plan ?tuning program arguments in
    object
      inherit
        [Process.State.t option * Process.t]
           Cortex.Object.with_private_interface t

      method start : unit -> Process.State.t * bool =
        fun () -> start t

      method previous_status : unit -> Process.State.t option =
        fun () -> previous_status t

      method previous_really_executed : unit -> bool =
        fun () -> previous_really_executed t

      method previous_aged_at_least : seconds:float -> bool =
        fun ~seconds -> previous_aged_at_least ~seconds t

      method previous_age : unit -> float option =
        fun () -> previous_age t

      method status : unit -> Process.State.t =
        fun () -> status t

      method suspend : unit -> Process.State.t * bool =
        fun () -> suspend t

      method resume : ?nohang:unit -> unit -> Process.State.t * bool =
        fun ?nohang () -> resume ?nohang t

      method stop : ?nohang:unit -> unit -> Process.State.t * bool =
        fun ?nohang () -> stop ?nohang t

      method restart : unit -> Process.State.t * bool =
        fun () -> restart t

    end


end (* module Service *)

module Channel = struct

  (* The channel may be empty or it may contain a message for someone *)
  type 'a t = ('a option) Cortex.t

  let return
    ?equality
    ?on_proposal
    ?on_commit
    ?init
    ()
    =
    let equality = match equality with
    | None   -> None
    | Some f ->
        Some
          (fun xo yo -> match xo,yo with
           | None, None     -> true
           | Some x, Some y -> f x y
           | _,_ -> false)
    in
    Cortex.return ?equality ?on_proposal ?on_commit init

  let receive (t:'a t) : 'a =
    let (result, _changed) =
      Cortex.eval
	~guard:(fun v -> v<>None)
	(fun v () ->
	  match v with
	  | Some msg -> (None, (fun _ -> msg))
	  | None     -> assert false)
	()
	t
    in result

  let send (t:'a t) (msg:'a) : bool =
    let (result, changed) =
      Cortex.eval
	~guard:(fun v -> v=None)
	(fun v () ->
	  match v with
	  | None   -> (Some msg), (fun _accepted -> ())
	  | Some _ -> assert false)
	()
	t
     in
     changed

end (* Canal *)

module Clock = struct

  (* Just a counter incremented by an hidden thread. *)
  type t = int Cortex.t

  let make ?(init=0) ?limit ?(delay=1.) () =
    let result = Cortex.return init in
    let _orbiter =
      let terminate =
        match limit with
        | None       -> (fun i -> false)
        | Some limit -> ((=)limit)
      in
      let rec loop i =
        if terminate i then () else (* continue: *)
        let () = Thread.delay delay in
        let i = i + 1 in
        (* val Cortex.move : ?guard:('a -> bool) -> 'a t -> ('a -> 'a) -> 'a * bool *)
        let _ = Cortex.move result (fun j -> j+1) in
        (* let () = Cortex.set result i in *)
        loop i
      in
      Thread.create loop init
   in
   result

end (* Clock *)

