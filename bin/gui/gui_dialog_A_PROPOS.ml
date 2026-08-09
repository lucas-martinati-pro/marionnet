(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007-2026  Jean-Vincent Loddo
   Copyright (C) 2007  Luca Saiu
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


(** Gui completion for the dialog_A_PROPOS widget defined with glade. *)

(* --- *)
module Environments = Ocamlbricks.Environments
(* --- *)
open Gettext;;

(* Shortcuts *)
let mkenv = Environments.make_string_env

module Make (State:sig val st:State.globalState end) = struct

  (* open State *)

  (* User handler for dialog completion. *)
  let dialog () =

   let d = new Gui.dialog_A_PROPOS (*~width:800 ~height:600*) () in
   d#toplevel#set_title (s_ "About");
   (* No #resize here on purpose. A pixel size was fighting a symptom: since the
      labels of this dialog wrap, their natural width used to be the whole text
      unwrapped (measured: 4978 px), so the dialog opened as wide as the screen and
      the resize had to cap it -- a cap the window manager applies asynchronously,
      hence a size that was not even reproducible. The constraint now lives where it
      belongs, in the glade: `max-width-chars' 80 on the labels that wrap (natural
      width down to 1212 px), and the four copyright lines have a label of their own
      which does NOT wrap, so each of them holds on a single line whatever the width
      of the dialog, the font and the theme. *)
(*    d#toplevel#resize ~width:600 ~height:400; *)
(*    d#toplevel#resize ~width:1024 ~height:400; *)
    (*d#scrolledwindow11#resize ~width:600 ~height:400;*)


   (* Labels *)
   let () = begin
    let set label text =
      label#set_use_markup true;
      label#set_label text
    in

   set d#label_dialog_A_PROPOS_a_propos (s_ "About");

   let text_title =
     Printf.sprintf "<b>%s</b>" (s_ "Marionnet, a virtual network laboratory")
   in
   let text_subtitle =
     Printf.sprintf "<i>Version %s </i> revno %s - %s" Version.version Meta.revision Meta.source_date
   in
   let title = Printf.sprintf "\n%s\n<small>%s</small>\n" text_title text_subtitle in
   set d#label_dialog_A_PROPOS_title title;

   set d#label_dialog_A_PROPOS_a_propos_content (s_ "<b>Marionnet</b> is an environment for the simulation of a network composed of GNU/Linux machines. This software was thought for students to experiment with bulding and configuring networks, and for teachers to prepare excercises and tests.\n\nMarionnet is based on the UML features of the Linux kernel.\n<tt><u><span color=\"blue\">http://www.marionnet.org</span></u></tt>\n");

   set d#label_dialog_A_PROPOS_authors (s_ "Authors");
   set d#label_dialog_A_PROPOS_authors_content "
<b><span color=\"dimgray\">Jean-Vincent Loddo</span></b>
Département R&amp;T - IUT de Villetaneuse
Laboratoire d'Informatique de Paris Nord (LIPN)
Université Sorbonne Paris Nord (USPN) 2007-2023
Université numérique Île-de-France (UNIF) 2024-2026\n
<b><span color=\"dimgray\">Luca Saiu</span></b>
Laboratoire d'Informatique de Paris Nord (LIPN)
Université Sorbonne Paris Nord (USPN) 2007-2012\n\n";

   set d#label_dialog_A_PROPOS_license (s_ "License");
   (* Own label, which does not wrap: each copyright line is then guaranteed to fit
      on a single line whatever the width of the dialog, the font and the theme: *)
   set d#label_dialog_A_PROPOS_license_copyright "
Copyright (C) 2007-2026  Jean-Vincent Loddo
Copyright (C) 2007-2012  Luca Saiu
Copyright (C) 2007-2026  Université Sorbonne Paris Nord (USPN)
Copyright (C) 2026  Université numérique Île-de-France (UNIF)";
   set d#label_dialog_A_PROPOS_license_content "
<i>Marionnet is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 2 of the License, or (at your option) any later version.</i>\n
This program is distributed in the hope that it will be useful, but <b>WITHOUT ANY WARRANTY</b>; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.\n
You should have received a copy of the GNU General Public License along with this program.  If not, see
<tt><u><span color=\"blue\">http://www.gnu.org/licenses/</span></u></tt>.\n
<b>Logos.</b> The emblems of USPN, of the IUT de Villetaneuse, of the LIPN and of UNIF displayed by this program are the trademarks of these institutions. They are <b>not</b> covered by the GNU GPL and remain the property of their owners: they are reproduced here for the sole purpose of crediting the institutions that support Marionnet, and may not be reused or modified independently of this program. Their origin is recorded in the file <tt>images/LOGOS.md</tt> of the distribution.\n\n";

   set d#label_dialog_A_PROPOS_thanks "Thanks";
   set d#label_dialog_A_PROPOS_thanks_content "We wish to thank Jeff Dike and the other authors of UML for their nice work, which made Marionnet possible; Renzo Davoli for VDE, the powerful communication infrastructure that we used and modified; the authors of OCaml for their nice language; and of course the whole free software community, of which the GNU and Linux projects remain the foremost contributors.\n
This beautiful logo was designed by Silviu Barsanu:\n<tt><u><span color=\"blue\">http://www.silviubarsanu.evonet.ro</span></u></tt>";
   (* The line break is deliberate (the label does not wrap): it balances the two
      lines instead of letting the width of the dialog decide. The second one then
      carries both institutions in parallel: *)
   set d#label_dialog_A_PROPOS_thanks_sponsors
     "Marionnet has been sponsored as an e-learning project\nby USPN since 2007, and supported by UNIF since 2024";
   end

   in d

end
