(* GPL-2.0-or-later. Graphviz rendering, independent of GTK. *)
type request = {
  dot_file : string;
  png_file : string;
  content : string;
  splines : bool;
}

type rendered

(** Render into private files next to the destination. Existing drawings are
    untouched on failure. The caller supplies its process supervisor and decides
    whether the request is still current. *)
val render :
  spawn:(string -> string array -> Unix.file_descr -> Unix.file_descr -> Unix.file_descr -> int) ->
  request -> (rendered, string) result
val map_file : request -> string
val publish : rendered -> unit
val discard : rendered -> unit

(** Wall time spent launching and waiting for Graphviz, in milliseconds. *)
val graphviz_ms : rendered -> float

(** Read the private geometry before publication or discard. *)
val hit_map : rendered -> string
