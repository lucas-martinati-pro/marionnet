(* Regression tests for .mar saving, GPL-2.0-or-later. Real tar, no Gtk+, sudo or guest. *)

let write path content =
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc content)

let read path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let require condition message = if not condition then failwith message

let contains text part =
  let rec loop i =
    i + String.length part <= String.length text &&
    (String.sub text i (String.length part) = part || loop (i + 1))
  in loop 0

let rec remove path =
  if (Unix.lstat path).Unix.st_kind = Unix.S_DIR then begin
    Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path);
    Unix.rmdir path
  end else Unix.unlink path

let command program arguments =
  let ic = Unix.open_process_args_in program (Array.of_list (program :: arguments)) in
  let output = Buffer.create 128 in
  (try while true do Buffer.add_string output (input_line ic); Buffer.add_char output '\n' done
   with End_of_file -> ());
  require (Unix.close_process_in ic = Unix.WEXITED 0) (program ^ " failed");
  Buffer.contents output

let with_fixture f =
  let directory = Filename.temp_file "marionnet-archive-test-" "" in
  Unix.unlink directory;
  Unix.mkdir directory 0o700;
  Fun.protect ~finally:(fun () -> remove directory) (fun () ->
    let working = Filename.concat directory "TP d'aujourd'hui $ (réseau)" in
    Unix.mkdir working 0o700;
    let root = "-lab" in
    let project = Filename.concat working root in
    Unix.mkdir project 0o700;
    List.iter (fun name -> Unix.mkdir (Filename.concat project name) 0o700) ["states"; "tmp"];
    write (Filename.concat project "version") "v3\n";
    write (Filename.concat project "states/current.cow") "current disk\n";
    write (Filename.concat project "states/old.cow") "old disk\n";
    write (Filename.concat project "tmp/ephemeral") "must not be saved\n";
    let target = Filename.concat directory "TP d'aujourd'hui $ (réseau).mar" in
    f directory working root project target)

let save ?on_staging_file working root target =
  Project_archive.save ?on_staging_file ~filename:target ~working_directory:working
    ~root_basename:root ~excluded_paths:["tmp"; "states/old.cow"] ()

let no_temporary_files directory =
  require (not (Array.exists (fun name -> String.starts_with ~prefix:".marionnet-save-" name)
                  (Sys.readdir directory))) "temporary save files leaked"

let real_tar =
  let path = Sys.getenv "PATH" in
  let candidates = List.map (fun dir -> Filename.concat dir "tar") (String.split_on_char ':' path) in
  Unix.realpath (List.find (fun p -> try Unix.access p [Unix.X_OK]; true with _ -> false) candidates)

(* The wrapper injects faults only in tar; the production writer is exercised unchanged.
   Neither shell commands nor tests ever interpolate a project path. *)
let with_tar_wrapper directory body f =
  let wrappers = Filename.concat directory "tools" in
  Unix.mkdir wrappers 0o700;
  let wrapper = Filename.concat wrappers "tar" in
  write wrapper ("#!/bin/sh\n" ^ body ^ "\nexec " ^ Filename.quote real_tar ^ " \"$@\"\n");
  Unix.chmod wrapper 0o700;
  let old_path = Sys.getenv "PATH" in
  Unix.putenv "PATH" (wrappers ^ ":" ^ old_path);
  Fun.protect ~finally:(fun () -> Unix.putenv "PATH" old_path) f

let expect_failure f =
  match (try f (); None with e -> Some e) with
  | Some e -> Printexc.to_string e
  | None -> failwith "the save incorrectly succeeded"

let check_failure ~body ~diagnostic =
  with_fixture (fun directory working root _ target ->
    save working root target;
    let previous = read target in
    with_tar_wrapper directory body (fun () ->
      let error = expect_failure (fun () -> save working root target) in
      require (contains error diagnostic) ("missing failure cause: " ^ error));
    require (read target = previous) "the previous archive was overwritten";
    ignore (command real_tar ["-tzf"; target]);
    no_temporary_files directory)

let failures = ref 0
let test name f =
  try f (); Printf.printf "OK    %s\n%!" name with e ->
    incr failures;
    Printf.printf "FAIL  %s: %s\n%!" name (Printexc.to_string e)

