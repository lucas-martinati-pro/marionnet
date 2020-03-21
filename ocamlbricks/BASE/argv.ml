(* This file is part of ocamlbricks
   Copyright (C) 2012  Jean-Vincent Loddo

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

(* -----------------------------------------
          Module's hidden state
   ----------------------------------------- *)

type error_msg = string
type argument_spec =
  | Optional      of (string -> unit)
  | Mandatory     of (string -> unit) * error_msg
  | List0         of (string -> unit)
  | List1         of (string -> unit) * error_msg
  | Optional_last of (string -> unit)
  | List0_last    of (string -> unit)
  | List1_last    of (string -> unit) * error_msg

let options_register = ref [] ;;
let arguments_register : argument_spec list ref  = ref [] ;;
let usage_msg = ref "Usage: " ;;

module Tuning = struct
  let no_error_location_parsing_arguments = ref None
  let no_usage_on_error_parsing_arguments = ref None
end

let tuning
  ?no_error_location_parsing_arguments
  ?no_usage_on_error_parsing_arguments
  ()
  =
  begin
    Tuning.no_error_location_parsing_arguments := no_error_location_parsing_arguments;
    Tuning.no_usage_on_error_parsing_arguments := no_usage_on_error_parsing_arguments;
  end

(* -----------------------------------------
                    Usage
   ----------------------------------------- *)

let register_usage_msg x =
  usage_msg := x
;;

let register_h_option_as_help () =
  let spec_list () = Arg.align (List.rev !options_register) in
  let doc = " Display this list of options" in
  let spec = (("-h"), Arg.Unit (fun () -> Printf.printf "%s" (Arg.usage_string (spec_list ()) !usage_msg); exit 0), doc) in
  (options_register := spec::!options_register);
  ()
;;

(* -----------------------------------------
                  Options
   ----------------------------------------- *)

let properly_append_arg_name_in_help_and_doc ~arg_name_in_help ~doc =
  let doc = if (String.get doc 0 <> ' ') then (" "^doc) else doc in
  (arg_name_in_help ^ doc)
;;

let register_unit_option (x:string) ?(aliases=[]) ?(doc="undocumented") ?(default=None) ?toggle () =
  let doc = properly_append_arg_name_in_help_and_doc ~arg_name_in_help:"" ~doc in
  let result = ref default in
  let callback =
    match toggle with
    | None    -> (fun () -> result := Some ())
    | Some () -> (fun () -> result := if !result=None then Some () else None)
  in
  List.iter
    (fun x ->
       let spec = (("-"^x), Arg.Unit callback, doc) in
       (options_register := spec::!options_register))
    (x::aliases);
  result
;;

let register_bool_option (x:string) ?(aliases=[]) ?(arg_name_in_help="BOOL") ?(doc="undocumented") ?(default=None) () =
  let doc = properly_append_arg_name_in_help_and_doc ~arg_name_in_help ~doc in
  let result = ref default in
  List.iter
    (fun x ->
       let spec = (("-"^x), Arg.Bool (fun v -> result := Some v), doc) in
       (options_register := spec::!options_register))
    (x::aliases);
  result
;;

(* val compose_tests : (('a -> bool) * error_msg) list -> 'a -> error_msg option *)
let rec compose_tests tests =
  fun v ->
    match tests with
    | [] -> None (* it's fine, no errors *)
    | (test_pred, test_err_msg)::tests ->
	if test_pred v then compose_tests tests v else (Some test_err_msg)
;;

(* val properly_compose_with_tests : ?tests:(('a -> bool) * error_msg) list -> ('a -> 'b) -> ('a -> 'b) *)
let properly_compose_with_tests ?tests normal_callback =
  match tests with
  | None -> normal_callback
  | Some tests ->
      (fun v ->
         match compose_tests tests v with
         | None -> normal_callback v
         | Some err_msg -> raise (Arg.Bad err_msg)
         )
;;

let convert_int_tests_into_string_tests ?tests () =
  match tests with
  | None -> None
  | Some pms ->
      Some (List.map (fun (p,m)-> (fun (x:string) -> (p (int_of_string x))),m) pms)
;;

let convert_float_tests_into_string_tests ?tests () =
  match tests with
  | None -> None
  | Some pms ->
      Some(List.map (fun (p,m)-> (fun (x:string) -> (p (float_of_string x))),m) pms)
;;

let register_string_option (x:string) ?(aliases=[]) ?tests ?(arg_name_in_help="STRING") ?(doc="undocumented") ?(default=None) () =
  let result = ref default in
  let doc = properly_append_arg_name_in_help_and_doc ~arg_name_in_help ~doc in
  let callback = properly_compose_with_tests ?tests (fun v -> result := Some v) in
  List.iter
    (fun x ->
       let spec = (("-"^x), Arg.String callback, doc) in
       (options_register := spec::!options_register))
    (x::aliases);
  result
;;

(** Could the process perform some operations on the file:
    read ([?r]) and/or write ([?w]) and/or execution ([?x])?
    Copied from UnixExtra in order to break the dependence. *)
let test_access ?r ?w ?x filename : bool =
 let xs = [(r,Unix.R_OK); (w,Unix.W_OK); (x,Unix.X_OK)] in
 let xs = List.filter (fun (v,_)-> v<>None) xs in
 let xs = Unix.F_OK::(List.map snd xs) in
 try
   let _ = Unix.access filename xs in true
 with Unix.Unix_error (_,_,_) -> false
;;

let words_about_access ?r ?w ?x () =
  let xs = [(r,"readable"); (w,"writable"); (x,"executable")] in
  let xs = List.filter (fun (v,_)-> v<>None) xs in
  String.concat " and " (List.map snd xs)
;;

let test_kind ?follow ?f ?d ?c ?b ?h ?p ?socket filename =
 let xs =
   [(f, Unix.S_REG); (d, Unix.S_DIR); (c, Unix.S_CHR); (b, Unix.S_BLK); (h, Unix.S_LNK);
    (p, Unix.S_FIFO); (socket, Unix.S_SOCK) ]
 in
 let xs = List.filter (fun (v,_)-> v<>None) xs in
 let xs = (List.map snd xs) in
 match xs with
 | [] -> true
 | [expected_file_kind] ->
     (try
       let infos = (if follow=None then Unix.stat else Unix.lstat) filename in
       infos.Unix.st_kind = expected_file_kind
      with Unix.Unix_error (_,_,_) -> false)
 | _ -> false (* No condition was given *)
;;

let words_about_kind ?follow ?f ?d ?c ?b ?h ?p ?socket () =
  let xs =
    [(h, "symlink");
     (f, "regular"); (d, "directory"); (c, "character device"); (b, "block device");
     (p, "named pipe"); (socket, "socket") ]
  in
  let xs = List.filter (fun (v,_)-> v<>None) xs in
  (assert ((List.length xs) <= 2));
  (* If there are two elements, the first is "symlink" (because of the option ?follow) *)
  String.concat " -> " (List.map snd xs)
;;

let parenthesis_about_access_and_kind ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket () =
  let r1 = words_about_access ?r ?w ?x () in
  let r2 = words_about_kind ?follow ?f ?d ?c ?b ?h ?p ?socket () in
  let r = String.concat " " (List.filter ((<>)"") [r1; r2]) in
  if r="" then r else (Printf.sprintf "(%s) " r)

let test_access_and_kind ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket filename =
  (test_access ?r ?w ?x filename) && (test_kind ?follow ?f ?d ?c ?b ?h ?p ?socket filename)
;;

let register_filename_option
  (y:string)
  ?aliases ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket ?error_msg ?tests
  ?(arg_name_in_help="FILE") ?doc ?default ()
  =
  let file_test =
    let pred = (test_access_and_kind ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket) in
    let err_msg =
      match error_msg with
      | Some m -> m
      | None ->
	  let parenthesis = parenthesis_about_access_and_kind ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket () in
	  Printf.sprintf "file doesn't exist or does not fit the conditions; option `-%s' expects a %sfile name." y parenthesis
    in
    (pred, err_msg)
  in
  (* File related test will be applied foremost: *)
  let tests = file_test::(match tests with None -> [] | Some ts -> ts) in
  register_string_option y ?aliases ~arg_name_in_help ~tests ?doc ?default ()
;;

let register_directory_option
  (y:string)
  ?aliases ?r ?w ?x ?error_msg ?tests
  ?(arg_name_in_help="DIR") ?doc ?default ()
  =
  let file_test =
    (* In order to prevent the exception that Sys.is_directory could raise: *)
    let pred v = (Sys.file_exists v) && (Sys.is_directory v) && (test_access ?r ?w ?x v) in
    let err_msg =
      match error_msg with
      | Some m -> m
      | None ->
          let parenthesis = parenthesis_about_access_and_kind ?r ?w ?x () in
          Printf.sprintf "directory doesn't exist or does not fit the conditions; option `-%s' expects a %sdirectory." y parenthesis
    in
    (pred, err_msg)
  in
  (* File related test will be applied foremost: *)
  let tests = file_test::(match tests with None -> [] | Some ts -> ts) in
  register_string_option y ?aliases ~arg_name_in_help ~tests ?doc ?default ()
;;

let register_enum_option (x:string) ?(aliases=[]) ~admissible_args ?(doc="undocumented") ?(default=None) () =
  let result = ref default in
  let doc = properly_append_arg_name_in_help_and_doc ~arg_name_in_help:"" ~doc in
  List.iter
    (fun x ->
       let spec = (("-"^x), Arg.Symbol (admissible_args, fun v -> result := Some v), doc) in
       (options_register := spec::!options_register))
    (x::aliases);
  result
;;

let register_int_option (x:string) ?(aliases=[]) ?tests ?(arg_name_in_help="INT") ?(doc="undocumented") ?(default=None) () =
  let result = ref default in
  let doc = properly_append_arg_name_in_help_and_doc ~arg_name_in_help ~doc in
  let callback = properly_compose_with_tests ?tests (fun v -> result := Some v) in
  List.iter
    (fun x ->
       let spec = (("-"^x), Arg.Int callback, doc) in
       (options_register := spec::!options_register))
    (x::aliases);
  result
;;

let register_float_option (x:string) ?(aliases=[]) ?tests ?(arg_name_in_help="FLOAT") ?(doc="undocumented") ?(default=None) () =
  let result = ref default in
  let doc = properly_append_arg_name_in_help_and_doc ~arg_name_in_help ~doc in
  let callback = properly_compose_with_tests ?tests (fun v -> result := Some v) in
  List.iter
    (fun x ->
       let spec = (("-"^x), Arg.Float callback, doc) in
       (options_register := spec::!options_register))
    (x::aliases);
  result
;;

(* -----------------------------------------
                String arguments
   ----------------------------------------- *)

let register_string_optional_argument ?tests ?(default=None) () =
  let result = ref default in
  let callback = properly_compose_with_tests ?tests (fun v -> result := Some v) in
  let spec = Optional callback in
  (arguments_register := spec::!arguments_register);
  result
;;

let register_string_argument ?tests ?(error_msg="argument expected") () =
  let result = ref "" in
  let callback = properly_compose_with_tests ?tests (fun v -> result := v) in
  let spec = Mandatory (callback, error_msg) in
  (arguments_register := spec::!arguments_register);
  result
;;

let register_string_list0_argument ?tests () =
  let result = ref [] in
  let callback = properly_compose_with_tests ?tests (fun v -> result := v::!result) in
  (arguments_register := (List0 callback)::!arguments_register);
  result
;;

let register_string_list1_argument ?tests ?(error_msg="argument(s) expected") () =
  let result = ref [] in
  let callback = properly_compose_with_tests ?tests (fun v -> result := v::!result) in
  (arguments_register := (List1 (callback, error_msg))::!arguments_register);
  result
;;

(* -----------------------------------------
                Int arguments
   ----------------------------------------- *)

let register_int_optional_argument ?tests ?(default=None) () =
  let result = ref default in
  let tests = convert_int_tests_into_string_tests ?tests () in
  let callback = properly_compose_with_tests ?tests (fun v -> result := Some (int_of_string v)) in
  let spec = Optional callback in
  (arguments_register := spec::!arguments_register);
  result
;;

let register_int_argument ?tests ?(error_msg="int argument expected") () =
  let result = ref 42 in
  let tests = convert_int_tests_into_string_tests ?tests () in
  let callback = properly_compose_with_tests ?tests (fun v -> result := (int_of_string v)) in
  let spec = Mandatory (callback, error_msg) in
  (arguments_register := spec::!arguments_register);
  result
;;

let register_int_list0_argument ?tests () =
  let result = ref [] in
  let tests = convert_int_tests_into_string_tests ?tests () in
  let callback = properly_compose_with_tests ?tests (fun v -> result := (int_of_string v)::!result) in
  (arguments_register := (List0 callback)::!arguments_register);
  result
;;

let register_int_list1_argument ?tests ?(error_msg="int argument(s) expected") () =
  let result = ref [] in
  let tests = convert_int_tests_into_string_tests ?tests () in
  let callback = properly_compose_with_tests ?tests (fun v -> result := (int_of_string v)::!result) in
  (arguments_register := (List1 (callback, error_msg))::!arguments_register);
  result
;;

(* -----------------------------------------
                Float arguments
   ----------------------------------------- *)

let register_float_optional_argument ?tests ?(default=None) () =
  let result = ref default in
  let tests = convert_float_tests_into_string_tests ?tests () in
  let callback = properly_compose_with_tests ?tests (fun v -> result := Some (float_of_string v)) in
  let spec = Optional callback in
  (arguments_register := spec::!arguments_register);
  result
;;

let register_float_argument ?tests ?(error_msg="float argument expected") () =
  let result = ref 42. in
  let tests = convert_float_tests_into_string_tests ?tests () in
  let callback = properly_compose_with_tests ?tests (fun v -> result := (float_of_string v)) in
  let spec = Mandatory (callback, error_msg) in
  (arguments_register := spec::!arguments_register);
  result
;;

let register_float_list0_argument ?tests () =
  let result = ref [] in
  let tests = convert_float_tests_into_string_tests ?tests () in
  let callback = properly_compose_with_tests ?tests (fun v -> result := (float_of_string v)::!result) in
  (arguments_register := (List0 callback)::!arguments_register);
  result
;;

let register_float_list1_argument ?tests ?(error_msg="float argument(s) expected") () =
  let result = ref [] in
  let tests = convert_float_tests_into_string_tests ?tests () in
  let callback = properly_compose_with_tests ?tests (fun v -> result := (float_of_string v)::!result) in
  (arguments_register := (List1 (callback, error_msg))::!arguments_register);
  result
;;

(* -----------------------------------------
                Bool arguments
   ----------------------------------------- *)

IFNDEF OCAML4_04_OR_LATER THEN
let lowercase = String.lowercase
ELSE
let lowercase = String.lowercase_ascii
ENDIF

let register_bool_optional_argument ?(default=None) () =
  let result = ref default in
  let spec = Optional (fun v -> result := Some (bool_of_string (lowercase v))) in
  (arguments_register := spec::!arguments_register);
  result
;;

let register_bool_argument ?(error_msg="bool argument expected") () =
  let result = ref true in
  let spec = Mandatory ((fun v -> result := (bool_of_string v)), error_msg) in
  (arguments_register := spec::!arguments_register);
  result
;;

let register_bool_list0_argument () =
  let result = ref [] in
  let callback = (fun v -> result := (bool_of_string (lowercase v))::!result) in
  (arguments_register := (List0 callback)::!arguments_register);
  result
;;

let register_bool_list1_argument ?(error_msg="bool argument(s) expected") () =
  let result = ref [] in
  let callback = (fun v -> result := (bool_of_string v)::!result) in
  (arguments_register := (List1 (callback, error_msg))::!arguments_register);
  result
;;

(* -----------------------------------------
                File arguments
   ----------------------------------------- *)

let make_filename_test_for_argument
  ?(what="file") ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket ?error_msg
  ()
  =
  let pred = (test_access_and_kind ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket) in
  let err_msg =
    match error_msg with
    | Some m -> m
    | None ->
        let parenthesis = parenthesis_about_access_and_kind ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket () in
        Printf.sprintf "the expected %s%s doesn't exist or does not fit the conditions" parenthesis what
  in
  (pred, err_msg)

(* File related test will be applied foremost: *)
let make_filename_tests ?what ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket ?error_msg ?tests () =
  let file_test = make_filename_test_for_argument ?what ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket ?error_msg () in
  file_test::(match tests with None -> [] | Some ts -> ts)

let register_filename_optional_argument ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket ?error_msg ?tests ?default () =
  let tests = make_filename_tests ~what:"file" ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket ?error_msg ?tests () in
  register_string_optional_argument ~tests ?default ()
;;

let register_filename_argument ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket ?error_msg ?tests () =
  let tests = make_filename_tests ~what:"file" ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket ?error_msg ?tests () in
  register_string_argument ~tests ~error_msg:"filename expected" ()
;;

let register_filename_list0_argument ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket ?error_msg ?tests () =
  let tests = make_filename_tests ~what:"file" ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket ?error_msg ?tests () in
  register_string_list0_argument ~tests ()
;;

let register_filename_list1_argument ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket ?error_msg ?tests () =
  let tests = make_filename_tests ~what:"file" ?r ?w ?x ?follow ?f ?d ?c ?b ?h ?p ?socket ?error_msg ?tests () in
  register_string_list1_argument ~tests ~error_msg:"filename(s) expected" ()
;;


(* -----------------------------------------
                Parsing actuals
   ----------------------------------------- *)


type attempt = Success of unit | Failure of error_msg

let attempt_and_branch ?(err_msg="attempt_and_branch") f a ~success ~failure =
  let attempt =
    try
      Success (f a)
    with
      | Arg.Bad err_msg -> Failure err_msg
      | _               -> Failure err_msg (* in this case failure does not really need an argument *)
  in
  (* Note that it's relevant that the continuations (success and failure)
     are called out of the try-with bloc: *)
  match attempt with
  | Success ()      -> success ()
  | Failure err_msg -> failure err_msg
;;

let parse_actuals ~usage_with_options ~arguments_spec_list ~actuals =
  let raise_bad nth err_msg =
    let usage_with_options =
      if !Tuning.no_usage_on_error_parsing_arguments<>None
        then ""
        else Lazy.force usage_with_options
    in
    let bad_err_msg =
      match !Tuning.no_error_location_parsing_arguments with
      | None    -> Printf.sprintf "%s: argument #%d: %s\n%s" Sys.argv.(0) nth err_msg usage_with_options
      | Some () -> Printf.sprintf "%s\n%s" err_msg usage_with_options
    in
    (raise (Arg.Bad bad_err_msg))
  in
  let rec loop nth sl al =
    match sl,al with
    | (Optional f)::sl', a::al' ->
         attempt_and_branch f a
           ~success:(fun () -> loop (nth+1) sl' al')
           ~failure:(fun  _ -> loop nth sl' al)

    | (Optional f)::sl', [] ->
         loop nth sl' []

    | (Optional_last f)::sl', a::al' ->
         attempt_and_branch f a
           ~success:(fun () -> loop (nth+1) sl' al')
           ~failure:(raise_bad nth)

    | (Optional_last f)::sl', [] ->
         loop nth sl' []

    | (Mandatory (f, _))::sl', a::al' ->
         (* In case of failure, the error_msg is provided by the raised exception: *)
         attempt_and_branch f a ~success:(fun () -> loop (nth+1) sl' al') ~failure:(raise_bad nth)

    | (Mandatory (f, err_msg))::sl', [] ->
         (raise_bad nth err_msg)

    | (List0 f)::sl', a::al' ->
         attempt_and_branch f a
           ~success:(fun () ->loop (nth+1) sl al')
           ~failure:(fun _ -> loop nth sl' al)

    | (List0 f)::sl', [] ->
         loop nth sl' []

    | (List1 (f, _))::sl', a::al' ->
         (* In case of failure, the error_msg is provided by the raised exception: *)
         attempt_and_branch f a
           ~success:(fun () -> loop (nth+1) ((List0 f)::sl') al')
           ~failure:(raise_bad nth)

    | (List1 (f, err_msg))::sl', [] ->
         (raise_bad nth err_msg)

    | (List0_last f)::sl', a::al' ->
         (* In case of failure, the error_msg is provided by the raised exception: *)
         attempt_and_branch f a ~success:(fun () -> loop (nth+1) sl al') ~failure:(raise_bad nth)

    | (List0_last f)::sl', [] ->
         loop nth sl' []

    | (List1_last (f, _))::sl', a::al' ->
         (* In case of failure, the error_msg is provided by the raised exception: *)
         attempt_and_branch f a
           ~success:(fun () -> loop (nth+1) ((List0_last f)::sl') al')
           ~failure:(raise_bad nth)

    | (List1_last (f, err_msg))::sl', [] ->
         (raise_bad nth err_msg)

    | [], a::al' ->
         let err_msg = Printf.sprintf "unexpected argument `%s'" a in
         (raise_bad nth err_msg)

    | [], [] -> ()
  in
  loop 1 arguments_spec_list actuals

(* -----------------------------------------
           Parsing command line
   ----------------------------------------- *)

let get_options_spec_list () =
  Arg.align (List.rev !options_register)

let get_arguments_spec_list () =
  (* Tagging the last list allows us to offer a more comprehensible error message to the user.
     Indeed, instead of having error messages in the form "unexpected argument", we will have
     the error message raised by the last executed test (associated to the last list). *)
  let xs =
    match !arguments_register with
    | (Optional f)::xs        -> (Optional_last f)::xs
    | (List0 f)::xs           -> (List0_last f)::xs
    | (List1 (f,err_msg))::xs -> (List1_last (f,err_msg))::xs
    | xs -> xs
  in
  List.rev xs

let parse_argv argv =
  let options_spec_list = get_options_spec_list () in
  let actuals = ref [] in
  let anon_fun_collecting_actuals = fun (x:string) -> (actuals := x::!actuals) in
  (* Parse the actual options: *)
  let () = Arg.parse_argv argv options_spec_list anon_fun_collecting_actuals !usage_msg in
  (* Parse now the actual arguments: *)
  let () =
    parse_actuals
      ~usage_with_options:(lazy (Arg.usage_string options_spec_list !usage_msg))
      ~arguments_spec_list:(get_arguments_spec_list ())
      ~actuals:(List.rev !actuals)
  in
  ()
;;

let parse ?(exit_with_errno=1) () =
 try
  let options_spec_list = get_options_spec_list () in
  let actuals = ref [] in
  let anon_fun_collecting_actuals = fun (x:string) -> (actuals := x::!actuals) in
  (* Parse the actual options: *)
  let () = Arg.parse options_spec_list anon_fun_collecting_actuals !usage_msg in
  (* Parse now the actual arguments: *)
  let () =
    parse_actuals
      ~usage_with_options:(lazy (Arg.usage_string options_spec_list !usage_msg))
      ~arguments_spec_list:(get_arguments_spec_list ())
      ~actuals:(List.rev !actuals)
  in
  ()
 with Arg.Bad msg ->
   begin
     Printf.fprintf stderr "%s" msg;
     exit exit_with_errno;
   end
;;
