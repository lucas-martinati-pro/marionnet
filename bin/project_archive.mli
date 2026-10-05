(** Transactional writing of the existing .mar (sparse tar.gz) container, without Gtk+.
    Creation, verification and file synchronisation happen beside the destination. The
    destination is replaced by rename only after these steps succeed, then its directory
    is synchronised. An error before rename leaves the previous archive untouched; an
    error synchronising the directory after rename is reported, although the replacement
    has already happened. Handled failures remove the temporary files.

    Existing file permissions and symbolic-link destinations are preserved. New archives
    are private (0600). A save needs write access to the destination directory.
    [on_staging_file] lets the progress indicator observe the archive being written.
    No shell interprets filenames or exclusion arguments. *)
val save :
  ?on_staging_file:(string -> unit) ->
  filename:string -> working_directory:string -> root_basename:string ->
  excluded_paths:string list -> unit -> unit