let () =
  test "real tar: special paths, leading dash, exclusions and archive contents" (fun () ->
    with_fixture (fun directory working root _ target ->
      save working root target;
      let names = command real_tar ["-tzf"; target] in
      require (contains names "-lab/version\n") "the project root is missing";
      require (contains names "-lab/states/current.cow\n") "the current disk is missing";
      require (not (contains names "old.cow")) "an excluded snapshot was archived";
      require (not (contains names "/tmp/")) "temporary project data was archived";
      require (command real_tar ["-xOzf"; target; "--"; "-lab/version"] = "v3\n")
        "the version was changed";
      require ((Unix.stat target).Unix.st_perm = 0o600) "new archive is not private";
      no_temporary_files directory));
  test "replacement keeps the old archive until commit and preserves permissions" (fun () ->
    with_fixture (fun directory working root project target ->
      save working root target;
      Unix.chmod target 0o640;
      let previous = read target in
      write (Filename.concat project "version") "v3 updated\n";
      save ~on_staging_file:(fun path ->
        require (Filename.dirname path = Filename.dirname target) "staging is on another filesystem";
        require (read target = previous) "target changed before writing") working root target;
      require (command real_tar ["-xOzf"; target; "--"; "-lab/version"] = "v3 updated\n")
        "the new archive was not published";
      require ((Unix.stat target).Unix.st_perm = 0o640) "existing permissions changed";
      no_temporary_files directory));
  test "partial write + nonzero exit keeps the previous archive and reports stderr" (fun () ->
    check_failure ~diagnostic:"simulated disk full" ~body:
      "if [ \"$1\" = --create ]; then\n  while [ \"$1\" != --file ]; do shift; done\n  printf partial > \"$2\"\n  echo 'simulated disk full' >&2\n  exit 2\nfi");
  test "successful exit with invalid output is rejected by real tar verification" (fun () ->
    check_failure ~diagnostic:"verification" ~body:
      "if [ \"$1\" = --create ]; then\n  while [ \"$1\" != --file ]; do shift; done\n  printf broken > \"$2\"\n  exit 0\nfi");
  test "a signalled tar cannot replace the previous archive" (fun () ->
    check_failure ~diagnostic:"signal" ~body:
      "if [ \"$1\" = --create ]; then kill -KILL $$; fi");
  test "a verification error keeps the previous archive" (fun () ->
    check_failure ~diagnostic:"verification denied" ~body:
      "if [ \"$1\" = --list ]; then echo 'verification denied' >&2; exit 2; fi");
  test "missing source leaves no new destination or temporary archive" (fun () ->
    with_fixture (fun directory working root _ target ->
      ignore (expect_failure (fun () -> save (working ^ "/absent") root target));
      require (not (Sys.file_exists target)) "failed first save created the destination";
      no_temporary_files directory));
  test "failed rename is reported and removes its temporary files" (fun () ->
    with_fixture (fun directory working root _ target ->
      ignore (expect_failure (fun () ->
        save ~on_staging_file:(fun _ -> Unix.mkdir target 0o700) working root target));
      require ((Unix.stat target).Unix.st_kind = Unix.S_DIR) "destination directory was altered";
      no_temporary_files directory));
  test "existing symlink updates its target and keeps the link" (fun () ->
    with_fixture (fun directory working root project target ->
      save working root target;
      let link = Filename.concat directory "linked.mar" in
      Unix.symlink (Filename.basename target) link;
      write (Filename.concat project "version") "linked update\n";
      save working root link;
      require ((Unix.lstat link).Unix.st_kind = Unix.S_LNK) "symbolic link was replaced";
      require (command real_tar ["-xOzf"; target; "--"; "-lab/version"] = "linked update\n")
        "symbolic-link target was not updated";
      no_temporary_files directory));
  test "sparse disks survive archive creation and extraction" (fun () ->
    with_fixture (fun directory working root project target ->
      let sparse = Filename.concat project "states/sparse.cow" in
      let fd = Unix.openfile sparse [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_CLOEXEC] 0o600 in
      Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
        ignore (Unix.lseek fd (16 * 1024 * 1024) Unix.SEEK_SET);
        ignore (Unix.write fd (Bytes.of_string "x") 0 1));
      save working root target;
      let extracted = Filename.concat directory "extracted" in
      Unix.mkdir extracted 0o700;
      ignore (command real_tar ["-xzf"; target; "-C"; extracted]);
      let disk = Filename.concat extracted "-lab/states/sparse.cow" in
      require ((Unix.stat disk).Unix.st_size = 16 * 1024 * 1024 + 1) "disk size changed";
      let blocks = int_of_string (String.trim (command "stat" ["-c"; "%b"; "--"; disk])) in
      require (blocks * 512 < 1024 * 1024) "disk lost its sparse representation"));
  Printf.printf "%d failure(s)\n%!" !failures;
  if !failures > 0 then exit 1
