(* This file is part of Marionnet, GPL-2.0-or-later.
   Copyright (C) 2026 Marionnet contributors. *)

type request = {
  dot_file : string;
  png_file : string;
  content : string;
  splines : bool;
}

type rendered = { request : request; dot_tmp : string; png_tmp : string; map_tmp : string; graphviz_ms : float }

let map_file request = Filename.remove_extension request.png_file ^ ".cmapx"

let unlink file = try Sys.remove file with Sys_error _ -> ()
let discard result = unlink result.dot_tmp; unlink result.png_tmp; unlink result.map_tmp

let render ~spawn request =
  let temporary_files = ref [] in
  let temporary suffix =
    let file = Filename.temp_file
      ~temp_dir:(Filename.dirname request.png_file) ".marionnet-sketch-" suffix in
    temporary_files := file :: !temporary_files;
    file
  in
  let cleanup () = List.iter unlink !temporary_files in
  try
    let dot_tmp = temporary ".dot" in
    let png_tmp = temporary ".png" in
    let map_tmp = temporary ".cmapx" in
    let errors = temporary ".log" in
    let channel = open_out_bin dot_tmp in
    Fun.protect ~finally:(fun () -> close_out_noerr channel)
      (fun () -> output_string channel request.content);
    let stderr = Unix.openfile errors [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
    let graphviz_started = Unix.gettimeofday () in
    let status = Fun.protect ~finally:(fun () -> Unix.close stderr) (fun () ->
      let argv = [| "dot"; "-Gsplines=" ^ string_of_bool request.splines;
        "-Efontname=FreeSans"; "-Nfontname=FreeSans"; "-Tpng";
        "-o"; png_tmp; "-Tcmapx"; "-o"; map_tmp; dot_tmp |] in
      let pid = spawn "dot" argv Unix.stdin Unix.stdout stderr in
      let rec wait () =
        try snd (Unix.waitpid [] pid)
        with Unix.Unix_error (Unix.EINTR, _, _) -> wait ()
      in wait ()) in
    match status with
    | Unix.WEXITED 0 when (Unix.stat png_tmp).Unix.st_size > 0 && (Unix.stat map_tmp).Unix.st_size > 0 ->
        unlink errors;
        Ok { request; dot_tmp; png_tmp; map_tmp;
             graphviz_ms = 1000. *. (Unix.gettimeofday () -. graphviz_started) }
    | _ ->
        let channel = open_in_bin errors in
        let details = Fun.protect ~finally:(fun () -> close_in_noerr channel)
          (fun () -> really_input_string channel (min 4096 (in_channel_length channel))) in
        let status_text = match status with
          | Unix.WEXITED n -> Printf.sprintf "exit %d" n
          | Unix.WSIGNALED n -> Printf.sprintf "signal %d" n
          | Unix.WSTOPPED n -> Printf.sprintf "stopped %d" n in
        cleanup ();
        Error (Printf.sprintf "Graphviz (%s): %s" status_text (String.trim details))
  with exception_ ->
    cleanup ();
    Error (Printexc.to_string exception_)

let publish result =
  Fun.protect ~finally:(fun () -> discard result) (fun () ->
    Unix.rename result.dot_tmp result.request.dot_file;
    Unix.rename result.map_tmp (map_file result.request);
    Unix.rename result.png_tmp result.request.png_file)

let graphviz_ms result = result.graphviz_ms

let hit_map result =
  let channel = open_in_bin result.map_tmp in
  Fun.protect ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))
