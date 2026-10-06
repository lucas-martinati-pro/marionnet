(** Reservations prevent concurrent tasks on the same resource, including before a
    worker begins. Ownership permits synchronous nested calls by that worker. *)
type t
type ticket
val create : unit -> t
val reserve : t -> key:string -> label:string -> ticket option
val enter : t -> ticket -> unit
val owned : t -> string -> bool
(** Releasing an old ticket cannot remove a later reservation for the same key. *)
val release : t -> ticket -> unit
val active : t -> (string * string) list
