(* GPL-2.0-or-later. Geometry produced by Graphviz alongside the PNG. *)
module Log = Marionnet_log

type target = Node of int | Cable of int
type shape = Rect of float * float * float * float
  | Circle of float * float * float | Poly of (float * float) array
type area = { target : target; shape : shape }

let attribute name tag =
  let expression = Str.regexp (name ^ "=\"\\([^\"]*\\)\"") in
  ignore (Str.search_forward expression tag 0);
  Str.matched_group 1 tag

let parse text =
  let tags = Str.full_split (Str.regexp "<area[^>]*>") text in
  List.filter_map (function
    | Str.Delim tag ->
        (try
          let target = match String.split_on_char ':' (attribute "href" tag) with
            | ["marionnet"; "node"; id] -> Node (int_of_string id)
            | ["marionnet"; "cable"; id] -> Cable (int_of_string id)
            | _ -> raise Not_found in
          let coordinates = List.map float_of_string
            (String.split_on_char ',' (attribute "coords" tag)) in
          let shape = match attribute "shape" tag, coordinates with
            | "rect", [x1; y1; x2; y2] -> Rect (x1, y1, x2, y2)
            | "circle", [x; y; radius] -> Circle (x, y, radius)
            | "poly", coordinates ->
                let rec pairs = function
                  | x :: y :: rest -> (x, y) :: pairs rest
                  | [] -> [] | _ -> raise Not_found in
                let points = Array.of_list (pairs coordinates) in
                if Array.length points < 3 then raise Not_found;
                Poly points
            | _ -> raise Not_found in
          Some { target; shape }
        with Not_found | Failure _ -> None)
    | _ -> None) tags

let contains shape x y = match shape with
  | Rect (x1, y1, x2, y2) -> x >= x1 && x <= x2 && y >= y1 && y <= y2
  | Circle (cx, cy, radius) -> (x -. cx) ** 2. +. (y -. cy) ** 2. <= radius ** 2.
  | Poly points ->
      let inside = ref false in
      Array.iteri (fun i (xi, yi) ->
        let xj, yj = points.((i + Array.length points - 1) mod Array.length points) in
        if (yi > y) <> (yj > y)
        && x < (xj -. xi) *. (y -. yi) /. (yj -. yi) +. xi then
          inside := not !inside) points;
      !inside

let hit areas ~x ~y =
  (* Nodes take precedence where an edge's envelope crosses an icon. *)
  let find predicate = List.find_opt (fun area -> predicate area.target && contains area.shape x y) areas in
  match find (function Node _ -> true | _ -> false) with
  | Some area -> Some area.target
  | None -> Option.map (fun area -> area.target) (find (fun _ -> true))
