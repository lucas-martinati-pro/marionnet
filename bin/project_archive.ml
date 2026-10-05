(* This file is part of Marionnet, distributed under GPL-2.0-or-later. *)

module Log = Marionnet_log

let unlink_if_present path =
  try Unix.unlink path with
  | Unix.Unix_error (Unix.ENOENT, _, _) -> ()
  | e -> Log.printf2 ~force:true "Project_archive: cannot remove %s: %s\n"
           path (Printexc.to_string e)

let with_fd path flags perm f =
  let fd = Unix.openfile path (Unix.O_CLOEXEC :: flags) perm in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () -> f fd)

let rec waitpid pid =
  try snd (Unix.waitpid [] pid) with
  | Unix.Unix_error (Unix.EINTR, _, _) -> waitpid pid

let read_diagnostic path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () -> String.trim (really_input_string ic (min 65536 (in_channel_length ic))))

let run_tar ~stderr_path ~step arguments =
  let argv = Array.of_list ("tar" :: arguments) in
  Log.printf1 "Project_archive: %s\n"
    (String.concat " " (List.map Filename.quote (Array.to_list argv)));
  let status =
    with_fd "/dev/null" [Unix.O_RDONLY] 0 (fun stdin ->
      with_fd "/dev/null" [Unix.O_WRONLY] 0 (fun stdout ->
        with_fd stderr_path [Unix.O_WRONLY; Unix.O_TRUNC] 0 (fun stderr ->
          waitpid (Unix.create_process "tar" argv stdin stdout stderr))))
  in
  match status with
  | Unix.WEXITED 0 -> ()
  | _ ->
      let status_text = match status with
        | Unix.WEXITED code -> Printf.sprintf "exit %d" code
        | Unix.WSIGNALED signal -> Printf.sprintf "signal %d" signal
        | Unix.WSTOPPED signal -> Printf.sprintf "stopped by signal %d" signal
      in
      failwith (Printf.sprintf "Project archive %s failed (%s): %s"
                  step status_text (read_diagnostic stderr_path))

let save ?(on_staging_file=(fun _ -> ()))
    ~filename ~working_directory ~root_basename ~excluded_paths () =
  (* Saving through an existing symlink updates its target, as the old tar writer did.
     A dangling symlink is an error, rather than silently replacing the link itself. *)
  let destination =
    try
      if (Unix.lstat filename).Unix.st_kind = Unix.S_LNK
      then Unix.realpath filename else filename
    with Unix.Unix_error (Unix.ENOENT, _, _) ->
      (* realpath must not turn a dangling link into an ordinary new filename. *)
      (match (try Some (Unix.lstat filename) with
              Unix.Unix_error (Unix.ENOENT, _, _) -> None) with
       | Some _ -> failwith ("Cannot save through a dangling link: " ^ filename)
       | None -> filename)
  in
  let permissions =
    try
      let stat = Unix.stat destination in
      if stat.Unix.st_kind <> Unix.S_REG then
        failwith ("Project archive destination is not a regular file: " ^ filename);
      Unix.access destination [Unix.W_OK];
      stat.Unix.st_perm
    with Unix.Unix_error (Unix.ENOENT, _, _) -> 0o600
  in
  let directory = Filename.dirname destination in
  let staging = Filename.temp_file ~temp_dir:directory ".marionnet-save-" ".mar.part" in
  Fun.protect ~finally:(fun () -> unlink_if_present staging) (fun () ->
    let diagnostic = Filename.temp_file ~temp_dir:directory ".marionnet-save-" ".stderr" in
    Fun.protect ~finally:(fun () -> unlink_if_present diagnostic) (fun () ->
      on_staging_file staging;
      let exclusions = List.map (fun path -> "--exclude=" ^ path) excluded_paths in
      run_tar ~stderr_path:diagnostic ~step:"creation"
        (["--create"; "--sparse"; "--gzip"; "--file"; staging;
          "--directory"; working_directory] @ exclusions @ ["--"; root_basename]);
      run_tar ~stderr_path:diagnostic ~step:"verification"
        ["--list"; "--gzip"; "--file"; staging];
      with_fd staging [Unix.O_RDWR] 0 (fun fd ->
        Unix.fchmod fd permissions;
        Unix.fsync fd);
      with_fd directory [Unix.O_RDONLY] 0 (fun dir_fd ->
        (* Check that this filesystem supports directory synchronisation before committing. *)
        Unix.fsync dir_fd;
        Unix.rename staging destination;
        Unix.fsync dir_fd)))
