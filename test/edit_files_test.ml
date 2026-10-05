(* GPL-2.0-or-later. Real sparse files, deletion, symlinks and retained inodes. *)
let require condition message = if not condition then failwith message
let () =
  let root = Filename.temp_dir "marionnet-undo-files-" "" in
  Fun.protect ~finally:(fun () -> Edit_files.discard root) (fun () ->
    List.iter (fun name -> Unix.mkdir (Filename.concat root name) 0o700)
      ["tmp"; "states"; "hostfs"];
    let disk = Filename.concat root "states/disk.cow" in
    let fd = Unix.openfile disk [Unix.O_CREAT; Unix.O_RDWR] 0o600 in
    ignore (Unix.LargeFile.lseek fd 1073741824L Unix.SEEK_SET);
    ignore (Unix.write_substring fd "state" 0 5);
    Unix.close fd;
    let link = Filename.concat root "hostfs/shortcut" in
    Unix.symlink "../states/disk.cow" link;
    let before = Unix.stat disk in
    let locked = Filename.concat root "hostfs/read-only" in
    Unix.mkdir locked 0o555;
    let backup = Edit_files.capture root in
    let held = Unix.stat (Filename.concat backup "states/disk.cow") in
    require (held.Unix.st_ino = before.Unix.st_ino) "The sparse disk was copied";
    (* Runtime bytes stay current even when a configuration edit is older. *)
    let out = open_out_gen [Open_wronly; Open_append; Open_binary] 0o600 disk in
    output_string out "latest"; close_out out;
    let latest = Unix.stat disk in
    Unix.unlink disk; Unix.unlink link; Unix.rmdir locked;
    Edit_files.restore ~root backup;
    let restored = Unix.stat disk in
    require (restored.Unix.st_ino = latest.Unix.st_ino
      && restored.Unix.st_size = latest.Unix.st_size
      && restored.Unix.st_mtime = latest.Unix.st_mtime) "Guest data or backing-file mtime was lost";
    require (Unix.readlink link = "../states/disk.cow") "Symlink was not restored";
    require ((Unix.stat locked).Unix.st_perm = 0o555) "Directory permissions changed";
    let outside = Filename.temp_dir "marionnet-undo-outside-" "" in
    Fun.protect ~finally:(fun () -> Edit_files.discard outside) (fun () ->
      Edit_files.discard (Filename.concat root "hostfs");
      Unix.symlink outside (Filename.concat root "hostfs");
      let refused = try Edit_files.restore ~root backup; false with Failure _ -> true in
      require refused "Restoration followed an existing symbolic link";
      require (Sys.readdir outside = [||]) "Restoration wrote outside the project");
    Edit_files.discard backup;
    require (Sys.file_exists disk) "Discarding history removed the restored disk";
    print_endline "PASS: sparse guest data, timestamps and symlinks survive deletion and history cleanup")
