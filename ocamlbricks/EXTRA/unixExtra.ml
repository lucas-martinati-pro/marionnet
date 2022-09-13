(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Jean-Vincent Loddo

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

(* Do not remove the following line: it's an ocamldoc workaround!*)
(** *)

IFNDEF OCAML4_02_OR_LATER THEN
module Bytes = struct  include String  let to_string x = x  let of_string x = x  end
type bytes = string
ENDIF

IFDEF OCAML4_07_OR_LATER THEN
module Pervasives = Stdlib
ENDIF

module Log = Ocamlbricks_log

(** A {e filename} is a string. *)
type filename = string;;

(** A {e dirname} is a string. *)
type dirname = string;;

(** A {e content} is a string. *)
type content = string;;

let apply_ignoring_Unix_error f x =
 try f x with Unix.Unix_error (_,_,_) -> ()
;;

let apply_catching_Unix_error ~fallback f x =
 try f x with Unix.Unix_error (e,b,c) -> fallback (e,b,c)
;;

(** The {e user}, {e group} and {e other} permissions [(r,w,x),(r,w,x),(r,w,x)]. *)
type symbolic_mode = (bool*bool*bool)*(bool*bool*bool)*(bool*bool*bool)

let list_of_symbolic_mode = function
  ((u_r, u_w, u_x), (g_r, g_w, g_x), (o_r, o_w, o_x)) -> [u_r; u_w; u_x ; g_r; g_w; g_x; o_r; o_w; o_x ]

let symbolic_mode_of_list = function
  | [u_r; u_w; u_x ; g_r; g_w; g_x; o_r; o_w; o_x ] ->  ((u_r, u_w, u_x), (g_r, g_w, g_x), (o_r, o_w, o_x))
  | xs -> invalid_arg (Printf.sprintf
                        "symbolic_mode_of_list: the length of list is %d but it expected to be 9"
                        (List.length xs))

(** Update a symbolic mode using optial parameters with a meaning similar to the command
    line options of the unix utility [chmod]. *)
let update_symbolic_mode ?u ?g ?o ?a ?r ?w ?x ((u_r, u_w, u_x), (g_r, g_w, g_x), (o_r, o_w, o_x)) =
 let extract = function Some x -> x | None -> assert false in
 let user_involved = (u<>None || a<>None) in
 let u_r = if user_involved && r<>None then (extract r) else u_r in
 let u_w = if user_involved && w<>None then (extract w) else u_w in
 let u_x = if user_involved && x<>None then (extract x) else u_x in
 let group_involved = (g<>None || a<>None) in
 let g_r = if group_involved && r<>None then (extract r) else g_r in
 let g_w = if group_involved && w<>None then (extract w) else g_w in
 let g_x = if group_involved && x<>None then (extract x) else g_x in
 let other_involved = (o<>None || a<>None) in
 let o_r = if other_involved && r<>None then (extract r) else o_r in
 let o_w = if other_involved && w<>None then (extract w) else o_w in
 let o_x = if other_involved && x<>None then (extract x) else o_x in
 ((u_r, u_w, u_x), (g_r, g_w, g_x), (o_r, o_w, o_x))

(** The current value of umask. *)
let get_umask () : symbolic_mode =
 let current = Unix.umask 0 in
 let   _     = Unix.umask current in
 symbolic_mode_of_list (List.map not (Bit.bits_as_booleans_of_int ~length:9 current))
;;

(** Set umask using (a currified version of) a symbolic mode. *)
let set_umask um gm om =
 let i = Bit.int_of_bits_as_booleans (List.map not (list_of_symbolic_mode (um,gm,om))) in
 ignore (Unix.umask i)
;;

(** Update the default file creation mask specifying who is updated: user ([?u]) and/or group ([?g])
    and/or other ([?o]) and/or all ([?a]), and what you whant to update and how ([true/false]):
    read ([?r]) and/or write ([?w]) and/or execution ([?x]). *)
let update_umask ?u ?g ?o ?a ?r ?w ?x () =
 let sm = get_umask () in
 let (um,gm,om) = update_symbolic_mode ?u ?g ?o ?a ?r ?w ?x sm in
 set_umask um gm om
;;

(** Get the permissions of a file: a triple of booleans respectively for user, group and other. *)
let get_perm (fname:filename) : symbolic_mode =
 try
  let i = (Unix.stat fname).Unix.st_perm in
  symbolic_mode_of_list (Bit.bits_as_booleans_of_int ~length:9 i)
 with
  | Unix.Unix_error (Unix.ENOENT,"stat", _) -> failwith ("UnixExtra.get_perm: cant stat the file "^fname)
;;

(** Set the permissions of a file specifying who is involved: user ([?u]) and/or group ([?g])
    and/or other ([?o]) and/or all ([?a]), and what you whant to set and how ([true/false]):
    read ([?r]) and/or write ([?w]) and/or execution ([?x]). *)
let set_perm ?u ?g ?o ?a ?r ?w ?x (fname:filename) =
 let sm = get_perm fname in
 let sm = update_symbolic_mode ?u ?g ?o ?a ?r ?w ?x sm in
 let file_perm = Bit.int_of_bits_as_booleans (list_of_symbolic_mode sm) in
 Unix.chmod fname file_perm
 ;;

(** Could the process perform some operations on the file: read ([?r]) and/or write ([?w]) and/or
    execution ([?x])?*)
let test_access ?r ?w ?x filename : bool =
 let xs = [(r,Unix.R_OK); (w,Unix.W_OK); (x,Unix.X_OK)] in
 let xs = List.filter (fun (v,_)-> v<>None) xs in
 let xs = Unix.F_OK::(List.map snd xs) in
 try
   let () = Unix.access filename xs in true
 with
  (* For a strange reason, exceptions are not matched by the
      pattern `Unix.Unix_error (_, _, _)', even if they should!
      Unix.Unix_error (_,_,_) -> false
      So, we have to manipulate exceptions instead of Unix errors: *)
   e -> false
;;

(** Options:
    ~f stands for Unix.S_REG  (* Regular file *),
    ~d stands for Unix.S_DIR  (* Directory *),
    ~c stands for Unix.S_CHR  (* Character device *),
    ~b stands for Unix.S_BLK  (* Block device *),
    ~l stands for Unix.S_LNK  (* Symbolic link *),
    ~p stands for Unix.S_FIFO (* Named pipe *),
    ~s stands for Unix.S_SOCK (* Socket *).
    If any argument is provided, the function tests only the existence.
    If the option ~l (symlink) is provided with another kind-related option,
    the later is automatically considered as test(s) for the link's target, not for the link itself.
    **)
let test_kind_and_access ?follow (*kind*) ?f ?d ?c ?b ?l ?p ?s (*access*) ?r ?w ?x filename : bool =
 let access = test_access ?r ?w ?x filename in
 access &&
   begin
     try
	let xs = [(l, Unix.S_LNK); (f, Unix.S_REG); (d, Unix.S_DIR);  (c, Unix.S_CHR);  (b, Unix.S_BLK); (p, Unix.S_FIFO); (s, Unix.S_SOCK)] in
	let xs = List.filter (fun (v,_)-> v<>None) xs in
	let stat = (if follow = Some () then Unix.stat else Unix.lstat) in
	let kind = (stat filename).Unix.st_kind in
	(match xs with
	 | ((Some ()), Unix.S_LNK)::y::ys when kind = Unix.S_LNK ->
	      (* The other options are automatically considered as test(s) for the link's target, not for the link itself: *)
	      let kind = (Unix.stat (* not lstat! *) filename).Unix.st_kind in
	      List.for_all (fun (_, k) -> k = kind) (y::ys)
	 | _ ->
	      List.for_all (fun (_, k) -> k = kind) xs
	 )
     with
       (* looping symlinks are considered as not accessible: *)
       Unix.Unix_error (Unix.ELOOP, _, _) -> false
   end

(** Equivalent to the bash test [\[\[ -d $1 && -r $1 && -w $1 \]\]]. *)
let dir_rw_or_link_to dirname =
  test_kind_and_access ~follow:() ~d:() ~r:() ~w:() dirname

(** Equivalent to the bash test [\[\[ -d $1 && -r $1 && -w $1 && -x $1 \]\]]. *)
let dir_rwx_or_link_to dirname =
  test_kind_and_access ~follow:() ~d:() ~r:() ~w:() ~x:() dirname

(** Equivalent to the bash test [\[\[ -f $1 && -r $1 \]\]]. *)
let regfile_r_or_link_to filename =
  test_kind_and_access ~follow:() ~f:() ~r:() filename

(** Equivalent to the bash test [\[\[ -f $1 && -r $1 && -w $1 \]\]]. *)
let regfile_rw_or_link_to filename =
  test_kind_and_access ~follow:() ~f:() ~r:() ~w:() filename

(** A fresh name is viable if it doesn't exist and its parent directory is writable. *)
let viable_freshname x =
  (not (Sys.file_exists x)) &&
     (let dirname = (Filename.dirname x) in
      test_kind_and_access ~follow:() ~d:() ~w:() dirname)

(** Create a file if necessary with the given permissions
   (by default equal to [0o644]). *)
let touch ?(perm=0o644) (fname:filename) : unit =
 try (* file exists *)
   let stat = (Unix.stat fname) in
   let size = stat.Unix.st_size in
   let fd = Unix.openfile fname [Unix.O_WRONLY] 0o644 in
   Unix.ftruncate fd size;
   Unix.close fd;
 with
   | Unix.Unix_error (Unix.EACCES,"open", _) -> failwith ("UnixExtra.touch: cannot open file "^fname)
   | Unix.Unix_error (Unix.ENOENT,"stat", _) ->
       begin (* file doesn't exist *)
	 let fd = (Unix.openfile fname [Unix.O_CREAT] perm) in
	 (Unix.close fd)
       end
;;

(** Copy or append a file into another. Optional permissions (by default [0o644]) concern of course the target.
    -- Adapted from {{:http://www.enseignement.polytechnique.fr/profs/informatique/Didier.Remy/system/camlunix/fich.html}Xavier Leroy and Didier Remy's OS course, Chapter 2}. *)
let file_copy_or_append ?(flag=Unix.O_TRUNC) ?(buffer_size=8192) ?perm input_name output_name =
  let perm = match perm with Some x -> x | None -> (Unix.stat input_name).Unix.st_perm in
  let buffer = Bytes.create buffer_size in
  let fd_in  = Unix.openfile input_name  [Unix.O_RDONLY] 0 in
  let fd_out = Unix.openfile output_name [Unix.O_WRONLY; Unix.O_CREAT; flag] perm in
  let rec copy_loop () =
   match Unix.read fd_in buffer 0 buffer_size with
     0 -> ()
   | r -> ignore (Unix.write fd_out buffer 0 r); copy_loop () in
  copy_loop ();
  Unix.close fd_in;
  Unix.close fd_out
;;

(** Copy a file into another. Defaults are [buffer_size=8192] and [perm=0o644]. Permissions are used
    only if the target file must be created. *)
let file_copy   = file_copy_or_append ~flag:Unix.O_TRUNC  ;;

(** Append a file into another. Defaults are [buffer_size=8192] and [perm=0o644]. Permissions are used
    only if the target file must be created. *)
let file_append = file_copy_or_append ~flag:Unix.O_APPEND ;;

(** Try to rename or copy-and-unlink the source file. *)
let file_move input_name output_name =
  try  (* try to rename *)
    Unix.rename input_name output_name
  with (* else copy and unlink *)
    Unix.Unix_error (_,"rename",_) ->
       begin
        file_copy input_name output_name;
        Unix.unlink input_name;
       end
;;

(** Write or rewrite the file with the given content.
    If the file does not exists, it is created with the given permission
   (set by default to [0o644]). *)
let put ?(perm=0o644) (fname:filename) (x:content) : unit =
  let fd = (Unix.openfile fname [Unix.O_CREAT; Unix.O_WRONLY; Unix.O_TRUNC] perm) in
  let n = String.length x in
  ignore (Unix.write fd (Bytes.of_string x) 0 n);
  (Unix.close fd)
;;

(** Alias for [put]. *)
let rewrite = put;;

(** Similar to the function [put] described above, but the content is {b appended} instead of rewrited.
    If the file doesn't exists, it is created with the given permissions (set by default to [0o644]). *)
let append ?(perm=0o644) (fname:filename) (x:content) =
  let fd = (Unix.openfile fname [Unix.O_CREAT; Unix.O_WRONLY; Unix.O_APPEND] perm) in
  let n  = String.length x in
  ignore (Unix.write fd (Bytes.of_string x) 0 n);
  (Unix.close fd)
;;

(** Return the {b whole} content (caution!) of the file
    as a string. Use only for small files.
    Great for making pipelines. For instance,
    the following pipeline catches the first line of [/etc/fstab] containing
    the substring "hda1":
{[# "/etc/fstab" => ( cat || String.to_list || Str.grep ".*hda1.*" || hd ) ]}*)
let cat (fname:filename) =
  let fd = (Unix.openfile fname [Unix.O_RDONLY] 0o644) in
  let len = 16*1024 in
  let buff = Bytes.create len in
  let rec loop acc =
    begin
    let n = (Unix.read fd buff 0 len) in
    let s = Bytes.sub buff 0 n in
    if (n<len) then (Bytes.concat (Bytes.of_string "") (List.rev (s::acc)))
    else loop (s::acc)
    end in
  let result = loop [] in
  let () = Unix.close fd in
  (Bytes.to_string result)
;;


(** Support for this section. *)
module Templib = struct

(** General function for creating temporary files or directories in a parent directory
    with some permissions and with a prefix and suffix for the name.
    The function returns the name of the created file or directory.
*)
let rec temp_name ~(dir:bool) ~(perm:Unix.file_perm) ~(parent:string) ~(prefix:string) ~(suffix:string) () =
  begin
   let rnd = Random.int (1024*1024*1023) in
   let candidate = (Filename.concat parent (prefix^(string_of_int rnd)^suffix)) in
   if (Sys.file_exists candidate) then (temp_name ~dir ~perm  ~parent ~prefix ~suffix ())
   else
     begin
         if dir then (Unix.mkdir candidate perm)
         else (touch candidate ~perm) ;
         candidate
     end
  end
;;
end;; (* module Templib *)

(** Create a temporary directory in a parent directory using a random name in the range [0..2^30].
    By default:
   - permissions [perm] are set to [0o755]
   - the parent directory is set to ["/tmp"]
   - the prefix and suffix of the name are the empty string

The function returns the name of the created directory.

{b Example}:
{[# temp_dir ();;
  : string = "/tmp/819618234"

# temp_dir ~suffix:".txt" ();;
  : string = "/tmp/625724514.txt"
]}*)
let temp_dir ?(perm=0o755) ?(parent="/tmp") ?(prefix="") ?(suffix="") () =
  Templib.temp_name ~dir:true ~parent ~perm ~prefix ~suffix ()
;;

(** Create a temporary file in a parent directory. The optional parameters have the same meaning
    of the function [temp_dir]. In addition, the parameter [content] may be set in order
    to put it in the created file. By default the [content] is the empty string.
    The function returns the name of the created directory.
*)
let temp_file ?(perm=0o644) ?(parent="/tmp") ?(prefix="") ?(suffix="") ?(content:string="") () =
  let fname = (Templib.temp_name ~dir:false ~perm ~parent ~prefix ~suffix ()) in
  (if content<>"" then (rewrite fname content));
  fname
;;

(** More safe (quite paranoic) functions using the [TMPDIR] environment variable
    and implemented as [Filename.open_temp] wrappers. *)
module TMPDIR = struct

let default_prefix = (Filename.basename Sys.executable_name)^".";;

let open_temp
  ?(perm=0o644)
  ?(prefix=default_prefix)
  ?(suffix="") () =
  (try
    let (filename,ch) = Filename.open_temp_file prefix suffix in
    let fd = Unix.descr_of_out_channel ch in
    (Unix.chmod filename perm);
    (filename,fd)
   with e ->
     (Printf.eprintf "%s: cannot create a temporary file; set the environment variable TMPDIR to resolve this problem.\n" Sys.executable_name);
     (flush stderr);
     raise e)

let temp_file
 ?(perm=0o644)
 ?(prefix=default_prefix)
 ?(suffix="") () =
 let (filename,fd) = open_temp ~perm ~prefix ~suffix () in
 (Unix.close fd);
 filename

end;;

(** Heuristic that tries to convert a char into a value of the type:

    [Unix.file_kind = S_REG | S_DIR | S_CHR | S_BLK | S_LNK | S_FIFO | S_SOCK]

    The input character must belong to the set ['f';'d';'c';'b';'h';'p';'s'],
    following the convention of the standard unix [test] command.
    Otherwise, the result is [None].*)
let file_kind_of_char = function
 | 'f'       -> Some Unix.S_REG  (*  Regular file  *)
 | 'd'       -> Some Unix.S_DIR  (*  Directory  *)
 | 'c'       -> Some Unix.S_CHR  (*  Character device  *)
 | 'b'       -> Some Unix.S_BLK  (*  Block device  *)
 | 'h' | 'L' -> Some Unix.S_LNK  (*  Symbolic link  *)
 | 'p'       -> Some Unix.S_FIFO (*  Named pipe  *)
 | 'S'       -> Some Unix.S_SOCK (*  Socket  *)
 |  _        -> None
;;

(** [iter_dir f dirname] iterate the function [f] on each entry of the directory [dirname].
-- From {{:http://www.enseignement.polytechnique.fr/profs/informatique/Didier.Remy/system/camlunix/fich.html}Xavier Leroy and Didier Remy's OS course, Chapter 2}. *)
let iter_dir f dirname =
      let d = Unix.opendir dirname in
      try while true do f (Unix.readdir d) done
      with End_of_file -> Unix.closedir d
;;


(** Support for finding in a directory hierarchy.
-- From {{:http://www.enseignement.polytechnique.fr/profs/informatique/Didier.Remy/system/camlunix/fich.html}Xavier Leroy and Didier Remy's OS course, Chapter 2}. *)
module Findlib = struct

    exception Hidden of exn

    let hide_exn f x = try f x with exn -> raise (Hidden exn);;
    let reveal_exn f x = try f x with Hidden exn -> raise exn;;

    let find on_error on_path follow depth roots =
      let rec loop depth visiting filename =
        try
          let infos = (if follow then Unix.stat else Unix.lstat) filename in
          let continue = hide_exn (on_path filename) infos in
          let id = infos.Unix.st_dev, infos.Unix.st_ino in
          if infos.Unix.st_kind = Unix.S_DIR && depth > 0 && continue &&
            (not follow || not (List.mem id visiting))
          then
            let process_child child =
              if (child <> Filename.current_dir_name &&
                  child <> Filename.parent_dir_name) then
                let child_name = Filename.concat filename child in
                let visiting =
                  if follow then id :: visiting else visiting in
                 loop (depth-1) visiting child_name
            in
            iter_dir process_child filename
        with
        (* For a strange reason, exceptions are not matched by the
           pattern `Unix.Unix_error (e, b, c)', even if they should!
           | Unix.Unix_error (e, b, c) -> hide_exn on_error (e, b, c)
           So, we have to manipulate exceptions instead of Unix errors: *)
           | e -> hide_exn on_error e
      in
      reveal_exn (List.iter (loop depth [])) roots
;;

end;; (* module Findlib *)


(** Find something in an input directory. This function is an interface for the
    tool [Findlib.find].

    The default assignements are:
    - [follow=false]
    - [maxdepth=1024]
    - [kind='_'] which implies no condition on kind
    - [name=""]  which implies no condition on name.

    The set of characters corresponding
    to the kind of file are the same of the standard [test] unix command (i.e.
    ['f';'d';'c';'b';'h';'p';'s']); see the function {!file_kind_of_char}
    for more details.

    {b Warning:} use this function with caution: the good version
    of this function will be a version returning a sequence (stream) instead of
    a list.

{b Examples}:
{[# find "/etc/ssh/" ;;
  : string list = ["/etc/ssh/"; "/etc/ssh/ssh_config"; "/etc/ssh/sshd_config";
 "/etc/ssh/ssh_host_key"; "/etc/ssh/ssh_host_dsa_key.pub";
 "/etc/ssh/ssh_host_rsa_key.pub"; "/etc/ssh/moduli";
 "/etc/ssh/ssh_host_key.pub"; "/etc/ssh/ssh_host_dsa_key";
 "/etc/ssh/ssh_host_rsa_key"]

# find ~kind:'d' "/etc/ssh/" ;;
  : string list = ["/etc/ssh/"]

# find ~name:"moduli" "/etc/ssh/" ;;
  : string list = ["/etc/ssh/moduli"]
]} *)
let find ?follow ?(maxdepth=1024) ?(kind='_') ?(basename="") ?only_first roots : string list * exn list =
  let follow = (follow = Some ()) in
  let result_paths = ref [] in
  let result_exn   = ref [] in
  let action =
    let push_on_condition (condition) p =
      if (condition) then result_paths := (p::!result_paths) else ()
    in
    match (file_kind_of_char kind, basename) with
    | (None    , ""   ) -> fun p infos -> result_paths := (p::!result_paths)
    | ((Some k), ""   ) -> fun p infos -> push_on_condition (infos.Unix.st_kind = k) p
    | (None    , n    ) -> fun p infos -> push_on_condition ((Filename.basename p) = n) p
    | ((Some k), n    ) -> fun p infos -> push_on_condition ((infos.Unix.st_kind = k) && ((Filename.basename p) = n)) p
  in
  let continue =
    match only_first with
    | None    -> fun () -> true
    | Some () -> fun () -> !result_paths = []
  in
  let action p infos =
    (action p infos; continue ())
  in
  let on_error exn =
    (result_exn := exn::!result_exn)
  in
  let make_result () =
    (List.rev (!result_paths), List.rev (!result_exn))
  in
  try
    let () = Findlib.find on_error action follow maxdepth roots in
    make_result ()
  with
    exn ->
	let () = (result_exn := exn::!result_exn) in
	make_result ()
;;

(* For the same strange reason mentioned above, this redefinition doesn't run
   correctly : the second part of the result (the list of errors) is each time the empty list...
   However, outside the module UnixExtra the result may be kept and correctly matched. *)
(*
let find ?follow ?maxdepth ?kind ?basename ?only_first roots =
  let (xs,es) = find ?follow ?maxdepth ?kind ?basename ?only_first roots in
  let es2 =
    lazy
      let es1 = List.filter (function Unix.Unix_error (_,_,_) -> true | _ -> false) es in
      List.map (function Unix.Unix_error (e,b,c) -> (e,b,c) | _ -> assert false) es1
  in
  (xs, es2)
*)

let find_fold ?follow ?maxdepth ?kind ?basename ?only_first (f:('a -> string * string list * exn list -> 'a)) acc roots : 'a =
  List.fold_left
    (fun acc root ->
      let (xs,es) = find ?follow ?maxdepth ?kind ?basename ?only_first [root] in
      f acc (root,xs,es))
    acc
    roots

let find_first_and_map ?follow ?maxdepth ?kind ?basename (f:string -> string -> 'a) roots : 'a option =
  List.fold_left
    (fun acc root ->
      if acc<>None then acc else
      let (xs,es) = find ?follow ?maxdepth ?kind ?basename ~only_first:() [root] in
      match xs with
      | x::_ -> Some (f root x)
      | [] -> None
      )
    None
    roots


(** Support for input passwords.
-- From {{:http://www.enseignement.polytechnique.fr/profs/informatique/Didier.Remy/system/camlunix/fich.html}Xavier Leroy and Didier Remy's OS course, Chapter 2}. *)
module Passwdlib = struct

     let read_passwd message =
      match
        try
          let default = Unix.tcgetattr Unix.stdin in
          let silent =
            { default with
              Unix.c_echo = false;
              Unix.c_echoe = false;
              Unix.c_echok = false;
              Unix.c_echonl = false;
            } in
          Some (default, silent)
        with _ -> None
      with
      | None -> input_line Pervasives.stdin
      | Some (default, silent) ->
          print_string message;
          flush Pervasives.stdout;
          Unix.tcsetattr Unix.stdin Unix.TCSANOW silent;
          try
            let s = input_line Pervasives.stdin in
            Unix.tcsetattr Unix.stdin Unix.TCSANOW default; s
          with x ->
            Unix.tcsetattr Unix.stdin Unix.TCSANOW default; raise x;;

end;; (* Passwdlib *)

(** Prompt for a password. The terminal is set for hiding the characters read from keyboard. *)
let read_passwd prompt = Passwdlib.read_passwd prompt;;

let string_of_process_status = function
 | Unix.WEXITED   code   -> (Printf.sprintf "Unix.WEXITED %d" code)
 | Unix.WSIGNALED signal -> (Printf.sprintf "Unix.WSIGNALED %d" signal)
 | Unix.WSTOPPED  signal -> (Printf.sprintf "Unix.WSTOPPED %d" signal)
;;

(** A {e command} is something understandable by the shell. *)
type command = string;;

(** A {e program} is a file binary (which will be found by the system in [PATH]). *)
type program = string;;

(** Search the directory containing the executable. Candidates are taken from the environment variable [PATH].
    The result [None] means not found. {b Examples}:
{[# UnixExtra.path_of_implicit "ls" ;;
  : string option = Some "/bin"

# UnixExtra.path_of_implicit "foo" ;;
  : string option = None
]} *)
let path_of_implicit p =
 let is_there_an_executable p d =
   let filelist = Array.to_list (Sys.readdir d) in
   (List.mem p filelist) && (test_access ~x:() (Filename.concat d p))
 in
 let dirs = StringExtra.split ~d:':' (Sys.getenv "PATH") in
 let dirs = List.filter (test_access ~r:()) dirs in
 try Some(List.find (is_there_an_executable p) dirs)
 with Not_found -> None

(** Run Unix.system with the given argument, and raise exception in case of failure;
    return unit on success. *)
let system_or_fail ?(hide_output=false) ?(hide_errors=false) command =
  let suffix1 = if hide_output then " 1>/dev/null" else "" in
  let suffix2 = if hide_errors then " 2>/dev/null" else "" in
  let command = Printf.sprintf "%s%s%s" command suffix1 suffix2 in
  match Unix.system command with
  | Unix.WEXITED 0   -> ()
  | Unix.WEXITED n   -> failwith (Printf.sprintf "Unix.system: the process exited with %i" n)
  | Unix.WSIGNALED _
  | Unix.WSTOPPED _  -> failwith "Unix.system: the process was signaled or stopped"
;;

open Endpoint;;

(** [kill_safe pid signal] send the [signal] to the process [pid] ignoring exceptions. *)
let kill_safe pid signal =
  try Unix.kill pid signal with _ -> ()
;;

exception Signal_forward of int;;
exception Waitpid;;

type waiting_events = {
  mutable forwarded_signal : int option ;
  mutable process_status   : Unix.process_status option;
  mutable waitpid_exn      : bool ;
 };;

let new_waiting_events () = {
  forwarded_signal = None  ;
  process_status   = None  ;
  waitpid_exn      = false ;
 };;


let rec wait_child child_pid events =
 try begin
  let (_, process_status) = (Unix.waitpid [] child_pid) in
  (events.process_status <- Some process_status);
  match process_status with
  | Unix.WEXITED   code   -> () (* return *)
  | Unix.WSIGNALED signal
  | Unix.WSTOPPED  signal -> (events.forwarded_signal <- Some signal); wait_child child_pid events
 end with
 | Unix.Unix_error(_,_,_) -> (events.waitpid_exn <- true)
 ;;

 let new_handler child_pid events =
  Sys.Signal_handle
   (fun s -> (events.forwarded_signal <- Some s);
             (kill_safe child_pid s);
             (wait_child child_pid events))
 ;;

 (** Create process with [?stdin=Unix.stdin], [?stdout=Unix.stdout] and [?stderr=Unix.stderr] connected
     to a given source and sinks, then wait until its termination.
     During waiting, some signals could be forwarded by the father to the child specifying the argument [?(forward = [Sys.sigint; Sys.sigabrt; Sys.sigquit; Sys.sigterm; Sys.sigcont])].
     The two last parameters are the program (binary) and its list of actual parameters. The process is created with the primitive [Unix.create_process].
     If the process exits with [Unix.WEXITED code] the code is returned. Otherwise an exception is raised, more specifically:
     - [Signal_forward s] is raised if the father has transmitted a signal (certainly the reason of the violent termination of the child);
     - [Waitpid] is raised if the internal call to [Unix.waitpid] has failed for some unknown reasons.*)
 let create_process_and_wait
 ?(stdin  = Source.Unix_descr Unix.stdin)
 ?(stdout = Sink.Unix_descr   Unix.stdout)
 ?(stderr = Sink.Unix_descr   Unix.stderr)
 ?pseudo
 ?(forward = [Sys.sigint; Sys.sigabrt; Sys.sigquit; Sys.sigterm])
 ?register_pid
 program arguments =

 let (stdin,  stdin_must_be_closed )  = Source.to_file_descr stdin in
 let (stdout, stdout_must_be_closed)  = Sink.to_file_descr stdout  in
 let (stderr, stderr_must_be_closed)  = Sink.to_file_descr stderr  in

 let events = new_waiting_events () in
 let name = match pseudo with None -> program | Some name -> name in
 let argv = (Array.of_list (name :: arguments)) in
 let child_pid = (Unix.create_process program argv stdin stdout stderr) in
 (match register_pid with None -> () | Some f -> f child_pid);
 let handler = new_handler child_pid events in
 let handler_backups = List.map  (fun s -> (s, (Sys.signal s handler))) forward in
 let restore_handlers () = List.iter (fun (s,h) -> Sys.set_signal s h) handler_backups in
 (wait_child child_pid events);
(restore_handlers ());

 (if  stdin_must_be_closed then Unix.close stdin);
 (if stdout_must_be_closed then Unix.close stdout);
 (if stderr_must_be_closed then Unix.close stderr);

 match events with
  | { process_status   = Some (Unix.WEXITED code); forwarded_signal = None;  waitpid_exn = false } -> code
  | { process_status   = Some (Unix.WEXITED code); forwarded_signal = Some s; _ } when s=Sys.sigcont  -> code
  | { forwarded_signal = Some s ; waitpid_exn = true; _ } -> (raise (Signal_forward s))
  | { waitpid_exn      = true; _ }                       -> (raise Waitpid)
  | _ -> (assert false)
 ;;

(** High-level result: (code, stdout, stderr) *)
type process_result = (int * string * string) ;;

(** Similar to [create_process_and_wait], but the results on endpoints [stdout] and [stderr] are converted
    in strings and returned.
    However, if the optional parameters [stdout] and [stderr] are provided, their corresponding string in the result
    will be empty. *)
let create_process_and_wait_then_get_result ?stdin ?stdout ?stderr ?pseudo ?forward ?register_pid (program:program) (argv_list:string list) =
 begin
 let define_sink_and_string_maker optional_sink =
   (match optional_sink with
    | Some x -> (x, fun () -> "")
    | None   ->
        let q = String_queue.create () in
        (Sink.String_queue q), (fun () -> String_queue.concat q)
    )
 in
 let (stdout, stdout_string_maker) = define_sink_and_string_maker stdout in
 let (stderr, stderr_string_maker) = define_sink_and_string_maker stderr in
 let code =
    try  create_process_and_wait ?stdin ~stdout ~stderr ?pseudo ?forward ?register_pid program argv_list
    with _ -> (-1)
 in
 let stdout_string = stdout_string_maker () in
 let stderr_string = stderr_string_maker () in
 (code,stdout_string,stderr_string)
 end
;;

(* Convert a string option into a shell specification. The shell "bash" is our default. *)
let shell_of_string_option = function
| None       -> "bash"
| Some shell -> shell
;;

(** [run command] exec the shell ([bash] by default) with arguments [\["-c";command\]] and return the pair (output, exit-code).
    A string can be specified as standard input for the command. The flag [trace] (by default set to [false])
    permits to obtain some informations about the running on [stderr]. {b Examples}:
{[# run "ls /etc/*tab";;
  : string * Unix.process_status =
("/etc/crontab\n/etc/fstab\n/etc/inittab\n/etc/mtab\n/etc/quotatab\n", Unix.WEXITED 0)

# run ~input:"hello" "cat";;
  : string * Unix.process_status = ("hello", Unix.WEXITED 0)

# run ~shell:"dash" ~input:"HELLO" "head -n 1 /etc/passwd /dev/stdin | cut -c-15";;
  : string * Unix.process_status =
("==> /etc/passwd\nat:x:25:25:Batc\n\n==> /dev/stdin \nHELLO\n", Unix.WEXITED 0)
]} *)
let run ?shell ?(trace:bool=false) ?input ?stderr (cmd:command) : string * Unix.process_status =
  let shell = shell_of_string_option shell in
  let (stdin,inp) = match input with
   | None   -> (Source.Unix_descr Unix.stdin, "<stdin>")
   | Some x -> (Source.String x, x)
  in
  let queue  = String_queue.create () in
  let stdout = Sink.String_queue queue in
  let code = create_process_and_wait ~stdin ~stdout ?stderr shell ["-c";cmd] in
  let out  = (String_queue.concat queue) in
  (if trace then begin
     (* For tracing we use the standard error, not the argument ?stderr which target is the command: *)
      Printf.eprintf "UnixExtra.run: tracing: input   is '%s'\n" inp;
      Printf.eprintf "UnixExtra.run: tracing: command is '%s'\n" cmd;
      Printf.eprintf "UnixExtra.run: tracing: output  is '%s'\n" out;
      flush Pervasives.stderr;
      end);
  (out, Unix.WEXITED code)
;;

(** As [run], but ignoring the exit-code. This function is
    simply a shortcut for the composition of [run] with [fst]. {b Examples}:

{[# shell "date";;
  : string = "ven avr 13 18:34:02 CEST 2007\n"

# String.Text.Matrix.of_string (shell "wc -l /etc/*tab");;
  : string list list =
[["8"; "/etc/crontab"]; ["20"; "/etc/fstab"]; ["98"; "/etc/inittab"];
 ["11"; "/etc/mtab"]; ["127"; "/etc/naccttab"]; ["9"; "/etc/quotatab"];
 ["273"; "total"]]
]}*)
let shell ?shell ?(trace:bool=false) ?(input:string="") ?stderr cmd =
  fst(run ~shell:(shell_of_string_option shell) ~trace ~input ?stderr cmd)
;;


(** A Unix future is a future containing the exit code and the two strings outcoming from stdout and stderr.
    The negative exit code (-1) means that the process didn't well exited. *)
type _future = (int * string * string) Future.t ;;

(** Similar to {!val:UnixExtra.future}, but with a continuation executed {b within} the thread.
    The default for [forward] here is the empty list [[]]. *)
let kfuture ?stdin ?stdout ?stderr ?pseudo ?(forward=[]) ?register_pid (program:program) (argv_list:string list) k =
 begin
 let define_sink_and_string_maker optional_sink =
   (match optional_sink with
    | Some x -> (x, fun () -> "")
    | None   ->
        let q = String_queue.create () in
        (Sink.String_queue q), (fun () -> String_queue.concat q)
    )
 in
 let (stdout, stdout_string_maker) = define_sink_and_string_maker stdout in
 let (stderr, stderr_string_maker) = define_sink_and_string_maker stderr in
 let future = Future.future (fun () ->
     begin
      let code =
        try  create_process_and_wait ?stdin ~stdout ~stderr ?pseudo ~forward ?register_pid program argv_list
        with _ -> (-1)
      in
      let stdout_string = stdout_string_maker () in
      let stderr_string = stderr_string_maker () in
      (k code stdout_string stderr_string)
     end) () in
 future
 end
;;

(** Create a {!type:UnixExtra.process_result} {!type:Future.t} that you can manage as usual with functions of the module {!Future}. *)
let future ?stdin ?stdout ?stderr ?pseudo ?(forward=[]) ?register_pid program argv_list =
 kfuture ?stdin ?stdout ?stderr ?pseudo ~forward ?register_pid program argv_list (fun x y z -> (x,y,z))

(** With the {b content} provided by the user, a script file is created on the fly, executed and finally removed.
    The result is a 3-uple with the exit code and the two strings outcoming from stdout and stderr. *)
let script ?stdin ?stdout ?stderr ?pseudo ?(forward=[]) ?register_pid (content:content) (argv_list:string list) : (int * string * string) =
 begin
 let program = temp_file ~perm:0o755 ~suffix:".sh" ~content () in
 try
  let f = future ?stdin ?stdout ?stderr ?pseudo ~forward ?register_pid program argv_list in
  let result = Future.touch f in
  (Unix.unlink program);
  result
 with e -> ((Unix.unlink program); raise e)
 end
;;

let script_future ?stdin ?stdout ?stderr ?pseudo ?(forward=[]) ?register_pid (content:content) (argv_list:string list) : (int * string * string) Future.t =
 begin
 let program = temp_file ~perm:0o755 ~suffix:".sh" ~content () in
 try
  let k x y z =
    let () = Unix.unlink program in
    (x,y,z)
  in
  kfuture ?stdin ?stdout ?stderr ?pseudo ~forward ?register_pid program argv_list k
 with e -> ((Unix.unlink program); raise e)
 end
;;

(** Tools for manipulating directory entries: *)
module Dir = struct

  type t = string

  (* This protection is necessary because there is a time period between the call of `Unix.readdir'
     and the successive call to `Unix.stat'. In this period the entry may be deleted.  *)
  let protected_pred p x =
    try (p x) with Unix.Unix_error (Unix.ENOENT, _, _) -> false

  let file_kind_pred_of ?entry_kind ?follow dir =
    let stat = (if follow=Some () then Unix.stat else Unix.lstat) in
    match entry_kind with
    | None           -> (fun _ -> true)
    | Some file_kind -> protected_pred (fun x -> (stat (Filename.concat dir x)).Unix.st_kind = file_kind)

  let fold ?entry_kind ?follow f zero dir =
    let file_kind_pred = file_kind_pred_of ?entry_kind ?follow dir in
    let dir_handle = Unix.opendir dir in
    let rec loop acc =
      try
        let x = Unix.readdir dir_handle in
        let acc = if (x = ".") || (x = "..")  || (not (file_kind_pred x)) then acc else (f acc x) in
        loop acc
      with End_of_file -> acc
    in
    let result = (loop zero) in
    let () = Unix.closedir dir_handle in
    result

  let iter ?entry_kind ?follow f dir =
    fold ?entry_kind ?follow (fun () x -> f x) () dir

  let to_list ?entry_kind ?follow dir =
    List.rev (fold ?entry_kind ?follow (fun xs x -> x::xs) [] dir)

  let map ?entry_kind ?follow f dir =
    List.rev (fold ?entry_kind ?follow (fun xs x -> (f x)::xs) []  dir)

  (* --- with kind --- *)

  (* This protection is necessary because there is a time period between the call of `Unix.readdir'
     and the successive call to `Unix.stat'. In this period the entry may be deleted.  *)
  let file_kind_of ?follow dir =
    let stat = (if follow=Some () then Unix.stat else Unix.lstat) in
    fun x ->
      try
        Some (stat (Filename.concat dir x)).Unix.st_kind
      with
        Unix.Unix_error (Unix.ENOENT, _, _) -> None

  let fold_with_kind ?follow f zero dir =
    let file_kind : string -> Unix.file_kind option = file_kind_of ?follow dir in
    let dir_handle = Unix.opendir dir in
    let rec loop acc =
      try
        let x = Unix.readdir dir_handle in
        let acc = if (x = ".") || (x = "..") then acc else
        match (file_kind x) with
        | Some k -> f acc x k
        | None   -> acc
        in
        loop acc
      with End_of_file -> acc
    in
    let result = (loop zero) in
    let () = Unix.closedir dir_handle in
    result

  let iter_with_kind ?follow f dir =
    fold_with_kind ?follow (fun () x k -> f x k) () dir

  let to_list_with_kind ?follow dir =
    List.rev (fold_with_kind ?follow (fun xs x k -> (x,k)::xs) [] dir)

  let map_with_kind ?follow f dir =
    List.rev (fold_with_kind ?follow (fun xs x k -> (f x k)::xs) [] dir)

  (* val bool_of_unsafe_tool : ('a -> 'b) -> ('a -> bool) *)
  let bool_of_unsafe_tool f x =
    try let () = ignore (f x) in true with _ -> false

  let rec remove_recursively ?verbose t =
    let () = if verbose = Some () then Log.printf1 "UnixExtra.Dir.remove_recursively: entering directory %s\n" t in
    try
      let content_success =
        Flip.flip2 (fold_with_kind ?follow:None) true t (fun s x ->
          let tx = (Filename.concat t x) in
          function
          (* Directory *)
          | Unix.S_DIR -> (remove_recursively ?verbose tx) && s
          (* Any other: (S_LNK | S_CHR | S_BLK | S_FIFO |  S_SOCK) *)
          | _ ->
             let () = if verbose = Some () then Log.printf1 "UnixExtra.Dir.remove_recursively: about to unlink %s\n" tx in
             (bool_of_unsafe_tool Unix.unlink tx) && s
          )
      in
      (bool_of_unsafe_tool Unix.rmdir t) && content_success
    with e ->
      let () = if verbose = Some () then
        Log.printf1 "UnixExtra.Dir.remove_recursively: exception: %s\n" (Printexc.to_string e)
      in
      false


end (* Dir *)


type pid = int

(** [does_process_exist pid] return true if and only if the [pid] is alive in the system. *)
external does_process_exist : int -> bool = "does_process_exist_c";;
let is_process_alive = does_process_exist

module Process = struct

 type status =
 | WUNCHANGED        (** Used when non-blocking calls with WNOHANG return immediately without value *)
 | WEXITED of int    (** The process terminated normally by exit; the argument is the return code. *)
 | WSIGNALED of int  (** The process was killed by a signal; the argument is the signal number.    *)
 | WSTOPPED of int   (** The process was stopped by a signal; the argument is the signal number.   *)
 | WCONTINUED        (** The process was resumed *)

 type wait_flag =
 | WNOHANG           (** do not block if no child has died yet, but immediately return with a pid equal to 0. *)
 | WUNTRACED         (** report also the children that receive stop signals. *)
 | WCONTINUE         (** report also if the children resume *)

 external waitpid : wait_flag list -> pid -> int * status = "waitpid_c"

 let string_of_status = function
   | WUNCHANGED       -> (Printf.sprintf "Process.WUNCHANGED")
   | WEXITED   code   -> (Printf.sprintf "Process.WEXITED %d" code)
   | WSIGNALED signal -> (Printf.sprintf "Process.WSIGNALED %d" signal)
   | WSTOPPED  signal -> (Printf.sprintf "Process.WSTOPPED %d" signal)
   | WCONTINUED       -> (Printf.sprintf "Process.WCONTINUED")

 (** Similar to waitpid but protected from the exception [Unix.Unix_error (Unix.EINTR, _, _)].
     If this exception is raised, the function recalls itself in order to wait again: *)
 let rec waitpid_non_intr ?(wait_flags=[]) pid =
  try
    Either.Right (waitpid wait_flags pid)
  with
    | Unix.Unix_error (Unix.EINTR, _, _) -> waitpid_non_intr ~wait_flags pid
    | e -> Either.Left e

 (** Similar to [waitpid_non_intr] but protected also from the exception:
     [Unix.Unix_error (Unix.ECHILD, _, _)] which may simply mean that the process doesn't exist
     or it is already terminated (and wait-ed by someone else). In this case, the function returns immediately.
     However, if this exception is raised when the process is still alive, this means that the process
     cannot be wait-ed (is not a child or a descendant). In this case, an exception [Invalid_argument] is raised. *)
 let join_process pid : unit =
  let invalid_arg () =
    let msg = Printf.sprintf "UnixExtra.join_process: pid %d is not a child neither a descendant" pid in
    invalid_arg msg
  in
  let wait_flags = [] in
  match (waitpid_non_intr ~wait_flags pid) with
  | Either.Left (Unix.Unix_error (Unix.ECHILD, _, _)) ->
      if is_process_alive pid
        then invalid_arg () (* Not a child neither a descendant *)
        else ()             (* Unexistent or already dead process *)
  | Either.Left e                 -> raise e
  | Either.Right (_, WEXITED _)   -> ()
  | Either.Right (_, WSIGNALED _) -> ()
  | Either.Right (_, WSTOPPED _)  -> assert false
  | Either.Right (_, WCONTINUED)  -> assert false
  | Either.Right (_, WUNCHANGED)  -> assert false

end (* Process *)


(** Return the current date formatted as a string like ["2010-06-24.17:34:25"].
    Dashes, dot and colons may be replaced by something else
    using the optional parameters. *)
let date ?gmt ?(dash="-") ?(dot=".") ?(colon=":") ?no_time ?no_sec ?no_date () =
  let time_function = match gmt with
  | None    -> Unix.localtime
  | Some () -> Unix.gmtime
  in
  let tm = time_function (Unix.time ()) in
  match no_time, no_sec, no_date with
  | None, None, None ->
      Printf.sprintf "%4d%s%02d%s%02d%s%02d%s%02d%s%02d"
	(1900+tm.Unix.tm_year) dash
	(1+tm.Unix.tm_mon) dash
	(tm.Unix.tm_mday)
	dot
	(tm.Unix.tm_hour) colon
	(tm.Unix.tm_min)  colon
	(tm.Unix.tm_sec)
  | None, Some (), None ->
      Printf.sprintf "%4d%s%02d%s%02d%s%02d%s%02d"
        (1900+tm.Unix.tm_year) dash
        (1+tm.Unix.tm_mon) dash
        (tm.Unix.tm_mday)
        dot
        (tm.Unix.tm_hour) colon
        (tm.Unix.tm_min)
  | Some (), _, None ->
      Printf.sprintf "%4d%s%02d%s%02d"
	(1900+tm.Unix.tm_year) dash
	(1+tm.Unix.tm_mon) dash
	(tm.Unix.tm_mday)

  | None, None, Some () ->
      Printf.sprintf "%02d%s%02d%s%02d"
	(tm.Unix.tm_hour) colon
	(tm.Unix.tm_min)  colon
	(tm.Unix.tm_sec)
  | None, Some (), Some () ->
      Printf.sprintf "%02d%s%02d"
        (tm.Unix.tm_hour) colon
        (tm.Unix.tm_min)
  | Some (), _, Some () -> invalid_arg "UnixExtra.date: strangely called with ~no_time:() and ~no_date:()"

(** Resolve a symbolic link if the argument is a symbolic link, otherwise
   return the argument (identity). {b Example}:
{[
# resolve_symlink "/initrd.img" ;;
  : string = "//boot/initrd.img-2.6.32-24-generic"

# resolve_symlink "/not/existing/file" ;;
  : string = "/not/existing/file"
]}
*)
let resolve_symlink ?(max_hops=64) filename =
 let rec loop max_hops filename =
  begin try
    if max_hops <= 0 then filename else
    let target = Unix.readlink filename in
    let target =
      (match (Filename.is_relative target) with
      | true ->
	  let dir = Filename.dirname filename in
	  Printf.sprintf "%s/%s" dir target
      | false -> target
      )
    in
    if target = filename then target else (loop (max_hops-1) target)
   with _ -> filename
  end
 in loop max_hops filename

let is_symlink filename =
 try
  ignore (Unix.readlink filename);
  true
 with _ -> false

(* This version is thread_unsafe because of Sys.chdir. *)
module Thread_unsafe = struct

 (** See the unix command realpath (which has the same strange semantics): *)
 let realpath ?s x =
  let x = match s with
  | None    -> resolve_symlink x
  | Some () -> x
  in
  let cwd = Sys.getcwd () in
  let result =
    try
      match (Filename.basename x) with
      | ".." ->
         let dir = x in
         (Sys.chdir dir);
         Some (Sys.getcwd ())
      | "." ->
         let dir = Filename.dirname x in
         (Sys.chdir dir);
         Some (Sys.getcwd ())
      | basename ->
         let dir = Filename.dirname x in
         (Sys.chdir dir);
         let dir' = Sys.getcwd () in
         let y = Filename.concat dir' basename in
         Some y
    with _ -> None
  in
  (Sys.chdir cwd);
  result

end

module Mutex = MutexExtra.Recursive
let mutex = Mutex.create ()

let realpath ?s x = Mutex.apply_with_mutex mutex (Thread_unsafe.realpath ?s) x

IFDEF OCAML4_04_OR_LATER THEN
(** Slightly different from `realpath' in the sense that this function returns
    something (not None) if and only if all the items in the chain of symlinks,
    included the final target (that is not a symlink) exist.
    Example:
      Sys.command "ln -s /usr/bin /tmp/usr-bin" ;;
      - : int = 0

      Sys.command "realpath /tmp/usr-bin/non-existing-binary" ;;
      /usr/bin/non-existing-binary
      - : int = 0

      UnixExtra.realpath "/tmp/usr-bin/non-existing-binary" ;;
      - : string option = Some "/usr/bin/non-existing-binary"

      UnixExtra.realpath_exists "/tmp/usr-bin/" ;;
      - : string option = Some "/usr/bin"

      UnixExtra.realpath_exists "/tmp/usr-bin" ;;
      - : string option = Some "/usr/bin"

      UnixExtra.realpath_exists "/usr/bin/non-existing-exe" ;;
      - : string option = None
      *)
let rec realpath_exists =
  let rec follow d dx =
    try
      let y = Unix.readlink dx in
      let y0 = Filename.dirname  y in
      let y1 = Filename.basename y in
      let d' = if y0 = "." then d else if Filename.is_relative y0 then Printf.sprintf "%s/%s" d y0 else y0 in
      let dy = Printf.sprintf "%s/%s" d' y1 in
      follow d' dy
    with Unix.Unix_error (_,_,_) -> dx
  in
  fun x ->
    let x = Printf.sprintf "%s/%s" (Filename.dirname x) (Filename.basename x) in
    (* --- *)
    if not (Sys.file_exists x) then None else (* continue: *)
    (* Follow the link, if any, in order to have something real: *)
    let dy = follow (Filename.dirname x) x in
    (* --- *)
    if not (Sys.file_exists dy) then None else (* continue: *)
    (* --- *)
    (* If, after resolution, the target still remains relative,
       we transform it in an absolute path: *)
    let dz = FilenameExtra.simplify (FilenameExtra.to_absolute dy) in
    (* Now we have to recursively solve symlinks on the directory part. The result will be a
       path composed by real directory names (not symlinks) terminating with a real directory
       or file name (again, not a symlink): *)
    match (Filename.dirname dz) with
    | "/" -> Some (dz)
    |  d  -> Option.bind (realpath_exists d) (fun d' -> Some (Filename.concat d' (Filename.basename dz)))

ENDIF

(** Version working in the both cases implicit/explicit program
    reference as a shell interpreter. *)
let is_executable program =
  if Filename.is_implicit program
    then (path_of_implicit program) <> None
    else (Sys.file_exists program) && (test_access ~x:() program)

let realpath_alias = realpath

(** Version working in the both cases implicit/explicit program
    reference as a shell interpreter. *)
let resolve_executable ?realpath program =
  let result =
    if Filename.is_implicit program then
      Option.map (fun path -> Filename.concat path program) (path_of_implicit program)
    else
    if not (Sys.file_exists program) then None else
    if not (test_access ~x:() program) then None else
    Some program
  in
  if realpath = None then result else
  Option.bind result (fun pathname -> realpath_alias pathname)

(** Poor man profiling tool (based on Unix.gettimeofday): *)
(* val perf : ('a -> 'b) -> 'a -> 'b * float *)
let perf f x =
 let t0 = Unix.gettimeofday () in
 let y  = f x in
 let t1 = Unix.gettimeofday () in
 (y, t1 -. t0)
