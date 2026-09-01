(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008, 2009  Luca Saiu
   Copyright (C) 2010-2026  Jean-Vincent Loddo
   Copyright (C) 2007-2026 Université Sorbonne Paris Nord (USPN)
   Copyright (C) 2026 Université numérique Île-de-France (UNIF)

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

(* --- *)
module Log = Marionnet_log

open Gettext;;

(* span foreground="red" *)

let text_title =
  Printf.sprintf
    "<small><b>%s</b></small>"
    (s_ "Marionnet, a virtual network laboratory")
;;

let text_subtitle = match Initialization.released with
 | true  -> "<small><i>Version " ^ Initialization.user_intelligible_version ^ "</i> - " ^ Meta.source_date_utc_yy_mm_dd ^ "</small>"
 | false -> "<small><i>Version " ^ Initialization.user_intelligible_version ^ "</i> - " ^ Meta.source_date ^ "</small>"
;;

let text_copyright =
"<small>Copyright (C) 2007-2026 Jean-Vincent Loddo
Copyright (C) 2007-2012 Luca Saiu
Copyright (C) 2007-2026 Université Sorbonne Paris Nord (USPN)
Copyright (C) 2026 Université numérique Île-de-France (UNIF)</small>";;

(* Split from the copyright block above in order to be centered (see the ~justify
   argument where this label is built), the copyright lines remaining flush left: *)
let text_warranty =
"<small><i>Marionnet comes with <b>absolutely no warranty</b>.
This is free software, covered by the GNU GPL.
You are welcome to redistribute it under certain
conditions; see the file `COPYING' for details.</i></small>";;

let handle_click window _ =
  Log.printf "handle_click: the splash screen was closed\n";
  window#misc#hide ();
  window#destroy ();
  true;;

(*let splash_image =
  GDraw.pixmap_from_xpm
    ~file:(Initialization.Path.images^"splash.300x348.xpm")
    ();;*)

(* GdkPixbuf.from_file : string -> pixbuf *)
let splash_pixbuf : GdkPixbuf.pixbuf =
    GdkPixbuf.from_file (Initialization.Path.images^"splash.300x348.xpm");;

let splash =
  GWindow.window
    ~resizable:false
    ~border_width:24
    ~position:`CENTER
    ~type_hint:`DIALOG
    ~modal:true
(*   ~wm_name:"Marionnet splash screen" *)
    ~icon:Icon.icon_pixbuf
    ();;

splash#set_title (s_ "Welcome to Marionnet");;
let event_box = GBin.event_box ~packing:splash#add () in
(* The spacing separates the four blocks of the splash (image and title, copyright,
   warranty, logos) with one and the same vertical gap: *)
let box = GPack.vbox ~spacing:32 ~border_width:2 ~packing:event_box#add () in
(*let _image = GMisc.pixmap splash_image ~packing:(box#pack ~padding:3) () in*)
let _image = GMisc.image ~pixbuf:(splash_pixbuf) ~packing:(box#pack ~padding:3) ~show:true () in
(* --- *)
let _title =
  let align = GBin.alignment ~xalign:1. ~packing:box#add () in
  let table = GPack.table ~rows:2 ~columns:1 ~row_spacings:0 ~homogeneous:false ~packing:(align#add) () in
  let attach = table#attach ~expand:`X ~fill:`BOTH ~left:0 in
  let _ = GMisc.label ~markup:text_title    ~packing:(attach ~top:0) ~xalign:0.5 ~line_wrap:false () in
  let _ = GMisc.label ~markup:text_subtitle ~packing:(attach ~top:1) ~xalign:0.5 ~line_wrap:false () in
  ()
in
let _ = GMisc.label ~markup:text_copyright ~packing:box#add ~line_wrap:false () in
let _ = GMisc.label ~markup:text_warranty ~justify:`CENTER
          ~packing:box#add ~line_wrap:false () in
(* --- *)
(* The logos have different widths (the IUT one is a wide logotype, which has to
   stay readable). The table is therefore NOT homogeneous: each column takes the
   natural width of its logo plus an equal share of the remaining space, which
   spreads the four logos over the whole width with equal gaps: *)
let table =
  GPack.table ~rows:1 ~columns:4 ~col_spacings:16
    ~homogeneous:false
    ~packing:box#add ()
in
let attach = table#attach ~expand:`X ~fill:`BOTH ~top:0 in
let _logo_uspn =
 GMisc.image
   ~file:(Initialization.Path.images^"logo.uspn.png")
   ~xalign:0.5 ~packing:(attach ~left:0) ()
in
let _logo_iutv =
 GMisc.image
   ~file:(Initialization.Path.images^"logo.iutv.png")
   ~xalign:0.5 ~packing:(attach ~left:1) ()
in
let _logo_lipn =
 GMisc.image
   ~file:(Initialization.Path.images^"logo.lipn.png")
   ~xalign:0.5 ~packing:(attach ~left:2) ()
in
let _logo_unif =
 GMisc.image
   ~file:(Initialization.Path.images^"logo.unif.png")
   ~xalign:0.5 ~packing:(attach ~left:3) ()
in
let _ = event_box#event#connect#button_press ~callback:(handle_click splash) in
let _ = splash#event#connect#key_press       ~callback:(fun ev -> handle_click splash ()) in ()
;;

let show_splash ?timeout () =
  (match timeout with
    Some timeout ->
      ignore
        (GMain.Timeout.add
           ~ms:timeout
           ~callback:(fun () -> ignore (handle_click splash ()); false))
  | None ->
      ());
  splash#show ();;
