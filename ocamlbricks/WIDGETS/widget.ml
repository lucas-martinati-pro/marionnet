(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Jean-Vincent Loddo

   Trivial change in 2008 by Luca Saiu

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

(** Some generic tools for building GUIs *)

open Sugar;;

(** {2 Image manipulations } *)

(** Module for managing images.  *)
module Image = struct

(** Scale the given image at the given size (width,height). @return a new image *)
let scaleTo (width,height) pixbuf =
  begin
  let scaled = GdkPixbuf.create ~has_alpha:true ~width ~height () in
(*  GdkPixbuf.scale ~dest:scaled ~width ~height ~interp:`BILINEAR pixbuf; *)
  GdkPixbuf.scale ~dest:scaled ~width ~height ~interp:`HYPER pixbuf;
  scaled
  end
;;

(** Make a zoom of the given image with the given factor (>1 |> zoom IN, <1 |> zoom OUT).
    @return a new image *)
let zoom (factor:float) pixbuf =
  let formule = (fun x -> (float_of_int  x)  *. factor +. 0.5 ) ||> int_of_float in
  let width  = pixbuf |> (GdkPixbuf.get_width  ||> formule) in
  let height = pixbuf |> (GdkPixbuf.get_height ||> formule) in
  prerr_endline ("Old width="^(string_of_int (GdkPixbuf.get_width pixbuf)));
  prerr_endline ("Old height="^(string_of_int (GdkPixbuf.get_height pixbuf))^"\n");
  scaleTo (width,height) pixbuf
;;

(** The pixels to inch conversion: ppi stands for pixel-per-inch *)
let inch_of_pixels ?(ppi=96.) (x:int) = (float_of_int x) /. ppi ;;

end;; (* module Image *)


(** {2 Dynamic submenus } *)

(** Module for building dynamic {e submenus}. A {e submenu} is a menu included in another menu.  *)
module DynamicSubmenu = struct

(** Makes a dynamic submenu of a given menu (the {e father}). When
    the father is activated, the submenu entries are recalculated with the given function ([dynList]).

Exemple:

{[make
  ~submenu:w#MACHINE_ELIM_menu
  ~menu:w#MACHINE_ELIM
  ~dynList:machineList
  ~action:(fun x ->fun _ -> prerr_endline x)   ;; ]}
*)
let make
   ?(set_active:(string->bool)=(fun x->false))
   ~(submenu: GMenu.menu)
   ~(menu:    GMenu.menu_item)
   ~(dynList: unit->(string list))
   ~(action:  string->unit->unit) () =

  let recalc () = (

    List.iter  (submenu#remove) (submenu#children) ;

    List.iter  (fun x -> let i=(GMenu.check_menu_item ~active:(set_active x) ~label:x  ~packing:(submenu#add) ()) in
                         let _ = i#connect#toggled ~callback:(action x) in ()
                )
               (dynList ())          ) in

  let _ = menu#connect#activate ~callback:recalc in
  ()
;;
end;; (* Module DynamicSubmenu *)



(* ********************************* *
      Module  ComboTextTree

    comboTextTree class & constructors
 * ********************************* *)


(** {2 ComboText Trees} *)

(** Module for building a set (structured in a tree hierarchy) of dependent combo texts.
    Any change of the selected value of a particular node, cause the rebuilding
    of the choice list of all its descendents in the tree. *)
module ComboTextTree = struct

(** {2 Class definition} *)

(** A ComboTextTree is a combo with eventually some dependent {i children} (or {i slaves}).
    The choice list of a node in the tree depends on the father's selected value and on the
    ancestors's selected values. The list of choices of a node is given dynamically by a function
    called the {i generator} which is used to calculte or recalculate the choice list.
*)
class comboTextTree = fun

  (* The option generator. May be a constant function as particular case. *)
  ~(generator: string Environments.string_env -> string list)

  (* The first input for the generator. *)
  ~(msg:string Environments.string_env)

  (* The key of the pair (key,value) send to its children. *)
  ~(key:string)

  (* An optional callback function, to call at any change *)
  ~(callback:(string->unit) option)

  (* The packing function. *)
  ~(packing:(GObj.widget -> unit) option)

  ->  (* Build the initial combo list (no packing and no callback are defined here
         (because self dont exist at this stage). *)
      let strList = (generator msg) in
      let (initial_box, (_, initial_col)) = GEdit.combo_box_text ~strings:strList () in
      let _ = initial_box#set_active 0  in

  object (self)

  (** Constant fields (methods) *)

  (** The function to build or rebuild the choices using the given environnement.
      For a simple comboTextTree, this method is used only at the creation and the function
      is not really dependent from its argument, but it is a simple costant function. *)
  method generator : (string Environments.string_env -> string list) = generator

  (** The key of the pair (key,value) which this widget (node) eventually transmit to its children (slaves). This field
      is set at the creation. The value of the pair (key,value) will be the selected value of the widget, of course. *)
  method key : string = key

  (** A secondary function to call at any change of the selected item. This represent an additional callback.
      The principal callback is the method [children_rebuild] which propagate the selected value to all children. *)
  method callback  : (string -> unit) = match callback with None   -> (fun x->()) | Some f -> f

  (** The function to call to attach self somewhere. For instance :
      {[ packing = dialog#table#attach ~left:1 ~top:2 ~right:3 ]}
      Every time the comboTextTree is rebuilt, the old box is destroyed, rebuilt and finally repackaged
      with this packing function. *)
  method packing   : (GObj.widget -> unit) = match packing with None -> (fun x->()) | Some f -> f

  (** Variable fields *)

  (** This fields stores the environment used for the last generation of the choice list.
      This information is fundamental because if this widget has some ancestors and also some descendents,
      for any alteration of its state, it must resend to its children the last environment received
      from its ancestors enriched with the pair (key,value) representing its own state. In this way,
      every descendent know the state of all its ancestors (not only the state of its father). *)
  val mutable env     : (string Environments.string_env)     = msg

  (** The choices calculated by the last call to the generator. *)
  val mutable choices : (string list)  = (generator msg)

  (** The currently encapsulated [GEdit.combo_box]. *)
  val mutable box     : #GEdit.combo_box  = initial_box
  val mutable col     : ('a GTree.column) = initial_col

  (** The children list of this widget. *)
  val mutable children  : comboTextTree list = []

  (** Accessors *)

  method env     = env
  method choices = choices
  method box     = box
  method col     = col
  method children  = children
  method child i = List.nth children i

  (** Convenient aliases *)

  method slave   = List.nth children 0
  method slave0  = List.nth children 0
  method slave1  = List.nth children 1
  method slave2  = List.nth children 2
  method slave3  = List.nth children 3
  method slave4  = List.nth children 4
  method slave5  = List.nth children 5

  (** Fixing variable fields *)

  method set_env     r = env     <- r
  method set_choices l = choices <- l
  method set_box     b = box     <- b
  method set_col     c = col     <- c
  method set_children  l = children  <- l
  method add_child   x = children  <- children @ [x]

  (** Selected item *)

  (** In the most cases, {b the only interesting method} from an abstract point of view.
      @return the selected string belong the combo items *)
  method selected =
    match self#box#active_iter with
    | None     -> ""
    | Some row -> (self#box#model#get ~row ~column:self#col)


  (** Set the current active (selected) choice by its value (instead of its index) *)
  method set_active_value (v:string) =
    try
      let i = Option.extract (ListExtra.indexOf v self#choices) in
      self#box#set_active i ;
      self#children_rebuild ()
    with _ -> ()


  (** Rebuilding self and children *)

  (** Demands to all children to rebuild theirself and their children and so on.
      This procedure is performed sending to all children the ancestor environment (method [env]) enriched by
      the pair (key,value), where value is the current selected item of this node. *)
  method children_rebuild () =
    let msg = Environments.make_string_env (self#env#to_list @ [(self#key,self#selected)]) in  (* x = self#selected *)
    List.iter (fun w -> w#rebuild msg) self#children


  (** Rebuild this widget, and its eventually all children, with the new given environment. *)
  method rebuild (msg : string Environments.string_env) =
    begin
      (* Save the current selected choice. We will try to reset it. *)
      let previous = self#selected in

      (* Destroy the old combo box. *)
      self#box#destroy () ;                          (* Essentiel! *)

      (* Rebuild combo list. *)
      let strList = (self#generator msg) in

      let (combo, (_, column)) = GEdit.combo_box_text ~strings:strList () in
      self#set_box combo                             ;
      self#set_col column                            ;
      self#set_choices strList                       ;
      self#initialize_callbacks                      ;  (* Re-initialize callbacks for the new box! *)
      self#packing   (self#box :> GObj.widget)       ;  (* repack self *)

      (* Register the last master environment *)
      self#set_env msg ;

      (* Try to restore the previous selected value (or select the index 0) *)
      let i = ((ListExtra.indexOf previous self#choices) |=> 0) in
      (self#box#set_active i) ;

      (* Propagate to its children. *)
      self#children_rebuild () ;

      ()
    end

  (**/**) (* STOP DOC *)

  (* Procédure de connection de l'élement changed d'un combo à un callback qui permet
     de faire appel à un second callback (cbackfun), de type string->unit, sur la chaine
     selectionnée dans le widget. *)
  method changedAndGetActive (cbfun:string->unit) =
    let _ = self#box#connect#changed ~callback:(
        fun () -> match self#box#active_iter with
                | None -> ()
                | Some row -> let data = (self#box#model#get ~row ~column:self#col) in cbfun data)
    in
    ()


  (* The packing initialization (only for bootstrap). *)
  val initialize_packing =
      let _ = match packing with None -> () | Some f -> f (initial_box :> GObj.widget) in ()

  (* This method must be called by a constructor after the bootstrap.
     These action cannot be placed in the boostrap of the instance. *)
  method initialize_callbacks =
    let _ = self#changedAndGetActive (fun x -> self#children_rebuild ()) in  (** First connect the standard callback. *)
    let _ = self#changedAndGetActive self#callback in ()    (** Second connect the given callback. *)

end;; (* class comboTextTree *)



(** {2 Constructors and convenient API} *)

(** A choice is simply a string. *)
type choice  = string;;

(** The type [choices] represent a [choice list], of course. *)
type choices = choice list;;


(** The simplest and general constuctor. Simply calls the class constructor and initialize callbacks. *)
let make

  ~(generator: (string Environments.string_env)->(string list)) (** The option generator. May be a constant function as particular case. *)
  ~(msg:string Environments.string_env)                         (** The input for the generator. *)
  ~(key:string)                                      (** The key of the pair (key,value) send to its children. *)
  ~(callback:(choice->unit) option)                  (** An optional callback function, to call at any change *)
  ~(packing:(GObj.widget -> unit) option)            (** The packing function. *)

    = let self = new comboTextTree ~generator ~msg ~key ~callback ~packing in
      let _ = self#initialize_callbacks in self
;;


(** Make a simple combo text with no children.
     You can specify a [key] (if you plan to affect some children to this widget) and an additional [callback]
     fonction of type [choice -> unit], which will be called every time the user will modify its selection.
     You also can specify a packing function. Examples:

- {[   let colors = fromList ["red"; "blue"; "black"] ;;  ]}

- {[   let colors = fromList
                      ~packing:(Some (dialog#table#attach ~left:2 ~top:6 ~right:4))
                      ["red"; "blue"; "black"]  ]}

*)
let fromList
  ?(key:string="unused_key")
  ?(callback:((choice->unit) option) = None )
  ?(packing:((GObj.widget -> unit) option) = None )
  (lst:choices)
  =
  let g = (fun r -> lst)  in
  let m = (Environments.make_string_env []) in
  make ~generator:g ~msg:m ~key ~callback ~packing
;;


(** {3 Combo chains} *)

(** {b Modelling a dependent chain of widgets: {v master -> slave -> slave -> .. v} } *)


(** Make a two level chain of dependent combos text. You can access to the slave simply writing [master#slave]
    ([slave] is simply an alias for the child number 0). Example :

{[    let distrib = fromListWithSlave
                      ~masterPacking: (Some (dialog#table#attach ~left:2 ~top:4 ~right:4))
                      ["debian";"redhat";"suse"]
                      ~slavePacking:  (Some (dialog#table#attach ~left:2 ~top:5 ~right:4))
                      MSys.patchListOf  ;; ]}
 *)
let fromListWithSlave
 ?(masterCallback:((choice->unit) option) = None)
 ?(masterPacking:((GObj.widget -> unit) option) = None)
  (masterChoices:choices)

 ?(slaveCallback:((choice->unit) option) = None)
 ?(slavePacking:((GObj.widget -> unit) option) = None )
  (slaveChoices: choice -> choices)

 = let master = fromList ~key:"master" ~callback:masterCallback ~packing:masterPacking masterChoices in
   let slave  = make
         ~generator:(fun r -> slaveChoices (r#get "master"))
         ~msg:(Environments.make_string_env [("master",master#selected)])
         ~key:"slave"
         ~callback:slaveCallback
         ~packing:slavePacking in

     let _ = master#add_child slave in master (* Here you set the dependency. *)
;;


(** Make a 3 levels chain of dependent combos text. You can access the slave simply writing [master#slave],
    and the slave of the slave simply writing [master#slave#slave]. *)
let fromListWithSlaveWithSlave
 ?(masterCallback:((choice->unit) option) = None)
 ?(masterPacking:((GObj.widget -> unit) option) = None)
  (masterChoices:choices)

 ?(slaveCallback:((choice->unit) option) = None)
 ?(slavePacking:((GObj.widget -> unit) option) = None )
  (slaveChoices: choice -> choices)

 ?(slaveSlaveCallback:((choice->unit) option) = None)
 ?(slaveSlavePacking:((GObj.widget -> unit) option) = None )
  (slaveSlaveChoices: choice -> choice -> choices)

 = let master =
     fromListWithSlave ~masterCallback ~masterPacking masterChoices ~slaveCallback ~slavePacking slaveChoices
   in
   let slaveSlave =
     make
       ~generator:(fun r -> slaveSlaveChoices (r#get "master") (r#get "slave"))
       ~msg:(Environments.make_string_env [("master",master#selected);("slave",master#slave#selected)])
       ~key:"slaveSlave"
       ~callback:slaveSlaveCallback
       ~packing:slaveSlavePacking
   in
   (* Here you set the dependency: *)
   let _ = master#slave#add_child slaveSlave in
   master
;;


(** Make a 4 levels chain of dependent combos text. You can access the slave chain simply by
    [master#slave], [master#slave#slave] and [master#slave#slave#slave].*)
let fromListWithSlaveWithSlaveWithSlave
 ?(masterCallback:((choice->unit) option) = None)
 ?(masterPacking:((GObj.widget -> unit) option) = None)
  (masterChoices:choices)

 ?(slaveCallback:((choice->unit) option) = None)
 ?(slavePacking:((GObj.widget -> unit) option) = None )
  (slaveChoices: choice -> choices)

 ?(slaveSlaveCallback:((choice->unit) option) = None)
 ?(slaveSlavePacking:((GObj.widget -> unit) option) = None )
  (slaveSlaveChoices: choice -> choice -> choices)

 ?(slaveSlaveSlaveCallback:((choice->unit) option) = None)
 ?(slaveSlaveSlavePacking:((GObj.widget -> unit) option) = None )
  (slaveSlaveSlaveChoices: choice -> choice -> choice -> choices)

 = let master =
     fromListWithSlaveWithSlave
        ~masterCallback      ~masterPacking      masterChoices
        ~slaveCallback       ~slavePacking       slaveChoices
        ~slaveSlaveCallback  ~slaveSlavePacking  slaveSlaveChoices in

   let slaveSlaveSlave = make
         ~generator:(fun r -> slaveSlaveSlaveChoices (r#get "master") (r#get "slave") (r#get "slaveSlave"))
         ~msg:(Environments.make_string_env [("master",master#selected);("slave",master#slave#selected);("slaveSlave",master#slave#slave#selected)])
         ~key:"slaveSlaveSlave"
         ~callback:slaveSlaveSlaveCallback
         ~packing:slaveSlaveSlavePacking in

     let _ = master#slave#slave#add_child slaveSlaveSlave in master (* Here you set the dependency. *)
;;


(** {3 Simple tree constructor} *)

(** {b Modelling a dependent tree of widgets: {v
         master
           /    \
       slave0   slave1
v} } *)

(** Make a simple tree with 3 nodes: a root combo with two combos (dependent) children (which can be accessed with the handlers
    [master#slave0] and [master#slave1]). This function is in this API as an exemple. See the code in order to easily
    define your own comboTextTree. *)
let fromListWithTwoSlaves
 ?(masterCallback:((choice->unit) option) = None)
 ?(masterPacking:((GObj.widget -> unit) option) = None)
  (masterChoices:choices)

 ?(slave0Callback:((choice->unit) option) = None)
 ?(slave0Packing:((GObj.widget -> unit) option) = None )
  (slave0Choices: choice -> choices)

 ?(slave1Callback:((choice->unit) option) = None)
 ?(slave1Packing:((GObj.widget -> unit) option) = None )
  (slave1Choices: choice -> choices)

 = let master =
     fromList ~key:"master" ~callback:masterCallback ~packing:masterPacking masterChoices
   in
   let slave0  =
     make
      ~generator:(fun r -> slave0Choices (r#get "master"))
      ~msg:(Environments.make_string_env [("master",master#selected)])
      ~key:"slave0"
      ~callback:slave0Callback
      ~packing:slave0Packing
   in
   let slave1  =
     make
      ~generator:(fun r -> slave1Choices (r#get "master"))
      ~msg:(Environments.make_string_env [("master",master#selected)])
      ~key:"slave1"
      ~callback:slave1Callback
      ~packing:slave1Packing
   in
   let _ = master#add_child slave0 in
   let _ = master#add_child slave1 in
   master
;;

let fromListWithThreeSlaves
 ?(masterCallback:((choice->unit) option) = None)
 ?(masterPacking:((GObj.widget -> unit) option) = None)
  (masterChoices:choices)

 ?(slave0Callback:((choice->unit) option) = None)
 ?(slave0Packing:((GObj.widget -> unit) option) = None )
  (slave0Choices: choice -> choices)

 ?(slave1Callback:((choice->unit) option) = None)
 ?(slave1Packing:((GObj.widget -> unit) option) = None )
  (slave1Choices: choice -> choices)

 ?(slave2Callback:((choice->unit) option) = None)
 ?(slave2Packing:((GObj.widget -> unit) option) = None )
  (slave2Choices: choice -> choices)

 = let master =
     fromList ~key:"master" ~callback:masterCallback ~packing:masterPacking masterChoices
   in
   let slave0  =
     make
      ~generator:(fun r -> slave0Choices (r#get "master"))
      ~msg:(Environments.make_string_env [("master",master#selected)])
      ~key:"slave0"
      ~callback:slave0Callback
      ~packing:slave0Packing
   in
   let slave1  =
     make
      ~generator:(fun r -> slave1Choices (r#get "master"))
      ~msg:(Environments.make_string_env [("master",master#selected)])
      ~key:"slave1"
      ~callback:slave1Callback
      ~packing:slave1Packing
   in
   let slave2  =
     make
      ~generator:(fun r -> slave2Choices (r#get "master"))
      ~msg:(Environments.make_string_env [("master",master#selected)])
      ~key:"slave2"
      ~callback:slave2Callback
      ~packing:slave2Packing
   in
   let _ = master#add_child slave0 in
   let _ = master#add_child slave1 in
   let _ = master#add_child slave2 in
   master
;;


end ;; (* Module ComboTextTree *)



(* ********************************* *
         Class TextView

  Facilities for using GtkTextView
 * ********************************* *)


class textview = fun ?(view:GText.view = GText.view ()) () ->

  let v = view in

  object (self)

  val view   = v
  val buffer = v#buffer
  val mutable iter = v#buffer#get_iter_at_char 0

  method view   = view

  (** Append text with the optional list of tags. *)
  method append ?(tags=[]) x =
         buffer#insert ~iter:iter ~tag_names:tags x

  (** Append the image found in the given filename  *)
  method append_image ?(scale:((int*int) option)=None) filename =
   begin
   let pixbuf = GdkPixbuf.from_file filename in
   let pixbuf = (match scale with
   | None                -> pixbuf
   | Some (width,height) -> let scaled = GdkPixbuf.create ~has_alpha:true ~width ~height () in
                            GdkPixbuf.scale ~dest:scaled ~width ~height ~interp:`BILINEAR pixbuf; scaled) in
   buffer#insert_pixbuf ~iter:iter ~pixbuf
   end

  (** Refresh the content applying tags. To use after all calls to append.  *)
  method refresh () =
   begin
   let start,stop = buffer#bounds in
   buffer#apply_tag_by_name "word_wrap" ~start ~stop ;
   ()
   end

  (** Delete the content of the buffer *)
  method delete () =
   begin
   let start,stop = buffer#bounds in
   buffer#delete ~start ~stop ;
   iter <- buffer#get_iter_at_char 0
   end

  (** As append but first delete the old content *)
  method rewrite ?(tags=[]) x = self#delete () ; self#append ~tags x

  (** Call by initializer *)
(*  method private create_tags () =
   begin
   let stipple = Gdk.Bitmap.create_from_data 2 2 "\002\001" in
   buffer#create_tag ~name:"heading"             [`WEIGHT `BOLD; `SIZE (15*Pango.scale)] |> ignore ;
   buffer#create_tag ~name:"italic"              [`STYLE `ITALIC]                        |> ignore ;
   buffer#create_tag ~name:"bold"                [`WEIGHT `BOLD]                         |> ignore ;
   buffer#create_tag ~name:"big"                 [`SIZE 20]                              |> ignore ;
   buffer#create_tag ~name:"xx-small"            [`SCALE `XX_SMALL]                      |> ignore ;
   buffer#create_tag ~name:"x-large"             [`SCALE `X_LARGE]                       |> ignore ;
   buffer#create_tag ~name:"monospace"           [`FAMILY "monospace"]                   |> ignore ;
   buffer#create_tag ~name:"blue_foreground"     [`FOREGROUND "blue"]                    |> ignore ;
   buffer#create_tag ~name:"red_background"      [`BACKGROUND "red"]                     |> ignore ;
   buffer#create_tag ~name:"background_stipple"  [`BACKGROUND_STIPPLE stipple]           |> ignore ;
   buffer#create_tag ~name:"foreground_stipple"  [`FOREGROUND_STIPPLE stipple]           |> ignore ;
   buffer#create_tag ~name:"big_gap_before_line" [`PIXELS_ABOVE_LINES 30]                |> ignore ;
   buffer#create_tag ~name:"big_gap_after_line"  [`PIXELS_BELOW_LINES 30]                |> ignore ;
   buffer#create_tag ~name:"double_spaced_line"  [`PIXELS_INSIDE_WRAP 10]                |> ignore ;
   buffer#create_tag ~name:"not_editable"        [`EDITABLE false]                       |> ignore ;
   buffer#create_tag ~name:"word_wrap"           [`WRAP_MODE `WORD]                      |> ignore ;
   buffer#create_tag ~name:"char_wrap"           [`WRAP_MODE `CHAR]                      |> ignore ;
   buffer#create_tag ~name:"no_wrap"             [`WRAP_MODE `NONE]                      |> ignore ;
   buffer#create_tag ~name:"center"              [`JUSTIFICATION `CENTER]                |> ignore ;
   buffer#create_tag ~name:"right_justify"       [`JUSTIFICATION `RIGHT]                 |> ignore ;
   buffer#create_tag ~name:"wide_margins"        [`LEFT_MARGIN  50; `RIGHT_MARGIN 50]    |> ignore ;
   buffer#create_tag ~name:"strikethrough"       [`STRIKETHROUGH true]                   |> ignore ;
   buffer#create_tag ~name:"underline"           [`UNDERLINE `SINGLE]                    |> ignore ;
   buffer#create_tag ~name:"double_underline"    [`UNDERLINE `DOUBLE]                    |> ignore ;
   buffer#create_tag ~name:"superscript"         [`RISE (10*Pango.scale); `SIZE (8*Pango.scale)]  |> ignore ;
   buffer#create_tag ~name:"subscript"           [`RISE (-10*Pango.scale); `SIZE (8*Pango.scale)] |> ignore ;
   buffer#create_tag ~name:"rtl_quote"[`WRAP_MODE `WORD; `DIRECTION `RTL; `INDENT 30; `LEFT_MARGIN 20; `RIGHT_MARGIN 20] |> ignore ;
   ()
   end

 initializer self#create_tags ()*)

end;; (* class textview *)









