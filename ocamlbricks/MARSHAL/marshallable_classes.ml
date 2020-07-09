(*  This file is part of ocamlbricks
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
    along with this program.  If not, see <http://www.gnu.org/licenses/>.*)

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

IFNDEF OCAML4_02_OR_LATER THEN
module Bytes = struct  include String  let to_string x = x  let of_string x = x  end
type bytes = string
ENDIF

IFDEF OCAML4_07_OR_LATER THEN
module Pervasives = Stdlib
ENDIF

let marshallable_classes_version = "0.1" ;;

let marshallable_classes_metadata () =
 Printf.sprintf "marshallable_classes version %s (executable %s)
Copyright (C) 2012  Jean-Vincent Loddo,
This is free software; see the source for copying conditions.
There is NO warranty; not even for MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.
" (marshallable_classes_version) (Sys.executable_name)
;;

(* ********************************* *
         WARNINGS and TRACING
 * ********************************* *)
let warnings = ref true ;;
let enable_warnings  () = (warnings := true);;
let disable_warnings () = (warnings := false);;
let are_warnings_enable () = !warnings
let are_warnings_disabled () = not !warnings

let tracing = ref false ;;
let enable_tracing  () = (tracing := true);;
let disable_tracing () = (tracing := false);;
let is_tracing_enable () = !tracing
let is_tracing_disabled () = not !tracing

(* ********************************* *
              TOOLS
 * ********************************* *)

let with_open_in_bin ~filename mtdh =
  let in_channel = open_in_bin filename in
  let length = in_channel_length (in_channel) in
  let result = mtdh in_channel length in
  close_in in_channel;
  result
;;

let with_open_out_bin ?(perm=0o644) ~filename mtdh =
  let file_exists = Sys.file_exists filename in
  let out_channel = open_out_gen [Open_wronly; Open_creat; Open_trunc; Open_binary] 0 filename in
  let result = mtdh out_channel in
  close_out out_channel;
  if not file_exists then Unix.chmod filename perm else ();
  result
;;

let get_file_content ~filename =
  with_open_in_bin ~filename
    (fun in_channel length ->
       let s = Bytes.create length in
       really_input in_channel s 0 length;
       s)
;;

let set_file_content ?perm ~filename content =
  with_open_out_bin ?perm ~filename
    (fun out_channel -> output_string out_channel content)
;;

(* A simple (but portable) hash function generating natural numbers in the range [0..(2^30)-1]
   with a uniform distribution. Note that the limit is exactly the value of max_int on 32-bit
   architectures, i.e. 1073741823 = (2^30)-1 *)
let hash32 s =
  let max_int32 = 1073741823 in
  let s = Digest.to_hex (Digest.string s) in
  let max_int32_succ = Int64.succ (Int64.of_int max_int32) (* (2^30) *) in
  let hash_portion portion =
    let length = 8 in
    let offset = portion * length in
    let sub = Bytes.create (2+length) in
    let () = Bytes.blit (Bytes.of_string "0x") 0 sub 0 2 in
    let () = Bytes.blit (Bytes.of_string s) offset sub 2 length in
    let i = Int64.of_string (Bytes.to_string sub) in (* 0..(16^8)-1 = 0..(2^32)-1 *)
    (Int64.rem i max_int32_succ)   (* 0..max_int32 *)
  in
  let result =
    let xs = [ (hash_portion 0); (hash_portion 1); (hash_portion 2); (hash_portion 3) ] in
    let sum = List.fold_left (fun s x -> Int64.add s x) Int64.zero xs in
    let remainder = Int64.rem (sum) (max_int32_succ) in (* 0..max_int32 *)
    Int64.to_int (remainder)
  in
  result
;;


module Option = struct
let extract =
 function
  | None   -> failwith "Option.extract"
  | Some x -> x

let map f = function None -> None | Some x -> Some (f x)
let iter f = function None -> () | Some x -> (f x)
let extract_or_force xo y = match xo with
 | Some x -> x
 | None   -> Lazy.force y

(* To manage the type `unit option' which is isomorphic to bool: *)
let switch (opt) (case_None) (case_Some) =
     match opt with
      | None    -> case_None
      | Some () -> case_Some

end (* Option *)

type oid = Oid of int
type next_index = int

type magic = int ref (* just a pointer... *)

type ('a,'b) either = Left of 'a | Right of 'b

module Extend_Map = functor (M:Map.S) -> struct
  include M

  let of_list (xs : (key * 'a) list) : 'a t =
    List.fold_left (fun m (k,a) -> add k a m) empty xs

  let to_list (m : 'a t) =
    fold (fun k a xs -> (k,a)::xs) m []

  let filter_mapi (p : key -> 'a -> bool) (f:key -> 'a -> 'b) (m : 'a t) : 'b t =
    fold (fun k a m' -> if p k a then add k (f k a) m' else m') m empty

  let product (m1:'a t) (m2:'b t) : ('a * 'b) t =
    filter_mapi (fun k _ -> mem k m2) (fun k a -> (a, (find k m2))) m1

  let length (m : 'a t) =
    fold (fun k a n -> n+1) m 0

end

(* Note that compare is a flipped version of the provided one in order
   to have the result of to_list automatically sorted by key (from the
   lesser to the greater key, in the sense of the provided compare). *)
module Map_Make (Ord : Map.OrderedType) =
  Extend_Map
    (Map.Make (struct include Ord let compare x y = compare y x end))

module Oid_map = Map_Make (struct type t = oid let compare = compare end)
module Int_map = Map_Make (struct type t = int let compare = compare end)
module String_map = Map_Make (struct type t = string let compare = compare end)


(* ********************************* *
       Basic class constructors
 * ********************************* *)

type 'a whatever_object = < .. > as 'a
type 'a basic_class_constructor = unit -> 'a whatever_object

let basic_class_constructors = ref String_map.empty
let bcc = basic_class_constructors (* convenient alias *)

let register_basic_constructor ~(class_name:string) (f: 'a basic_class_constructor) =
  let f () =
    if is_tracing_disabled () then f () else begin
    Printf.kfprintf flush stderr "\n--- loading: creating instance for class `%s' BEGIN\n" class_name;
    let result = f () in
    Printf.kfprintf flush stderr "--- loading: created object %d for class `%s' END\n\n" (Oo.id result) class_name;
    result
    end
  in
  bcc := String_map.add class_name (Obj.magic f) !bcc

let get_basic_constructor ~involved_field ~involved_class class_name : 'a basic_class_constructor =
 try
   Obj.magic (String_map.find class_name !bcc)
 with
  Not_found ->
    invalid_arg
      (Printf.sprintf
         "Error: loading field `%s.%s' needs to recreate `%s' instances but this class has not a registered basic constructor."
         involved_class involved_field class_name)

let search_a_basic_constructor_for class_name : (string, 'a basic_class_constructor) either =
 try
   Right (Obj.magic (String_map.find class_name !bcc))
 with
  Not_found ->
    let warning_msg =
      (Printf.sprintf
         "Warning: loading would need to recreate a `%s' foreign instance but this class is not defined in this program."
         class_name)
    in Left warning_msg


(* **************************************** *
    Marshalling/Unmarshalling environments
 * **************************************** *)

type index = int

(* In any case marshallable without closures: *)
type marshallable =
  | Pointer of index (* to an object or a string (representing the object) *)
  | Datum of magic   (* something marshallable without closures *)

type field_name = string
type labelled_values = (field_name * marshallable) (* ordered *) list
type unlabelled_values = marshallable list

(* This structure requires a saving or loading environment in order to be meaningfull.
   (because we have to correctly interpret pointers) *)
type object_structure = {
  class_name        : string option;
  labelled_values   : (field_name * marshallable) (* ordered *) list;
  unlabelled_values : marshallable list;
  }

(* The ready-to-be-marshalled structure representing objects: *)
type object_closure =
  index_struct_list * object_structure

and index_struct_list =
  (index * object_structure) (* ordered *) list


(* Environments used for marshalling (saving): *)
module Saving_env = struct
 type t = next_index * oid_index_env * index_struct_env
  and oid_index_env    = index  Oid_map.t (* oid   -> index *)
  and index_struct_env = object_structure Int_map.t (* index -> object_structure *)

 let initial ~parent_oid =
   let parent_index = 0 in
   let next_index = parent_index+1 in
   let oid_index_env =
      Oid_map.add (Oid parent_oid) (parent_index) (Oid_map.empty)
   in
   let index_struct_env = Int_map.empty in
   (next_index, oid_index_env, index_struct_env)

 let search_index_by_oid oid t =
   let (next_index, oid_index_env, index_struct_env) = t in
   try
     Some (Oid_map.find oid oid_index_env)
   with Not_found -> None

 let add_oid_and_get_index (oid:oid) (t:t) : (t * index) =
   let (next_index, oid_index_env, index_struct_env) = t in
   let index = next_index in
   let oid_index_env' =  Oid_map.add oid index oid_index_env in
   let next_index'    = index + 1 in
   let t' = (next_index', oid_index_env', index_struct_env) in
   (t', index)

 let add_object_structure (index:index) (str:object_structure) (t:t) : t =
   let (next_index, oid_index_env, index_struct_env) = t in
   let index_struct_env' = Int_map.add index str index_struct_env in
   let t' = (next_index, oid_index_env, index_struct_env') in
   t'

 let extract_index_struct_env (t:t) : (index * object_structure) (* ordered *) list =
   let (next_index, oid_index_env, index_struct_env) = t in
   Int_map.to_list index_struct_env

end (* module Saving_env *)

(* Unmarshalling environments: *)
module Loading_env = struct

 type t = {
   (* index -> (Left of object_structure | Right of object) *)
   index_map : ((object_structure, magic) either) Int_map.t;
   options : loading_options;
   }
  and loading_options = {
   mapping                     : (field_name->field_name) option;
   try_to_preserve_upcasting   : unit option;
   try_to_reuse_living_objects : unit option;
   }

 (* This function is the unique way to build options. It will be exported in the .mli. *)
 let make_loading_options
  ?(mapping:(field_name -> field_name) option)
  ?(mapping_by_list:((field_name * field_name) list) option)
  ?try_to_preserve_upcasting
  ?try_to_reuse_living_objects
  () : loading_options
  =
  let mapping =
    match mapping, mapping_by_list with
    | None, None -> None
    | Some f, None -> Some f
    | None, Some l ->
        let smap = String_map.of_list l in
        Some (fun field -> String_map.find field smap)
    | Some f, Some l ->
        let smap = String_map.of_list l in
        Some (fun field -> try (f field) with _ -> (String_map.find field smap))
  in
  (* Simply ignore mapping failures: *)
  let mapping =
     Option.map
       (fun f -> fun x -> try f x with _ -> x)
       mapping
  in
  { mapping                     = mapping;
    try_to_preserve_upcasting   = try_to_preserve_upcasting;
    try_to_reuse_living_objects = try_to_reuse_living_objects;
    }

 let get_structure_or_object_by_index index t =
   Int_map.find (index) t.index_map

 let replace_structure_with_object (index:index) obj t =
   {t with index_map = Int_map.add index (Right obj) t.index_map; }

 let initial ?options ~(parent:magic) ~(index_struct_list: (index * object_structure) list) () =
   let parent_index = 0 in
   let index_struct_env = Int_map.of_list index_struct_list in
   let imported_index_struct_env =
     Int_map.map (fun str -> Left str) index_struct_env
   in
   let options = match options with
   | None -> make_loading_options ()
   | Some options -> options
   in
   { index_map = Int_map.add parent_index (Right parent) (imported_index_struct_env);
     options = options;}

 let extract_label_mapping t = t.options.mapping

 let create_or_recycle_object_according_to_options
   ~(field_declared_class_name:string option)
   ~(foreign_class_name:string option)
   ~(object_maker)
   (* if the getter is not provided, the maker is used instead: *)
   ?(object_getter = object_maker)
   t
   =
   let switch = Option.switch in
   if (t.options.try_to_preserve_upcasting = None)
   || (foreign_class_name = None)
   || (foreign_class_name = field_declared_class_name) (* no upcasting *)
   then
     (* It's a simple case: create or reuse according to the associated option: *)
     switch (t.options.try_to_reuse_living_objects) (object_maker) (object_getter)
   else
   (* We try to preserve upcasting
     *and* the foreign class is defined
     *and* the foreign class is not the declared class of the field (there is an upcasting to preserve): *)
   let foreign_class_name = Option.extract foreign_class_name in
   match search_a_basic_constructor_for (foreign_class_name) with
   | Left warning_msg ->
       (* --- there isn't a local constructor for the foreign class, so we can't preserve upcasting anyway: *)
       (if are_warnings_enable () then Printf.kfprintf flush stderr "%s\n" warning_msg);
       switch (t.options.try_to_reuse_living_objects) (object_maker) (object_getter)
       (* --- *)
   | Right foreign_class_maker->
       (* --- there is a local constructor for the foreign class. Now the question became:
              can the current instance be reused? *)
       let current_object_class_name = (object_getter ())#marshaller#parent_class_name in
       if current_object_class_name = (Some foreign_class_name)
       then
         (* Yes, it can be reused (according to the option) because it belongs to the same class: *)
         switch (t.options.try_to_reuse_living_objects) (foreign_class_maker) (object_getter)
       else
         (* No, it cannot be reused, we have to create a new object: *)
         foreign_class_maker

end (* module Saving_env *)

(* Elements to be exported (in the interface): *)
type loading_options = Loading_env.loading_options
let make_loading_options = Loading_env.make_loading_options
type saving_env = Saving_env.t
type loading_env = Loading_env.t

module Fields_register = struct

 (* Variables that I call "saa" are of this type: *)
 type adapted_accessors = {
   get : Saving_env.t   -> unit -> marshallable * Saving_env.t;
   set : Loading_env.t -> marshallable -> unit * Loading_env.t;
   }

 type t = {
   anonymous_fields : adapted_accessors list;         (* The order here is relevant *)
   named_fields     : adapted_accessors String_map.t; (* field-name -> adapted_accessors *)
   }

 let empty : t = {
   anonymous_fields = [];
   named_fields = String_map.empty;
   }

 let add ?field_name saa t =
   match field_name with
   | None      -> {t with anonymous_fields=(saa :: t.anonymous_fields)}
   | Some name -> {t with named_fields = String_map.add name saa t.named_fields}

 let match_named_fields_with_labelled_values ?foreign_class_name ?class_name ?label_mapping (t:t) (labelled_values: (string * 'a) list)
   : (adapted_accessors * 'a) list
   =
   let labelled_values = match label_mapping with
   | None   -> labelled_values
   | Some f -> List.map (fun (k,v) -> ((f k),v)) labelled_values
   in
   let labelled_values = String_map.of_list labelled_values in
   let matching = String_map.product t.named_fields labelled_values in
   let matching_as_list = String_map.to_list matching in
   let () =
     if are_warnings_disabled () then () else
     let nf = String_map.length t.named_fields in
     let nv = String_map.length labelled_values in
     let nm = List.length matching_as_list in
     let what = lazy (match class_name with
     | None -> "an object"
     | Some name -> Printf.sprintf "a `%s' instance" name)
     in
     match (compare nf nv), (nm < (min nf nv)) with
     | -1, false ->
	Printf.kfprintf flush stderr
	  "Warning: loading %s from a serialized richer object (%d/%d labelled values taken).\n"
	  (Lazy.force what) nf nv
     |  1, false ->
	Printf.kfprintf flush stderr
	  "Warning: loading %s from a serialized poorer object (%d/%d labelled values taken).\n"
	  (Lazy.force what) nf nv
     |  0, false -> ()
     | _ ->
	Printf.kfprintf flush stderr
	  "Warning: loading %s from a serialized different object (%d common fields, %d unloaded fields, %d unused values).\n"
	  (Lazy.force what) nm (nf-nm) (nv-nm)
   in
   (* Now forget field names: *)
   List.map snd matching_as_list

 let match_anonymous_fields_with_unlabelled_values ?foreign_class_name ?class_name (t:t) (unlabelled_values: 'a list)
   : (adapted_accessors * 'a) list
   =
   let what = lazy (match class_name with
   | None -> "an object"
   | Some name -> Printf.sprintf "a `%s' instance" name)
   in
   let rec combine fs vs =
     match (fs, vs) with
     | ([],[]) -> []
     | (f::fs, v::vs) -> (f,v)::(combine fs vs)
     | ([],_) ->
         let () =
           if are_warnings_disabled () then () else
           Printf.kfprintf flush stderr
             "Warning: loading the anonymous fields of %s from a serialized richer object (%d/%d values taken).\n"
             (Lazy.force what)
             (List.length t.anonymous_fields)
             (List.length unlabelled_values)
         in []
     | (_,[]) ->
         let () =
           if are_warnings_disabled () then () else
           Printf.kfprintf flush stderr
             "Warning: loading the anonymous fields of %s from a serialized poorer object (%d/%d values taken).\n"
             (Lazy.force what)
             (List.length t.anonymous_fields)
             (List.length unlabelled_values)
         in []
   in
   combine t.anonymous_fields unlabelled_values

end (* module Fields_register *)


class marshallable_class ?name ~(marshaller:marshaller option ref) () =
let shared_marshaller = marshaller in
object (self)

  (* When objects will be initialized, the shared_marshaller will be defined once by
     the first inherited, that is precisely this class (marshallable_class): *)
  method marshaller : marshaller =
    match !shared_marshaller with Some x -> x | None -> assert false

  (* The first initializer wins: *)
  initializer
    match !shared_marshaller with
    | None   ->
        begin
          let created_marshaller =
            new marshaller ?parent_class_name:name ~parent:(self :> (marshallable_class)) ()
          in
          let () = if is_tracing_disabled () then () else
            Printf.kfprintf flush stderr
              "creating: %s.marshallable_class(%d).initializer: created the marshaller %d\n"
              (Option.extract name) (Oo.id self) (Oo.id created_marshaller)
          in
          shared_marshaller := (Some created_marshaller); (* Release the information to the parent *)
        end
    | Some m ->
          let () = if is_tracing_disabled () then () else
            Printf.kfprintf flush stderr
              "creating: %s.marshallable_class(%d).initializer: sharing the marshaller %d\n"
              (Option.extract name) (Oo.id self) (Oo.id m)
          in
          () (* It's fine, a shared marshaller has been already created *)

end

and (* class *) marshaller ?parent_class_name ~(parent:marshallable_class) () =
let _WITHOUT_CLOSURES_OF_COURSE = [] in
object (self)

  val parent_class_name : string option = parent_class_name
  method parent_class_name = parent_class_name

  val mutable fields_register : Fields_register.t =
    Fields_register.empty

  method private get_fields_register = fields_register

  method private get_anonymous_fields =
    fields_register.Fields_register.anonymous_fields

  method private get_named_fields_as_ordered_assoc_list =
    let m = fields_register.Fields_register.named_fields in
    String_map.to_list m

  method private register_adapted_accessors ?field_name (saa : Fields_register.adapted_accessors) =
     fields_register <- (Fields_register.add ?field_name saa fields_register)

  (* -----------------------------
       Registering SIMPLE fields
     ----------------------------- *)

  method private adapt_simple_field : 'a. (unit -> 'a) -> ('a -> unit) -> Fields_register.adapted_accessors =
     fun real_get real_set ->
     let adapted_get : Saving_env.t -> unit -> marshallable * Saving_env.t =
       fun saving_env () ->
         let x = real_get () in
         let datum = Datum (Obj.magic x) in
         (datum, saving_env)
     in
     let adapted_set : Loading_env.t -> marshallable -> unit * Loading_env.t =
       fun loading_env ->
         function
         | Datum x      -> ((real_set (Obj.magic x)), loading_env)
         | Pointer index -> assert false
     in
     { Fields_register.get = adapted_get;
       Fields_register.set = adapted_set}

  method register_simple_field : 'a. ?name:string -> (unit -> 'a) -> ('a -> unit) -> unit =
     fun ?name real_get real_set ->
       self#register_adapted_accessors ?field_name:name (self#adapt_simple_field real_get real_set)

  (* -----------------------------
       Registering OBJECT fields
     ----------------------------- *)

  (* To be used with map_and_fold (map the first result, fold the second) *)
  method private marshallable_of_object
    : Saving_env.t -> (< marshaller:marshaller; .. > as 'a) -> marshallable * Saving_env.t
    = fun saving_env obj ->
    let oid = Oid (Oo.id obj) in
    (* The result is always a pointer (the string is stored in the saving_env): *)
    match Saving_env.search_index_by_oid oid saving_env with
    | Some index ->
        (if is_tracing_enable () then
           Printf.kfprintf flush stderr "saving: making a pointer to index %d\n" index);
        let pointer = (Pointer index) in
        (pointer, saving_env)
    | None ->
        let (saving_env, index) =
          Saving_env.add_oid_and_get_index oid saving_env
        in
        (if is_tracing_enable () then
          Printf.kfprintf flush stderr "saving: added object oid %d with index %d\n" (Oo.id obj) index);
        let (str, saving_env) =
          obj#marshaller#protected_save_to_object_structure saving_env
        in
        let saving_env =
          Saving_env.add_object_structure index str saving_env
        in
        let pointer = (Pointer index) in
        (pointer, saving_env)

  method private object_of_marshallable (* : .. -> .. -> object * loading_env *) =
    fun ?getter ~maker loading_env ->
      function
      | Pointer index ->
         begin
          match Loading_env.get_structure_or_object_by_index index loading_env with
	  | Left (obj_structure : object_structure) ->
	      let create_or_recycle_object =
	        Loading_env.create_or_recycle_object_according_to_options
	          ~field_declared_class_name:None
	          ~foreign_class_name:(obj_structure.class_name)
	          ~object_maker:maker
	          ?object_getter:getter
	          loading_env
	      in
	      let obj = create_or_recycle_object () in
              (if is_tracing_enable () then
	        Printf.kfprintf flush stderr "loading: adding object oid %d with index %d before loading it\n" (Oo.id obj) index);
	      let loading_env =
		Loading_env.replace_structure_with_object index (Obj.magic obj) loading_env
	      in
	      let (), loading_env =
		obj#marshaller#protected_load_from_object_structure (loading_env) (obj_structure)
	      in
	      (obj, loading_env)

	  | Right obj ->
              (if is_tracing_enable () then
	        Printf.kfprintf  flush stderr "loading: found object oid %d with index %d\n" (Oo.id (Obj.magic obj)) index);
	      (Obj.magic obj), loading_env
         end (* of Pointer's case *)
      | Datum _ -> assert false


  method private adapt_object_field
     : (unit -> (< marshaller : marshaller; .. >)) ->  (* object maker *)
       (unit -> (< marshaller:marshaller; .. >)) ->    (* The real get-accessor of the field *)
       (< marshaller:marshaller; .. > -> unit) ->      (* The real set-accessor of the field *)
       Fields_register.adapted_accessors
     =
     fun object_maker real_get real_set ->
     let adapted_get : Saving_env.t -> unit -> marshallable * Saving_env.t =
       fun saving_env () ->
         let obj = real_get () in
         self#marshallable_of_object saving_env obj
     in
     let adapted_set : Loading_env.t -> marshallable -> unit * Loading_env.t =
       fun loading_env marshallable ->
         let (obj, loading_env) =
           self#object_of_marshallable
             ~getter:(real_get)
             ~maker:(object_maker)
             (loading_env)
             (marshallable)
         in
         ((real_set (Obj.magic obj)), loading_env)
     in
     { Fields_register.get = adapted_get;
       Fields_register.set = adapted_set}

  method register_object_field
     : 'obj. ?name:string ->
           (unit -> (< marshaller : marshaller; .. > as 'obj)) ->  (* object maker *)
           (unit -> 'obj) ->                                       (* getter *)
           ('obj -> unit) ->                                       (* setter *)
           unit
     = Obj.magic begin
	fun ?name (object_maker:unit->'obj) real_get real_set ->
	  let object_maker : (unit -> < marshaller : marshaller; .. >) = Obj.magic object_maker in
	  (self#register_adapted_accessors
	      ?field_name:name
	      (self#adapt_object_field object_maker real_get real_set))
       end

  (* -----------------------------------------
       Registering FUNCTORIZED OBJECT fields
     ----------------------------------------- *)

  method private adapt_functorized_object_field
     :  'obj_t 'a_t 'b_t 'ab_t.
        ?zip:('a_t -> 'b_t -> 'ab_t) ->                                                            (* functor zip *)
        (((< marshaller : marshaller; .. > as 'obj) -> marshallable) -> 'obj_t -> marshallable) -> (* functor map1 *)
        ((marshallable -> 'obj) -> marshallable -> 'obj_t) ->                                      (* functor map2 *)
        (unit -> 'obj) ->                                                                          (* object maker *)
        (unit -> 'obj_t) ->                                                                        (* getter *)
        ('obj_t -> unit) ->                                                                        (* setter *)
        Fields_register.adapted_accessors (* result *)
     =
     fun ?zip map1 map2 object_maker real_get real_set ->
     let adapted_get : Saving_env.t -> unit -> marshallable * Saving_env.t =
       fun saving_env () ->
         let object_t = real_get () in
         let marshallable_t, saving_env =
           (Functor.map_and_fold_of_functor map1) (self#marshallable_of_object) (saving_env) object_t
         in
         (Datum (Obj.magic marshallable_t), saving_env)
     in
     let adapted_set : Loading_env.t -> marshallable -> unit * Loading_env.t =
       fun loading_env ->
         let zip = Obj.magic zip in
         function
         | Datum x when zip=None ->
             let marshallable_t = Obj.magic x in
             let object_t, loading_env =
               (Functor.map_and_fold_of_functor map2)
                 (self#object_of_marshallable ~maker:object_maker)
                 (loading_env)
                 marshallable_t
             in
             ((real_set object_t), loading_env)

         | Datum x (* when zip<>None *) ->
             let marshallable_t = Obj.magic x in
             let zip = Option.extract zip in
             let living_object_t = real_get () in
             let object_t, loading_env =
	       try
	         (* The following definition is commented in order to avoid a boring warning: *)
                 (* let marshallable_object_t = zip marshallable_t living_object_t in (* this call may fail *) *)
		 (Functor.map_and_fold_of_functor (Obj.magic map2))
		    (fun env (msh,liv_obj) ->
		        self#object_of_marshallable ~getter:(fun ()->liv_obj) ~maker:object_maker env msh)
		    (loading_env)
		    ((Obj.magic zip) marshallable_t living_object_t) (* marshallable_object_t *)
	       with _ -> begin
	         (* Ignore zip: *)
		 (Functor.map_and_fold_of_functor map2)
		   (self#object_of_marshallable ~maker:object_maker)
		   (loading_env)
		   marshallable_t
		  end
             in
             ((real_set object_t), loading_env)

         (* The field is a non-object structure containing objects *)
         | Pointer _ -> (assert false)
     in
     { Fields_register.get = adapted_get;
       Fields_register.set = adapted_set}


  method register_functorized_object_field
     :  'obj 'obj_t 'a 'b 'a_t 'b_t 'ab_t.
        ?name:string ->                                         (* name *)
        ?zip:('a_t -> 'b_t -> 'ab_t) ->                         (* functor zip *)
        (('a -> 'b) -> 'a_t -> 'b_t) ->                         (* functor *)
        (unit -> (< marshaller : marshaller; .. > as 'obj)) ->  (* object maker *)
        (unit -> 'obj_t) ->                                     (* getter *)
        ('obj_t -> unit) ->                                     (* setter *)
          unit
     = fun ?name ?zip functor_map object_maker real_get real_set ->
         let map1 = Obj.magic functor_map in
         let map2 = Obj.magic functor_map in
         (* Because of a strange typing problem: *)
         let object_maker : (unit -> < marshaller : marshaller; .. >) = Obj.magic object_maker in
         self#register_adapted_accessors ?field_name:name
           (self#adapt_functorized_object_field ?zip map1 map2 object_maker real_get real_set)

  (* ---------------------------------------------
       Registering BI-FUNCTORIZED OBJECTS fields
     --------------------------------------------- *)

  method private adapt_bifunctorized_objects_field
     :  'objects_t 'au_t 'bv_t 'axb_uxv_t .

        (* bifunctor zip *)
        ?zip:('au_t -> 'bv_t -> 'axb_uxv_t) ->

        (* bifunctor map1 *)
        (((< marshaller : marshaller; .. > as 'obj1) -> marshallable) ->
         ((< marshaller : marshaller; .. > as 'obj2) -> marshallable) -> 'objects_t -> marshallable) ->

        (* bifunctor map2 *)
        ((marshallable -> 'obj1) -> (marshallable -> 'obj2) -> marshallable -> 'objects_t) ->

        (unit -> 'obj1) ->         (* object maker 1 *)
        (unit -> 'obj2) ->         (* object maker 2 *)
        (unit -> 'objects_t) ->    (* getter *)
        ('objects_t -> unit) ->    (* setter *)

        Fields_register.adapted_accessors (* result *)
     =
     fun ?zip map1 map2 object_maker1 object_maker2 real_get real_set ->
     let adapted_get : Saving_env.t -> unit -> marshallable * Saving_env.t =
       fun saving_env () ->
         let objects_t = real_get () in
         let marshallable_t, saving_env =
           (Functor.map_and_fold_of_bifunctor map1)
             (self#marshallable_of_object)
             (self#marshallable_of_object)
             (saving_env)
             objects_t
         in
         (Datum (Obj.magic marshallable_t), saving_env)
     in
     let adapted_set : Loading_env.t -> marshallable -> unit * Loading_env.t =
       fun loading_env ->
         let zip = Obj.magic zip in
         function
         | Datum x when zip=None ->
             let marshallable_t = Obj.magic x in
             let objects_t, loading_env =
               (Functor.map_and_fold_of_bifunctor map2)
                 (self#object_of_marshallable ~maker:object_maker1)
                 (self#object_of_marshallable ~maker:object_maker2)
                 (loading_env)
                 marshallable_t
             in
             ((real_set objects_t), loading_env)

         | Datum x (*when zip<>None*) ->
             let marshallable_t = Obj.magic x in
             let zip = Option.extract zip in
             let living_objects_t = real_get () in
             let objects_t, loading_env =
	       try
                 (* The following definition is commented in order to avoid a boring warning: *)
                 (* let marshallable_x_objects_t = zip marshallable_t living_objects_t in (* this call may fails *) *)
                 (Functor.map_and_fold_of_bifunctor (Obj.magic map2))
		    (fun env (msh, liv_obj) -> self#object_of_marshallable ~getter:(fun ()->liv_obj) ~maker:object_maker1 env msh)
		    (fun env (msh, liv_obj) -> self#object_of_marshallable ~getter:(fun ()->liv_obj) ~maker:object_maker2 env msh)
		    (loading_env)
		    ((Obj.magic zip) marshallable_t living_objects_t) (* marshallable_x_objects_t *)
	       with _ -> begin
	         (* Ignore zip: *)
                 (Functor.map_and_fold_of_bifunctor map2)
                   (self#object_of_marshallable ~maker:object_maker1)
                   (self#object_of_marshallable ~maker:object_maker2)
                   (loading_env)
                   marshallable_t
		  end
             in
             ((real_set objects_t), loading_env)

         (* The field is a non-object structure containing objects *)
         | Pointer _ -> (assert false)
     in
     { Fields_register.get = adapted_get;
       Fields_register.set = adapted_set}


  method register_bifunctorized_objects_field
     :  'obj1 'obj2 'objects_t 'a 'b 'c 'd 'ac_t 'bd_t 'au_t 'bv_t 'axb_uxv_t.
        ?name:string ->                                          (* name *)
        ?zip:('au_t -> 'bv_t -> 'axb_uxv_t) ->                   (* zip for bifunctor *)
        (('a -> 'b) -> ('c -> 'd) -> 'ac_t -> 'bd_t) ->          (* bifunctor *)
        (unit -> (< marshaller : marshaller; .. > as 'obj1)) ->  (* object maker 1 *)
        (unit -> (< marshaller : marshaller; .. > as 'obj2)) ->  (* object maker 2 *)
        (unit -> 'objects_t) ->                                  (* getter *)
        ('objects_t -> unit) ->                                  (* setter *)
          unit
     = fun ?name ?zip bifunctor_map object_maker1 object_maker2 real_get real_set ->
         let map1 = Obj.magic bifunctor_map in
         let map2 = Obj.magic bifunctor_map in
         (* Because of a strange typing problem: *)
         let maker1 : (unit -> < marshaller : marshaller; .. >) = Obj.magic object_maker1 in
         let maker2 : (unit -> < marshaller : marshaller; .. >) = Obj.magic object_maker2 in
         self#register_adapted_accessors ?field_name:name
           (self#adapt_bifunctorized_objects_field ?zip map1 map2 maker1 maker2 real_get real_set)

  (* ---------------------------------------------
       Registering TRI-FUNCTORIZED OBJECTS fields
     --------------------------------------------- *)

  method private adapt_trifunctorized_objects_field
     :  'objects_t 'ace_t 'bdf_t 'aue_t 'bvf_t 'axb_uxv_exf_t.

        (* trifunctor zip *)
        ?zip:('aue_t -> 'bvf_t -> 'axb_uxv_exf_t) ->

        (* trifunctor map1 *)
        (((< marshaller : marshaller; .. > as 'obj1) -> marshallable) ->
         ((< marshaller : marshaller; .. > as 'obj2) -> marshallable) ->
         ((< marshaller : marshaller; .. > as 'obj3) -> marshallable) -> 'objects_t -> marshallable) ->

        (* trifunctor map2 *)
        ((marshallable -> 'obj1) -> (marshallable -> 'obj2) -> (marshallable -> 'obj3) -> marshallable -> 'objects_t) ->

        (unit -> 'obj1) ->         (* object maker 1 *)
        (unit -> 'obj2) ->         (* object maker 2 *)
        (unit -> 'obj3) ->         (* object maker 3 *)
        (unit -> 'objects_t) ->    (* getter *)
        ('objects_t -> unit) ->    (* setter *)

        Fields_register.adapted_accessors (* result *)
     =
     fun ?zip map1 map2 object_maker1 object_maker2 object_maker3 real_get real_set ->
     let adapted_get : Saving_env.t -> unit -> marshallable * Saving_env.t =
       fun saving_env () ->
         let objects_t = real_get () in
         let marshallable_t, saving_env =
           (Functor.map_and_fold_of_trifunctor map1)
             (self#marshallable_of_object)
             (self#marshallable_of_object)
             (self#marshallable_of_object)
             (saving_env)
             objects_t
         in
         (Datum (Obj.magic marshallable_t), saving_env)
     in
     let adapted_set : Loading_env.t -> marshallable -> unit * Loading_env.t =
       fun loading_env ->
         let zip = Obj.magic zip in
         function
         | Datum x when zip=None ->
             let marshallable_t = Obj.magic x in
             let objects_t, loading_env =
               (Functor.map_and_fold_of_trifunctor map2)
                 (self#object_of_marshallable ~maker:object_maker1)
                 (self#object_of_marshallable ~maker:object_maker2)
                 (self#object_of_marshallable ~maker:object_maker3)
                 (loading_env)
                 marshallable_t
             in
             ((real_set objects_t), loading_env)

         | Datum x (*when zip<>None*) ->
             let marshallable_t = Obj.magic x in
             let zip = Option.extract zip in
             let living_objects_t = real_get () in
             let objects_t, loading_env =
	       try
                 (* The following definition is commented in order to avoid a boring warning: *)
                 (* let marshallable_x_objects_t = zip marshallable_t living_objects_t in (* this call may fails *) *)
                 (Functor.map_and_fold_of_trifunctor (Obj.magic map2))
		    (fun env (msh, liv_obj) -> self#object_of_marshallable ~getter:(fun ()->liv_obj) ~maker:object_maker1 env msh)
		    (fun env (msh, liv_obj) -> self#object_of_marshallable ~getter:(fun ()->liv_obj) ~maker:object_maker2 env msh)
		    (fun env (msh, liv_obj) -> self#object_of_marshallable ~getter:(fun ()->liv_obj) ~maker:object_maker3 env msh)
		    (loading_env)
		    ((Obj.magic zip) marshallable_t living_objects_t) (* marshallable_x_objects_t *)
	       with _ -> begin
	         (* Ignore zip: *)
		  (Functor.map_and_fold_of_trifunctor map2)
		    (self#object_of_marshallable ~maker:object_maker1)
		    (self#object_of_marshallable ~maker:object_maker2)
		    (self#object_of_marshallable ~maker:object_maker3)
		    (loading_env)
		    marshallable_t
		  end
             in
             ((real_set objects_t), loading_env)

         (* The field is a non-object structure containing objects *)
         | Pointer _ -> (assert false)
     in
     { Fields_register.get = adapted_get;
       Fields_register.set = adapted_set}


  method register_trifunctorized_objects_field
     :  'obj1 'obj2 'obj3 'objects_t 'a 'b 'c 'd 'e 'f 'ace_t 'bdf_t 'aue_t 'bvf_t 'axb_uxv_exf_t .
        ?name:string ->                                          (* name *)
        ?zip:('aue_t -> 'bvf_t -> 'axb_uxv_exf_t) ->             (* trifunctor zip *)
        (('a -> 'b) -> ('c -> 'd) -> ('e -> 'f) -> 'ace_t -> 'bdf_t) -> (* trifunctor *)
        (unit -> (< marshaller : marshaller; .. > as 'obj1)) ->  (* object maker 1 *)
        (unit -> (< marshaller : marshaller; .. > as 'obj2)) ->  (* object maker 2 *)
        (unit -> (< marshaller : marshaller; .. > as 'obj3)) ->  (* object maker 3 *)
        (unit -> 'objects_t) ->                                  (* getter *)
        ('objects_t -> unit) ->                                  (* setter *)
          unit
     = fun ?name ?zip trifunctor_map object_maker1 object_maker2 object_maker3 real_get real_set ->
         let map1 = Obj.magic trifunctor_map in
         let map2 = Obj.magic trifunctor_map in
         (* Because of a strange typing problem: *)
         let maker1 : (unit -> < marshaller : marshaller; .. >) = Obj.magic object_maker1 in
         let maker2 : (unit -> < marshaller : marshaller; .. >) = Obj.magic object_maker2 in
         let maker3 : (unit -> < marshaller : marshaller; .. >) = Obj.magic object_maker3 in
         self#register_adapted_accessors ?field_name:name
           (self#adapt_trifunctorized_objects_field ?zip map1 map2 maker1 maker2 maker3 real_get real_set)

  (* --------------------------------------
          S A V I N G    (marshalling)
     -------------------------------------- *)

  method save_to_string : string =
    let object_closure = self#save_to_object_closure in
    Marshal.to_string (object_closure) (_WITHOUT_CLOSURES_OF_COURSE)

  method save_to_file filename =
    let object_closure = self#save_to_object_closure in
    with_open_out_bin ~filename
      (fun out_channel ->
         Marshal.to_channel out_channel
           (object_closure)
           (_WITHOUT_CLOSURES_OF_COURSE))

  method private save_to_object_closure : object_closure =
    let (object_structure, saving_env) =
      self#protected_save_to_object_structure
        (Saving_env.initial ~parent_oid:(Oo.id parent))
    in
    (* Extract now the index->string environment from the saving_env: *)
    let index_struct_list =
      Saving_env.extract_index_struct_env saving_env
    in
    let object_closure = (index_struct_list, object_structure) in
    object_closure

  method (* protected *) protected_save_to_object_structure (saving_env) : object_structure * Saving_env.t
    =
    let labelled_values,   saving_env = self#save_to_labelled_values   (saving_env) in
    let unlabelled_values, saving_env = self#save_to_unlabelled_values (saving_env) in
    let object_structure = {
      class_name = self#parent_class_name;
      labelled_values = labelled_values;
      unlabelled_values = unlabelled_values;
      }
    in
    (object_structure, saving_env)

  method private save_to_labelled_values (saving_env) =
    let (result: (string*marshallable) list), saving_env =
      List.fold_left
	(fun state ((name:string), (saa:Fields_register.adapted_accessors)) ->
	    let result, saving_env = state in
	    let (mshlable, saving_env) = saa.Fields_register.get saving_env () in
	    let state' = ((name, mshlable)::result, saving_env) in
	    state')
	([], saving_env)
	self#get_named_fields_as_ordered_assoc_list (* NAMED FIELDS! *)
    in
    (result, saving_env)

  method private save_to_unlabelled_values (saving_env) =
    let (result: marshallable list), saving_env =
      List.fold_left
	(fun state (saa:Fields_register.adapted_accessors) ->
	    let result, saving_env = state in
	    let (mshlable, saving_env) = saa.Fields_register.get saving_env () in
	    let state' = (mshlable::result, saving_env) in
	    state')
	([], saving_env)
	self#get_anonymous_fields (* ANONYMOUS FIELDS! *)
    in
    (List.rev result, saving_env)


  (* --------------------------------------
         L O A D I N G   (unmarshalling)
     -------------------------------------- *)

  (* Loading from a string: *)
  method load_from_string ?options (str:string) : unit =
    let object_closure = (Marshal.from_string str 0) in
    self#load_from_object_closure ?options object_closure

  (* Loading from a file: *)
  method load_from_file ?options filename : unit =
    let (object_closure : object_closure) =
      try
        with_open_in_bin ~filename
          (fun in_channel length ->
             Marshal.from_channel in_channel)
      with _ ->
        failwith "load_from_file: failed unmarshalling the file content"
    in
    self#load_from_object_closure ?options (object_closure)

  (* Loading from a object_closure: *)
  method private load_from_object_closure : ?options:loading_options -> object_closure -> unit =
    fun ?options object_closure ->
      let (index_struct_list, object_structure) = object_closure in
      let loading_env =
        Loading_env.initial ?options ~parent:(Obj.magic parent) ~index_struct_list ()
      in
      let (), _loading_env =
        self#protected_load_from_object_structure (loading_env) (object_structure)
      in
      ()

  (* Loading from a both labelled and unlabelled values.
     It's simply the composition of the two functions loading
     from labelled and from unlabelled values: *)
  method (* protected *) protected_load_from_object_structure
    (loading_env)
    (object_structure : object_structure)
    : unit * Loading_env.t
    =
    let foreign_class_name = object_structure.class_name
    and labelled_values    = object_structure.labelled_values
    and unlabelled_values  = object_structure.unlabelled_values
    in
    let (), loading_env = self#load_from_labelled_values   ?foreign_class_name (loading_env) (labelled_values)   in
    let (), loading_env = self#load_from_unlabelled_values ?foreign_class_name (loading_env) (unlabelled_values) in
    ((), loading_env)

  (* Loading from a list of labelled values: *)
  method private load_from_labelled_values
    ?foreign_class_name
    (loading_env)
    (labelled_values : (field_name * marshallable) list)
    : unit * Loading_env.t
    =
    let set_arg_list =
      let saa_arg_list =
        Fields_register.match_named_fields_with_labelled_values
          ?foreign_class_name
          ?class_name:(self#parent_class_name)
          ?label_mapping:(Loading_env.extract_label_mapping loading_env)
          (self#get_fields_register)
          (labelled_values)
      in
      List.map (fun (saa,arg) -> (saa.Fields_register.set,arg)) saa_arg_list
    in
    self#load_from_set_arg_list (loading_env) set_arg_list

  (* Loading from a list of unlabelled values: *)
  method private load_from_unlabelled_values
    ?foreign_class_name
    (loading_env)
    (unlabelled_values : marshallable list)
    : unit * Loading_env.t
    =
    let set_arg_list =
      let saa_arg_list =
        Fields_register.match_anonymous_fields_with_unlabelled_values
          ?foreign_class_name
          ?class_name:(self#parent_class_name)
          (self#get_fields_register)
          (unlabelled_values)
      in
      List.map (fun (saa,arg) -> (saa.Fields_register.set,arg)) saa_arg_list
    in
    self#load_from_set_arg_list (loading_env) set_arg_list

  method private load_from_set_arg_list (loading_env) set_arg_list : unit * Loading_env.t =
    let loading_env =
      List.fold_left
	(fun loading_env (set, arg) -> snd (set loading_env arg))
	loading_env
	set_arg_list
    in
    ((), loading_env)

  (* --------------------------------------
              Other methods
     -------------------------------------- *)

   method compare : 'a. (< marshaller:marshaller; .. > as 'a) -> int
     = fun obj -> Pervasives.compare (self#save_to_string) (obj#marshaller#save_to_string)

   method equals : 'a. (< marshaller:marshaller; .. > as 'a) -> bool
     = fun obj -> (self#save_to_string) = (obj#marshaller#save_to_string)

   method hash32 : int =
     hash32 (self#save_to_string)

   method md5sum : string =
     Digest.to_hex (Digest.string (self#save_to_string))

   method remake_simplest : unit =
     self#load_from_string (self#save_to_string)

   (* Alias for remake_simplest: *)
   method remove_upcasting : unit =
     self#load_from_string (self#save_to_string)

end;;

(* ********************************* *
         Associated tools
 * ********************************* *)

module Toolkit = struct

 (* Just an alias for List.combine: *)
 let zip_list = List.combine

 let zip_array xs ys =
   if (Array.length xs) <> (Array.length ys) then invalid_arg "zip_array" else
   Array.mapi (fun i a -> (a,ys.(i))) xs ;;

 let zip_option x y =
   match (x,y) with
   | (None, None)     -> None
   | (Some x, Some y) -> Some (x,y)
   | _ -> invalid_arg "zip_option"

 let zip_either x y =
   match (x,y) with
   | (Either.Left  a, Either.Left  c) -> Either.Left  (a,c)
   | (Either.Right b, Either.Right d) -> Either.Right (b,d)
   | _ , _ -> invalid_arg "zip_either"
end


(* ********************************* *
              Example
 * ********************************* *)

IFDEF DOCUMENTATION_OR_DEBUGGING THEN
module Example = struct

(* A concrete syntax like:

     tag (marshallable) class <class-definitions>

   adds the parameter ?marshaller to all defined classes as first parameter *)
class class1 ?(marshaller:(marshaller option ref) option) () =
let marshaller = match marshaller with None -> ref None | Some r -> r in
object (self)

  (* Automatically added at the beginning of the class definition: *)
  inherit marshallable_class ~name:"class1" ~marshaller ()

  (* When a class is inherited, the parameter ~marshaller is given to the class constructor:
     inherit class0 expr  =>  inherit ~marshaller class0 expr
     *)

  val mutable field0 = 16
  method get_field0 = field0
  method set_field0 v = field0 <- v
  initializer
    self#marshaller#register_simple_field ~name:"field0" (fun () -> self#get_field0) self#set_field0;

  val mutable field1 = "field1"
  method get_field1 = field1
  method set_field1 v = field1 <- v
  initializer
    self#marshaller#register_simple_field ~name:"field1" (fun () -> self#get_field1) self#set_field1;

  val mutable field2 = Some 42
  method get_field2 = field2
  method set_field2 v = field2 <- v
  initializer
    self#marshaller#register_simple_field ~name:"field2" (fun () -> self#get_field2) self#set_field2;


end (* end of class1.. *)
(* ..but the class definition is not complete: we have to register its basic class constructor: *)
let () = register_basic_constructor ~class_name:"class1" (fun () -> new class1 ())

class class2 ?(marshaller:(marshaller option ref) option) () =
let marshaller = match marshaller with None -> ref None | Some r -> r in
let involved_class = "class2" in
object (self)

  (* Automatically added at the beginning of the class definition: *)
  inherit marshallable_class ~name:"class2" ~marshaller ()

  (* Share the marshaller: *)
  inherit class1 ~marshaller ()

  (* A field containing a (marshallable) object:
     Concrete syntax:
       tag (object) val mutable field3 : class1 = new class1 ()
     In case of composition (not inheritance) I dont need to provide
     the same marshaller to the class constructor. *)
  val mutable field3 : class1 = new class1 () (* another marshaller! *)
  method get_field3 = field3
  method set_field3 v = field3 <- v
  initializer
    let object_maker = get_basic_constructor "class1" ~involved_field:"field3" ~involved_class in
    self#marshaller#register_object_field ~name:"field3"
      object_maker
      (fun () -> self#get_field3)
      self#set_field3;

  (* A field containing an optional (marshallable) object:
     Concrete syntax:
       tag (object option) val mutable field4 : class2 option = None
    *)
  val mutable field4 : class2 option = None
  method get_field4 = field4
  method set_field4 v = field4 <- v
  initializer
    (* from the tag: *)
    let object_maker = get_basic_constructor "class2" ~involved_field:"field4" ~involved_class in
    let functor_map = Option.map in        (* from the tag: option -> Option.map *)
    self#marshaller#register_functorized_object_field ~name:"field4"
      ~zip:(fun x y -> match (x,y) with None,None-> None| Some x, Some y -> Some (x,y) | _,_ -> assert false)
      functor_map
      object_maker
      (fun () -> self#get_field4)
      self#set_field4

  (* A field containing a list of (marshallable) objects:
     Concrete syntax:
       tag (object list) val mutable field4 : class2 list = None
  *)
  val mutable field5 : class2 list = []
  method get_field5 = field5
  method set_field5 v = field5 <- v
  initializer
    let object_maker = get_basic_constructor "class2" ~involved_field:"field5" ~involved_class in
    let functor_map = List.map in          (* from the tag: list -> List.map *)
    self#marshaller#register_functorized_object_field ~name:"field5"
      ~zip:(List.combine)
      functor_map
      object_maker
      (fun () -> self#get_field5)
      self#set_field5

end (* end of class2.. *)
(* ..but the class definition is not complete: we have to register its basic class constructor: *)
let () = register_basic_constructor ~class_name:"class2" (fun () -> new class2 ())

class class3 ?(marshaller:(marshaller option ref) option) () =
let marshaller = match marshaller with None -> ref None | Some r -> r in
let involved_class = "class3" in
object (self)

  (* Automatically added at the beginning of the class definition: *)
  inherit marshallable_class ~name:"class3" ~marshaller ()

  (* Note that now `marshaller' stands for the inherited field (not the parameter): *)
  inherit class2 ~marshaller ()

  val mutable field6 = '6'
  method get_field6 = field6
  method set_field6 v = field6 <- v
  initializer
    self#marshaller#register_simple_field ~name:"field6" (fun () -> self#get_field6) self#set_field6;

  val mutable field7 : (class2, class3) Either.t = Either.Left (new class2 ())
  method get_field7 = field7
  method set_field7 v = field7 <- v
  initializer
    let object_maker1 = get_basic_constructor "class2" ~involved_field:"field7" ~involved_class in
    let object_maker2 = get_basic_constructor "class3" ~involved_field:"field7" ~involved_class in
    let functor_map = Either.Bifunctor.map in
    self#marshaller#register_bifunctorized_objects_field ~name:"field7"
      ~zip:(fun x y -> match x,y with (Left a, Left b) -> Left (a,b) | (Right c, Right d) -> Right (c,d) | _,_ -> assert false)
      functor_map
      object_maker1
      object_maker2
      (fun () -> self#get_field7)
      self#set_field7

end
let () = register_basic_constructor ~class_name:"class3" (fun () -> new class3 ())

let crash_test () =
  let x  = new class3 () in
  let y  = new class3 () in
  assert ((x=y) = false);
  (* but *)
  assert (x#marshaller#equals y);
  let z1  = new class2 () in
  let z2  = new class2 () in
  let load_y_with_x ?reuse ?upcasting () =
    let options =
      make_loading_options
        ?try_to_preserve_upcasting:upcasting
        ?try_to_reuse_living_objects:reuse
        ()
    in
    y#marshaller#load_from_string ~options (x#marshaller#save_to_string)
  in
  x#set_field5 [z1; z2];
  assert (not (x#marshaller#equals y));
  load_y_with_x ();
  assert (x#marshaller#equals y);

  (* --- Test objects' reusing: *)
  let oid1 = Oo.id (List.hd (x#get_field5)) in
  let oid2 = Oo.id (List.hd (y#get_field5)) in
  assert (oid1 <> oid2);
  load_y_with_x ();
  let oid3 = Oo.id (List.hd (y#get_field5)) in
  assert (oid2 <> oid3);
  load_y_with_x ~reuse:() ();
  let oid4 = Oo.id (List.hd (y#get_field5)) in
  assert (oid3 = oid4);

  (* --- A little change in (the graph of) x: *)
  assert (x#marshaller#equals y);
  z1#set_field0 1234;
  assert (not (x#marshaller#equals y));
  let z1' = List.hd y#get_field5 in
  assert (not (z1#marshaller#equals z1'));
  z1'#set_field0 1234;
  assert (z1#marshaller#equals z1');
  assert (x#marshaller#equals y);

  (* --- Test bifunctors: *)
  let z  = new class3 () in
  x#set_field7 (Either.Right z);
  assert (not (x#marshaller#equals y));
  load_y_with_x ();
  assert (x#marshaller#equals y);

  (* --- Test reusing with bifunctors (zip): *)
  let oid1 = Oo.id (Either.get_right (y#get_field7)) in
  load_y_with_x ();
  let oid2 = Oo.id (Either.get_right (y#get_field7)) in
  assert (oid1 <> oid2);
  load_y_with_x ~reuse:() ();
  let oid3 = Oo.id (Either.get_right (y#get_field7)) in
  assert (oid2 = oid3);

  (* --- Test cyclicity and casting: *)
  x#set_field3 (x :> class1);
  assert (not (x#marshaller#equals y));
  load_y_with_x ();
  (* because loops are recognized and reproduced identically: *)
  assert (x#marshaller#equals y);
  (* but... *)
  x#set_field3 (z1 :> class1);
  load_y_with_x ();
  (* now field3 is not a loop: *)
  assert (not (x#marshaller#equals y));
  (* we have to set the option ~try_to_preserve_upcasting *)
  load_y_with_x ~upcasting:() ();
  (* now it's fine: *)
  assert (x#marshaller#equals y);

  (* --- Test loading from structure containing itself: *)
  z#set_field7 (Either.Right x);        (* x -> z -> x *)
  z#set_field5 ([x; z] :> class2 list); (* x -> z -> z *)
  load_y_with_x ();
  assert (not (x#marshaller#equals y)); (* because of casting! *)
  load_y_with_x ~upcasting:() ();
  assert (x#marshaller#equals y);

  z#set_field5 ([y; x; z] :> class2 list); (* y is in the graph of x and conversely... *)
  assert ((y :> class2) = List.hd ((Either.get_right x#get_field7)#get_field5));
  load_y_with_x ~upcasting:() ();
  (* because y in the list of (z of) x was not recognized as... y itself
     when y was loading: *)
  assert (not (x#marshaller#equals y));
  (* but the first element of the list in y is the old state of y, not the new state
     obtained loading from x: *)
  let y'= List.hd ((Either.get_right y#get_field7)#get_field5) in
  assert (not (y#marshaller#equals y'));
  (* so, we can try to fix y' in this way: *)
  let options = make_loading_options ~try_to_preserve_upcasting:() () in
  y'#marshaller#load_from_string ~options (y#marshaller#save_to_string);
  (* but y has not the same graph of x: is an equivalent graph where a loop
     has been expanded: *)
  assert (not (x#marshaller#equals y));
  (* so, we can't restore the broken loop. A solution of this problem
     could be to define a sigle method saving and loading at same time
     (instead of doing them sequentially) *)

  (* --- Test remove_upcasting: *)
  (* Reloading x and z with themselves, the surplus of methods
     of their sub-objects will be removed: *)
  x#marshaller#remake_simplest;
  assert (not (x#marshaller#equals y));
  y#marshaller#remake_simplest;
  (* Now it's fine: *)
  assert (x#marshaller#equals y);
  (* Success: *)
  Printf.printf "Success.\n";
  ()
;;

end (* module Example *)
ENDIF
