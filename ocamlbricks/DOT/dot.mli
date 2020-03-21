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

(** Simplified interface (forgetting options):

{[
val graph    : ?... -> statement list -> graph
val subgraph : ?... -> statement list -> statement
val cluster  : ?... -> statement list -> statement
val node     : ?... -> node_ident -> statement
val edge     : ?... -> node_ident -> node_ident -> statement

val graph_default :  ?... -> unit -> statement
val node_default  :  ?... -> unit -> statement
val edge_default  :  ?... -> unit -> statement

val label_of_text  : ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> text  -> [ `html of html_like ]
val label_of_table : ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> table -> [ `html of html_like ]
val html_of_text   : ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> text  -> html_like
val html_of_table  : ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> table -> html_like

val text_of_string : ?br:unit -> ?align:[ `CENTER | `LEFT | `RIGHT ] -> string -> text
val text_concat    : text list -> text
val table          : ?... -> row list -> table
val cell_of_text   : ?... -> text -> cell
val cell_of_table  : ?... -> table -> cell
val cell_of_image  : ?... -> filename -> cell

val  print : graph -> unit
val fprint : filename -> graph -> unit
val sprint : graph -> string
]}
*)

type graph
type statement

type color = [ `RGB of int * int * int | `HSV of float*float*float | `name of string ]
type filename = string
type ident = string
type layer_ident = string
type point_ident = string
type port_ident = string
type node_ident = string
type cluster_ident = string

type escaped_string = string
   (* string allowing escape sequences which are replaced according to the context. For node attributes,
      the substring "\N" is replaced by the name of the node, and the substring "\G" by the name of the graph.
      For graph or cluster attributes, the substring "\G" is replaced by the name of the graph or cluster.
      For edge attributes, the substring "\N" is replaced by the name of the edge, and the substrings "\T"
      and "\H" by the names of the tail and head nodes, respectively. The name of an edge is the string formed
      from the name of the tail node, the appropriate edge operator ("--" or "->") and the name of the head node.
      In addition, if the associated attribute is label, headlabel or taillabel, the escape sequences "\n", "\l" and "\r"
      divide the label into lines, centered, left-justified, and right-justified, respectively. *)

(* See http://www.graphviz.org/pub/scm/graphviz2/doc/info/shapes.html#html *)
type html_like = [ `text of text | `TABLE of table | `FONT of font ]
 and text = item list
 and item = [ `string of string | `BR of br_attribute list ]
 and table = table_attribute list * row list
 and table_attribute =
  [ `ALIGN of [`CENTER|`LEFT|`RIGHT]
  | `BGCOLOR of color
  | `BORDER of float
  | `CELLBORDER of float
  | `CELLPADDING of float
  | `CELLSPACING of float
  | `FIXEDSIZE of bool
  | `HEIGHT of float
  | `HREF of string
  | `PORT of string
  | `TARGET of string
  | `TITLE of string
  | `TOOLTIP of string
  | `VALIGN of [ `MIDDLE|`BOTTOM|`TOP ]
  | `WIDTH of float
  ]
 and font = font_attribute list * html_like
 and font_attribute =
  [ `COLOR of color
  | `FACE of string
  | `POINT_SIZE of int
  ]
 and br_attribute =
  [ `ALIGN of [`CENTER|`LEFT|`RIGHT]
  ]
 and row   = cell list
 and cell  = cell_attribute list * [ `html of html_like | `IMG of image ]
 and cell_attribute =
  [ `ALIGN of [`CENTER|`LEFT|`RIGHT]
  | `BGCOLOR of color
  | `BORDER of float
  | `CELLPADDING of float
  | `CELLSPACING of float
  | `FIXEDSIZE of bool
  | `HEIGHT of float
  | `HREF of string
  | `PORT of string
  | `TARGET of string
  | `TITLE of string
  | `TOOLTIP of string
  | `VALIGN of [ `MIDDLE|`BOTTOM|`TOP ]
  | `WIDTH of float
  (* cell specific: *)
  | `COLSPAN of int
  | `ROWSPAN of int
 ]
 and image = image_attribute list
 and image_attribute =
  [ `SCALE of [`FALSE|`TRUE|`WIDTH|`HEIGHT|`BOTH]
  | `SRC of filename
  ]

type label = [ `escaped of escaped_string | `html of html_like ]

(** Graph constructor. *)
val graph:

 ?strict:unit -> (* If  the  graph is strict then multiple edges are not allowed between the same pairs of nodes. *)

 ?digraph:bool ->
    (* If it is a directed graph, indicated by digraph,  then  the  edgeop  must  be "->".
       If it is an undirected graph then the edgeop must be "--".  *)

 ?name:ident ->

 ?size:[ `max of (float*float) | `force of (float*float) ] ->
   (* size="x,y" sets bounding box of drawing in inches.
      Maximum width and height of drawing, in inches. If defined and the drawing is too large, the drawing is uniformly scaled down so
      that it fits within the given size.
      If size ends in an exclamation point (!), then it is taken to be the desired size. In this case, if both dimensions of the
      drawing are less than size, the drawing is scaled up uniformly until at least one dimension equals its dimension in size.
      Note that there is some interaction between the size and ratio attributes. *)

 ?page:(float*float) ->
    (* page="x,y" sets the PostScript pagination unit.
       Width and height of output pages, in inches. If this is set and is smaller than the size of the layout, a rectangular array
       of pages of the specified page size is overlaid on the layout, with origins aligned in the lower-left corner, thereby
       partitioning the layout into pages. The pages are then produced one at a time, in pagedir order. *)

 ?pagedir: [ `BL | `BR | `TL | `TR | `RB | `RT | `LB | `LT ] ->
    (* pagedir "BL", "BR", "TL", "TR", "RB", "RT", "LB", "LT" specify the 8 row or column major orders for traversing
       a rectangular array, the first character corresponding to the major order and the second to the minor order. Thus, for "BL",
       the major order is from bottom to top, and the minor order is from left to right. This means the bottom row is traversed
       first, from left to right, then the next row up, from left to right, and so on, until the topmost row is traversed. *)

 ?rotate:float -> (* rotate=90  sets  landscape  mode. *)

 ?ratio:[ `float of float | `fill | `compress | `auto ] ->
    (* ratio=f sets the aspect ratio (drawing height/drawing width) for the drawing.
       Note that this is adjusted before the size attribute constraints are enforced.
       - If ratio is numeric, it is taken as the desired aspect ratio. Then, if the actual aspect ratio is less than
       the desired ratio, the drawing height is scaled up to achieve the desired ratio; if the actual ratio is greater
       than that desired ratio, the drawing width is scaled up.
       - If ratio = "fill" and the size attribute is set, node positions are scaled, separately in both x and y, so that
       the final drawing exactly fills the specified size.
       - If ratio = "compress" and the size attribute is set, dot attempts to compress the initial layout to fit in the given size.
       This achieves a tighter packing of nodes but reduces the balance and symmetry. This feature only works in dot.
       - If ratio = "expand", the size attribute is set, and both the width and the height of the graph are less than the value in size,
       node positions are scaled uniformly until at least one dimension fits size exactly. Note that this is distinct from using size as
       the desired size, as here the drawing is expanded before edges are generated and all node and text sizes remain unchanged.
       - If ratio = "auto", the page attribute is set and the graph cannot be drawn on a single page, then size is set to an ``ideal'' value.
       In particular, the size in a given dimension will be the smallest integral multiple of the page size in that dimension which is at
       least half the current size. The two dimensions are then scaled independently to the new size. This feature only works in dot. *)

 ?margin:(float*float) -> (* For graphs, this sets x and y margins of canvas, in inches. *)
 ?center:unit -> (* If true, the drawing is centered in the output canvas. *)

 ?nodesep:float -> (* nodesep=f set the minimum space between two adjacent nodes in the same rank, in inches. Default 0.25, minimum 0.02 *)

 ?ordering:[ `inp | `out ] ->
    (* If "out" for a graph G, and n is a node in G, then edges n->* appear left-to-right in the
       same order in which they are defined. If "in", the edges *->n appear left-to-right in the
       same order in which they are defined for all nodes n. *)

 ?outputorder: [ `breadthfirst | `nodesfirst | `edgesfirst ] ->
    (* Specify order in which nodes and edges are drawn. "breadthfirst","nodesfirst","edgesfirst" specify the order in which nodes
       and edges are drawn in concrete output. The default "breadthfirst" is the simplest, but when the graph layout does not avoid
       edge-node overlap, this mode will sometimes have edges drawn over nodes and sometimes on top of nodes. If the mode "nodesfirst"
       is chosen, all nodes are drawn first, followed by the edges. This guarantees an edge-node overlap will not be mistaken for an
       edge ending at a node. On the other hand, usually for aesthetic reasons, it may be desirable that all edges appear beneath nodes,
       even if the resulting drawing is ambiguous. This can be achieved by choosing "edgesfirst". *)

 ?rank: [ `same | `min | `max | `source | `sink ] ->
    (* rank=.. Rank constraints on the nodes in a subgraph. If rank="same", all nodes are placed on the same rank.
       If rank="min", all nodes are placed on the minimum rank. If rank="source", all nodes are placed on the minimum
       rank, and the only nodes on the minimum rank belong to some subgraph whose rank attribute is "source" or "min".
       Analogous criteria hold for rank="max" and rank="sink". (Note: the minimum rank is topmost or leftmost, and the
       maximum rank is bottommost or rightmost.) *)

 ?rankdir: [`TB|`LR|`RL|`BT] -> (* rankdir=LR|RL|BT requests a left‐to‐right, right‐to‐left, or bottom‐to‐top, drawing. *)
 ?ranksep:float -> (* ranksep=f sets the minimum separation between ranks. Default 0.5. *)

 ?clusterrank:[ `local | `global | `none ] ->
    (* Mode used for handling clusters. If clusterrank is "local", a subgraph whose name begins with "cluster" is given
       special treatment. The subgraph is laid out separately, and then integrated as a unit into its parent graph, with
       a bounding rectangle drawn about it. If the cluster has a label parameter, this label is displayed within the rectangle.
       Note also that there can be clusters within clusters. At present, the modes "global" and "none" appear to be identical,
       both turning off the special cluster processing. *)

 ?nslimit:float -> (* nslimit=f adjusts the bound on the number of network simplex or min‐cross  iterations  by  the  given  ratio. *)

 ?layers:layer_ident list -> (* graph layers declarations. See http://www.graphviz.org/Documentation/html/layers/ *)

 ?color:color ->
    (*  color=colorvalue sets foreground color. This is the basic drawing color for graphics, not text.
        For the latter, use the fontcolor attribute. For edges, the value can either be a single color or a colorList.
        In the latter case, the edge is drawn using parallel splines or lines, one for each color in the list, in the order given. *)

 ?bgcolor:color ->
   (*  bgcolor=colorvalue sets background color.
       When attached to the root graph, this color is used as the background for entire canvas. When a cluster attribute, it is used as
       the initial background for the cluster. If a cluster has a filled style, the cluster's fillcolor will overlay the background color.
       If no background color is specified for the root graph, no graphics operation are performed on the background. This works fine for
       PostScript but for bitmap output, all bits are initialized to something. This means that when the bitmap output is included in some
       other document, all of the bits within the bitmap's bounding box will be set, overwriting whatever color or graphics where already
       on the page. If this effect is not desired, and you only want to set bits explicitly assigned in drawing the graph, set background="transparent". *)

 ?href:string ->
    (* href="url" the default url for image map files; in PostScript files, the base URL
       for all relative URLs, as recognized by Acrobat Distiller 3.0 and up. *)

 ?url:escaped_string ->
    (* Hyperlinks incorporated into device-dependent output. At present, used in ps2, cmap, i*map and svg formats. For all these formats,
       URLs can be attached to nodes, edges and clusters. URL attributes can also be attached to the root graph in ps2, cmap and i*map formats.
       This serves as the base URL for relative URLs in the former, and as the default image map file in the latter.
       The active area for a node or cluster is its bounding box. For edges, the active areas are small circles where the edge contacts its head and tail nodes.
       These areas may overlap the related node, and the edge URL dominates. If the edge has a label, this will also be active. Finally, if the edge has a head
       or tail label, this will also be active. Note, however, that if the edge has a headURL attribute, it is this value that is used near the head node and on
       the head label, if defined. The similar restriction holds when tailURL is defined.
       The URL of the root graph is only treated as an escString if the output format is cmap. *)

 ?stylesheet:string ->
    (* stylesheet="file.css" includes a reference to a stylesheet in -Tsvg and -Tsvgz
       outputs. Ignored by other formats. *)

 ?charset:string ->
    (* Specifies the character encoding used when interpreting string input as a text label. The default value is "UTF-8".
       The other legal value is "iso-8859-1" or, equivalently, "Latin1". The charset attribute is case-insensitive.
       Note that if the character encoding used in the input does not match the charset value, the resulting output may be very strange. *)

 ?comment: string   -> (* Comments are inserted into output. Device-dependent *)
 ?compound: unit    -> (* If true, allow edges between clusters. (See lhead and ltail). *)
 ?concentrate: unit -> (* If true, use edge concentrators. *)

 ?fontcolor: color  -> (* Color used for text. *)

 ?fontname:string   ->
    (* Font used for text. This very much depends on the output format and, for non-bitmap output such as PostScript or SVG,
       the availability of the font when the graph is displayed or printed. As such, it is best to rely on font faces that
       are generally available, such as Times-Roman, Helvetica or Courier. *)

 ?fontpath:string list ->
    (* Directory list used by libgd to search for bitmap fonts if Graphviz was not built with the fontconfig library.
       If fontpath is not set, the environment variable DOTFONTPATH is checked. If that is not set, GDFONTPATH is checked.
       If not set, libgd uses its compiled-in font path. Note that fontpath is an attribute of the root graph. *)

 ?fontsize:int -> (* Font size, in points, used for text. Default is 14.0, minimum is 1.0 *)

 ?label: label -> (* Text label attached to objects. *)

 ?labeljust: [ `r | `l | `c ] ->
    (* Justification for cluster labels. If "r", the label is right-justified within bounding rectangle; if "l", left-justified;
       else the label is centered. Note that a subgraph inherits attributes from its parent. Thus, if the root graph sets
       labeljust to "l", the subgraph inherits this value. *)

 ?labelloc: [ `t | `b ] ->
    (* Top/bottom placement of graph and cluster labels. If the attribute is "t", place label at the top; if the attribute is "b",
       place label at the bottom. By default, root graph labels go on the bottom and cluster labels go on the top. Note that a
       subgraph inherits attributes from its parent. Thus, if the root graph sets labelloc to "b", the subgraph inherits this value.
       Default is "b" for root graphs. *)

 ?nojustify:unit ->
    (* By default, the justification of multi-line labels is done within the largest context that makes sense. Thus, in the label of a
       polygonal node, a left-justified line will align with the left side of the node (shifted by the prescribed margin).
       In record nodes, left-justified line will line up with the left side of the enclosing column of fields.
       If nojustify is "true", multi-line labels will be justified in the context of itself. For example, if the attribute is set,
       the first label line is long, and the second is shorter and left-justified, the second will align with the left-most character
       in the first line, regardless of how large the node might be. *)


 ?quantum:float -> (* If quantum > 0.0, node label dimensions will be rounded to integral multiples of the quantum. *)
 ?remincross:unit -> (* If true and there are multiple clusters, run cross minimization a second time. *)

 ?samplepoints: int ->
    (* If the input graph defines the ?vertices attribute, and output is dot or xdot, this give the number of points used to represent
       circles and ellipses. It plays the same role in neato, when adjusting the layout to avoid overlapping nodes. Default 8. *)

 statement list -> graph



val subgraph:

 ?name:ident ->

 ?rank: [ `same | `min | `max | `source | `sink ] ->
    (* rank=.. Rank constraints on the nodes in a subgraph. If rank="same", all nodes are placed on the same rank.
       If rank="min", all nodes are placed on the minimum rank. If rank="source", all nodes are placed on the minimum
       rank, and the only nodes on the minimum rank belong to some subgraph whose rank attribute is "source" or "min".
       Analogous criteria hold for rank="max" and rank="sink". (Note: the minimum rank is topmost or leftmost, and the
       maximum rank is bottommost or rightmost.) *)

 statement list -> statement


(* See http://www.graphviz.org/Gallery/directed/cluster.html *)
val cluster:

 ?name_suffix:cluster_ident ->
 ?rank: [ `same | `min | `max | `source | `sink ] ->
 ?color:color ->
 ?bgcolor:color ->

 ?fillcolor: color  ->
    (* Color used to fill the background of a node or cluster. If fillcolor is not defined, color is used.
       (For clusters, if color is not defined, bgcolor is used.) If this is not defined, the default is used, except for shape=point or when
       the output format is MIF, which use black by default.
       Note that a cluster inherits the root graph's attributes if defined. Thus, if the root graph has defined a fillcolor, this will override
       a color or bgcolor attribute set for the cluster. Default is black for clusters. *)

 ?pencolor:color ->
    (* Color used to draw the bounding box around a cluster. If pencolor is not defined, color is used. If this is not defined, bgcolor is used.
       If this is not defined, the default is used. Note that a cluster inherits the root graph's attributes if defined. Thus, if the root graph
       has defined a pencolor, this will override a color or bgcolor attribute set for the cluster. *)

 ?fontcolor: color  ->
 ?fontname:string   -> (* Default is "Times-Roman" *)
 ?fontsize:int ->
 ?label: label ->
 ?labeljust: [ `r | `l | `c ] ->
 ?labelloc: [ `t | `b ] -> (* Default is "t" for clusters. *)
 ?nojustify:unit ->
 ?url:escaped_string ->

 ?peripheries: int ->
    (* Set number of peripheries used in polygonal shapes and cluster boundaries. Note that user-defined shapes are treated as a form of box shape,
       so the default peripheries value is 1 and the user-defined shape will be drawn in a bounding rectangle. Setting peripheries=0 will turn this off.
       Also, 1 is the maximum peripheries value for clusters. Default is 1 for clusters *)

 ?style: [ `filled | `rounded ] list -> (*  For cluster subgraph, if "filled", the cluster box's background is filled. *)

 statement list -> statement


val node :

 ?url:escaped_string ->
 ?color:color ->
 ?comment: string   ->
 ?distortion:float ->
    (* Distortion factor for shape=polygon. Positive values cause top part to be larger than bottom; negative values do the opposite.
       Default is 0.0, maximum is 100.0 *)

 ?fillcolor: color  -> (* Default is lightgrey for nodes *)

 ?fontcolor: color  ->
 ?fontname:string   ->
 ?fontsize:int ->

 ?fixedsize:unit ->
    (* If true, the node size is specified by the values of the width and height attributes only and is not expanded to contain the text label. *)

 ?group:string ->
    (* If the end points of an edge belong to the same group, i.e., have the same group attribute, parameters are set to avoid
       crossings and keep the edges straight. *)

 ?height:float ->
    (* Height of node, in inches. This is taken as the initial, minimum height of the node. If fixedsize is true, this will be the final height of the node.
       Otherwise, if the node label requires more height to fit, the node's height will be increased to contain the label. Note also that, if the output
       format is dot, the value given to height will be the final value. Default is 0.5, maximum is 0.02. *)

 ?layer: layer_ident list -> (* Specifies layers in which the node or edge is present. *)

 ?margin:(float*float) -> (* For nodes, this attribute specifies space left around the node's label. By default, the value is 0.11,0.055. *)

 ?nojustify:unit ->

 ?orientation:float -> (* Angle, in degrees, used to rotate node shapes. Default is 0.0, maximum is 360.0 *)

 ?peripheries: int -> (* Default is shape default for nodes *)

 ?pos:float*float -> (* Set the position of node in points. Concerning this, see the -s command line flag. *)
 ?regular:unit ->    (* Force polygon to be regular. *)

 ?shape: [ `box | `ellipse | `circle | `point | `egg | `triangle | `plaintext | `diamond | `trapezium | `parallelogram | `house
         | `pentagon | `hexagon | `septagon | `octagon | `doublecircle | `doubleoctagon | `tripleoctagon | `invtriangle | `invtrapezium
         | `invhouse | `Mdiamond | `Msquare | `Mcircle | `rect | `rectangle | `none
         | `epsf of filename (* shape=epsf, shapefile=filename *)
         | `polygon of int * int (* shape=polygon, sides=int, skew=int. Default are sides=4 and skew=0.0 *)
         ] ->
   (* Default is ellipse. See http://www.graphviz.org/pub/scm/graphviz2/doc/info/shapes.html#polygon  *)

 (* Undocumented, but really nice: the image act as a background for the label. *)
 ?image:filename ->

 ?label: label -> (* Internal label. Default is "N" for nodes. *)
 ?style: [ `dashed | `dotted | `solid | `invis | `bold | `filled | `diagonals | `rounded ] list ->

 ?width:float ->
    (* Width of node, in inches. This is taken as the initial, minimum width of the node. If fixedsize is true, this will be the final width of the node.
       Otherwise, if the node label requires more width to fit, the node's width will be increased to contain the label. Note also that, if the output format
       is dot, the value given to width will be the final value. *)

 ?z:float ->
   (* Provides z coordinate value for 3D layouts and displays. If the graph has dim set to 3 (or more), neato will use a node's z value for
      the z coordinate of its initial position if its pos attribute is also defined.
      Even if no z values are specified in the input, it is necessary to declare a z attribute for nodes, e.g, using node[z=""] in order to get z values on output.
      Thus, setting dim=3 but not declaring z will cause neato -Tvrml to layout the graph in 3D but project the layout onto the xy-plane for the rendering.
      If the z attribute is declared, the final rendering will be in 3D. *)

 ?outlabel:[ `north of label | `south of label | `east of label | `west of label ] ->

 node_ident -> statement


val edge :

 ?url:escaped_string ->
 ?color:color ->
 ?comment: string   ->

 ?arrowhead: [ `normal | `inv | `dot | `invdot | `odot | `invodot | `none | `tee | `empty | `invempty
             | `diamond | `odiamond | `ediamond | `crow | `box | `obox | `Open | `halfopen | `vee ] ->
   (* Style of arrowhead on the head node of an edge. Default is normal. See: http://www.graphviz.org/pub/scm/graphviz2/doc/info/attrs.html#k:arrowType *)

 ?arrowtail: [ `normal | `inv | `dot | `invdot | `odot | `invodot | `none | `tee | `empty | `invempty
             | `diamond | `odiamond | `ediamond | `crow | `box | `obox | `Open | `halfopen | `vee ] ->
   (* Style of arrowhead on the tail node of an edge. Default is normal. See: http://www.graphviz.org/pub/scm/graphviz2/doc/info/attrs.html#k:arrowType *)

 ?dir: [ `forward | `back | `both | `none ] -> (* Default is forward fo directed graphs *)

 ?arrowsize:float -> (* Multiplicative scale factor for arrowheads. Default is 1.0 *)

 ?constraint_off:unit ->
    (* Dot attribute is simply "constraint" which is an OCaml keyword.
       If set, the edge is not used in ranking the nodes. *)

 ?decorate:unit ->
   (* Attach edge label to edge by a 2-segment polyline, underlining the label, then going to the closest point of spline. *)

 ?fontcolor: color  ->
 ?fontname:string   ->
 ?fontsize:int -> (* Default is 14.0, minimum is 1.0. *)

 ?headclip:bool ->
   (* If true, the head of an edge is clipped to the boundary of the head node; otherwise, the end of the edge goes to the center of the node,
      or the center of a port, if applicable. Default is true. *)

 ?headlabel: label ->
   (* Text label to be placed near head of edge. *)

 ?headport: port_ident * ([ `n | `ne | `e | `se | `s | `sw | `w | `nw ] option) ->
   (* Indicates where on the head node to attach the head of the edge. In the default case, the edge is aimed towards the center of the node,
      and then clipped at the node boundary.
      The optional modifier indicating where on a node an edge should be aimed. It has the form portname[:compass_point] or compass_point. If the first form is used,
      the corresponding node must either have record shape with one of its fields having the given portname, or have an HTML-like label, one of whose
      components has a PORT attribute set to portname. In this case, the edge is aimed for the center of the corresponding field.
      If a compass point is used, it must have the form "n","ne","e","se","s","sw","w","nw". This modifies the edge placement to aim for the corresponding
      compass point on the port or, in the second form where no portname is supplied, on the node itself.
      This attribute can be attached to an edge using the headport and tailport attributes, or as part of the edge description as in
      node1:port1 -> node2:port5:nw. Default is center. *)

 ?tailclip:bool ->
 ?taillabel: label ->
 ?tailport: port_ident * ([ `n | `ne | `e | `se | `s | `sw | `w | `nw ] option) ->

 ?label: label -> (* Default is the empty string for edges. *)

 ?labelangle:float ->
   (* This, along with labeldistance, determine where the headlabel (taillabel) are placed with respect to the head (tail) in polar coordinates.
       The origin in the coordinate system is the point where the edge touches the node. The ray of 0 degrees goes from the origin back along the edge,
       parallel to the edge at the origin. The angle, in degrees, specifies the rotation from the 0 degree ray, with positive angles moving counterclockwise
       and negative angles moving clockwise. Default is -25.0, minimum is -180.0 *)

 ?labeldistance:float ->
   (* Multiplicative scaling factor adjusting the distance that the headlabel(taillabel) is from the head(tail) node.
       The default distance is 10 points. See labelangle for more details. Default is 1.0. *)

 ?labelfloat:unit ->
   (* Allows edge labels to be less constrained in position. In particular, it may appear on top of other edges. *)

 ?labelfontcolor: color ->
   (* Color used for headlabel and taillabel. If not set, defaults to edge's fontcolor. Default is black. *)

 ?labelfontname:string ->
   (* Font used for headlabel and taillabel. If not set, defaults to edge's fontname. *)

 ?labelfontsize:int ->
   (* Font size, in points, used for headlabel and taillabel. If not set, defaults to edge's fontsize. *)

 ?layer: layer_ident list -> (* Specifies layers in which the node or edge is present. *)

 ?lhead:cluster_ident ->
   (* Logical head of an edge. When the graph option "compound" is true, if lhead is defined and is the name of a cluster containing the real head,
      the edge is clipped to the boundary of the cluster. *)

 ?ltail:cluster_ident ->
   (* Logical tail of an edge. When compound is true, if ltail is defined and is the name of a cluster containing the real tail, the edge is clipped
      to the boundary of the cluster. *)

 ?minlen:int ->
   (* Minimum edge length (rank difference between head and tail). *)

 ?nojustify:unit ->
 ?pos:float*float -> (* Set the position of spline control points in points. Concerning this, see the -s command line flag. *)

 ?samehead:point_ident ->  (* Edges with the same head and the same samehead value are aimed at the same point on the head. *)
 ?sametail:point_ident ->  (* Edges with the same tail and the same sametail value are aimed at the same point on the tail. *)

 ?style: [ `dashed | `dotted | `solid | `invis | `bold ] list ->

 ?weight:float ->
   (* Weight of edge. In dot, the heavier the weight, the shorter, straighter and more vertical the edge is.
      Default is 1.0, minimum is 0. *)

 node_ident -> node_ident -> statement


val graph_default :
 ?size:[ `max of (float*float) | `force of (float*float) ] ->
 ?page:(float*float) ->
 ?pagedir: [ `BL | `BR | `TL | `TR | `RB | `RT | `LB | `LT ] ->
 ?rotate:float ->
 ?ratio:[ `float of float | `fill | `compress | `auto ] ->
 ?margin:(float*float) ->
 ?center:unit ->
 ?nodesep:float ->
 ?ordering:[ `inp | `out ] ->
 ?outputorder: [ `breadthfirst | `nodesfirst | `edgesfirst ] ->
 ?rank: [ `same | `min | `max | `source | `sink ] ->
 ?rankdir: [`TB|`LR|`RL|`BT] ->
 ?ranksep:float ->
 ?clusterrank:[ `local | `global | `none ] ->
 ?nslimit:float ->
 ?layers:layer_ident list ->
 ?color:color ->
 ?bgcolor:color ->
 ?href:string ->
 ?url:escaped_string ->
 ?stylesheet:string ->
 ?charset:string ->
 ?comment: string ->
 ?compound: unit  ->
 ?concentrate: unit ->
 ?fontcolor: color  ->
 ?fontname:string   ->
 ?fontpath:string list ->
 ?fontsize:int ->
 ?label: label ->
 ?labeljust: [ `r | `l | `c ] ->
 ?labelloc: [ `t | `b ] ->
 ?nojustify:unit ->
 ?quantum:float ->
 ?remincross:unit ->
 ?samplepoints: int ->
 unit -> statement


val node_default :
 ?url:escaped_string ->
 ?color:color ->
 ?comment: string   ->
 ?distortion:float ->
 ?fillcolor: color  ->
 ?fontcolor: color  ->
 ?fontname:string   ->
 ?fontsize:int ->
 ?fixedsize:unit ->
 ?group:string ->
 ?height:float ->
 ?layer: layer_ident list ->
 ?margin:(float*float) ->
 ?nojustify:unit ->
 ?orientation:float ->
 ?peripheries: int ->
 ?pos:float*float ->
 ?regular:unit ->
 ?shape: [ `box | `ellipse | `circle | `point | `egg | `triangle | `plaintext | `diamond | `trapezium | `parallelogram | `house
         | `pentagon | `hexagon | `septagon | `octagon | `doublecircle | `doubleoctagon | `tripleoctagon | `invtriangle | `invtrapezium
         | `invhouse | `Mdiamond | `Msquare | `Mcircle | `rect | `rectangle | `none
         | `epsf of filename (* shape=epsf, shapefile=filename *)
         | `polygon of int * int (* shape=polygon, sides=int, skew=int. Default are sides=4 and skew=0.0 *)
         ] ->
 ?image:filename ->
 ?label: label ->
 ?style: [ `dashed | `dotted | `solid | `invis | `bold | `filled | `diagonals | `rounded ] list ->
 ?width:float ->
 ?z:float ->
 unit -> statement

val edge_default :
 ?url:escaped_string ->
 ?color:color ->
 ?comment: string   ->
 ?arrowhead: [ `normal | `inv | `dot | `invdot | `odot | `invodot | `none | `tee | `empty | `invempty
             | `diamond | `odiamond | `ediamond | `crow | `box | `obox | `Open | `halfopen | `vee ] ->
 ?arrowtail: [ `normal | `inv | `dot | `invdot | `odot | `invodot | `none | `tee | `empty | `invempty
             | `diamond | `odiamond | `ediamond | `crow | `box | `obox | `Open | `halfopen | `vee ] ->
 ?dir: [ `forward | `back | `both | `none ] ->
 ?arrowsize:float ->
 ?constraint_off:unit ->
 ?decorate:unit ->
 ?fontcolor: color  ->
 ?fontname:string   ->
 ?fontsize:int ->
 ?headclip:bool ->
 ?headlabel: label ->
 ?headport: port_ident * ([ `n | `ne | `e | `se | `s | `sw | `w | `nw ] option) ->
 ?tailclip:bool ->
 ?taillabel: label ->
 ?tailport: port_ident * ([ `n | `ne | `e | `se | `s | `sw | `w | `nw ] option) ->
 ?label: label ->
 ?labelangle:float ->
 ?labeldistance:float ->
 ?labelfloat:unit ->
 ?labelfontcolor: color ->
 ?labelfontname:string ->
 ?labelfontsize:int ->
 ?layer: layer_ident list ->
 ?lhead:cluster_ident ->
 ?ltail:cluster_ident ->
 ?minlen:int ->
 ?nojustify:unit ->
 ?pos:float*float ->
 ?samehead:point_ident ->
 ?sametail:point_ident ->
 ?style: [ `dashed | `dotted | `solid | `invis | `bold ] list ->
 ?weight:float ->
 unit -> statement


val label_of_text  : ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> text  -> label
val label_of_table : ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> table -> label
val label_of_image :
 ?align: [ `CENTER | `LEFT | `RIGHT ] ->
 ?valign:[ `BOTTOM | `MIDDLE | `TOP ] ->
 ?bgcolor:color ->
 ?border:float ->
 ?cellborder:float ->
 ?cellpadding:float ->
 ?cellspacing:float ->
 ?fixedsize:bool ->
 ?height:float ->
 ?href:string ->
 ?port:string ->
 ?target:string ->
 ?title:string ->
 ?tooltip:string ->
 ?width:float ->
 ?imagescale:[ `BOTH | `FALSE | `HEIGHT | `TRUE | `WIDTH ] ->
 filename -> label

val html_of_text  : ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> text  -> html_like
val html_of_table : ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> table -> html_like
val html_of_label : ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> label -> html_like

val text_of_string : ?br:unit -> ?align:[ `CENTER | `LEFT | `RIGHT ] -> string -> text
val text_concat : text list -> text

val table :
 ?align: [ `CENTER | `LEFT | `RIGHT ] ->
 ?valign:[ `BOTTOM | `MIDDLE | `TOP ] ->
 ?bgcolor:color ->
 ?border:float ->
 ?cellborder:float ->
 ?cellpadding:float ->
 ?cellspacing:float ->
 ?fixedsize:bool ->
 ?height:float ->
 ?href:string ->
 ?port:string ->
 ?target:string ->
 ?title:string ->
 ?tooltip:string ->
 ?width:float
 -> row list -> table

val cell_of_text :
 ?align: [ `CENTER | `LEFT | `RIGHT ] ->
 ?valign:[ `BOTTOM | `MIDDLE | `TOP ] ->
 ?bgcolor:color ->
 ?border:float ->
 ?cellpadding:float ->
 ?cellspacing:float ->
 ?fixedsize:bool ->
 ?height:float ->
 ?href:string ->
 ?port:string ->
 ?target:string ->
 ?title:string ->
 ?tooltip:string ->
 ?width:float ->
 ?colspan:int ->
 ?rowspan:int ->
 ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> text -> cell

val cell_of_string :
 ?align: [ `CENTER | `LEFT | `RIGHT ] ->
 ?valign:[ `BOTTOM | `MIDDLE | `TOP ] ->
 ?bgcolor:color ->
 ?border:float ->
 ?cellpadding:float ->
 ?cellspacing:float ->
 ?fixedsize:bool ->
 ?height:float ->
 ?href:string ->
 ?port:string ->
 ?target:string ->
 ?title:string ->
 ?tooltip:string ->
 ?width:float ->
 ?colspan:int ->
 ?rowspan:int ->
 ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> string -> cell

val cell_of_table :
 ?align: [ `CENTER | `LEFT | `RIGHT ] ->
 ?valign:[ `BOTTOM | `MIDDLE | `TOP ] ->
 ?bgcolor:color ->
 ?border:float ->
 ?cellpadding:float ->
 ?cellspacing:float ->
 ?fixedsize:bool ->
 ?height:float ->
 ?href:string ->
 ?port:string ->
 ?target:string ->
 ?title:string ->
 ?tooltip:string ->
 ?width:float ->
 ?colspan:int ->
 ?rowspan:int ->
 ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> table -> cell

val cell_of_html :
 ?align: [ `CENTER | `LEFT | `RIGHT ] ->
 ?valign:[ `BOTTOM | `MIDDLE | `TOP ] ->
 ?bgcolor:color ->
 ?border:float ->
 ?cellpadding:float ->
 ?cellspacing:float ->
 ?fixedsize:bool ->
 ?height:float ->
 ?href:string ->
 ?port:string ->
 ?target:string ->
 ?title:string ->
 ?tooltip:string ->
 ?width:float ->
 ?colspan:int ->
 ?rowspan:int ->
 ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> html_like -> cell

val cell_of_label :
 ?align: [ `CENTER | `LEFT | `RIGHT ] ->
 ?valign:[ `BOTTOM | `MIDDLE | `TOP ] ->
 ?bgcolor:color ->
 ?border:float ->
 ?cellpadding:float ->
 ?cellspacing:float ->
 ?fixedsize:bool ->
 ?height:float ->
 ?href:string ->
 ?port:string ->
 ?target:string ->
 ?title:string ->
 ?tooltip:string ->
 ?width:float ->
 ?colspan:int ->
 ?rowspan:int ->
 ?fontcolor:color -> ?fontname:string -> ?fontsize:int -> label -> cell

val cell_of_image :
 ?align: [ `CENTER | `LEFT | `RIGHT ] ->
 ?valign:[ `BOTTOM | `MIDDLE | `TOP ] ->
 ?bgcolor:color ->
 ?border:float ->
 ?cellpadding:float ->
 ?cellspacing:float ->
 ?fixedsize:bool ->
 ?height:float ->
 ?href:string ->
 ?port:string ->
 ?target:string ->
 ?title:string ->
 ?tooltip:string ->
 ?width:float ->
 ?colspan:int ->
 ?rowspan:int ->
 ?imagescale:[ `BOTH | `FALSE | `HEIGHT | `TRUE | `WIDTH ] ->
 filename -> cell

val  print  : graph -> unit
val display : ?bg:unit -> ?silent:unit -> graph -> unit
val fprint  : filename -> graph -> unit
val sprint  : graph -> string
val graph_of_list : (node_ident * node_ident) list -> graph

type output_format =
 [ `bmp                    (* Windows Bitmap Format *)
 | `canon | `dot | `xdot   (* DOT *)
 | `cmap                   (* Client-side imagemap (deprecated) *)
 | `dia                    (* Dia diagram creation program *)
 | `eps                    (* Encapsulated PostScript *)
 | `fig                    (* FIG *)
 | `gd | `gd2              (* GD/GD2 formats *)
 | `gif                    (* GIF *)
 | `hpgl                   (* HP-GL subset of PCL *)
 | `ico                    (* Icon Image File Format *)
 | `imap | `cmapx          (* Server-side and client-side imagemaps *)
 | `imap_np | `cmapx_np    (* Server-side and client-side imagemaps *)
 | `ismap                  (* Server-side imagemap (deprecated) *)
 | `jpg                    (* JPEG *)
 | `pdf                    (* Portable Document Format (PDF) *)
 | `plain | `plain_ext     (* Simple text format *)
 | `png                    (* Portable Network Graphics format *)
 | `ps                     (* PostScript *)
 | `ps2                    (* PostScript for PDF *)
 | `svg | `svgz            (* Scalable Vector Graphics *)
 | `tiff                   (* TIFF (Tag Image File Format) *)
 | `vml | `vmlz            (* Vector Markup Language (VML) *)
 | `vrml                   (* VRML *)
 | `wbmp                   (* Wireless BitMap format *)
(* The following provoke an long time (infinite?) execution: *)
(*  | `xlib                   (* Xlib canvas *) *)
 ]

val string_of_output_format : output_format -> string
val output_format_of_string : string -> output_format

val output_format_description : output_format -> string
val admissible_output_formats : output_format list
val admissible_output_formats_as_strings : string list

val make_image :
  ?silent:unit -> (* Hide dot errors or warnings *)
  ?dotfile:filename ->
  ?imgfile:filename ->
  ?imgtype:output_format -> (* by default `png *)
  graph -> (filename * filename)

(** Return a 4-tuple (output, as_string, description, file_command_output) *)
val working_output_formats : ?no_file_inspection:unit -> unit -> (output_format * string * string * string) list
val working_output_formats_as_objects : ?no_file_inspection:unit -> unit ->
 < output_format : output_format;
   output_format_as_string : string;
   description : string;
   file_command_output : string;
   > list
