(* GPL-2.0-or-later. Backups live in the project's tmp/ and are never archived. *)
val capture : string -> string
val restore : root:string -> string -> unit
val discard : string -> unit
