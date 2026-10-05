(* GPL-2.0-or-later. Coordinates are PNG pixels, before viewport translation. *)
type target = Node of int | Cable of int
type shape = Rect of float * float * float * float
  | Circle of float * float * float | Poly of (float * float) array
type area = { target : target; shape : shape }
val parse : string -> area list
val hit : area list -> x:float -> y:float -> target option
