(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008  Luca Saiu
   Copyright (C) 2010  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2010  Université Paris 13

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

(* A general-purpose BLOCKING queue (a mutex plus a condition variable), used as the mailbox
   of an actor: one thread enqueues, another one waits in `dequeue'.
   ---
   Its only client is `task_runner.ml' (which `open's this module), for two distinct purposes:
   the queue of pending tasks, and a "dummy" unit queue used as a rendez-vous — a thread
   blocks on `dequeue' until the worker enqueues, which is how `wait_for_all_currently_scheduled_tasks'
   is implemented.
   ---
   Not to be confused with `Ocamlbricks.Channel' (Milner channels, used by `GMain_actor') nor
   with `Ocamlbricks.Future'. This one is deliberately minimal, and has NO termination
   protocol: a thread blocked in `dequeue' stays blocked until something is enqueued. *)

(** An unbounded FIFO of ['a], safe for concurrent use. *)
class ['a] queue : object

  (** Append at the tail and wake up one waiting consumer. Never blocks. *)
  method enqueue : 'a -> unit

  (** Insert at the HEAD instead of the tail, making the queue a deque. Meant for urgent
      messages that must overtake the pending ones — typically a termination request. *)
  method prepend : 'a -> unit

  (** Remove and return the head element, BLOCKING the calling thread while the queue is
      empty. Must therefore never be called from the GTK main thread. *)
  method dequeue : 'a

end
