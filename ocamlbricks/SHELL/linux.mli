(* This file is part of ocamlbricks
   Copyright (C) 2013  Jean-Vincent Loddo
   Copyright (C) 2013  Université Paris 13

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

(** Specific functions for [Linux]. *)

type pid = int
type filename = string
type directory = string

(** The number of processors, read from /proc/cpuinfo: *)
val processor_no : int lazy_t

(** [Linux] processes related features. With respect to the other [Unix],
    we suppose here to be able to get information from [/proc/<PID>/] directories.*)
module Process : sig

 (** Simplified (and object-oriented) version of the main type [stat] full commented later: *)
 type easy_stat = < pid:int; comm:string; state:char; ppid:int; pgrp:int; session:int; tty_nr:int; tpgid:int; other_fields:string >


 (** Source: [http://man7.org/linux/man-pages/man5/proc.5.html].
     Status information about the process provided by [/proc/<PID>/stat].
     This is used by [ps(1)]. It is defined in [/usr/src/linux/fs/proc/array.c].
     The fields are listed with their proper [scanf(3)] format specifiers. *)
 type stat = {

   pid : int;          (** %d (1) The process ID. *)

   comm : string;      (** %s (2) The filename of the executable, in
                          parentheses.  This is visible whether or not the
                          executable is swapped out. *)

   state : char;       (** %c (3) One character from the string "RSDZTW" where R
                          is running, S is sleeping in an interruptible
                          wait, D is waiting in uninterruptible disk sleep,
                          Z is zombie, T is traced or stopped (on a signal),
                          and W is paging. *)

   ppid : int;         (** %d (4) The PID of the parent. *)

   pgrp : int;         (** %d (5) The process group ID of the process. *)

   session : int;      (** %d (6) The session ID of the process. *)

   tty_nr : int;       (** %d (7) The controlling terminal of the process.  (The
                          minor device number is contained in the
                          combination of bits 31 to 20 and 7 to 0; the major
                          device number is in bits 15 to 8.) *)

   tpgid : int;        (** %d (8) The ID of the foreground process group of the
                          controlling terminal of the process. *)

   flags : int64;      (** %lu (should be %u, or %lu before Linux 2.6.22)
                          (9) The kernel flags word of the process.  For bit
                          meanings, see the PF_* defines in the Linux kernel
                          source file include/linux/sched.h.  Details depend
                          on the kernel version. *)

   minflt : int64;     (** %lu (10) The number of minor faults the process has
                          made which have not required loading a memory page
                          from disk. *)

   cminflt : int64;    (** %lu (11) The number of minor faults that the process's
                          waited-for children have made. *)

   majflt : int64;     (** %lu (12) The number of major faults the process has
                          made which have required loading a memory page
                          from disk. *)

   cmajflt : int64;    (** %lu (13) The number of major faults that the process's
                          waited-for children have made. *)

   utime : int64;      (** %lu (14) Amount of time that this process has been
                          scheduled in user mode, measured in clock ticks
                          (divide by sysconf(_SC_CLK_TCK)).  This includes
                          guest time, guest_time (time spent running a
                          virtual CPU, see below), so that applications that
                          are not aware of the guest time field do not lose
                          that time from their calculations. *)

   stime : int64;      (** %lu (15) Amount of time that this process has been
                          scheduled in kernel mode, measured in clock ticks
                          (divide by sysconf(_SC_CLK_TCK)). *)

   cutime : int64;     (** %ld (16) Amount of time that this process's waited-for
                          children have been scheduled in user mode,
                          measured in clock ticks (divide by
                          sysconf(_SC_CLK_TCK)).  (See also times(2).)  This
                          includes guest time, cguest_time (time spent
                          running a virtual CPU, see below). *)

   cstime : int64;     (** %ld (17) Amount of time that this process's waited-for
                          children have been scheduled in kernel mode,
                          measured in clock ticks (divide by
                          sysconf(_SC_CLK_TCK)). *)

   priority : int64;   (** %ld (18) (Explanation for Linux 2.6) For processes
                          running a real-time scheduling policy (policy
                          below; see sched_setscheduler(2)), this is the
                          negated scheduling priority, minus one; that is, a
                          number in the range -2 to -100, corresponding to
                          real-time priorities 1 to 99.  For processes
                          running under a non-real-time scheduling policy,
                          this is the raw nice value (setpriority(2)) as
                          represented in the kernel.  The kernel stores nice
                          values as numbers in the range 0 (high) to 39
                          (low), corresponding to the user-visible nice
                          range of -20 to 19.
                          Before Linux 2.6, this was a scaled value based on
                          the scheduler weighting given to this process. *)

   nice : int64;       (** %ld (19) The nice value (see setpriority(2)), a value
                          in the range 19 (low priority) to -20 (high
                          priority). *)

   num_threads : int64;(** %ld (20) Number of threads in this process (since
                          Linux 2.6).  Before kernel 2.6, this field was
                          hard coded to 0 as a placeholder for an earlier
                          removed field. *)

   itrealvalue : int64;(** %ld (21) The time in jiffies before the next SIGALRM
                          is sent to the process due to an interval timer.
                          Since kernel 2.6.17, this field is no longer
                          maintained, and is hard coded as 0. *)

   starttime : int64;  (** %llu (was %lu before Linux 2.6)
                          (22) The time the process started after system
                          boot.  In kernels before Linux 2.6, this value was
                          expressed in jiffies.  Since Linux 2.6, the value
                          is expressed in clock ticks (divide by
                          sysconf(_SC_CLK_TCK)). *)

   vsize : int64;      (** %lu (23) Virtual memory size in bytes. *)

   rss : int64;        (** %ld (24) Resident Set Size: number of pages the
                          process has in real memory.  This is just the
                          pages which count toward text, data, or stack
                          space.  This does not include pages which have not
                          been demand-loaded in, or which are swapped out. *)

   rsslim : int64 option; (** %lu (25) Current soft limit in bytes on the rss of the
                          process; see the description of RLIMIT_RSS in
                          getrlimit(2). *)

   startcode : int64;  (** %lu (26) The address above which program text can run. *)

   endcode : int64;    (** %lu (27) The address below which program text can run. *)

   startstack : int64; (** %lu (28) The address of the start (i.e., bottom) of
                          the stack. *)

   kstkesp : int64;    (** %lu (29) The current value of ESP (stack pointer), as
                          found in the kernel stack page for the process. *)

   kstkeip : int64;    (** %lu (30) The current EIP (instruction pointer). *)

   signal : int64;     (** %lu (31) The bitmap of pending signals, displayed as a
                          decimal number.  Obsolete, because it does not
                          provide information on real-time signals; use
                          /proc/[pid]/status instead. *)

   blocked : int64;    (** %lu (32) The bitmap of blocked signals, displayed as a
                          decimal number.  Obsolete, because it does not
                          provide information on real-time signals; use
                          /proc/[pid]/status instead. *)

   sigignore : int64;  (** %lu (33) The bitmap of ignored signals, displayed as a
                          decimal number.  Obsolete, because it does not
                          provide information on real-time signals; use
                          /proc/[pid]/status instead. *)

   sigcatch : int64;   (** %lu (34) The bitmap of caught signals, displayed as a
                          decimal number.  Obsolete, because it does not
                          provide information on real-time signals; use
                          /proc/[pid]/status instead. *)

   wchan : int64 option;(** %lu (35) This is the "channel" in which the process is
                          waiting.  It is the address of a system call, and
                          can be looked up in a namelist if you need a
                          textual name.  (If you have an up-to-date
                          /etc/psdatabase, then try ps -l to see the WCHAN
                          field in action.) *)

   nswap : int64;      (** %lu (36) Number of pages swapped (not maintained). *)

   cnswap : int64;     (** %lu (37) Cumulative nswap for child processes (not
                          maintained). *)

   exit_signal : int;  (** %d (since Linux 2.1.22)
                          (38) Signal to be sent to parent when we die. *)

   processor : int;    (** %d (since Linux 2.2.8)
                          (39) CPU number last executed on. *)

   rt_priority : int64;(** %lu (should be %u since Linux 2.5.19; was %lu before Linux 2.6.22)
                          (40) Real-time scheduling priority, a number in
                          the range 1 to 99 for processes scheduled under a
                          real-time policy, or 0, for non-real-time
                          processes (see sched_setscheduler(2)). *)

   policy : int64;     (** %lu (should be %u since Linux 2.5.19; was %lu before Linux 2.6.22)
                          (41) Scheduling policy (see
                          sched_setscheduler(2)).  Decode using the SCHED_*
                          constants in linux/sched.h. *)

   delayacct_blkio_ticks : int64; (** %llu (since Linux 2.6.18)
                          (42) Aggregated block I/O delays, measured in
                          clock ticks (centiseconds). *)

   guest_time : int64; (** %lu (since Linux 2.6.24)
                          (43) Guest time of the process (time spent running
                          a virtual CPU for a guest operating system),
                          measured in clock ticks (divide by
                          sysconf(_SC_CLK_TCK)). *)

   cguest_time : int64;(** %ld (since Linux 2.6.24)
                          (44) Guest time of the process's children,
                          measured in clock ticks (divide by
                          sysconf(_SC_CLK_TCK)). *)
 } (* type stat *)


 (** Status information about the process. Implemented reading the file [/proc/<PID>/stat]. *)
 val stat : pid -> stat option

 (** Status information about the process (simplified object-oriented data structure).
     Implemented as [stat] reading the file [/proc/<PID>/stat]. *)
 val easy_stat : pid -> easy_stat option

 (** Get statistics of all currently running processes. *)
 val get_stats      : unit -> stat list

 (** Get statistics of all currently running processes (using the simplified structure). *)
 val get_easy_stats : unit -> easy_stat list

 (** {2 Descendants' PID}*)

 (** Get the children PID list of the caller (by default) or the provided [~pid]. *)
 val get_children : ?pid:int -> unit -> pid list

 (** Get the PID list of the descendants of the caller (by default) or the provided [~pid]. *)
 val get_descendants : ?pid:int -> unit -> pid list

 (** Get the PID hierarchy (forest) of the descendants of the caller (by default) or the provided [~pid]. *)
 val get_descendants_as_forest : ?pid:int -> unit -> pid Forest.t

 (** {2 Descendants' statistics}*)

 (** Get the statistics list of the descendants of the caller (by default) or the provided [~pid]. *)
 val get_descendant_stats : ?pid:int -> unit -> stat list

 (** Get the statistics list of the descendants of the caller (by default) or the provided [~pid] (using the simplified structure). *)
 val get_descendant_easy_stats : ?pid:int -> unit -> easy_stat list

 (** Get the statistics hierarchy (forest) of the descendants of the caller (by default) or the provided [~pid]. *)
 val get_descendant_stats_as_forest : ?pid:int -> unit -> stat Forest.t

 (** Get the statistics hierarchy (forest) of the descendants of the caller (by default) or the provided [~pid] (using the simplified structure). *)
 val get_descendant_easy_stats_as_forest : ?pid:int -> unit -> easy_stat Forest.t

 (** {2 Kill descendants}*)

 (** Kill the whole hierarchy (forest) of the descendants of the caller (by default) or the provided [~pid].
     By default the children are processed concurrently (and recursively) using futures.
     The sequence of signals send to each process (from leafs to root) are (by default) the following in this order:
     [\[Sys.sigterm; Sys.sigint; Sys.sigcont; Sys.sigkill]\].
     After each signal in the sequence, we leave to the fathers the time [wait_delay] to register the death of their children.
     The processes still alive are then recalculated and the next signal is sent to the survivors and so on.
     Optional parameters and their defaults:
{[?sequential:unit                       (* Process the children sequentially (instead of concurrently) *)
?wait_delay:float                      (* Default: 0.1 (seconds) *)
?wait_delay_node_increase_factor:float (* Increase factor for each retry at any node level. Default: 2. *)
?wait_delay_root_increase_factor:float (* Increase factor for each retry at root level. Default: 2. *)
?node_max_retries:int                  (* Default: 1   *)
?root_max_retries:int                  (* Default: 1   *)
?signal_sequence:int list              (* Default: [Sys.sigterm; Sys.sigint; Sys.sigcont; Sys.sigkill] *)
?pid:int                               (* Default: the pid of the caller *)
]} *)
 val kill_descendants :
   ?sequential:unit ->
   ?wait_delay:float ->
   ?wait_delay_node_increase_factor:float ->
   ?wait_delay_root_increase_factor:float ->
   ?node_max_retries:int ->
   ?root_max_retries:int ->
   ?signal_sequence:int list ->
   ?pid:int ->
   unit -> unit


(* Wait until a process die (child or unrelated).
   Implemented as passive waiting based on Inotify.
   The polling_interval is a guarantees of not to fall into unfortunate cases (race conditions)
   where the caller would be blocked indefinitely on a read operation. *)
 val watch_process : ?verbose:unit -> ?polling_interval:float (* 10. seconds *) -> pid -> unit

end (* Process *)

(* Returns the first ipv6 address corresponding to the interface in the file "/proc/net/if_inet6".
   Example:
     # get_ipv6_address "enp0s25" ;;
     - : string option = Some "fe80::5297:708f:75a3:7a99" *)
val get_ipv6_address_of   : string -> string option

(* Example:
     # get_ipv6_addresses_of "enp0s25" ;;
     - : string list = ["fe80::5297:708f:75a3:7a99"; "2a01:cb00:1d3:e400:78b5:5904:d7e3:7c7f"] *)
val get_ipv6_addresses_of : string -> string list

(* Help about Inotify:
   ---
     type selector = (* Type of event masks. *)
     | S_Access | S_Attrib | S_Close_write | S_Close_nowrite | S_Create | S_Delete | S_Delete_self | S_Modify | S_Move_self
     | S_Moved_from | S_Moved_to | S_Open | S_Dont_follow | S_Mask_add | S_Oneshot | S_Onlydir | S_Move | S_Close | S_All

     type event_kind = (* Type of observed events. *)
     | Access | Attrib | Close_write | Close_nowrite | Create | Delete | Delete_self | Modify | Move_self | Moved_from
     | Moved_to | Open | Ignored | Isdir | Q_overflow | Unmount
   ---
   Example:
   ---
     Linux.watch_directory ~verbose:() ~exit_door:".hidden_file" ~selector:[Inotify.S_Close_write; Inotify.S_Open]
         ~pathfilter:(Str.regexp "abc[0-7]$") ~callback:(fun _ -> prerr_endline "!!!CALLBACK!!!"; true) "/tmp/FOO" ;;

     [25890.0]: watch_directory: something happened in /tmp/FOO
       ∟ watch=1 cookie=0 events=OPEN "aaa"
       ∟ watch=1 cookie=0 events=CLOSE_WRITE "aaa"
     [25890.0]: watch_directory: something happened in /tmp/FOO
       ∟ watch=1 cookie=0 events=OPEN "abc"
       ∟ watch=1 cookie=0 events=CLOSE_WRITE "abc"
     [25890.0]: watch_directory: something happened in /tmp/FOO
       ∟ watch=1 cookie=0 events=OPEN "abc16"
       ∟ watch=1 cookie=0 events=CLOSE_WRITE "abc16"
     [25890.0]: watch_directory: something happened in /tmp/FOO    # date >/tmp/FOO/abc1
       ∟ watch=1 cookie=0 events=OPEN "abc1"
     !!!CALLBACK!!!
     [25890.0]: watch_directory: something happened in /tmp/FOO
       ∟ watch=1 cookie=0 events=CLOSE_WRITE "abc1"
     !!!CALLBACK!!!
     [25890.0]: watch_directory: something happened in /tmp/FOO    # touch /tmp/FOO/abc1
       ∟ watch=1 cookie=0 events=OPEN "abc1"
       ∟ watch=1 cookie=0 events=CLOSE_WRITE "abc1"
     !!!CALLBACK!!!
     !!!CALLBACK!!!
     [25890.0]: watch_directory: something happened in /tmp/FOO    # echo > /tmp/FOO/.hidden_file
       ∟ watch=1 cookie=0 events=OPEN ".hidden_file"
       ∟ watch=1 cookie=0 events=CLOSE_WRITE ".hidden_file"
     - : unit = ()
   ---
   Wait until something happen (by default a `close_write' event) in a directory.
   Implemented as passive waiting based on Inotify.
   This function never raises exceptions except Invalid_argument at starting if the provided directory
   does not exist. The function simply returns when the directory does not exist anymore or when the
   optional argument ?exit_door is set up and the provided filename is written.
*)
val watch_directory :
  ?verbose:unit ->
  ?ignore_unexisting_arg:unit ->         (* return immediately (instead of fail) when the directory doesn't exist. *)
  ?exit_door:filename ->                 (* exit if an event Inotify.S_Close_write occurs about this filename *)
  ?selector:Inotify.selector list ->     (* [Inotify.S_Close_write] *)
  ?pathfilter:Str.regexp ->              (* select only events which involve a path matching the regular expression *)
  callback:(Inotify.event -> bool) ->    (* treat the event then say if we have to continue in watching the directory *)
  directory -> unit
