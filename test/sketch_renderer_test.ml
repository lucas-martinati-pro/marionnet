(* GPL-2.0-or-later. Real Graphviz; no display, guest or privileged operation. *)
let require condition message = if not condition then failwith message
let render_snapshot = Sketch_renderer.render ~spawn:Unix.create_process

let read file =
  let channel = open_in_bin file in
  Fun.protect ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let rec remove file =
  if (Unix.lstat file).Unix.st_kind = Unix.S_DIR then begin
    Array.iter (fun name -> remove (Filename.concat file name)) (Sys.readdir file);
    Unix.rmdir file
  end else Unix.unlink file

let () =
  let directory = Filename.temp_file "marionnet-sketch-test-" " d'aujourd'hui $ (réseau)" in
  Unix.unlink directory;
  Unix.mkdir directory 0o700;
  Fun.protect ~finally:(fun () -> remove directory) (fun () ->
    let request = {
      Sketch_renderer.dot_file = Filename.concat directory "-network.dot";
      png_file = Filename.concat directory "-network.png";
      content = "digraph network { h1 [URL=\"marionnet:node:1\"]; h2 [URL=\"marionnet:node:2\"]; h1 -> h2 [URL=\"marionnet:cable:3\"] }";
      splines = false;
    } in
    let render request = match render_snapshot request with
      | Ok result -> result | Error error -> failwith error in
    let first = render request in
    require (not (Sys.file_exists request.png_file)) "render published without permission";
    Sketch_renderer.publish first;
    let png = read request.png_file in
    let map = read (Sketch_renderer.map_file request) in
    let areas = Sketch_hit_map.parse map in
    require (List.exists (fun a -> a.Sketch_hit_map.target = Sketch_hit_map.Node 1) areas) "node map missing";
    require (List.exists (fun a -> a.Sketch_hit_map.target = Sketch_hit_map.Cable 3) areas) "cable map missing";
    require (String.starts_with ~prefix:"\137PNG\r\n\026\n" png) "not a PNG";
    require (read request.dot_file = request.content) "source snapshot changed";
    (* Invalid input may leave a partial output. Neither published file changes. *)
    (match render_snapshot {request with content = "invalid graph !"} with
     | Ok result -> Sketch_renderer.discard result; failwith "invalid DOT accepted"
     | Error error -> require (String.length error > 0) "Graphviz diagnostic missing");
    require (read request.png_file = png) "failure destroyed the last drawing";
    require (read request.dot_file = request.content) "failure destroyed the export source";
    require (read (Sketch_renderer.map_file request) = map) "failure replaced the hit map";
    (* A completed but obsolete job can be discarded without displaying it. *)
    let obsolete = render {request with content = "digraph network { stale }"} in
    Sketch_renderer.discard obsolete;
    require (read request.png_file = png) "discard published an obsolete result";
    require (Array.length (Sys.readdir directory) = 3) "temporary files leaked";
    (match render_snapshot {request with png_file = Filename.concat directory "missing/graph.png"} with
     | Error _ -> () | Ok result -> Sketch_renderer.discard result; failwith "missing directory accepted");
    print_endline "PASS: Graphviz snapshots, special paths, failed render, obsolete result and cleanup")
