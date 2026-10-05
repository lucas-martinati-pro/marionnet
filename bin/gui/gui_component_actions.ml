(* GPL-2.0-or-later. The palette and drawing share their actual callbacks. *)
module Log = Marionnet_log

type action = { label : string; stock : GtkStock.id; enabled : unit -> bool;
                run : unit -> unit }
type kind = [ `Node | `Cable ]
let providers : (kind -> string -> action list) list ref = ref []
let register provider = providers := !providers @ [provider]
let actions kind name = List.concat_map (fun provider -> provider kind name) !providers
let make ~label ~stock ~names ~callback name =
  let enabled () = List.mem name (names ()) in
  { label; stock; enabled; run = (fun () -> if enabled () then callback name ()) }
