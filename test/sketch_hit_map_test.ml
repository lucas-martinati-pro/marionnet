(* GPL-2.0-or-later. Coordinates and overlap semantics, independent of GTK. *)
let require condition message = if not condition then failwith message
let () =
  let map = Sketch_hit_map.parse {|<map>
<area shape="poly" href="marionnet:cable:2" coords="0,0,50,0,50,50,0,50" />
<area shape="rect" href="marionnet:node:1" coords="10,10,20,20" />
<area shape="circle" href="marionnet:node:3" coords="70,20,5" />
<area shape="poly" href="marionnet:cable:4" coords="60,40,80,40,80,50,70,50,70,60,60,60" />
<area shape="rect" href="https://example.com" coords="0,0,100,100" />
<area shape="poly" href="marionnet:node:5" coords="1,2,3" />
<area shape="rect" href="marionnet:node:oops" coords="1,2,3,4" />
</map>|} in
  let hit x y = Sketch_hit_map.hit map ~x ~y in
  require (List.length map = 4) "malformed or external URL accepted";
  require (hit 15. 15. = Some (Sketch_hit_map.Node 1)) "node must win over cable";
  require (hit 10. 10. = Some (Sketch_hit_map.Node 1)) "rectangle boundary excluded";
  require (hit 5. 5. = Some (Sketch_hit_map.Cable 2)) "polygon interior missing";
  require (hit 75. 20. = Some (Sketch_hit_map.Node 3)) "circle boundary excluded";
  require (hit 76. 20. = None) "circle radius ignored";
  require (hit 65. 55. = Some (Sketch_hit_map.Cable 4)) "concave polygon interior missing";
  require (hit 75. 55. = None) "concave polygon notch selected";
  require (hit (-1.) 0. = None && hit 100. 100. = None) "blank space selected";
  print_endline "PASS: node precedence, circle, concave polygons and malformed hit maps"
