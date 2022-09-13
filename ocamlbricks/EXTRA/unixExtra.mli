(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009 Jean-Vincent Loddo

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

(** Additional features for the standard library [Unix]. *)

type filename = string
type dirname  = string
type content  = string

val apply_ignoring_Unix_error : ('a -> unit) -> 'a -> unit
val apply_catching_Unix_error : fallback:(Unix.error * string * string -> 'b) -> ('a -> 'b) -> 'a -> 'b

(** {2 File permissions} *)

type symbolic_mode = (bool*bool*bool)*(bool*bool*bool)*(bool*bool*bool)

val update_symbolic_mode :
  ?u:unit -> ?g:unit -> ?o:unit -> ?a:unit -> ?r:bool -> ?w:bool -> ?x:bool ->
  symbolic_mode -> symbolic_mode

val get_umask : unit -> symbolic_mode
val set_umask : (bool*bool*bool) -> (bool*bool*bool) -> (bool*bool*bool) -> unit
val update_umask :
  ?u:unit -> ?g:unit -> ?o:unit -> ?a:unit -> ?r:bool -> ?w:bool -> ?x:bool ->
  unit -> unit

val test_access : ?r:unit -> ?w:unit -> ?x:unit -> filename -> bool
val touch : ?perm:Unix.file_perm -> filename -> unit

val get_perm : filename -> symbolic_mode
val set_perm :
  ?u:unit -> ?g:unit -> ?o:unit -> ?a:unit -> ?r:bool -> ?w:bool -> ?x:bool ->
  filename -> unit

(** {2 File kinds and permissions} *)

val test_kind_and_access :
  ?follow:unit ->                                                                (* follow symlinks *)
  ?f:unit -> ?d:unit -> ?c:unit -> ?b:unit -> ?l:unit -> ?p:unit -> ?s:unit ->   (* kinds *)
  ?r:unit -> ?w:unit -> ?x:unit ->                                               (* permissions *)
  filename -> bool

(** {b Instances}: *)

val dir_rw_or_link_to     : dirname  -> bool  (* test_kind_and_access ~follow:() ~d:() ~r:() ~w:()       *)
val dir_rwx_or_link_to    : dirname  -> bool  (* test_kind_and_access ~follow:() ~d:() ~r:() ~w:() ~x:() *)
val regfile_r_or_link_to  : filename -> bool  (* test_kind_and_access ~follow:() ~f:() ~r:()             *)
val regfile_rw_or_link_to : filename -> bool  (* test_kind_and_access ~follow:() ~f:() ~r:() ~w:()       *)
val viable_freshname      : filename -> bool

(** {2 Copying files} *)

val file_copy   : ?buffer_size:int -> ?perm:Unix.file_perm -> filename -> filename -> unit
val file_append : ?buffer_size:int -> ?perm:Unix.file_perm -> filename -> filename -> unit
val file_move   : filename -> filename -> unit

(** {2 Saving strings} *)

val put     : ?perm:Unix.file_perm -> filename -> content -> unit
val rewrite : ?perm:Unix.file_perm -> filename -> content -> unit
val append  : ?perm:Unix.file_perm -> filename -> content -> unit

(** {2 Loading strings} *)

val cat : filename -> string

(** {2 Temporary files} *)

val temp_dir :
  ?perm:Unix.file_perm ->
  ?parent:string -> ?prefix:string -> ?suffix:string -> unit -> string

val temp_file :
  ?perm:Unix.file_perm ->
  ?parent:string ->
  ?prefix:string -> ?suffix:string -> ?content:content -> unit -> string

module TMPDIR :
  sig
    val default_prefix : string
    val open_temp :
      ?perm:Unix.file_perm ->
      ?prefix:string -> ?suffix:string -> unit -> string * Unix.file_descr
    val temp_file :
      ?perm:Unix.file_perm ->
      ?prefix:string -> ?suffix:string -> unit -> string
  end


(** {2 File kind} *)

val file_kind_of_char : char -> Unix.file_kind option

(** {2 Directories} *)

val iter_dir : (string -> unit) -> string -> unit

val find :
  ?follow:unit ->
  ?maxdepth:int ->
  ?kind:char ->
  ?basename:string ->
  ?only_first:unit ->
  string list -> string list * exn list

val find_fold :
  ?follow:unit ->
  ?maxdepth:int ->
  ?kind:char ->
  ?basename:string ->
  ?only_first:unit ->
  ('a -> string * string list * exn list -> 'a) -> 'a -> string list -> 'a

val find_first_and_map :
  ?follow:unit ->
  ?maxdepth:int ->
  ?kind:char ->
  ?basename:string ->
  (string -> string -> 'a) ->
  string list -> 'a option

(** {2 Password} *)

val read_passwd : string -> string

(** {2 Process status} *)

val string_of_process_status : Unix.process_status -> string

(** {2 Managing external programs} *)

type command = string
type program = string

val path_of_implicit : program -> string option

(** Version working in the both cases implicit/explicit program
    reference as a shell interpreter. *)
val is_executable : program -> bool

(** Version working in the both cases implicit/explicit program
    reference as a shell interpreter. *)
val resolve_executable : ?realpath:unit -> program -> string option

val system_or_fail : ?hide_output:bool -> ?hide_errors:bool -> command -> unit

val kill_safe : int -> int -> unit

exception Signal_forward of int
exception Waitpid

val create_process_and_wait :
  ?stdin:Endpoint.Source.t ->
  ?stdout:Endpoint.Sink.t  ->
  ?stderr:Endpoint.Sink.t  ->
  ?pseudo:string ->
  ?forward:int list ->
  ?register_pid:(int->unit) ->
  program -> string list -> int

type process_result = int * string * string

val create_process_and_wait_then_get_result :
  ?stdin:Endpoint.Source.t ->
  ?stdout:Endpoint.Sink.t  ->
  ?stderr:Endpoint.Sink.t  ->
  ?pseudo:string ->
  ?forward:int list ->
  ?register_pid:(int->unit) ->
  program -> string list -> process_result

val run   : ?shell:command -> ?trace:bool -> ?input:string -> ?stderr:Endpoint.Sink.t -> command -> string * Unix.process_status
val shell : ?shell:command -> ?trace:bool -> ?input:string -> ?stderr:Endpoint.Sink.t -> command -> string

(** {b Asynchronous version} *)

val future :
  ?stdin:Endpoint.Source.t ->
  ?stdout:Endpoint.Sink.t  ->
  ?stderr:Endpoint.Sink.t  ->
  ?pseudo:string ->
  ?forward:int list ->
  ?register_pid:(int->unit) ->
  program -> string list -> process_result Future.t

val kfuture :
  ?stdin:Endpoint.Source.t ->
  ?stdout:Endpoint.Sink.t  ->
  ?stderr:Endpoint.Sink.t  ->
  ?pseudo:string ->
  ?forward:int list ->
  ?register_pid:(int->unit) ->
  program -> string list -> (int -> string -> string ->'a) -> 'a Future.t

val script :
  ?stdin:Endpoint.Source.t ->
  ?stdout:Endpoint.Sink.t  ->
  ?stderr:Endpoint.Sink.t  ->
  ?pseudo:string ->
  ?forward:int list ->
  ?register_pid:(int->unit) ->
  content -> string list -> process_result

val script_future :
  ?stdin:Endpoint.Source.t ->
  ?stdout:Endpoint.Sink.t  ->
  ?stderr:Endpoint.Sink.t  ->
  ?pseudo:string ->
  ?forward:int list ->
  ?register_pid:(int->unit) ->
  content -> string list -> process_result Future.t

type pid = int
val is_process_alive : pid -> bool

module Process : sig

 type status =
 | WUNCHANGED
 | WEXITED of int
 | WSIGNALED of int
 | WSTOPPED of int
 | WCONTINUED

 type wait_flag =
 | WNOHANG
 | WUNTRACED
 | WCONTINUE

 val waitpid : wait_flag list -> pid -> int * status
 val string_of_status : status -> string

 (** Similar to waitpid but protected from the exception [Unix.Unix_error (Unix.EINTR, _, _)].
     If this exception is raised, the function recall itself in order to wait again: *)
 val waitpid_non_intr : ?wait_flags:wait_flag list -> pid -> (exn, int * status) Either.t

 (** Similar to [waitpid_non_intr] but protected also from the exception:
     [Unix.Unix_error (Unix.ECHILD, _, _)] which may simply mean that the process doesn't exist
     or it is already terminated (and wait-ed by someone else). In this case, the function returns immediately.
     However, if this exception is raised when the process is still alive, this means that the process
     cannot be wait-ed (is not a child or a descendant). In this case, an exception [Invalid_argument] is raised. *)
 val join_process : pid -> unit

end (* Process *)

module Dir : sig

 type t = string

 val iter    : ?entry_kind:Unix.file_kind -> ?follow:unit -> (string -> unit) -> t -> unit
 val to_list : ?entry_kind:Unix.file_kind -> ?follow:unit -> t -> string list
 val map     : ?entry_kind:Unix.file_kind -> ?follow:unit -> (string -> 'a) -> t -> 'a list
 val fold    : ?entry_kind:Unix.file_kind -> ?follow:unit -> ('a -> string -> 'a) -> 'a -> t -> 'a

 val iter_with_kind    : ?follow:unit -> (string -> Unix.file_kind -> unit) -> t -> unit
 val to_list_with_kind : ?follow:unit -> t -> (string * Unix.file_kind) list
 val map_with_kind     : ?follow:unit -> (string -> Unix.file_kind -> 'a) -> t -> 'a list
 val fold_with_kind    : ?follow:unit -> ('a -> string -> Unix.file_kind -> 'a) -> 'a -> t -> 'a

 (* Try to remove anything possible. Return true if all the removing operation succeed (all files and subdirectories). *)
 val remove_recursively : ?verbose:unit -> t -> bool

end (* Dir *)

val date : ?gmt:unit -> ?dash:string -> ?dot:string -> ?colon:string -> ?no_time:unit -> ?no_sec:unit -> ?no_date:unit
  -> unit -> string

val resolve_symlink : ?max_hops:int -> string -> string
val is_symlink : string -> bool

module Thread_unsafe : sig
 val realpath : ?s:unit -> string -> string option
end

val realpath : ?s:unit -> string -> string option

IFDEF OCAML4_04_OR_LATER THEN
(** Return something (not None) if and only if all the items in the chain of symlinks,
    included the final target (that is not a symlink) exist. *)
val realpath_exists : string -> string option
ENDIF

(** Poor man profiling tool (based on Unix.gettimeofday): *)
val perf : ('a -> 'b) -> 'a -> 'b * float
