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

(** Modules encapsulating a global state possibly shared by threads. *)

module type Type = sig type t val name:string option end

module Variable (Type:Type) = struct

  let failmsg = match Type.name with
  | None   -> Printf.sprintf "Stateful_modules: undefined content"
  | Some x -> Printf.sprintf "Stateful_modules: %s is undefined" x

  type t = Type.t
  let content = ref None
  let set (x:t) = (content := Some (lazy x))
  let unset () = (content := None)

  let get () = match !content with
   | Some x -> Some (Lazy.force x)
   | None   -> None

  let extract () = match !content with
   | Some x -> Lazy.force x
   | None   -> failwith failmsg

  let lazy_set lx = (content := Some lx)

end

module Thread_shared_variable (Type:Type) = struct
  include Variable (Type)
  module Mutex = MutexExtra.Recursive
  let mutex = Mutex.create ()
  (* we provide these new methods: *)
  let apply_with_mutex f x = Mutex.apply_with_mutex mutex f x
  let lock () = Mutex.lock mutex
  let unlock () = Mutex.unlock mutex
  (* and the thread-safe versions of accessors: *)
  let set x = apply_with_mutex set x
  let unset () = apply_with_mutex unset ()
  let get x = apply_with_mutex get x
  let extract x = apply_with_mutex extract x
  let lazy_set x = apply_with_mutex lazy_set x
end

module type Type_with_init =
  sig
    type t
    val name : string option
    val init : unit -> t
  end

(** The idea is basically that when a process forks, its child must reset the structure.
    There isn't sharing among processes, but only among threads of the same process. *)
module Process_private_thread_shared_variable (Type:Type_with_init) = struct
  include Variable (Type)
  module Mutex = MutexExtra.Recursive
  let mutex = Mutex.create ()
  (* we provide these new methods: *)
  let apply_with_mutex f x = Mutex.apply_with_mutex mutex f x
  let lock () = Mutex.lock mutex
  let unlock () = Mutex.unlock mutex

  (* First redefiniton: the process-safe versions of accessors: *)
  let owner = ref (Unix.getpid ()) (* Initialized at the module creation time *)
  let get () =
    let pid = Unix.getpid () in
    if pid = !owner then get ()
    else begin
      set (Type.init ());
      owner := pid;
      get ()
    end
  let extract () =
    let pid = Unix.getpid () in
    if pid = !owner then extract ()
    else begin
      set (Type.init ());
      owner := pid;
      extract ()
    end

  (* Second redefiniton: the thread-safe versions of accessors: *)
  let set x = apply_with_mutex set x
  let unset () = apply_with_mutex unset ()
  let get x = apply_with_mutex get x
  let extract x = apply_with_mutex extract x
  let lazy_set x = apply_with_mutex lazy_set x

  (* The variable is automatically initialized in a lazy way by the provided init() function: *)
  let () = lazy_set (lazy (Type.init ()))
end

