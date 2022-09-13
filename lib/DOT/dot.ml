(* This file is part of ocamlbricks
   Copyright (C) 2010 Jean-Vincent Loddo

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

#load "include_type_definitions_p4.cmo";;
INCLUDE DEFINITIONS "../../../../lib/DOT/dot.mli"
;;

type graph = {
  strict     : bool;
  digraph    : bool;
  name       : name;
  statements : statement list;
  }

 and statement =
   | Graph_default  of graph_option                           (* name=val *)
   | Graph_defaults of graph_option list                      (* graph [name=val,..] *)
   | Node_defaults  of node_option  list                      (* node [name=val,..] *)
   | Edge_defaults  of edge_option  list                      (* edge [name=val,..] *)
   | Node of node_ident * (node_option list)                  (* id [name=val,...] *)
   | Edge of node_ident * node_ident * (edge_option list)     (* id -> id [name=val,...] *)
   | Subgraph of name * (statement list)                      (* subgraph name { statements } *)
(*    | Statement_list of statement list *)

 and name = string
 and graph_option = string
 and node_option = string
 and edge_option = string

let commacat = String.concat ","
let newlinecat = String.concat "\n"

let rec cotokens_of_statement tab edge_operator = function
| Graph_default graph_option          ->  [Printf.sprintf "%s%s" tab graph_option]
| Graph_defaults graph_option_list    ->  [Printf.sprintf "%sgraph [%s]" tab  (commacat graph_option_list)]
| Node_defaults  node_option_list     ->  [Printf.sprintf "%snode [%s]" tab  (commacat node_option_list)]
| Edge_defaults  edge_option_list     ->  [Printf.sprintf "%sedge [%s]" tab  (commacat edge_option_list)]
| Node (node_ident, node_option_list) ->  [Printf.sprintf "%s%s [%s]" tab  node_ident (commacat node_option_list)]
| Edge (n1, n2, edge_option_list)     ->  [Printf.sprintf "%s%s %s %s [%s]" tab n1 edge_operator n2 (commacat edge_option_list)]
(* | Statement_list statement_list       ->  List.flatten (List.map (cotokens_of_statement tab edge_operator) statement_list) *)
| Subgraph (name, statement_list)     ->
    let tab' = (tab^"  ") in
    let first = Printf.sprintf "%ssubgraph %s {" tab name in
    let last  = Printf.sprintf "%s}" tab in
    let rest  = ListExtra.flatten ~acc:[last] (List.map (cotokens_of_statement tab' edge_operator) statement_list) in
    first::rest

let cotokens_of_graph { strict = strict; digraph = digraph; name = name; statements = statements; } =
  let strict  = if strict then "strict " else "" in
  let (digraph, edge_operator) = if digraph then ("digraph","->") else ("graph","--") in
  let first = Printf.sprintf "%s%s %s {" strict digraph name in
  let last  = Printf.sprintf "}" in
  let rest = ListExtra.flatten ~acc:[last] (List.map (cotokens_of_statement "  " edge_operator) statements) in
  first::rest

let print g =
 begin
 List.iter (Printf.printf "%s\n") (cotokens_of_graph g);
 flush stdout;
 end

let fprint filename g =
 begin
  let ch = open_out filename in
  List.iter (Printf.fprintf ch "%s\n") (cotokens_of_graph g);
  flush ch;
  close_out ch;
 end

let sprint g = newlinecat (cotokens_of_graph g)

let string_of_output_format = function
|`bmp-> "bmp"
|`canon->"canon"
|`dot->"dot"
|`xdot->"xdot"
|`cmap->"cmap"
| `dia->"dia"
|`eps->"eps"
|`fig->"fig"
|`gd->"gd"
|`gd2->"gd2"
|`gif->"gif"
|`hpgl->"hpgl"
|`ico->"ico"
|`imap->"imap"
|`cmapx->"cmapx"
|`imap_np->"imap_np"
|`cmapx_np->"cmapx_np"
|`ismap->"ismap"
|`jpg->"jpg"
|`pdf->"pdf"
|`plain->"plain"
|`plain_ext->"plain_ext"
|`png->"png"
|`ps->"ps"
|`ps2->"ps2"
|`svg->"svg"
|`svgz->"svgz"
|`tiff->"tiff"
|`vml->"vml"
|`vmlz->"vmlz"
|`vrml->"vrml"
|`wbmp->"wbmp"
(* |`xlib->"xlib" *)

let output_format_of_string = function
| "bmp" -> `bmp
| "canon" -> `canon
| "dot" -> `dot
| "xdot" -> `xdot
| "dia" -> `dia
| "cmap" -> `cmap
| "eps" -> `eps
| "fig" -> `fig
| "gd" -> `gd
| "gd2" -> `gd2
| "gif" -> `gif
| "hpgl" -> `hpgl
| "ico" -> `ico
| "imap" -> `imap
| "cmapx" -> `cmapx
| "imap_np" -> `imap_np
| "cmapx_np" -> `cmapx_np
| "ismap" -> `ismap
| "jpg" -> `jpg
| "pdf" -> `pdf
| "plain" -> `plain
| "plain_ext" -> `plain_ext
| "png" -> `png
| "ps" -> `ps
| "ps2" -> `ps2
| "svg" -> `svg
| "svgz" -> `svgz
| "tiff" -> `tiff
| "vml" -> `vml
| "vmlz" -> `vmlz
| "vrml" -> `vrml
| "wbmp" -> `wbmp
(* | "xlib" -> `xlib                                                                                                                                                                                   *)
| _ -> raise Not_found

let admissible_output_formats = [
  `bmp; `canon; `dia; `dot; `xdot; `cmap; `eps; `fig; `gd; `gd2; `gif; `hpgl; `ico; `imap; `cmapx; `imap_np; `cmapx_np; `ismap;
  `jpg; `pdf; `plain; `plain_ext; `png; `ps; `ps2; `svg; `svgz; `tiff; `vml; `vmlz; `vrml; `wbmp; (*`xlib;*)
   ]

let admissible_output_formats_as_strings =
  List.map string_of_output_format admissible_output_formats

let output_format_description = function
 | `bmp                    -> "Windows Bitmap Format"
 | `canon | `dot | `xdot   -> "Graphviz dot drawing program"
 | `cmap                   -> "Client-side imagemap (deprecated)"
 | `dia                    -> "Diagram creation program"
 | `eps                    -> "Encapsulated PostScript"
 | `fig                    -> "FIG vector drawing format"
 | `gd                     -> "GD graphics library format"
 | `gd2                    -> "GD2 graphics library format"
 | `gif                    -> "GIF Graphics Interchange Format"
 | `hpgl                   -> "HP-GL subset of PCL"
 | `ico                    -> "Icon Image File Format"
 | `imap | `cmapx          -> "Server- and client-side imagemaps"
 | `imap_np | `cmapx_np    -> "Server- and client-side imagemaps"
 | `ismap                  -> "Server-side imagemap (deprecated)"
 | `jpg                    -> "JPEG Joint Photographic Group"
 | `pdf                    -> "PDF Portable Document Format"
 | `plain | `plain_ext     -> "Simple text format"
 | `png                    -> "PNG Portable Network Graphics format"
 | `ps                     -> "PostScript"
 | `ps2                    -> "PostScript for PDF"
 | `svg                    -> "Scalable Vector Graphics"
 | `svgz                   -> "Compressed Scalable Vector Graphics"
 | `tiff                   -> "TIFF Tag Image File Format"
 | `vml                    -> "VML Vector Markup Language"
 | `vmlz                   -> "VML Compressed Vector Markup Language"
 | `vrml                   -> "VRML Text file format"
 | `wbmp                   -> "Wireless BitMap format"
(* | `xlib                   -> "Xlib canvas" *)

let make_image ?silent ?dotfile ?imgfile ?(imgtype=`png) g =
 begin
 let imgtype = string_of_output_format imgtype in
 let dotfile = match dotfile with Some x -> x | None -> Filename.temp_file "Dot.make_image." ".dot" in
 let imgfile = match imgfile with Some x -> x | None -> Filename.temp_file "Dot.make_image." ("."^imgtype) in
 fprint dotfile g;
 let silent = match silent with None -> "" | Some () -> "2>/dev/null" in
 let cmd = Printf.sprintf "dot -T%s -o %s %s %s" imgtype imgfile dotfile silent in
 if (Sys.command cmd) <> 0
   then failwith (Printf.sprintf "Dot.make_image: dot doesn't like this graph (file: %s)" dotfile)
   else ();
 (dotfile, imgfile)
 end

let display_fg ~silent g =
 begin
 let dotfile = Filename.temp_file "Dot.display." ".dot" in
 let pngfile = Filename.temp_file "Dot.display." ".png" in
 fprint dotfile g;
 let cmd = Printf.sprintf "dot -Tpng -o %s %s %s" pngfile dotfile silent in
 if (Sys.command cmd) <> 0
  then failwith (Printf.sprintf "Dot.display (fg): dot doesn't like this graph (file: %s)" dotfile)
  else ();
 let cmd = Printf.sprintf "display %s %s" pngfile silent in
 if (Sys.command cmd) <> 0
  then failwith (Printf.sprintf "Dot.display (fg): display (imagemagick) doesn't like this png (file: %s)" pngfile)
  else ();
 Sys.remove dotfile;
 Sys.remove pngfile;
 end

(* The temporary file is not deleted. The correct implementation should use threads (or futures). *)
let display_bg ~silent g =
 begin
 let dotfile = "Dot.display.bg.dot" in
 fprint dotfile g;
 let cmd = Printf.sprintf "dot -Tpng %s %s | display %s &" dotfile silent silent in
 if (Sys.command cmd) <> 0
  then failwith (Printf.sprintf "Dot.display (bg): something goes wrong (dotfile: %s)" dotfile)
  else ();
 end

let display ?bg ?silent g =
  let silent = match silent with None -> "" | Some () -> "2>/dev/null" in
  match bg with None -> display_fg ~silent g | Some () -> display_bg ~silent g

(* Common functions for further modules. *)
module Common = struct
 let string_of_color = function
  | `RGB (r,g,b) -> Printf.sprintf "#%02x%02x%02x" r g b
  | `HSV (h,s,v) -> Printf.sprintf "%f %f %f" h s v
  | `name x      -> x
end

module Html_like_constructors = struct

 let append_to_ref options inject opt =
 match opt with
 | None -> ()
 | Some x -> (options := (inject x)::!options)

 let html_map f ?fontcolor ?fontname ?fontsize alpha : html_like =
   let font_attributes = ref [] in
   let append f x = append_to_ref font_attributes f x in
   append (fun x -> `COLOR x) fontcolor;
   append (fun x -> `FACE x) fontname;
   append (fun x -> `POINT_SIZE x) fontsize;
   match !font_attributes with
   | []     -> (f alpha)
   | fattrs -> (`FONT (fattrs, f alpha))

 let html_of_text =
   let f x = `text x in
   html_map f

 let html_of_table =
   let f x = `TABLE x in
   html_map f

 let html_of_label =
   let f = function
    | (`escaped s) -> (`text [`string s])
    | (`html h)    -> h
   in html_map f

 let label_of_text  ?fontcolor ?fontname ?fontsize x = `html (html_of_text  ?fontcolor ?fontname ?fontsize x)
 let label_of_table ?fontcolor ?fontname ?fontsize x = `html (html_of_table ?fontcolor ?fontname ?fontsize x)

 let text_of_string ?br ?align s : text =
   let attributes = ref [] in
   let append f x = append_to_ref attributes f x in
   append (fun x -> `ALIGN x) align;
   match br with
   | None    -> [ `string s ]
   | Some () -> [ `string s; `BR !attributes ]

 let text_concat (ts:text list) : text = List.flatten ts

 let table
  ?align ?valign ?bgcolor ?border ?cellborder ?cellpadding ?cellspacing
  ?fixedsize ?height ?href ?port ?target ?title ?tooltip ?width
  row_list : table =
   let attributes = ref [] in
   let append f x = append_to_ref attributes f x in
   append (fun x -> `ALIGN x) align;
   append (fun x -> `BGCOLOR x) bgcolor;
   append (fun x -> `BORDER x) border;
   append (fun x -> `CELLBORDER x) cellborder;
   append (fun x -> `CELLPADDING x) cellpadding;
   append (fun x -> `CELLSPACING x) cellspacing;
   append (fun x -> `FIXEDSIZE x) fixedsize;
   append (fun x -> `HEIGHT x) height;
   append (fun x -> `HREF x) href;
   append (fun x -> `PORT x) port;
   append (fun x -> `TARGET x) target;
   append (fun x -> `TITLE x) title;
   append (fun x -> `TOOLTIP x) tooltip;
   append (fun x -> `VALIGN x) valign;
   append (fun x -> `WIDTH x) width;
   (!attributes, row_list)


 let cell_map f ?align ?valign ?bgcolor ?border ?cellpadding
  ?cellspacing ?fixedsize ?height ?href ?port ?target ?title ?tooltip
  ?width ?colspan ?rowspan ?fontcolor ?fontname ?fontsize
  alpha : cell =
   let attributes = ref [] in
   let append f x = append_to_ref attributes f x in
   append (fun x -> `ALIGN x) align;
   append (fun x -> `BGCOLOR x) bgcolor;
   append (fun x -> `BORDER x) border;
   append (fun x -> `CELLPADDING x) cellpadding;
   append (fun x -> `CELLSPACING x) cellspacing;
   append (fun x -> `FIXEDSIZE x) fixedsize;
   append (fun x -> `HEIGHT x) height;
   append (fun x -> `HREF x) href;
   append (fun x -> `PORT x) port;
   append (fun x -> `TARGET x) target;
   append (fun x -> `TITLE x) title;
   append (fun x -> `TOOLTIP x) tooltip;
   append (fun x -> `VALIGN x) valign;
   append (fun x -> `WIDTH x) width;
   append (fun x -> `COLSPAN x) colspan;
   append (fun x -> `ROWSPAN x) rowspan;
   let font_attributes = ref [] in
   let append f x = append_to_ref font_attributes f x in
   append (fun x -> `COLOR x) fontcolor;
   append (fun x -> `FACE x) fontname;
   append (fun x -> `POINT_SIZE x) fontsize;
  (!attributes, f alpha !font_attributes)

let cell_of_text =
  let f text = function
   | []     -> `html (`text text)
   | fattrs -> `html (`FONT (fattrs, `text text))
  in
  cell_map f

let cell_of_string =
  let f s = function
   | []     -> `html (`text [`string s])
   | fattrs -> `html (`FONT (fattrs, `text [`string s]))
  in
  cell_map f

let cell_of_table =
  let f table = function
   | []     -> `html (`TABLE table)
   | fattrs -> `html (`FONT (fattrs, `TABLE table))
  in
  cell_map f

let cell_of_html =
  let f html = function
   | []     -> `html html
   | fattrs -> `html (`FONT (fattrs, html))
  in
  cell_map f

let cell_of_label =
  let f label =
    let html = match label with
    | (`escaped s) -> (`text [`string s])
    | (`html h)    -> h
    in function
    | []     -> `html html
    | fattrs -> `html (`FONT (fattrs, html))
  in
  cell_map f

let cell_of_image
  ?align ?valign ?bgcolor ?border ?cellpadding ?cellspacing
  ?fixedsize ?height ?href ?port ?target ?title ?tooltip ?width
  ?colspan ?rowspan ?imagescale
  filename : cell =
   let attributes = ref [] in
   let append f x = append_to_ref attributes f x in
   append (fun x -> `ALIGN x) align;
   append (fun x -> `BGCOLOR x) bgcolor;
   append (fun x -> `BORDER x) border;
   append (fun x -> `CELLPADDING x) cellpadding;
   append (fun x -> `CELLSPACING x) cellspacing;
   append (fun x -> `FIXEDSIZE x) fixedsize;
   append (fun x -> `HEIGHT x) height;
   append (fun x -> `HREF x) href;
   append (fun x -> `PORT x) port;
   append (fun x -> `TARGET x) target;
   append (fun x -> `TITLE x) title;
   append (fun x -> `TOOLTIP x) tooltip;
   append (fun x -> `VALIGN x) valign;
   append (fun x -> `WIDTH x) width;
   append (fun x -> `COLSPAN x) colspan;
   append (fun x -> `ROWSPAN x) rowspan;
   let image_attributes = ref [] in
   let append f x = append_to_ref image_attributes f x in
   append (fun x -> `SCALE x) imagescale;
   append (fun x -> `SRC x)   (Some filename);
   (!attributes, `IMG !image_attributes)

 let label_of_image
  ?align ?valign ?bgcolor ?border ?cellborder ?cellpadding ?cellspacing
  ?fixedsize ?height ?href ?port ?target ?title ?tooltip ?width
  ?imagescale
  filename =
   let cell = cell_of_image
     ?align ?valign ?bgcolor ?border ?cellpadding ?cellspacing
     ?fixedsize ?height ?href ?port ?target ?title ?tooltip ?width
     ?imagescale
     filename
   in
   let table = table ?border ?cellborder [[cell]] in
   `html (html_of_table table)

end (* Html_like_constructors *)

module Html_like_printer = struct

(*  let cat ?(tab="") = List.fold_left (fun s x -> Printf.sprintf "%s\n%s%s" s tab x) "" *)
 let cat ?(sep="\n") ?(tab="") = function
 | [] -> ""
 | y::ys -> List.fold_left (fun s x -> Printf.sprintf "%s%s%s%s" s sep tab x) y ys

 let string_of_color = Common.string_of_color

 let attribute tab = function
  | `ALIGN `CENTER  -> Printf.sprintf "%sALIGN=\"%s\"" tab "CENTER"
  | `ALIGN `LEFT    -> Printf.sprintf "%sALIGN=\"%s\"" tab "LEFT"
  | `ALIGN `RIGHT   -> Printf.sprintf "%sALIGN=\"%s\"" tab "RIGHT"
  | `BGCOLOR color  -> Printf.sprintf "%sBGCOLOR=\"%s\"" tab (string_of_color color)
  | `BORDER x       -> Printf.sprintf "%sBORDER=\"%f\"" tab x
  | `CELLBORDER x   -> Printf.sprintf "%sCELLBORDER=\"%f\"" tab x
  | `CELLPADDING x  -> Printf.sprintf "%sCELLPADDING=\"%f\"" tab x
  | `CELLSPACING x  -> Printf.sprintf "%sCELLSPACING=\"%f\"" tab x
  | `FIXEDSIZE b    -> Printf.sprintf "%sFIXEDSIZE=\"%b\"" tab b
  | `HEIGHT x       -> Printf.sprintf "%sHEIGHT=\"%f\"" tab x
  | `HREF s         -> Printf.sprintf "%sHREF=\"%s\"" tab s
  | `PORT s         -> Printf.sprintf "%sPORT=\"%s\"" tab s
  | `TARGET s       -> Printf.sprintf "%sTARGET=\"%s\"" tab s
  | `TITLE s        -> Printf.sprintf "%sTITLE=\"%s\"" tab s
  | `TOOLTIP s      -> Printf.sprintf "%sTOOLTIP=\"%s\"" tab s
  | `VALIGN `MIDDLE -> Printf.sprintf "%sVALIGN=\"%s\"" tab "MIDDLE"
  | `VALIGN `BOTTOM -> Printf.sprintf "%sVALIGN=\"%s\"" tab "BOTTOM"
  | `VALIGN `TOP    -> Printf.sprintf "%sVALIGN=\"%s\"" tab "TOP"
  | `WIDTH x        -> Printf.sprintf "%sWIDTH=\"%f\"" tab x
  (* font *)
  | `COLOR color    -> Printf.sprintf "%sCOLOR=\"%s\"" tab (string_of_color color)
  | `FACE s         -> Printf.sprintf "%sFACE=\"%s\"" tab s
  | `POINT_SIZE i   -> Printf.sprintf "%sPOINT-SIZE=\"%d\"" tab i
  (* cell *)
  | `COLSPAN i      -> Printf.sprintf "%sCOLSPAN=\"%d\"" tab i
  | `ROWSPAN i      -> Printf.sprintf "%sROWSPAN=\"%d\"" tab i
  (* image *)
  | `SCALE `FALSE   -> Printf.sprintf "%sSCALE=\"%s\"" tab "FALSE"
  | `SCALE `TRUE    -> Printf.sprintf "%sSCALE=\"%s\"" tab "TRUE"
  | `SCALE `WIDTH   -> Printf.sprintf "%sSCALE=\"%s\"" tab "WIDTH"
  | `SCALE `HEIGHT  -> Printf.sprintf "%sSCALE=\"%s\"" tab "HEIGHT"
  | `SCALE `BOTH    -> Printf.sprintf "%sSCALE=\"%s\"" tab "BOTH"
  | `SRC s          -> Printf.sprintf "%sSRC=\"%s\"" tab s

 let rec html_like tab =
  function
  | `text is  -> text is
  | `TABLE tbl -> table tab tbl
  | `FONT html -> font tab html

 and string_or_br =
  function
  | `string s -> StringExtra.expand (function '>' -> Some "&gt;" | '<' -> Some "&lt;" | _ -> None ) s
  | `BR attribute_list ->
      let xs = List.map (attribute "") attribute_list in
      let br_and_attrs = cat ~sep:" " ("<BR"::xs) in
      Printf.sprintf "%s/>" br_and_attrs

 and text string_or_br_list = cat ~sep:"" (List.map string_or_br string_or_br_list)

 and table tab =
  let tab' = tab ^ "  " in
  function
  | (attribute_list, row_list) ->
      let xs = List.map (attribute tab') attribute_list in
      let attrs = cat xs in
      let ys = List.map (row tab') row_list in
      let rows = cat ~tab:tab' ys in
(*       Printf.sprintf "%s<TABLE\n%s%s\n%s>\n%s\n%s</TABLE>" tab tab' attrs tab rows tab *)
      Printf.sprintf "\n%s<TABLE %s >\n%s\n%s</TABLE>" tab attrs rows tab

 and row tab =
  let tab' = tab ^ "  " in
  function cell_list ->
      let xs = List.map (cell tab') cell_list in
      let cells = cat ~tab:tab' xs in
      Printf.sprintf "%s<TR>\n%s\n%s</TR>" tab cells tab

 and cell_content tab = function
  | `html h -> html_like tab h
  (* In the case of an image, dot doesn't accept spaces among <TD> and <IMG>!!!*)
  | `IMG img -> image img

 and cell tab =
  let tab' = tab ^ "  " in
  function
  | (cell_attribute_list, html_or_image) ->
      let xs = List.map (attribute tab') cell_attribute_list in
      let attrs = cat ~tab:tab' xs in
      let content = cell_content tab' html_or_image in
      Printf.sprintf "%s<TD %s>%s</TD>" tab attrs content

 and font tab =
  let tab' = tab ^ "  " in
  function
  | (attribute_list, content) ->
      let xs = List.map (attribute "") attribute_list in
      let attrs = cat ~sep:" " ~tab:"" xs in
      let content = html_like tab' content in
      Printf.sprintf "<FONT %s>%s</FONT>" attrs content

 and image attribute_list =
      let xs = List.map (attribute "") attribute_list in
      let attrs = cat xs in
      Printf.sprintf "<IMG %s/>" attrs

end

module String_of = struct

  let size = function
   | `force (x,y) -> Printf.sprintf "size=\"%f,%f!\"" x y
   | `max   (x,y) -> Printf.sprintf "size=\"%f,%f\""  x y

  let page (x,y) = Printf.sprintf "page=\"%f,%f\"" x y

  let pagedir = function
   | `BL -> "pagedir=BL"
   | `BR -> "pagedir=BR"
   | `LB -> "pagedir=LB"
   | `LT -> "pagedir=LT"
   | `RB -> "pagedir=RB"
   | `RT -> "pagedir=RT"
   | `TL -> "pagedir=TL"
   | `TR -> "pagedir=TR"

  let rotate = Printf.sprintf "rotate=\"%f\""

  let ratio = function
   | `auto     -> "ratio=\"auto\""
   | `compress -> "ratio=\"compress\""
   | `fill     -> "ratio=\"fill\""
   | `float x  -> Printf.sprintf "ratio=\"%f\"" x

  let margin (x,y) = Printf.sprintf "margin=\"%f,%f\"" x y
  let pos (x,y)    = Printf.sprintf "pos=\"%f,%f\"" x y

  let center () = "center=\"1\""

  let nodesep = Printf.sprintf "nodesep=\"%f\""

  let ordering = function
   | `inp -> "ordering=\"in\""
   | `out -> "ordering=\"out\""

  let outputorder = function
   | `breadthfirst -> "outputorder=\"breadthfirst\""
   | `edgesfirst   -> "outputorder=\"edgesfirst\""
   | `nodesfirst   -> "outputorder=\"nodesfirst\""

  let rank = function
   | `max    -> "rank=\"max\""
   | `min    -> "rank=\"min\""
   | `same   -> "rank=\"same\""
   | `sink   -> "rank=\"sink\""
   | `source -> "rank=\"source\""

 let rankdir = function
  | `TB -> "rankdir=\"TB\""
  | `BT -> "rankdir=\"BT\""
  | `LR -> "rankdir=\"LR\""
  | `RL -> "rankdir=\"RL\""

 let ranksep = Printf.sprintf "ranksep=\"%f\""

 let clusterrank = function
  | `global -> "clusterrank=\"global\""
  | `local  -> "clusterrank=\"local\""
  | `none   -> "clusterrank=\"none\""

 let nslimit = Printf.sprintf "nslimit=\"%f\""

 let layers xs =
  let ys = List.fold_left (fun s x -> s^":"^x) "" xs in
  Printf.sprintf "layers=\"%s\"" ys

 let string_of_color = Common.string_of_color

 let color   x = Printf.sprintf "color=\"%s\""   (string_of_color x)
 let bgcolor x = Printf.sprintf "bgcolor=\"%s\"" (string_of_color x)

 let href = Printf.sprintf "href=\"%s\""
 let url  = Printf.sprintf "url=\"%s\""
 let stylesheet = Printf.sprintf "stylesheet=\"%s\""
 let charset = Printf.sprintf "charset=\"%s\""
 let comment = Printf.sprintf "comment=\"%s\""
 let compound () = "compound=\"true\""
 let concentrate () = "concentrate=\"true\""
 let regular () = "regular=\"true\""

 let fontcolor x = Printf.sprintf "fontcolor=\"%s\"" (string_of_color x)
 let fillcolor x = Printf.sprintf "fillcolor=\"%s\"" (string_of_color x)
 let pencolor  x = Printf.sprintf "pencolor=\"%s\""  (string_of_color x)
 let labelfontcolor x = Printf.sprintf "labelfontcolor=\"%s\""  (string_of_color x)

 let fontname = Printf.sprintf "fontname=\"%s\""
 let labelfontname = Printf.sprintf "labelfontname=\"%s\""

 let fontpath xs =
  let ys = List.fold_left (fun s x -> s^":"^x) "" xs in
  Printf.sprintf "fontpath=\"%s\"" ys

 let fontsize = Printf.sprintf "fontsize=\"%d\""
 let labelfontsize = Printf.sprintf "labelfontsize=\"%d\""

 let string_of_html_like (html :html_like) = Html_like_printer.html_like "" html

 let gen_label label = function
  | `escaped x -> Printf.sprintf "%s=\"%s\"" label x
  | `html h    -> Printf.sprintf "%s=<%s>" label (string_of_html_like h)

 let label = gen_label "label"
 let headlabel = gen_label "headlabel"
 let taillabel = gen_label "taillabel"

 let labeljust = function
  | `c -> "labeljust=\"c\""
  | `l -> "labeljust=\"l\""
  | `r -> "labeljust=\"r\""

 let labelloc = function
  | `b -> "labelloc=\"b\""
  | `t -> "labelloc=\"t\""

 let nojustify () = "nojustify=\"true\""
 let fixedsize () = "fixedsize=\"true\""
 let constraint_off () = "constraint=\"false\""
 let decorate () = "decorate=\"true\""
 let labelfloat () = "labelfloat=\"true\""

 let peripheries = Printf.sprintf "peripheries=\"%d\""

 let quantum = Printf.sprintf "quantum=\"%f\""
 let remincross () = "remincross=\"true\""
 let samplepoints = Printf.sprintf "samplepoints=\"%d\""
 let distortion = Printf.sprintf "distortion=\"%f\""
 let group = Printf.sprintf "group=\"%s\""
 let height = Printf.sprintf "height=\"%f\""
 let orientation = Printf.sprintf "orientation=\"%f\""
 let width = Printf.sprintf "width=\"%f\""
 let headclip = Printf.sprintf "headclip=\"%b\""
 let tailclip = Printf.sprintf "tailclip=\"%b\""

 let string_of_style = function
  | `bold      -> "bold"
  | `dashed    -> "dashed"
  | `diagonals -> "diagonals"
  | `dotted    -> "dotted"
  | `filled    -> "filled"
  | `invis     -> "invis"
  | `rounded   -> "rounded"
  | `solid     -> "solid"

 let style xs =
  let ys = List.map string_of_style xs in
  let zs = List.fold_left (fun s x -> s^","^x) "" ys in
  Printf.sprintf "style=\"%s\"" zs

 let layer xs =
  let ys = List.fold_left (fun s x -> s^":"^x) "" xs in
  Printf.sprintf "layer=\"%s\"" ys

 let string_of_shape = function
  | `Mcircle -> "Mcircle"
  | `Mdiamond -> "Mdiamond"
  | `Msquare -> "Msquare"
  | `box -> "box"
  | `circle -> "circle"
  | `diamond -> "diamond"
  | `doublecircle -> "doublecircle"
  | `doubleoctagon -> "doubleoctagon"
  | `egg -> "egg"
  | `ellipse -> "ellipse"
  | `hexagon -> "hexagon"
  | `house -> "house"
  | `invhouse -> "invhouse"
  | `invtrapezium -> "invtrapezium"
  | `invtriangle -> "invtriangle"
  | `none -> "none"
  | `octagon -> "octagon"
  | `parallelogram -> "parallelogram"
  | `pentagon -> "pentagon"
  | `plaintext -> "plaintext"
  | `point -> "point"
  | `rect -> "rect"
  | `rectangle -> "rectangle"
  | `septagon -> "septagon"
  | `trapezium -> "trapezium"
  | `triangle -> "triangle"
  | `tripleoctagon -> "tripleoctagon"
  (* Managed outside: *)
  | `polygon (sides,skew) -> assert false
  | `epsf filename        -> assert false

 let shape = function
  | `polygon (sides,skew) -> Printf.sprintf "shape=\"polygon\", sides=\"%d\", skew=\"%d\"" sides skew
  | `epsf filename        -> Printf.sprintf "shape=\"epsf\", shapefile=\"%s\"" filename
  | x -> Printf.sprintf "shape=\"%s\"" (string_of_shape x)

 (* For node (dot-undocumented) option "image=filename" *)
 let image = Printf.sprintf "image=\"%s\""

 let string_of_arrow_type = function
  | `Open -> "open"
  | `box -> "box"
  | `crow -> "crow"
  | `diamond -> "diamond"
  | `dot -> "dot"
  | `ediamond -> "ediamond"
  | `empty -> "empty"
  | `halfopen -> "halfopen"
  | `inv -> "inv"
  | `invdot -> "invdot"
  | `invempty -> "invempty"
  | `invodot -> "invodot"
  | `none -> "none"
  | `normal -> "normal"
  | `obox -> "obox"
  | `odiamond -> "odiamond"
  | `odot -> "odot"
  | `tee -> "tee"
  | `vee -> "vee"

 let arrowhead x = Printf.sprintf "arrowhead=\"%s\"" (string_of_arrow_type x)
 let arrowtail x = Printf.sprintf "arrowtail=\"%s\"" (string_of_arrow_type x)

 let string_of_dir= function
  | `back -> "back"
  | `both -> "both"
  | `forward -> "forward"
  | `none -> "none"
 let dir x = Printf.sprintf "dir=\"%s\"" (string_of_dir x)

 let arrowsize = Printf.sprintf "arrowsize=\"%f\""
 let labelangle = Printf.sprintf "labelangle=\"%f\""
 let labeldistance = Printf.sprintf "labeldistance=\"%f\""

 let string_of_compass_point = function
  | `e -> "e"
  | `n -> "n"
  | `ne -> "ne"
  | `nw -> "nw"
  | `s -> "s"
  | `se -> "se"
  | `sw -> "sw"
  | `w -> "w"

 let head_or_tail_port label = function
  | ident, None      -> Printf.sprintf "%s=\"%s\"" label ident
  | ident, (Some cp) -> Printf.sprintf "%s=\"%s:%s\"" label ident (string_of_compass_point cp)

 let headport = head_or_tail_port "headport"
 let tailport = head_or_tail_port "tailport"

 let lhead = Printf.sprintf "lhead=\"%s\""
 let ltail = Printf.sprintf "ltail=\"%s\""
 let minlen = Printf.sprintf "minlen=\"%d\""
 let samehead = Printf.sprintf "samehead=\"%s\""
 let sametail = Printf.sprintf "sametail=\"%s\""
 let weight = Printf.sprintf "weight=\"%f\""
 let z = Printf.sprintf "z=\"%f\""

end


let append options injection conv opt =
 match opt with
 | None -> ()
 | Some x -> (options := (injection (conv x))::!options)

module Extract = struct
 let unit = function None -> false | Some () -> true
 let bool ?(default=false) = function None -> default | Some b -> b

 let ident ?(prefix="id") =
  let counter = ref 0 in
  function
  | None -> let result = Printf.sprintf "%s%d" prefix !counter in ((incr counter); result)
  | Some id -> id

end (* Extract *)

let map_graph_options f
  ?strict ?digraph ?name ?size ?page ?pagedir ?rotate ?ratio ?margin ?center ?nodesep
  ?ordering ?outputorder ?rank ?rankdir ?ranksep ?clusterrank ?nslimit ?layers ?color
  ?bgcolor ?href ?url ?stylesheet ?charset ?comment ?compound ?concentrate ?fontcolor ?fontname
  ?fontpath ?fontsize ?label ?labeljust ?labelloc ?nojustify ?quantum ?remincross ?samplepoints
  statement_list =

  let strict  = Extract.unit strict  in
  let digraph = Extract.bool ~default:true digraph in
  let name    = Extract.ident ~prefix:"graph_" name in

  (** Create the container of options: *)
  let graph_options = ref [] in
  let append f x = append graph_options (fun e-> Graph_default e) f x in

  append (String_of.size) size;
  append (String_of.page) page;
  append (String_of.pagedir) pagedir;
  append (String_of.rotate) rotate;
  append (String_of.ratio) ratio;
  append (String_of.margin) margin;
  append (String_of.center) center;
  append (String_of.nodesep) nodesep;
  append (String_of.ordering) ordering;
  append (String_of.outputorder) outputorder;
  append (String_of.rank) rank;
  append (String_of.rankdir) rankdir;
  append (String_of.ranksep) ranksep;
  append (String_of.clusterrank) clusterrank;
  append (String_of.nslimit) nslimit;
  append (String_of.layers) layers;
  append (String_of.color) color;
  append (String_of.bgcolor) bgcolor;
  append (String_of.href) href;
  append (String_of.url) url;
  append (String_of.stylesheet) stylesheet;
  append (String_of.charset) charset;
  append (String_of.comment) comment;
  append (String_of.compound) compound;
  append (String_of.concentrate) concentrate;
  append (String_of.fontcolor) fontcolor;
  append (String_of.fontname) fontname;
  append (String_of.fontpath) fontpath;
  append (String_of.fontsize) fontsize;
  append (String_of.label) label;
  append (String_of.labeljust) labeljust;
  append (String_of.labelloc) labelloc;
  append (String_of.nojustify) nojustify;
  append (String_of.quantum) quantum;
  append (String_of.remincross) remincross;
  append (String_of.samplepoints) samplepoints;
  f strict digraph name statement_list graph_options

let graph =
 let f strict digraph name statement_list graph_options =
    { strict = strict; digraph = digraph; name=name;
      statements = List.append !graph_options statement_list; }
 in map_graph_options f

let graph_default =
 let map_graph_options_call =
   let f strict digraph name statement_list graph_options =
     Graph_defaults (List.map (function Graph_default x -> x | _ -> assert false) !graph_options)
    in map_graph_options f
 in
 map_graph_options_call ?strict:None ?digraph:None ?name:None


let subgraph ?name ?rank statement_list =
  let name    = Extract.ident ~prefix:"subgraph_" name in
  let statements = ref statement_list in
  let append f x = append statements (fun e-> Graph_default e) f x in
  append (String_of.rank) rank;
  Subgraph (name, !statements)


let cluster
  ?name_suffix ?rank ?color ?bgcolor ?fillcolor ?pencolor ?fontcolor ?fontname ?fontsize
  ?label ?labeljust ?labelloc ?nojustify ?url ?peripheries ?style
  statement_list =
  let name    = "cluster_"^(Extract.ident name_suffix) in
  let statements = ref statement_list in
  let append f x = append statements (fun e-> Graph_default e) f x in
  append (String_of.rank) rank;
  append (String_of.color) color;
  append (String_of.bgcolor) bgcolor;
  append (String_of.fillcolor) fillcolor;
  append (String_of.pencolor) pencolor;
  append (String_of.fontcolor) fontcolor;
  append (String_of.fontname) fontname;
  append (String_of.fontsize) fontsize;
  append (String_of.label) label;
  append (String_of.labeljust) labeljust;
  append (String_of.labelloc) labelloc;
  append (String_of.nojustify) nojustify;
  append (String_of.url) url;
  append (String_of.peripheries) peripheries;
  append (String_of.style) style;
  Subgraph (name, !statements)


let map_edge_options f
  ?url ?color ?comment ?arrowhead ?arrowtail ?dir ?arrowsize ?constraint_off ?decorate
  ?fontcolor ?fontname ?fontsize ?headclip ?headlabel ?headport ?tailclip ?taillabel ?tailport
  ?label ?labelangle ?labeldistance ?labelfloat ?labelfontcolor ?labelfontname ?labelfontsize
  ?layer ?lhead ?ltail ?minlen ?nojustify ?pos ?samehead ?sametail ?style ?weight
  alpha =

  let edge_options = ref [] in
  let append f x = append edge_options (fun e->e) f x in
  append (String_of.url) url;
  append (String_of.color) color;
  append (String_of.comment) comment;
  append (String_of.arrowhead) arrowhead;
  append (String_of.arrowtail) arrowtail;
  append (String_of.dir) dir;
  append (String_of.arrowsize) arrowsize;
  append (String_of.constraint_off) constraint_off;
  append (String_of.decorate) decorate;
  append (String_of.fontcolor) fontcolor;
  append (String_of.fontname) fontname;
  append (String_of.fontsize) fontsize;
  append (String_of.headclip) headclip;
  append (String_of.headlabel) headlabel;
  append (String_of.headport) headport;
  append (String_of.tailclip) tailclip;
  append (String_of.taillabel) taillabel;
  append (String_of.tailport) tailport;
  append (String_of.label) label;
  append (String_of.labelangle) labelangle;
  append (String_of.labeldistance) labeldistance;
  append (String_of.labelfloat) labelfloat;
  append (String_of.labelfontcolor) labelfontcolor;
  append (String_of.labelfontname) labelfontname;
  append (String_of.labelfontsize) labelfontsize;
  append (String_of.layer) layer;
  append (String_of.lhead) lhead;
  append (String_of.ltail) ltail;
  append (String_of.minlen) minlen;
  append (String_of.nojustify) nojustify;
  append (String_of.pos) pos;
  append (String_of.samehead) samehead;
  append (String_of.sametail) sametail;
  append (String_of.style) style;
  append (String_of.weight) weight;
  f alpha edge_options

let edge =
 let f = fun node_ident_head edge_options node_ident_tail -> Edge (node_ident_head, node_ident_tail, !edge_options) in
 map_edge_options f

let edge_default =
 let f _ edge_options =  (Edge_defaults !edge_options) in
 map_edge_options f


let map_node_options f
  ?url ?color ?comment ?distortion ?fillcolor ?fontcolor ?fontname ?fontsize ?fixedsize ?group ?height
  ?layer ?margin ?nojustify ?orientation ?peripheries ?pos ?regular ?shape ?image ?label ?style ?width ?z
  node_ident =

  let node_options = ref [] in
  let append f x = append node_options (fun e->e) f x in
  append (String_of.url) url;
  append (String_of.color) color;
  append (String_of.comment) comment;
  append (String_of.distortion) distortion;
  append (String_of.fillcolor) fillcolor;
  append (String_of.fontcolor) fontcolor;
  append (String_of.fontname) fontname;
  append (String_of.fontsize) fontsize;
  append (String_of.fixedsize) fixedsize;
  append (String_of.group) group;
  append (String_of.height) height;
  append (String_of.layer) layer;
  append (String_of.margin) margin;
  append (String_of.nojustify) nojustify;
  append (String_of.orientation) orientation;
  append (String_of.peripheries) peripheries;
  append (String_of.pos) pos;
  append (String_of.regular) regular;
  append (String_of.shape) shape;
  append (String_of.image) image;
  append (String_of.label) label;
  append (String_of.style) style;
  append (String_of.width) width;
  append (String_of.z) z;

  f node_ident node_options

let node =
 let f = fun node_ident node_options -> Node (node_ident, !node_options) in
 map_node_options f

let node_default =
  let f _ node_options = (Node_defaults !node_options) in
  map_node_options f

let phantom_fresh_name = Counter.make_string_generator ~prefix:"_phantom_" ()

(* shorthand *)
module Html = Html_like_constructors

(* Node redefinition, in order to manage the pseudo-option "outlabel" *)
let node
  ?url ?color ?comment ?distortion ?fillcolor ?fontcolor ?fontname ?fontsize ?fixedsize ?group ?height
  ?layer ?margin ?nojustify ?orientation ?peripheries ?pos ?regular ?shape ?image ?label ?style ?width ?z
  ?outlabel
  node_ident =
  let super = node in (* The redefined function *)
  match outlabel with
  | None ->
     super
       ?url ?color ?comment ?distortion ?fillcolor ?fontcolor ?fontname ?fontsize ?fixedsize ?group ?height
       ?layer ?margin ?nojustify ?orientation ?peripheries ?pos ?regular ?shape ?image ?label ?style ?width ?z
       node_ident
  | Some outlabel ->
      let wrapped_label =
         (match label with
         | None       -> (`escaped node_ident)
         | Some label -> label
         )
      in
      let label =
        let table_content = match outlabel with
        | `north label ->
            let l = Html.cell_of_label ~valign:`BOTTOM label in
            let n = Html.cell_of_label ~valign:`TOP    wrapped_label in
            [[l];[n]]
        | `south label ->
            let l = Html.cell_of_label ~valign:`TOP    label in
            let n = Html.cell_of_label ~valign:`BOTTOM wrapped_label in
            [[n];[l]]
        | `east label  ->
            let l = Html.cell_of_label ~align:`LEFT  label in
            let n = Html.cell_of_label ~align:`RIGHT wrapped_label in
            [[n;l]]
        | `west label  ->
            let l = Html.cell_of_label ~align:`RIGHT label in
            let n = Html.cell_of_label ~align:`LEFT  wrapped_label in
            [[l;n]]
        in
        Html.label_of_table
          (Html.table
	      ~align:`CENTER
	      ~border:0.
	      ~cellborder:0.
	      ~cellspacing:0.
              table_content)
      in
      super
        ?url ?color ?comment ?distortion ?fillcolor ?fontcolor ?fontname ?fontsize ?fixedsize ?group ?height
        ?layer ?margin ?nojustify ?orientation ?peripheries ?pos ?regular ?shape ?image ~label ?style ?width ?z
        node_ident


let graph_of_list nns =
 let sl = List.map (function (n1,n2) -> edge n1 n2) nns in
 graph sl

include Html_like_constructors

let working_output_formats ?no_file_inspection () =
  let g = (graph [node "good_luck"]) in
  let dotfile = Filename.temp_file "Dot.make_image." ".dot" in
  let imgfile = Filename.temp_file "Dot.make_image." ".img" in
  let mill imgtype =
    try
      let _ = make_image ~silent:() ~imgtype ~dotfile ~imgfile g in
      let file_output =
        match no_file_inspection with
        | Some () -> ""
        | None ->
           let cmd = Printf.sprintf "file -b -z %s" imgfile in
           StringExtra.rstrip (UnixExtra.shell cmd)
      in
      Some (imgtype, (string_of_output_format imgtype), (output_format_description imgtype), file_output)
    with _ -> None
  in
  let result = ListExtra.filter_map mill admissible_output_formats in
  let () = List.iter Unix.unlink [dotfile; imgfile] in
  result

(** Redefined with a cache: *)
let working_output_formats =
 let cache1 = ref None in
 let cache2 = ref None in
 fun ?no_file_inspection () ->
   let run_with_cache cache =
     match !cache with
     | None ->
	 let result = working_output_formats ?no_file_inspection () in
	 cache := Some result;
	 result
     | Some result -> result
   in
   match no_file_inspection with
   | None    -> run_with_cache cache1
   | Some () -> run_with_cache cache2

let working_output_formats_as_objects ?no_file_inspection () =
 List.map
   (fun (x,y,z,t) ->
      object
        method output_format = x
        method output_format_as_string = y
        method description = z
        method file_command_output = t
      end)
   (working_output_formats ?no_file_inspection ())
