(* This file is part of ocamlbricks
   Copyright (C) 2010 Jean-Vincent Loddo

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>. *)


(** Support for managing the component garbage. *)
class virtual destroy_methods () =
 let mrproper = new Thunk.lifo_unit_protected_container () in
 object

  (* Accessor to the inner mrproper object: *)
  method mrproper = mrproper

  (* Automatically protected and considered as one-shot (linear) thunk: *)
  method add_destroy_callback f = ignore (mrproper#register_lazy f)

  (* Initially private, but may became public: *)
  method (*private*) destroy = mrproper#apply ()

 end (* destroy_methods *)


module Gc_sync = struct

let finalizer (f : int -> unit) ~oid ~finalizer_hook =
  let g = fun _ -> f oid in
  Gc.finalise g finalizer_hook

let notify =
  (Printf.kfprintf flush stderr "Gc_sync: instance %d collected.\n")

class ['a] t ?destroy (v:'a) =
object (self)
  val content = ref v (* in the heap *)
  method get = !content

  (** For each set a full major collection is called.
      In this way the unlinked value may be immediately collected
      (if unused elsewhere) raising its finalization. *)
  method set x =
    content := x;
    Gc.full_major ();

  (* The container itself have a finalizer: *)
  initializer
    let destroy = match destroy with
    | None   -> notify
    | Some f -> f
    in
    finalizer destroy ~oid:(Oo.id self) ~finalizer_hook:content
end

let ref = new t;;

(** {b Example}:
{[let x = ref ([ref 2; ref 1; ref 0]) ;;
x#set [] ;;
Gc_sync: instance 6 collected!!!
Gc_sync: instance 5 collected!!!
Gc_sync: instance 4 collected!!!
  : unit = ()
]}
*)
end
