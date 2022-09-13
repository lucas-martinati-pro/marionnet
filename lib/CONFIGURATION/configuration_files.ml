(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2008  Luca Saiu
   Copyright (C) 2012  Jean-Vincent Loddo
   Copyright (C) 2008 2012  Université Paris 13

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
 * - Luca Saiu: configuration_files.ml
 * - Jean-Vincent Loddo: refactoring
 *)

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

type varname = string

(** An alist is just a list of pairs: *)
type 'a alist =
    (string * 'a) list;;

(** For each variable bound in the shell environment echo its name and its value,
one binding per line: *)
let output_of_environment variables =
  let command_line =
    List.fold_left
      (fun string variable ->
        (* Print a line with: the variable name, a space, and its value,
           IF the variable is defined in the environment; otherwise don't
           print anything, and let the configuration file binding (if any)
           take precedence: *)
        Printf.sprintf
          "%s if test -n \"$%s\"; then echo %s \"$%s\"; fi; "
          string variable variable variable)
      ""
      variables in
  (* Printf.printf "The command line is\n%s\n" command_line; *)
  let (output, exit_code) = UnixExtra.run command_line in
  assert(exit_code = Unix.WEXITED 0);
  (* Printf.printf "The output is:\n-------------------------\n%s\n-------------------------\n" output; *)
  output;;

(** Evaluate the given file, then 'echo' each variable name and its value, one variable
    per line: *)
let output_of_file_name file_name variables =
  try
    let source_command_line =
      (* This is very important: dash does not support "source", you have to use the
         less readable, but more portable, ".": *)
      Printf.sprintf "set -e; (. %s 2> /dev/null &&" file_name 
    in
    let command_line =
      List.fold_left
        (fun string variable ->
          (* Print a line with: the variable name, a space, and its value *)
          Printf.sprintf "%s echo %s $%s && " string variable variable)
        source_command_line
        variables 
    in
    let command_line = command_line ^ " true) 2> /dev/null" in
    (* Printf.printf "The command line is %s\n" command_line; *)
    let (output, exit_code) = UnixExtra.run ~shell:"bash" command_line in
    if not (exit_code = Unix.WEXITED 0) then
      failwith ("Failed when source'ing the configuration file " ^ file_name)
    else begin
      (* Printf.printf "The output is:\n-------------------------\n%s\n-------------------------\n" output; *)
      output;
    end
  with _ -> begin
    (* Printf.printf "WARNING: could not source %s\n" file_name; *)
    "";
  end;;

(** Convert an output into a list of rows, where each row is a list of
    strings: first the variable name, then the value, possibly made of several
    tokens: *)
let matrix_of_output output =
  StringExtra.Text.Matrix.of_string output;;

(** Extract only the variable names from the matrix, disregarding values: *)
let variables_of_matrix matrix =
  List.map
    (fun row -> match row with
    | variable :: _ -> variable
    | _ -> assert false) (* no line should be empty *)
    matrix;;

(** Turn a matrix into an alist mapping each variable name into a value; each
    variable value (as a list of strings) is passed to the given function to
    obtain the value which is bound in the returned environment. Variables for
    which the given function fails are simply ignored: *)
let alist_of_matrix row_to_element matrix : 'a alist =
  let result = ref [] in
  List.iter
    (fun row ->
      match row with
      | (variable :: values) ->
          (try result := (variable, (row_to_element values)) :: !result; with _ -> ())
      | _ ->
          assert false)
    matrix;
  !result;;

(** Turn a matrix into an alist mapping each variable name into a value; each
    variable value (as a single string, with token separated by a single space)
    is passed to the given function to obtain the value which is bound in the
    returned environment. Variables for which the given function fails are simply
    ignored: *)
let scalar_alist_of_matrix string_to_element =
  alist_of_matrix
    (fun values -> string_to_element (String.concat " " values));;

(** Turn a matrix into an alist mapping each variable name into the list of
    the tokens of its value: *)
let list_alist_of_matrix =
  alist_of_matrix (fun values -> values);;

(** Turn a matrix into an alist mapping each variable name into the string
    containing its value (tokens concatenated into a string, separated by
    single spaces): *)
let string_alist_of_matrix =
  scalar_alist_of_matrix (fun string -> string);;

(** Turn a matrix into an alist mapping each variable name with an integer
    value into the integer. Non-integer-valued variables are ignored: *)
let int_alist_of_matrix =
  scalar_alist_of_matrix int_of_string;;

(** Turn a matrix into an alist mapping each variable name with an float
    value into the float. Non-float-valued variables are ignored: *)
let float_alist_of_matrix =
  scalar_alist_of_matrix float_of_string;;

(** Turn a matrix into an alist mapping each variable name with an bool
    value into the bool. Non-bool-valued variables are ignored: *)
let bool_alist_of_matrix =
  scalar_alist_of_matrix bool_of_string;;

(** Turn a matrix into a "tuple of alists", which henceforth means
    an alist of strings, an alist of ints, an alist of floats, an
    alist of bools, and an alist of lists of strings; as usual, values
    of the "wrong" type are ignored: *)
let alists_tuple_of_output output variables =
  let matrix = matrix_of_output output in
  let string_alist : (string * string) list        = string_alist_of_matrix matrix in
  let int_alist    : (string * int)    list        = int_alist_of_matrix    matrix in
  let float_alist  : (string * float)  list        = float_alist_of_matrix  matrix in
  let bool_alist   : (string * bool)   list        = bool_alist_of_matrix   matrix in
  let list_alist   : (string * (string list)) list = list_alist_of_matrix   matrix in
  (* --- *)
  (string_alist, int_alist, float_alist, bool_alist, list_alist)
;;

(** Turn a *file* into a tuple of alists: *)
let alists_tuple_of_file (file_name) (variables) =
  let output = output_of_file_name file_name variables in
  let (ts, ti, tf, tb, tl) = alists_tuple_of_output output variables in
  (* Inject now the information about the source (file_name) of the binding: *)
  let inj xys = List.map (fun (x,y) -> (x, (y, `Filename file_name))) xys in
  ((inj ts), (inj ti), (inj tf), (inj tb), (inj tl))
;;

(** Merge the two given alist groups; the latest one takes precedence: *)
let merge_alists xss yss =
  let (string_xs, int_xs, float_xs, bool_xs, list_xs) = xss in
  let (string_ys, int_ys, float_ys, bool_ys, list_ys) = yss in
  (string_xs @ string_ys,
      int_xs @ int_ys,
    float_xs @ float_ys,
     bool_xs @ bool_ys,
     list_xs @ list_ys)
;;

type source = [ `Filename of string | `Environment ] 

(** Make a configuration object from a list of file name or a software name;
    in the latter case the configuration files have "reasonable" default
    names; {b Example}:
{[let q = new configuration
  ~file_names:["~luca/working/ocamlbricks/MYSETTINGS"; "~luca/working/ocamlbricks/MYSETTINGS2"]
  ~software_name:"marionnet"
  ~variables:["ZZZ"; "fortytwo";]
  ();;

Printf.printf ">%s<\n" (q#string "ZZZ");;
Printf.printf ">%i<\n" (q#int "fortytwo");;
Printf.printf ">%f<\n" (q#float "fortytwo");;
]} *)
class configuration =
  fun ?software_name
      ?file_names
      ~variables
      ?(dont_read_environment:unit option)
      () ->
let read_environment = (dont_read_environment = None) in
let file_names =
  match file_names, software_name with
  | None, None ->
      failwith "either ~software_name or ~file_names should be passed"
  | (Some file_names), None ->
      file_names
  | None, (Some software_name) ->
      [ Printf.sprintf "/etc/%s/%s.conf" software_name software_name;
        Printf.sprintf "~/.%s/%s.conf" software_name software_name ]
  | (Some _), (Some _) ->
      failwith "you should pass exactly one of ~software_name and ~file_names"
in
object(self)
  (* Associative containers used for efficient access, after initialization: *)
  val string_hashmap = new Hashmap.hashmap ();
  val int_hashmap    = new Hashmap.hashmap ();
  val float_hashmap  = new Hashmap.hashmap ();
  val bool_hashmap   = new Hashmap.hashmap ();
  val list_hashmap   = new Hashmap.hashmap ();

  initializer 
    begin
      (* First execute all configuration files in the correct order, and merge the
        bindings: *)
      let alists =
        List.fold_left
          (fun accumulator file_name ->
            merge_alists accumulator (alists_tuple_of_file file_name variables))
          ([], [], [], [], [])
          file_names 
      in
      (* If we also want to access the shell environment, then look it up, and
        give it precedence over configuration files: *)
      let (string_alist, int_alist, float_alist, bool_alist, list_alist) =
        if read_environment then
          let environment_output = output_of_environment variables in
          let (ts, ti, tf, tb, tl) = alists_tuple_of_output environment_output variables in
          (* Inject now the information about the source (the environment) of the binding: *)
          let inj xys = List.map (fun (x,y) -> (x, (y, `Environment))) xys in
          let alists_tuple_env = ((inj ts), (inj ti), (inj tf), (inj tb), (inj tl)) in
          merge_alists alists (alists_tuple_env)
        else
          alists 
      in
      (* Finally convert the bindings from alists into hashes, for efficient access: *)
      string_hashmap#add_list string_alist;
      int_hashmap#add_list    int_alist;
      float_hashmap#add_list  float_alist;
      bool_hashmap#add_list   bool_alist;
      list_hashmap#add_list   list_alist;
    end
    
  (* The list of variable is redefined now as set: *)
  val expected_variables = SetExtra.String_set.of_list variables
  method check_expected_variable_or_raise_invalid_arg x =
    if (SetExtra.String_set.mem x expected_variables) then ()
    else invalid_arg (Printf.sprintf "Configuration_files: Unexpected variable name `%s'" x)

  method expected_variable x =
    (SetExtra.String_set.mem x expected_variables)

  (** Lookup a variable of the type [string]. *)
  method string x = fst (string_hashmap#lookup x)
  method string_with_source x : string * source = string_hashmap#lookup x

  (** Lookup a variable of the type [int]. *)
  method int x = fst (int_hashmap#lookup x)
  method int_with_source x : int * source  = int_hashmap#lookup x

  (** Lookup a variable of the type [float]. *)
  method float x = fst (float_hashmap#lookup x)
  method float_with_source x : float * source = float_hashmap#lookup x

  (** Lookup a variable of the type [bool]. *)
  method bool x = fst (bool_hashmap#lookup x)
  method bool_with_source x : bool * source = bool_hashmap#lookup x

  (** Lookup a variable of the type [string list]. *)
  method list x = fst (list_hashmap#lookup x)
  method list_with_source x : string list * source = list_hashmap#lookup x

end;; (* class *)


type t = configuration
let make = new configuration


module Polymorphic_functions = struct

let extract_variable_or :
  ?k:('a -> 'a) ->                                   (* An optional continuation *)
  ?log_printf:(string -> unit) Log_builder.printf -> (* An optional Log.printf *)
  ?ignore_undeclared:unit ->                         (* Do not fail, just warning if `log_printf' is provided *)
  ?unsuitable_value:('a -> bool) ->                  (* Filter unsuitable values *)
  to_string:('a -> string) ->                        (* String conversion for logging messages *)
  default:'a ->                                      (* The default value, if the variable is undeclared or its value unsuitable *)
  mthd:(varname -> 'a) ->                            (* The method of an instance of the class configuration. For instance `configuration#float' *)
  varname ->                                         (* The name of the variable *)
  t -> 'a
  =
  fun
  ?(k:('a -> 'a) option)
  ?(log_printf:((string->unit) Log_builder.printf) option)
  ?ignore_undeclared
  ?(unsuitable_value=(fun y -> false)) (* values are suitable by default *)
  ~(to_string:'a -> string)
  ~(default:'a)
  (* The method of an instance of the class configuration. For instance `configuration#float': *)
  ~(mthd:varname -> 'a)
  (varname:string)
  (t:t)
  ->
  let () =
    if ignore_undeclared = None
      then t#check_expected_variable_or_raise_invalid_arg varname
      else ()
  in
  let log_printf =
    match log_printf with
    | None -> fun ?v ?force ?banner _ _ -> ()
    | Some printf -> printf
  in
  let fallback e x =
    if (t#expected_variable x) then () else log_printf "Warning: %s not declared.\n" x
  in
  let use_default () =
    log_printf " - using default \"%s\"\n" (to_string default);
    default
  in
  let use_found_value y =
    log_printf " - found value \"%s\"\n" (to_string y);
    y
  in
  let result =
    log_printf "Searching for variable %s:\n" varname;
    match Option.apply_or_catch ~fallback mthd varname
    with
    | None -> use_default ()
    | Some y when (unsuitable_value y) -> use_default ()
    | Some y -> use_found_value y
   in
   (* Launch the continuation on the result: *)
   match k with None -> result | Some f -> (f result)
 ;;

let get_variable :
  ?k:('a -> 'a option) ->                            (* An optional continuation (called with Option.bind) *)
  ?log_printf:(string -> unit) Log_builder.printf -> (* An optional Log.printf *)
  ?ignore_undeclared:unit ->                         (* Do not fail, just warning if `log_printf' is provided *)
  ?unsuitable_value:('a -> bool) ->                  (* Filter unsuitable values *)
  to_string:('a -> string) ->                        (* String conversion for logging messages *)
  mthd:(varname -> 'a) ->                            (* The method of an instance of the class configuration. For instance `configuration#float' *)
  varname ->                                         (* The name of the variable *)
  t -> 'a option
  =
  fun
  ?(k:('a -> 'a option) option)
  ?(log_printf:((string->unit) Log_builder.printf) option)
  ?ignore_undeclared
  ?(unsuitable_value=(fun y -> false)) (* values are suitable by default *)
  ~(to_string:'a -> string)
  ~(mthd:varname -> 'a)
  varname
  t
  ->
  let () =
    if ignore_undeclared = None
      then t#check_expected_variable_or_raise_invalid_arg varname
      else ()
  in
  let log_printf =
    match log_printf with
    | None -> fun ?v ?force ?banner _ _ -> ()
    | Some printf -> printf
  in
  let fallback e x =
    if (t#expected_variable x) then () else log_printf "Warning: %s not declared.\n" x
  in
  let use_found_value y =
    log_printf " - found value \"%s\"\n" (to_string y);
    y
  in
  let result =
    log_printf "Searching for variable %s:\n" varname;
    match Option.apply_or_catch ~fallback mthd varname
    with
    | None -> None
    | Some y when (unsuitable_value y) -> None
    | Some y -> Some (use_found_value y)
   in
   (* Launch the continuation on the result: *)
   match k with None -> result | Some f -> Option.bind result f
 ;;

end (* module Polymorphic_functions *)


(* ============================================
     Now starts the user interface section...
   =========================================== *)

(** The type of functions looking in the structure for a variable and
    returning an optional result: *)
type 'a get_variable =
  ?k:('a -> 'a option) ->            (* An optional continuation (called with Option.bind) *)
  ?ignore_undeclared:unit ->         (* Do not fail when undeclared *)
  ?unsuitable_value:('a -> bool) ->  (* Filter unsuitable values *)
  varname ->                         (* The name of the variable *)
  t -> 'a option

(** The type of functions looking in the structure for a variable and
    returning the value found or a default: *)
type 'a extract_variable_or =
  ?k:('a -> 'a) ->                   (* An optional continuation *)
  ?ignore_undeclared:unit ->         (* Do not fail when undeclared *)
  ?unsuitable_value:('a -> bool) ->  (* Filter unsuitable values *)
  default:'a ->                      (* The default value, if the variable is undeclared or its value unsuitable *)
  varname ->                         (* The name of the variable *)
  t -> 'a

let get_bool_variable : bool get_variable =
  fun ?k ?ignore_undeclared ?unsuitable_value varname t ->
  Polymorphic_functions.get_variable ?k ?ignore_undeclared ?unsuitable_value
    ~to_string:(string_of_bool)
    ~mthd:(t#bool)
    varname t

let get_float_variable : float get_variable =
  fun ?k ?ignore_undeclared ?unsuitable_value varname t ->
  Polymorphic_functions.get_variable ?k ?ignore_undeclared ?unsuitable_value
    ~to_string:(string_of_float)
    ~mthd:(t#float)
    varname t

let get_int_variable : int get_variable =
  fun ?k ?ignore_undeclared ?unsuitable_value varname t ->
  Polymorphic_functions.get_variable ?k ?ignore_undeclared ?unsuitable_value
    ~to_string:(string_of_int)
    ~mthd:(t#int)
    varname t

let add_constraint_not_empty_string ?unsuitable_value () : (string -> bool) =
  let result = match unsuitable_value with
  | None    -> ((=)"")
  | Some f  -> (fun y -> (y="") || (f y))
  in
  result

let get_string_variable : string get_variable =
  fun ?k ?ignore_undeclared ?unsuitable_value varname t ->
  (* Empty strings are not considered as a result (=> None): *)
  let f = add_constraint_not_empty_string ?unsuitable_value () in
  Polymorphic_functions.get_variable ?k ?ignore_undeclared ~unsuitable_value:f
    ~to_string:(fun x -> x)
    ~mthd:(t#string)
    varname t

let get_string_list_variable : (string list) get_variable =
  fun ?k ?ignore_undeclared ?unsuitable_value varname t ->
  Polymorphic_functions.get_variable ?k ?ignore_undeclared ?unsuitable_value
    ~to_string:(String.concat " ")
    ~mthd:(t#list)
    varname t

let extract_bool_variable_or : bool extract_variable_or =
  fun ?k ?ignore_undeclared ?unsuitable_value ~default varname t ->
  Polymorphic_functions.extract_variable_or ?k ?ignore_undeclared ?unsuitable_value
    ~to_string:(string_of_bool)
    ~default
    ~mthd:(t#bool)
    varname t

let extract_float_variable_or : float extract_variable_or =
  fun ?k ?ignore_undeclared ?unsuitable_value ~default varname t ->
  Polymorphic_functions.extract_variable_or ?k ?ignore_undeclared ?unsuitable_value
    ~to_string:(string_of_float)
    ~default
    ~mthd:(t#float)
    varname t

let extract_int_variable_or : int extract_variable_or =
  fun ?k ?ignore_undeclared ?unsuitable_value ~default varname t ->
  Polymorphic_functions.extract_variable_or ?k ?ignore_undeclared ?unsuitable_value
    ~to_string:(string_of_int)
    ~default
    ~mthd:(t#int)
    varname t

let extract_string_variable_or : string extract_variable_or =
  fun ?k ?ignore_undeclared ?unsuitable_value ~default varname t ->
  (* Empty strings are not considered as a result (=> default): *)
  let f = add_constraint_not_empty_string ?unsuitable_value () in
  Polymorphic_functions.extract_variable_or ?k ?ignore_undeclared ~unsuitable_value:f
    ~to_string:(fun x->x)
    ~default
    ~mthd:(t#string)
    varname t

let extract_string_list_variable_or : (string list) extract_variable_or =
  fun ?k ?ignore_undeclared ?unsuitable_value ~default varname t ->
  Polymorphic_functions.extract_variable_or ?k ?ignore_undeclared ?unsuitable_value
    ~to_string:(String.concat " ")
    ~default
    ~mthd:(t#list)
    varname t

module With_source = struct
  
  let string_of_source = function
  | `Environment -> "<Environment>"
  | `Filename f  -> f
  
  let get_bool_variable : (bool * source) get_variable =
    fun ?k ?ignore_undeclared ?unsuitable_value varname t ->
    Polymorphic_functions.get_variable ?k ?ignore_undeclared ?unsuitable_value
      ~to_string:(fun (x,s) -> Printf.sprintf "(%b, %s)" x (string_of_source s))
      ~mthd:(t#bool_with_source)
      varname t

  let get_float_variable : (float * source) get_variable =
    fun ?k ?ignore_undeclared ?unsuitable_value varname t ->
    Polymorphic_functions.get_variable ?k ?ignore_undeclared ?unsuitable_value
      ~to_string:(fun (x,s) -> Printf.sprintf "(%F, %s)" x (string_of_source s))
      ~mthd:(t#float_with_source)
      varname t

  let get_int_variable : (int * source) get_variable =
    fun ?k ?ignore_undeclared ?unsuitable_value varname t ->
    Polymorphic_functions.get_variable ?k ?ignore_undeclared ?unsuitable_value
      ~to_string:(fun (x,s) -> Printf.sprintf "(%d, %s)" x (string_of_source s))
      ~mthd:(t#int_with_source)
      varname t

  let add_constraint_not_empty_string ?unsuitable_value () : (string * source -> bool) =
    let result = match unsuitable_value with
    | None    -> (fun (x,s) -> x = "")
    | Some f  -> (fun (y,s) -> (y="") || (f (y,s)))
    in
    result
      
  let get_string_variable : (string * source) get_variable =
    fun ?k ?ignore_undeclared ?unsuitable_value varname t ->
    (* Empty strings are not considered as a result (=> None): *)
    let f = add_constraint_not_empty_string ?unsuitable_value () in
    Polymorphic_functions.get_variable ?k ?ignore_undeclared ~unsuitable_value:f
      ~to_string:(fun (x,s) -> Printf.sprintf "(%s, %s)" x (string_of_source s))
      ~mthd:(t#string_with_source)
      varname t

  let get_string_list_variable : ((string list) * source) get_variable =
    fun ?k ?ignore_undeclared ?unsuitable_value varname t ->
    Polymorphic_functions.get_variable ?k ?ignore_undeclared ?unsuitable_value
      ~to_string:(fun (x,s) -> Printf.sprintf "([%s], %s)" (String.concat "; " x) (string_of_source s))
      ~mthd:(t#list_with_source)
      varname t
      
end
    
(* Versions with logging features: *)
module Logging = struct

  (** The type of (logged) functions looking in the structure for a variable and returning an optional result: *)
  type 'a get_variable =
    ?k:('a -> 'a option) ->                                (* An optional continuation (called with Option.bind) *)
    ?log_printf:(string -> unit) Log_builder.printf ->     (* An optional Log.printf *)
    ?ignore_undeclared:unit ->                             (* Do not fail, just warning (supposing that `log_printf' has been provided) *)
    ?unsuitable_value:('a -> bool) ->                      (* Filter unsuitable values *)
    varname ->                                             (* The name of the variable *)
    t -> 'a option

  (** The type of (logged) functions looking in the structure for a variable and returning the value found or a default: *)
  type 'a extract_variable_or =
    ?k:('a -> 'a) ->                                       (* An optional continuation *)
    ?log_printf:(string -> unit) Log_builder.printf ->     (* An optional Log.printf *)
    ?ignore_undeclared:unit ->                             (* Do not fail, just warning (supposing that `log_printf' has been provided) *)
    ?unsuitable_value:('a -> bool) ->                      (* Filter unsuitable values *)
    default:'a ->                                          (* The default value, if the variable is undeclared or its value unsuitable *)
    varname ->                                             (* The name of the variable *)
    t -> 'a

  let get_bool_variable : bool get_variable =
    fun ?k ?log_printf ?ignore_undeclared ?unsuitable_value varname t ->
    Polymorphic_functions.get_variable ?k ?ignore_undeclared ?unsuitable_value
      ~log_printf:(Option.extract_or log_printf Ocamlbricks_log.printf1)
      ~to_string:(string_of_bool)
      ~mthd:(t#bool)
      varname t

  let get_float_variable : float get_variable =
    fun ?k ?log_printf ?ignore_undeclared ?unsuitable_value varname t ->
    Polymorphic_functions.get_variable ?k ?ignore_undeclared ?unsuitable_value
      ~log_printf:(Option.extract_or log_printf Ocamlbricks_log.printf1)
      ~to_string:(string_of_float)
      ~mthd:(t#float)
      varname t

  let get_int_variable : int get_variable =
    fun ?k ?log_printf ?ignore_undeclared ?unsuitable_value varname t ->
    Polymorphic_functions.get_variable ?k ?ignore_undeclared ?unsuitable_value
      ~log_printf:(Option.extract_or log_printf Ocamlbricks_log.printf1)
      ~to_string:(string_of_int)
      ~mthd:(t#int)
      varname t

  let get_string_variable : string get_variable =
    fun ?k ?log_printf ?ignore_undeclared ?unsuitable_value varname t ->
    (* Empty strings are not considered as a result (=> default): *)
    let f = add_constraint_not_empty_string ?unsuitable_value () in
    Polymorphic_functions.get_variable ?k ?ignore_undeclared ~unsuitable_value:f
      ~log_printf:(Option.extract_or log_printf Ocamlbricks_log.printf1)
      ~to_string:(fun x -> x)
      ~mthd:(t#string)
      varname t

  let get_string_list_variable : (string list) get_variable =
    fun ?k ?log_printf ?ignore_undeclared ?unsuitable_value varname t ->
    Polymorphic_functions.get_variable ?k ?ignore_undeclared ?unsuitable_value
      ~log_printf:(Option.extract_or log_printf Ocamlbricks_log.printf1)
      ~to_string:(String.concat " ")
      ~mthd:(t#list)
      varname t

  let extract_bool_variable_or : bool extract_variable_or =
    fun ?k ?log_printf ?ignore_undeclared ?unsuitable_value ~default varname t ->
    Polymorphic_functions.extract_variable_or ?k ?ignore_undeclared ?unsuitable_value
      ~log_printf:(Option.extract_or log_printf Ocamlbricks_log.printf1)
      ~to_string:(string_of_bool)
      ~default
      ~mthd:(t#bool)
      varname t

  let extract_float_variable_or : float extract_variable_or =
    fun ?k ?log_printf ?ignore_undeclared ?unsuitable_value ~default varname t ->
    Polymorphic_functions.extract_variable_or ?k ?ignore_undeclared ?unsuitable_value
      ~log_printf:(Option.extract_or log_printf Ocamlbricks_log.printf1)
      ~to_string:(string_of_float)
      ~default
      ~mthd:(t#float)
      varname t

  let extract_int_variable_or : int extract_variable_or =
    fun ?k ?log_printf ?ignore_undeclared ?unsuitable_value ~default varname t ->
    Polymorphic_functions.extract_variable_or ?k ?ignore_undeclared ?unsuitable_value
      ~log_printf:(Option.extract_or log_printf Ocamlbricks_log.printf1)
      ~to_string:(string_of_int)
      ~default
      ~mthd:(t#int)
      varname t

  let extract_string_variable_or : string extract_variable_or =
    fun ?k ?log_printf ?ignore_undeclared ?unsuitable_value ~default varname t ->
    (* Empty strings are not considered as a result (=> default): *)
    let f = add_constraint_not_empty_string ?unsuitable_value () in
    Polymorphic_functions.extract_variable_or ?k ?ignore_undeclared ~unsuitable_value:f
      ~log_printf:(Option.extract_or log_printf Ocamlbricks_log.printf1)
      ~to_string:(fun x->x)
      ~default
      ~mthd:(t#string)
      varname t

  let extract_string_list_variable_or : (string list) extract_variable_or =
    fun ?k ?log_printf ?ignore_undeclared ?unsuitable_value ~default varname t ->
    Polymorphic_functions.extract_variable_or ?k ?ignore_undeclared ?unsuitable_value
      ~log_printf:(Option.extract_or log_printf Ocamlbricks_log.printf1)
      ~to_string:(String.concat " ")
      ~default
      ~mthd:(t#list)
      varname t

end (* Logging *)
