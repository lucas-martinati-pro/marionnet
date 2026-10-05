(* GPL-2.0-or-later. Preserve project-owned files across reversible edits.
   Hard links retain sparse guest disks without copying or rolling back their bytes. *)

module Log = Marionnet_log

let rec remove path =
  match (Unix.lstat path).Unix.st_kind with
  | Unix.S_DIR ->
      Unix.chmod path ((Unix.stat path).Unix.st_perm lor 0o700);
      Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path);
      Unix.rmdir path
  | _ -> Unix.unlink path

let rec link_tree source target =
  let stat = Unix.lstat source in
  match stat.Unix.st_kind with
  | Unix.S_DIR ->
      Unix.mkdir target 0o700;
      Array.iter (fun name -> link_tree (Filename.concat source name)
        (Filename.concat target name)) (Sys.readdir source);
      Unix.chmod target stat.Unix.st_perm
  | Unix.S_REG -> Unix.link source target
  | Unix.S_LNK -> Unix.symlink (Unix.readlink source) target
  | _ -> () (* Runtime sockets and devices are not project data. *)

let capture root =
  let backup = Filename.temp_dir ~temp_dir:(Filename.concat root "tmp") ".undo-" "" in
  try
    List.iter (fun folder ->
      let source = Filename.concat root folder in
      if Sys.file_exists source then link_tree source (Filename.concat backup folder))
      ["states"; "hostfs"];
    backup
  with e -> remove backup; raise e

let discard backup = if Sys.file_exists backup then remove backup

let rec restore_tree source target =
  let stat = Unix.lstat source in
  match stat.Unix.st_kind with
  | Unix.S_DIR ->
      let created = not (Sys.file_exists target) in
      if created then Unix.mkdir target 0o700;
      if (Unix.lstat target).Unix.st_kind <> Unix.S_DIR then
        failwith ("Cannot restore project directory through a symbolic link: " ^ target);
      Array.iter (fun name -> restore_tree (Filename.concat source name)
        (Filename.concat target name)) (Sys.readdir source);
      if created then Unix.chmod target stat.Unix.st_perm
  | Unix.S_REG ->
      if not (Sys.file_exists target) then Unix.link source target
  | Unix.S_LNK ->
      (try ignore (Unix.lstat target) with Unix.Unix_error (Unix.ENOENT, _, _) ->
        Unix.symlink (Unix.readlink source) target)
  | _ -> ()

let restore ~root backup =
  Array.iter (fun folder -> restore_tree (Filename.concat backup folder)
    (Filename.concat root folder)) (Sys.readdir backup)
