(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2020  Jean-Vincent Loddo
   Copyright (C) 2020  Université Sorbonne Paris Nord

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


(* USAGE:

$ _build/tests/test_future.native
ocamlopt --version  : 4.04.2
uname -s -v -p      : Linux #44-Ubuntu SMP Wed Jan 15 02:03:45 UTC 2020 x86_64
processors          : 15
meminfo             : 131969248 kB

NOTE: backtrace_status = false

Test #1  DELAYED LIGHT COMPUTATION     #list: 15  delay of tool mapped over list: 0.0
  ---
  ∟ List.map                  =>  result: e7ea156b141b3864f25b2b0a9796041a  time: 0.000084
  ∟ Future.List.map           =>  result: e7ea156b141b3864f25b2b0a9796041a  time: 0.002361
  ∟ Future.List.map ~fork     =>  result: e7ea156b141b3864f25b2b0a9796041a  time: 0.011724

Test #2  DELAYED LIGHT COMPUTATION     #list: 15  delay of tool mapped over list: 0.1
  ---
  ∟ List.map                  =>  result: e7ea156b141b3864f25b2b0a9796041a  time: 1.502298
  ∟ Future.List.map           =>  result: e7ea156b141b3864f25b2b0a9796041a  time: 0.101837
  ∟ Future.List.map ~fork     =>  result: e7ea156b141b3864f25b2b0a9796041a  time: 0.111498

Test #3  DELAYED LIGHT COMPUTATION     #list: 15  delay of tool mapped over list: 0.2
  ---
  ∟ List.map                  =>  result: e7ea156b141b3864f25b2b0a9796041a  time: 3.003949
  ∟ Future.List.map           =>  result: e7ea156b141b3864f25b2b0a9796041a  time: 0.202238
  ∟ Future.List.map ~fork     =>  result: e7ea156b141b3864f25b2b0a9796041a  time: 0.212690

Test #4  HEAVY COMPUTATION (size 1000) #list: 30  delay of tool mapped over list: 0.0
  ---
  ∟ List.map                  =>  result: b183c427d257a44fdfc401258eaf4efd  time: 0.101797
  ∟ Future.List.map           =>  result: b183c427d257a44fdfc401258eaf4efd  time: 0.164677
  ∟ Future.List.map ~fork     =>  result: b183c427d257a44fdfc401258eaf4efd  time: 0.024069

Test #5  HEAVY COMPUTATION (size 2000) #list: 30  delay of tool mapped over list: 0.0
  ---
  ∟ List.map                  =>  result: 96777b120be6132f82a40e9837454679  time: 0.206023
  ∟ Future.List.map           =>  result: 96777b120be6132f82a40e9837454679  time: 0.340274
  ∟ Future.List.map ~fork     =>  result: 96777b120be6132f82a40e9837454679  time: 0.033715

Test #6  HEAVY COMPUTATION (size 3000) #list: 30  delay of tool mapped over list: 0.0
  ---
  ∟ List.map                  =>  result: 24af6c88eea8bec240e75c4ac424fd11  time: 0.325505
  ∟ Future.List.map           =>  result: 24af6c88eea8bec240e75c4ac424fd11  time: 0.468766
  ∟ Future.List.map ~fork     =>  result: 24af6c88eea8bec240e75c4ac424fd11  time: 0.043071

test_future [28692]: exiting
*)

let pr fmt = Printf.kfprintf flush stderr fmt ;;

let _ = pr "%-20s: " "ocamlopt --version"; Sys.command "ocamlopt --version";;
let _ = pr "%-20s: " "uname -s -v -p ";    Sys.command "uname -s -v -p ";;
let _ = pr "%-20s: " "processors"; Sys.command "grep processor /proc/cpuinfo | tail -n 1 | grep -o '[0-9][1-9]*'";;
let _ = pr "%-20s: " "meminfo";    Sys.command "grep MemTotal  /proc/meminfo | grep -o '[0-9].*'";;

let pid = Unix.getpid () ;;

(* To show that this handler will be ignored by forks: *)
let () = at_exit (fun () -> pr "test_future [%d]: exiting\n" pid) ;;

let md5sum x = Digest.to_hex (Digest.string (Marshal.to_string x [])) ;;

let a_tool1 delay x =
  (let () = Thread.delay (delay) in exp (sqrt ((sin x) *. (log x))))
;;

let () = pr "\nNOTE: backtrace_status=%b\n\n" (Printexc.backtrace_status ()) ;;

let a_tool2 ?(verbose=false) ?(working_array_size=1000) (* 10000 => DEADLOCK *) =
  (* Precalculated in order to have exactly the same job to do for all threads or forks: *)
  let xs = Array.init (working_array_size) (fun i -> Random.int 42000) in
  (* --- *)
  fun delay x ->
    let () = if verbose then pr "a_tool2 (pid=%d): --- BEGIN\n" (Unix.getpid ()) in
    let () = Thread.delay (delay) in
    let x = int_of_float (x**4. *. 12345.) in
    (* Allocation is not the problem, we have the same behaviour with "let result = xs in": *)
    let result = (Array.append [|x|] xs) in
    (* --- *)
    let compare0 x y = compare x y in
    let compare1 x y = compare y x in
    let () = if verbose then pr "a_tool2 (pid=%d): AFTER ALLOCATION, BEFORE LOOP\n" (Unix.getpid ()) in
    let () =
      for i = 1 to 10 (* 100 => DEADLOCK *) do
        Array.sort (if i mod 2 = 0 then compare0 else compare1) result
      done
    in
    let () = if verbose then pr "a_tool2 (pid=%d): END ---\n" (Unix.getpid ()) in
    result
;;

let test (test_nb) (title) (a_tool) (a_list) (delay) =
  (* --- *)
  let () =
    pr "Test #%d  %-29s #list: %d  delay of tool mapped over list: %3.1f\n  ---\n"
      (test_nb) (title) (List.length a_list) (delay)
  in
  (* --- *)
  let a_tool = a_tool (delay) in
  (* --- *)
  let f0 () =         List.map          (a_tool) (a_list)                 in
  let f1 () =  Future.List.map          (a_tool) (a_list) |> Future.touch in
  let f2 () =  Future.List.map ~fork:() (a_tool) (a_list) |> Future.touch in
  (* --- *)
  let y0, t0 = UnixExtra.perf f0 () in
  let () = pr "  ∟ %-25s =>  result: %s  time: %f\n" "List.map" (md5sum y0) t0 in
  (* --- *)
  let y1, t1 = UnixExtra.perf f1 () in
  let () = pr "  ∟ %-25s =>  result: %s  time: %f\n" "Future.List.map" (md5sum y1) t1 in
  (* --- *)
  let y2, t2 = UnixExtra.perf f2 () in
  let () = pr "  ∟ %-25s =>  result: %s  time: %f\n\n" "Future.List.map ~fork" (md5sum y2) t2 in
  (* --- *)
  ()
;;

(* A list of 15 inputs: *)
let a_list = [3.14; 1.27; 1.12; 2.14; 2.09; 2.11; 2.09; 2.18; 1.65; 1.70; 1.16; 1.23; 1.45; 1.56; 1.75 ];;

(* --- *)

let title = "DELAYED LIGHT COMPUTATION" ;;
test 1 (title) (a_tool1) (a_list) (0.);;
test 2 (title) (a_tool1) (a_list) (0.1);;
test 3 (title) (a_tool1) (a_list) (0.2);;

(* --- *)

let title = "HEAVY COMPUTATION" ;;
test 4 (title^" (size 1000)")  (a_tool2 ~verbose:false ~working_array_size:1000)  (a_list@a_list) (0.);;
test 5 (title^" (size 2000)")  (a_tool2 ~verbose:false ~working_array_size:2000)  (a_list@a_list) (0.);;
test 6 (title^" (size 3000)")  (a_tool2 ~verbose:false ~working_array_size:3000)  (a_list@a_list) (0.);;

(* --- *)

(* BUG:
    Uncomment the following line to observe a reproducible bug (of future.ml? of OCaml? of Linux?)
    which occurs when the size of the working array is sufficiently large: *)

(* (* --------------------------------------------------------------------------------------------------- *) *)
(* test 7 (title^" (size 10000)") (a_tool2 ~verbose:true  ~working_array_size:10000) (a_list@a_list) (0.);; *)
(* (* --------------------------------------------------------------------------------------------------- *) *)

(* ... then compile and launch this way:
---
$ make native-programs
$ _build/tests/test.native | tee /tmp/bug.log
CTRL-C
$ grep BEGIN /tmp/bug.log | wc -l
90
$ grep BEFORE /tmp/bug.log | wc -l
90
$ grep END /tmp/bug.log | wc -l
60
---
CONCLUSION:

  The 30 processes launched by (Future.List.map ~fork) seems anymore not able to sort the array
  (in the for loop). The same strange behaviour may be observed increasing the number of cycles
  (at line 85), for instance with 100 instead of 10 (with working_array_size=1000), despite the
  fact there's no data allocation executed in the loop body.
  This remark seems to exclude a bug related to this discussion:
      https://discuss.ocaml.org/t/fork-fails-with-cannot-allocate-memory-despite-lots-of-memory/1280/11
---
QUESTION:

  Is it another safeguard against fork bombs?
*)
